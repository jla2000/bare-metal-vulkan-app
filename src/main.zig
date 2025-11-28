const std = @import("std");
const debug = @import("debug.zig");
const c = @import("c_imports.zig").c;

const assert = std.debug.assert;

var gpa = std.heap.DebugAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return error.GlfwInit;
    }
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    const window = c.glfwCreateWindow(800, 600, "Vulkan window", null, null);
    defer c.glfwDestroyWindow(window);

    const instance = try create_instance();
    defer c.vkDestroyInstance(instance, null);

    var debug_messenger = debug.create_debug_messenger(instance);
    defer debug.destroy_debug_messenger(instance, &debug_messenger);

    var surface: c.VkSurfaceKHR = undefined;
    assert(c.glfwCreateWindowSurface(instance, window, null, &surface) == c.VK_SUCCESS);
    defer c.vkDestroySurfaceKHR(instance, surface, null);

    const physical_device, const queue_indices = try find_physical_device(instance, surface);
    const device = try create_device(physical_device, queue_indices);
    defer c.vkDestroyDevice(device, null);

    var graphics_queue: c.VkQueue = undefined;
    var compute_queue: c.VkQueue = undefined;
    var present_queue: c.VkQueue = undefined;

    c.vkGetDeviceQueue(device, queue_indices.graphics_queue_idx, 0, &graphics_queue);
    c.vkGetDeviceQueue(device, queue_indices.compute_queue_idx, 0, &compute_queue);
    c.vkGetDeviceQueue(device, queue_indices.present_queue_idx, 0, &present_queue);

    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    assert(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities) == c.VK_SUCCESS);

    const surface_format = choose_surface_format(physical_device, surface);
    const present_mode = choose_present_mode(physical_device, surface);

    _ = surface_format;
    _ = present_mode;

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        c.glfwSwapBuffers(window);
    }
}

fn choose_surface_format(physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) c.VkSurfaceFormatKHR {
    var num_surface_formats: u32 = 0;
    assert(c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &num_surface_formats, null) == c.VK_SUCCESS);

    const surface_formats = allocator.alloc(c.VkSurfaceFormatKHR, num_surface_formats) catch unreachable;
    defer allocator.free(surface_formats);
    assert(c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &num_surface_formats, surface_formats.ptr) == c.VK_SUCCESS);

    for (surface_formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }

    return surface_formats[0];
}

fn choose_present_mode(physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) c.VkPresentModeKHR {
    var num_present_modes: u32 = 0;
    assert(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, null) == c.VK_SUCCESS);

    const present_modes = allocator.alloc(c.VkPresentModeKHR, num_present_modes) catch unreachable;
    defer allocator.free(present_modes);
    assert(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, present_modes.ptr) == c.VK_SUCCESS);

    for (present_modes) |mode| {
        if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return mode;
        }
    }

    // fifo should be always supported.
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn create_instance() !c.VkInstance {
    var num_glfw_extensions: u32 = 0;
    var glfw_extensions: [*c][*c]const u8 = null;
    glfw_extensions = c.glfwGetRequiredInstanceExtensions(&num_glfw_extensions);

    var extensions = try allocator.alloc([*c]const u8, num_glfw_extensions + 1);
    defer allocator.free(extensions);

    @memcpy(extensions, glfw_extensions);
    extensions[extensions.len - 1] = c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME;

    const enabled_layers = [_][*]const u8{"VK_LAYER_KHRONOS_validation"};

    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "zig-raytracer",
        .applicationVersion = c.VK_MAKE_VERSION(0, 0, 1),
        .pEngineName = "No engine",
        .engineVersion = c.VK_MAKE_VERSION(0, 0, 1),
        .apiVersion = c.VK_API_VERSION_1_4,
    };

    const instance_create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledExtensionNames = extensions.ptr,
        .enabledLayerCount = enabled_layers.len,
        .ppEnabledLayerNames = &enabled_layers,
        .pNext = @ptrCast(&debug.DEBUG_MESSENGER_CREATE_INFO),
    };

    var instance: c.VkInstance = undefined;
    assert(c.vkCreateInstance(&instance_create_info, null, &instance) == c.VK_SUCCESS);

    return instance;
}

fn rate_physical_device(physical_device: c.VkPhysicalDevice) !u32 {
    var properties: c.VkPhysicalDeviceProperties = undefined;
    var features: c.VkPhysicalDeviceFeatures = undefined;

    c.vkGetPhysicalDeviceProperties(physical_device, &properties);
    c.vkGetPhysicalDeviceFeatures(physical_device, &features);

    const score: u32 = switch (properties.deviceType) {
        c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => 3,
        c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => 2,
        c.VK_PHYSICAL_DEVICE_TYPE_CPU => 1,
        else => return 0,
    };

    std.log.info("Found suitable physical device: {s}", .{properties.deviceName});

    return score;
}

fn find_physical_device(instance: c.VkInstance, surface: c.VkSurfaceKHR) !struct { c.VkPhysicalDevice, QueueIndices } {
    var num_devices: u32 = 0;
    assert(c.vkEnumeratePhysicalDevices(instance, &num_devices, null) == c.VK_SUCCESS);
    assert(num_devices > 0);

    const physical_devices = try allocator.alloc(c.VkPhysicalDevice, num_devices);
    defer allocator.free(physical_devices);

    assert(c.vkEnumeratePhysicalDevices(instance, &num_devices, physical_devices.ptr) == c.VK_SUCCESS);

    var best_score: u32 = 0;
    var best_device: c.VkPhysicalDevice = undefined;
    var best_queue_indices: QueueIndices = undefined;

    for (physical_devices) |physical_device| {
        const queue_indices = try find_queue_indices(physical_device, surface) orelse continue;
        const score = try rate_physical_device(physical_device);

        if (score >= best_score) {
            best_score = score;
            best_device = physical_device;
            best_queue_indices = queue_indices;
        }
    }

    assert(best_score > 0);
    return .{ best_device, best_queue_indices };
}

fn create_device(physical_device: c.VkPhysicalDevice, queue_indices: QueueIndices) !c.VkDevice {
    const device_features = c.VkPhysicalDeviceFeatures{};
    const device_extensions = [_][*]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

    var unique_queue_indices = std.hash_map.AutoHashMap(u32, void).init(allocator);
    defer unique_queue_indices.deinit();

    try unique_queue_indices.put(queue_indices.compute_queue_idx, void{});
    try unique_queue_indices.put(queue_indices.graphics_queue_idx, void{});
    try unique_queue_indices.put(queue_indices.present_queue_idx, void{});

    const queue_priority: f32 = 1.0;
    var queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo){};
    defer queue_create_infos.deinit(allocator);

    var it = unique_queue_indices.keyIterator();
    while (it.next()) |queue_idx| {
        try queue_create_infos.append(allocator, c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = queue_idx.*,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        });
    }

    const device_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = queue_create_infos.items.ptr,
        .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
        .pEnabledFeatures = &device_features,
        .ppEnabledExtensionNames = &device_extensions,
        .enabledExtensionCount = device_extensions.len,
    };

    var device: c.VkDevice = undefined;
    assert(c.vkCreateDevice(physical_device, &device_create_info, null, &device) == c.VK_SUCCESS);

    return device;
}

const QueueIndices = struct {
    graphics_queue_idx: u32,
    compute_queue_idx: u32,
    present_queue_idx: u32,
};

fn find_queue_indices(physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !?QueueIndices {
    var num_queue_families: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &num_queue_families, null);

    const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, num_queue_families);
    defer allocator.free(queue_families);

    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &num_queue_families, queue_families.ptr);

    var compute_queue_idx: ?u32 = null;
    var graphics_queue_idx: ?u32 = null;
    var present_queue_idx: ?u32 = null;

    for (0..num_queue_families) |idx| {
        const queue_family = queue_families[idx];
        const queue_family_idx: u32 = @intCast(idx);

        var present_support: c.VkBool32 = 0;
        assert(c.vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, queue_family_idx, surface, &present_support) == c.VK_SUCCESS);

        if (present_support == 1) {
            present_queue_idx = queue_family_idx;
        }
        if (queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0) {
            compute_queue_idx = queue_family_idx;
        }
        if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            graphics_queue_idx = queue_family_idx;
        }
    }

    const compute = compute_queue_idx orelse return null;
    const graphics = graphics_queue_idx orelse return null;
    const present = present_queue_idx orelse return null;

    return QueueIndices{
        .compute_queue_idx = compute,
        .graphics_queue_idx = graphics,
        .present_queue_idx = present,
    };
}

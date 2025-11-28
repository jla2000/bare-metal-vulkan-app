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

    const physical_device = try find_physical_device(instance);
    const queue_family_index = (try find_queue_family(physical_device)).?;
    const device = try create_device(physical_device, queue_family_index);
    defer c.vkDestroyDevice(device, null);

    var compute_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device, queue_family_index, 0, &compute_queue);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        c.glfwSwapBuffers(window);
    }
}

fn create_instance() !c.VkInstance {
    var num_glfw_extensions: u32 = 0;
    var glfw_extensions: [*c][*c]const u8 = null;
    glfw_extensions = c.glfwGetRequiredInstanceExtensions(&num_glfw_extensions);

    var extensions = try allocator.alloc([*c]const u8, num_glfw_extensions + 1);
    defer allocator.free(extensions);

    @memcpy(extensions, glfw_extensions);
    extensions[extensions.len - 1] = c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME;

    const enabled_layers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};

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
    if (try find_queue_family(physical_device) == null) {
        return 0;
    }

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

fn find_physical_device(instance: c.VkInstance) !c.VkPhysicalDevice {
    var num_devices: u32 = 0;
    assert(c.vkEnumeratePhysicalDevices(instance, &num_devices, null) == c.VK_SUCCESS);
    assert(num_devices > 0);

    const physical_devices = try allocator.alloc(c.VkPhysicalDevice, num_devices);
    defer allocator.free(physical_devices);

    assert(c.vkEnumeratePhysicalDevices(instance, &num_devices, physical_devices.ptr) == c.VK_SUCCESS);

    var best_device: c.VkPhysicalDevice = undefined;
    var best_device_score: u32 = 0;

    for (physical_devices) |physical_device| {
        const score = try rate_physical_device(physical_device);

        if (score >= best_device_score) {
            best_device_score = score;
            best_device = physical_device;
        }
    }

    assert(best_device_score > 0);
    return best_device;
}

fn create_device(physical_device: c.VkPhysicalDevice, queue_family_index: u32) !c.VkDevice {
    const device_features = c.VkPhysicalDeviceFeatures{};

    const queue_priority: f32 = 1.0;
    const queue_create_info = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family_index,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };

    const device_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_info,
        .queueCreateInfoCount = 1,
        .pEnabledFeatures = &device_features,
    };

    var device: c.VkDevice = undefined;
    assert(c.vkCreateDevice(physical_device, &device_create_info, null, &device) == c.VK_SUCCESS);

    return device;
}

fn find_queue_family(physical_device: c.VkPhysicalDevice) !?u32 {
    var num_queue_families: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &num_queue_families, null);

    const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, num_queue_families);
    defer allocator.free(queue_families);

    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &num_queue_families, queue_families.ptr);

    for (0..num_queue_families) |idx| {
        const queue_family = queue_families[idx];

        if (queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0) {
            return @intCast(idx);
        }
    }

    return null;
}

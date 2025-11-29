const std = @import("std");
const debug = @import("debug.zig");
const common = @import("common.zig");
const c = common.c;

const allocator = common.allocator;
const assert = std.debug.assert;

pub fn main() !void {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return error.GlfwInit;
    }
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    const window = c.glfwCreateWindow(800, 600, "Vulkan window", null, null);
    defer c.glfwDestroyWindow(window);

    const instance = create_instance();
    defer c.vkDestroyInstance(instance, null);

    var debug_messenger = debug.create_debug_messenger(instance);
    defer debug.destroy_debug_messenger(instance, &debug_messenger);

    var surface: c.VkSurfaceKHR = undefined;
    assert(c.glfwCreateWindowSurface(instance, window, null, &surface) == c.VK_SUCCESS);
    defer c.vkDestroySurfaceKHR(instance, surface, null);

    const physical_device = find_physical_device(instance, surface);
    std.log.info("Using physical device: {s}", .{physical_device.properties.deviceName});

    const device = create_device(physical_device.handle, physical_device.queue_indices);
    defer c.vkDestroyDevice(device, null);

    var graphics_queue: c.VkQueue = undefined;
    var compute_queue: c.VkQueue = undefined;
    var present_queue: c.VkQueue = undefined;

    c.vkGetDeviceQueue(device, physical_device.queue_indices.graphics_family, 0, &graphics_queue);
    c.vkGetDeviceQueue(device, physical_device.queue_indices.compute_family, 0, &compute_queue);
    c.vkGetDeviceQueue(device, physical_device.queue_indices.present_family, 0, &present_queue);

    const swapchain, const images, const format = create_swapchain(
        window,
        physical_device.handle,
        device,
        surface,
        physical_device.queue_indices,
    );
    defer c.vkDestroySwapchainKHR(device, swapchain, null);
    defer allocator.free(images);

    const image_views = create_image_views(device, images, format);
    defer {
        for (image_views) |image_view| {
            c.vkDestroyImageView(device, image_view, null);
        }
        allocator.free(image_views);
    }

    const shader_module = create_shader_module(device, &c.SPIRV_SHADER_CODE);
    defer c.vkDestroyShaderModule(device, shader_module, null);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        c.glfwSwapBuffers(window);
        break;
    }
}

fn create_shader_module(device: c.VkDevice, code: []const u32) c.VkShaderModule {
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len * @sizeOf(u32),
        .pCode = code.ptr,
    };

    var shader_module: c.VkShaderModule = undefined;
    assert(c.vkCreateShaderModule(device, &create_info, null, &shader_module) == c.VK_SUCCESS);

    return shader_module;
}

fn create_image_views(device: c.VkDevice, images: []c.VkImage, format: c.VkFormat) []c.VkImageView {
    const image_views = allocator.alloc(c.VkImageView, images.len) catch unreachable;

    for (0..images.len) |image_idx| {
        const image_view_create_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = images[image_idx],
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        assert(c.vkCreateImageView(device, &image_view_create_info, null, &image_views[image_idx]) == c.VK_SUCCESS);
    }

    return image_views;
}

fn create_swapchain(
    window: ?*c.GLFWwindow,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    surface: c.VkSurfaceKHR,
    queue_indices: QueueIndices,
) struct { c.VkSwapchainKHR, []c.VkImage, c.VkFormat } {
    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    assert(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities) == c.VK_SUCCESS);

    const extent = choose_swapchain_extent(window, capabilities);
    const surface_format = choose_surface_format(physical_device, surface);
    const present_mode = choose_swapchain_present_mode(physical_device, surface);

    var num_images = capabilities.minImageCount + 1;
    var swapchain_create_info = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = num_images,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    };

    if (queue_indices.graphics_family != queue_indices.present_family) {
        swapchain_create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        swapchain_create_info.queueFamilyIndexCount = 2;
        swapchain_create_info.pQueueFamilyIndices = &[_]u32{ queue_indices.graphics_family, queue_indices.compute_family };
    }

    var swapchain: c.VkSwapchainKHR = undefined;
    assert(c.vkCreateSwapchainKHR(device, &swapchain_create_info, null, &swapchain) == c.VK_SUCCESS);

    assert(c.vkGetSwapchainImagesKHR(device, swapchain, &num_images, null) == c.VK_SUCCESS);
    const images = allocator.alloc(c.VkImage, num_images) catch unreachable;
    assert(c.vkGetSwapchainImagesKHR(device, swapchain, &num_images, images.ptr) == c.VK_SUCCESS);

    return .{ swapchain, images, surface_format.format };
}

fn choose_swapchain_extent(window: ?*c.GLFWwindow, capabilities: c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    }

    var width: i32 = 0;
    var height: i32 = 0;
    c.glfwGetFramebufferSize(window, &width, &height);

    return c.VkExtent2D{
        .width = std.math.clamp(@as(u32, @intCast(width)), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
        .height = std.math.clamp(@as(u32, @intCast(height)), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };
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

fn choose_swapchain_present_mode(physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) c.VkPresentModeKHR {
    var num_present_modes: u32 = 0;
    assert(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, null) == c.VK_SUCCESS);

    const present_modes = allocator.alloc(c.VkPresentModeKHR, num_present_modes) catch unreachable;
    defer allocator.free(present_modes);
    assert(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, present_modes.ptr) == c.VK_SUCCESS);

    // for (present_modes) |mode| {
    //     if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
    //         return mode;
    //     }
    // }

    // fifo should be always supported.
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn create_instance() c.VkInstance {
    var num_glfw_extensions: u32 = 0;
    var glfw_extensions: [*c][*c]const u8 = null;
    glfw_extensions = c.glfwGetRequiredInstanceExtensions(&num_glfw_extensions);

    var extensions = allocator.alloc([*c]const u8, num_glfw_extensions + 1) catch unreachable;
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

const PhysicalDeviceInfo = struct {
    handle: c.VkPhysicalDevice,
    features: c.VkPhysicalDeviceFeatures,
    properties: c.VkPhysicalDeviceProperties,
    queue_indices: QueueIndices,
};

fn find_physical_device(instance: c.VkInstance, surface: c.VkSurfaceKHR) PhysicalDeviceInfo {
    var num_devices: u32 = 0;
    assert(c.vkEnumeratePhysicalDevices(instance, &num_devices, null) == c.VK_SUCCESS);
    assert(num_devices > 0);

    const physical_devices = allocator.alloc(c.VkPhysicalDevice, num_devices) catch unreachable;
    defer allocator.free(physical_devices);
    assert(c.vkEnumeratePhysicalDevices(instance, &num_devices, physical_devices.ptr) == c.VK_SUCCESS);

    var suitable_devices = std.ArrayList(PhysicalDeviceInfo){};
    defer suitable_devices.deinit(allocator);

    for (physical_devices) |physical_device| {
        const queue_indices = find_queue_indices(physical_device, surface) orelse continue;

        var properties: c.VkPhysicalDeviceProperties = undefined;
        var features: c.VkPhysicalDeviceFeatures = undefined;
        c.vkGetPhysicalDeviceProperties(physical_device, &properties);
        c.vkGetPhysicalDeviceFeatures(physical_device, &features);

        suitable_devices.append(allocator, PhysicalDeviceInfo{
            .handle = physical_device,
            .features = features,
            .properties = properties,
            .queue_indices = queue_indices,
        }) catch unreachable;

        std.log.debug("Found suitable device: {s}", .{properties.deviceName});
    }

    if (suitable_devices.items.len == 0) {
        @panic("No suitable device found");
    }

    var best_device_index: usize = 0;
    var best_device_score: usize = 0;

    for (0..suitable_devices.items.len) |device_index| {
        const score: usize = switch (suitable_devices.items[device_index].properties.deviceType) {
            c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => 2,
            c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => 1,
            else => 0,
        };

        if (score >= best_device_index) {
            best_device_score = score;
            best_device_index = device_index;
        }
    }

    return suitable_devices.items[best_device_index];
}

fn create_device(physical_device: c.VkPhysicalDevice, queue_indices: QueueIndices) c.VkDevice {
    const device_features = c.VkPhysicalDeviceFeatures{};
    const device_extensions = [_][*]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

    var unique_queue_indices = std.hash_map.AutoHashMap(u32, void).init(allocator);
    defer unique_queue_indices.deinit();

    unique_queue_indices.put(queue_indices.compute_family, void{}) catch unreachable;
    unique_queue_indices.put(queue_indices.graphics_family, void{}) catch unreachable;
    unique_queue_indices.put(queue_indices.present_family, void{}) catch unreachable;

    const queue_priority: f32 = 1.0;
    var queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo){};
    defer queue_create_infos.deinit(allocator);

    var it = unique_queue_indices.keyIterator();
    while (it.next()) |queue_idx| {
        queue_create_infos.append(allocator, c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = queue_idx.*,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        }) catch unreachable;
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
    graphics_family: u32,
    compute_family: u32,
    present_family: u32,
};

fn find_queue_indices(physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) ?QueueIndices {
    var num_queue_families: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &num_queue_families, null);

    const queue_families = allocator.alloc(c.VkQueueFamilyProperties, num_queue_families) catch unreachable;
    defer allocator.free(queue_families);

    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &num_queue_families, queue_families.ptr);

    var compute_queue_idx: ?u32 = null;
    var graphics_queue_idx: ?u32 = null;
    var present_queue_idx: ?u32 = null;

    for (0..num_queue_families) |idx| {
        const queue_family = queue_families[idx];
        const queue_family_idx: u32 = @intCast(idx);

        var present_support: c.VkBool32 = c.VK_FALSE;
        assert(c.vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, queue_family_idx, surface, &present_support) == c.VK_SUCCESS);

        if (present_support == c.VK_TRUE) {
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
        .compute_family = compute,
        .graphics_family = graphics,
        .present_family = present,
    };
}

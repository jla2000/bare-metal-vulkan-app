const std = @import("std");
const c = @import("common.zig").c;

const allocator = @import("common.zig").allocator;
const vk_error = @import("common.zig").vk_error;

pub const CreateSurfaceFn = fn (?*anyopaque, c.VkInstance, *c.VkSurfaceKHR) c.VkResult;

pub const Core = struct {
    instance: c.VkInstance,
    debug_messenger: ?c.VkDebugUtilsMessengerEXT,
    surface: c.VkSurfaceKHR,
    phys_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    queue: c.VkQueue,
    queue_family_idx: u32,

    pub fn init(
        instance_extensions: []const [*c]const u8,
        device_extensions: []const [*c]const u8,
        device_next: ?*const anyopaque,
        enable_debug: bool,
        user_data: ?*anyopaque,
        create_surface: CreateSurfaceFn,
    ) !Core {
        const instance = try create_instance(instance_extensions, enable_debug);
        const debug_messenger = if (enable_debug) try create_debug_messenger(instance) else null;

        var surface: c.VkSurfaceKHR = undefined;
        try vk_error(create_surface(user_data, instance, &surface));

        const suitable_devices = try find_suitable_devices(instance, surface);
        defer allocator.free(suitable_devices);

        const phys_device, const properties, const queue_family_idx = try pick_best_device(suitable_devices);
        std.log.info("Picking device: {s}", .{properties.deviceName});

        const device = try create_device(phys_device, queue_family_idx, device_extensions, device_next);

        var queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, queue_family_idx, queue_family_idx, &queue);

        return .{
            .instance = instance,
            .debug_messenger = debug_messenger,
            .surface = surface,
            .phys_device = phys_device,
            .device = device,
            .queue = queue,
            .queue_family_idx = queue_family_idx,
        };
    }

    pub fn deinit(self: *Core) void {
        c.vkDestroyDevice(self.device, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        if (self.debug_messenger) |*debug_messenger| {
            destroy_debug_messenger(self.instance, debug_messenger);
        }
        c.vkDestroyInstance(self.instance, null);
    }
};

fn create_instance(
    required_extensions: []const [*c]const u8,
    enable_debug: bool,
) !c.VkInstance {
    var extensions = std.ArrayList([*c]const u8){};
    defer extensions.deinit(allocator);

    try extensions.appendSlice(allocator, required_extensions);
    if (enable_debug) {
        try extensions.append(allocator, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    }

    var layers = std.ArrayList([*c]const u8){};
    defer layers.deinit(allocator);
    if (enable_debug) {
        try layers.append(allocator, "VK_LAYER_KHRONOS_validation");
    }

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
        .enabledExtensionCount = @intCast(extensions.items.len),
        .ppEnabledExtensionNames = extensions.items.ptr,
        .enabledLayerCount = @intCast(layers.items.len),
        .ppEnabledLayerNames = layers.items.ptr,
        .pNext = if (enable_debug) &DEBUG_MESSENGER_CREATE_INFO else null,
    };

    var instance: c.VkInstance = undefined;
    try vk_error(c.vkCreateInstance(&instance_create_info, null, &instance));

    return instance;
}

const DEBUG_MESSENGER_CREATE_INFO = c.VkDebugUtilsMessengerCreateInfoEXT{
    .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
    .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
    .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
    .pfnUserCallback = debug_callback,
    .pUserData = null,
};

fn debug_callback(
    message_severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    message_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    _ = message_type;
    _ = user_data;

    switch (message_severity) {
        // c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT => std.log.debug("{s}", .{callback_data.*.pMessage}),
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => std.log.warn("{s}", .{callback_data.*.pMessage}),
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => std.log.err("{s}", .{callback_data.*.pMessage}),
        else => {},
    }

    return c.VK_FALSE;
}

pub fn create_debug_messenger(instance: c.VkInstance) !c.VkDebugUtilsMessengerEXT {
    var debug_messenger: c.VkDebugUtilsMessengerEXT = undefined;

    const create_debug_utils_messenger_ext: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(
        instance,
        "vkCreateDebugUtilsMessengerEXT",
    ));
    try vk_error(create_debug_utils_messenger_ext.?(instance, &DEBUG_MESSENGER_CREATE_INFO, null, &debug_messenger));

    return debug_messenger;
}

pub fn destroy_debug_messenger(instance: c.VkInstance, debug_messenger: *c.VkDebugUtilsMessengerEXT) void {
    const destroy_debug_utils_messenger_ext: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(
        instance,
        "vkDestroyDebugUtilsMessengerEXT",
    ));
    destroy_debug_utils_messenger_ext.?(instance, debug_messenger.*, null);
}

pub fn find_suitable_devices(
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
) ![]struct { c.VkPhysicalDevice, c.VkPhysicalDeviceProperties, u32 } {
    var num_devices: u32 = 0;
    try vk_error(c.vkEnumeratePhysicalDevices(instance, &num_devices, null));

    const physical_devices = try allocator.alloc(c.VkPhysicalDevice, num_devices);
    defer allocator.free(physical_devices);
    try vk_error(c.vkEnumeratePhysicalDevices(instance, &num_devices, physical_devices.ptr));

    var suitable_devices = std.ArrayList(struct { c.VkPhysicalDevice, c.VkPhysicalDeviceProperties, u32 }){};

    for (physical_devices) |physical_device| {
        const queue_family_idx = try find_queue_family_index(physical_device, surface) orelse continue;

        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(physical_device, &properties);

        var num_extensions: u32 = 0;
        try vk_error(c.vkEnumerateDeviceExtensionProperties(physical_device, null, &num_extensions, null));

        const extensions = allocator.alloc(c.VkExtensionProperties, num_extensions) catch unreachable;
        try vk_error(c.vkEnumerateDeviceExtensionProperties(physical_device, null, &num_extensions, extensions.ptr));

        // TODO: check if the extensions are supported

        try suitable_devices.append(allocator, .{ physical_device, properties, queue_family_idx });
        std.log.debug("Found suitable device: {s}", .{properties.deviceName});
    }

    return suitable_devices.items;
}

fn pick_best_device(
    suitable_devices: []struct { c.VkPhysicalDevice, c.VkPhysicalDeviceProperties, u32 },
) !struct { c.VkPhysicalDevice, c.VkPhysicalDeviceProperties, u32 } {
    var best_device_index: usize = 0;
    var best_device_score: usize = 0;

    for (0..suitable_devices.len) |device_index| {
        const score: usize = switch (suitable_devices[device_index][1].deviceType) {
            c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => 2,
            c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => 1,
            else => 0,
        };

        if (score >= best_device_index) {
            best_device_score = score;
            best_device_index = device_index;
        }
    }

    return suitable_devices[best_device_index];
}

pub fn find_queue_family_index(
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !?u32 {
    var num_queue_families: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &num_queue_families, null);

    const queue_families = allocator.alloc(c.VkQueueFamilyProperties, num_queue_families) catch unreachable;
    defer allocator.free(queue_families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &num_queue_families, queue_families.ptr);

    for (0..num_queue_families) |idx| {
        const queue_family = queue_families[idx];
        const queue_family_idx: u32 = @intCast(idx);

        var present_support: c.VkBool32 = c.VK_FALSE;
        try vk_error(c.vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, queue_family_idx, surface, &present_support));

        if (present_support == c.VK_TRUE and queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0 and queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            return queue_family_idx;
        }
    }

    return null;
}

pub fn create_device(
    physical_device: c.VkPhysicalDevice,
    queue_family_idx: u32,
    extensions: []const [*c]const u8,
    next: ?*const anyopaque,
) !c.VkDevice {
    const device_features = c.VkPhysicalDeviceFeatures{};

    const queue_priority: f32 = 0.5;
    const queue_create_info = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family_idx,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };

    const device_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_info,
        .queueCreateInfoCount = 1,
        .pEnabledFeatures = &device_features,
        .ppEnabledExtensionNames = extensions.ptr,
        .enabledExtensionCount = @intCast(extensions.len),
        .pNext = next,
    };

    var device: c.VkDevice = undefined;
    try vk_error(c.vkCreateDevice(physical_device, &device_create_info, null, &device));

    return device;
}

const std = @import("std");

pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
});

pub const Context = struct {
    instance: c.VkInstance,
    debug_messenger: ?c.VkDebugUtilsMessengerEXT,
    surface: c.VkSurfaceKHR,
    phys_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    queue: c.VkQueue,
    queue_family_idx: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        window_extensions: [][*c]const u8,
        enable_debug: bool,
    ) !Context {
        const instance = try create_instance(allocator, window_extensions, enable_debug);
        const debug_messenger = if (enable_debug) try create_debug_messenger(instance) else null;

        return .{
            .instance = instance,
            .debug_messenger = debug_messenger,
            .surface = undefined,
            .phys_device = undefined,
            .device = undefined,
            .queue = undefined,
            .queue_family_idx = undefined,
        };
    }

    pub fn deinit(self: *Context) void {
        if (self.debug_messenger) |*debug_messenger| {
            destroy_debug_messenger(self.instance, debug_messenger);
        }
        c.vkDestroyInstance(self.instance, null);
    }
};

pub fn vk_error(result: c.VkResult) !void {
    if (result != c.VK_SUCCESS) {
        return error.Vulkan;
    }
}

fn create_instance(
    allocator: std.mem.Allocator,
    window_extensions: [][*c]const u8,
    enable_debug: bool,
) !c.VkInstance {
    var extensions = std.ArrayList([*c]const u8){};
    defer extensions.deinit(allocator);

    try extensions.appendSlice(allocator, window_extensions);
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

const std = @import("std");
const core = @import("core.zig");

const allocator = std.heap.c_allocator;

pub fn main() !void {
    if (core.c.glfwInit() != core.c.GLFW_TRUE) {
        return error.GlfwInit;
    }
    defer core.c.glfwTerminate();

    core.c.glfwWindowHint(core.c.GLFW_CLIENT_API, core.c.GLFW_NO_API);
    core.c.glfwWindowHint(core.c.GLFW_RESIZABLE, core.c.GLFW_FALSE);

    const window = core.c.glfwCreateWindow(800, 600, "Vulkan window", null, null);
    defer core.c.glfwDestroyWindow(window);

    var num_glfw_extensions: u32 = 0;
    var glfw_extensions: [*][*c]const u8 = undefined;
    glfw_extensions = core.c.glfwGetRequiredInstanceExtensions(&num_glfw_extensions);

    var context = try core.Context.init(
        window,
        allocator,
        glfw_extensions[0..num_glfw_extensions],
        true,
        create_surface,
    );
    defer context.deinit();
}

fn create_surface(window: ?*anyopaque, instance: core.c.VkInstance, surface: *core.c.VkSurfaceKHR) core.c.VkResult {
    const window_: *core.c.GLFWwindow = @ptrCast(window);
    return core.c.glfwCreateWindowSurface(instance, window_, null, surface);
}

// const std = @import("std");
// const debug = @import("debug.zig");
// const common = @import("common.zig");
// const queue = @import("queue.zig");
// const swap = @import("swapchain.zig");
// const dev = @import("device.zig");
// const inst = @import("instance.zig");
// const c = common.c;
//
// const allocator = common.allocator;
// const assert = std.debug.assert;
//
// pub fn main() !void {
//     if (c.glfwInit() != c.GLFW_TRUE) {
//         return error.GlfwInit;
//     }
//     defer c.glfwTerminate();
//
//     c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
//     c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);
//
//     const window = c.glfwCreateWindow(800, 600, "Vulkan window", null, null);
//     defer c.glfwDestroyWindow(window);
//
//     const instance = inst.create_instance();
//     defer c.vkDestroyInstance(instance, null);
//
//     var debug_messenger = debug.create_debug_messenger(instance);
//     defer debug.destroy_debug_messenger(instance, &debug_messenger);
//
//     var surface: c.VkSurfaceKHR = undefined;
//     assert(c.glfwCreateWindowSurface(instance, window, null, &surface) == c.VK_SUCCESS);
//     defer c.vkDestroySurfaceKHR(instance, surface, null);
//
//     const physical_device = dev.find_physical_device(instance, surface);
//     std.log.info("Using physical device: {s}", .{physical_device.properties.deviceName});
//
//     const device = dev.create_device(physical_device.handle, physical_device.queue_indices);
//     defer c.vkDestroyDevice(device, null);
//
//     const queues = queue.create_queues(device, physical_device.queue_indices);
//     _ = queues;
//
//     const swapchain, const images, const format = swap.create_swapchain(
//         window,
//         physical_device.handle,
//         device,
//         surface,
//         physical_device.queue_indices,
//     );
//     defer c.vkDestroySwapchainKHR(device, swapchain, null);
//     defer allocator.free(images);
//
//     const image_views = swap.create_image_views(device, images, format);
//     defer {
//         for (image_views) |image_view| {
//             c.vkDestroyImageView(device, image_view, null);
//         }
//         allocator.free(image_views);
//     }
//
//     const shader_module = create_shader_module(device, &c.SPIRV_SHADER_CODE);
//     defer c.vkDestroyShaderModule(device, shader_module, null);
//
//     while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
//         c.glfwPollEvents();
//         c.glfwSwapBuffers(window);
//         break;
//     }
// }
//
// fn create_shader_module(device: c.VkDevice, code: []const u32) c.VkShaderModule {
//     const create_info = c.VkShaderModuleCreateInfo{
//         .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
//         .codeSize = code.len * @sizeOf(u32),
//         .pCode = code.ptr,
//     };
//
//     var shader_module: c.VkShaderModule = undefined;
//     assert(c.vkCreateShaderModule(device, &create_info, null, &shader_module) == c.VK_SUCCESS);
//
//     return shader_module;
// }

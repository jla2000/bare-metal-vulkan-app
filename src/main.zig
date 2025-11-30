const std = @import("std");
const debug = @import("debug.zig");
const common = @import("common.zig");
const queue = @import("queue.zig");
const swap = @import("swapchain.zig");
const dev = @import("device.zig");
const inst = @import("instance.zig");
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

    const instance = inst.create_instance();
    defer c.vkDestroyInstance(instance, null);

    var debug_messenger = debug.create_debug_messenger(instance);
    defer debug.destroy_debug_messenger(instance, &debug_messenger);

    var surface: c.VkSurfaceKHR = undefined;
    assert(c.glfwCreateWindowSurface(instance, window, null, &surface) == c.VK_SUCCESS);
    defer c.vkDestroySurfaceKHR(instance, surface, null);

    const physical_device = dev.find_physical_device(instance, surface);
    std.log.info("Using physical device: {s}", .{physical_device.properties.deviceName});

    const device = dev.create_device(physical_device.handle, physical_device.queue_indices);
    defer c.vkDestroyDevice(device, null);

    var graphics_queue: c.VkQueue = undefined;
    var compute_queue: c.VkQueue = undefined;
    var present_queue: c.VkQueue = undefined;

    c.vkGetDeviceQueue(device, physical_device.queue_indices.graphics_family, 0, &graphics_queue);
    c.vkGetDeviceQueue(device, physical_device.queue_indices.compute_family, 0, &compute_queue);
    c.vkGetDeviceQueue(device, physical_device.queue_indices.present_family, 0, &present_queue);

    const swapchain, const images, const format = swap.create_swapchain(
        window,
        physical_device.handle,
        device,
        surface,
        physical_device.queue_indices,
    );
    defer c.vkDestroySwapchainKHR(device, swapchain, null);
    defer allocator.free(images);

    const image_views = swap.create_image_views(device, images, format);
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

const std = @import("std");
const c = @import("common.zig").c;

const allocator = @import("common.zig").allocator;
const vk_error = @import("common.zig").vk_error;

const Core = @import("core.zig").Core;
const Swapchain = @import("swapchain.zig").Swapchain;

pub fn main() !void {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return error.GlfwInit;
    }
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    const window = c.glfwCreateWindow(800, 600, "Vulkan window", null, null);
    defer c.glfwDestroyWindow(window);

    var num_glfw_extensions: u32 = 0;
    var glfw_extensions: [*][*c]const u8 = undefined;
    glfw_extensions = c.glfwGetRequiredInstanceExtensions(&num_glfw_extensions);

    const device_extensions = [_][*]const u8{
        c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        c.VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME,
        c.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME,
        c.VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME,
    };

    const enable_raytracing_pipeline = c.VkPhysicalDeviceRayTracingPipelineFeaturesKHR{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR,
        .rayTracingPipeline = c.VK_TRUE,
    };

    var core = try Core.init(
        glfw_extensions[0..num_glfw_extensions],
        &device_extensions,
        &enable_raytracing_pipeline,
        true,
        window,
        create_surface,
    );
    defer core.deinit();

    var width: i32 = 0;
    var height: i32 = 0;
    c.glfwGetFramebufferSize(window, &width, &height);

    var swapchain = try Swapchain.init(core, @intCast(width), @intCast(height));
    defer swapchain.deinit(core);

    const pool_create_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = core.queue_family_idx,
    };

    var command_pool: c.VkCommandPool = undefined;
    try vk_error(c.vkCreateCommandPool(core.device, &pool_create_info, null, &command_pool));
    defer c.vkDestroyCommandPool(core.device, command_pool, null);

    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var command_buffer: c.VkCommandBuffer = undefined;
    try vk_error(c.vkAllocateCommandBuffers(core.device, &alloc_info, &command_buffer));

    var image_available_semaphore: c.VkSemaphore = undefined;
    var render_finished_semaphore: c.VkSemaphore = undefined;
    var in_flight_fence: c.VkFence = undefined;

    const semaphore_create_info = c.VkSemaphoreCreateInfo{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    const fence_create_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    try vk_error(c.vkCreateSemaphore(core.device, &semaphore_create_info, null, &image_available_semaphore));
    try vk_error(c.vkCreateSemaphore(core.device, &semaphore_create_info, null, &render_finished_semaphore));
    try vk_error(c.vkCreateFence(core.device, &fence_create_info, null, &in_flight_fence));

    defer c.vkDestroySemaphore(core.device, image_available_semaphore, null);
    defer c.vkDestroySemaphore(core.device, render_finished_semaphore, null);
    defer c.vkDestroyFence(core.device, in_flight_fence, null);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();

        var image_idx: u32 = undefined;
        try vk_error(c.vkAcquireNextImageKHR(core.device, swapchain.handle, c.UINT64_MAX, image_available_semaphore, null, &image_idx));

        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &image_available_semaphore,
            .pSwapchains = &swapchain.handle,
            .swapchainCount = 1,
            .pImageIndices = &image_idx,
        };

        try vk_error(c.vkQueuePresentKHR(core.queue, &present_info));
    }

    try vk_error(c.vkDeviceWaitIdle(core.device));
}

fn create_surface(user_data: ?*anyopaque, instance: c.VkInstance, surface: *c.VkSurfaceKHR) c.VkResult {
    const window: *c.GLFWwindow = @ptrCast(user_data);
    return c.glfwCreateWindowSurface(instance, window, null, surface);
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

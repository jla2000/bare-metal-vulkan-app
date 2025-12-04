pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("spirv_shader.h");
});

pub const allocator = @import("std").heap.c_allocator;

pub fn vk_error(result: c.VkResult) !void {
    if (result != c.VK_SUCCESS) {
        return error.Vulkan;
    }
}

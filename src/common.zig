pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
    @cInclude("spirv_shader.h");
});

pub const allocator = @import("std").heap.c_allocator;

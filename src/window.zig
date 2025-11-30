const std = @import("std");
const common = @import("common.zig");
const c = common.c;

pub fn open_window(width: u32, height: u32, title: []const u8) struct {
    c.GLFWwindow,
} {}

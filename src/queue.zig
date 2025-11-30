const std = @import("std");
const common = @import("common.zig");
const c = common.c;

const allocator = common.allocator;
const assert = std.debug.assert;

pub const QueueIndices = struct {
    graphics_family: u32,
    compute_family: u32,
    present_family: u32,
};

pub const Queues = struct {
    graphics_queue: c.VkQueue,
    compute_queue: c.VkQueue,
    present_queue: c.VkQueue,
};

pub fn find_queue_indices(physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) ?QueueIndices {
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

pub fn create_queues(device: c.VkDevice, queue_indices: QueueIndices) Queues {
    var queues: Queues = undefined;

    c.vkGetDeviceQueue(device, queue_indices.graphics_family, 0, &queues.graphics_queue);
    c.vkGetDeviceQueue(device, queue_indices.compute_family, 0, &queues.compute_queue);
    c.vkGetDeviceQueue(device, queue_indices.present_family, 0, &queues.present_queue);

    return queues;
}

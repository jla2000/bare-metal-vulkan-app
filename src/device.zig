const std = @import("std");
const common = @import("common.zig");
const queue = @import("queue.zig");
const c = common.c;

const allocator = common.allocator;
const assert = std.debug.assert;

pub const PhysicalDeviceInfo = struct {
    handle: c.VkPhysicalDevice,
    features: c.VkPhysicalDeviceFeatures,
    properties: c.VkPhysicalDeviceProperties,
    queue_indices: queue.QueueIndices,
};

const device_extensions = [_][*]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    c.VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME,
    c.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME,
    c.VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME,
};

pub fn find_physical_device(instance: c.VkInstance, surface: c.VkSurfaceKHR) PhysicalDeviceInfo {
    var num_devices: u32 = 0;
    assert(c.vkEnumeratePhysicalDevices(instance, &num_devices, null) == c.VK_SUCCESS);
    assert(num_devices > 0);

    const physical_devices = allocator.alloc(c.VkPhysicalDevice, num_devices) catch unreachable;
    defer allocator.free(physical_devices);
    assert(c.vkEnumeratePhysicalDevices(instance, &num_devices, physical_devices.ptr) == c.VK_SUCCESS);

    var suitable_devices = std.ArrayList(PhysicalDeviceInfo){};
    defer suitable_devices.deinit(allocator);

    for (physical_devices) |physical_device| {
        const queue_indices = queue.find_queue_indices(physical_device, surface) orelse continue;

        var properties: c.VkPhysicalDeviceProperties = undefined;
        var features: c.VkPhysicalDeviceFeatures = undefined;
        c.vkGetPhysicalDeviceProperties(physical_device, &properties);
        c.vkGetPhysicalDeviceFeatures(physical_device, &features);

        var num_extensions: u32 = 0;
        assert(c.vkEnumerateDeviceExtensionProperties(physical_device, null, &num_extensions, null) == c.VK_SUCCESS);
        const extensions = allocator.alloc(c.VkExtensionProperties, num_extensions) catch unreachable;
        assert(c.vkEnumerateDeviceExtensionProperties(physical_device, null, &num_extensions, extensions.ptr) == c.VK_SUCCESS);

        // TODO: check if the extensions are supported

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

pub fn create_device(physical_device: c.VkPhysicalDevice, queue_indices: queue.QueueIndices) c.VkDevice {
    const device_features = c.VkPhysicalDeviceFeatures{};
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

    const enable_raytracing_pipeline = c.VkPhysicalDeviceRayTracingPipelineFeaturesKHR{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR,
        .rayTracingPipeline = c.VK_TRUE,
    };

    const device_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = queue_create_infos.items.ptr,
        .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
        .pEnabledFeatures = &device_features,
        .ppEnabledExtensionNames = &device_extensions,
        .enabledExtensionCount = device_extensions.len,
        .pNext = &enable_raytracing_pipeline,
    };

    var device: c.VkDevice = undefined;
    assert(c.vkCreateDevice(physical_device, &device_create_info, null, &device) == c.VK_SUCCESS);

    return device;
}

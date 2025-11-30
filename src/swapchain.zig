const std = @import("std");
const common = @import("common.zig");
const queue = @import("queue.zig");
const c = common.c;

const allocator = common.allocator;
const assert = std.debug.assert;

pub fn create_swapchain(
    window: ?*c.GLFWwindow,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    surface: c.VkSurfaceKHR,
    queue_indices: queue.QueueIndices,
) struct { c.VkSwapchainKHR, []c.VkImage, c.VkFormat } {
    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    assert(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities) == c.VK_SUCCESS);

    const extent = choose_swapchain_extent(window, capabilities);
    const surface_format = choose_surface_format(physical_device, surface);
    const present_mode = choose_swapchain_present_mode(physical_device, surface);

    var num_images = capabilities.minImageCount + 1;
    var swapchain_create_info = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = num_images,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    };

    if (queue_indices.graphics_family != queue_indices.present_family) {
        swapchain_create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        swapchain_create_info.queueFamilyIndexCount = 2;
        swapchain_create_info.pQueueFamilyIndices = &[_]u32{ queue_indices.graphics_family, queue_indices.compute_family };
    }

    var swapchain: c.VkSwapchainKHR = undefined;
    assert(c.vkCreateSwapchainKHR(device, &swapchain_create_info, null, &swapchain) == c.VK_SUCCESS);

    assert(c.vkGetSwapchainImagesKHR(device, swapchain, &num_images, null) == c.VK_SUCCESS);
    const images = allocator.alloc(c.VkImage, num_images) catch unreachable;
    assert(c.vkGetSwapchainImagesKHR(device, swapchain, &num_images, images.ptr) == c.VK_SUCCESS);

    return .{ swapchain, images, surface_format.format };
}

fn choose_swapchain_extent(window: ?*c.GLFWwindow, capabilities: c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    }

    var width: i32 = 0;
    var height: i32 = 0;
    c.glfwGetFramebufferSize(window, &width, &height);

    return c.VkExtent2D{
        .width = std.math.clamp(@as(u32, @intCast(width)), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
        .height = std.math.clamp(@as(u32, @intCast(height)), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };
}

fn choose_surface_format(physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) c.VkSurfaceFormatKHR {
    var num_surface_formats: u32 = 0;
    assert(c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &num_surface_formats, null) == c.VK_SUCCESS);

    const surface_formats = allocator.alloc(c.VkSurfaceFormatKHR, num_surface_formats) catch unreachable;
    defer allocator.free(surface_formats);
    assert(c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &num_surface_formats, surface_formats.ptr) == c.VK_SUCCESS);

    for (surface_formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }

    return surface_formats[0];
}

fn choose_swapchain_present_mode(physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) c.VkPresentModeKHR {
    var num_present_modes: u32 = 0;
    assert(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, null) == c.VK_SUCCESS);

    const present_modes = allocator.alloc(c.VkPresentModeKHR, num_present_modes) catch unreachable;
    defer allocator.free(present_modes);
    assert(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, present_modes.ptr) == c.VK_SUCCESS);

    // for (present_modes) |mode| {
    //     if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
    //         return mode;
    //     }
    // }

    // fifo should be always supported.
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

pub fn create_image_views(device: c.VkDevice, images: []c.VkImage, format: c.VkFormat) []c.VkImageView {
    const image_views = allocator.alloc(c.VkImageView, images.len) catch unreachable;

    for (0..images.len) |image_idx| {
        const image_view_create_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = images[image_idx],
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        assert(c.vkCreateImageView(device, &image_view_create_info, null, &image_views[image_idx]) == c.VK_SUCCESS);
    }

    return image_views;
}

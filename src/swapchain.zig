const std = @import("std");
const c = @import("common.zig").c;

const CoreContext = @import("core.zig").Core;
const allocator = @import("common.zig").allocator;
const vk_error = @import("common.zig").vk_error;

pub const Swapchain = struct {
    handle: c.VkSwapchainKHR,
    images: []c.VkImage,
    image_views: []c.VkImageView,

    pub fn init(core: CoreContext, width: u32, height: u32) !Swapchain {
        var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
        try vk_error(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(core.phys_device, core.surface, &capabilities));

        const extent = choose_swapchain_extent(capabilities, width, height);
        const surface_format = try choose_surface_format(core.phys_device, core.surface);
        const present_mode = try choose_swapchain_present_mode(core.phys_device, core.surface);

        var num_images = capabilities.minImageCount + 1;
        var swapchain_create_info = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = core.surface,
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

        var swapchain: c.VkSwapchainKHR = undefined;
        try vk_error(c.vkCreateSwapchainKHR(core.device, &swapchain_create_info, null, &swapchain));

        try vk_error(c.vkGetSwapchainImagesKHR(core.device, swapchain, &num_images, null));
        const images = try allocator.alloc(c.VkImage, num_images);
        try vk_error(c.vkGetSwapchainImagesKHR(core.device, swapchain, &num_images, images.ptr));

        const image_views = try create_image_views(core.device, images, surface_format.format);

        return .{ .handle = swapchain, .images = images, .image_views = image_views };
    }

    pub fn deinit(self: *Swapchain, core: CoreContext) void {
        for (self.image_views) |image_view| {
            c.vkDestroyImageView(core.device, image_view, null);
        }
        c.vkDestroySwapchainKHR(core.device, self.handle, null);

        allocator.free(self.image_views);
        allocator.free(self.images);
    }
};

fn choose_swapchain_extent(capabilities: c.VkSurfaceCapabilitiesKHR, width: u32, height: u32) c.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    }

    return c.VkExtent2D{
        .width = std.math.clamp(width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
        .height = std.math.clamp(height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };
}

fn choose_surface_format(physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceFormatKHR {
    var num_surface_formats: u32 = 0;
    try vk_error(c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &num_surface_formats, null));

    const surface_formats = try allocator.alloc(c.VkSurfaceFormatKHR, num_surface_formats);
    defer allocator.free(surface_formats);
    try vk_error(c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &num_surface_formats, surface_formats.ptr));

    for (surface_formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }

    return surface_formats[0];
}

fn choose_swapchain_present_mode(physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkPresentModeKHR {
    var num_present_modes: u32 = 0;
    try vk_error(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, null));

    const present_modes = try allocator.alloc(c.VkPresentModeKHR, num_present_modes);
    defer allocator.free(present_modes);
    try vk_error(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &num_present_modes, present_modes.ptr));

    // for (present_modes) |mode| {
    //     if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
    //         return mode;
    //     }
    // }

    // fifo should be always supported.
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

pub fn create_image_views(device: c.VkDevice, images: []c.VkImage, format: c.VkFormat) ![]c.VkImageView {
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

        try vk_error(c.vkCreateImageView(device, &image_view_create_info, null, &image_views[image_idx]));
    }

    return image_views;
}

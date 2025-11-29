const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-raytracer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const shader_step = b.addSystemCommand(&[_][]const u8{"slangc"});
    shader_step.addFileArg(b.path("src/shaders/main.slang"));
    shader_step.addArgs(&[_][]const u8{
        "-target",
        "spirv",
        "-source-embed-style",
        "u32",
        "-source-embed-language",
        "c",
        "-source-embed-name",
        "SPIRV_SHADER_CODE",
        "-o",
    });
    const shader_output = shader_step.addOutputFileArg("spirv_shader.h");

    exe.step.dependOn(&shader_step.step);
    exe.addIncludePath(shader_output.dirname());

    exe.linkSystemLibrary("vulkan");
    exe.linkSystemLibrary("glfw");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}

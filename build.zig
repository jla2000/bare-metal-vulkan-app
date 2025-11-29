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

    const shader_step = b.addSystemCommand(&[_][]const u8{
        "slangc",
        "shaders/hello.slang",
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
    const shader_header = shader_step.addOutputFileArg("spirv_shader.h");
    exe.step.dependOn(&shader_step.step);

    exe.addIncludePath(shader_header.dirname());
    exe.linkSystemLibrary("vulkan");
    exe.linkSystemLibrary("glfw");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}

fn build_shaders(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
    _ = options;
    _ = step;
}

const std = @import("std");

const Sdk = @import("Sdk.zig");
const Assimp = @import("vendor/zig-assimp/Sdk.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    const sdk = Sdk.init(b, target, mode);

    const arg_module = b.createModule(.{ .root_source_file = .{ .path = "vendor/args/args.zig" } });

    {
        const zero_init = b.addExecutable(.{
            .name = "zero-init",
            .target = target,
            .root_source_file = .{ .path = "tools/zero-init/main.zig" },
            .optimize = mode,
        });
        zero_init.root_module.addImport("args", arg_module);
        b.installArtifact(zero_init);
    }

    // compile the zero-init example so can be sure that it actually compiles!
    {
        const app = sdk.createApplication("zero_init_app", "tools/zero-init/template/src/main.zig");
        app.setDisplayName("ZeroGraphics Init App");
        app.setPackageName("net.random_projects.zero_graphics.init_app");
        b.getInstallStep().dependOn(app.compileForWeb(mode).getStep());
    }

    {
        const converter_api = b.addTranslateC(.{
            .target = target,
            .source_file = .{ .path = "tools/zero-convert/api.h" },
            .optimize = mode,
        });
        const api_module = b.createModule(.{ .root_source_file = converter_api.getOutput() });
        const z3d_module = b.createModule(.{ .root_source_file = .{ .path = "src/rendering/z3d-format.zig" } });

        const converter = b.addExecutable(.{
            .name = "zero-convert",
            .target = target,
            .root_source_file = .{ .path = "tools/zero-convert/main.zig" },
            .optimize = mode,
        });
        converter.root_module.addImport("api", api_module);
        converter.root_module.addImport("z3d", z3d_module);
        converter.root_module.addImport("args", arg_module);

        converter.addCSourceFile(.{ .file = .{ .path = "tools/zero-convert/converter.cpp" }, .flags = &[_][]const u8{
            "-std=c++17",
            "-Wall",
            "-Wextra",
        } });
        const assimp = Assimp.init(b);
        assimp.addTo(converter, .static, Assimp.FormatSet.default);
        converter.linkLibC();
        converter.linkLibCpp();

        b.installArtifact(converter);
    }

    const zlm_module = b.createModule(.{ .root_source_file = .{ .path = "vendor/zlm/zlm.zig" } });

    const app = sdk.createApplication("demo_application", "examples/features/feature-demo.zig");
    app.setDisplayName("ZeroGraphics Demo");
    app.setPackageName("net.random_projects.zero_graphics.demo");
    app.addPackage("zero-graphics", sdk.getLibraryPackage());
    app.addPackage("zlm", zlm_module);

    // Build wasm application
    {
        const wasm_build = app.compileForWeb(mode);
        wasm_build.install();

        const serve = wasm_build.run();

        const build_step = b.step("build-wasm", "Builds the wasm app and installs it.");
        build_step.dependOn(wasm_build.install_step.?);

        const run_step = b.step("run-wasm", "Serves the wasm app");
        run_step.dependOn(&serve.step);
    }
}

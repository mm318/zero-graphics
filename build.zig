const std = @import("std");

const Sdk = @import("Sdk.zig");
const Assimp = @import("vendor/zig-assimp/Sdk.zig");

pub fn build(b: *std.Build) !void {
    const sdk = Sdk.init(b);
    const assimp = Assimp.init(b);

    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    const arg_module = b.addModule("args", .{ .source_file = .{ .path = "vendor/args/args.zig" } });

    {
        const zero_init = b.addExecutable(.{
            .name = "zero-init",
            .root_source_file = .{ .path = "tools/zero-init/main.zig" },
        });
        zero_init.addModule("args", arg_module);
        b.installArtifact(zero_init);
    }

    // compile the zero-init example so can be sure that it actually compiles!
    {
        const app = sdk.createApplication("zero_init_app", "tools/zero-init/template/src/main.zig");
        app.setDisplayName("ZeroGraphics Init App");
        app.setPackageName("net.random_projects.zero_graphics.init_app");
        app.setBuildMode(mode);
        b.getInstallStep().dependOn(app.compileForWeb().getStep());
    }

    {
        const converter_api = b.addTranslateC(.{ .source_file = .{ .path = "tools/zero-convert/api.h" }, .target = target, .optimize = mode });
        const api_module = b.addModule("api", .{ .source_file = converter_api.getOutput() });
        const z3d_module = b.addModule("z3d", .{ .source_file = .{ .path = "src/rendering/z3d-format.zig" } });

        const converter = b.addExecutable(.{ .name = "zero-convert", .root_source_file = .{ .path = "tools/zero-convert/main.zig" } });
        converter.addCSourceFile(.{ .file = .{ .path = "tools/zero-convert/converter.cpp" }, .flags = &[_][]const u8{
            "-std=c++17",
            "-Wall",
            "-Wextra",
        } });
        converter.addModule("api", api_module);
        converter.addModule("z3d", z3d_module);
        converter.addModule("args", arg_module);
        converter.linkLibC();
        converter.linkLibCpp();
        assimp.addTo(converter, .static, Assimp.FormatSet.default);
        b.installArtifact(converter);
    }

    const app = sdk.createApplication("demo_application", "examples/features/feature-demo.zig");
    app.setDisplayName("ZeroGraphics Demo");
    app.setPackageName("net.random_projects.zero_graphics.demo");
    app.setBuildMode(mode);

    app.addPackage(std.build.Pkg{
        .name = "zlm",
        .source = .{ .path = "vendor/zlm/zlm.zig" },
    });

    // Build wasm application
    {
        const wasm_build = app.compileForWeb();
        wasm_build.install();

        const serve = wasm_build.run();

        const build_step = b.step("build-wasm", "Builds the wasm app and installs it.");
        build_step.dependOn(wasm_build.install_step.?);

        const run_step = b.step("run-wasm", "Serves the wasm app");
        run_step.dependOn(&serve.step);
    }

    // {
    //     const zero_g_pkg = sdk.getLibraryPackage("zero-graphics");
    //     const zero_ui_pkg = std.build.Pkg{
    //         .name = "zero-ui",
    //         .source = .{ .path = "src/ui/core/ui.zig" },
    //         .dependencies = &.{
    //             zero_g_pkg,
    //             .{
    //                 .name = "controls",
    //                 .source = .{ .path = "src/ui/standard-controls/standard-controls.zig" },
    //                 .dependencies = &.{
    //                     .{
    //                         .name = "ui",
    //                         .source = .{ .path = "src/ui/core/ui.zig" },
    //                     },
    //                     .{
    //                         .name = "TextEditor",
    //                         .source = .{ .path = "vendor/text-editor/src/TextEditor.zig" },
    //                         .dependencies = &.{
    //                             .{
    //                                 .name = "ziglyph",
    //                                 .source = .{ .path = "vendor/ziglyph/src/ziglyph.zig" },
    //                             },
    //                         },
    //                     },
    //                 },
    //             },
    //         },
    //     };

    //     const ui_demo = sdk.createApplication("ui_demo", "examples/ui/demo.zig");
    //     ui_demo.setDisplayName("Zero UI");
    //     ui_demo.setPackageName("net.random_projects.zero_graphics.ui_demo");
    //     ui_demo.setBuildMode(mode);
    //     ui_demo.addPackage(zero_ui_pkg);
    //     ui_demo.addPackage(.{
    //         .name = "layout-engine",
    //         .source = .{ .path = "src/ui/standard-layout/standard-layout.zig" },
    //         .dependencies = &.{zero_ui_pkg},
    //     });
    //     ui_demo.addPackage(.{
    //         .name = "render-engine",
    //         .source = .{ .path = "src/ui/standard-renderer/standard-renderer.zig" },
    //         .dependencies = &.{ zero_ui_pkg, zero_g_pkg },
    //     });

    //     ui_demo.setInitialResolution(.{ .windowed = .{ .width = 480, .height = 320 } });

    //     const ui_demo_exe = ui_demo.compileForWeb(platform);

    //     ui_demo_exe.install();
    // }
}

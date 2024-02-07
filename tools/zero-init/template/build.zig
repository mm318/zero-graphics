const std = @import("std");
const Sdk = @import("vendor/zero-graphics/Sdk.zig");

pub fn build(b: *std.build.Builder) !void {
    const sdk = Sdk.init(b);

    const mode = b.standardReleaseOptions();
    const platform = sdk.standardPlatformOptions();

    const app = sdk.createApplication("new_project", "src/main.zig");
    app.setDisplayName("New Project");
    app.setPackageName("com.example.new_project");
    app.setBuildMode(mode);

    {
        const desktop_exe = app.compileFor(platform);
        desktop_exe.install();

        const run_cmd = desktop_exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // Build wasm application
    {
        const wasm_build = app.compileFor(.web);
        wasm_build.install();
    }
}

const std = @import("std");
const Sdk = @import("vendor/zero-graphics/Sdk.zig");

pub fn build(b: *std.build.Builder) !void {
    const sdk = Sdk.init(b);

    const mode = b.standardReleaseOptions();

    const app = sdk.createApplication("new_project", "src/main.zig");
    app.setDisplayName("New Project");
    app.setPackageName("com.example.new_project");
    app.setBuildMode(mode);

    // Build wasm application
    {
        const wasm_build = app.compileForWeb(.web);
        wasm_build.install();
    }
}

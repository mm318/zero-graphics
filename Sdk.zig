const std = @import("std");
const logger = std.log.scoped(.zero_graphics_sdk);

const Sdk = @This();

const TemplateStep = @import("vendor/ztt/src/TemplateStep.zig");

const web_folder = std.Build.InstallDir{ .custom = "www" };

builder: *std.Build,
dummy_server: *std.Build.Step.Compile,
install_web_sources: []*std.Build.Step.InstallFile,
render_main_page_tool: *std.Build.Step.Compile,
zero_graphics_pkg: ?*std.Build.Module,

pub fn init(builder: *std.Build, target: std.Build.ResolvedTarget, mode: std.builtin.OptimizeMode) *Sdk {
    const sdk = builder.allocator.create(Sdk) catch @panic("out of memory");
    sdk.* = Sdk{
        .builder = builder,
        .install_web_sources = builder.allocator.dupe(
            *std.Build.Step.InstallFile,
            &[_]*std.Build.Step.InstallFile{
                builder.addInstallFileWithDir(builder.path("www/barebones-wasi.js"), web_folder, "barebones-wasi.js"),
                builder.addInstallFileWithDir(builder.path("www/zero-graphics.js"), web_folder, "zero-graphics.js"),
            },
        ) catch @panic("out of memory"),
        .render_main_page_tool = builder.addExecutable(.{
            .name = "render-html-page",
            .target = target,
            .root_source_file = builder.path("tools/render-ztt-page.zig"),
            .optimize = mode,
        }),
        .dummy_server = undefined,
        .zero_graphics_pkg = null,
    };

    const html_module = builder.addModule("html", .{
        .root_source_file = TemplateStep.transformSource(builder, builder.path("www/application.ztt")),
    });
    sdk.render_main_page_tool.root_module.addImport("html", html_module);

    sdk.dummy_server = builder.addExecutable(.{
        .name = "http-server",
        .target = target,
        .root_source_file = builder.path("tools/http-server.zig"),
        .optimize = mode,
    });
    sdk.dummy_server.linkLibC();

    return sdk;
}

fn validateName(name: []const u8, allowed_chars: []const u8) void {
    for (name) |c| {
        if (std.mem.indexOfScalar(u8, allowed_chars, c) == null)
            std.debug.panic("The given name '{s}' contains invalid characters. Allowed characters are '{s}'", .{ name, allowed_chars });
    }
}

pub fn getLibraryPackage(sdk: *Sdk) *std.Build.Module {
    if (sdk.zero_graphics_pkg == null) {
        const zigimg = std.Build.Module.Import{
            .name = "zigimg",
            .module = sdk.builder.createModule(.{ .root_source_file = sdk.builder.path("vendor/zigimg/zigimg.zig") }),
        };
        const ziglyph = std.Build.Module.Import{
            .name = "ziglyph",
            .module = sdk.builder.createModule(.{ .root_source_file = sdk.builder.path("vendor/ziglyph/src/ziglyph.zig") }),
        };
        const zigstr = std.Build.Module.Import{
            .name = "zigstr",
            .module = sdk.builder.createModule(.{
                .root_source_file = sdk.builder.path("vendor/zigstr/src/Zigstr.zig"),
                .imports = &.{ziglyph},
            }),
        };
        const text_editor = std.Build.Module.Import{
            .name = "TextEditor",
            .module = sdk.builder.createModule(.{
                .root_source_file = sdk.builder.path("vendor/text-editor/src/TextEditor.zig"),
                .imports = &.{ziglyph},
            }),
        };

        sdk.zero_graphics_pkg = sdk.builder.createModule(.{
            .root_source_file = sdk.builder.path("src/zero-graphics.zig"),
            .imports = &[_]std.Build.Module.Import{
                zigimg,
                ziglyph,
                zigstr,
                text_editor,
            },
        });
        // TTF rendering library:
        sdk.zero_graphics_pkg.?.addCSourceFile(.{
            .file = sdk.builder.path("src/rendering/stb_truetype.c"),
            .flags = &[_][]const u8{"-std=c99"},
        });
        sdk.zero_graphics_pkg.?.addIncludePath(sdk.builder.path("vendor/stb/"));
    }

    return sdk.zero_graphics_pkg.?;
}

pub fn createApplication(sdk: *Sdk, name: []const u8, root_file: []const u8) *Application {
    return createApplicationSource(sdk, name, sdk.builder.path(root_file));
}

pub fn createApplicationSource(sdk: *Sdk, name: []const u8, root_file: std.Build.LazyPath) *Application {
    validateName(name, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_");

    const app = sdk.builder.allocator.create(Application) catch @panic("out of memory");
    const create_meta_step = CreateAppMetaStep.create(sdk, app);
    app.* = Application{
        .sdk = sdk,
        .name = sdk.builder.dupe(name),
        .app_root_file = root_file.dupe(sdk.builder),
        .app_deps = std.ArrayList(std.Build.Module.Import).init(sdk.builder.allocator),
        .framework_pkg = std.Build.Module.Import{
            .name = "zero-graphics",
            .module = sdk.getLibraryPackage(),
        },
        .meta_pkg = std.Build.Module.Import{
            .name = "application-meta",
            .module = sdk.builder.createModule(.{
                .root_source_file = create_meta_step.getOutput(),
            }),
        },
    };

    return app;
}

pub const Size = struct {
    width: u15,
    height: u15,
};

pub const InitialResolution = union(enum) {
    fullscreen,
    windowed: Size,
};

pub const Features = struct {
    code_editor: bool,
    file_dialogs: bool,
};

pub const Application = struct {
    sdk: *Sdk,
    app_root_file: std.Build.LazyPath,
    app_deps: std.ArrayList(std.Build.Module.Import),
    framework_pkg: std.Build.Module.Import,
    meta_pkg: std.Build.Module.Import,

    name: []const u8,
    display_name: ?[]const u8 = null,
    package_name: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    resolution: InitialResolution = .{ .windowed = Size{ .width = 1280, .height = 720 } },

    /// Set of features not necessarily present on every platform.
    /// Enable/disable these features to increase/decrease project size.
    features: Features = .{
        .code_editor = true,
        .file_dialogs = false, // not supported by default atm
    },

    pub fn addPackage(app: *Application, name: []const u8, pkg: *std.Build.Module) void {
        app.app_deps.append(.{ .name = name, .module = pkg }) catch @panic("out of memory!");
    }

    /// The display name of the application. This is shown to the users.
    pub fn setDisplayName(app: *Application, name: []const u8) void {
        app.display_name = app.sdk.builder.dupe(name);
    }

    /// Java package name, usually the reverse top level domain + app name.
    /// Only lower case letters, dots and underscores are allowed.
    pub fn setPackageName(app: *Application, name: []const u8) void {
        validateName(name, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.");
        app.package_name = app.sdk.builder.dupe(name);
    }

    /// Path to the application icon, must be a PNG file.
    pub fn setIcon(app: *Application, icon: []const u8) void {
        app.icon = app.sdk.builder.dupe(icon);
    }

    /// Sets the initial preferred resolution for the application.
    /// This isn't a hard constraint, but zero-graphics tries to satisfy this if possible.
    /// Some backends can only provide fullscreen applications though.
    pub fn setInitialResolution(app: *Application, resolution: InitialResolution) void {
        app.resolution = resolution;
    }

    fn prepareExe(app: *Application, exe: *std.Build.Step.Compile, app_pkg: std.Build.Module.Import, features: Features) void {
        app.framework_pkg.module.addImport(app_pkg.name, app_pkg.module);

        exe.root_module.addImport(app_pkg.name, app_pkg.module);
        exe.root_module.addImport(app.framework_pkg.name, app.framework_pkg.module);
        exe.root_module.addImport(app.meta_pkg.name, app.meta_pkg.module);

        if (features.code_editor) {
            const scintilla_header = app.sdk.builder.addTranslateC(.{
                .root_source_file = app.sdk.builder.path("src/scintilla/code_editor.h"),
                .target = exe.root_module.resolved_target.?,
                .optimize = exe.root_module.optimize.?,
            });

            exe.root_module.addImport("scintilla", app.sdk.builder.createModule(.{
                .root_source_file = scintilla_header.getOutput(),
            }));
            exe.step.dependOn(&scintilla_header.step);

            const scintilla = createScintilla(app.sdk.builder, exe.root_module.resolved_target.?, exe.root_module.optimize.?);
            exe.linkLibrary(scintilla);
        }

        if (features.file_dialogs) {
            @panic("file dialogs not supported on web platform.");
        }
    }

    pub fn compileForWeb(app: *Application, mode: std.builtin.OptimizeMode) *AppCompilation {
        const target = std.Build.resolveTargetQuery(app.sdk.builder, .{ .cpu_arch = .wasm32, .os_tag = .wasi });

        const app_pkg = std.Build.Module.Import{
            .name = "application",
            .module = app.sdk.builder.createModule(.{
                .root_source_file = app.app_root_file,
                .imports = app.app_deps.items,
            }),
        };

        const features = blk: {
            var features = Features{
                .code_editor = app.features.code_editor,
                .file_dialogs = app.features.file_dialogs,
            };

            if (features.file_dialogs) {
                features.file_dialogs = false;
                logger.warn("Disabling unsupported feature 'file_dialogs' for web platform", .{});
            }

            break :blk features;
        };

        const options = app.sdk.builder.addWriteFile("target-config.zig", blk: {
            var list = std.ArrayList(u8).init(app.sdk.builder.allocator);
            var writer = list.writer();

            writer.writeAll(
                \\pub const Features = struct { 
                \\      code_editor: bool,
                \\      file_dialogs: bool
                \\};
                \\
                \\pub const features = Features {
            ) catch unreachable;
            writer.print("\n    .code_editor = {},", .{features.code_editor}) catch unreachable;
            writer.print("\n    .file_dialogs = {},", .{features.file_dialogs}) catch unreachable;
            writer.writeAll(
                \\
                \\};
                \\
            ) catch unreachable;

            break :blk list.toOwnedSlice() catch unreachable;
        });

        const build_options = app.sdk.builder.createModule(.{ .root_source_file = .{
            .generated = .{ .file = &options.generated_directory, .sub_path = "target-config.zig" },
        } });

        const exe = app.sdk.builder.addExecutable(.{
            .name = app.name,
            .target = target,
            .root_source_file = app.sdk.builder.path("src/main/wasm.zig"),
            .optimize = mode,
        });
        exe.entry = .disabled;
        exe.rdynamic = true;
        exe.root_module.addImport("build-options", build_options);
        app.prepareExe(exe, app_pkg, features);

        return app.createCompilation(.{ .web = exe });
    }

    fn createCompilation(app: *Application, data: AppCompilation.Data) *AppCompilation {
        const comp = app.sdk.builder.allocator.create(AppCompilation) catch @panic("out of memory");
        comp.* = AppCompilation{
            .sdk = app.sdk,
            .app = app,
            .data = data,
        };
        return comp;
    }
};

pub const AppCompilation = struct {
    const Data = union(enum) {
        web: *std.Build.Step.Compile,
    };

    sdk: *Sdk,
    app: *Application,
    data: Data,
    install_step: ?*std.Build.Step = null,

    pub fn getStep(comp: *AppCompilation) *std.Build.Step {
        return switch (comp.data) {
            .web => |step| &step.step,
        };
    }

    pub fn install(comp: *AppCompilation) void {
        switch (comp.data) {
            .web => |step| {
                const install_step = comp.sdk.builder.addInstallArtifact(step, .{
                    .dest_dir = .{ .override = web_folder },
                });

                for (comp.sdk.install_web_sources) |installer| {
                    install_step.step.dependOn(&installer.step);
                }

                const file_name = comp.sdk.builder.fmt("{s}.htm", .{step.name});

                const app_html_page = CreateApplicationHtmlPageStep.create(
                    comp.sdk,
                    comp.app.name,
                    comp.app.display_name orelse "Untitled Application",
                );

                const install_html_page = comp.sdk.builder.addInstallFileWithDir(
                    app_html_page.outfile,
                    web_folder,
                    file_name,
                );
                install_html_page.step.dependOn(&app_html_page.step.step);

                install_step.step.dependOn(&install_html_page.step);

                comp.install_step = &install_step.step;
            },
        }
    }

    pub fn run(comp: *AppCompilation) *std.Build.Step.Run {
        return switch (comp.data) {
            .web => |step| blk: {
                comp.sdk.builder.installArtifact(step);

                const serve = comp.sdk.builder.addRunArtifact(comp.sdk.dummy_server);
                serve.addArg(comp.app.name);
                serve.step.dependOn(comp.install_step orelse @panic("App not installed before running"));
                serve.cwd = .{ .cwd_relative = comp.sdk.builder.getInstallPath(web_folder, "") };
                break :blk serve;
            },
        };
    }
};

const CreateAppMetaStep = struct {
    step: std.Build.Step,
    app: *Application,

    outfile: std.Build.GeneratedFile,

    pub fn create(sdk: *Sdk, app: *Application) *CreateAppMetaStep {
        const ms = sdk.builder.allocator.create(CreateAppMetaStep) catch @panic("out of memory");
        ms.* = CreateAppMetaStep{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "Create application meta data",
                .owner = sdk.builder,
                .makeFn = make,
            }),
            .app = app,
            .outfile = std.Build.GeneratedFile{ .step = &ms.step },
        };
        return ms;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const self: *CreateAppMetaStep = @fieldParentPtr("step", step);

        var cache = CacheBuilder.init(self.app.sdk.builder, "zero-graphics");

        var file_data = std.ArrayList(u8).init(self.app.sdk.builder.allocator);
        defer file_data.deinit();
        {
            const writer = file_data.writer();

            try writer.print("pub const name = \"{}\";\n", .{
                std.zig.fmtEscapes(self.app.name),
            });
            try writer.print("pub const display_name = \"{}\";\n", .{
                std.zig.fmtEscapes(self.app.display_name orelse self.app.name),
            });
            try writer.print("pub const package_name = \"{}\";\n", .{
                std.zig.fmtEscapes(self.app.package_name orelse self.app.name),
            });
            if (self.app.resolution == .windowed) {
                try writer.print("pub const initial_resolution = .{{ .width = {}, .height = {} }};\n", .{
                    self.app.resolution.windowed.width,
                    self.app.resolution.windowed.height,
                });
            }
        }

        cache.addBytes(file_data.items);

        self.outfile.path = try cache.createSingleFile("app-meta.zig", file_data.items);
    }

    pub fn getOutput(create_step: *CreateAppMetaStep) std.Build.LazyPath {
        return .{ .generated = .{ .file = &create_step.outfile } };
    }
};

const CreateApplicationHtmlPageStep = struct {
    sdk: *Sdk,
    step: *std.Build.Step.Run,
    outfile: std.Build.LazyPath,

    pub fn create(sdk: *Sdk, app_name: []const u8, display_name: []const u8) *CreateApplicationHtmlPageStep {
        const run_step = sdk.builder.addRunArtifact(sdk.render_main_page_tool);
        const output = run_step.addOutputFileArg("index.htm");
        run_step.addArgs(&[_][]const u8{
            app_name,
            display_name,
        });

        const ms = sdk.builder.allocator.create(CreateApplicationHtmlPageStep) catch @panic("out of memory");
        ms.* = CreateApplicationHtmlPageStep{
            .sdk = sdk,
            .step = run_step,
            .outfile = output,
        };
        return ms;
    }
};

const CacheBuilder = struct {
    const Self = @This();

    builder: *std.Build,
    hasher: std.crypto.hash.Sha1,
    subdir: ?[]const u8,

    pub fn init(builder: *std.Build, subdir: ?[]const u8) Self {
        return Self{
            .builder = builder,
            .hasher = std.crypto.hash.Sha1.init(.{}),
            .subdir = if (subdir) |s|
                builder.dupe(s)
            else
                null,
        };
    }

    pub fn addBytes(self: *Self, bytes: []const u8) void {
        self.hasher.update(bytes);
    }

    pub fn addFile(self: *Self, file: std.Build.LazyPath) !void {
        const path = file.getPath(self.builder);

        const data = try std.fs.cwd().readFileAlloc(self.builder.allocator, path, 1 << 32); // 4 GB
        defer self.builder.allocator.free(data);

        self.addBytes(data);
    }

    fn createPath(self: *Self) ![]const u8 {
        var hash: [20]u8 = undefined;
        self.hasher.final(&hash);

        const path = if (self.subdir) |subdir|
            try std.fmt.allocPrint(
                self.builder.allocator,
                "{s}/{s}/o/{}",
                .{
                    self.builder.cache_root.path orelse ".",
                    subdir,
                    std.fmt.fmtSliceHexLower(&hash),
                },
            )
        else
            try std.fmt.allocPrint(
                self.builder.allocator,
                "{s}/o/{}",
                .{
                    self.builder.cache_root.path orelse ".",
                    std.fmt.fmtSliceHexLower(&hash),
                },
            );

        return path;
    }

    pub const DirAndPath = struct {
        dir: std.fs.Dir,
        path: []const u8,
    };
    pub fn createAndGetDir(self: *Self) !DirAndPath {
        const path = try self.createPath();
        return DirAndPath{
            .path = path,
            .dir = try std.fs.cwd().makeOpenPath(path, .{}),
        };
    }

    pub fn createAndGetPath(self: *Self) ![]const u8 {
        const path = try self.createPath();
        try std.fs.cwd().makePath(path);
        return path;
    }

    pub fn createSingleFile(self: *Self, name: []const u8, data: []const u8) ![]const u8 {
        var dp = try self.createAndGetDir();
        defer dp.dir.close();

        try dp.dir.writeFile(.{ .sub_path = name, .data = data });

        return try std.fs.path.join(self.builder.allocator, &[_][]const u8{
            dp.path,
            name,
        });
    }
};

fn createScintilla(b: *std.Build, target: std.Build.ResolvedTarget, mode: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "scintilla",
        .target = target,
        .optimize = mode,
    });
    lib.addCSourceFiles(.{ .files = &scintilla_sources, .flags = &scintilla_flags });
    lib.addIncludePath(b.path("vendor/scintilla/include"));
    lib.addIncludePath(b.path("vendor/scintilla/lexlib"));
    lib.addIncludePath(b.path("vendor/scintilla/src"));
    lib.defineCMacro("SCI_LEXER", null);
    lib.defineCMacro("GTK", null);
    lib.defineCMacro("SCI_NAMESPACE", null);
    lib.linkLibC();
    lib.linkLibCpp();
    // TODO: This is not clean, fix it!
    lib.addCSourceFile(.{
        .file = b.path("src/scintilla/code_editor.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-Wall",
            "-Wextra",
            "-Wno-unused-parameter",
        },
    });
    return lib;
}

const scintilla_flags = [_][]const u8{
    "-std=c++17",
    "-fno-sanitize=undefined",
};

const scintilla_sources = [_][]const u8{
    "vendor/scintilla/lexers/LexCPP.cxx",
    "vendor/scintilla/lexers/LexOthers.cxx",
    "vendor/scintilla/lexlib/Accessor.cxx",
    "vendor/scintilla/lexlib/CharacterCategory.cxx",
    "vendor/scintilla/lexlib/CharacterSet.cxx",
    "vendor/scintilla/lexlib/LexerBase.cxx",
    "vendor/scintilla/lexlib/LexerModule.cxx",
    "vendor/scintilla/lexlib/LexerNoExceptions.cxx",
    "vendor/scintilla/lexlib/LexerSimple.cxx",
    "vendor/scintilla/lexlib/PropSetSimple.cxx",
    "vendor/scintilla/lexlib/StyleContext.cxx",
    "vendor/scintilla/lexlib/WordList.cxx",
    "vendor/scintilla/src/AutoComplete.cxx",
    "vendor/scintilla/src/CallTip.cxx",
    "vendor/scintilla/src/CaseConvert.cxx",
    "vendor/scintilla/src/CaseFolder.cxx",
    "vendor/scintilla/src/Catalogue.cxx",
    "vendor/scintilla/src/CellBuffer.cxx",
    "vendor/scintilla/src/CharClassify.cxx",
    "vendor/scintilla/src/ContractionState.cxx",
    "vendor/scintilla/src/Decoration.cxx",
    "vendor/scintilla/src/Document.cxx",
    "vendor/scintilla/src/EditModel.cxx",
    "vendor/scintilla/src/Editor.cxx",
    "vendor/scintilla/src/EditView.cxx",
    "vendor/scintilla/src/ExternalLexer.cxx",
    "vendor/scintilla/src/Indicator.cxx",
    "vendor/scintilla/src/KeyMap.cxx",
    "vendor/scintilla/src/LineMarker.cxx",
    "vendor/scintilla/src/MarginView.cxx",
    "vendor/scintilla/src/PerLine.cxx",
    "vendor/scintilla/src/PositionCache.cxx",
    "vendor/scintilla/src/RESearch.cxx",
    "vendor/scintilla/src/RunStyles.cxx",
    "vendor/scintilla/src/Selection.cxx",
    "vendor/scintilla/src/Style.cxx",
    "vendor/scintilla/src/UniConversion.cxx",
    "vendor/scintilla/src/ViewStyle.cxx",
    "vendor/scintilla/src/XPM.cxx",
};

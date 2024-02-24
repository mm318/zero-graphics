const std = @import("std");
const logger = std.log.scoped(.zero_graphics_sdk);

fn sdkPath(comptime suffix: []const u8) std.Build.LazyPath {
    if (suffix[0] != '/') {
        @compileError("sdkPath requires an absolute path!");
    }
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk std.Build.LazyPath{ .path = root_dir ++ suffix };
    };
}

const Sdk = @This();

const TemplateStep = @import("vendor/ztt/src/TemplateStep.zig");

fn requiresSingleThreaded(target: std.Build.ResolvedTarget) bool {
    if (target.result.cpu.arch == .wasm32) { // always
        return true;
    }
    return false;
}

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
                builder.addInstallFileWithDir(sdkPath("/www/zero-graphics.js"), web_folder, "zero-graphics.js"),
            },
        ) catch @panic("out of memory"),
        .render_main_page_tool = builder.addExecutable(.{
            .name = "render-html-page",
            .target = target,
            .root_source_file = sdkPath("/tools/render-ztt-page.zig"),
            .optimize = mode,
        }),
        .dummy_server = undefined,
        .zero_graphics_pkg = null,
    };

    const html_module = builder.addModule("html", .{
        .root_source_file = TemplateStep.transformSource(builder, sdkPath("/www/application.ztt")),
    });
    sdk.render_main_page_tool.root_module.addImport("html", html_module);

    sdk.dummy_server = builder.addExecutable(.{
        .name = "http-server",
        .target = target,
        .root_source_file = sdkPath("/tools/http-server.zig"),
        .optimize = mode,
    });
    sdk.dummy_server.root_module.addAnonymousImport("apple_pie", .{
        .root_source_file = sdkPath("/vendor/apple_pie/src/apple_pie.zig"),
    });

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
            .module = sdk.builder.createModule(.{ .root_source_file = sdkPath("/vendor/zigimg/zigimg.zig") }),
        };
        const ziglyph = std.Build.Module.Import{
            .name = "ziglyph",
            .module = sdk.builder.createModule(.{ .root_source_file = sdkPath("/vendor/ziglyph/src/ziglyph.zig") }),
        };
        const zigstr = std.Build.Module.Import{
            .name = "zigstr",
            .module = sdk.builder.createModule(.{
                .root_source_file = sdkPath("/vendor/zigstr/src/Zigstr.zig"),
                .imports = &.{ziglyph},
            }),
        };
        const text_editor = std.Build.Module.Import{
            .name = "TextEditor",
            .module = sdk.builder.createModule(.{
                .root_source_file = sdkPath("/vendor/text-editor/src/TextEditor.zig"),
                .imports = &.{ziglyph},
            }),
        };
        sdk.zero_graphics_pkg = sdk.builder.createModule(.{
            .root_source_file = sdkPath("/src/zero-graphics.zig"),
            .imports = &[_]std.Build.Module.Import{
                zigimg,
                ziglyph,
                zigstr,
                text_editor,
            },
        });
    }

    return sdk.zero_graphics_pkg.?;
}

pub fn createApplication(sdk: *Sdk, name: []const u8, root_file: []const u8) *Application {
    return createApplicationSource(sdk, name, .{ .path = root_file });
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
                .root_source_file = std.Build.LazyPath{ .generated = &create_meta_step.outfile },
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
        // exe.main_pkg_path = sdkPath("/src");
        app.framework_pkg.module.addImport(app_pkg.name, app_pkg.module);

        exe.root_module.addImport(app_pkg.name, app_pkg.module);
        exe.root_module.addImport(app.framework_pkg.name, app.framework_pkg.module);
        exe.root_module.addImport(app.meta_pkg.name, app.meta_pkg.module);

        // TTF rendering library:
        exe.addIncludePath(sdkPath("/vendor/stb"));
        exe.addCSourceFile(.{ .file = sdkPath("/src/rendering/stb_truetype.c"), .flags = &[_][]const u8{"-std=c99"} });

        exe.addIncludePath(sdkPath("/src/scintilla"));

        if (features.code_editor) {
            const scintilla_header = app.sdk.builder.addTranslateC(.{
                .source_file = sdkPath("/src/scintilla/code_editor.h"),
                .target = exe.root_module.resolved_target.?,
                .optimize = exe.root_module.optimize.?,
            });

            exe.root_module.addImport("scintilla", app.sdk.builder.createModule(.{
                .root_source_file = .{ .generated = &scintilla_header.output_file },
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
        const target = std.Build.resolveTargetQuery(app.sdk.builder, .{ .cpu_arch = .wasm32, .os_tag = .freestanding, .abi = .musl });

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

            if (features.code_editor) {
                features.code_editor = false;
                logger.warn("Disabling unsupported feature 'code_editor' for web platform", .{});
            }
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

        // var options_file: ?*std.Build.Step.WriteFile.File = null;
        const options_file: ?*std.Build.Step.WriteFile.File = for (options.files.items) |file| {
            if (std.mem.eql(u8, "target-config.zig", file.sub_path)) {
                break file;
            }
        } else null;
        const build_options = app.sdk.builder.createModule(.{ .root_source_file = options_file.?.getPath() });

        const exe = app.sdk.builder.addExecutable(.{
            .name = app.name,
            .target = target,
            .root_source_file = sdkPath("/src/main/wasm.zig"),
            .optimize = mode,
            .single_threaded = requiresSingleThreaded(target),
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
                serve.cwd = .{ .path = comp.sdk.builder.getInstallPath(web_folder, "") };
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

    fn make(step: *std.Build.Step, prog_node: *std.Progress.Node) anyerror!void {
        _ = prog_node;
        const self = @fieldParentPtr(CreateAppMetaStep, "step", step);

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

        try dp.dir.writeFile(name, data);

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
        .single_threaded = requiresSingleThreaded(target),
    });
    lib.addCSourceFiles(.{ .files = &scintilla_sources, .flags = &scintilla_flags });
    lib.addIncludePath(sdkPath("/vendor/scintilla/include"));
    lib.addIncludePath(sdkPath("/vendor/scintilla/lexlib"));
    lib.addIncludePath(sdkPath("/vendor/scintilla/src"));
    lib.defineCMacro("SCI_LEXER", null);
    lib.defineCMacro("GTK", null);
    lib.defineCMacro("SCI_NAMESPACE", null);
    lib.linkLibC();
    lib.linkLibCpp();
    // TODO: This is not clean, fix it!
    lib.addCSourceFile(.{
        .file = sdkPath("/src/scintilla/code_editor.cpp"),
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
    "-fno-sanitize=undefined",
    "-std=c++17",
};

const scintilla_sources = [_][]const u8{
    sdkPath("/vendor/scintilla/lexers/LexCPP.cxx").path,
    sdkPath("/vendor/scintilla/lexers/LexOthers.cxx").path,
    sdkPath("/vendor/scintilla/lexlib/Accessor.cxx").path,
    sdkPath("/vendor/scintilla/lexlib/CharacterCategory.cxx").path,
    sdkPath("/vendor/scintilla/lexlib/CharacterSet.cxx").path,
    sdkPath("/vendor/scintilla/lexlib/LexerBase.cxx").path,
    sdkPath("/vendor/scintilla/lexlib/LexerModule.cxx").path,
    sdkPath("/vendor/scintilla/lexlib/LexerNoExceptions.cxx").path,
    sdkPath("/vendor/scintilla/lexlib/LexerSimple.cxx").path,
    sdkPath("/vendor/scintilla/lexlib/PropSetSimple.cxx").path,
    sdkPath("/vendor/scintilla/lexlib/StyleContext.cxx").path,
    sdkPath("/vendor/scintilla/lexlib/WordList.cxx").path,
    sdkPath("/vendor/scintilla/src/AutoComplete.cxx").path,
    sdkPath("/vendor/scintilla/src/CallTip.cxx").path,
    sdkPath("/vendor/scintilla/src/CaseConvert.cxx").path,
    sdkPath("/vendor/scintilla/src/CaseFolder.cxx").path,
    sdkPath("/vendor/scintilla/src/Catalogue.cxx").path,
    sdkPath("/vendor/scintilla/src/CellBuffer.cxx").path,
    sdkPath("/vendor/scintilla/src/CharClassify.cxx").path,
    sdkPath("/vendor/scintilla/src/ContractionState.cxx").path,
    sdkPath("/vendor/scintilla/src/Decoration.cxx").path,
    sdkPath("/vendor/scintilla/src/Document.cxx").path,
    sdkPath("/vendor/scintilla/src/EditModel.cxx").path,
    sdkPath("/vendor/scintilla/src/Editor.cxx").path,
    sdkPath("/vendor/scintilla/src/EditView.cxx").path,
    sdkPath("/vendor/scintilla/src/ExternalLexer.cxx").path,
    sdkPath("/vendor/scintilla/src/Indicator.cxx").path,
    sdkPath("/vendor/scintilla/src/KeyMap.cxx").path,
    sdkPath("/vendor/scintilla/src/LineMarker.cxx").path,
    sdkPath("/vendor/scintilla/src/MarginView.cxx").path,
    sdkPath("/vendor/scintilla/src/PerLine.cxx").path,
    sdkPath("/vendor/scintilla/src/PositionCache.cxx").path,
    sdkPath("/vendor/scintilla/src/RESearch.cxx").path,
    sdkPath("/vendor/scintilla/src/RunStyles.cxx").path,
    sdkPath("/vendor/scintilla/src/ScintillaBase.cxx").path,
    sdkPath("/vendor/scintilla/src/Selection.cxx").path,
    sdkPath("/vendor/scintilla/src/Style.cxx").path,
    sdkPath("/vendor/scintilla/src/UniConversion.cxx").path,
    sdkPath("/vendor/scintilla/src/ViewStyle.cxx").path,
    sdkPath("/vendor/scintilla/src/XPM.cxx").path,
};

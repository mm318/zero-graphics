const std = @import("std");
const types = @import("zero-graphics.zig");
const logger = std.log.scoped(.user_interface);

const Point = types.Point;
const Size = types.Size;
const Rectangle = types.Rectangle;
const Color = types.Color;

const ResourceManager = @import("rendering/ResourceManager.zig");
const Renderer = @import("rendering/Renderer2D.zig");

const Texture = ResourceManager.Texture;

// layout helpers

pub const VerticalStackLayout = @import("ui/VerticalStackLayout.zig");
pub const HorizontalStackLayout = @import("ui/HorizontalStackLayout.zig");
pub const DockLayout = @import("ui/DockLayout.zig");

/// A text editor base that allows implementing visual text editors on top of.
/// Provides a cursor-based editing interface.
pub const TextEditor = @import("TextEditor");

pub const CustomWidget = Widget.Custom;

pub const ButtonStyle = struct {
    border: Color,
    background: Color,
    text_color: Color,
};

pub const BoxStyle = struct {
    border: Color,
    background: Color,
};

pub const LabelStyle = struct {
    text_color: Color,
};

pub const ModalLayerStyle = struct {
    fill_color: Color,
};

pub const ButtonTheme = struct {
    icon_size: u15,
    default: ButtonStyle,
    clicked: ButtonStyle,
    hovered: ButtonStyle,
    disabled: ButtonStyle,
};

pub const TextBoxTheme = struct {
    default: BoxStyle,
    focused: BoxStyle,
};

pub const Theme = struct {
    fn rgb(comptime str: *const [6]u8) Color {
        return Color{
            .r = std.fmt.parseInt(u8, str[0..2], 16) catch unreachable,
            .g = std.fmt.parseInt(u8, str[2..4], 16) catch unreachable,
            .b = std.fmt.parseInt(u8, str[4..6], 16) catch unreachable,
        };
    }

    fn rgba(comptime str: *const [6]u8, alpha: f32) Color {
        var color = rgb(str);
        color.a = @floatToInt(u8, 255.0 * alpha);
        return color;
    }

    button: ButtonTheme,
    panel: BoxStyle,
    text_box: TextBoxTheme,
    label: LabelStyle,
    modal_layer: ModalLayerStyle,

    pub const default = Theme{
        .button = ButtonTheme{
            .icon_size = 24,
            .default = ButtonStyle{
                .border = rgb("cccccc"),
                .background = rgb("303030"),
                .text_color = Color.white,
            },
            .hovered = ButtonStyle{
                .border = rgb("ffffff"),
                .background = rgb("404040"),
                .text_color = Color.white,
            },
            .clicked = ButtonStyle{
                .border = rgb("ffffff"),
                .background = rgb("202020"),
                .text_color = Color.white,
            },
            .disabled = ButtonStyle{
                .border = rgb("888888"),
                .background = rgb("303030"),
                .text_color = rgb("cccccc"),
            },
        },

        .panel = BoxStyle{
            .border = rgb("cccccc"),
            .background = rgb("303030"),
        },

        .text_box = TextBoxTheme{
            .default = BoxStyle{
                .border = rgb("cccccc"),
                .background = rgb("303030"),
            },
            .focused = BoxStyle{
                .border = rgb("3b4898"),
                .background = rgb("303030"),
            },
        },

        .label = LabelStyle{
            .text_color = rgb("ffffff"),
        },

        .modal_layer = ModalLayerStyle{
            .fill_color = rgba("808080", 0.25),
        },
    };
};

const WidgetID = enum(u32) { _ };

const Widget = struct {
    // Control state:
    id: WidgetID,
    control: Control,
    bounds: Rectangle,

    const Control = union(enum) {
        unset,
        modal_layer: ModalLayer,
        image: Image,
        panel: Panel,
        button: Button,
        text_box: TextBox,
        label: Label,
        check_box: CheckBox,
        radio_button: RadioButton,
        custom: Custom,
    };

    fn deinit(self: *Widget) void {
        switch (self.control) {
            .unset => {},
            .panel => {},
            .button => |*ctrl| {
                ctrl.text.deinit();
            },
            .text_box => |*ctrl| {
                ctrl.editor.deinit();
            },
            .label => |*ctrl| {
                ctrl.text.deinit();
            },
            .check_box => {},
            .radio_button => {},
            .image => {},
            .custom => {},
            .modal_layer => {},
        }
        self.* = undefined;
    }

    pub fn isHitTestVisible(self: Widget) bool {
        return switch (self.control) {
            .unset => unreachable,
            .panel => |ctrl| ctrl.config.hit_test_visible,
            .button => |ctrl| ctrl.config.hit_test_visible,
            .text_box => |ctrl| ctrl.config.hit_test_visible,
            .label => |ctrl| ctrl.config.hit_test_visible,
            .check_box => |ctrl| ctrl.config.hit_test_visible,
            .radio_button => |ctrl| ctrl.config.hit_test_visible,
            .image => |ctrl| ctrl.config.hit_test_visible,
            .modal_layer => |ctrl| ctrl.config.hit_test_visible,
            .custom => |custom| custom.config.hit_test_visible,
        };
    }

    pub fn click(self: *Widget, ui: *UserInterface, point: Point) void {
        switch (self.control) {
            .button => |*control| {
                if (control.config.enabled) {
                    control.clickable.clicked = true;
                }
            },
            .check_box => |*control| {
                if (control.config.enabled) {
                    control.clickable.clicked = true;
                }
            },
            .radio_button => |*control| {
                if (control.config.enabled) {
                    control.clickable.clicked = true;
                }
            },
            .modal_layer => |*control| {
                control.clickable.clicked = true;
            },
            .text_box => |*control| {
                const EditorFont = struct {
                    renderer: *Renderer,
                    font: *const Renderer.Font,

                    pub fn measureStringWidth(ef: @This(), string: []const u8) u15 {
                        return ef.renderer.measureString(ef.font, string).width;
                    }
                };
                // TODO: Expose user interface in this function
                logger.info("click @ {},{}", .{
                    point.x - self.bounds.x - 7,
                    point.y - self.bounds.y,
                });
                control.editor.setGraphicalCursor(
                    EditorFont{
                        .renderer = ui.renderer orelse return,
                        .font = ui.default_font, // TODO: Select correct font for checkbox
                    },
                    point.x - self.bounds.x - 7, // TODO: Adjust to real padding value
                    point.y - self.bounds.y,
                );
            },
            else => {},
        }
    }

    ///invoked when the widget is getting focus
    fn enter(widget: *Widget, ui: *UserInterface) void {
        _ = ui;
        switch (widget.control) {
            .text_box => |*control| {
                control.events.insert(.enter);
            },
            else => {},
        }
    }

    ///invoked when the widget is losing focus
    fn leave(widget: *Widget, ui: *UserInterface) void {
        _ = ui;
        switch (widget.control) {
            .text_box => |*control| {
                control.events.insert(.leave);
            },
            else => {},
        }
    }

    pub fn sendEvent(self: *Widget, event: Custom.Event) void {
        if (self.control == .custom) {
            if (self.control.custom.config.process_event) |process_event| {
                self.control.custom.result = process_event(self.control.custom, event) orelse self.control.custom.result;
            }
        }
    }

    const EmptyConfig = struct {
        hit_test_visible: bool = true,
    };

    const Clickable = struct {
        clicked: bool = false,
    };

    const Button = struct {
        pub const Config = struct {
            const IconPosition = enum {
                above_text,
                below_text,
                left,
                right,
            };

            text_color: ?types.Color = null,
            font: ?*const Renderer.Font = null,
            icon_location: IconPosition = .left,
            enabled: bool = true,
            style: ?ButtonTheme = null,
            hit_test_visible: bool = true,
        };
        text: StringBuffer,
        icon: ?*Texture,
        config: Config = .{},
        clickable: Clickable = .{},
    };

    const ModalLayer = struct {
        const Config = struct {
            style: ?ModalLayerStyle = null,
            hit_test_visible: bool = true,
        };

        config: Config = .{},
        clickable: Clickable = .{},
    };

    const Panel = struct {
        const Config = struct {
            style: ?BoxStyle = null,
            hit_test_visible: bool = true,
        };

        config: Config = .{},
    };
    const Image = struct {
        pub const Config = struct {
            tint: ?types.Color = null,
            hit_test_visible: bool = true,
            source_rect: ?Rectangle = null,
        };
        image: *Texture,
        config: Config = .{},
    };
    const TextBox = struct {
        const Config = struct {
            style: ?TextBoxTheme = null,
            hit_test_visible: bool = true,
            accept_tabs: bool = false,
            accept_return: bool = false,
        };
        const Event = enum { accepted, enter, leave, cancelled, text_changed };

        editor: TextEditor,
        content_hash: StringHash = StringHash.compute(""),

        ctrl_pressed: bool = false,

        events: std.enums.EnumSet(Event) = std.enums.EnumSet(Event){},

        config: Config = .{},
    };
    const Label = struct {
        pub const Config = struct {
            style: ?LabelStyle = null,
            text_color: ?types.Color = null,
            font: ?*const Renderer.Font = null,
            vertical_alignment: types.VerticalAlignment = .center,
            horizontal_alignment: types.HorzizontalAlignment = .left,
            hit_test_visible: bool = false,
        };

        text: StringBuffer,
        config: Config = .{},
    };
    const CheckBox = struct {
        const Config = struct {
            enabled: bool = true,
            hit_test_visible: bool = true,
        };
        is_checked: bool,
        clickable: Clickable = .{},
        config: Config = .{},
    };
    const RadioButton = struct {
        const Config = struct {
            enabled: bool = true,
            hit_test_visible: bool = true,
        };
        is_checked: bool,
        clickable: Clickable = .{},
        config: Config = .{},
    };
    const Custom = struct {
        pub const Event = union(enum) {
            pub const PointerRelease = struct {
                position: Point,
                pointer: Pointer,
                hit_test_visible: bool = true,
            };

            pointer_enter,
            pointer_leave,
            pointer_press: Point,
            pointer_release: PointerRelease,
            pointer_motion: Point,
        };

        pub const DrawInfo = struct {
            is_hovered: bool,
            is_pressed: bool,
            hit_test_visible: bool = true,
        };

        pub const Config = struct {
            hit_test_visible: bool = true,
            draw: ?fn (Custom, Rectangle, *Renderer, DrawInfo) Renderer.DrawError!void = null,
            process_event: ?fn (Custom, Event) ?usize = null,
            /// generic second user data to provide context information for the user data
            context: ?*anyopaque = null,
        };
        config: Config = .{},
        /// User data passed to the builder.custom call.
        user_data: ?*anyopaque,
        result: ?usize = null,
    };
};

const ControlType = std.meta.Tag(Widget.Control);

const WidgetList = std.TailQueue(Widget);
const WidgetNode = std.TailQueue(Widget).Node;

const UserInterface = @This();

const ProcessingMode = enum { default, updating, building };

const Icons = struct {
    checkbox_unchecked: *Texture,
    checkbox_checked: *Texture,
    radiobutton_unchecked: *Texture,
    radiobutton_checked: *Texture,
};

allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

/// The current mode. This is used to interlock building and updating APIs
mode: ProcessingMode = .default,

/// Contains the sequence of widgets that were created between
/// `.begin()` and `.end()`. All widgets in this list are active in
/// the current frame.
active_widgets: WidgetList = .{},

/// Contains the list of all widgets that were available in the last
/// frame. Widgets in here have valid `.data` and might be re-used in
/// the current frame. This allows keeping state over several frames.
retained_widgets: WidgetList = .{},

/// Contains nodes that are not used right now and free for allocation
/// `WidgetNode.data` contains garbage and must be freshly initialized.
free_widgets: WidgetList = .{},

/// The theme that is used to render the UI.
/// Contains all colors and sizes for widgets.
theme: *const Theme = &Theme.default,

/// The default font the renderer will use to render text in its widgets.
default_font: *const Renderer.Font,

/// Current location of the mouse cursor or finger
pointer_position: Point,

/// When the pointer is pressed, the widget is saved until the pointer
/// is released. When the pointer is released over the previously pressed widget,
/// we recognize this as a click.
pressed_widget: ?*Widget = null,

/// The widget which is currently hovered by the pointer.
hovered_widget: ?*Widget = null,

/// The widget that is currently having the keyboard focus.
/// Use `focusWidget` function to set this field, as there is logic that must be executed.
focused_widget: ?*Widget = null,

renderer: ?*Renderer,

icons: Icons,

pub fn init(allocator: std.mem.Allocator, renderer: ?*Renderer) !UserInterface {
    var ui = UserInterface{
        .renderer = null,
        .default_font = undefined,
        .icons = undefined,
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .pointer_position = Point{
            .x = std.math.minInt(i16),
            .y = std.math.minInt(i16),
        },
    };

    try ui.setRenderer(renderer);

    return ui;
}

pub fn deinit(self: *UserInterface) void {
    while (self.active_widgets.popFirst()) |node| {
        node.data.deinit();
    }
    while (self.free_widgets.popFirst()) |node| {
        // node.data.deinit();
        _ = node;
    }

    self.setRenderer(null) catch unreachable; // can only error when non-null is passed

    self.arena.deinit();
    self.* = undefined;
}

pub fn setRenderer(self: *UserInterface, new_renderer: ?*Renderer) !void {
    if (self.renderer == new_renderer)
        return;

    if (self.renderer) |renderer| {
        renderer.resources.destroyTexture(self.icons.checkbox_checked);
        renderer.resources.destroyTexture(self.icons.checkbox_unchecked);
        renderer.resources.destroyTexture(self.icons.radiobutton_checked);
        renderer.resources.destroyTexture(self.icons.radiobutton_unchecked);
        renderer.destroyFont(self.default_font);
    }

    self.renderer = new_renderer;

    if (self.renderer) |renderer| {
        errdefer self.renderer = null;

        const default_font = try renderer.createFont(@embedFile("ui-data/FiraSans-Regular.ttf"), 16);
        errdefer renderer.destroyFont(default_font);

        var icons = Icons{
            .checkbox_unchecked = undefined,
            .checkbox_checked = undefined,
            .radiobutton_unchecked = undefined,
            .radiobutton_checked = undefined,
        };

        icons.checkbox_checked = try renderer.resources.createTexture(.ui, ResourceManager.DecodePng{
            .data = @embedFile("ui-data/checkbox-marked.png"),
        });
        errdefer renderer.resources.destroyTexture(icons.checkbox_checked);

        icons.checkbox_unchecked = try renderer.resources.createTexture(.ui, ResourceManager.DecodePng{
            .data = @embedFile("ui-data/checkbox-blank.png"),
        });
        errdefer renderer.resources.destroyTexture(icons.checkbox_unchecked);

        icons.radiobutton_checked = try renderer.resources.createTexture(.ui, ResourceManager.DecodePng{
            .data = @embedFile("ui-data/radiobox-marked.png"),
        });
        errdefer renderer.resources.destroyTexture(icons.radiobutton_checked);

        icons.radiobutton_unchecked = try renderer.resources.createTexture(.ui, ResourceManager.DecodePng{
            .data = @embedFile("ui-data/radiobox-blank.png"),
        });
        errdefer renderer.resources.destroyTexture(icons.radiobutton_unchecked);

        self.default_font = default_font;
        self.icons = icons;
    }
}

/// Allocates a new WidgetNode, either via the arena or
/// fetches it from the free_widgets list
fn allocWidgetNode(self: *UserInterface) !*WidgetNode {
    const node = if (self.free_widgets.popFirst()) |n|
        n
    else
        try self.arena.allocator().create(WidgetNode);
    node.* = .{
        .data = undefined,
    };
    return node;
}

/// Marks the WidgetNode as invalid and moves it into the free_widgets list for
/// later reallocation.
fn freeWidgetNode(self: *UserInterface, node: *WidgetNode) void {
    node.data = undefined;
    self.free_widgets.append(node);
}

/// Fetches a fitting widget from the `retained_widgets` list or creates a new node.
/// On success, the widget is appended to the `active_widgets` list.
fn findOrAllocWidget(self: *UserInterface, widget_type: ControlType, id: WidgetID) !*Widget {
    var it = self.retained_widgets.first;
    while (it) |node| : (it = node.next) {
        if (node.data.id == id) {
            // When this assertion is true, we created the same ID twice
            // for different widget invocations. This means we must increase the number of bits
            // in WidgetID and adjust our hash function
            std.debug.assert(node.data.control == widget_type);

            // Shuffle from one list into the other:
            self.retained_widgets.remove(node);
            self.active_widgets.append(node);

            return &node.data;
        }
    }

    const node = try self.allocWidgetNode();
    node.data = Widget{
        .id = id,
        .control = .unset,
        .bounds = undefined,
    };
    self.active_widgets.append(node);
    return &node.data;
}

/// Returns a unqiue identifier for each type.
fn typeId(comptime T: type) usize {
    _ = T;
    return comptime @ptrToInt(&struct {
        var i: u8 = 0;
    }.i);
}

/// Computes a adler32 ID from the
fn widgetId(config: anytype) WidgetID {
    const Config = @TypeOf(config);

    var hash = std.hash.Adler32.init();
    hash.update(std.mem.asBytes(&typeId(Config)));
    if (@hasField(Config, "id"))
        hash.update(std.mem.asBytes(&config.id));

    return @intToEnum(WidgetID, hash.final());
}

fn updateWidgetConfig(dst_config: anytype, src_config: anytype) void {
    inline for (std.meta.fields(@TypeOf(src_config))) |fld| {
        if (comptime !std.mem.eql(u8, fld.name, "id")) {
            @field(dst_config, fld.name) = @field(src_config, fld.name);
        }
    }
}

/// Starts a UI pass and collects widgets. The return value can be used to create new widgets.
/// Call `finish()` on the returned builder to complete the construction.
/// Widgets are then created with calls to `.button`, `.textBox`, ... until `.finish()` is called.
pub fn construct(self: *UserInterface, screen_size: Size) Builder {
    std.debug.assert(self.mode == .default);
    self.mode = .building;

    // Moves all active widgets into the retained storage.
    // Widgets will be pulled from there when reused, otherwise will be destroyed in `.end()`.
    while (self.active_widgets.popFirst()) |node| {
        self.retained_widgets.append(node);
    }

    return Builder{
        .ui = self,
        .screen_size = screen_size,
    };
}

pub const Builder = struct {
    const Self = @This();

    pub const Error = error{
        OutOfMemory,
        InvalidUtf8,
    };

    ui: *UserInterface,
    screen_size: Size,

    /// Ends the UI construction pass and stops collecting widgets.
    /// Will destroy all remaining widgets in `retained_widgets`
    /// that are left, as those must be recreated when used the next time.
    pub fn finish(self: *Self) void {
        std.debug.assert(self.ui.mode == .building);
        self.ui.mode = .default;

        while (self.ui.retained_widgets.popFirst()) |node| {
            node.data.deinit();
            self.ui.freeWidgetNode(node);
        }

        self.* = undefined;
    }

    fn InitOrUpdateWidget(comptime widget: ControlType) type {
        return struct {
            pub const Control = blk: {
                inline for (std.meta.fields(Widget.Control)) |fld| {
                    if (std.mem.eql(u8, fld.name, @tagName(widget)))
                        break :blk fld.field_type;
                }
                @compileError("Unknown widget type:");
            };

            widget: *Widget,
            control: *Control,
            needs_init: bool,
        };
    }

    fn initOrUpdateWidget(self: Self, comptime control_type: ControlType, rectangle: Rectangle, config: anytype) !InitOrUpdateWidget(control_type) {
        const widget = try self.ui.findOrAllocWidget(control_type, widgetId(config));
        widget.bounds = rectangle;

        const needs_init = (widget.control == .unset);
        const control = switch (widget.control) {
            // fresh widget
            .unset => blk: {
                widget.control = @unionInit(Widget.Control, @tagName(control_type), undefined);
                break :blk &@field(widget.control, @tagName(control_type));
            },
            control_type => |*ctrl| ctrl,
            else => unreachable,
        };

        return InitOrUpdateWidget(control_type){
            .widget = widget,
            .control = control,
            .needs_init = needs_init,
        };
    }

    fn processClickable(clickable: *Widget.Clickable) bool {
        const clicked = clickable.clicked;
        clickable.clicked = false;
        return clicked;
    }

    pub fn panel(self: Self, rectangle: Rectangle, config: anytype) Error!void {
        const info = try self.initOrUpdateWidget(.panel, rectangle, config);
        if (info.needs_init) {
            info.control.* = .{};
        }
        updateWidgetConfig(&info.control.config, config);
    }

    pub fn modalLayer(self: Self, config: anytype) Error!bool {
        const info = try self.initOrUpdateWidget(.modal_layer, Rectangle.init(Point.zero, self.screen_size), config);
        if (info.needs_init) {
            info.control.* = .{};
        }

        updateWidgetConfig(&info.control.config, config);

        return processClickable(&info.control.clickable);
    }

    /// Creates a button at the provided position that will display `text` as
    pub fn button(self: Self, rectangle: Rectangle, text: ?[]const u8, icon: ?*Texture, config: anytype) Error!bool {
        const info = try self.initOrUpdateWidget(.button, rectangle, config);
        if (info.needs_init) {
            info.control.* = .{
                .text = try StringBuffer.init(self.ui.allocator, text orelse ""),
                .icon = icon,
            };
        } else {
            try info.control.text.set(self.ui.allocator, text orelse "");
            info.control.icon = icon;
        }

        updateWidgetConfig(&info.control.config, config);

        return processClickable(&info.control.clickable);
    }

    pub fn checkBox(self: Self, rectangle: Rectangle, is_checked: bool, config: anytype) Error!bool {
        const info = try self.initOrUpdateWidget(.check_box, rectangle, config);
        if (info.needs_init) {
            info.control.* = .{
                .is_checked = is_checked,
            };
        } else {
            info.control.is_checked = is_checked;
        }

        updateWidgetConfig(&info.control.config, config);

        return processClickable(&info.control.clickable);
    }

    pub fn radioButton(self: Self, rectangle: Rectangle, is_checked: bool, config: anytype) Error!bool {
        const info = try self.initOrUpdateWidget(.radio_button, rectangle, config);
        if (info.needs_init) {
            info.control.* = .{
                .is_checked = is_checked,
            };
        } else {
            info.control.is_checked = is_checked;
        }

        updateWidgetConfig(&info.control.config, config);

        return processClickable(&info.control.clickable);
    }

    pub fn label(self: Self, rectangle: Rectangle, text: []const u8, config: anytype) Error!void {
        const info = try self.initOrUpdateWidget(.label, rectangle, config);

        if (info.needs_init) {
            info.control.* = .{
                .text = try StringBuffer.init(self.ui.allocator, text),
            };
        } else {
            try info.control.text.set(self.ui.allocator, text);
        }
        updateWidgetConfig(&info.control.config, config);
    }

    pub fn image(self: Self, rectangle: Rectangle, texture: *ResourceManager.Texture, config: anytype) Error!void {
        const info = try self.initOrUpdateWidget(.image, rectangle, config);

        if (info.needs_init) {
            info.control.* = .{
                .image = texture,
            };
        } else {
            info.control.image = texture;
        }
        updateWidgetConfig(&info.control.config, config);
    }

    pub fn custom(self: Self, rectangle: Rectangle, user_data: ?*anyopaque, config: anytype) Error!?usize {
        const info = try self.initOrUpdateWidget(.custom, rectangle, config);

        if (info.needs_init) {
            info.control.* = .{
                .user_data = user_data,
            };
        } else {
            info.control.user_data = user_data;
        }
        updateWidgetConfig(&info.control.config, config);

        const result = info.control.result;
        info.control.result = null;
        return result;
    }

    pub const TextBoxEvent = union(enum) {
        focus_lost: []const u8,
        text_changed: []const u8,
        user_accept: []const u8,
        user_clear,
    };
    pub fn textBox(self: Self, rectangle: Rectangle, display_string: []const u8, config: anytype) Error!?TextBoxEvent {
        const info = try self.initOrUpdateWidget(.text_box, rectangle, config);
        const text_box: *Widget.TextBox = info.control;

        // reset all events at the end of this
        defer text_box.events = std.enums.EnumSet(Widget.TextBox.Event){}; // clear

        const display_hash = StringHash.compute(display_string);

        if (info.needs_init) {
            info.control.* = .{
                .editor = try TextEditor.init(self.ui.allocator, display_string),
                .content_hash = display_hash,
            };
        } else {

            // clear text box to default when ESC is pressed or the input string changes
            if ((text_box.content_hash != display_hash) or text_box.events.contains(.cancelled)) {
                logger.info("updating text box content to {s}", .{display_string});
                try text_box.editor.setText(display_string);
                text_box.content_hash = display_hash;
            }
        }
        updateWidgetConfig(&text_box.config, config);

        if (text_box.events.contains(.cancelled)) {
            return TextBoxEvent.user_clear;
        }
        if (text_box.events.contains(.accepted)) {
            return TextBoxEvent{ .user_accept = info.control.editor.getText() };
        }
        if (text_box.events.contains(.leave)) {
            return TextBoxEvent{ .focus_lost = info.control.editor.getText() };
        }
        if (text_box.events.contains(.text_changed)) {
            return TextBoxEvent{ .text_changed = info.control.editor.getText() };
        }

        return null;
    }
};

pub fn processInput(self: *UserInterface) InputProcessor {
    std.debug.assert(self.mode == .default);
    self.mode = .updating;
    return InputProcessor{
        .ui = self,
    };
}

fn widgetFromPosition(self: *UserInterface, point: Point) ?*Widget {
    var iter = self.widgetIterator(.event_order);
    while (iter.next()) |widget| {
        if (widget.bounds.contains(point))
            return widget;
    }
    return null;
}

/// The user interface supports two types of pointer input.
/// - The `primary` pointer is the normal touch input or mouse click with the left mouse button. This usually activates the main action of the widget.
/// - The `secondary` pointer is either a long-click for touch/single button inputs or the right mouse button. This usually opens a context menu or similar.
pub const Pointer = types.Input.MouseButton;

pub const InputProcessor = struct {
    const Self = @This();

    ui: *UserInterface,

    pub fn finish(self: *Self) void {
        std.debug.assert(self.ui.mode == .updating);
        self.ui.mode = .default;
        self.* = undefined;
    }

    pub fn setPointer(self: Self, position: Point) void {
        self.ui.pointer_position = position;

        const previous_hovered_widget = self.ui.hovered_widget;
        self.ui.hovered_widget = self.ui.widgetFromPosition(self.ui.pointer_position);

        if (previous_hovered_widget != self.ui.hovered_widget) {
            if (previous_hovered_widget) |w| w.sendEvent(.pointer_leave);
            if (self.ui.hovered_widget) |w| w.sendEvent(.pointer_enter);
        }

        if (self.ui.hovered_widget) |widget| {
            widget.sendEvent(.{ .pointer_motion = self.ui.pointer_position });
        }
    }

    pub fn pointerDown(self: Self) void {
        const clicked_widget = self.ui.widgetFromPosition(self.ui.pointer_position);

        if (clicked_widget) |widget| {
            widget.sendEvent(.{ .pointer_press = self.ui.pointer_position });
        }

        self.ui.pressed_widget = clicked_widget;
    }

    pub fn pointerUp(self: Self, pointer: Pointer) void {
        defer self.ui.pressed_widget = null;

        const clicked_widget = self.ui.widgetFromPosition(self.ui.pointer_position) orelse {
            // clicking on *no* widget unfocused the current one
            self.ui.focusWidget(null);
            return;
        };

        if (self.ui.pressed_widget) |widget| {
            widget.sendEvent(.{ .pointer_release = .{
                .position = self.ui.pointer_position,
                .pointer = pointer,
            } });
        }

        const pressed_widget = self.ui.pressed_widget orelse return;

        if (pointer == .primary and clicked_widget == pressed_widget) {
            // if the widget is clickable, we focus it
            self.ui.focusWidget(clicked_widget);
            clicked_widget.click(self.ui, self.ui.pointer_position);
        }
    }

    fn wordModifier(box: Widget.TextBox) TextEditor.EditUnit {
        return if (box.ctrl_pressed)
            TextEditor.EditUnit.word
        else
            TextEditor.EditUnit.letter;
    }

    pub fn buttonDown(self: Self, button: types.Input.Scancode) !void {
        const active_widget = self.ui.focused_widget orelse return;
        switch (active_widget.control) {
            .text_box => |*control| switch (button) {
                .ctrl_left => control.ctrl_pressed = true,
                .ctrl_right => control.ctrl_pressed = true,
                .@"return" => control.events.insert(.accepted),
                .escape => control.events.insert(.cancelled),
                .tab => {
                    if (control.config.accept_tabs) {
                        try control.editor.insertText("\t");
                        control.events.insert(.text_changed);
                    } else {
                        // TODO: move focus
                    }
                },

                .backspace => {
                    control.editor.delete(.left, wordModifier(control.*));
                    control.events.insert(.text_changed);
                },
                .delete => {
                    control.editor.delete(.right, wordModifier(control.*));
                    control.events.insert(.text_changed);
                },
                .left => control.editor.moveCursor(.left, wordModifier(control.*)),
                .right => control.editor.moveCursor(.right, wordModifier(control.*)),

                .home => control.editor.moveCursor(.left, .line),
                .end => control.editor.moveCursor(.right, .line),
                else => {},
            },
            else => return, // just eat the event by default
        }
    }

    pub fn buttonUp(self: Self, button: types.Input.Scancode) !void {
        const active_widget = self.ui.focused_widget orelse return;
        switch (active_widget.control) {
            .text_box => |*control| switch (button) {
                .ctrl_left => control.ctrl_pressed = false,
                .ctrl_right => control.ctrl_pressed = false,
                else => {},
            },
            else => return, // just eat the event by default
        }
    }

    pub fn enterText(self: Self, string: []const u8) !void {
        const active_widget = self.ui.focused_widget orelse return;

        switch (active_widget.control) {
            // these widgets can be activated by pressing space
            .button, .check_box, .radio_button => for (string) |c| switch (c) {
                ' ' => active_widget.click(self.ui, self.ui.pointer_position),
                else => {}, // ignore everything else
            },

            .text_box => |*control| {
                // these chars cannot be entered via the keyboard
                const filtered_chars = [_]u8{
                    // ASCII control codes
                    0,   1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
                    16,  17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
                    // DELETE
                    127,
                };

                var offset: usize = 0;
                while (offset < string.len) {
                    if (std.mem.indexOfAnyPos(u8, string, offset, &filtered_chars)) |index| {
                        try control.editor.insertText(string[offset..index]);
                        offset = index + 1;

                        control.events.insert(.text_changed);
                    } else {
                        try control.editor.insertText(string[offset..]);
                        offset = string.len;

                        control.events.insert(.text_changed);
                    }
                }

                logger.info("insertText(\"{}\") => \"{}\"", .{
                    std.fmt.fmtSliceEscapeUpper(string),
                    std.fmt.fmtSliceEscapeUpper(control.editor.getText()),
                });
            },

            else => return, // just eat the event by default
        }
    }
};

fn clampSub(a: u15, b: u15) u15 {
    return if (b < a)
        a - b
    else
        0;
}

fn isFocused(self: UserInterface, widget: *Widget) bool {
    return (self.focused_widget == widget);
}

fn focusWidget(self: *UserInterface, widget: ?*Widget) void {
    if (self.focused_widget) |focus| {
        focus.leave(self);
    }
    self.focused_widget = widget;
    if (self.focused_widget) |focus| {
        focus.enter(self);
    }
}

pub fn hasFocus(self: UserInterface) bool {
    return (self.focused_widget != null);
}

pub fn render(self: UserInterface) !void {
    const renderer = self.renderer orelse @panic("usage error");
    var iterator = self.widgetIterator(.draw_order);
    while (iterator.next()) |widget| {
        const is_hovered = (self.hovered_widget == widget);
        const is_pressed = is_hovered and (self.pressed_widget == widget);

        switch (widget.control) {
            // unset is only required for allocating fresh nodes and then initialize them properly in the
            // corresponding widget function
            .unset => unreachable,

            .modal_layer => |control| {
                const style = control.config.style orelse self.theme.modal_layer;
                try renderer.fillRectangle(widget.bounds, style.fill_color);
            },

            .button => |control| {
                const style = control.config.style orelse self.theme.button;

                const style_info = if (!control.config.enabled)
                    style.disabled
                else if (is_pressed)
                    style.clicked
                else if (is_hovered)
                    style.hovered
                else
                    style.default;

                try renderer.fillRectangle(widget.bounds, style_info.background);
                try renderer.drawRectangle(widget.bounds, style_info.border);

                if (control.icon) |icon| {
                    try renderer.drawTexture(
                        widget.bounds.centered(style.icon_size, style.icon_size),
                        icon,
                        Color.white,
                    );
                }

                const text = control.text.get();
                if (text.len > 0) {
                    const font = control.config.font orelse self.default_font;
                    const string_size = renderer.measureString(font, control.text.get());
                    try renderer.drawString(
                        font,
                        control.text.get(),
                        widget.bounds.x + @divTrunc((@as(i16, widget.bounds.width) - string_size.width), 2),
                        widget.bounds.y + @divTrunc((@as(i16, widget.bounds.height) - string_size.height), 2),
                        control.config.text_color orelse style_info.text_color,
                    );
                }
            },

            .panel => |control| {
                const style = control.config.style orelse self.theme.panel;
                try renderer.fillRectangle(widget.bounds, style.background);
                try renderer.drawRectangle(widget.bounds, style.border);
            },

            .text_box => |control| {
                const theme = control.config.style orelse self.theme.text_box;

                const style = if (self.isFocused(widget))
                    theme.focused
                else
                    theme.default;

                try renderer.fillRectangle(widget.bounds, style.background);
                try renderer.drawRectangle(widget.bounds, style.border);

                const string = control.editor.getText();
                const font = self.default_font;
                const string_height = font.getLineHeight();

                try renderer.drawString(
                    font,
                    string,
                    widget.bounds.x + 3,
                    widget.bounds.y + clampSub(widget.bounds.height, string_height) / 2,
                    Color.white,
                );

                if (self.isFocused(widget)) {
                    const cursor_prefix = control.editor.getSubString(0, control.editor.cursor);

                    const string_width = renderer.measureString(font, cursor_prefix).width;

                    const blink_period = 800;
                    const timer = @mod(types.milliTimestamp(), blink_period);
                    if (timer >= blink_period / 2) {
                        try renderer.drawLine(
                            widget.bounds.x + 4 + string_width,
                            widget.bounds.y + clampSub(widget.bounds.height, string_height) / 2,
                            widget.bounds.x + 4 + string_width,
                            widget.bounds.y + (widget.bounds.height + string_height) / 2,
                            Color.white,
                        );
                    }
                }
            },
            .label => |control| {
                const style = control.config.style orelse self.theme.label;

                const font = control.config.font orelse self.default_font;
                const string_size = renderer.measureString(font, control.text.get());
                try renderer.drawString(
                    font,
                    control.text.get(),
                    widget.bounds.x + switch (control.config.horizontal_alignment) {
                        .left => 0,
                        .center => clampSub(widget.bounds.width, string_size.width) / 2,
                        .right => clampSub(clampSub(widget.bounds.width, 4), string_size.width),
                    },
                    widget.bounds.y + switch (control.config.vertical_alignment) {
                        .top => 0,
                        .center => clampSub(widget.bounds.height, string_size.height) / 2,
                        .bottom => clampSub(widget.bounds.height, string_size.height),
                    },
                    control.config.text_color orelse style.text_color,
                );
            },
            .check_box => |control| {
                try renderer.drawTexture(
                    widget.bounds,
                    if (control.is_checked)
                        self.icons.checkbox_checked
                    else
                        self.icons.checkbox_unchecked,
                    if (control.config.enabled) Color.white else Color.gray(0x80),
                );
            },
            .radio_button => |control| {
                try renderer.drawTexture(
                    widget.bounds,
                    if (control.is_checked)
                        self.icons.radiobutton_checked
                    else
                        self.icons.radiobutton_unchecked,
                    if (control.config.enabled) Color.white else Color.gray(0x80),
                );
            },
            .image => |control| {
                if (control.config.source_rect) |source_rect| {
                    try renderer.drawPartialTexture(
                        widget.bounds,
                        control.image,
                        source_rect,
                        control.config.tint orelse types.Color.white,
                    );
                } else {
                    try renderer.drawTexture(
                        widget.bounds,
                        control.image,
                        control.config.tint orelse types.Color.white,
                    );
                }
            },
            .custom => |control| {
                if (control.config.draw) |draw| {
                    try draw(control, widget.bounds, renderer, .{
                        .is_hovered = is_hovered,
                        .is_pressed = is_pressed,
                    });
                }
            },
        }
    }
}

const WidgetOrder = enum { draw_order, event_order };

fn widgetIterator(self: UserInterface, order: WidgetOrder) WidgetIterator {
    return switch (order) {
        .draw_order => WidgetIterator{
            .order = .draw_order,
            .it = self.active_widgets.first,
        },
        .event_order => WidgetIterator{
            .order = .event_order,
            .it = self.active_widgets.last,
        },
    };
}

const WidgetIterator = struct {
    order: WidgetOrder,
    it: ?*WidgetNode,

    pub fn next(self: *@This()) ?*Widget {
        while (true) {
            const result = self.it;
            if (result) |node| {
                self.it = switch (self.order) {
                    .draw_order => node.next,
                    .event_order => node.prev,
                };

                if (self.order == .event_order) {
                    // don't iterate over widgets that cannot receive events
                    if (!node.data.isHitTestVisible())
                        continue;
                }
                return &node.data;
            } else {
                return null;
            }
        }
    }
};

fn getListLength(list: WidgetList) usize {
    var it = list.first;
    var len: usize = 0;
    while (it) |node| : (it = node.next) {
        len += 1;
    }
    return len;
}

test "basic widget collection" {
    var ui = init(std.testing.allocator);
    defer ui.deinit();

    {
        ui.begin();
        defer ui.end();

        _ = try ui.button(undefined, "Cancel", .{});
        _ = try ui.button(undefined, "Ok", .{});

        var i: usize = 0;
        while (i < 3) : (i += 1) {
            _ = try ui.button(undefined, "List Button", .{ .id = i });
        }
        try ui.label(undefined, "Hello", .{});
    }
    try std.testing.expectEqual(@as(usize, 0), getListLength(ui.retained_widgets));
    try std.testing.expectEqual(@as(usize, 0), getListLength(ui.free_widgets));
    try std.testing.expectEqual(@as(usize, 6), getListLength(ui.active_widgets));
}

test "widget re-collection" {

    // Tests if widgets are properly re-collected in consecutive loops, even
    // if not all widgets are reused

    var ui = init(std.testing.allocator);
    defer ui.deinit();

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        {
            ui.begin();
            defer ui.end();

            if (i == 0) {
                _ = try ui.button(undefined, "Ok", .{});
                _ = try ui.button(undefined, "Cancel", .{});
            }

            var j: usize = 0;
            while (j < 3) : (j += 1) {
                _ = try ui.button(undefined, "Listed Button", .{ .id = j });
            }
            try ui.label(undefined, "Hello", .{});

            if (i == 1) {
                // test that the two buttons from the first frame are properly retained until the end,
                // and then freed:
                try std.testing.expectEqual(@as(usize, 2), getListLength(ui.retained_widgets));
            }
        }

        // Retained must always be empty after ui.end()!
        try std.testing.expectEqual(@as(usize, 0), getListLength(ui.retained_widgets));

        if (i == 0) {
            try std.testing.expectEqual(@as(usize, 0), getListLength(ui.free_widgets));
            try std.testing.expectEqual(@as(usize, 6), getListLength(ui.active_widgets));
        } else {
            try std.testing.expectEqual(@as(usize, 2), getListLength(ui.free_widgets)); // two conditional widgets
            try std.testing.expectEqual(@as(usize, 4), getListLength(ui.active_widgets)); // four unconditional widgets
        }
    }
}

/// A dynamic, potentially allocated string buffer that can store texts.
const StringBuffer = union(enum) {
    const Self = @This();

    self_contained: ArrayBuffer,
    allocated: std.ArrayList(u8),

    const ArrayBuffer = struct {
        const max_len = 3 * @sizeOf(usize);
        len: usize,
        items: [max_len]u8,
    };

    pub fn init(allocator: std.mem.Allocator, string: []const u8) !Self {
        var self = Self{ .self_contained = undefined };
        try self.set(allocator, string);
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.* == .allocated) {
            self.allocated.deinit();
        }
        self.* = undefined;
    }

    pub fn get(self: *const Self) []const u8 {
        return switch (self.*) {
            .allocated => |*list| list.items,
            .self_contained => |*str| str.items[0..str.len],
        };
    }

    pub fn set(self: *Self, allocator: std.mem.Allocator, string: []const u8) !void {
        switch (self.*) {
            .allocated => |*list| {
                try list.resize(string.len);
                std.mem.copy(u8, list.items, string);
            },
            else => {
                if (string.len <= ArrayBuffer.max_len) {
                    self.* = Self{
                        .self_contained = .{
                            .items = undefined,
                            .len = string.len,
                        },
                    };
                    std.mem.copy(u8, self.self_contained.items[0..string.len], string);
                } else {
                    self.* = Self{
                        .allocated = std.ArrayList(u8).init(allocator),
                    };
                    try self.allocated.resize(string.len);
                    std.mem.copy(u8, self.allocated.items, string);
                }
            },
        }
    }

    pub fn shrink(self: *Self, new_length: usize) void {
        switch (self.*) {
            .allocated => |*list| list.shrinkRetainingCapacity(new_length),
            .self_contained => |*buf| {
                std.debug.assert(buf.len >= new_length);
                buf.len = new_length;
            },
        }
    }

    pub fn format(self: StringBuffer, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("\"{}\"", .{std.fmt.fmtSliceEscapeUpper(self.get())});
    }
};

test "StringBuffer" {
    var buf = try StringBuffer.init(std.testing.allocator, "Hello");
    defer buf.deinit();

    try std.testing.expectEqualStrings("Hello", buf.get());

    try buf.set(std.testing.allocator, "");
    try std.testing.expectEqualStrings("", buf.get());

    const long_string = "Hello, i am a very long string that is self-contained and should probably exceed the length of a StringBuffer by far!";
    try buf.set(std.testing.allocator, long_string);
    try std.testing.expectEqualStrings(long_string, buf.get());
}

const StringHash = enum(u32) {
    _,

    pub fn compute(string: []const u8) StringHash {
        return @intToEnum(StringHash, std.hash.CityHash32.hash(string));
    }
};

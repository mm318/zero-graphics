const std = @import("std");
const gles = @import("../gl_es_2v0.zig");
const zerog = @import("../zero-graphics.zig");
const Application = @import("application");

comptime {
    // enforce inclusion of "extern  c" implementations
    const common = @import("common.zig");

    // verify the application api
    common.verifyApplication(Application);
}

extern fn wasm_loadOpenGlFunction(function: [*]const u8, function_len: usize) ?*c_void;

extern fn wasm_quit() void;
extern fn wasm_panic(ptr: [*]const u8, len: usize) void;
extern fn wasm_log_write(ptr: [*]const u8, len: usize) void;
extern fn wasm_log_flush() void;
extern fn wasm_getScreenW() u32;
extern fn wasm_getScreenH() u32;
extern fn now_f64() f64;

pub const log_level = .info;

var app_instance: Application = undefined;
var input_handler: zerog.Input = undefined;

var global_arena: std.heap.ArenaAllocator = undefined;
var gpa: std.heap.GeneralPurposeAllocator(.{
    .safety = false,
}) = undefined;

const WriteError = error{};
const LogWriter = std.io.Writer(void, WriteError, writeLog);

fn writeLog(_: void, msg: []const u8) WriteError!usize {
    wasm_log_write(msg.ptr, msg.len);
    return msg.len;
}

pub fn milliTimestamp() i64 {
    return @floatToInt(i64, now_f64());
}

pub fn getDisplayDPI() f32 {
    // TODO: Figure out if browsers can actually report the correct DPI scale
    // for the display.
    // Otherwise, keep 96 as it's the default for all browsers now?
    return 96.0;
}

/// Overwrite default log handler
pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = switch (message_level) {
        .emerg => "emergency",
        .alert => "alert",
        .crit => "critical",
        .err => "error",
        .warn => "warning",
        .notice => "notice",
        .info => "info",
        .debug => "debug",
    };
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    (LogWriter{ .context = {} }).print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;

    wasm_log_flush();
}

/// Overwrite default panic handler
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace) noreturn {
    // std.log.crit("panic: {s}", .{msg});
    wasm_panic(msg.ptr, msg.len);
    unreachable;
}

pub fn loadOpenGlFunction(_: void, function: [:0]const u8) ?*const c_void {
    inline for (std.meta.declarations(WebGL)) |decl| {
        const gl_ep = "gl" ++ [_]u8{std.ascii.toUpper(decl.name[0])} ++ decl.name[1..];
        if (std.mem.eql(u8, gl_ep, function)) {
            return @as(*const c_void, @field(WebGL, decl.name));
        }
    }
    return null;
}

export fn app_init() u32 {
    global_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    gpa = .{
        .backing_allocator = &global_arena.allocator,
    };

    input_handler = zerog.Input.init(&gpa.allocator);

    app_instance.init(&gpa.allocator, &input_handler) catch |err| @panic(@errorName(err));

    gles.load({}, loadOpenGlFunction) catch |err| @panic(@errorName(err));

    app_instance.setupGraphics() catch |err| @panic(@errorName(err));

    app_instance.resize(@intCast(u15, wasm_getScreenW()), @intCast(u15, wasm_getScreenH())) catch return 2;

    return 0;
}

export fn app_update() u32 {
    app_instance.resize(@intCast(u15, wasm_getScreenW()), @intCast(u15, wasm_getScreenH())) catch return 2;

    const res = app_instance.update() catch return 1;
    if (!res)
        wasm_quit();
    app_instance.render() catch return 3;
    return 0;
}

export fn app_deinit() u32 {
    app_instance.teardownGraphics();
    app_instance.deinit();
    input_handler.deinit();
    // _ = gpa.deinit();
    global_arena.deinit();

    return 0;
}

fn unknownOpenGlFunction() void {
    @panic("tried to use unknown opengl function!");
}

const GLuint = gles.GLuint;
const GLenum = gles.GLenum;
const GLfloat = gles.GLfloat;
const GLchar = gles.GLchar;
const GLint = gles.GLint;
const GLboolean = gles.GLboolean;
const GLsizei = gles.GLsizei;
const GLintptr = gles.GLintptr;
const GLubyte = gles.GLubyte;
const GLsizeiptr = gles.GLsizeiptr;
const WebGL = struct {
    pub extern fn activeTexture(target: c_uint) void;
    pub extern fn attachShader(program: c_uint, shader: c_uint) void;
    pub extern fn bindBuffer(type: c_uint, buffer_id: c_uint) void;
    pub extern fn bindVertexArray(vertex_array_id: c_uint) void;
    pub extern fn bindFramebuffer(target: c_uint, framebuffer: c_uint) void;
    pub extern fn bindTexture(target: c_uint, texture_id: c_uint) void;
    pub extern fn blendFunc(x: c_uint, y: c_uint) void;
    pub extern fn bufferData(type: c_uint, count: c_long, data_ptr: ?*const c_void, draw_type: c_uint) void;
    pub extern fn checkFramebufferStatus(target: gles.GLenum) gles.GLenum;
    pub extern fn clear(mask: gles.GLbitfield) void;
    pub extern fn clearColor(r: f32, g: f32, b: f32, a: f32) void;
    pub extern fn compileShader(shader: gles.GLuint) void;
    // pub extern fn getShaderCompileStatus(shader: gles.GLuint) GLboolean;
    pub extern fn getShaderiv(_shader: gles.GLuint, _pname: gles.GLenum, _params: [*c]gles.GLint) void;
    pub extern fn getProgramiv(_program: gles.GLuint, _pname: gles.GLenum, _params: [*c]gles.GLint) void;
    pub extern fn genBuffers(_n: gles.GLsizei, _buffers: [*c]gles.GLuint) void;
    pub extern fn createFramebuffer() gles.GLuint;
    pub extern fn createProgram() gles.GLuint;
    pub extern fn createShader(shader_type: gles.GLenum) gles.GLuint;
    pub extern fn genTextures(count: gles.GLsizei, textures: [*c]gles.GLuint) void;
    pub extern fn deleteBuffers(count: gles.GLsizei, id: [*c]const gles.GLuint) void;
    pub extern fn deleteProgram(id: c_uint) void;
    pub extern fn deleteShader(id: c_uint) void;
    pub extern fn deleteTexture(id: c_uint) void;
    pub extern fn deleteVertexArrays(count: gles.GLsizei, id: [*c]const gles.GLuint) void;
    pub extern fn depthFunc(x: c_uint) void;
    pub extern fn detachShader(program: c_uint, shader: c_uint) void;
    pub extern fn disable(cap: gles.GLenum) void;
    pub extern fn genVertexArrays(_n: gles.GLsizei, _arrays: [*c]gles.GLuint) void;
    pub extern fn drawArrays(type: c_uint, offset: c_uint, count: c_int) void;
    pub extern fn drawElements(mode: gles.GLenum, count: gles.GLsizei, type: gles.GLenum, offset: ?*const c_void) void;
    pub extern fn enable(x: c_uint) void;
    pub extern fn enableVertexAttribArray(x: c_uint) void;
    pub extern fn framebufferTexture2D(target: gles.GLenum, attachment: gles.GLenum, textarget: gles.GLenum, texture: gles.GLuint, level: gles.GLint) void;
    pub extern fn frontFace(mode: gles.GLenum) void;
    pub extern fn cullFace(face: gles.GLenum) void;
    extern fn getAttribLocation_(program_id: c_uint, name_ptr: [*]const u8, name_len: c_uint) c_int;
    pub fn getAttribLocation(program_id: c_uint, name_ptr: [*:0]const u8) callconv(.C) c_int {
        const name = std.mem.span(name_ptr);
        return getAttribLocation_(program_id, name.ptr, name.len);
    }
    pub extern fn getError() c_int;
    pub extern fn getShaderInfoLog(shader: gles.GLuint, maxLength: gles.GLsizei, length: ?*gles.GLsizei, infoLog: ?[*]u8) void;
    extern fn getUniformLocation_(program_id: c_uint, name_ptr: [*]const u8, name_len: c_uint) c_int;
    pub fn getUniformLocation(program_id: c_uint, name_ptr: [*:0]const u8) c_int {
        const name = std.mem.span(name_ptr);
        return getUniformLocation_(program_id, name.ptr, name.len);
    }
    pub extern fn linkProgram(program: c_uint) void;
    // pub extern fn getProgramLinkStatus(program: c_uint) gles.GLboolean;
    pub extern fn getProgramInfoLog(program: gles.GLuint, maxLength: gles.GLsizei, length: ?*gles.GLsizei, infoLog: ?[*]u8) void;
    pub extern fn pixelStorei(pname: gles.GLenum, param: gles.GLint) void;
    pub extern fn shaderSource(shader: gles.GLuint, count: gles.GLsizei, string: [*c]const [*c]const gles.GLchar, length: [*c]const gles.GLint) void;
    pub extern fn texImage2D(target: c_uint, level: c_uint, internal_format: c_uint, width: c_int, height: c_int, border: c_uint, format: c_uint, type: c_uint, data_ptr: ?[*]const u8) void;
    pub extern fn texParameterf(target: c_uint, pname: c_uint, param: f32) void;
    pub extern fn texParameteri(target: c_uint, pname: c_uint, param: c_uint) void;
    pub extern fn uniform1f(location_id: c_int, x: f32) void;
    pub extern fn uniform1i(location_id: c_int, x: c_int) void;
    pub extern fn uniform4f(location_id: c_int, x: f32, y: f32, z: f32, w: f32) void;
    pub extern fn uniformMatrix4fv(location_id: c_int, data_len: c_int, transpose: c_uint, data_ptr: [*]const f32) void;
    pub extern fn useProgram(program_id: c_uint) void;
    pub extern fn vertexAttribPointer(attrib_location: c_uint, size: c_uint, type: c_uint, normalize: c_uint, stride: c_uint, offset: ?*const c_void) void;
    pub extern fn viewport(x: c_int, y: c_int, width: c_int, height: c_int) void;
    pub extern fn scissor(x: gles.GLint, y: gles.GLint, width: gles.GLsizei, height: gles.GLsizei) void;

    extern fn blendEquation(_mode: GLenum) callconv(.C) void;

    pub extern fn getStringJs(name: GLenum) void;
    fn getString(name: GLenum) callconv(.C) ?[*:0]const GLubyte {
        const String = struct {
            var memory: ?[:0]u8 = null;

            export fn getString_alloc(size: u32) [*]u8 {
                if (memory) |old| {
                    gpa.allocator.free(old);
                    memory = null;
                }
                memory = gpa.allocator.allocSentinel(u8, size, 0) catch @panic("out of memory!");
                return memory.?.ptr;
            }
        };

        getStringJs(name);

        return String.memory.?.ptr;
    }
    extern fn uniform2i(_location: GLint, _v0: GLint, _v1: GLint) callconv(.C) void;

    extern fn hint(_target: GLenum, _mode: GLenum) void;

    extern fn bindAttribLocation(_program: GLuint, _index: GLuint, _name: [*c]const GLchar) void;

    extern fn bindRenderbuffer(_target: GLenum, _renderbuffer: GLuint) void;

    extern fn blendColor(_red: GLfloat, _green: GLfloat, _blue: GLfloat, _alpha: GLfloat) void;

    extern fn blendEquationSeparate(_modeRGB: GLenum, _modeAlpha: GLenum) void;

    extern fn blendFuncSeparate(_sfactorRGB: GLenum, _dfactorRGB: GLenum, _sfactorAlpha: GLenum, _dfactorAlpha: GLenum) void;

    extern fn bufferSubData(_target: GLenum, _offset: GLintptr, _size: GLsizeiptr, _data: ?*const c_void) void;

    extern fn clearDepthf(_d: GLfloat) void;

    extern fn clearStencil(_s: GLint) void;

    extern fn colorMask(_red: GLboolean, _green: GLboolean, _blue: GLboolean, _alpha: GLboolean) void;

    extern fn compressedTexImage2D(_target: GLenum, _level: GLint, _internalformat: GLenum, _width: GLsizei, _height: GLsizei, _border: GLint, _imageSize: GLsizei, _data: ?*const c_void) void;

    extern fn compressedTexSubImage2D(_target: GLenum, _level: GLint, _xoffset: GLint, _yoffset: GLint, _width: GLsizei, _height: GLsizei, _format: GLenum, _imageSize: GLsizei, _data: ?*const c_void) void;

    extern fn copyTexImage2D(_target: GLenum, _level: GLint, _internalformat: GLenum, _x: GLint, _y: GLint, _width: GLsizei, _height: GLsizei, _border: GLint) void;

    extern fn copyTexSubImage2D(_target: GLenum, _level: GLint, _xoffset: GLint, _yoffset: GLint, _x: GLint, _y: GLint, _width: GLsizei, _height: GLsizei) void;

    extern fn deleteFramebuffers(_n: GLsizei, _framebuffers: [*c]const GLuint) void;

    extern fn deleteRenderbuffers(_n: GLsizei, _renderbuffers: [*c]const GLuint) void;

    extern fn deleteTextures(_n: GLsizei, _textures: [*c]const GLuint) void;

    extern fn depthMask(_flag: GLboolean) void;

    extern fn depthRangef(_n: GLfloat, _f: GLfloat) void;

    extern fn disableVertexAttribArray(_index: GLuint) void;

    extern fn finish() void;

    extern fn flush() void;

    extern fn framebufferRenderbuffer(_target: GLenum, _attachment: GLenum, _renderbuffertarget: GLenum, _renderbuffer: GLuint) void;

    extern fn generateMipmap(_target: GLenum) void;

    extern fn genFramebuffers(_n: GLsizei, _framebuffers: [*c]GLuint) void;

    extern fn genRenderbuffers(_n: GLsizei, _renderbuffers: [*c]GLuint) void;

    extern fn getActiveAttrib(_program: GLuint, _index: GLuint, _bufSize: GLsizei, _length: [*c]GLsizei, _size: [*c]GLint, _type: [*c]GLenum, _name: [*c]GLchar) void;

    extern fn getActiveUniform(_program: GLuint, _index: GLuint, _bufSize: GLsizei, _length: [*c]GLsizei, _size: [*c]GLint, _type: [*c]GLenum, _name: [*c]GLchar) void;

    extern fn getAttachedShaders(_program: GLuint, _maxCount: GLsizei, _count: [*c]GLsizei, _shaders: [*c]GLuint) void;

    extern fn getBooleanv(_pname: GLenum, _data: [*c]GLboolean) void;

    extern fn getBufferParameteriv(_target: GLenum, _pname: GLenum, _params: [*c]GLint) void;

    extern fn getFloatv(_pname: GLenum, _data: [*c]GLfloat) void;

    extern fn getFramebufferAttachmentParameteriv(_target: GLenum, _attachment: GLenum, _pname: GLenum, _params: [*c]GLint) void;

    extern fn getIntegerv(_pname: GLenum, _data: [*c]GLint) void;

    extern fn getRenderbufferParameteriv(_target: GLenum, _pname: GLenum, _params: [*c]GLint) void;

    extern fn getShaderPrecisionFormat(_shadertype: GLenum, _precisiontype: GLenum, _range: [*c]GLint, _precision: [*c]GLint) void;

    extern fn getShaderSource(_shader: GLuint, _bufSize: GLsizei, _length: [*c]GLsizei, _source: [*c]GLchar) void;

    extern fn getTexParameterfv(_target: GLenum, _pname: GLenum, _params: [*c]GLfloat) void;

    extern fn getTexParameteriv(_target: GLenum, _pname: GLenum, _params: [*c]GLint) void;

    extern fn getUniformfv(_program: GLuint, _location: GLint, _params: [*c]GLfloat) void;

    extern fn getUniformiv(_program: GLuint, _location: GLint, _params: [*c]GLint) void;

    extern fn getVertexAttribfv(_index: GLuint, _pname: GLenum, _params: [*c]GLfloat) void;

    extern fn getVertexAttribiv(_index: GLuint, _pname: GLenum, _params: [*c]GLint) void;

    extern fn getVertexAttribPointerv(_index: GLuint, _pname: GLenum, _pointer: ?*?*c_void) void;

    extern fn isBuffer(_buffer: GLuint) GLboolean;

    extern fn isEnabled(_cap: GLenum) GLboolean;

    extern fn isFramebuffer(_framebuffer: GLuint) GLboolean;

    extern fn isProgram(_program: GLuint) GLboolean;

    extern fn isRenderbuffer(_renderbuffer: GLuint) GLboolean;

    extern fn isShader(_shader: GLuint) GLboolean;

    extern fn isTexture(_texture: GLuint) GLboolean;

    extern fn lineWidth(_width: GLfloat) void;

    extern fn polygonOffset(_factor: GLfloat, _units: GLfloat) void;

    extern fn readPixels(_x: GLint, _y: GLint, _width: GLsizei, _height: GLsizei, _format: GLenum, _type: GLenum, _pixels: ?*c_void) void;

    extern fn releaseShaderCompiler() void;

    extern fn renderbufferStorage(_target: GLenum, _internalformat: GLenum, _width: GLsizei, _height: GLsizei) void;

    extern fn sampleCoverage(_value: GLfloat, _invert: GLboolean) void;

    extern fn shaderBinary(_count: GLsizei, _shaders: [*c]const GLuint, _binaryFormat: GLenum, _binary: ?*const c_void, _length: GLsizei) void;

    extern fn stencilFunc(_func: GLenum, _ref: GLint, _mask: GLuint) void;

    extern fn stencilFuncSeparate(_face: GLenum, _func: GLenum, _ref: GLint, _mask: GLuint) void;

    extern fn stencilMask(_mask: GLuint) void;

    extern fn stencilMaskSeparate(_face: GLenum, _mask: GLuint) void;

    extern fn stencilOp(_fail: GLenum, _zfail: GLenum, _zpass: GLenum) void;

    extern fn stencilOpSeparate(_face: GLenum, _sfail: GLenum, _dpfail: GLenum, _dppass: GLenum) void;

    extern fn texParameterfv(_target: GLenum, _pname: GLenum, _params: [*c]const GLfloat) void;

    extern fn texParameteriv(_target: GLenum, _pname: GLenum, _params: [*c]const GLint) void;

    extern fn texSubImage2D(_target: GLenum, _level: GLint, _xoffset: GLint, _yoffset: GLint, _width: GLsizei, _height: GLsizei, _format: GLenum, _type: GLenum, _pixels: ?*const c_void) void;

    extern fn uniform1fv(_location: GLint, _count: GLsizei, _value: [*c]const GLfloat) void;

    extern fn uniform1iv(_location: GLint, _count: GLsizei, _value: [*c]const GLint) void;

    extern fn uniform2f(_location: GLint, _v0: GLfloat, _v1: GLfloat) void;

    extern fn uniform2fv(_location: GLint, _count: GLsizei, _value: [*c]const GLfloat) void;

    extern fn uniform2iv(_location: GLint, _count: GLsizei, _value: [*c]const GLint) void;

    extern fn uniform3f(_location: GLint, _v0: GLfloat, _v1: GLfloat, _v2: GLfloat) void;

    extern fn uniform3fv(_location: GLint, _count: GLsizei, _value: [*c]const GLfloat) void;

    extern fn uniform3i(_location: GLint, _v0: GLint, _v1: GLint, _v2: GLint) void;

    extern fn uniform3iv(_location: GLint, _count: GLsizei, _value: [*c]const GLint) void;

    extern fn uniform4fv(_location: GLint, _count: GLsizei, _value: [*c]const GLfloat) void;

    extern fn uniform4i(_location: GLint, _v0: GLint, _v1: GLint, _v2: GLint, _v3: GLint) void;

    extern fn uniform4iv(_location: GLint, _count: GLsizei, _value: [*c]const GLint) void;

    extern fn uniformMatrix2fv(_location: GLint, _count: GLsizei, _transpose: GLboolean, _value: [*c]const GLfloat) void;

    extern fn uniformMatrix3fv(_location: GLint, _count: GLsizei, _transpose: GLboolean, _value: [*c]const GLfloat) void;

    extern fn validateProgram(_program: GLuint) void;

    extern fn vertexAttrib1f(_index: GLuint, _x: GLfloat) void;

    extern fn vertexAttrib1fv(_index: GLuint, _v: [*c]const GLfloat) void;

    extern fn vertexAttrib2f(_index: GLuint, _x: GLfloat, _y: GLfloat) void;

    extern fn vertexAttrib2fv(_index: GLuint, _v: [*c]const GLfloat) void;

    extern fn vertexAttrib3f(_index: GLuint, _x: GLfloat, _y: GLfloat, _z: GLfloat) void;

    extern fn vertexAttrib3fv(_index: GLuint, _v: [*c]const GLfloat) void;

    extern fn vertexAttrib4f(_index: GLuint, _x: GLfloat, _y: GLfloat, _z: GLfloat, _w: GLfloat) void;

    extern fn vertexAttrib4fv(_index: GLuint, _v: [*c]const GLfloat) void;
};
const builtin = std.builtin;
const std = @import("std");
const io = std.io;
const meta = std.meta;

const native_endian = @import("builtin").target.cpu.arch.endian();

pub const StructReadError = error{ EndOfStream, InvalidData } || io.StreamSource.ReadError;

pub fn toMagicNumberNative(magic: []const u8) u32 {
    var result: u32 = 0;
    for (magic, 0..) |character, index| {
        result |= (@as(u32, character) << @as(u5, @intCast((index * 8))));
    }
    return result;
}

pub fn toMagicNumberForeign(magic: []const u8) u32 {
    var result: u32 = 0;
    for (magic, 0..) |character, index| {
        result |= (@as(u32, character) << @as(u5, @intCast((magic.len - 1 - index) * 8)));
    }
    return result;
}

pub const toMagicNumberBig = switch (native_endian) {
    builtin.Endian.little => toMagicNumberForeign,
    builtin.Endian.big => toMagicNumberNative,
};

pub const toMagicNumberLittle = switch (native_endian) {
    builtin.Endian.little => toMagicNumberNative,
    builtin.Endian.big => toMagicNumberForeign,
};

fn checkEnumFields(data: anytype) StructReadError!void {
    const T = @typeInfo(@TypeOf(data)).Pointer.child;
    inline for (meta.fields(T)) |entry| {
        switch (@typeInfo(entry.type)) {
            .Enum => {
                const value = @intFromEnum(@field(data, entry.name));
                _ = std.meta.intToEnum(entry.type, value) catch return StructReadError.InvalidData;
            },
            .Struct => {
                try checkEnumFields(&@field(data, entry.name));
            },
            else => {},
        }
    }
}

pub fn readStructNative(reader: io.StreamSource.Reader, comptime T: type) StructReadError!T {
    var result: T = try reader.readStruct(T);
    try checkEnumFields(&result);
    return result;
}

fn swapFieldBytes(data: anytype) StructReadError!void {
    const T = @typeInfo(@TypeOf(data)).Pointer.child;
    inline for (meta.fields(T)) |entry| {
        switch (@typeInfo(entry.type)) {
            .Int => |int| {
                if (int.bits > 8) {
                    @field(data, entry.name) = @byteSwap(@field(data, entry.name));
                }
            },
            .Struct => {
                try swapFieldBytes(&@field(data, entry.name));
            },
            .Enum => {
                const value = @intFromEnum(@field(data, entry.name));
                if (@bitSizeOf(@TypeOf(value)) > 8) {
                    @field(data, entry.name) = try std.meta.intToEnum(entry.type, @byteSwap(value));
                } else {
                    _ = std.meta.intToEnum(entry.type, value) catch return StructReadError.InvalidData;
                }
            },
            .Array => |array| {
                if (array.child != u8) {
                    @compileError("Add support for type " ++ @typeName(T) ++ "." ++ @typeName(entry.type) ++ " in swapFieldBytes");
                }
            },
            .Bool => {},
            else => {
                @compileError("Add support for type " ++ @typeName(T) ++ "." ++ @typeName(entry.type) ++ " in swapFieldBytes");
            },
        }
    }
}

pub fn readStructForeign(reader: io.StreamSource.Reader, comptime T: type) StructReadError!T {
    var result: T = try reader.readStruct(T);
    try swapFieldBytes(&result);
    return result;
}

pub const readStructLittle = switch (native_endian) {
    builtin.Endian.little => readStructNative,
    builtin.Endian.big => readStructForeign,
};

pub const readStructBig = switch (native_endian) {
    builtin.Endian.little => readStructForeign,
    builtin.Endian.big => readStructNative,
};

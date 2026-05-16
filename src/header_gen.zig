// Copyright (C) 2026 Igor Spichkin
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

const kats_tools = @import("kats_tools");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const src_path = args[1];
    const dst_path = args[2];

    var header_content = try std.Io.Dir.cwd().readFileAlloc(init.io, src_path, init.arena.allocator(), .unlimited);

    var xor_keys_writer: std.Io.Writer.Allocating = .init(init.arena.allocator());

    inline for (comptime std.meta.declarations(kats_tools.XorKeys)) |decl| {
        const value = std.mem.readInt(u32, @field(kats_tools.XorKeys, decl.name)[0..4], .little);

        try xor_keys_writer.writer.print("#define KATS_XOR_KEY_{s} 0x{X:0>8}\n", .{ decl.name, value });
    }

    header_content = try std.mem.replaceOwned(u8, init.arena.allocator(), header_content, "// $XOR_KEYS", xor_keys_writer.written());

    var model_record_types_writer: std.Io.Writer.Allocating = .init(init.arena.allocator());

    inline for (@typeInfo(kats_tools.ModelRecordType).@"enum".fields) |field| {
        const name = try std.ascii.allocUpperString(init.arena.allocator(), field.name);

        try model_record_types_writer.writer.print("#define KATS_MODEL_RECORD_TYPE_{s} {}\n", .{ name, field.value });
    }

    header_content = try std.mem.replaceOwned(u8, init.arena.allocator(), header_content, "// $MODEL_RECORD_TYPES", model_record_types_writer.written());

    var primitive_types_writer: std.Io.Writer.Allocating = .init(init.arena.allocator());

    inline for (@typeInfo(kats_tools.PrimitiveType).@"enum".fields) |field| {
        const name = try std.ascii.allocUpperString(init.arena.allocator(), field.name);

        try primitive_types_writer.writer.print("#define KATS_PRIMITIVE_TYPE_{s} {}\n", .{ name, field.value });
    }

    header_content = try std.mem.replaceOwned(u8, init.arena.allocator(), header_content, "// $PRIMITIVE_TYPES", primitive_types_writer.written());

    try std.Io.Dir.cwd().writeFile(init.io, .{
        .data = header_content,
        .sub_path = dst_path,
        .flags = .{},
    });
}

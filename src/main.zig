// Copyright (C) 2026 Igor Spichkin
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

const kats_tools = @import("kats_tools");

pub fn printUsage() void {
    std.debug.print("Usage: kats-tools <COMMAND> <GAME_DIR> <OUT_DIR>\n", .{});
    std.debug.print("COMMANDS:\n", .{});
    std.debug.print("  decrypt - only decrypts the game files.\n", .{});
    std.debug.print("  convert - decrypts and converts the game files to the common formats.\n", .{});
    std.debug.print("  help - print this text.\n", .{});
}

inline fn withoutExt(path: []const u8) []const u8 {
    if (std.mem.findLast(u8, path, ".")) |idx| {
        return path[0..idx];
    }

    return path;
}

const FileType = enum {
    animation,
    clipper,
    model,
    texture,
    sound,
};

const FileMeta = struct {
    sub_path: []const u8,
    xor_key: []const u8,
    ty: FileType,
};

const FILES_META: []const FileMeta = &.{
    .{ .sub_path = "animation/animation00.bin", .xor_key = kats_tools.XorKeys.ANIMATION00, .ty = .animation },
    .{ .sub_path = "animation/animation01.bin", .xor_key = kats_tools.XorKeys.ANIMATION01, .ty = .animation },
    .{ .sub_path = "animation/animation02.bin", .xor_key = kats_tools.XorKeys.ANIMATION02, .ty = .animation },
    .{ .sub_path = "animation/animation03.bin", .xor_key = kats_tools.XorKeys.ANIMATION03, .ty = .animation },
    .{ .sub_path = "clipper/clipper00.bin", .xor_key = kats_tools.XorKeys.CLIPPER00, .ty = .clipper },
    .{ .sub_path = "model/model00.bin", .xor_key = kats_tools.XorKeys.MODEL00, .ty = .model },
    .{ .sub_path = "model/model01.bin", .xor_key = kats_tools.XorKeys.MODEL01, .ty = .model },
    .{ .sub_path = "model/model02.bin", .xor_key = kats_tools.XorKeys.MODEL02, .ty = .model },
    .{ .sub_path = "model/model03.bin", .xor_key = kats_tools.XorKeys.MODEL03, .ty = .model },
    .{ .sub_path = "model/model04.bin", .xor_key = kats_tools.XorKeys.MODEL04, .ty = .model },
    .{ .sub_path = "model/texture00.bin", .xor_key = kats_tools.XorKeys.TEXTURE00, .ty = .texture },
    .{ .sub_path = "model/texture01.bin", .xor_key = kats_tools.XorKeys.TEXTURE01, .ty = .texture },
    .{ .sub_path = "model/texture02.bin", .xor_key = kats_tools.XorKeys.TEXTURE02, .ty = .texture },
    .{ .sub_path = "model/texture03.bin", .xor_key = kats_tools.XorKeys.TEXTURE03, .ty = .texture },
    .{ .sub_path = "model/texture04.bin", .xor_key = kats_tools.XorKeys.TEXTURE04, .ty = .texture },
    .{ .sub_path = "sound/sound00.bin", .xor_key = kats_tools.XorKeys.SOUND00, .ty = .sound },
    .{ .sub_path = "sound/sound01.bin", .xor_key = kats_tools.XorKeys.SOUND01, .ty = .sound },
};

fn decrypt(init: std.process.Init, args: []const [:0]const u8) !void {
    if (args.len != 4) {
        printUsage();

        return error.BadArgs;
    }

    const game_dir = args[2];
    const out_dir = args[3];

    for (FILES_META) |meta| {
        const input_path = try std.fs.path.join(init.gpa, &.{ game_dir, meta.sub_path });
        defer init.gpa.free(input_path);

        const file_content = try std.Io.Dir.cwd().readFileAlloc(init.io, input_path, init.gpa, .unlimited);
        defer init.gpa.free(file_content);

        kats_tools.kats_tools_decrypt(std.mem.readInt(u32, meta.xor_key[0..4], .little), file_content.ptr, file_content.len);

        const out_path = try std.fs.path.join(init.gpa, &.{ out_dir, meta.sub_path });
        defer init.gpa.free(out_path);

        std.debug.print("{s} -> {s}\n", .{ meta.sub_path, out_path });

        try std.Io.Dir.cwd().createDirPath(init.io, std.fs.path.dirname(out_path).?);
        try std.Io.Dir.cwd().writeFile(init.io, .{
            .sub_path = out_path,
            .data = file_content,
            .flags = .{},
        });
    }
}

fn convert(init: std.process.Init, args: []const [:0]const u8) !void {
    if (args.len != 4) {
        printUsage();

        return error.BadArgs;
    }

    var ok: bool = true;

    const game_dir = args[2];
    const out_dir = args[3];

    for (FILES_META) |meta| {
        const input_path = try std.fs.path.join(init.gpa, &.{ game_dir, meta.sub_path });
        defer init.gpa.free(input_path);

        const file_content = try std.Io.Dir.cwd().readFileAlloc(init.io, input_path, init.gpa, .unlimited);
        defer init.gpa.free(file_content);

        kats_tools.kats_tools_decrypt(std.mem.readInt(u32, meta.xor_key[0..4], .little), file_content.ptr, file_content.len);

        switch (meta.ty) {
            .clipper => {
                const bmp_files = kats_tools.kats_tools_clipper_count_files(file_content.ptr, file_content.len);

                std.debug.print("BMP files: {d}\n", .{bmp_files});

                if (bmp_files == 0) {
                    std.debug.print("Bad clipper file: {s}\n", .{input_path});
                    ok = false;

                    continue;
                }

                for (0..bmp_files) |i| {
                    const out_path = try std.fmt.allocPrint(init.gpa, "{f}/{d}.bmp", .{ std.fs.path.fmtJoin(&.{ out_dir, withoutExt(meta.sub_path) }), i });
                    defer init.gpa.free(out_path);

                    std.debug.print("{s} -> {s}\n", .{ meta.sub_path, out_path });

                    var wav_data: []const u8 = &.{};

                    if (!kats_tools.kats_tools_clipper_get(file_content.ptr, file_content.len, i, &wav_data.ptr, &wav_data.len)) {
                        std.debug.print("BMP file {d} not found in {s}\n", .{ i, input_path });
                        ok = false;

                        continue;
                    }

                    try std.Io.Dir.cwd().createDirPath(init.io, std.fs.path.dirname(out_path).?);
                    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = wav_data, .flags = .{} });
                }
            },
            .texture => {
                const tga_files = kats_tools.kats_tools_texture_count_files(file_content.ptr, file_content.len);

                std.debug.print("TGA files: {d}\n", .{tga_files});

                if (tga_files == 0) {
                    std.debug.print("Bad texture file: {s}\n", .{input_path});
                    ok = false;

                    continue;
                }

                for (0..tga_files) |i| {
                    const out_path = try std.fmt.allocPrint(init.gpa, "{f}/{d}.tga", .{ std.fs.path.fmtJoin(&.{ out_dir, withoutExt(meta.sub_path) }), i });
                    defer init.gpa.free(out_path);

                    std.debug.print("{s} -> {s}\n", .{ meta.sub_path, out_path });

                    var tga_data: []const u8 = &.{};

                    if (!kats_tools.kats_tools_texture_get(file_content.ptr, file_content.len, i, &tga_data.ptr, &tga_data.len)) {
                        std.debug.print("TGA file {d} not found in {s}\n", .{ i, input_path });
                        ok = false;

                        continue;
                    }

                    try std.Io.Dir.cwd().createDirPath(init.io, std.fs.path.dirname(out_path).?);
                    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = tga_data, .flags = .{} });
                }
            },
            .sound => {
                const wave_files = kats_tools.kats_tools_sound_count_files(file_content.ptr, file_content.len);

                std.debug.print("WAV files: {d}\n", .{wave_files});

                if (wave_files == 0) {
                    std.debug.print("Bad sound file: {s}\n", .{input_path});
                    ok = false;

                    continue;
                }

                for (0..wave_files) |i| {
                    const out_path = try std.fmt.allocPrint(init.gpa, "{f}/{d}.wav", .{ std.fs.path.fmtJoin(&.{ out_dir, withoutExt(meta.sub_path) }), i });
                    defer init.gpa.free(out_path);

                    std.debug.print("{s} -> {s}\n", .{ meta.sub_path, out_path });

                    var wav_data: []const u8 = &.{};

                    if (!kats_tools.kats_tools_sound_get(file_content.ptr, file_content.len, i, &wav_data.ptr, &wav_data.len)) {
                        std.debug.print("WAV file {d} not found in {s}\n", .{ i, input_path });
                        ok = false;

                        continue;
                    }

                    try std.Io.Dir.cwd().createDirPath(init.io, std.fs.path.dirname(out_path).?);
                    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = wav_data, .flags = .{} });
                }
            },
            else => {},
        }
    }

    if (!ok) {
        return error.BadGameFiles;
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        printUsage();

        return error.BadArgs;
    }

    if (std.mem.eql(u8, args[1], "help")) {
        printUsage();
    } else if (std.mem.eql(u8, args[1], "decrypt")) {
        try decrypt(init, args);
    } else if (std.mem.eql(u8, args[1], "convert")) {
        try convert(init, args);
    }
}

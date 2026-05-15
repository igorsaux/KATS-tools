// Copyright (C) 2026 Igor Spichkin
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

const SignatureKind = enum { header, footer };

inline fn countSignatures(data: []const u8, signature: []const u8) usize {
    var count: usize = 0;
    var offset: usize = 0;

    while (std.mem.indexOf(u8, data[offset..], signature)) |idx| {
        count += 1;
        offset += idx + signature.len;
    }

    return count;
}

inline fn getSignatureSlice(data: []const u8, signature: []const u8, kind: SignatureKind, idx: usize) ?[]const u8 {
    var current_idx: usize = 0;
    var offset: usize = 0;

    switch (kind) {
        .header => {
            var chunk_start: usize = 0;

            while (std.mem.indexOf(u8, data[offset..], signature)) |found_idx| {
                const abs_idx = offset + found_idx;

                if (current_idx == idx) {
                    chunk_start = abs_idx;
                } else if (current_idx == idx + 1) {
                    return data[chunk_start..abs_idx];
                }

                current_idx += 1;
                offset = abs_idx + signature.len;
            }

            if (current_idx == idx + 1) {
                return data[chunk_start..];
            }

            return null;
        },
        .footer => {
            var chunk_start: usize = 0;

            while (std.mem.indexOf(u8, data[offset..], signature)) |found_idx| {
                const abs_idx = offset + found_idx;
                const chunk_end = abs_idx + signature.len;

                if (current_idx == idx) {
                    return data[chunk_start..chunk_end];
                }

                chunk_start = chunk_end;
                current_idx += 1;
                offset = chunk_end;
            }

            return null;
        },
    }
}

pub const XorKeys = struct {
    pub const CLIPPER00: []const u8 = &.{ 0xB9, 0x5A, 0x74, 0xD2 };

    pub const SOUND00: []const u8 = &.{ 0x3D, 0xC4, 0x5B, 0x6E };
    pub const SOUND01: []const u8 = &.{ 0x74, 0x2A, 0x83, 0xFD };

    pub const ANIMATION00: []const u8 = &.{ 0x56, 0xAC, 0x5F, 0x32 };
    pub const ANIMATION01: []const u8 = &.{ 0xF9, 0x4E, 0xC4, 0xA7 };
    pub const ANIMATION02: []const u8 = &.{ 0xA5, 0x34, 0xA9, 0x78 };
    pub const ANIMATION03: []const u8 = &.{ 0xA1, 0x9B, 0xE6, 0xE5 };

    pub const MODEL00: []const u8 = &.{ 0x64, 0x3A, 0x57, 0x5C };
    pub const MODEL01: []const u8 = &.{ 0xC9, 0x2D, 0x33, 0xD8 };
    pub const MODEL02: []const u8 = &.{ 0xC3, 0x7A, 0x7B, 0x96 };
    pub const MODEL03: []const u8 = &.{ 0x5F, 0x19, 0x86, 0xAB };
    pub const MODEL04: []const u8 = &.{ 0xBE, 0xDB, 0x95, 0x87 };

    pub const TEXTURE00: []const u8 = &.{ 0x43, 0xDB, 0xD9, 0x83 };
    pub const TEXTURE01: []const u8 = &.{ 0xD1, 0x25, 0x67, 0xFE };
    pub const TEXTURE02: []const u8 = &.{ 0x54, 0x32, 0x89, 0x75 };
    pub const TEXTURE03: []const u8 = &.{ 0xA5, 0x47, 0x3D, 0x32 };
    pub const TEXTURE04: []const u8 = &.{ 0xFC, 0x7F, 0xD5, 0x98 };
};

pub export fn kats_tools_decrypt(key: u32, data: [*]u8, data_len: usize) callconv(.c) void {
    const key_bytes = std.mem.toBytes(std.mem.littleToNative(u32, key));

    for (0..data_len) |i| {
        const k = key_bytes[i % 4];

        data[i] ^= k;
    }
}

pub export fn kats_tools_sound_count_files(data: [*]const u8, data_len: usize) callconv(.c) usize {
    return countSignatures(data[0..data_len], "RIFF");
}

pub export fn kats_tools_sound_get(data: [*]const u8, data_len: usize, idx: usize, out: *[*]const u8, out_len: *usize) callconv(.c) bool {
    const slice = getSignatureSlice(data[0..data_len], "RIFF", .header, idx) orelse return false;

    out.* = slice.ptr;
    out_len.* = slice.len;

    return true;
}

pub export fn kats_tools_clipper_count_files(data: [*]const u8, data_len: usize) callconv(.c) usize {
    return countSignatures(data[0..data_len], "BM6");
}

pub export fn kats_tools_clipper_get(data: [*]const u8, data_len: usize, idx: usize, out: *[*]const u8, out_len: *usize) callconv(.c) bool {
    const slice = getSignatureSlice(data[0..data_len], "BM6", .header, idx) orelse return false;

    out.* = slice.ptr;
    out_len.* = slice.len;

    return true;
}

pub export fn kats_tools_texture_count_files(data: [*]const u8, data_len: usize) callconv(.c) usize {
    return countSignatures(data[0..data_len], "TRUEVISION-XFILE.\x00");
}

pub export fn kats_tools_texture_get(data: [*]const u8, data_len: usize, idx: usize, out: *[*]const u8, out_len: *usize) callconv(.c) bool {
    const slice = getSignatureSlice(data[0..data_len], "TRUEVISION-XFILE.\x00", .footer, idx) orelse return false;

    out.* = slice.ptr;
    out_len.* = slice.len;

    return true;
}

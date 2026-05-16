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

pub export fn kats_decrypt(key: u32, data: [*]u8, data_len: usize) callconv(.c) void {
    const key_bytes = std.mem.toBytes(std.mem.littleToNative(u32, key));

    for (0..data_len) |i| {
        const k = key_bytes[i % 4];

        data[i] ^= k;
    }
}

pub export fn kats_sound_count_files(data: [*]const u8, data_len: usize) callconv(.c) usize {
    return countSignatures(data[0..data_len], "RIFF");
}

pub export fn kats_sound_get(data: [*]const u8, data_len: usize, idx: usize, out: *[*]const u8, out_len: *usize) callconv(.c) bool {
    const slice = getSignatureSlice(data[0..data_len], "RIFF", .header, idx) orelse return false;

    out.* = slice.ptr;
    out_len.* = slice.len;

    return true;
}

pub export fn kats_clipper_count_files(data: [*]const u8, data_len: usize) callconv(.c) usize {
    return countSignatures(data[0..data_len], "BM6");
}

pub export fn kats_clipper_get(data: [*]const u8, data_len: usize, idx: usize, out: *[*]const u8, out_len: *usize) callconv(.c) bool {
    const slice = getSignatureSlice(data[0..data_len], "BM6", .header, idx) orelse return false;

    out.* = slice.ptr;
    out_len.* = slice.len;

    return true;
}

pub export fn kats_texture_count_files(data: [*]const u8, data_len: usize) callconv(.c) usize {
    return countSignatures(data[0..data_len], "TRUEVISION-XFILE.\x00");
}

pub export fn kats_texture_get(data: [*]const u8, data_len: usize, idx: usize, out: *[*]const u8, out_len: *usize) callconv(.c) bool {
    const slice = getSignatureSlice(data[0..data_len], "TRUEVISION-XFILE.\x00", .footer, idx) orelse return false;

    out.* = slice.ptr;
    out_len.* = slice.len;

    return true;
}

pub const ModelRecordType = enum(c_int) {
    mesh_shape = 0,
    material = 1,
    shape_ref = 2,
    texture_ref = 3,
    transform_node = 4,
    shader_ref = 5,
    anim_ref = 7,
    keyframe_channel = 8,
    anim_set = 9,
    skeleton_root = 10,
    joint = 11,
};

pub export fn kats_model_count_records(data: [*]const u8, data_len: usize) callconv(.c) usize {
    var reader: std.Io.Reader = .fixed(data[0..data_len]);
    var count: usize = 0;

    while (true) {
        _ = std.enums.fromInt(ModelRecordType, reader.takeInt(u32, .little) catch return 0) orelse {
            return 0;
        };

        const size = reader.takeInt(u32, .little) catch {
            return 0;
        };

        if (size < @sizeOf(u32) * 2) {
            return 0;
        }

        reader.discardAll(size - (@sizeOf(u32) * 2)) catch {
            return 0;
        };

        count += 1;

        if (reader.peek(1) == error.EndOfStream) {
            return count;
        }
    }
}

pub const Record = extern struct {
    ptr: [*]const u8,
    ty: ModelRecordType,
    size: usize,
    name: [*:0]const u8,
    tag: [*]const u8,
    tag_len: usize,
    data: [*]const u8,
    data_len: usize,
};

inline fn skipToModelRecord(reader: *std.Io.Reader, idx: usize) !void {
    var count: usize = 0;

    while (count != idx) {
        _ = std.enums.fromInt(ModelRecordType, try reader.takeInt(u32, .little)) orelse {
            return error.BadModelRecordType;
        };

        const size = try reader.takeInt(u32, .little);

        if (size < @sizeOf(u32) * 2) {
            return error.InvalidRecordSize;
        }

        try reader.discardAll(size - (@sizeOf(u32) * 2));

        count += 1;
    }
}

pub export fn kats_model_get_record(data: [*]const u8, data_len: usize, idx: usize, out: *Record) callconv(.c) bool {
    var reader: std.Io.Reader = .fixed(data[0..data_len]);

    skipToModelRecord(&reader, idx) catch {
        return false;
    };

    const start_idx = reader.seek;

    out.ptr = data[reader.seek..];

    out.ty = std.enums.fromInt(ModelRecordType, reader.takeInt(u32, .little) catch return false) orelse {
        return false;
    };

    out.size = reader.takeInt(u32, .little) catch {
        return false;
    };

    if (out.size < @sizeOf(u32) * 2) {
        return false;
    }

    out.name = (reader.takeSentinel(0) catch {
        return false;
    }).ptr;

    const tag = data[reader.seek..data_len];
    var i: usize = 0;

    while (i < tag.len and std.ascii.isDigit(tag[i])) : (i += 1) {}

    out.tag = tag.ptr;
    out.tag_len = i;

    reader.discardAll(i) catch {
        return false;
    };

    const consumed = reader.seek - start_idx;
    if (consumed > out.size) {
        return false;
    }

    out.data = data[reader.seek..];
    out.data_len = out.size - consumed;

    return true;
}

inline fn readF32Le(ptr: [*]const u8) f32 {
    return @bitCast(std.mem.readInt(u32, ptr[0..4], .little));
}

pub const MeshShapeHeader = extern struct {
    radius: f32,
    cx: f32,
    cy: f32,
    cz: f32,
    flag: u32,
    skeleton_id: u32,
    padding: u32,
    vertex_count: u32,
};

pub export fn kats_model_get_mesh_shape_header(record: *const Record, out: *MeshShapeHeader) callconv(.c) bool {
    var reader: std.Io.Reader = .fixed(record.data[0..record.data_len]);

    out.radius = std.mem.bytesToValue(f32, reader.takeArray(@sizeOf(f32)) catch return false);
    out.cx = std.mem.bytesToValue(f32, reader.takeArray(@sizeOf(f32)) catch return false);
    out.cy = std.mem.bytesToValue(f32, reader.takeArray(@sizeOf(f32)) catch return false);
    out.cz = std.mem.bytesToValue(f32, reader.takeArray(@sizeOf(f32)) catch return false);

    out.flag = reader.takeInt(u32, .little) catch {
        return false;
    };

    out.skeleton_id = reader.takeInt(u32, .little) catch {
        return false;
    };

    out.padding = reader.takeInt(u32, .little) catch {
        return false;
    };

    out.vertex_count = reader.takeInt(u32, .little) catch {
        return false;
    };

    return true;
}

pub const PrimitiveType = enum(c_int) {
    triangle_strip = 1,
    triangle_list = 4,
};

pub const ModelShapeTrailer = extern struct {
    primitive_ty: PrimitiveType,
    flag: u32,
    index_count: u32,
    indexes: [*]const u16,
};

pub export fn kats_model_get_mesh_shape_trailer(record: *const Record, header: *const MeshShapeHeader, stride: u32, out: *ModelShapeTrailer) callconv(.c) bool {
    const header_size: usize = @sizeOf(MeshShapeHeader);
    const vtx_data_len: usize = @as(usize, header.vertex_count) * stride;
    const trailer_offset: usize = header_size + vtx_data_len;

    if (trailer_offset + 12 > record.data_len) {
        return false;
    }

    var reader: std.Io.Reader = .fixed(record.data[trailer_offset..record.data_len]);

    out.primitive_ty = std.enums.fromInt(PrimitiveType, reader.takeInt(u32, .little) catch return false) orelse {
        return false;
    };

    out.flag = reader.takeInt(u32, .little) catch {
        return false;
    };

    out.index_count = reader.takeInt(u32, .little) catch {
        return false;
    };

    const indexes_offset: usize = trailer_offset + 12;

    if (indexes_offset + @as(usize, out.index_count) * 2 > record.data_len) {
        return false;
    }

    out.indexes = @ptrCast(@alignCast(record.data[indexes_offset..]));

    return true;
}

pub export fn kats_model_guess_mesh_shape_stride(record: *const Record, header: *const MeshShapeHeader, out: *u32) callconv(.c) bool {
    const STRIDES = [_]u32{ 32, 48, 56, 60, 64, 36, 40, 44, 52, 24, 28 };

    if (header.vertex_count > 100_000) {
        return false;
    }

    const vtx_start: usize = @sizeOf(MeshShapeHeader);

    for (STRIDES) |stride| {
        const vtx_data_len: usize = @as(usize, header.vertex_count) * stride;
        const trailer_offset: usize = vtx_start + vtx_data_len;

        // Check that there's room for the trailer header (12 bytes)
        if (trailer_offset + 12 > record.data_len) {
            continue;
        }

        var reader: std.Io.Reader = .fixed(record.data[trailer_offset..record.data_len]);

        const t1 = reader.takeInt(u32, .little) catch return false;
        const t2 = reader.takeInt(u32, .little) catch return false;
        const t3 = reader.takeInt(u32, .little) catch return false;

        // Validate trailer: primitive_type must be 1 (strip) or 4 (list), flag must be 1,
        // index_count must be reasonable
        if ((t1 != 1 and t1 != 4) or t2 != 1 or t3 == 0 or t3 > 100_000) {
            continue;
        }

        // Check that indices fit exactly within the record
        const idx_end: usize = trailer_offset + 12 + @as(usize, t3) * 2;

        if (idx_end != record.data_len) {
            continue;
        }

        // Validate first index is within vertex range
        if (t3 >= 2) {
            const first_idx = std.mem.readInt(u16, record.data[trailer_offset + 12 ..][0..2], .little);

            if (first_idx > header.vertex_count) {
                continue;
            }
        }

        // Validate first vertex: position should be in reasonable range,
        // normal should be approximately unit length
        if (vtx_start + stride <= record.data_len and stride >= 32) {
            const px = readF32Le(record.data[vtx_start..]);
            const py = readF32Le(record.data[vtx_start + 4 ..]);
            const pz = readF32Le(record.data[vtx_start + 8 ..]);

            if (@abs(px) > 50000 or @abs(py) > 50000 or @abs(pz) > 50000) {
                continue;
            }

            const nx = readF32Le(record.data[vtx_start + 12 ..]);
            const ny = readF32Le(record.data[vtx_start + 16 ..]);
            const nz = readF32Le(record.data[vtx_start + 20 ..]);

            const nlen = @sqrt(nx * nx + ny * ny + nz * nz);

            if (nlen > 0.01 and @abs(nlen - 1.0) > 0.5) {
                continue;
            }
        }

        out.* = stride;

        return true;
    }

    return false;
}

pub export fn kats_model_get_mesh_shape_vertex(record: *const Record, header: *const MeshShapeHeader, stride: u32, vertex_idx: u32, out_position: *[3]f32, out_normal: *[3]f32, out_uv: *[2]f32) callconv(.c) bool {
    if (vertex_idx >= header.vertex_count) {
        return false;
    }

    const vtx_offset: usize = @sizeOf(MeshShapeHeader) + @as(usize, vertex_idx) * stride;

    if (vtx_offset + stride > record.data_len) {
        return false;
    }

    const vtx = record.data[vtx_offset..record.data_len];

    // Position: offset 0, 3 floats
    out_position[0] = @bitCast(std.mem.readInt(u32, vtx[0..4], .little));
    out_position[1] = @bitCast(std.mem.readInt(u32, vtx[4..8], .little));
    out_position[2] = @bitCast(std.mem.readInt(u32, vtx[8..12], .little));

    // Normal: offset 12, 3 floats
    out_normal[0] = @bitCast(std.mem.readInt(u32, vtx[12..16], .little));
    out_normal[1] = @bitCast(std.mem.readInt(u32, vtx[16..20], .little));
    out_normal[2] = @bitCast(std.mem.readInt(u32, vtx[20..24], .little));

    // UV: offset (stride - 8), 2 floats
    if (stride >= 32) {
        const uv_off: usize = stride - 8;

        out_uv[0] = @bitCast(std.mem.readInt(u32, vtx[uv_off .. uv_off + 4][0..4], .little));
        out_uv[1] = @bitCast(std.mem.readInt(u32, vtx[uv_off + 4 .. uv_off + 8][0..4], .little));
    } else {
        out_uv[0] = 0.0;
        out_uv[1] = 0.0;
    }

    return true;
}

pub export fn kats_model_mesh_shape_triangle_list_index_count(trailer: *const ModelShapeTrailer) callconv(.c) usize {
    if (trailer.primitive_ty == .triangle_list) {
        return trailer.index_count;
    }

    var count: usize = 0;
    var i: usize = 0;

    while (i + 3 <= trailer.index_count) : (i += 1) {
        const ind_0 = trailer.indexes[i];
        const ind_1 = trailer.indexes[i + 1];
        const ind_2 = trailer.indexes[i + 2];

        if (ind_0 == 0xFFFF or ind_1 == 0xFFFF or ind_2 == 0xFFFF) {
            continue;
        }

        count += 1;
    }

    return count * 3;
}

pub export fn kats_model_mesh_shape_to_triangle_list(trailer: *const ModelShapeTrailer, out_indices: [*]u16, out_len: usize) callconv(.c) bool {
    if (trailer.primitive_ty == .triangle_list) {
        if (out_len < trailer.index_count) {
            return false;
        }

        // Reverse winding for each triangle (ind_2, ind_1, ind_0) to invert normals
        var tri: usize = 0;
        while (tri + 3 <= trailer.index_count) : (tri += 3) {
            out_indices[tri] = trailer.indexes[tri + 2];
            out_indices[tri + 1] = trailer.indexes[tri + 1];
            out_indices[tri + 2] = trailer.indexes[tri];
        }

        // Copy any remaining indices if index_count is not a multiple of 3
        if (trailer.index_count % 3 != 0) {
            const start = trailer.index_count - (trailer.index_count % 3);
            @memcpy(out_indices[start..trailer.index_count], trailer.indexes[start..trailer.index_count]);
        }

        return true;
    }

    var out_idx: usize = 0;
    var i: usize = 0;

    while (i + 3 <= trailer.index_count) : (i += 1) {
        const ind_0 = trailer.indexes[i];
        const ind_1 = trailer.indexes[i + 1];
        const ind_2 = trailer.indexes[i + 2];

        if (ind_0 == 0xFFFF or ind_1 == 0xFFFF or ind_2 == 0xFFFF) {
            continue;
        }

        if (out_idx + 3 > out_len) {
            return false;
        }

        // Even triangles: raw order (ind_0, ind_1, ind_2)
        // Odd triangles: swap ind_0 and ind_1 (ind_1, ind_0, ind_2)
        if (i % 2 == 0) {
            out_indices[out_idx] = ind_0;
            out_indices[out_idx + 1] = ind_1;
            out_indices[out_idx + 2] = ind_2;
        } else {
            out_indices[out_idx] = ind_1;
            out_indices[out_idx + 1] = ind_0;
            out_indices[out_idx + 2] = ind_2;
        }

        out_idx += 3;
    }

    return true;
}

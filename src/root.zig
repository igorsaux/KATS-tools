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

/// TGA v2 footer signature (18 bytes at the end of the file).
const TGA_FOOTER_SIGNATURE: []const u8 = "TRUEVISION-XFILE.\x00";

/// TGA v2 footer total size: 4 bytes extension area offset + 4 bytes developer
/// directory offset + 18 bytes signature = 26 bytes.
const TGA_FOOTER_SIZE: usize = 26;

/// Read a u16 little-endian from a byte pointer.
inline fn readU16Le(ptr: [*]const u8) u16 {
    return std.mem.readInt(u16, ptr[0..2], .little);
}

/// Parse a TGA image starting at the given offset in the data.
/// Returns the byte length of the complete TGA image
/// (header + id + colormap + image data + optional TGA v2 footer),
/// or 0 if the data at `offset` does not look like a valid TGA.
fn parseTgaImageSize(data: [*]const u8, data_len: usize, offset: usize) usize {
    if (offset + 18 > data_len) {
        return 0;
    }

    // Read header fields manually to avoid alignment issues
    const h = data + offset;
    const id_length: u8 = h[0];
    const color_map_type: u8 = h[1];
    const image_type: u8 = h[2];
    const color_map_length: u16 = readU16Le(h + 5);
    const color_map_entry_size: u8 = h[7];
    const width: u16 = readU16Le(h + 12);
    const height: u16 = readU16Le(h + 14);
    const pixel_depth: u8 = h[16];

    // Validate image type: must be one of the known TGA image types
    switch (image_type) {
        0, 1, 2, 3, 9, 10, 11 => {},
        else => return 0,
    }

    // Validate color map type
    if (color_map_type > 1) {
        return 0;
    }

    // Validate dimensions
    if (width == 0 or height == 0 or width > 4096 or height > 4096) {
        return 0;
    }

    // Validate pixel depth
    switch (pixel_depth) {
        8, 16, 24, 32 => {},
        else => return 0,
    }

    // Calculate position after header + image ID
    var pos: usize = offset + 18 + id_length;

    // Skip color map data
    if (color_map_type == 1) {
        const cm_entry_bytes: usize = (@as(usize, color_map_entry_size) + 7) / 8;
        const cm_bytes: usize = @as(usize, color_map_length) * cm_entry_bytes;

        pos += cm_bytes;
    }

    if (pos > data_len) {
        return 0;
    }

    // Calculate image data size
    const pixel_count: usize = @as(usize, width) * @as(usize, height);
    const bytes_per_pixel: usize = pixel_depth / 8;

    switch (image_type) {
        1, 2, 3 => {
            // Uncompressed: exact pixel data size
            pos += pixel_count * bytes_per_pixel;
        },
        9, 10, 11 => {
            // RLE compressed: scan through RLE packets to find actual data size
            var pixels_decoded: usize = 0;

            while (pixels_decoded < pixel_count) {
                if (pos + 1 > data_len) {
                    return 0;
                }

                const packet_type = data[pos];
                pos += 1;

                const count: usize = (@as(usize, packet_type & 0x7F) + 1);

                if (packet_type & 0x80 != 0) {
                    // RLE packet: one pixel value repeated `count` times
                    if (pos + bytes_per_pixel > data_len) {
                        return 0;
                    }

                    pos += bytes_per_pixel;
                    pixels_decoded += count;
                } else {
                    // Raw packet: `count` individual pixel values
                    if (pos + count * bytes_per_pixel > data_len) {
                        return 0;
                    }

                    pos += count * bytes_per_pixel;
                    pixels_decoded += count;
                }
            }
        },
        else => unreachable,
    }

    if (pos > data_len) return 0;

    // Check for TGA v2 footer immediately after image data.
    // The footer is 26 bytes: 4-byte extension area offset + 4-byte developer
    // directory offset + 18-byte signature "TRUEVISION-XFILE.\0".
    // All footer-bearing TGAs in the game files have ext_offset=0 and
    // dev_offset=0, so the footer is placed right after the image data.
    if (pos + TGA_FOOTER_SIZE <= data_len) {
        const sig_start = pos + 8; // signature starts 8 bytes into the footer
        const sig_end = sig_start + TGA_FOOTER_SIGNATURE.len;

        if (std.mem.eql(u8, data[sig_start..sig_end], TGA_FOOTER_SIGNATURE)) {
            pos += TGA_FOOTER_SIZE;
        }
    }

    return pos - offset;
}

pub export fn kats_texture_count_files(data: [*]const u8, data_len: usize) callconv(.c) usize {
    var count: usize = 0;
    var offset: usize = 0;

    while (offset < data_len) {
        const tga_size = parseTgaImageSize(data, data_len, offset);

        if (tga_size == 0) {
            // Could not parse a valid TGA at this position; skip forward
            // and try to find the next valid TGA header. This handles edge
            // cases where there might be alignment padding or garbage bytes.
            offset += 1;
            continue;
        }

        count += 1;
        offset += tga_size;
    }

    return count;
}

pub export fn kats_texture_get(data: [*]const u8, data_len: usize, idx: usize, out: *[*]const u8, out_len: *usize) callconv(.c) bool {
    var current_idx: usize = 0;
    var offset: usize = 0;

    while (offset < data_len) {
        const tga_size = parseTgaImageSize(data, data_len, offset);

        if (tga_size == 0) {
            offset += 1;
            continue;
        }

        if (current_idx == idx) {
            out.* = data + offset;
            out_len.* = tga_size;

            return true;
        }

        current_idx += 1;
        offset += tga_size;
    }

    return false;
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

/// Validate a MeshShapeHeader at a given payload offset.
/// Returns true if the header looks sane: flag==1, padding==0, vertex_count reasonable,
/// and radius/center are finite floats.
fn validateMeshShapeHeader(payload: [*]const u8, payload_len: usize, header_offset: usize) bool {
    if (header_offset + @sizeOf(MeshShapeHeader) > payload_len) {
        return false;
    }

    const p = payload + header_offset;

    const radius = readF32Le(p);
    if (!std.math.isFinite(radius)) {
        return false;
    }

    const cx = readF32Le(p + 4);
    const cy = readF32Le(p + 8);
    const cz = readF32Le(p + 12);

    if (!std.math.isFinite(cx) or !std.math.isFinite(cy) or !std.math.isFinite(cz)) {
        return false;
    }

    const flag = std.mem.readInt(u32, p[16..20], .little);

    if (flag != 1) {
        return false;
    }

    const padding = std.mem.readInt(u32, p[24..28], .little);

    if (padding != 0) {
        return false;
    }

    const vertex_count = std.mem.readInt(u32, p[28..32], .little);

    if (vertex_count == 0 or vertex_count > 100_000) {
        return false;
    }

    // Position sanity check for first vertex data after header
    const vtx_start = header_offset + @sizeOf(MeshShapeHeader);

    if (vtx_start + 32 <= payload_len) {
        const px = readF32Le(payload + vtx_start);
        const py = readF32Le(payload + vtx_start + 4);
        const pz = readF32Le(payload + vtx_start + 8);

        if (@abs(px) > 50000 or @abs(py) > 50000 or @abs(pz) > 50000) {
            return false;
        }

        const nx = readF32Le(payload + vtx_start + 12);
        const ny = readF32Le(payload + vtx_start + 16);
        const nz = readF32Le(payload + vtx_start + 20);

        const nlen = @sqrt(nx * nx + ny * ny + nz * nz);

        if (nlen > 0.01 and @abs(nlen - 1.0) > 0.5) {
            return false;
        }
    }

    return true;
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

    // Greedily count ASCII digit bytes after null terminator
    const tag = data[reader.seek..data_len];
    var greedy_tag_len: usize = 0;

    while (greedy_tag_len < tag.len and std.ascii.isDigit(tag[greedy_tag_len])) : (greedy_tag_len += 1) {}

    // For MeshShape records, the greedy tag may have consumed bytes that are actually
    // part of the 32-byte header (the LSB of the radius float can be in 0x30-0x39 range).
    // Probe from shortest tag (0) to greedy length, and pick the first that yields a
    // valid MeshShapeHeader.
    var actual_tag_len: usize = greedy_tag_len;

    if (out.ty == .mesh_shape and greedy_tag_len > 0) {
        const payload_start = reader.seek;
        const payload_available = out.size - (reader.seek - start_idx);

        var best_tag_len: usize = greedy_tag_len;
        var found_valid: bool = false;

        // Try tag lengths from 0 up to greedy_tag_len, prefer the longest valid one
        // that still produces a sane header. Start from greedy and work backwards
        // to prefer the most specific tag match.
        var probe_len = greedy_tag_len;

        while (true) : (probe_len -= 1) {
            const header_offset = probe_len;

            if (validateMeshShapeHeader(data + payload_start, payload_available, header_offset)) {
                best_tag_len = probe_len;
                found_valid = true;
            }

            if (probe_len == 0) {
                break;
            }
        }

        if (found_valid) {
            actual_tag_len = best_tag_len;
        }
    }

    out.tag = tag.ptr;
    out.tag_len = actual_tag_len;

    reader.discardAll(actual_tag_len) catch {
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

/// Check whether a candidate stride yields a valid trailer and vertex data.
fn validateStride(record: *const Record, header: *const MeshShapeHeader, stride: u32) bool {
    if (stride == 0 or stride > 256) {
        return false;
    }

    if (header.vertex_count > 100_000) {
        return false;
    }

    const vtx_start: usize = @sizeOf(MeshShapeHeader);
    const vtx_data_len: usize = @as(usize, header.vertex_count) * stride;
    const trailer_offset: usize = vtx_start + vtx_data_len;

    // Check that there's room for the trailer header (12 bytes)
    if (trailer_offset + 12 > record.data_len) {
        return false;
    }

    var reader: std.Io.Reader = .fixed(record.data[trailer_offset..record.data_len]);

    const t1 = reader.takeInt(u32, .little) catch {
        return false;
    };

    const t2 = reader.takeInt(u32, .little) catch {
        return false;
    };

    const t3 = reader.takeInt(u32, .little) catch {
        return false;
    };

    // Validate trailer: primitive_type must be 1 (strip) or 4 (list), flag must be 1,
    // index_count must be reasonable
    if ((t1 != 1 and t1 != 4) or t2 != 1 or t3 == 0 or t3 > 100_000) {
        return false;
    }

    // Check that indices fit exactly within the record
    const idx_end: usize = trailer_offset + 12 + @as(usize, t3) * 2;

    if (idx_end != record.data_len) {
        return false;
    }

    // Validate first index is within vertex range
    if (t3 >= 2) {
        const first_idx = std.mem.readInt(u16, record.data[trailer_offset + 12 ..][0..2], .little);

        if (first_idx > header.vertex_count) {
            return false;
        }
    }

    // Validate first vertex: position should be in reasonable range,
    // normal should be approximately unit length
    if (vtx_start + stride <= record.data_len and stride >= 24) {
        const px = readF32Le(record.data[vtx_start..]);
        const py = readF32Le(record.data[vtx_start + 4 ..]);
        const pz = readF32Le(record.data[vtx_start + 8 ..]);

        if (@abs(px) > 50000 or @abs(py) > 50000 or @abs(pz) > 50000) {
            return false;
        }

        const nx = readF32Le(record.data[vtx_start + 12 ..]);
        const ny = readF32Le(record.data[vtx_start + 16 ..]);
        const nz = readF32Le(record.data[vtx_start + 20 ..]);

        const nlen = @sqrt(nx * nx + ny * ny + nz * nz);

        if (nlen > 0.01 and @abs(nlen - 1.0) > 0.5) {
            return false;
        }
    }

    return true;
}

pub export fn kats_model_guess_mesh_shape_stride(record: *const Record, header: *const MeshShapeHeader, out: *u32) callconv(.c) bool {
    if (header.vertex_count == 0 or header.vertex_count > 100_000) {
        return false;
    }

    const vtx_start: usize = @sizeOf(MeshShapeHeader);

    // Strategy 1: Scan for a valid trailer by computing stride from data_len constraints.
    // We know the record layout is: [header][vertex_data][trailer_header(12)][index_data].
    // For each possible index_count (reading from potential trailer positions),
    // we can compute the trailer_offset and derive the stride.
    // trailer_offset + 12 + index_count * 2 = data_len
    // vtx_start + vertex_count * stride = trailer_offset
    // So: stride = (data_len - 12 - index_count * 2 - vtx_start) / vertex_count
    //
    // We scan possible index_counts by probing potential trailer positions.

    // Scan for valid trailer at 4-byte aligned offsets after the minimum vertex data
    {
        const min_vertex_data: usize = @as(usize, header.vertex_count) * 24; // minimum stride = 24
        const scan_start: usize = vtx_start + min_vertex_data;

        // Try offsets in steps of vertex_count to find aligned strides
        var offset: usize = scan_start;

        while (offset + 12 <= record.data_len) {
            const remaining: usize = record.data_len - offset - 12;

            // The remaining bytes after the 12-byte trailer header must be an even number
            // (16-bit indices) and the index_count must match
            if (remaining % 2 == 0) {
                const potential_index_count: u32 = @intCast(remaining / 2);

                // Read potential trailer fields
                const t1 = std.mem.readInt(u32, record.data[offset..][0..4], .little);
                const t2 = std.mem.readInt(u32, record.data[offset + 4 ..][0..4], .little);
                const t3 = std.mem.readInt(u32, record.data[offset + 8 ..][0..4], .little);

                if ((t1 == 1 or t1 == 4) and t2 == 1 and t3 > 0 and t3 <= 100_000 and t3 == potential_index_count) {
                    // Compute stride from this trailer position
                    const vtx_data_len: usize = offset - vtx_start;

                    if (vtx_data_len % header.vertex_count == 0) {
                        const stride: u32 = @intCast(vtx_data_len / header.vertex_count);

                        if (stride >= 24 and stride <= 256 and validateStride(record, header, stride)) {
                            out.* = stride;

                            return true;
                        }
                    }
                }
            }

            // Advance by vertex_count bytes (keeps stride aligned) or by 4 if that's too large
            const step = if (header.vertex_count <= 64) @as(usize, header.vertex_count) else 4;
            offset += step;
        }
    }

    // Strategy 2: Fallback - try known stride values from the original hardcoded list.
    // This catches edge cases where the scan-based approach misses a valid stride
    // (e.g., when vertex_count is very large and the step size overshoots).
    const KNOWN_STRIDES = [_]u32{ 32, 48, 56, 60, 64, 36, 40, 44, 52, 24, 28, 72, 68, 76, 80 };

    for (KNOWN_STRIDES) |stride| {
        if (validateStride(record, header, stride)) {
            out.* = stride;

            return true;
        }
    }

    // Strategy 3: Last resort - try every 4-byte aligned stride from 24 to 256
    {
        var stride: u32 = 24;

        while (stride <= 256) : (stride += 4) {
            // Skip strides already tried in KNOWN_STRIDES
            var already_tried = false;

            for (KNOWN_STRIDES) |ks| {
                if (ks == stride) {
                    already_tried = true;

                    break;
                }
            }

            if (!already_tried and validateStride(record, header, stride)) {
                out.* = stride;

                return true;
            }
        }
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

const NameTagResult = struct {
    name: [*:0]const u8,
    end_offset: usize,
};

/// Read a null-terminated string from a record data payload.
/// Unlike readNameTagInPayload, this does NOT skip ASCII digit bytes after
/// the null terminator. The "digit tag" convention is specific to the record
/// header format (name + optional numeric tag). Within a record's data payload,
/// strings are simply null-terminated and the byte immediately after the null
/// belongs to the next field, not a tag.
///
/// Using readNameTagInPayload for data payloads was causing subtle offset bugs:
/// if the byte after a name's null terminator happened to fall in 0x30..0x39
/// (e.g. the LSB of a D3D material float like 0.7f -> [0x33,0x33,0x33,0x3F]),
/// it would be consumed as a "digit tag", shifting all subsequent reads.
fn readNullTermInPayload(payload: [*]const u8, payload_len: usize, offset: usize) ?NameTagResult {
    if (offset >= payload_len) {
        return null;
    }

    const bytes = payload[0..payload_len];

    var null_pos: usize = offset;

    while (null_pos < payload_len and bytes[null_pos] != 0) : (null_pos += 1) {}

    if (null_pos >= payload_len) {
        return null;
    }

    const name: [*:0]const u8 = @ptrCast(payload + offset);

    return .{
        .name = name,
        .end_offset = null_pos + 1,
    };
}

/// Read a null-terminated string followed by an optional numeric tag (ASCII
/// digit bytes) from a record HEADER. This is the original format where the
/// record name is followed by an optional sequence of ASCII digits used as a
/// disambiguation tag (e.g. "mesh\0" vs "mesh\01").
///
/// NOTE: Do NOT use this for reading strings from record DATA payloads.
/// Use readNullTermInPayload instead, since data payload strings do not have
/// digit tags and the next byte after null belongs to the following field.
fn readNameTagInPayload(payload: [*]const u8, payload_len: usize, offset: usize) ?NameTagResult {
    if (offset >= payload_len) {
        return null;
    }

    const bytes = payload[0..payload_len];

    var null_pos: usize = offset;

    while (null_pos < payload_len and bytes[null_pos] != 0) : (null_pos += 1) {}

    if (null_pos >= payload_len) {
        return null;
    }

    const name: [*:0]const u8 = @ptrCast(payload + offset);

    var pos: usize = null_pos + 1;

    while (pos < payload_len and bytes[pos] >= 0x30 and bytes[pos] <= 0x39) : (pos += 1) {}

    return .{
        .name = name,
        .end_offset = pos,
    };
}

pub export fn kats_model_get_vertex_format(stride: u32, out_has_color: *bool, out_has_skin: *bool, out_num_weights: *u32) callconv(.c) void {
    out_has_color.* = false;
    out_has_skin.* = false;
    out_num_weights.* = 0;

    switch (stride) {
        32 => {},
        48 => {
            out_has_color.* = true;
        },
        56 => {
            out_has_skin.* = true;
            out_num_weights.* = 2;
        },
        60 => {
            out_has_skin.* = true;
            out_num_weights.* = 3;
        },
        64 => {
            out_has_skin.* = true;
            out_num_weights.* = 4;
        },
        else => {},
    }
}

pub const MeshShapeVertexFull = extern struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    diffuse: [4]f32,
    weights: [4]f32,
    bone_indices: [4]f32,
    has_color: bool,
    has_skin: bool,
    num_weights: u32,
};

pub export fn kats_model_get_mesh_shape_vertex_full(record: *const Record, header: *const MeshShapeHeader, stride: u32, vertex_idx: u32, out: *MeshShapeVertexFull) callconv(.c) bool {
    if (vertex_idx >= header.vertex_count) {
        return false;
    }

    const vtx_offset: usize = @sizeOf(MeshShapeHeader) + @as(usize, vertex_idx) * stride;

    if (vtx_offset + stride > record.data_len) {
        return false;
    }

    out.* = std.mem.zeroes(MeshShapeVertexFull);

    var has_color: bool = undefined;
    var has_skin: bool = undefined;
    var num_weights: u32 = undefined;

    kats_model_get_vertex_format(stride, &has_color, &has_skin, &num_weights);

    out.has_color = has_color;
    out.has_skin = has_skin;
    out.num_weights = num_weights;

    const vtx = record.data[vtx_offset..record.data_len];

    // Position: offset 0
    out.position[0] = @bitCast(std.mem.readInt(u32, vtx[0..4], .little));
    out.position[1] = @bitCast(std.mem.readInt(u32, vtx[4..8], .little));
    out.position[2] = @bitCast(std.mem.readInt(u32, vtx[8..12], .little));

    // Normal: offset 12
    out.normal[0] = @bitCast(std.mem.readInt(u32, vtx[12..16], .little));
    out.normal[1] = @bitCast(std.mem.readInt(u32, vtx[16..20], .little));
    out.normal[2] = @bitCast(std.mem.readInt(u32, vtx[20..24], .little));

    // UV: offset (stride - 8)
    if (stride >= 32) {
        const uv_off: usize = stride - 8;

        out.uv[0] = @bitCast(std.mem.readInt(u32, vtx[uv_off .. uv_off + 4][0..4], .little));
        out.uv[1] = @bitCast(std.mem.readInt(u32, vtx[uv_off + 4 .. uv_off + 8][0..4], .little));
    }

    if (has_color) {
        out.diffuse[0] = @bitCast(std.mem.readInt(u32, vtx[24..28], .little));
        out.diffuse[1] = @bitCast(std.mem.readInt(u32, vtx[28..32], .little));
        out.diffuse[2] = @bitCast(std.mem.readInt(u32, vtx[32..36], .little));
        out.diffuse[3] = @bitCast(std.mem.readInt(u32, vtx[36..40], .little));
    }

    if (has_skin) {
        var raw_weights = [4]f32{ 0.0, 0.0, 0.0, 0.0 };

        for (0..num_weights) |w_idx| {
            const w_off: usize = 24 + w_idx * 4;

            raw_weights[w_idx] = @bitCast(std.mem.readInt(u32, vtx[w_off .. w_off + 4][0..4], .little));
        }

        if (num_weights == 2) {
            raw_weights[2] = 0.0;
            raw_weights[3] = 0.0;
        } else if (num_weights == 3) {
            const sum3 = raw_weights[0] + raw_weights[1] + raw_weights[2];

            raw_weights[3] = if (sum3 < 1.0) 1.0 - sum3 else 0.0;
        }

        const wsum = raw_weights[0] + raw_weights[1] + raw_weights[2] + raw_weights[3];

        if (wsum > 0.0001) {
            out.weights[0] = raw_weights[0] / wsum;
            out.weights[1] = raw_weights[1] / wsum;
            out.weights[2] = raw_weights[2] / wsum;
            out.weights[3] = raw_weights[3] / wsum;
        } else {
            out.weights = .{ 1.0, 0.0, 0.0, 0.0 };
        }

        const bi_off: usize = 24 + @as(usize, num_weights) * 4;

        out.bone_indices[0] = @bitCast(std.mem.readInt(u32, vtx[bi_off .. bi_off + 4][0..4], .little));
        out.bone_indices[1] = @bitCast(std.mem.readInt(u32, vtx[bi_off + 4 .. bi_off + 8][0..4], .little));
        out.bone_indices[2] = @bitCast(std.mem.readInt(u32, vtx[bi_off + 8 .. bi_off + 12][0..4], .little));
        out.bone_indices[3] = @bitCast(std.mem.readInt(u32, vtx[bi_off + 12 .. bi_off + 16][0..4], .little));
    }

    return true;
}

pub const Material = extern struct {
    sub_count: u32,
    texture_name: [*:0]const u8,
    diffuse: [4]f32,
    ambient: [4]f32,
    specular: [4]f32,
    emissive: [4]f32,
    power: f32,
    has_d3d_material: bool,
    _bone_refs_offset: usize,
    _bone_refs_count: u32,
};

pub export fn kats_model_get_material(record: *const Record, out: *Material) callconv(.c) bool {
    if (record.ty != .material) {
        return false;
    }

    if (record.data_len < 4) {
        return false;
    }

    out.* = std.mem.zeroes(Material);

    out.sub_count = std.mem.readInt(u32, record.data[0..4], .little);

    const nt = readNullTermInPayload(record.data, record.data_len, 4) orelse {
        out.texture_name = @ptrCast(@alignCast(&empty_string));
        out._bone_refs_offset = 4;

        return true;
    };

    out.texture_name = nt.name;

    var pp: usize = nt.end_offset;

    if (pp + 68 <= record.data_len) {
        out.has_d3d_material = true;

        for (0..4) |comp| {
            out.diffuse[comp] = @bitCast(std.mem.readInt(u32, record.data[pp + comp * 4 .. pp + comp * 4 + 4][0..4], .little));
            out.ambient[comp] = @bitCast(std.mem.readInt(u32, record.data[pp + 16 + comp * 4 .. pp + 16 + comp * 4 + 4][0..4], .little));
            out.specular[comp] = @bitCast(std.mem.readInt(u32, record.data[pp + 32 + comp * 4 .. pp + 32 + comp * 4 + 4][0..4], .little));
            out.emissive[comp] = @bitCast(std.mem.readInt(u32, record.data[pp + 48 + comp * 4 .. pp + 48 + comp * 4 + 4][0..4], .little));
        }

        out.power = @bitCast(std.mem.readInt(u32, record.data[pp + 64 .. pp + 68][0..4], .little));
        pp += 68;
    }

    out._bone_refs_offset = pp;
    out._bone_refs_count = 0;

    // Try to locate the actual bone name strings.
    // The data after the D3D material may contain a bone palette index array
    // (sub_count * 4 bytes of u32) before the null-terminated bone names.
    // We scan from the current offset looking for a region where we can read
    // `sub_count` consecutive valid null-terminated ASCII strings.
    if (out.sub_count > 0 and out.sub_count < 30) {
        var best_offset: usize = pp;
        var best_count: u32 = 0;

        // Try offsets: current, current+4*sub_count, and a few other candidates
        const candidates = [_]usize{
            pp,
            pp + @as(usize, out.sub_count) * 4,
            pp + @as(usize, out.sub_count) * 2, // u16 indices
            pp + 4, // single u32 count
        };

        for (candidates) |try_offset| {
            if (try_offset >= record.data_len) continue;

            var off: usize = try_offset;
            var cnt: u32 = 0;

            while (cnt < out.sub_count and cnt < 30) {
                const br_nt = readNullTermInPayload(record.data, record.data_len, off) orelse {
                    break;
                };

                // Validate: bone name should contain only printable ASCII
                const name_slice = std.mem.span(br_nt.name);
                var valid = true;

                for (name_slice) |b| {
                    if (b < 0x20 or b > 0x7e) {
                        valid = false;

                        break;
                    }
                }

                // Empty names are technically valid (some bones may be unnamed)
                // but if we see non-printable chars, this offset is wrong
                if (!valid) {
                    break;
                }

                cnt += 1;
                off = br_nt.end_offset;
            }

            if (cnt > best_count) {
                best_count = cnt;
                best_offset = try_offset;
            }

            // If we got all sub_count strings, this is the right offset
            if (cnt == out.sub_count) {
                break;
            }
        }

        out._bone_refs_offset = best_offset;
        out._bone_refs_count = best_count;
    }

    return true;
}

const empty_string: [1]u8 = .{0};

pub export fn kats_model_get_material_bone_ref_count(record: *const Record, material: *const Material) callconv(.c) usize {
    // Use the pre-computed count from kats_model_get_material which already
    // validated the bone names for printable ASCII.
    if (material._bone_refs_count > 0) {
        return material._bone_refs_count;
    }

    // Fallback: count valid null-terminated strings
    var offset: usize = material._bone_refs_offset;
    var count: usize = 0;

    while (count < material.sub_count and count < 30) {
        const nt = readNullTermInPayload(record.data, record.data_len, offset) orelse {
            break;
        };

        // Validate: bone name should contain only printable ASCII
        const name_slice = std.mem.span(nt.name);
        var valid = true;

        for (name_slice) |b| {
            if (b < 0x20 or b > 0x7e) {
                valid = false;

                break;
            }
        }

        if (!valid) {
            break;
        }

        count += 1;
        offset = nt.end_offset;
    }

    return count;
}

pub export fn kats_model_get_material_bone_ref(record: *const Record, material: *const Material, idx: usize, out_name: *[*:0]const u8) callconv(.c) bool {
    var offset: usize = material._bone_refs_offset;
    var count: usize = 0;

    while (count <= idx and count < material.sub_count and count < 30) {
        const nt = readNullTermInPayload(record.data, record.data_len, offset) orelse {
            return false;
        };

        // Validate: bone name should contain only printable ASCII
        const name_slice = std.mem.span(nt.name);
        var valid = true;

        for (name_slice) |b| {
            if (b < 0x20 or b > 0x7e) {
                valid = false;

                break;
            }
        }

        if (!valid) {
            return false;
        }

        if (count == idx) {
            out_name.* = nt.name;

            return true;
        }

        count += 1;
        offset = nt.end_offset;
    }

    return false;
}

pub const ShapeRefHeader = extern struct {
    ref_count: u32,
};

pub export fn kats_model_get_shape_ref_header(record: *const Record, out: *ShapeRefHeader) callconv(.c) bool {
    if (record.ty != .shape_ref) {
        return false;
    }

    if (record.data_len < 4) {
        return false;
    }

    out.ref_count = std.mem.readInt(u32, record.data[0..4], .little);

    return true;
}

pub export fn kats_model_get_shape_ref_binding(record: *const Record, idx: usize, out_material_name: *[*:0]const u8, out_shape_name: *[*:0]const u8) callconv(.c) bool {
    if (record.ty != .shape_ref) {
        return false;
    }

    if (record.data_len < 4) {
        return false;
    }

    const ref_count = std.mem.readInt(u32, record.data[0..4], .little);

    if (idx >= ref_count) {
        return false;
    }

    var offset: usize = 4;
    var count: usize = 0;

    while (count <= idx) {
        const mat_nt = readNullTermInPayload(record.data, record.data_len, offset) orelse {
            return false;
        };

        const shape_nt = readNullTermInPayload(record.data, record.data_len, mat_nt.end_offset) orelse {
            return false;
        };

        if (count == idx) {
            out_material_name.* = mat_nt.name;
            out_shape_name.* = shape_nt.name;

            return true;
        }

        count += 1;
        offset = shape_nt.end_offset;
    }

    return false;
}

pub const TextureRef = extern struct {
    texture_set_name: [*:0]const u8,
    texture_file: [*:0]const u8,
    tex_params: [6]u32,
    has_params: bool,
};

pub export fn kats_model_get_texture_ref(record: *const Record, out: *TextureRef) callconv(.c) bool {
    if (record.ty != .texture_ref) {
        return false;
    }

    out.* = std.mem.zeroes(TextureRef);
    out.texture_set_name = record.name;

    const file_nt = readNullTermInPayload(record.data, record.data_len, 0) orelse {
        out.texture_file = @ptrCast(@alignCast(&empty_string));

        return true;
    };

    out.texture_file = file_nt.name;

    if (file_nt.end_offset + 24 <= record.data_len) {
        for (0..6) |param_idx| {
            const p_off = file_nt.end_offset + param_idx * 4;

            out.tex_params[param_idx] = std.mem.readInt(u32, record.data[p_off .. p_off + 4][0..4], .little);
        }

        out.has_params = true;
    }

    return true;
}

pub const TransformNode = extern struct {
    flag: u32,
    translation: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
};

pub export fn kats_model_get_transform_node(record: *const Record, out: *TransformNode) callconv(.c) bool {
    if (record.ty != .transform_node) {
        return false;
    }

    if (record.data_len < 40) {
        return false;
    }

    out.flag = std.mem.readInt(u32, record.data[0..4], .little);

    for (0..3) |comp| {
        out.translation[comp] = @bitCast(std.mem.readInt(u32, record.data[4 + comp * 4 .. 8 + comp * 4][0..4], .little));
        out.rotation[comp] = @bitCast(std.mem.readInt(u32, record.data[16 + comp * 4 .. 20 + comp * 4][0..4], .little));
        out.scale[comp] = @bitCast(std.mem.readInt(u32, record.data[28 + comp * 4 .. 32 + comp * 4][0..4], .little));
    }

    return true;
}

pub const SkeletonRoot = extern struct {
    val1: u32,
    val2: u32,
    skeleton_shape_ref: [*:0]const u8,
};

pub export fn kats_model_get_skeleton_root(record: *const Record, out: *SkeletonRoot) callconv(.c) bool {
    if (record.ty != .skeleton_root) {
        return false;
    }

    if (record.data_len < 8) {
        return false;
    }

    out.val1 = std.mem.readInt(u32, record.data[0..4], .little);
    out.val2 = std.mem.readInt(u32, record.data[4..8], .little);

    const shape_nt = readNullTermInPayload(record.data, record.data_len, 8) orelse {
        out.skeleton_shape_ref = @ptrCast(@alignCast(&empty_string));

        return true;
    };

    out.skeleton_shape_ref = shape_nt.name;

    return true;
}

pub const Joint = extern struct {
    flag: u32,
    translation: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
    inv_bind_matrix_3x4: [12]f32,
    has_inv_bind_matrix: bool,
    extra_data: [*]const u8,
    extra_data_len: usize,
};

pub export fn kats_model_get_joint(record: *const Record, out: *Joint) callconv(.c) bool {
    if (record.ty != .joint) {
        return false;
    }

    if (record.data_len < 40) {
        return false;
    }

    out.* = std.mem.zeroes(Joint);

    out.flag = std.mem.readInt(u32, record.data[0..4], .little);

    for (0..3) |comp| {
        out.translation[comp] = @bitCast(std.mem.readInt(u32, record.data[4 + comp * 4 .. 8 + comp * 4][0..4], .little));
        out.rotation[comp] = @bitCast(std.mem.readInt(u32, record.data[16 + comp * 4 .. 20 + comp * 4][0..4], .little));
        out.scale[comp] = @bitCast(std.mem.readInt(u32, record.data[28 + comp * 4 .. 32 + comp * 4][0..4], .little));
    }

    if (record.data_len >= 88) {
        out.has_inv_bind_matrix = true;

        for (0..12) |mat_idx| {
            const m_off: usize = 40 + mat_idx * 4;

            out.inv_bind_matrix_3x4[mat_idx] = @bitCast(std.mem.readInt(u32, record.data[m_off .. m_off + 4][0..4], .little));
        }

        if (record.data_len > 88) {
            out.extra_data = record.data + 88;
            out.extra_data_len = record.data_len - 88;
        }
    }

    return true;
}

pub const KeyframeChannel = extern struct {
    target_node: [*]const u8,
    target_node_len: usize,
    channel_type: [*]const u8,
    channel_type_len: usize,
    flag: u32,
    kf_count: u32,
    keyframes: [*]const f32,
};

pub export fn kats_model_get_keyframe_channel(record: *const Record, out: *KeyframeChannel) callconv(.c) bool {
    if (record.ty != .keyframe_channel) {
        return false;
    }

    if (record.data_len < 8) {
        return false;
    }

    out.* = std.mem.zeroes(KeyframeChannel);

    // record.name is the full channel name: {target_node}_{channel_type}
    // rsplit on last '_' to separate target_node and channel_type
    const full_name = std.mem.span(record.name);
    const name_len = full_name.len;

    var last_underscore: usize = name_len;
    {
        var pos: usize = name_len;
        while (pos > 0) : (pos -= 1) {
            if (full_name[pos - 1] == '_') {
                last_underscore = pos - 1;

                break;
            }
        }
    }

    if (last_underscore < name_len) {
        out.target_node = record.name;
        out.target_node_len = last_underscore;
        out.channel_type = record.name + last_underscore + 1;
        out.channel_type_len = name_len - last_underscore - 1;
    } else {
        out.target_node = record.name;
        out.target_node_len = name_len;
        out.channel_type = record.name + name_len;
        out.channel_type_len = 0;
    }

    // Validate channel type
    const VALID_TYPES = [_][]const u8{ "tx", "ty", "tz", "rx", "ry", "rz", "sx", "sy", "sz" };
    const ch_type_slice = out.channel_type[0..out.channel_type_len];

    var valid = false;

    for (VALID_TYPES) |vt| {
        if (std.mem.eql(u8, ch_type_slice, vt)) {
            valid = true;

            break;
        }
    }

    if (!valid) {
        return false;
    }

    out.flag = std.mem.readInt(u32, record.data[0..4], .little);
    out.kf_count = std.mem.readInt(u32, record.data[4..8], .little);

    if (out.kf_count > 100_000) {
        return false;
    }

    const kf_data_size: usize = @as(usize, out.kf_count) * 8;

    if (8 + kf_data_size > record.data_len) {
        return false;
    }

    out.keyframes = @ptrCast(@alignCast(record.data + 8));

    return true;
}

pub const AnimSet = extern struct {
    channel_count: u32,
};

pub export fn kats_model_get_anim_set(record: *const Record, out: *AnimSet) callconv(.c) bool {
    if (record.ty != .anim_set) {
        return false;
    }

    if (record.data_len < 4) {
        return false;
    }

    out.channel_count = std.mem.readInt(u32, record.data[0..4], .little);

    return true;
}

const JointParentRule = struct {
    pattern: []const u8,
    parent: ?[]const u8,
};

const JOINT_PARENT_RULES = [_]JointParentRule{
    .{ .pattern = "koshi", .parent = null },
    .{ .pattern = "spine1", .parent = "koshi" },
    .{ .pattern = "spine2", .parent = "spine1" },
    .{ .pattern = "neck", .parent = "spine2" },
    .{ .pattern = "head", .parent = "neck" },
    .{ .pattern = "sholderL1", .parent = "spine2" },
    .{ .pattern = "sholderL2", .parent = "sholderL1" },
    .{ .pattern = "udeL1", .parent = "sholderL2" },
    .{ .pattern = "udeL2", .parent = "udeL1" },
    .{ .pattern = "teL", .parent = "udeL2" },
    .{ .pattern = "sholderR1", .parent = "spine2" },
    .{ .pattern = "sholderR2", .parent = "sholderR1" },
    .{ .pattern = "udeR1", .parent = "sholderR2" },
    .{ .pattern = "udeR2", .parent = "udeR1" },
    .{ .pattern = "teR", .parent = "udeR2" },
    .{ .pattern = "momoL1", .parent = "koshi" },
    .{ .pattern = "momoL2", .parent = "momoL1" },
    .{ .pattern = "hizaL", .parent = "momoL2" },
    .{ .pattern = "suneL", .parent = "hizaL" },
    .{ .pattern = "ashiL", .parent = "suneL" },
    .{ .pattern = "momoR1", .parent = "koshi" },
    .{ .pattern = "momoR2", .parent = "momoR1" },
    .{ .pattern = "hizaR", .parent = "momoR2" },
    .{ .pattern = "suneR", .parent = "hizaR" },
    .{ .pattern = "ashiR", .parent = "suneR" },
    .{ .pattern = "hairBase", .parent = "head" },
    .{ .pattern = "hairL", .parent = "hairBase" },
    .{ .pattern = "hairR", .parent = "hairBase" },
    .{ .pattern = "hairBack", .parent = "hairBase" },
    .{ .pattern = "hatBase", .parent = "head" },
};

fn ciContains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) {
        return false;
    }

    for (0..haystack.len - needle.len + 1) |start| {
        var match = true;

        for (needle, 0..) |nc, offset| {
            var hc = haystack[start + offset];
            var ncc = nc;

            if (hc >= 'A' and hc <= 'Z') {
                hc += 32;
            }

            if (ncc >= 'A' and ncc <= 'Z') {
                ncc += 32;
            }

            if (hc != ncc) {
                match = false;

                break;
            }
        }

        if (match) {
            return true;
        }
    }

    return false;
}

fn ciEqual(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }

    for (a, b) |ac, bc| {
        var lc_a = ac;
        var lc_b = bc;

        if (lc_a >= 'A' and lc_a <= 'Z') {
            lc_a += 32;
        }

        if (lc_b >= 'A' and lc_b <= 'Z') {
            lc_b += 32;
        }

        if (lc_a != lc_b) {
            return false;
        }
    }

    return true;
}

pub export fn kats_infer_joint_parent(joint_name: [*:0]const u8, all_joint_names: [*]const [*:0]const u8, joint_count: usize, out_parent_name: *?[*:0]const u8) callconv(.c) bool {
    const jname = std.mem.span(joint_name);
    out_parent_name.* = null;

    // Check known patterns (case-insensitive substring match)
    for (JOINT_PARENT_RULES) |rule| {
        if (ciContains(jname, rule.pattern)) {
            if (rule.parent == null) {
                // Root joint
                return true;
            }

            // Find parent in joint list
            for (0..joint_count) |jdx| {
                const candidate = std.mem.span(all_joint_names[jdx]);

                if (ciContains(candidate, rule.parent.?)) {
                    out_parent_name.* = all_joint_names[jdx];

                    return true;
                }
            }
        }
    }

    // Heuristic: name ends with digit N > 1 - parent is prefix + (N-1)
    if (jname.len > 1) {
        var digit_start = jname.len;

        while (digit_start > 0 and jname[digit_start - 1] >= '0' and jname[digit_start - 1] <= '9') {
            digit_start -= 1;
        }

        if (digit_start < jname.len and digit_start > 0) {
            const suffix = std.fmt.parseInt(u32, jname[digit_start..], 10) catch {
                return true;
            };

            if (suffix > 1) {
                var buf: [256]u8 = undefined;
                const prefix = jname[0..digit_start];

                if (prefix.len + 10 > buf.len) {
                    return true;
                }

                @memcpy(buf[0..prefix.len], prefix);

                const suffix_str = std.fmt.bufPrint(buf[prefix.len..], "{d}", .{suffix - 1}) catch {
                    return true;
                };

                const candidate = buf[0 .. prefix.len + suffix_str.len];

                for (0..joint_count) |jdx| {
                    if (ciEqual(std.mem.span(all_joint_names[jdx]), candidate)) {
                        out_parent_name.* = all_joint_names[jdx];

                        return true;
                    }
                }
            }
        }
    }

    // No parent found - treat as root
    return true;
}

/// Animation file record types (reuse ModelRecordType since animation files
/// use the same TLV format with types 7, 8, 9).
pub export fn kats_animation_count_records(data: [*]const u8, data_len: usize) callconv(.c) usize {
    return kats_model_count_records(data, data_len);
}

pub export fn kats_animation_get_record(data: [*]const u8, data_len: usize, idx: usize, out: *Record) callconv(.c) bool {
    return kats_model_get_record(data, data_len, idx, out);
}

pub const AnimRef = extern struct {
    anim_set_name: [*:0]const u8,
};

pub export fn kats_animation_get_anim_ref(record: *const Record, out: *AnimRef) callconv(.c) bool {
    if (record.ty != .anim_ref) {
        return false;
    }

    if (record.data_len < 1) {
        return false;
    }

    // The AnimRef payload contains a null-terminated name of the AnimSet it references.
    const nt = readNullTermInPayload(record.data, record.data_len, 0) orelse {
        // Fallback: use the record's own name if no name found in payload
        out.anim_set_name = record.name;

        return true;
    };

    out.anim_set_name = nt.name;

    return true;
}

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

        kats_tools.kats_decrypt(std.mem.readInt(u32, meta.xor_key[0..4], .little), file_content.ptr, file_content.len);

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

const Binding = struct {
    material_name: []const u8,
    shape_name: []const u8,
};

const MeshData = struct {
    record: kats_tools.Record,
    header: kats_tools.MeshShapeHeader,
    stride: u32,
    trailer: kats_tools.ModelShapeTrailer,
    tri_indices: []u16,
};

const ShapeRefData = struct {
    name: []const u8,
    bindings: []Binding,
};

fn writeJsonFloatArray(writer: *std.Io.Writer, values: []const f32) !void {
    try writer.writeAll("[");

    for (values, 0..) |val, vidx| {
        if (vidx > 0) {
            try writer.writeAll(", ");
        }

        try writer.print("{d:.6}", .{val});
    }

    try writer.writeAll("]");
}

fn writeJsonU32Array(writer: *std.Io.Writer, values: []const u32) !void {
    try writer.writeAll("[");

    for (values, 0..) |val, vidx| {
        if (vidx > 0) {
            try writer.writeAll(", ");
        }

        try writer.print("{d}", .{val});
    }

    try writer.writeAll("]");
}

fn convertModel(init: std.process.Init, file_content: []const u8, out_dir: []const u8, sub_path: []const u8, ok: *bool) !void {
    const record_count = kats_tools.kats_model_count_records(file_content.ptr, file_content.len);

    std.debug.print("Records: {d}\n", .{record_count});

    if (record_count == 0) {
        std.debug.print("Bad model file: {s}\n", .{sub_path});
        ok.* = false;

        return;
    }

    var mesh_map: std.array_hash_map.String(MeshData) = .empty;
    defer {
        var it = mesh_map.iterator();

        while (it.next()) |entry| {
            init.gpa.free(entry.value_ptr.tri_indices);
        }

        mesh_map.deinit(init.gpa);
    }

    var material_map: std.array_hash_map.String(kats_tools.Record) = .empty;
    defer material_map.deinit(init.gpa);

    var shape_ref_list: std.ArrayList(ShapeRefData) = .empty;
    defer {
        for (shape_ref_list.items) |sr| {
            init.gpa.free(sr.bindings);
        }
        shape_ref_list.deinit(init.gpa);
    }

    var texture_ref_map: std.array_hash_map.String(kats_tools.Record) = .empty;
    defer texture_ref_map.deinit(init.gpa);

    var transform_map: std.array_hash_map.String(kats_tools.TransformNode) = .empty;
    defer transform_map.deinit(init.gpa);

    var skeleton_root_list: std.ArrayList(kats_tools.Record) = .empty;
    defer skeleton_root_list.deinit(init.gpa);

    var joint_list: std.ArrayList(kats_tools.Record) = .empty;
    defer joint_list.deinit(init.gpa);

    var referenced_meshes = std.StringHashMapUnmanaged(void){};
    defer referenced_meshes.deinit(init.gpa);

    for (0..record_count) |rec_idx| {
        var record: kats_tools.Record = undefined;

        if (!kats_tools.kats_model_get_record(file_content.ptr, file_content.len, rec_idx, &record)) {
            std.debug.print("Failed to parse record {d}\n", .{rec_idx});

            continue;
        }

        const rec_name = std.mem.span(record.name);

        switch (record.ty) {
            .mesh_shape => {
                var mesh_header: kats_tools.MeshShapeHeader = undefined;

                if (!kats_tools.kats_model_get_mesh_shape_header(&record, &mesh_header)) {
                    std.debug.print("Bad mesh shape header for record {d} ({s})\n", .{ rec_idx, rec_name });
                    ok.* = false;

                    continue;
                }

                var stride: u32 = undefined;

                if (!kats_tools.kats_model_guess_mesh_shape_stride(&record, &mesh_header, &stride)) {
                    std.debug.print("Failed to detect stride for mesh {d} ({s})\n", .{ rec_idx, rec_name });
                    ok.* = false;

                    continue;
                }

                var trailer: kats_tools.ModelShapeTrailer = undefined;

                if (!kats_tools.kats_model_get_mesh_shape_trailer(&record, &mesh_header, stride, &trailer)) {
                    std.debug.print("Failed to get trailer for mesh {d} ({s})\n", .{ rec_idx, rec_name });
                    ok.* = false;

                    continue;
                }

                const tri_count = kats_tools.kats_model_mesh_shape_triangle_list_index_count(&trailer);

                if (tri_count == 0) {
                    continue;
                }

                const tri_indices = try init.gpa.alloc(u16, tri_count);
                errdefer init.gpa.free(tri_indices);

                if (!kats_tools.kats_model_mesh_shape_to_triangle_list(&trailer, tri_indices.ptr, tri_indices.len)) {
                    init.gpa.free(tri_indices);
                    std.debug.print("Failed to convert indices for mesh {d} ({s})\n", .{ rec_idx, rec_name });
                    ok.* = false;

                    continue;
                }

                try mesh_map.put(init.gpa, rec_name, .{
                    .record = record,
                    .header = mesh_header,
                    .stride = stride,
                    .trailer = trailer,
                    .tri_indices = tri_indices,
                });
            },
            .material => {
                try material_map.put(init.gpa, rec_name, record);
            },
            .shape_ref => {
                var sr_header: kats_tools.ShapeRefHeader = undefined;

                if (!kats_tools.kats_model_get_shape_ref_header(&record, &sr_header)) {
                    continue;
                }

                var bindings: std.ArrayList(Binding) = .empty;
                errdefer bindings.deinit(init.gpa);

                for (0..sr_header.ref_count) |bind_idx| {
                    var mat_name: [*:0]const u8 = undefined;
                    var shape_name: [*:0]const u8 = undefined;

                    if (!kats_tools.kats_model_get_shape_ref_binding(&record, bind_idx, &mat_name, &shape_name)) {
                        break;
                    }

                    try bindings.append(init.gpa, .{
                        .material_name = std.mem.span(mat_name),
                        .shape_name = std.mem.span(shape_name),
                    });

                    try referenced_meshes.put(init.gpa, std.mem.span(shape_name), {});
                }

                try shape_ref_list.append(init.gpa, .{
                    .name = rec_name,
                    .bindings = try bindings.toOwnedSlice(init.gpa),
                });
            },
            .texture_ref => {
                try texture_ref_map.put(init.gpa, rec_name, record);
            },
            .transform_node => {
                var tn: kats_tools.TransformNode = undefined;

                if (kats_tools.kats_model_get_transform_node(&record, &tn)) {
                    try transform_map.put(init.gpa, rec_name, tn);
                }
            },
            .skeleton_root => {
                try skeleton_root_list.append(init.gpa, record);
            },
            .joint => {
                try joint_list.append(init.gpa, record);
            },
            else => {},
        }
    }

    std.debug.print("  Meshes: {d}, Materials: {d}, ShapeRefs: {d}, TextureRefs: {d}, Transforms: {d}, SkelRoots: {d}, Joints: {d}\n", .{
        mesh_map.values().len,
        material_map.values().len,
        shape_ref_list.items.len,
        texture_ref_map.values().len,
        transform_map.values().len,
        skeleton_root_list.items.len,
        joint_list.items.len,
    });

    // Build skeleton groups (joints grouped by their preceding SkeletonRoot)
    const SkeletonGroup = struct {
        root_record: kats_tools.Record,
        joint_records: []kats_tools.Record,
    };

    var skeleton_groups: std.ArrayList(SkeletonGroup) = .empty;
    defer {
        for (skeleton_groups.items) |sg| {
            init.gpa.free(sg.joint_records);
        }

        skeleton_groups.deinit(init.gpa);
    }

    {
        var current_root: ?kats_tools.Record = null;
        var current_joints: std.ArrayList(kats_tools.Record) = .empty;
        defer current_joints.deinit(init.gpa);

        for (0..record_count) |rec_idx| {
            var record: kats_tools.Record = undefined;

            if (!kats_tools.kats_model_get_record(file_content.ptr, file_content.len, rec_idx, &record)) {
                continue;
            }

            if (record.ty == .skeleton_root) {
                // Flush previous group
                if (current_root != null and current_joints.items.len > 0) {
                    const joints_copy = try init.gpa.dupe(kats_tools.Record, current_joints.items);

                    try skeleton_groups.append(init.gpa, .{
                        .root_record = current_root.?,
                        .joint_records = joints_copy,
                    });
                }

                current_root = record;
                current_joints.clearRetainingCapacity();
            } else if (record.ty == .joint) {
                if (current_root != null) {
                    try current_joints.append(init.gpa, record);
                }
            }
        }
        // Flush last group
        if (current_root != null and current_joints.items.len > 0) {
            const joints_copy = try init.gpa.dupe(kats_tools.Record, current_joints.items);

            try skeleton_groups.append(init.gpa, .{
                .root_record = current_root.?,
                .joint_records = joints_copy,
            });
        }
    }

    // Each ShapeRef defines one logical model. Meshes not in any ShapeRef get individual files.

    const ModelGroup = struct {
        name: []const u8,
        bindings: []const Binding,
    };

    var model_groups: std.ArrayList(ModelGroup) = .empty;
    defer model_groups.deinit(init.gpa);

    // Add ShapeRef-based groups
    for (shape_ref_list.items) |sr| {
        if (sr.bindings.len == 0) {
            continue;
        }

        try model_groups.append(init.gpa, .{
            .name = sr.name,
            .bindings = sr.bindings,
        });
    }

    // Add unreferenced meshes as individual groups
    var mesh_it = mesh_map.iterator();

    while (mesh_it.next()) |entry| {
        const mesh_name = entry.key_ptr.*;

        if (!referenced_meshes.contains(mesh_name)) {
            // Create a single-mesh group with no material
            const single_binding = try init.arena.allocator().create(Binding);

            single_binding.* = .{ .material_name = "", .shape_name = mesh_name };

            try model_groups.append(init.gpa, .{
                .name = mesh_name,
                .bindings = single_binding[0..1],
            });
        }
    }

    const base_dir = try std.fs.path.join(init.gpa, &.{ out_dir, withoutExt(sub_path) });
    defer init.gpa.free(base_dir);

    try std.Io.Dir.cwd().createDirPath(init.io, base_dir);

    for (model_groups.items) |group| {
        var obj_writer: std.Io.Writer.Allocating = .init(init.gpa);
        defer obj_writer.deinit();

        var mtl_writer: std.Io.Writer.Allocating = .init(init.gpa);
        defer mtl_writer.deinit();

        var json_writer: std.Io.Writer.Allocating = .init(init.gpa);
        defer json_writer.deinit();

        const mtl_filename = try std.fmt.allocPrint(init.gpa, "{s}.mtl", .{group.name});
        defer init.gpa.free(mtl_filename);

        try obj_writer.writer.print("mtllib {s}\n\n", .{mtl_filename});

        var used_materials = std.StringArrayHashMapUnmanaged(void){};
        defer used_materials.deinit(init.gpa);

        for (group.bindings) |binding| {
            if (binding.material_name.len > 0) {
                try used_materials.put(init.gpa, binding.material_name, {});
            }
        }

        var mat_iter = used_materials.iterator();
        while (mat_iter.next()) |mat_entry| {
            const mat_name = mat_entry.key_ptr.*;

            try mtl_writer.writer.print("newmtl {s}\n", .{mat_name});
            try mtl_writer.writer.writeAll("illum 2\n");

            if (material_map.getPtr(mat_name)) |mat_record| {
                var material: kats_tools.Material = undefined;

                if (kats_tools.kats_model_get_material(mat_record, &material)) {
                    if (material.has_d3d_material) {
                        try mtl_writer.writer.print("Ka {d:.6} {d:.6} {d:.6}\n", .{ material.ambient[0], material.ambient[1], material.ambient[2] });
                        try mtl_writer.writer.print("Kd {d:.6} {d:.6} {d:.6}\n", .{ material.diffuse[0], material.diffuse[1], material.diffuse[2] });
                        try mtl_writer.writer.print("Ks {d:.6} {d:.6} {d:.6}\n", .{ material.specular[0], material.specular[1], material.specular[2] });
                        try mtl_writer.writer.print("Ke {d:.6} {d:.6} {d:.6}\n", .{ material.emissive[0], material.emissive[1], material.emissive[2] });
                        try mtl_writer.writer.print("Ns {d:.6}\n", .{material.power});

                        if (material.diffuse[3] < 1.0) {
                            try mtl_writer.writer.print("d {d:.6}\n", .{material.diffuse[3]});
                        }
                    }

                    const tex_name = std.mem.span(material.texture_name);

                    if (tex_name.len > 0) {
                        try mtl_writer.writer.print("map_Kd {s}.tga\n", .{tex_name});
                    }
                }
            }

            try mtl_writer.writer.writeByte('\n');
        }

        var global_vtx_offset: usize = 0;

        for (group.bindings) |binding| {
            const mesh_entry = mesh_map.getPtr(binding.shape_name) orelse {
                std.debug.print("Warning: mesh '{s}' not found\n", .{binding.shape_name});

                continue;
            };

            const md = mesh_entry;
            const header = md.header;
            const stride = md.stride;
            const record = md.record;
            const tri_indices = md.tri_indices;
            const vertex_count: usize = header.vertex_count;
            const has_uv = stride >= 32;

            var has_color: bool = undefined;
            var has_skin: bool = undefined;
            var num_weights: u32 = undefined;

            kats_tools.kats_model_get_vertex_format(stride, &has_color, &has_skin, &num_weights);

            // Object group
            try obj_writer.writer.print("o {s}\n", .{binding.shape_name});

            if (binding.material_name.len > 0) {
                try obj_writer.writer.print("usemtl {s}\n", .{binding.material_name});
            }

            try obj_writer.writer.writeByte('\n');

            // Vertices
            for (0..vertex_count) |vtx_idx| {
                var vtx: kats_tools.MeshShapeVertexFull = undefined;

                if (!kats_tools.kats_model_get_mesh_shape_vertex_full(&record, &header, stride, @intCast(vtx_idx), &vtx)) {
                    try obj_writer.writer.writeAll("v 0.000000 0.000000 0.000000\n");

                    continue;
                }

                try obj_writer.writer.print("v {d:.6} {d:.6} {d:.6}\n", .{ vtx.position[0], vtx.position[1], vtx.position[2] });
            }

            try obj_writer.writer.writeByte('\n');

            // Normals
            for (0..vertex_count) |vtx_idx| {
                var vtx: kats_tools.MeshShapeVertexFull = undefined;

                if (!kats_tools.kats_model_get_mesh_shape_vertex_full(&record, &header, stride, @intCast(vtx_idx), &vtx)) {
                    try obj_writer.writer.writeAll("vn 0.000000 1.000000 0.000000\n");

                    continue;
                }

                try obj_writer.writer.print("vn {d:.6} {d:.6} {d:.6}\n", .{ vtx.normal[0], vtx.normal[1], vtx.normal[2] });
            }

            try obj_writer.writer.writeByte('\n');

            // UVs
            if (has_uv) {
                for (0..vertex_count) |vtx_idx| {
                    var vtx: kats_tools.MeshShapeVertexFull = undefined;

                    if (!kats_tools.kats_model_get_mesh_shape_vertex_full(&record, &header, stride, @intCast(vtx_idx), &vtx)) {
                        try obj_writer.writer.writeAll("vt 0.000000 0.000000\n");

                        continue;
                    }

                    try obj_writer.writer.print("vt {d:.6} {d:.6}\n", .{ vtx.uv[0], vtx.uv[1] });
                }

                try obj_writer.writer.writeByte('\n');
            }

            // Faces (1-based OBJ indices, offset by global_vtx_offset)
            var tri_pos: usize = 0;

            while (tri_pos < tri_indices.len) : (tri_pos += 3) {
                const idx_a = @as(usize, tri_indices[tri_pos]) + global_vtx_offset + 1;
                const idx_b = @as(usize, tri_indices[tri_pos + 1]) + global_vtx_offset + 1;
                const idx_c = @as(usize, tri_indices[tri_pos + 2]) + global_vtx_offset + 1;

                if (has_uv) {
                    try obj_writer.writer.print("f {d}/{d}/{d} {d}/{d}/{d} {d}/{d}/{d}\n", .{
                        idx_a, idx_a, idx_a,
                        idx_b, idx_b, idx_b,
                        idx_c, idx_c, idx_c,
                    });
                } else {
                    try obj_writer.writer.print("f {d}//{d} {d}//{d} {d}//{d}\n", .{
                        idx_a, idx_a,
                        idx_b, idx_b,
                        idx_c, idx_c,
                    });
                }
            }

            try obj_writer.writer.writeByte('\n');

            global_vtx_offset += vertex_count;
        }

        try json_writer.writer.writeAll("{\n");

        // Meshes metadata + skinning
        try json_writer.writer.writeAll("  \"meshes\": {\n");
        var mesh_idx_in_group: usize = 0;

        for (group.bindings) |binding| {
            const mesh_entry = mesh_map.getPtr(binding.shape_name) orelse {
                continue;
            };

            const md = mesh_entry;
            const header = md.header;
            const stride = md.stride;
            const record = md.record;
            const vertex_count: usize = header.vertex_count;

            var has_color: bool = undefined;
            var has_skin: bool = undefined;
            var num_weights: u32 = undefined;

            kats_tools.kats_model_get_vertex_format(stride, &has_color, &has_skin, &num_weights);

            if (mesh_idx_in_group > 0) {
                try json_writer.writer.writeAll(",\n");
            }

            mesh_idx_in_group += 1;

            try json_writer.writer.print("    \"{s}\": {{\n", .{binding.shape_name});
            try json_writer.writer.print("      \"stride\": {d},\n", .{stride});
            try json_writer.writer.print("      \"has_color\": {},\n", .{has_color});
            try json_writer.writer.print("      \"has_skin\": {},\n", .{has_skin});
            try json_writer.writer.print("      \"num_weights\": {d},\n", .{num_weights});
            try json_writer.writer.print("      \"skeleton_id\": {d},\n", .{header.skeleton_id});
            try json_writer.writer.print("      \"vertex_count\": {d},\n", .{header.vertex_count});
            try json_writer.writer.print("      \"bounding_sphere\": {{ \"radius\": {d:.6}, \"center\": [{d:.6}, {d:.6}, {d:.6}] }},\n", .{
                header.radius, header.cx, header.cy, header.cz,
            });

            // Skinning data
            if (has_skin and vertex_count > 0) {
                try json_writer.writer.writeAll("      \"skin_data\": {\n");
                try json_writer.writer.writeAll("        \"weights\": [");

                for (0..vertex_count) |vtx_idx| {
                    var vtx: kats_tools.MeshShapeVertexFull = undefined;

                    if (kats_tools.kats_model_get_mesh_shape_vertex_full(&record, &header, stride, @intCast(vtx_idx), &vtx)) {
                        if (vtx_idx > 0) {
                            try json_writer.writer.writeAll(", ");
                        }

                        try json_writer.writer.print("{d:.6}, {d:.6}, {d:.6}, {d:.6}", .{
                            vtx.weights[0], vtx.weights[1], vtx.weights[2], vtx.weights[3],
                        });
                    }
                }

                try json_writer.writer.writeAll("],\n");

                try json_writer.writer.writeAll("        \"bone_indices\": [");

                for (0..vertex_count) |vtx_idx| {
                    var vtx: kats_tools.MeshShapeVertexFull = undefined;

                    if (kats_tools.kats_model_get_mesh_shape_vertex_full(&record, &header, stride, @intCast(vtx_idx), &vtx)) {
                        if (vtx_idx > 0) {
                            try json_writer.writer.writeAll(", ");
                        }

                        try json_writer.writer.print("{d:.1}, {d:.1}, {d:.1}, {d:.1}", .{
                            vtx.bone_indices[0], vtx.bone_indices[1], vtx.bone_indices[2], vtx.bone_indices[3],
                        });
                    }
                }

                try json_writer.writer.writeAll("]\n");
                try json_writer.writer.writeAll("      },\n");
            }

            // Vertex color data
            if (has_color and vertex_count > 0) {
                try json_writer.writer.writeAll("      \"vertex_colors\": [");

                for (0..vertex_count) |vtx_idx| {
                    var vtx: kats_tools.MeshShapeVertexFull = undefined;

                    if (kats_tools.kats_model_get_mesh_shape_vertex_full(&record, &header, stride, @intCast(vtx_idx), &vtx)) {
                        if (vtx_idx > 0) {
                            try json_writer.writer.writeAll(", ");
                        }

                        try json_writer.writer.print("{d:.6}, {d:.6}, {d:.6}, {d:.6}", .{
                            vtx.diffuse[0], vtx.diffuse[1], vtx.diffuse[2], vtx.diffuse[3],
                        });
                    }
                }

                try json_writer.writer.writeAll("],\n");
            }

            try json_writer.writer.writeAll("      \"material\": \"");
            try json_writer.writer.writeAll(binding.material_name);
            try json_writer.writer.writeAll("\"\n");
            try json_writer.writer.writeAll("    }");
        }

        try json_writer.writer.writeAll("\n  },\n");

        // Materials extra data (bone_refs, texture_name for TextureRef matching)
        try json_writer.writer.writeAll("  \"materials\": {\n");
        mat_iter = used_materials.iterator();

        var first_mat: bool = true;

        while (mat_iter.next()) |mat_entry| {
            const mat_name = mat_entry.key_ptr.*;

            if (!first_mat) {
                try json_writer.writer.writeAll(",\n");
            }

            first_mat = false;

            try json_writer.writer.print("    \"{s}\": {{", .{mat_name});

            if (material_map.getPtr(mat_name)) |mat_record| {
                var material: kats_tools.Material = undefined;

                if (kats_tools.kats_model_get_material(mat_record, &material)) {
                    const tex_name = std.mem.span(material.texture_name);
                    try json_writer.writer.print("\"texture_name\": \"{s}\"", .{tex_name});

                    // Debug: warn if bone_refs parsing seems incorrect
                    {
                        const bro = material._bone_refs_offset;
                        const remaining = if (bro < mat_record.data_len) mat_record.data_len - bro else 0;
                        if (material.sub_count > 0 and material._bone_refs_count == 0 and remaining > 0) {
                            std.debug.print("WARNING: material '{s}' has sub_count={d} but found 0 valid bone refs (data_len={d}, offset={d}, remaining={d})\n", .{ mat_name, material.sub_count, mat_record.data_len, bro, remaining });
                        }
                    }

                    const bone_ref_count = kats_tools.kats_model_get_material_bone_ref_count(mat_record, &material);

                    if (bone_ref_count > 0) {
                        try json_writer.writer.writeAll(", \"bone_refs\": [");

                        for (0..bone_ref_count) |br_idx| {
                            var bone_name: [*:0]const u8 = undefined;

                            if (kats_tools.kats_model_get_material_bone_ref(mat_record, &material, br_idx, &bone_name)) {
                                if (br_idx > 0) {
                                    try json_writer.writer.writeAll(", ");
                                }

                                try json_writer.writer.print("\"{s}\"", .{std.mem.span(bone_name)});
                            }
                        }

                        try json_writer.writer.writeAll("]");
                    }
                }
            }

            try json_writer.writer.writeAll("}");
        }

        try json_writer.writer.writeAll("\n  },\n");

        // TextureRefs
        try json_writer.writer.writeAll("  \"texture_refs\": {\n");
        var tex_iter = texture_ref_map.iterator();
        var first_tex: bool = true;

        while (tex_iter.next()) |tex_entry| {
            const tex_name = tex_entry.key_ptr.*;
            const tex_record = tex_entry.value_ptr.*;

            if (!first_tex) {
                try json_writer.writer.writeAll(",\n");
            }

            first_tex = false;

            var tref: kats_tools.TextureRef = undefined;

            if (kats_tools.kats_model_get_texture_ref(&tex_record, &tref)) {
                const tfile = std.mem.span(tref.texture_file);
                try json_writer.writer.print("    \"{s}\": {{ \"file\": \"{s}\"", .{ tex_name, tfile });

                if (tref.has_params) {
                    try json_writer.writer.writeAll(", \"params\": ");
                    try writeJsonU32Array(&json_writer.writer, &tref.tex_params);
                }

                try json_writer.writer.writeAll(" }");
            }
        }

        try json_writer.writer.writeAll("\n  },\n");

        // TransformNodes
        try json_writer.writer.writeAll("  \"transforms\": {\n");
        var tn_iter = transform_map.iterator();
        var first_tn: bool = true;

        while (tn_iter.next()) |tn_entry| {
            const tn_name = tn_entry.key_ptr.*;
            const tn = tn_entry.value_ptr.*;

            if (!first_tn) {
                try json_writer.writer.writeAll(",\n");
            }

            first_tn = false;

            try json_writer.writer.print("    \"{s}\": {{\n", .{tn_name});
            try json_writer.writer.print("      \"flag\": {d},\n", .{tn.flag});
            try json_writer.writer.writeAll("      \"translation\": ");
            try writeJsonFloatArray(&json_writer.writer, &tn.translation);
            try json_writer.writer.writeAll(",\n");
            try json_writer.writer.writeAll("      \"rotation\": ");
            try writeJsonFloatArray(&json_writer.writer, &tn.rotation);
            try json_writer.writer.writeAll(",\n");
            try json_writer.writer.writeAll("      \"scale\": ");
            try writeJsonFloatArray(&json_writer.writer, &tn.scale);
            try json_writer.writer.writeAll("\n    }");
        }

        try json_writer.writer.writeAll("\n  },\n");

        // Skeletons
        try json_writer.writer.writeAll("  \"skeletons\": [\n");

        for (skeleton_groups.items, 0..) |sg, sg_idx| {
            if (sg_idx > 0) {
                try json_writer.writer.writeAll(",\n");
            }

            var skel_root: kats_tools.SkeletonRoot = undefined;
            _ = kats_tools.kats_model_get_skeleton_root(&sg.root_record, &skel_root);

            const root_name = std.mem.span(sg.root_record.name);
            try json_writer.writer.print("    {{\n", .{});
            try json_writer.writer.print("      \"name\": \"{s}\",\n", .{root_name});
            try json_writer.writer.print("      \"val1\": {d}, \"val2\": {d},\n", .{ skel_root.val1, skel_root.val2 });
            try json_writer.writer.print("      \"shape_ref\": \"{s}\",\n", .{std.mem.span(skel_root.skeleton_shape_ref)});

            // Build joint name array for parent inference
            var joint_names: std.ArrayList([*:0]const u8) = .empty;
            defer joint_names.deinit(init.gpa);

            for (sg.joint_records) |jr| {
                try joint_names.append(init.gpa, jr.name);
            }

            try json_writer.writer.writeAll("      \"joints\": [\n");

            for (sg.joint_records, 0..) |jr, jidx| {
                if (jidx > 0) {
                    try json_writer.writer.writeAll(",\n");
                }

                var joint: kats_tools.Joint = undefined;

                if (!kats_tools.kats_model_get_joint(&jr, &joint)) {
                    try json_writer.writer.writeAll("        {}");

                    continue;
                }

                const jname = std.mem.span(jr.name);

                // Infer parent
                var parent_name: ?[*:0]const u8 = null;
                _ = kats_tools.kats_infer_joint_parent(jr.name, joint_names.items.ptr, joint_names.items.len, &parent_name);

                try json_writer.writer.print("        {{\n", .{});
                try json_writer.writer.print("          \"name\": \"{s}\",\n", .{jname});

                if (parent_name) |pn| {
                    try json_writer.writer.print("          \"parent\": \"{s}\",\n", .{std.mem.span(pn)});
                } else {
                    try json_writer.writer.writeAll("          \"parent\": null,\n");
                }

                try json_writer.writer.print("          \"flag\": {d},\n", .{joint.flag});
                try json_writer.writer.writeAll("          \"translation\": ");
                try writeJsonFloatArray(&json_writer.writer, &joint.translation);
                try json_writer.writer.writeAll(",\n");
                try json_writer.writer.writeAll("          \"rotation\": ");
                try writeJsonFloatArray(&json_writer.writer, &joint.rotation);
                try json_writer.writer.writeAll(",\n");
                try json_writer.writer.writeAll("          \"scale\": ");
                try writeJsonFloatArray(&json_writer.writer, &joint.scale);

                if (joint.has_inv_bind_matrix) {
                    try json_writer.writer.writeAll(",\n          \"inv_bind_matrix_3x4\": ");
                    try writeJsonFloatArray(&json_writer.writer, &joint.inv_bind_matrix_3x4);
                }

                if (joint.extra_data_len > 0) {
                    try json_writer.writer.print(",\n          \"extra_data_len\": {d}", .{joint.extra_data_len});
                }

                try json_writer.writer.writeAll("\n        }");
            }

            try json_writer.writer.writeAll("\n      ]\n");
            try json_writer.writer.writeAll("    }");
        }

        try json_writer.writer.writeAll("\n  ]\n");

        try json_writer.writer.writeAll("}\n");

        const obj_path = try std.fmt.allocPrint(init.gpa, "{s}/{s}.obj", .{ base_dir, group.name });
        defer init.gpa.free(obj_path);

        const mtl_path = try std.fmt.allocPrint(init.gpa, "{s}/{s}", .{ base_dir, mtl_filename });
        defer init.gpa.free(mtl_path);

        const json_path = try std.fmt.allocPrint(init.gpa, "{s}/{s}.json", .{ base_dir, group.name });
        defer init.gpa.free(json_path);

        std.debug.print("  {s} -> {s}\n", .{ sub_path, obj_path });

        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = obj_path, .data = obj_writer.written(), .flags = .{} });
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = mtl_path, .data = mtl_writer.written(), .flags = .{} });
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = json_path, .data = json_writer.written(), .flags = .{} });
    }
}

fn convertAnimation(init: std.process.Init, file_content: []const u8, out_dir: []const u8, sub_path: []const u8, ok: *bool) !void {
    const record_count = kats_tools.kats_animation_count_records(file_content.ptr, file_content.len);

    std.debug.print("Animation records: {d}\n", .{record_count});

    if (record_count == 0) {
        std.debug.print("Bad animation file: {s}\n", .{sub_path});
        ok.* = false;

        return;
    }

    var json_writer: std.Io.Writer.Allocating = .init(init.gpa);
    defer json_writer.deinit();

    try json_writer.writer.writeAll("{\n");
    try json_writer.writer.writeAll("  \"source_file\": \"");
    try json_writer.writer.writeAll(sub_path);
    try json_writer.writer.writeAll("\",\n");

    // Collect all AnimSets and their channels
    // AnimSet groups channels that follow it until the next AnimSet or different record type

    const AnimGroup = struct {
        set_record: kats_tools.Record,
        channels: std.ArrayList(kats_tools.Record),
    };

    var anim_groups: std.ArrayList(AnimGroup) = .empty;
    defer {
        for (anim_groups.items) |*ag| {
            ag.channels.deinit(init.gpa);
        }

        anim_groups.deinit(init.gpa);
    }

    var anim_refs: std.ArrayList(kats_tools.Record) = .empty;
    defer anim_refs.deinit(init.gpa);

    // Group channels by their preceding AnimSet
    {
        var current_set: ?kats_tools.Record = null;
        var current_channels: std.ArrayList(kats_tools.Record) = .empty;
        defer current_channels.deinit(init.gpa);

        for (0..record_count) |rec_idx| {
            var record: kats_tools.Record = undefined;

            if (!kats_tools.kats_animation_get_record(file_content.ptr, file_content.len, rec_idx, &record)) {
                continue;
            }

            if (record.ty == .anim_set) {
                // Flush previous group
                if (current_set != null) {
                    const cloned_channels = try current_channels.clone(init.gpa);

                    try anim_groups.append(init.gpa, .{
                        .set_record = current_set.?,
                        .channels = cloned_channels,
                    });
                }

                current_set = record;
                current_channels.clearRetainingCapacity();
            } else if (record.ty == .keyframe_channel) {
                if (current_set != null) {
                    try current_channels.append(init.gpa, record);
                } else {
                    // Orphan channel without a preceding AnimSet - create a synthetic group
                    var synthetic_channels: std.ArrayList(kats_tools.Record) = .empty;
                    try synthetic_channels.append(init.gpa, record);

                    try anim_groups.append(init.gpa, .{
                        .set_record = record, // use channel as its own "set"
                        .channels = synthetic_channels,
                    });
                }
            } else if (record.ty == .anim_ref) {
                try anim_refs.append(init.gpa, record);
            }
        }

        // Flush last group
        if (current_set != null) {
            const last_cloned = try current_channels.clone(init.gpa);

            try anim_groups.append(init.gpa, .{
                .set_record = current_set.?,
                .channels = last_cloned,
            });
        }
    }

    // AnimRefs
    try json_writer.writer.writeAll("  \"anim_refs\": [\n");

    for (anim_refs.items, 0..) |ref_record, ref_idx| {
        if (ref_idx > 0) {
            try json_writer.writer.writeAll(",\n");
        }

        var anim_ref: kats_tools.AnimRef = undefined;

        if (kats_tools.kats_animation_get_anim_ref(&ref_record, &anim_ref)) {
            const ref_name = std.mem.span(ref_record.name);
            const set_name = std.mem.span(anim_ref.anim_set_name);

            try json_writer.writer.print("    {{ \"name\": \"{s}\", \"anim_set\": \"{s}\" }}", .{ ref_name, set_name });
        } else {
            const ref_name = std.mem.span(ref_record.name);
            try json_writer.writer.print("    {{ \"name\": \"{s}\" }}", .{ref_name});
        }
    }

    try json_writer.writer.writeAll("\n  ],\n");

    // AnimSets with their channels
    try json_writer.writer.writeAll("  \"animations\": {\n");

    for (anim_groups.items, 0..) |ag, group_idx| {
        if (group_idx > 0) {
            try json_writer.writer.writeAll(",\n");
        }

        const set_name = std.mem.span(ag.set_record.name);
        try json_writer.writer.print("    \"{s}\": {{\n", .{set_name});

        // AnimSet metadata
        if (ag.set_record.ty == .anim_set) {
            var anim_set: kats_tools.AnimSet = undefined;

            if (kats_tools.kats_model_get_anim_set(&ag.set_record, &anim_set)) {
                try json_writer.writer.print("      \"channel_count\": {d},\n", .{anim_set.channel_count});
            }
        }

        try json_writer.writer.writeAll("      \"channels\": [\n");

        for (ag.channels.items, 0..) |ch_record, ch_idx| {
            if (ch_idx > 0) {
                try json_writer.writer.writeAll(",\n");
            }

            var channel: kats_tools.KeyframeChannel = undefined;

            if (!kats_tools.kats_model_get_keyframe_channel(&ch_record, &channel)) {
                const ch_name = std.mem.span(ch_record.name);
                try json_writer.writer.print("        {{ \"name\": \"{s}\", \"error\": true }}", .{ch_name});

                continue;
            }

            const target_node = channel.target_node[0..channel.target_node_len];
            const channel_type = channel.channel_type[0..channel.channel_type_len];

            try json_writer.writer.writeAll("        {\n");
            try json_writer.writer.print("          \"name\": \"{s}\",\n", .{std.mem.span(ch_record.name)});
            try json_writer.writer.print("          \"target_node\": \"{s}\",\n", .{target_node});
            try json_writer.writer.print("          \"channel_type\": \"{s}\",\n", .{channel_type});
            try json_writer.writer.print("          \"flag\": {d},\n", .{channel.flag});
            try json_writer.writer.print("          \"keyframe_count\": {d},\n", .{channel.kf_count});

            // Keyframes: array of [time, value] pairs
            try json_writer.writer.writeAll("          \"keyframes\": [");

            for (0..channel.kf_count) |kf_idx| {
                const time = channel.keyframes[kf_idx * 2];
                const value = channel.keyframes[kf_idx * 2 + 1];

                if (kf_idx > 0) {
                    try json_writer.writer.writeAll(", ");
                }

                try json_writer.writer.print("[{d:.6}, {d:.6}]", .{ time, value });
            }

            try json_writer.writer.writeAll("]\n");
            try json_writer.writer.writeAll("        }");
        }

        try json_writer.writer.writeAll("\n      ]\n");
        try json_writer.writer.writeAll("    }");
    }

    try json_writer.writer.writeAll("\n  }\n");

    try json_writer.writer.writeAll("}\n");

    // Write JSON output
    const base_dir = try std.fs.path.join(init.gpa, &.{ out_dir, withoutExt(sub_path) });
    defer init.gpa.free(base_dir);

    try std.Io.Dir.cwd().createDirPath(init.io, base_dir);

    const json_path = try std.fmt.allocPrint(init.gpa, "{s}/animation.json", .{base_dir});
    defer init.gpa.free(json_path);

    std.debug.print("  {s} -> {s}\n", .{ sub_path, json_path });

    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = json_path, .data = json_writer.written(), .flags = .{} });
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

        kats_tools.kats_decrypt(std.mem.readInt(u32, meta.xor_key[0..4], .little), file_content.ptr, file_content.len);

        switch (meta.ty) {
            .clipper => {
                const bmp_files = kats_tools.kats_clipper_count_files(file_content.ptr, file_content.len);

                std.debug.print("BMP files: {d}\n", .{bmp_files});

                if (bmp_files == 0) {
                    std.debug.print("Bad clipper file: {s}\n", .{input_path});
                    ok = false;

                    continue;
                }

                for (0..bmp_files) |bmp_idx| {
                    const out_path = try std.fmt.allocPrint(init.gpa, "{f}/{d}.bmp", .{ std.fs.path.fmtJoin(&.{ out_dir, withoutExt(meta.sub_path) }), bmp_idx });
                    defer init.gpa.free(out_path);

                    std.debug.print("{s} -> {s}\n", .{ meta.sub_path, out_path });

                    var bmp_data: []const u8 = &.{};

                    if (!kats_tools.kats_clipper_get(file_content.ptr, file_content.len, bmp_idx, &bmp_data.ptr, &bmp_data.len)) {
                        std.debug.print("BMP file {d} not found in {s}\n", .{ bmp_idx, input_path });
                        ok = false;
                        continue;
                    }

                    try std.Io.Dir.cwd().createDirPath(init.io, std.fs.path.dirname(out_path).?);
                    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = bmp_data, .flags = .{} });
                }
            },
            .model => {
                try convertModel(init, file_content, out_dir, meta.sub_path, &ok);
            },
            .texture => {
                const tga_files = kats_tools.kats_texture_count_files(file_content.ptr, file_content.len);

                std.debug.print("TGA files: {d}\n", .{tga_files});

                if (tga_files == 0) {
                    std.debug.print("Bad texture file: {s}\n", .{input_path});
                    ok = false;

                    continue;
                }

                for (0..tga_files) |tga_idx| {
                    const out_path = try std.fmt.allocPrint(init.gpa, "{f}/{d}.tga", .{ std.fs.path.fmtJoin(&.{ out_dir, withoutExt(meta.sub_path) }), tga_idx });
                    defer init.gpa.free(out_path);

                    std.debug.print("{s} -> {s}\n", .{ meta.sub_path, out_path });

                    var tga_data: []const u8 = &.{};

                    if (!kats_tools.kats_texture_get(file_content.ptr, file_content.len, tga_idx, &tga_data.ptr, &tga_data.len)) {
                        std.debug.print("TGA file {d} not found in {s}\n", .{ tga_idx, input_path });
                        ok = false;

                        continue;
                    }

                    try std.Io.Dir.cwd().createDirPath(init.io, std.fs.path.dirname(out_path).?);
                    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = tga_data, .flags = .{} });
                }
            },
            .sound => {
                const wave_files = kats_tools.kats_sound_count_files(file_content.ptr, file_content.len);

                std.debug.print("WAV files: {d}\n", .{wave_files});

                if (wave_files == 0) {
                    std.debug.print("Bad sound file: {s}\n", .{input_path});
                    ok = false;

                    continue;
                }

                for (0..wave_files) |wav_idx| {
                    const out_path = try std.fmt.allocPrint(init.gpa, "{f}/{d}.wav", .{ std.fs.path.fmtJoin(&.{ out_dir, withoutExt(meta.sub_path) }), wav_idx });
                    defer init.gpa.free(out_path);

                    std.debug.print("{s} -> {s}\n", .{ meta.sub_path, out_path });

                    var wav_data: []const u8 = &.{};

                    if (!kats_tools.kats_sound_get(file_content.ptr, file_content.len, wav_idx, &wav_data.ptr, &wav_data.len)) {
                        std.debug.print("WAV file {d} not found in {s}\n", .{ wav_idx, input_path });
                        ok = false;

                        continue;
                    }

                    try std.Io.Dir.cwd().createDirPath(init.io, std.fs.path.dirname(out_path).?);
                    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = wav_data, .flags = .{} });
                }
            },
            .animation => {
                try convertAnimation(init, file_content, out_dir, meta.sub_path, &ok);
            },
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

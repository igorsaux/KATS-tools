#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""
KATS-tools JSON + OBJ + MTL -> glTF 2.0 converter.

Converts model data exported by kats-tools (OBJ geometry, MTL materials,
JSON metadata with skinning/skeleton/animation data) into a single glTF 2.0
binary (.glb) file with full skeletal animation support.

Usage:
    uv run to_gltf.py <model_dir> [--animation <anim_json>] [--output <output.glb>]

    model_dir      Directory containing the .obj, .mtl, and .json files produced
                   by `kats-tools convert`.
    --animation    Optional path to an animation JSON file produced by
                   `kats-tools convert` (animation/animationXX/animation.json).
                   May be specified multiple times.
    --output       Output .glb file path. Defaults to <model_dir>/<name>.glb.

Example:
    uv run to_gltf.py out/model/model00/ --animation out/animation/animation00/animation.json
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional

GLTF_MAGIC = 0x46546C67  # "glTF"
GLTF_VERSION = 2
CHUNK_TYPE_JSON = 0x4E4F534A
CHUNK_TYPE_BIN = 0x004E4942

# glTF component types
COMPONENT_FLOAT = 5126
COMPONENT_UNSIGNED_SHORT = 5123
COMPONENT_UNSIGNED_INT = 5125

# glTF accessor types
TYPE_SCALAR = "SCALAR"
TYPE_VEC2 = "VEC2"
TYPE_VEC3 = "VEC3"
TYPE_VEC4 = "VEC4"
TYPE_MAT4 = "MAT4"

# glTF primitive modes
MODE_TRIANGLES = 4

# glTF buffer view targets
TARGET_ARRAY_BUFFER = 34962
TARGET_ELEMENT_ARRAY_BUFFER = 34963


def component_size(comp_type: int) -> int:
    return {COMPONENT_FLOAT: 4, COMPONENT_UNSIGNED_SHORT: 2, COMPONENT_UNSIGNED_INT: 4}[
        comp_type
    ]


def accessor_count(type_str: str) -> int:
    return {
        TYPE_SCALAR: 1,
        TYPE_VEC2: 2,
        TYPE_VEC3: 3,
        TYPE_VEC4: 4,
        TYPE_MAT4: 16,
    }[type_str]


def accessor_byte_len(comp_type: int, type_str: str, count: int) -> int:
    return component_size(comp_type) * accessor_count(type_str) * count


class GltfBuilder:
    """Minimal glTF 2.0 binary builder."""

    def __init__(self) -> None:
        self.json_root: dict = {
            "asset": {"version": "2.0", "generator": "kats_to_gltf.py"},
            "scenes": [],
            "nodes": [],
            "meshes": [],
            "accessors": [],
            "bufferViews": [],
            "buffers": [],
            "skins": [],
            "animations": [],
        }
        self.bin_data = bytearray()
        self._has_materials = False

    def _add_buffer_view(self, data: bytes, target: int = 0) -> int:
        idx = len(self.json_root["bufferViews"])
        offset = len(self.bin_data)
        # Pad to 4-byte alignment
        pad = (4 - offset % 4) % 4
        self.bin_data.extend(b"\x00" * pad)
        offset = len(self.bin_data)
        self.bin_data.extend(data)
        bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            bv["target"] = target
        self.json_root["bufferViews"].append(bv)
        return idx

    def _add_accessor(
        self,
        bv_idx: int,
        comp_type: int,
        type_str: str,
        count: int,
        min_vals: list | None = None,
        max_vals: list | None = None,
    ) -> int:
        idx = len(self.json_root["accessors"])
        acc = {
            "bufferView": bv_idx,
            "componentType": comp_type,
            "type": type_str,
            "count": count,
        }
        if min_vals is not None:
            acc["min"] = min_vals
        if max_vals is not None:
            acc["max"] = max_vals
        self.json_root["accessors"].append(acc)
        return idx

    def add_positions(self, positions: list[list[float]]) -> int:
        """Add POSITION attribute data."""
        data = struct.pack(
            f"<{len(positions) * 3}f", *[c for p in positions for c in p]
        )
        bv_idx = self._add_buffer_view(data, TARGET_ARRAY_BUFFER)
        flat = [c for p in positions for c in p]
        mins = [min(flat[i::3]) for i in range(3)]
        maxs = [max(flat[i::3]) for i in range(3)]
        return self._add_accessor(
            bv_idx, COMPONENT_FLOAT, TYPE_VEC3, len(positions), mins, maxs
        )

    def add_normals(self, normals: list[list[float]]) -> int:
        data = struct.pack(f"<{len(normals) * 3}f", *[c for n in normals for c in n])
        bv_idx = self._add_buffer_view(data, TARGET_ARRAY_BUFFER)
        return self._add_accessor(bv_idx, COMPONENT_FLOAT, TYPE_VEC3, len(normals))

    def add_texcoords(self, uvs: list[list[float]]) -> int:
        data = struct.pack(f"<{len(uvs) * 2}f", *[c for uv in uvs for c in uv])
        bv_idx = self._add_buffer_view(data, TARGET_ARRAY_BUFFER)
        return self._add_accessor(bv_idx, COMPONENT_FLOAT, TYPE_VEC2, len(uvs))

    def add_joints(self, joints: list[list[int]]) -> int:
        """Add JOINTS_0 attribute (as unsigned shorts)."""
        data = struct.pack(f"<{len(joints) * 4}H", *[j for js in joints for j in js])
        bv_idx = self._add_buffer_view(data, TARGET_ARRAY_BUFFER)
        return self._add_accessor(
            bv_idx, COMPONENT_UNSIGNED_SHORT, TYPE_VEC4, len(joints)
        )

    def add_weights(self, weights: list[list[float]]) -> int:
        data = struct.pack(f"<{len(weights) * 4}f", *[w for ws in weights for w in ws])
        bv_idx = self._add_buffer_view(data, TARGET_ARRAY_BUFFER)
        return self._add_accessor(bv_idx, COMPONENT_FLOAT, TYPE_VEC4, len(weights))

    def add_indices(self, indices: list[int]) -> int:
        if max(indices) > 65535:
            data = struct.pack(f"<{len(indices)}I", *indices)
            bv_idx = self._add_buffer_view(data, TARGET_ELEMENT_ARRAY_BUFFER)
            return self._add_accessor(
                bv_idx, COMPONENT_UNSIGNED_INT, TYPE_SCALAR, len(indices)
            )
        else:
            data = struct.pack(f"<{len(indices)}H", *indices)
            bv_idx = self._add_buffer_view(data, TARGET_ELEMENT_ARRAY_BUFFER)
            return self._add_accessor(
                bv_idx, COMPONENT_UNSIGNED_SHORT, TYPE_SCALAR, len(indices)
            )

    def add_inverse_bind_matrices(self, matrices: list[list[float]]) -> int:
        """Add 4x4 column-major matrices for skin."""
        data = struct.pack(
            f"<{len(matrices) * 16}f", *[m for mat in matrices for m in mat]
        )
        bv_idx = self._add_buffer_view(data)
        return self._add_accessor(bv_idx, COMPONENT_FLOAT, TYPE_MAT4, len(matrices))

    def add_node(
        self,
        name: str | None = None,
        children: list[int] | None = None,
        mesh: int | None = None,
        skin: int | None = None,
        translation: list[float] | None = None,
        rotation: list[float] | None = None,
        scale: list[float] | None = None,
    ) -> int:
        idx = len(self.json_root["nodes"])
        node: dict = {}
        if name:
            node["name"] = name
        if children:
            node["children"] = children
        if mesh is not None:
            node["mesh"] = mesh
        if skin is not None:
            node["skin"] = skin
        if translation:
            node["translation"] = translation
        if rotation:
            node["rotation"] = rotation
        if scale:
            node["scale"] = scale
        self.json_root["nodes"].append(node)
        return idx

    def add_mesh(self, name: str, primitives: list[dict]) -> int:
        idx = len(self.json_root["meshes"])
        self.json_root["meshes"].append({"name": name, "primitives": primitives})
        return idx

    def add_skin(
        self,
        joints: list[int],
        skeleton: int | None = None,
        inverse_bind_matrices: int | None = None,
    ) -> int:
        idx = len(self.json_root["skins"])
        skin: dict = {"joints": joints}
        if skeleton is not None:
            skin["skeleton"] = skeleton
        if inverse_bind_matrices is not None:
            skin["inverseBindMatrices"] = inverse_bind_matrices
        self.json_root["skins"].append(skin)
        return idx

    def add_animation(
        self, name: str, channels: list[dict], samplers: list[dict]
    ) -> int:
        idx = len(self.json_root["animations"])
        self.json_root["animations"].append(
            {
                "name": name,
                "channels": channels,
                "samplers": samplers,
            }
        )
        return idx

    def add_scene(self, nodes: list[int]) -> int:
        idx = len(self.json_root["scenes"])
        self.json_root["scenes"].append({"nodes": nodes})
        return idx

    def ensure_materials_list(self) -> None:
        if "materials" not in self.json_root:
            self.json_root["materials"] = []

    def add_texture(self, source: int) -> int:
        if "textures" not in self.json_root:
            self.json_root["textures"] = []
        idx = len(self.json_root["textures"])
        self.json_root["textures"].append({"source": source})
        return idx

    def add_image(self, uri: str) -> int:
        if "images" not in self.json_root:
            self.json_root["images"] = []
        idx = len(self.json_root["images"])
        self.json_root["images"].append({"uri": uri})
        return idx

    def add_material(
        self,
        name: str,
        base_color_factor: list[float] | None = None,
        metallic_factor: float = 0.0,
        roughness_factor: float = 1.0,
        emissive_factor: list[float] | None = None,
        texture_uri: str | None = None,
        alpha_cutoff: float | None = None,
    ) -> int:
        self.ensure_materials_list()
        idx = len(self.json_root["materials"])
        mat: dict = {
            "name": name,
            "pbrMetallicRoughness": {
                "metallicFactor": metallic_factor,
                "roughnessFactor": roughness_factor,
            },
        }
        if base_color_factor:
            mat["pbrMetallicRoughness"]["baseColorFactor"] = base_color_factor
        if emissive_factor:
            mat["emissiveFactor"] = emissive_factor
        if texture_uri:
            img_idx = self.add_image(texture_uri)
            tex_idx = self.add_texture(img_idx)
            mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex_idx}
        if alpha_cutoff is not None:
            mat["alphaMode"] = "MASK"
            mat["alphaCutoff"] = alpha_cutoff
        elif (
            base_color_factor
            and len(base_color_factor) == 4
            and base_color_factor[3] < 1.0
        ):
            mat["alphaMode"] = "BLEND"
        self.json_root["materials"].append(mat)
        self._has_materials = True
        return idx

    def finalize(self) -> bytes:
        """Build the final .glb binary."""
        # Set buffer
        if self.bin_data:
            pad = (4 - len(self.bin_data) % 4) % 4
            self.bin_data.extend(b"\x00" * pad)
            self.json_root["buffers"] = [{"byteLength": len(self.bin_data)}]
        else:
            self.json_root["buffers"] = []
            self.bin_data = bytearray()

        # Remove empty top-level arrays
        for key in list(self.json_root.keys()):
            if isinstance(self.json_root[key], list) and len(self.json_root[key]) == 0:
                if (
                    key != "scenes"
                    and key != "nodes"
                    and key != "meshes"
                    and key != "accessors"
                    and key != "bufferViews"
                    and key != "buffers"
                    and key != "skins"
                    and key != "animations"
                ):
                    del self.json_root[key]

        json_bytes = json.dumps(self.json_root, separators=(",", ":")).encode("utf-8")
        # Pad JSON to 4-byte alignment (with spaces)
        pad = (4 - len(json_bytes) % 4) % 4
        json_bytes += b" " * pad

        # GLB header
        total_len = 12 + 8 + len(json_bytes) + 8 + len(self.bin_data)
        header = struct.pack("<III", GLTF_MAGIC, GLTF_VERSION, total_len)
        json_chunk = struct.pack("<II", len(json_bytes), CHUNK_TYPE_JSON) + json_bytes
        bin_chunk = struct.pack("<II", len(self.bin_data), CHUNK_TYPE_BIN) + bytes(
            self.bin_data
        )

        return header + json_chunk + bin_chunk


# ---------------------------------------------------------------------------
# OBJ parser
# ---------------------------------------------------------------------------


@dataclass
class ObjData:
    positions: list[list[float]] = field(default_factory=list)
    normals: list[list[float]] = field(default_factory=list)
    texcoords: list[list[float]] = field(default_factory=list)
    faces: list[dict] = field(default_factory=list)  # list of object groups
    materials: dict[str, dict] = field(default_factory=dict)
    current_object: str | None = None
    current_material: str | None = None
    current_face_group: dict = field(default_factory=dict)


def parse_obj(obj_path: Path) -> ObjData:
    """Parse an OBJ file and return structured data."""
    result = ObjData()

    with open(obj_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            parts = line.split()
            cmd = parts[0]

            if cmd == "v" and len(parts) >= 4:
                result.positions.append(
                    [float(parts[1]), float(parts[2]), float(parts[3])]
                )
            elif cmd == "vn" and len(parts) >= 4:
                result.normals.append(
                    [float(parts[1]), float(parts[2]), float(parts[3])]
                )
            elif cmd == "vt" and len(parts) >= 3:
                result.texcoords.append([float(parts[1]), float(parts[2])])
            elif cmd == "f":
                face_verts = []
                for vstr in parts[1:]:
                    vi, ti, ni = _parse_face_vertex(vstr)
                    face_verts.append((vi, ti, ni))
                if len(face_verts) >= 3:
                    # Triangulate (fan)
                    for i in range(1, len(face_verts) - 1):
                        tri = [face_verts[0], face_verts[i], face_verts[i + 1]]
                        key = (
                            result.current_object or "",
                            result.current_material or "",
                        )
                        if key not in result.current_face_group:
                            result.current_face_group[key] = []
                        result.current_face_group[key].append(tri)
            elif cmd == "o":
                result.current_object = parts[1] if len(parts) > 1 else None
            elif cmd == "usemtl":
                result.current_material = parts[1] if len(parts) > 1 else None
            elif cmd == "mtllib":
                pass  # handled separately

    result.faces = result.current_face_group
    return result


def _parse_face_vertex(vstr: str) -> tuple[int, int, int]:
    """Parse a face vertex string like '1/1/1' or '1//1' or '1'."""
    parts = vstr.split("/")
    vi = int(parts[0]) if parts[0] else 0
    ti = int(parts[1]) if len(parts) > 1 and parts[1] else 0
    ni = int(parts[2]) if len(parts) > 2 and parts[2] else 0
    return vi, ti, ni


def parse_mtl(mtl_path: Path) -> dict[str, dict]:
    """Parse an MTL file and return material definitions."""
    materials: dict[str, dict] = {}
    current: str | None = None

    with open(mtl_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            parts = line.split()
            cmd = parts[0]

            if cmd == "newmtl":
                current = " ".join(parts[1:])
                materials[current] = {}
            elif current:
                mat = materials[current]
                if cmd == "Ka" and len(parts) >= 4:
                    mat["ambient"] = [float(parts[1]), float(parts[2]), float(parts[3])]
                elif cmd == "Kd" and len(parts) >= 4:
                    mat["diffuse"] = [float(parts[1]), float(parts[2]), float(parts[3])]
                elif cmd == "Ks" and len(parts) >= 4:
                    mat["specular"] = [
                        float(parts[1]),
                        float(parts[2]),
                        float(parts[3]),
                    ]
                elif cmd == "Ke" and len(parts) >= 4:
                    mat["emissive"] = [
                        float(parts[1]),
                        float(parts[2]),
                        float(parts[3]),
                    ]
                elif cmd == "Ns":
                    mat["shininess"] = float(parts[1])
                elif cmd == "d":
                    mat["opacity"] = float(parts[1])
                elif cmd == "map_Kd":
                    mat["diffuse_map"] = parts[1]

    return materials


# ---------------------------------------------------------------------------
# Math helpers
# ---------------------------------------------------------------------------


def euler_to_quaternion(rx: float, ry: float, rz: float) -> list[float]:
    """Convert XYZ Euler angles (radians) to quaternion [x, y, z, w]."""
    cx, sx = math.cos(rx / 2), math.sin(rx / 2)
    cy, sy = math.cos(ry / 2), math.sin(ry / 2)
    cz, sz = math.cos(rz / 2), math.sin(rz / 2)

    w = cx * cy * cz + sx * sy * sz
    x = sx * cy * cz - cx * sy * sz
    y = cx * sy * cz + sx * cy * sz
    z = cx * cy * sz - sx * sy * cz

    return [x, y, z, w]


def mat3x4_to_mat4_col_major(m: list[float]) -> list[float]:
    """Convert a 3x4 row-major affine matrix to a 4x4 column-major matrix.

    Input layout (12 floats, row-major):
        [m00 m01 m02 tx]   float[0..3]
        [m10 m11 m12 ty] = float[4..7]
        [m20 m21 m22 tz]   float[8..11]

    Output: 16 floats in column-major order with [0 0 0 1] as last row.
    """
    # Row-major 3x4:
    # m[0]  m[1]  m[2]  m[3]
    # m[4]  m[5]  m[6]  m[7]
    # m[8]  m[9]  m[10] m[11]

    # Column-major 4x4:
    # Col0: m[0], m[4], m[8],  0
    # Col1: m[1], m[5], m[9],  0
    # Col2: m[2], m[6], m[10], 0
    # Col3: m[3], m[7], m[11], 1

    return [
        m[0],
        m[4],
        m[8],
        0.0,
        m[1],
        m[5],
        m[9],
        0.0,
        m[2],
        m[6],
        m[10],
        0.0,
        m[3],
        m[7],
        m[11],
        1.0,
    ]


# ---------------------------------------------------------------------------
# Main conversion
# ---------------------------------------------------------------------------


def convert_to_gltf(model_dir: Path, anim_paths: list[Path], output_path: Path) -> None:
    """Convert KATS-tools output to glTF 2.0 binary."""

    # Find input files
    obj_files = list(model_dir.glob("*.obj"))
    if not obj_files:
        print(f"Error: no .obj files found in {model_dir}", file=sys.stderr)
        sys.exit(1)

    # Load model JSON metadata
    json_files = list(model_dir.glob("*.json"))
    model_json: dict = {}
    if json_files:
        print(json_files[0])
        with open(json_files[0], "r", encoding="utf-8") as f:
            model_json = json.load(f)

    # Load animation JSONs
    anim_data: list[dict] = []
    for ap in anim_paths:
        with open(ap, "r", encoding="utf-8") as f:
            anim_data.append(json.load(f))

    builder = GltfBuilder()

    # Material index mapping
    material_indices: dict[str, int] = {}

    # -----------------------------------------------------------------------
    # Skeleton / Skin  (MUST be processed before meshes so that
    # joint_name_to_node is available for bone palette remapping)
    # -----------------------------------------------------------------------
    skin_index: int | None = None
    skeleton_root_node: int | None = None
    joint_name_to_node: dict[str, int] = {}

    skeletons = model_json.get("skeletons", [])
    if skeletons:
        for skel in skeletons:
            joint_records = skel.get("joints", [])
            if not joint_records:
                continue

            # Create nodes for joints
            joint_node_indices: list[int] = []
            joint_ibm_matrices: list[list[float]] = []

            for jdata in joint_records:
                jname = jdata["name"]
                translation = jdata.get("translation", [0, 0, 0])
                rotation = jdata.get("rotation", [0, 0, 0])
                scale = jdata.get("scale", [1, 1, 1])

                # Convert Euler to quaternion
                quat = euler_to_quaternion(rotation[0], rotation[1], rotation[2])

                node_idx = builder.add_node(
                    name=jname,
                    translation=translation,
                    rotation=quat,
                    scale=scale,
                )
                joint_node_indices.append(node_idx)
                joint_name_to_node[jname] = node_idx

                # Inverse bind matrix
                ibm = jdata.get("inv_bind_matrix_3x4")
                if ibm:
                    joint_ibm_matrices.append(mat3x4_to_mat4_col_major(ibm))
                else:
                    joint_ibm_matrices.append(
                        [
                            1,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                            0,
                            0,
                            0,
                            1,
                        ]
                    )

            # Set up parent-child relationships
            for jdata in joint_records:
                jname = jdata["name"]
                parent = jdata.get("parent")
                if parent:
                    parent_node = joint_name_to_node.get(parent)
                    child_node = joint_name_to_node.get(jname)
                    if parent_node is not None and child_node is not None:
                        parent_node_data = builder.json_root["nodes"][parent_node]
                        if "children" not in parent_node_data:
                            parent_node_data["children"] = []
                        parent_node_data["children"].append(child_node)

            # Skeleton root node
            root_joint_name = joint_records[0]["name"]
            skeleton_root_node = joint_name_to_node.get(root_joint_name)

            # Add inverse bind matrices accessor
            ibm_accessor = None
            if joint_ibm_matrices:
                ibm_accessor = builder.add_inverse_bind_matrices(joint_ibm_matrices)

            # Create skin
            skin_index = builder.add_skin(
                joints=joint_node_indices,
                skeleton=skeleton_root_node,
                inverse_bind_matrices=ibm_accessor,
            )

    # -----------------------------------------------------------------------
    # Process each OBJ file
    # -----------------------------------------------------------------------
    mesh_node_indices: list[int] = []

    for obj_file in obj_files:
        obj_name = obj_file.stem
        obj_data = parse_obj(obj_file)

        # Try to load matching MTL
        mtl_materials: dict[str, dict] = {}
        mtl_files = list(model_dir.glob("*.mtl"))
        if mtl_files:
            mtl_materials = parse_mtl(mtl_files[0])

        # Create glTF materials from MTL
        for mat_name, mat_def in mtl_materials.items():
            if mat_name in material_indices:
                continue
            diffuse = mat_def.get("diffuse", [0.8, 0.8, 0.8])
            opacity = mat_def.get("opacity", 1.0)
            base_color = diffuse + [opacity] if len(diffuse) == 3 else diffuse
            emissive = mat_def.get("emissive", None)
            shininess = mat_def.get("shininess", 1.0)
            # Convert shininess to roughness (rough approximation)
            roughness = max(0.04, 1.0 - shininess / 128.0) if shininess else 1.0
            texture_uri = mat_def.get("diffuse_map")
            idx = builder.add_material(
                name=mat_name,
                base_color_factor=base_color,
                roughness_factor=roughness,
                emissive_factor=emissive,
                texture_uri=texture_uri,
            )
            material_indices[mat_name] = idx

        # Build meshes from face groups
        for (obj_part, mat_name), triangles in obj_data.faces.items():
            if not triangles:
                continue

            # Remap OBJ indices to local indices (OBJ uses 1-based global indices)
            vertex_map: dict[tuple[int, int, int], int] = {}
            positions: list[list[float]] = []
            normals: list[list[float]] = []
            texcoords: list[list[float]] = []
            indices: list[int] = []

            for tri in triangles:
                for vi, ti, ni in tri:
                    # OBJ indices are 1-based
                    key = (vi, ti, ni)
                    if key not in vertex_map:
                        local_idx = len(positions)
                        vertex_map[key] = local_idx
                        p_idx = abs(vi) - 1 if vi else 0
                        n_idx = abs(ni) - 1 if ni else 0
                        t_idx = abs(ti) - 1 if ti else 0
                        positions.append(
                            obj_data.positions[p_idx]
                            if p_idx < len(obj_data.positions)
                            else [0, 0, 0]
                        )
                        normals.append(
                            obj_data.normals[n_idx]
                            if n_idx < len(obj_data.normals)
                            else [0, 1, 0]
                        )
                        if ti and t_idx < len(obj_data.texcoords):
                            texcoords.append(obj_data.texcoords[t_idx])
                        else:
                            texcoords.append([0, 0])
                    indices.append(vertex_map[key])

            # Build glTF primitive
            prim: dict = {"mode": MODE_TRIANGLES}
            prim["attributes"] = {"POSITION": builder.add_positions(positions)}
            prim["attributes"]["NORMAL"] = builder.add_normals(normals)
            if texcoords:
                prim["attributes"]["TEXCOORD_0"] = builder.add_texcoords(texcoords)
            prim["indices"] = builder.add_indices(indices)

            # Apply skinning data from model JSON
            mesh_metadata = model_json.get("meshes", {}).get(obj_part, {})
            skin_data = mesh_metadata.get("skin_data")

            if skin_data and positions:
                weights_flat = skin_data["weights"]
                bone_indices_flat = skin_data["bone_indices"]

                # Build a mapping from palette index to joint node index
                # using the material's bone_refs list. bone_refs[palette_idx]
                # gives the bone name, which we look up in joint_name_to_node.
                # Fall back to dividing by 3 (D3D8 palette row heuristic) if
                # bone_refs are not available for this material.
                _bone_palette_to_joint: dict[int, int] = {}

                mat_bone_refs = (
                    model_json.get("materials", {})
                    .get(mat_name, {})
                    .get("bone_refs", [])
                    if mat_name
                    else []
                )

                if mat_bone_refs:
                    for palette_idx, bone_name in enumerate(mat_bone_refs):
                        if bone_name and bone_name in joint_name_to_node:
                            _bone_palette_to_joint[palette_idx] = joint_name_to_node[
                                bone_name
                            ]

                n_verts = len(positions)
                joints_list: list[list[int]] = []
                weights_list: list[list[float]] = []

                for v_idx in range(n_verts):
                    w = weights_flat[v_idx * 4 : v_idx * 4 + 4]
                    bi = bone_indices_flat[v_idx * 4 : v_idx * 4 + 4]
                    # bone_indices are palette indices stored as float.
                    # Convert to int, then map via bone_refs if available.
                    raw_indices = [int(b) for b in bi]
                    if _bone_palette_to_joint:
                        mapped = []
                        for ri in raw_indices:
                            # Try direct mapping first, then fall back to ri//3
                            if ri in _bone_palette_to_joint:
                                mapped.append(_bone_palette_to_joint[ri])
                            elif ri // 3 in _bone_palette_to_joint:
                                mapped.append(_bone_palette_to_joint[ri // 3])
                            else:
                                # Last resort: use the index directly as joint node
                                mapped.append(
                                    min(ri, len(joint_name_to_node) - 1)
                                    if joint_name_to_node
                                    else 0
                                )
                    else:
                        # Fallback: divide by 3 (D3D8 palette row / 3 heuristic)
                        mapped = [ri // 3 for ri in raw_indices]
                    joints_list.append(mapped)
                    weights_list.append(w)

                prim["attributes"]["JOINTS_0"] = builder.add_joints(joints_list)
                prim["attributes"]["WEIGHTS_0"] = builder.add_weights(weights_list)

            # Material
            if mat_name and mat_name in material_indices:
                prim["material"] = material_indices[mat_name]

            mesh_name = f"{obj_part}" if obj_part else obj_name
            mesh_idx = builder.add_mesh(mesh_name, [prim])
            node_idx = builder.add_node(name=mesh_name, mesh=mesh_idx, skin=skin_index)
            mesh_node_indices.append(node_idx)

    # -----------------------------------------------------------------------
    # Animations
    # -----------------------------------------------------------------------
    for anim_json in anim_data:
        animations = anim_json.get("animations", {})
        for anim_name, anim_set in animations.items():
            channels_data = anim_set.get("channels", [])
            if not channels_data:
                continue

            samplers: list[dict] = []
            channels: list[dict] = []

            for ch in channels_data:
                if ch.get("error"):
                    continue

                target_node_name = ch.get("target_node", "")
                channel_type = ch.get("channel_type", "")
                keyframes = ch.get("keyframes", [])

                if not keyframes or not channel_type:
                    continue

                # Find the target node
                target_node_idx = (
                    joint_name_to_node.get(target_node_name) if skeletons else None
                )
                if target_node_idx is None:
                    # Try matching by substring (animation names may have a prefix)
                    for name, idx in joint_name_to_node.items():
                        if name.endswith(target_node_name) or target_node_name.endswith(
                            name
                        ):
                            target_node_idx = idx
                            break

                if target_node_idx is None:
                    continue

                # Determine glTF path
                gltf_path: str | None = None
                if channel_type in ("tx", "ty", "tz"):
                    gltf_path = "translation"
                elif channel_type in ("rx", "ry", "rz"):
                    gltf_path = "rotation"
                elif channel_type in ("sx", "sy", "sz"):
                    gltf_path = "scale"

                if gltf_path is None:
                    continue

                # Collect times and values for this channel type on this node
                # We need to group channels by (target_node, path) to create
                # combined accessors for translation/rotation/scale
                times = [kf[0] for kf in keyframes]
                values = [kf[1] for kf in keyframes]

                # For rotation channels, we need all 3 (rx, ry, rz) to form a quaternion
                # For translation/scale, we need all 3 components
                # Collect all channels for this target + path combination
                sibling_channels = [
                    c
                    for c in channels_data
                    if c.get("target_node") == target_node_name
                    and c.get("channel_type", "")[0] == channel_type[0]
                    and not c.get("error")
                ]

                # Check if we already processed this target+path combo
                existing = [
                    c
                    for c in channels
                    if c["target"]["node"] == target_node_idx
                    and c["target"]["path"] == gltf_path
                ]
                if existing:
                    continue

                # Build combined data from sibling channels
                comp_map: dict[str, list[float]] = {}
                for sc in sibling_channels:
                    ct = sc.get("channel_type", "")
                    kfs = sc.get("keyframes", [])
                    comp_map[ct] = [kf[1] for kf in kfs]

                # Use the times from any channel (they should be the same)
                all_times = set()
                for sc in sibling_channels:
                    for kf in sc.get("keyframes", []):
                        all_times.add(kf[0])
                sorted_times = sorted(all_times)

                if not sorted_times:
                    continue

                # Interpolate values at each time point
                def interp_value(ct: str, t: float) -> float:
                    kfs = comp_map.get(ct, [])
                    if not kfs:
                        return 0.0
                    ch_kfs = next(
                        (c for c in sibling_channels if c.get("channel_type") == ct),
                        None,
                    )
                    if ch_kfs is None:
                        return 0.0
                    ckf = ch_kfs.get("keyframes", [])
                    if not ckf:
                        return 0.0
                    # Simple linear interpolation
                    if t <= ckf[0][0]:
                        return ckf[0][1]
                    if t >= ckf[-1][0]:
                        return ckf[-1][1]
                    for i in range(len(ckf) - 1):
                        if ckf[i][0] <= t <= ckf[i + 1][0]:
                            frac = (
                                (t - ckf[i][0]) / (ckf[i + 1][0] - ckf[i][0])
                                if ckf[i + 1][0] != ckf[i][0]
                                else 0.0
                            )
                            return ckf[i][1] + frac * (ckf[i + 1][1] - ckf[i][1])
                    return ckf[-1][1]

                # Time accessor
                time_data = struct.pack(f"<{len(sorted_times)}f", *sorted_times)
                time_bv = builder._add_buffer_view(time_data)
                time_acc = builder._add_accessor(
                    time_bv,
                    COMPONENT_FLOAT,
                    TYPE_SCALAR,
                    len(sorted_times),
                    [min(sorted_times)],
                    [max(sorted_times)],
                )

                # Value accessor
                if gltf_path == "translation":
                    vals = [
                        [
                            interp_value("tx", t),
                            interp_value("ty", t),
                            interp_value("tz", t),
                        ]
                        for t in sorted_times
                    ]
                    flat = [c for v in vals for c in v]
                    val_data = struct.pack(f"<{len(flat)}f", *flat)
                    val_bv = builder._add_buffer_view(val_data)
                    val_acc = builder._add_accessor(
                        val_bv, COMPONENT_FLOAT, TYPE_VEC3, len(vals)
                    )
                elif gltf_path == "rotation":
                    quats = [
                        euler_to_quaternion(
                            interp_value("rx", t),
                            interp_value("ry", t),
                            interp_value("rz", t),
                        )
                        for t in sorted_times
                    ]
                    flat = [c for q in quats for c in q]
                    val_data = struct.pack(f"<{len(flat)}f", *flat)
                    val_bv = builder._add_buffer_view(val_data)
                    val_acc = builder._add_accessor(
                        val_bv, COMPONENT_FLOAT, TYPE_VEC4, len(quats)
                    )
                elif gltf_path == "scale":
                    vals = [
                        [
                            interp_value("sx", t),
                            interp_value("sy", t),
                            interp_value("sz", t),
                        ]
                        for t in sorted_times
                    ]
                    flat = [c for v in vals for c in v]
                    val_data = struct.pack(f"<{len(flat)}f", *flat)
                    val_bv = builder._add_buffer_view(val_data)
                    val_acc = builder._add_accessor(
                        val_bv, COMPONENT_FLOAT, TYPE_VEC3, len(vals)
                    )
                else:
                    continue

                sampler_idx = len(samplers)
                samplers.append(
                    {
                        "input": time_acc,
                        "output": val_acc,
                        "interpolation": "LINEAR",
                    }
                )
                channels.append(
                    {
                        "sampler": sampler_idx,
                        "target": {
                            "node": target_node_idx,
                            "path": gltf_path,
                        },
                    }
                )

            if channels:
                builder.add_animation(anim_name, channels, samplers)

    # -----------------------------------------------------------------------
    # Finalize scene
    # -----------------------------------------------------------------------
    scene_nodes = list(mesh_node_indices)
    if skeleton_root_node is not None and skeleton_root_node not in scene_nodes:
        scene_nodes.append(skeleton_root_node)

    scene_idx = builder.add_scene(scene_nodes)
    builder.json_root["scene"] = scene_idx

    # Write output
    glb_data = builder.finalize()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(glb_data)

    print(f"Written: {output_path} ({len(glb_data)} bytes)")
    print(f"  Meshes: {len(builder.json_root['meshes'])}")
    print(f"  Nodes: {len(builder.json_root['nodes'])}")
    print(f"  Skins: {len(builder.json_root['skins'])}")
    print(f"  Animations: {len(builder.json_root['animations'])}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert KATS-tools output (OBJ + MTL + JSON) to glTF 2.0 (.glb)",
    )
    parser.add_argument(
        "model_dir", type=Path, help="Directory with .obj/.mtl/.json files"
    )
    parser.add_argument(
        "--animation",
        "-a",
        type=Path,
        action="append",
        default=[],
        help="Path to animation JSON file (can be specified multiple times)",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        default=None,
        help="Output .glb path (default: <model_dir>/<name>.glb)",
    )

    args = parser.parse_args()

    model_dir = args.model_dir.resolve()
    if not model_dir.is_dir():
        print(f"Error: {model_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    # Default output path
    if args.output:
        output_path = args.output.resolve()
    else:
        # Use the first OBJ file's name as base
        obj_files = list(model_dir.glob("*.obj"))
        name = obj_files[0].stem if obj_files else "output"
        output_path = model_dir / f"{name}.glb"

    anim_paths = [p.resolve() for p in args.animation]

    convert_to_gltf(model_dir, anim_paths, output_path)


if __name__ == "__main__":
    main()

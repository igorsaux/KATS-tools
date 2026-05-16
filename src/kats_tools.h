// Copyright (C) 2026 Igor Spichkin
// SPDX-License-Identifier: MPL-2.0

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

//==============================================================================
// XOR keys in LE.
//==============================================================================

// $XOR_KEYS

//==============================================================================
// Decryption functions.
//==============================================================================

/// @brief Decrypts data using a 32-bit XOR key (cyclic, in-place).
/// @param key 32-bit XOR key in native endian.
/// @param data Pointer to the data to be decrypted (in-place).
/// @param data_len Length of the data in bytes.
void kats_decrypt(uint32_t key, uint8_t *data, size_t data_len);

//==============================================================================
// Sound file functions.
//==============================================================================

/// @brief Counts the number of sound files in the data.
/// @param data Pointer to the decrypted data.
/// @param data_len Length of the data in bytes.
/// @return Number of "RIFF" signatures found.
size_t kats_sound_count_files(const uint8_t *data, size_t data_len);

/// @brief Gets the data of a sound file at the specified index.
/// @param data Pointer to the decrypted data.
/// @param data_len Length of the data in bytes.
/// @param idx Zero-based index of the sound file.
/// @param[out] out Pointer to where the address of the found sound file
///            (starting from the "RIFF" signature) will be stored.
/// @param[out] out_len Pointer to where the length of the sound file data
///                (including the signature) will be stored.
/// @return true if the sound file was found, false otherwise.
bool kats_sound_get(const uint8_t *data, size_t data_len, size_t idx,
                    const uint8_t **out, size_t *out_len);

//==============================================================================
// Clipper file functions.
//==============================================================================

/// @brief Counts the number of clipper files in the data.
/// @param data Pointer to the decrypted data.
/// @param data_len Length of the data in bytes.
/// @return Number of "BM6" signatures found.
size_t kats_clipper_count_files(const uint8_t *data, size_t data_len);

/// @brief Gets the data of a clipper file at the specified index.
/// @param data Pointer to the decrypted data.
/// @param data_len Length of the data in bytes.
/// @param idx Zero-based index of the clipper file.
/// @param[out] out Pointer to where the address of the found clipper file
///            (starting from the "BM6" signature) will be stored.
/// @param[out] out_len Pointer to where the length of the clipper file data
///                (including the signature) will be stored.
/// @return true if the clipper file was found, false otherwise.
bool kats_clipper_get(const uint8_t *data, size_t data_len, size_t idx,
                      const uint8_t **out, size_t *out_len);

//==============================================================================
// Texture file functions.
//==============================================================================

/// @brief Counts the number of texture files in the data.
/// @param data Pointer to the decrypted data.
/// @param data_len Length of the data in bytes.
/// @return Number of "TRUEVISION-XFILE.\0" footers found.
size_t kats_texture_count_files(const uint8_t *data, size_t data_len);

/// @brief Gets the data of a texture file at the specified index.
/// @param data Pointer to the decrypted data.
/// @param data_len Length of the data in bytes.
/// @param idx Zero-based index of the texture file.
/// @param[out] out Pointer to where the address of the found texture file
///            (starting from the TGA header) will be stored.
/// @param[out] out_len Pointer to where the length of the texture file data
///                (up to and including the TGA footer) will be stored.
/// @return true if the texture file was found, false otherwise.
bool kats_texture_get(const uint8_t *data, size_t data_len, size_t idx,
                      const uint8_t **out, size_t *out_len);

//==============================================================================
// Model record type enumeration.
//==============================================================================

// TLV record types used in model .bin files.

// $MODEL_RECORD_TYPES

//==============================================================================
// Model file functions.
//==============================================================================

/// @brief Counts the number of TLV records in the model data.
/// @param data Pointer to the decrypted model data.
/// @param data_len Length of the data in bytes.
/// @return Number of records found, or 0 on error.
size_t kats_model_count_records(const uint8_t *data, size_t data_len);

/// @brief Parsed TLV record descriptor.
typedef struct
{
    /// @brief Pointer to the start of the record (type field).
    const uint8_t *ptr;
    /// @brief Record type.
    uint32_t ty;
    /// @brief  Total record size in bytes (including TLV header).
    size_t size;
    /// @brief Null-terminated record name.
    const char *name;
    /// @brief ASCII digit tag (NOT null-terminated; use tag_len).
    const char *tag;
    /// @brief Length of the tag in bytes.
    size_t tag_len;
    /// @brief Pointer to the payload data (after name+tag).
    const uint8_t *data;
    /// @brief Length of the payload data in bytes.
    size_t data_len;
} kats_Record;

/// @brief Gets a TLV record at the specified index.
/// @param data Pointer to the decrypted model data.
/// @param data_len Length of the data in bytes.
/// @param idx Zero-based index of the record.
/// @param[out] out Pointer to the output record descriptor.
/// @return true if the record was found and parsed, false otherwise.
bool kats_model_get_record(const uint8_t *data, size_t data_len, size_t idx,
                           kats_Record *out);

/// @brief MeshShape header (32 bytes).
typedef struct
{
    /// @brief Bounding sphere radius.
    float radius;
    /// @brief Bounding sphere center X.
    float cx;
    /// @brief Bounding sphere center Y.
    float cy;
    /// @brief Bounding sphere center Z.
    float cz;
    /// @brief Always 1 for valid meshes.
    uint32_t flag;
    /// @brief Skeleton ID (2051, 2067, 3267, 3523, 4035).
    uint32_t skeleton_id;
    /// @brief Always 0.
    uint32_t padding;
    /// @brief Number of vertices.
    uint32_t vertex_count;
} kats_MeshShapeHeader;

/// @brief Parses the MeshShape header from a record.
/// @param record Pointer to a previously obtained record (must be of type mesh_shape).
/// @param[out] out Pointer to the output header.
/// @return true on success, false if the data is too short.
bool kats_model_get_mesh_shape_header(const kats_Record *record,
                                      kats_MeshShapeHeader *out);

//==============================================================================
// Primitive type enumeration.
//==============================================================================

// Primitive topology types for mesh index buffers.

// $PRIMITIVE_TYPES

/// @brief MeshShape trailer (index buffer descriptor).
typedef struct
{
    /// @brief Primitive topology (strip or list).
    uint32_t primitive_ty;
    /// @brief Always 1.
    uint32_t flag;
    /// @brief Number of 16-bit indices.
    uint32_t index_count;
    /// @brief Pointer to the index data.
    const uint16_t *indexes;
} kats_ModelShapeTrailer;

/// @brief Parses the MeshShape trailer (index buffer) from a record.
///
/// The trailer is located after the vertex data:
///   offset = sizeof(kats_MeshShapeHeader) + vertex_count * stride
///
/// @param record Pointer to a previously obtained record (must be of type mesh_shape).
/// @param header Pointer to the previously parsed MeshShape header.
/// @param stride Vertex stride in bytes (use kats_model_guess_mesh_shape_stride).
/// @param[out] out Pointer to the output trailer descriptor.
/// @return true on success, false if the data is invalid or too short.
bool kats_model_get_mesh_shape_trailer(const kats_Record *record,
                                       const kats_MeshShapeHeader *header,
                                       uint32_t stride,
                                       kats_ModelShapeTrailer *out);

/// @brief Auto-detects the vertex stride for a MeshShape record.
///
/// The stride is not stored explicitly in the file. This function tries each
/// candidate stride and validates the trailer that would appear after the
/// vertex data. The validation checks:
///   - Trailer has valid primitive_type (1 or 4) and flag == 1.
///   - Index count is reasonable (1..100000).
///   - Indices fit exactly within the record bounds.
///   - First index is within vertex range.
///   - First vertex position is within [-50000, 50000].
///   - First vertex normal is approximately unit length.
///
/// Candidate strides are tried in order: 32, 48, 56, 60, 64, 36, 40, 44,
/// 52, 24, 28. The first valid match is returned.
///
/// @param record Pointer to a previously obtained record (must be of type mesh_shape).
/// @param header Pointer to the previously parsed MeshShape header.
/// @param[out] out Pointer to where the detected stride will be stored.
/// @return true if a valid stride was found, false otherwise.
bool kats_model_guess_mesh_shape_stride(const kats_Record *record,
                                        const kats_MeshShapeHeader *header,
                                        uint32_t *out);

//==============================================================================
// MeshShape vertex data functions.
//==============================================================================

/// @brief Extracts position, normal, and UV for a single vertex from a MeshShape record.
///
/// Vertex data layout is determined by the stride:
///   - Position is always at byte offset 0  (3 floats, 12 bytes).
///   - Normal   is always at byte offset 12 (3 floats, 12 bytes).
///   - UV       is always at byte offset (stride - 8) (2 floats, 8 bytes).
///
/// For strides < 32 the UV fields are set to (0, 0).
///
/// @param record Pointer to a previously obtained MeshShape record.
/// @param header Pointer to the previously parsed MeshShape header.
/// @param stride Vertex stride in bytes (from kats_model_guess_mesh_shape_stride).
/// @param vertex_idx Zero-based vertex index (must be < header->vertex_count).
/// @param[out] out_position Output: 3 floats (x, y, z).
/// @param[out] out_normal Output: 3 floats (x, y, z).
/// @param[out] out_uv Output: 2 floats (u, v).
/// @return true on success, false if vertex_idx is out of range or data is too short.
bool kats_model_get_mesh_shape_vertex(const kats_Record *record,
                                      const kats_MeshShapeHeader *header,
                                      uint32_t stride,
                                      uint32_t vertex_idx,
                                      float out_position[3],
                                      float out_normal[3],
                                      float out_uv[2]);

/// @brief Returns the number of uint16_t indices in the triangle-list representation.
///
/// For triangle_list primitives, returns trailer->index_count directly.
/// For triangle_strip primitives, counts non-restart, non-degenerate triangles
/// and returns count * 3. Strip restart indices (0xFFFF) are skipped.
///
/// Use the returned value to allocate the buffer passed to
/// kats_model_mesh_shape_to_triangle_list().
///
/// @param trailer Pointer to the parsed MeshShape trailer.
/// @return Number of uint16_t elements in the triangle-list representation.
size_t kats_model_mesh_shape_triangle_list_index_count(const kats_ModelShapeTrailer *trailer);

/// @brief Converts mesh indices to triangle list format.
///
/// For triangle_list primitives, copies indices directly into the output buffer.
/// For triangle_strip primitives, converts the strip to a triangle list with
/// CW -> CCW winding correction (D3D8 uses CW front faces; output uses CCW).
///
/// Even-indexed strip triangles have their first two vertices swapped to
/// correct the winding. Strip restart indices (0xFFFF) are skipped.
///
/// The output buffer must have at least
/// kats_model_mesh_shape_triangle_list_index_count() uint16_t elements.
///
/// @param trailer Pointer to the parsed MeshShape trailer.
/// @param[out] out_indices Caller-allocated buffer of uint16_t.
/// @param[out] out_len Number of uint16_t elements in the output buffer.
/// @return true on success, false if the output buffer is too small.
bool kats_model_mesh_shape_to_triangle_list(const kats_ModelShapeTrailer *trailer,
                                            uint16_t *out_indices,
                                            size_t out_len);

//==============================================================================
// Vertex format helpers.
//==============================================================================

/// @brief Determines vertex format properties from the vertex stride.
///
/// The game does not store the vertex format explicitly; it is fully determined
/// by the stride value detected by kats_model_guess_mesh_shape_stride.
/// This function decodes the format into boolean flags and a weight count.
///
/// Stride-to-format mapping:
///   32 — position(3f) + normal(3f) + uv(2f)
///   48 — position(3f) + normal(3f) + diffuse_rgba(4f) + uv(2f)
///   56 — position(3f) + normal(3f) + weights(2f) + bone_indices(4f) + uv(2f)
///   60 — position(3f) + normal(3f) + weights(3f) + bone_indices(4f) + uv(2f)
///   64 — position(3f) + normal(3f) + weights(4f) + bone_indices(4f) + uv(2f)
///
/// For any unrecognised stride all outputs are set to false / 0.
///
/// @param stride          Vertex stride in bytes (from kats_model_guess_mesh_shape_stride).
/// @param[out] out_has_color  Set to true if the format includes per-vertex diffuse RGBA.
/// @param[out] out_has_skin   Set to true if the format includes skinning data
///                            (blend weights + bone indices).
/// @param[out] out_num_weights Set to the number of explicit blend weight components
///                             (0 for non-skinned, 2 / 3 / 4 for skinned formats).
void kats_model_get_vertex_format(uint32_t stride, bool *out_has_color,
                                  bool *out_has_skin, uint32_t *out_num_weights);

//==============================================================================
// Full vertex data (with skinning and vertex color).
//==============================================================================

/// @brief Full vertex data including optional skinning and vertex color.
///
/// For non-skinned formats the weights and bone_indices arrays are zeroed and
/// has_skin is false. For formats without vertex color the diffuse array is
/// zeroed and has_color is false.
typedef struct
{
    /// @brief Position XYZ (offset 0 in every vertex format).
    float position[3];
    /// @brief Normal XYZ, approximately unit length (offset 12).
    float normal[3];
    /// @brief Texture coordinates UV (offset stride-8, zeroed when stride < 32).
    float uv[2];
    /// @brief Per-vertex diffuse RGBA (valid only when has_color is true, offset 24).
    float diffuse[4];
    /// @brief Normalised blend weights, 4 components (valid only when has_skin is true).
    ///        Weights sum to approximately 1.0. For 2- and 3-weight formats the
    ///        implicit components are filled in (w2=0, w3=0 for 2-weight;
    ///        w3 = 1-w0-w1-w2 for 3-weight) and the entire set is re-normalised.
    float weights[4];
    /// @brief Raw bone indices stored as float (valid only when has_skin is true).
    ///        These are D3D8 matrix palette row indices. To obtain the joint
    ///        array index, divide by 3:  joint_index = (int)bone_indices[k] / 3.
    float bone_indices[4];
    /// @brief True when the vertex format includes diffuse RGBA (stride 48).
    bool has_color;
    /// @brief True when the vertex format includes skinning data (stride 56/60/64).
    bool has_skin;
    /// @brief Number of explicit blend weight components (2, 3, or 4).
    uint32_t num_weights;
} kats_MeshShapeVertexFull;

/// @brief Extracts full vertex data including skinning and vertex colour.
///
/// See kats_MeshShapeVertexFull for the layout of the output structure.
/// This function supersets kats_model_get_mesh_shape_vertex; it returns
/// everything that function returns plus diffuse colour, blend weights, and
/// bone indices.
///
/// @param record     Pointer to a previously obtained MeshShape record.
/// @param header     Pointer to the previously parsed MeshShape header.
/// @param stride     Vertex stride in bytes (from kats_model_guess_mesh_shape_stride).
/// @param vertex_idx Zero-based vertex index (must be < header->vertex_count).
/// @param[out] out   Output vertex descriptor.
/// @return true on success, false if vertex_idx is out of range or data is too short.
bool kats_model_get_mesh_shape_vertex_full(const kats_Record *record,
                                           const kats_MeshShapeHeader *header,
                                           uint32_t stride, uint32_t vertex_idx,
                                           kats_MeshShapeVertexFull *out);

//==============================================================================
// Material (Type 1) functions.
//==============================================================================

/// @brief Parsed Material record (TLV type 1).
///
/// Materials contain a D3DMATERIAL8 structure, a texture name reference, and
/// a list of bone names that influence the sub-mesh. The D3DMATERIAL8 fields
/// follow the Direct3D 8 convention (all colour values in 0..1 range).
typedef struct
{
    /// @brief Number of bone reference sub-elements that follow the D3D material.
    uint32_t sub_count;
    /// @brief Texture name (null-terminated, within record data).
    ///        Corresponds to the name of a TextureRef record.
    ///        Empty string ("") if no texture name was found.
    const char *texture_name;
    /// @brief D3DMATERIAL8 Diffuse RGBA.
    float diffuse[4];
    /// @brief D3DMATERIAL8 Ambient RGBA.
    float ambient[4];
    /// @brief D3DMATERIAL8 Specular RGBA.
    float specular[4];
    /// @brief D3DMATERIAL8 Emissive RGBA.
    float emissive[4];
    /// @brief D3DMATERIAL8 Power (shininess exponent).
    float power;
    /// @brief True if the 68-byte D3DMATERIAL8 data was successfully parsed.
    bool has_d3d_material;
    /// @brief Internal: byte offset within record->data where bone_refs begin.
    ///        Used by kats_model_get_material_bone_ref_count and
    ///        kats_model_get_material_bone_ref. Do not modify.
    size_t _bone_refs_offset;
} kats_Material;

/// @brief Parses a Material record.
///
/// Reads the texture name, D3DMATERIAL8 fields, and computes the internal
/// offset for subsequent bone reference lookups.
///
/// @param record Pointer to a previously obtained record (must be of type material).
/// @param[out] out Output material descriptor.
/// @return true on success, false if the record type is not material or data is too short.
bool kats_model_get_material(const kats_Record *record, kats_Material *out);

/// @brief Returns the number of bone references in a material.
///
/// Scans the variable-length bone reference list starting at the internal
/// offset computed by kats_model_get_material. The count is capped at
/// sub_count and at most 30 entries to avoid runaway reads on corrupt data.
///
/// @param record   Pointer to the same record passed to kats_model_get_material.
/// @param material Pointer to the previously parsed material.
/// @return Number of valid bone references found (may be less than sub_count
///         if the data is truncated).
size_t kats_model_get_material_bone_ref_count(const kats_Record *record,
                                              const kats_Material *material);

/// @brief Gets a bone reference name from a material by index.
///
/// Each bone reference is a null-terminated name stored as a name+tag pair
/// within the record payload. The tag portion is skipped automatically.
///
/// @param record   Pointer to the same record passed to kats_model_get_material.
/// @param material Pointer to the previously parsed material.
/// @param idx      Zero-based bone reference index
///                 (must be < kats_model_get_material_bone_ref_count).
/// @param[out] out_name Pointer to the null-terminated bone name
///                      (within record data, valid as long as record data is valid).
/// @return true if the bone reference was found, false if idx is out of range
///         or the data is corrupt.
bool kats_model_get_material_bone_ref(const kats_Record *record,
                                      const kats_Material *material,
                                      size_t idx, const char **out_name);

//==============================================================================
// ShapeRef (Type 2) functions.
//==============================================================================

/// @brief Parsed ShapeRef header (TLV type 2).
///
/// A ShapeRef binds materials to mesh shapes, defining which material is
/// applied to which sub-mesh. Each ShapeRef corresponds to one logical model.
typedef struct
{
    /// @brief Number of (material, mesh) binding pairs in this ShapeRef.
    uint32_t ref_count;
} kats_ShapeRefHeader;

/// @brief Parses a ShapeRef header.
///
/// @param record Pointer to a previously obtained record (must be of type shape_ref).
/// @param[out] out Output header descriptor.
/// @return true on success, false if the record type is not shape_ref or data
///         is too short.
bool kats_model_get_shape_ref_header(const kats_Record *record,
                                     kats_ShapeRefHeader *out);

/// @brief Gets a (material, mesh) binding pair from a ShapeRef by index.
///
/// Each binding pair consists of a material name and a mesh shape name,
/// both stored as name+tag pairs. The material name corresponds to a
/// Material record; the shape name corresponds to a MeshShape record.
///
/// @param record Pointer to the ShapeRef record.
/// @param idx    Zero-based binding index (must be < ref_count from header).
/// @param[out] out_material_name Pointer to the null-terminated material name
///                               (within record data).
/// @param[out] out_shape_name    Pointer to the null-terminated mesh shape name
///                               (within record data).
/// @return true if the binding was found, false if idx is out of range or the
///         data is corrupt.
bool kats_model_get_shape_ref_binding(const kats_Record *record, size_t idx,
                                      const char **out_material_name,
                                      const char **out_shape_name);

//==============================================================================
// TextureRef (Type 3) functions.
//==============================================================================

/// @brief Parsed TextureRef record (TLV type 3).
///
/// Links a texture set name (used by Material::texture_name) to an actual
/// .tga file on disk, along with Direct3D 8 sampler state parameters.
typedef struct
{
    /// @brief Texture set name (the record's own name field).
    ///        This is the key that Material::texture_name references.
    const char *texture_set_name;
    /// @brief Texture file name (e.g. "body.tga"). Empty string if not found.
    const char *texture_file;
    /// @brief D3D8 sampler state parameters (valid only when has_params is true):
    ///        [0] min_filter, [1] mag_filter, [2] mip_filter,
    ///        [3] address_u,  [4] address_v,  [5] flags.
    uint32_t tex_params[6];
    /// @brief True if the 6 DWORD texture parameters were successfully read.
    bool has_params;
} kats_TextureRef;

/// @brief Parses a TextureRef record.
///
/// The texture_set_name is taken from the record's own name field.
/// The texture_file is the first name+tag in the payload.
/// The 6 sampler parameters follow immediately after.
///
/// @param record Pointer to a previously obtained record (must be of type texture_ref).
/// @param[out] out Output texture reference descriptor.
/// @return true on success, false if the record type is not texture_ref or
///         the payload is too short for the texture file name.
bool kats_model_get_texture_ref(const kats_Record *record, kats_TextureRef *out);

//==============================================================================
// TransformNode (Type 4) functions.
//==============================================================================

/// @brief Parsed TransformNode record (TLV type 4).
///
/// Represents a scene graph node with Translation-Rotation-Scale transform.
/// Rotation angles are stored as Euler angles in radians (XYZ order).
typedef struct
{
    /// @brief Node flags (usually 0 or 1).
    uint32_t flag;
    /// @brief Translation vector XYZ.
    float translation[3];
    /// @brief Rotation Euler angles in radians (XYZ order).
    float rotation[3];
    /// @brief Scale vector XYZ (typically 1.0, 1.0, 1.0).
    float scale[3];
} kats_TransformNode;

/// @brief Parses a TransformNode record.
///
/// @param record Pointer to a previously obtained record (must be of type transform_node).
/// @param[out] out Output transform descriptor.
/// @return true on success, false if the record type is not transform_node or
///         the payload is shorter than 40 bytes.
bool kats_model_get_transform_node(const kats_Record *record,
                                   kats_TransformNode *out);

//==============================================================================
// SkeletonRoot (Type 10) functions.
//==============================================================================

/// @brief Parsed SkeletonRoot record (TLV type 10).
///
/// Marks the beginning of a skeleton definition. All Joint records that
/// follow this record in TLV order (up to the next SkeletonRoot or end of
/// file) belong to this skeleton.
typedef struct
{
    /// @brief Unknown value (usually a small number).
    uint32_t val1;
    /// @brief Usually 1.
    uint32_t val2;
    /// @brief Name of the associated shape/transform (null-terminated, within
    ///        record data). Empty string if not found.
    const char *skeleton_shape_ref;
} kats_SkeletonRoot;

/// @brief Parses a SkeletonRoot record.
///
/// @param record Pointer to a previously obtained record (must be of type skeleton_root).
/// @param[out] out Output skeleton root descriptor.
/// @return true on success, false if the record type is not skeleton_root or
///         the payload is shorter than 8 bytes.
bool kats_model_get_skeleton_root(const kats_Record *record,
                                  kats_SkeletonRoot *out);

//==============================================================================
// Joint (Type 11) functions.
//==============================================================================

/// @brief Parsed Joint record (TLV type 11).
///
/// Represents a single bone in a skeleton. The TRS transform defines the
/// bone's local pose relative to its parent. The inverse bind matrix
/// transforms from model space to bone space.
///
/// The parent-child hierarchy is NOT stored explicitly in the file.
/// Use kats_infer_joint_parent to reconstruct it from naming conventions.
typedef struct
{
    /// @brief Joint flags (usually 1).
    uint32_t flag;
    /// @brief Translation XYZ relative to the parent joint.
    float translation[3];
    /// @brief Rotation Euler angles in radians (XYZ order) relative to parent.
    float rotation[3];
    /// @brief Scale XYZ (typically 1.0, 1.0, 1.0).
    float scale[3];
    /// @brief Inverse bind matrix stored as 3×4 row-major (12 floats).
    ///        Layout:
    ///          [m00 m01 m02 tx]   float[0..3]
    ///          [m10 m11 m12 ty] = float[4..7]
    ///          [m20 m21 m22 tz]   float[8..11]
    ///        To convert to a 4×4 column-major matrix for glTF/OpenGL:
    ///          1. Append row [0 0 0 1]
    ///          2. Transpose from row-major to column-major
    float inv_bind_matrix_3x4[12];
    /// @brief True if the 48-byte inverse bind matrix was successfully read.
    bool has_inv_bind_matrix;
    /// @brief Pointer to extra data after the inverse bind matrix, or NULL.
    ///        Some joints (e.g. physics/dynamics bones) store additional
    ///        4..12 bytes whose format is currently unknown.
    const uint8_t *extra_data;
    /// @brief Length of extra_data in bytes (0 if none).
    size_t extra_data_len;
} kats_Joint;

/// @brief Parses a Joint record.
///
/// Reads the TRS transform and, if present, the 3×4 inverse bind matrix.
/// Any bytes remaining after the IBM are exposed via extra_data.
///
/// @param record Pointer to a previously obtained record (must be of type joint).
/// @param[out] out Output joint descriptor.
/// @return true on success, false if the record type is not joint or the
///         payload is shorter than 40 bytes (minimum for TRS without IBM).
bool kats_model_get_joint(const kats_Record *record, kats_Joint *out);

//==============================================================================
// KeyframeChannel (Type 8) functions.
//==============================================================================

/// @brief Parsed KeyframeChannel record (TLV type 8).
///
/// Stores a single animated property (e.g. translation X, rotation Y) for
/// one node as a series of (time, value) keyframe pairs.
///
/// The channel name encodes the target node and property type:
///   format: {target_node}_{channel_type}
///   example: "osakaBeltVibrator00_ashiL1_rx" -> target="ashiL1", type="rx"
///
/// channel_type is one of: tx, ty, tz (translation), rx, ry, rz (rotation),
/// sx, sy, sz (scale).
typedef struct
{
    /// @brief Target node name (NOT null-terminated; use target_node_len).
    ///        Points into the record's name field. This is the substring
    ///        before the last underscore in the full channel name.
    const char *target_node;
    /// @brief Length of target_node in bytes.
    size_t target_node_len;
    /// @brief Channel type string (NOT null-terminated; use channel_type_len).
    ///        One of: "tx", "ty", "tz", "rx", "ry", "rz", "sx", "sy", "sz".
    const char *channel_type;
    /// @brief Length of channel_type in bytes (always 2 for valid channels).
    size_t channel_type_len;
    /// @brief Channel flags (usually 0).
    uint32_t flag;
    /// @brief Number of keyframes in this channel.
    uint32_t kf_count;
    /// @brief Pointer to keyframe data: array of kf_count pairs (time, value),
    ///        each pair is 2 floats (8 bytes). Total size: kf_count * 8 bytes.
    ///        time values are in seconds (or animation ticks); value is the
    ///        animated scalar (translation in game units, rotation in radians,
    ///        scale as a multiplier).
    const float *keyframes;
} kats_KeyframeChannel;

/// @brief Parses a KeyframeChannel record.
///
/// Splits the record name on the last underscore to extract target_node and
/// channel_type. Records with an unrecognised channel type (not one of
/// tx/ty/tz/rx/ry/rz/sx/sy/sz) are rejected.
///
/// Keyframe count is validated against a maximum of 100000 to avoid
/// garbage data from corrupt records.
///
/// @param record Pointer to a previously obtained record (must be of type keyframe_channel).
/// @param[out] out Output channel descriptor.
/// @return true on success, false if the record type is wrong, channel type
///         is invalid, keyframe count is unreasonable, or data is too short.
bool kats_model_get_keyframe_channel(const kats_Record *record,
                                     kats_KeyframeChannel *out);

//==============================================================================
// AnimSet (Type 9) functions.
//==============================================================================

/// @brief Parsed AnimSet record (TLV type 9).
///
/// Groups KeyframeChannel records into a named animation clip.
typedef struct
{
    /// @brief Number of channels in the set.
    ///        WARNING: for some AnimSet records this value is garbage
    ///        (e.g. 1862270977). Validate before use; a reasonable range
    ///        is 0..10000. When in doubt, count channels by scanning
    ///        KeyframeChannel records whose target_node prefix matches
    ///        the AnimSet name.
    uint32_t channel_count;
} kats_AnimSet;

/// @brief Parses an AnimSet record.
///
/// @param record Pointer to a previously obtained record (must be of type anim_set).
/// @param[out] out Output anim set descriptor.
/// @return true on success, false if the record type is not anim_set or
///         the payload is shorter than 4 bytes.
bool kats_model_get_anim_set(const kats_Record *record, kats_AnimSet *out);

//==============================================================================
// Skeleton hierarchy helper.
//==============================================================================

/// @brief Infers the parent joint name from naming conventions.
///
/// The game format does not store the bone hierarchy explicitly. This
/// function reconstructs it using two strategies:
///
/// 1. Known pattern matching (case-insensitive substring):
///      koshi     -> root (no parent)
///      spine1    -> koshi
///      spine2    -> spine1
///      neck      -> spine2
///      head      -> neck
///      sholderL1 -> spine2     sholderR1 -> spine2
///      sholderL2 -> sholderL1  sholderR2 -> sholderR1
///      udeL1     -> sholderL2  udeR1     -> sholderR2
///      udeL2     -> udeL1      udeR2     -> udeR1
///      teL       -> udeL2      teR       -> udeR2
///      momoL1    -> koshi      momoR1    -> koshi
///      momoL2    -> momoL1     momoR2    -> momoR1
///      hizaL     -> momoL2     hizaR     -> momoR2
///      suneL     -> hizaL      suneR     -> hizaR
///      ashiL     -> suneL      ashiR     -> suneR
///      hairBase  -> head       hatBase   -> head
///      hairL     -> hairBase   hairR     -> hairBase
///      hairBack  -> hairBase
///
/// 2. Numeric suffix heuristic: if the joint name ends with a digit N > 1,
///    the parent is assumed to be the same name with digit N-1.
///    Example: udeL2 -> udeL1.
///
/// The inferred parent is validated against all_joint_names; only names
/// present in that list are returned.
///
/// @param joint_name       Null-terminated joint name to find the parent for.
/// @param all_joint_names  Array of pointers to null-terminated joint names
///                         belonging to the same skeleton. Used for validation
///                         and for the numeric suffix heuristic.
/// @param joint_count      Number of elements in all_joint_names.
/// @param[out] out_parent_name Set to the parent joint name (a pointer into
///                             all_joint_names), or NULL if the joint is a
///                             root (e.g. koshi) or no parent could be found.
/// @return true if a parent was found or the joint was determined to be a root,
///         false on error (null pointers).
bool kats_infer_joint_parent(const char *joint_name,
                             const char *const *all_joint_names,
                             size_t joint_count,
                             const char **out_parent_name);

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
/// @param out Pointer to where the address of the found sound file
///            (starting from the "RIFF" signature) will be stored.
/// @param out_len Pointer to where the length of the sound file data
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
/// @param out Pointer to where the address of the found clipper file
///            (starting from the "BM6" signature) will be stored.
/// @param out_len Pointer to where the length of the clipper file data
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
/// @param out Pointer to where the address of the found texture file
///            (starting from the TGA header) will be stored.
/// @param out_len Pointer to where the length of the texture file data
///                (up to and including the TGA footer) will be stored.
/// @return true if the texture file was found, false otherwise.
bool kats_texture_get(const uint8_t *data, size_t data_len, size_t idx,
                      const uint8_t **out, size_t *out_len);

//==============================================================================
// Model record type enumeration.
//==============================================================================

/// @brief TLV record types used in model .bin files.
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
/// @param out Pointer to the output record descriptor.
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
/// @param out Pointer to the output header.
/// @return true on success, false if the data is too short.
bool kats_model_get_mesh_shape_header(const kats_Record *record,
                                      kats_MeshShapeHeader *out);

//==============================================================================
// Primitive type enumeration.
//==============================================================================

/// @brief Primitive topology types for mesh index buffers.
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
/// @param out Pointer to the output trailer descriptor.
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
/// @param out Pointer to where the detected stride will be stored.
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
/// @param out_position Output: 3 floats (x, y, z).
/// @param out_normal Output: 3 floats (x, y, z).
/// @param out_uv Output: 2 floats (u, v).
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
/// CW → CCW winding correction (D3D8 uses CW front faces; output uses CCW).
///
/// Even-indexed strip triangles have their first two vertices swapped to
/// correct the winding. Strip restart indices (0xFFFF) are skipped.
///
/// The output buffer must have at least
/// kats_model_mesh_shape_triangle_list_index_count() uint16_t elements.
///
/// @param trailer Pointer to the parsed MeshShape trailer.
/// @param out_indices Caller-allocated buffer of uint16_t.
/// @param out_len Number of uint16_t elements in the output buffer.
/// @return true on success, false if the output buffer is too small.
bool kats_model_mesh_shape_to_triangle_list(const kats_ModelShapeTrailer *trailer,
                                            uint16_t *out_indices,
                                            size_t out_len);

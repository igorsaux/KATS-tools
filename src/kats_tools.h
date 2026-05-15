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

/// @brief Decrypts data using a 32-bit XOR key.
/// @param key 32-bit XOR key.
/// @param data Pointer to the data to be decrypted (in-place).
/// @param data_len Length of the data.
void kats_tools_decrypt(uint32_t key, uint8_t* data, size_t data_len);

//==============================================================================
// Sound file functions.
//==============================================================================

/// @brief Counts the number of sound files in the data.
/// @param data Pointer to the data.
/// @param data_len Length of the data.
/// @return Number of sound files found.
size_t kats_tools_sound_count_files(const uint8_t* data, size_t data_len);

/// @brief Gets the data of a sound file at the specified index.
/// @param data Pointer to the data.
/// @param data_len Length of the data.
/// @param idx Index of the sound file.
/// @param out Pointer to where the address of the found sound file (starting from the signature) will be stored.
/// @param out_len Pointer to where the length of the data *after* the signature will be stored.
/// @return true if the sound file was found, false otherwise.
bool kats_tools_sound_get(const uint8_t* data, size_t data_len, size_t idx, const uint8_t** out, size_t* out_len);

//==============================================================================
// Clipper file functions.
//==============================================================================

/// @brief Counts the number of clipper files in the data.
/// @param data Pointer to the data.
/// @param data_len Length of the data.
/// @return Number of clipper files found.
size_t kats_tools_clipper_count_files(const uint8_t* data, size_t data_len);

/// @brief Gets the data of a clipper file at the specified index.
/// @param data Pointer to the data.
/// @param data_len Length of the data.
/// @param idx Index of the clipper file.
/// @param out Pointer to where the address of the found clipper file (starting from the signature) will be stored.
/// @param out_len Pointer to where the length of the data *after* the signature will be stored.
/// @return true if the clipper file was found, false otherwise.
bool kats_tools_clipper_get(const uint8_t* data, size_t data_len, size_t idx, const uint8_t** out, size_t* out_len);

//==============================================================================
// Texture file functions.
//==============================================================================

/// @brief Counts the number of texture files in the data.
/// @param data Pointer to the data.
/// @param data_len Length of the data.
/// @return Number of texture files found.
size_t kats_tools_texture_count_files(const uint8_t* data, size_t data_len);

/// @brief Gets the data of a texture file at the specified index.
/// @param data Pointer to the data.
/// @param data_len Length of the data.
/// @param idx Index of the texture file.
/// @param out Pointer to where the address of the found texture file will be stored.
/// @param out_len Pointer to where the length of the data will be stored.
/// @return true if the texture file was found, false otherwise.
bool kats_tools_texture_get(const uint8_t* data, size_t data_len, size_t idx, const uint8_t** out, size_t* out_len);

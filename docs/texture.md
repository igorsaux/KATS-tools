# Texture Files

The game stores texture assets in files like `texture0X.bin`.

### Format Details

- **Encryption**: These files are encrypted using a 4-byte XOR key.
- **Structure**: Each `.bin` file is a concatenation of multiple TGA images. Images may use either TGA v2.0 (with the `TRUEVISION-XFILE` footer) or the older TGA v1.0 format (without a footer). Many textures in the game use the older format, so extraction must not rely solely on footer detection.
- **Extraction**: The library sequentially parses each TGA image by reading its 18-byte header, skipping over the image ID, color map, and image data (handling both uncompressed and RLE-compressed types), and optionally including the TGA v2 footer if present. This approach correctly extracts all textures regardless of whether they have a footer.

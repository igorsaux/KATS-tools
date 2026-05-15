# Texture Files

The game stores texture assets in files like `texture0X.bin`.

### Format Details

- **Encryption**: These files are encrypted using a 4-byte XOR key.
- **Structure**: Each `.bin` file is a concatenation of multiple `TRUEVISION-XFILE` (TGA) chunks.
- **Extraction**: The library extracts these individual TGA files from the container.

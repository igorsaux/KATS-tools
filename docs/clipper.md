# Clipper Files

The game stores clipper/masking assets in files like `clipper00.bin`.

### Format Details

- **Encryption**: These files are encrypted using a 4-byte XOR key.
- **Structure**: Each `.bin` file is a concatenation of multiple `BM6` (a variation of BMP) chunks.
- **Extraction**: The library extracts these individual BMP files from the container.

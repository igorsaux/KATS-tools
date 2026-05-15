# Sound Files

The game stores sound assets in files like `soundXX.bin`.

### Format Details

- **Encryption**: These files are encrypted using a 4-byte XOR key.
- **Structure**: Each `.bin` file is a concatenation of multiple `RIFF` (WAV) chunks.
- **Extraction**: The library extracts these individual WAV files from the container.

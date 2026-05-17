# KATS-tools

A collection of tools and a C API for parsing and extracting assets from _Kasuga Ayumu no Tsuhan Seikatsu_ game files.

## Supported Formats

- [Sound Formats](docs/sound.md)
- [Clipper Formats](docs/clipper.md)
- [Texture Formats](docs/texture.md)
- [Models](docs/model.md)
- [Animations](docs/animation.md)

## Extraction Notes

- **3D Models**: The CLI tool exports only the mesh geometry to `.obj` (and `.mtl` where possible). All other metadata (skinning, material properties, transforms, etc.) is exported to a `.json` file located next to the `.obj`.
- **Animations**: The CLI tool exports animation data to `.json` files. Each animation file is dumped as a JSON containing AnimSets, KeyframeChannels, and AnimRefs.

# Animation Formats

Animation files (e.g., `animation00.bin`) contain keyframe data for animating the transforms of nodes and joints within a model.

## General Structure

Like model files, animation files use a **TLV (Type-Length-Value)** record structure.

## Supported Record Types

### Animation Set (`Type 9`)

Groups a collection of animation channels together. It contains:

- **Name**: A null-terminated string identifying the set.
- **Channel Count**: The number of keyframe channels belonging to this set.

### Keyframe Channel (`Type 8`)

Contains the actual animation data for a specific property of a specific node.

- **Naming Convention**: Channels are identified by a name in the format: `[AnimSet]_[NodeName]_[ChannelType]`.
  - `ChannelType` can be:
    - `tx`, `ty`, `tz`: Translation.
    - `rx`, `ry`, `rz`: Rotation (Euler angles in radians).
    - `sx`, `sy`, `sz`: Scale.
- **Data**: A list of keyframe entries, where each entry is a pair of `(Time, Value)` (both 4-byte floats).

### Animation Reference (`Type 7`)

Used to link an animation set to a model.

## Animation Logic

1.  **Targeting**: The animation engine matches a channel to a model node by parsing the `[NodeName]` from the channel's name.
2.  **Interpolation**: The data is stored as discrete keyframes. The engine interpolates between these frames (typically linear interpolation for position/scale and spherical linear interpolation for rotations, though the raw data is Euler).
3.  **Rotation**: Rotation is stored as Euler angles (`rx`, `ry`, `rz`) in radians.

## Encryption

All animation files are encrypted using a unique **4-byte XOR key** that repeats across the file.

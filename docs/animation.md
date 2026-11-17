# Animation Formats

Animation files (e.g., `animation00.bin`) contain keyframe data for animating the transforms of nodes and joints within a model.

## General Structure

Like model files, animation files use a **TLV (Type-Length-Value)** record structure.

## Supported Record Types

### Animation Set (`Type 9`)

Groups a collection of animation channels together. It contains:

- **Name**: A null-terminated string identifying the set.
- **Channel Count**: The number of keyframe channels belonging to this set.
- **Channel Names**: `Channel Count` tagged strings referencing Keyframe Channel records by their full names. Channels are not grouped by file adjacency.

### Keyframe Channel (`Type 8`)

Contains the actual animation data for a specific property of a specific node.

- **Naming Convention**: Channels are identified by a name in the format: `[AnimSet]_[NodeName]_[ChannelType]`.
  - `ChannelType` can be:
    - `tx`, `ty`, `tz`: Translation.
    - `rx`, `ry`, `rz`: Rotation (Euler angles in radians).
    - `sx`, `sy`, `sz`: Scale.
- **Data**: A list of 12-byte keyframe entries. Each entry is `(Duration, Delta, Value)` (three 4-byte floats). `Duration` is in frames, `Delta` is the value change to the next key (wrapping to the first key for the last entry), and `Value` is the value at the key.

### Animation Reference (`Type 7`)

Used to link an animation set to a model.

## Animation Logic

1.  **Targeting**: Remove the `[AnimSet]_` prefix and parse `[NodeName]_[ChannelType]` from the channel name.
2.  **Interpolation**: Key times are cumulative durations. Values between keys are linearly interpolated using `Value + Delta * elapsed / Duration`; rotations are converted from Euler before quaternion interpolation.
3.  **Rotation**: Rotation is stored as Euler angles (`rx`, `ry`, `rz`) in radians, composed as `Rz * Ry * Rx`. Unanimated components retain the node's bind transform.

## Encryption

All animation files are encrypted using a unique **4-byte XOR key** that repeats across the file.

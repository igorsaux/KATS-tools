# Model Formats

Model files (e.g., `model00.bin`) are custom binary containers used to store 3D geometry, material properties, and scene hierarchy.

## General Structure

The files use a **TLV (Type-Length-Value)** record-based format. Each record begins with:

- **Type** (4 bytes, `u32`)
- **Size** (4 bytes, `u32`)

Following the header, each record contains a **Name and Tag**:

- A null-terminated ASCII string (the name).
- A sequence of ASCII digits (the tag), which is _not_ null-terminated.

## Supported Record Types

### Mesh Shape (`Type 0`)

Defines the actual geometry.

- **Header** (32 bytes): Contains bounding sphere data (radius and center), a flag, a `skeleton_id`, a padding field, and the `vertex_count`.
- **Vertex Data**: An interleaved array of vertices. The stride is variable to support skinning:
  - **Standard (32 bytes)**: `Position (3f)`, `Normal (3f)`, `UV (2f)`.
  - **Skinned (48-64 bytes)**: Includes additional `blend_weight` and `bone_index` data.
- **Trailer**: Located at the end of the vertex data, it contains:
  - `Primitive Type` (e.g., `1` for triangle strips, `4` for triangle lists).
  - A flag.
  - `Index Count`.
  - **Indices**: An array of 16-bit unsigned integers.

### Material (`Type 1`)

Defines how a mesh is shaded.

- **Texture Link**: Contains the name of the associated texture.
- **D3D8 Parameters**: Includes diffuse, ambient, specular, and emissive color components, plus a specular power value.
- **Bone References**: A list of bone names associated with the material.

### Shape Reference (`Type 2`)

A mapping record that binds a `Material` name to a specific `Mesh Shape` name.

### Texture Reference (`Type 3`)

Links to an external TGA image file and contains texture sampling parameters.

### Transform Node & Joint (`Type 4` & `Type 11`)

Defines the scene hierarchy and skeleton.

- **Transform Node**: Defines a node's `Translation`, `Rotation` (Euler radians), and `Scale`.
- **Joint**: Similar to a transform node but includes an **Inverse Bind Matrix** (provided as a 3x4 affine matrix) used for skinning.

### Skeleton Root (`Type 10`)

Defines the root of a skeletal hierarchy.

## Encryption

All model files are encrypted using a unique **4-byte XOR key** that repeats across the file.

# Flutter 3D Game Engine & Editor: Architecture & Roadmap

This document outlines the system architecture, core dependencies, and a multi-phase implementation roadmap for building a 3D game engine and Unity-style desktop editor using Flutter.

## 1. System Architecture Overview

The engine uses a **hybrid architecture**:

```
+--------------------------------------------------------------------+
|               Flutter Desktop Editor & Tooling (Dart)             |
|   Hierarchy • Inspector • Asset Browser • Console • Viewport Shell |
+--------------------------------------------------------------------+
                                  |
               Dart FFI Bindings & Texture Bridge
                                  |
+--------------------------------------------------------------------+
|               Native Engine Core (C++ / Rust / C)                  |
|   • 3D Render Pipeline (Vulkan / Metal / DirectX via bgfx or wgpu)  |
|   • Physics World (Jolt Physics / Rapier)                          |
|   • Scene Graph & Spatial Indexing (BVH / Octree)                  |
|   • Asset Processing & Binary Serialization                        |
+--------------------------------------------------------------------+

```

* **Dart/Flutter Layer:** Handles UI layout, docking, inspector reflection, project management, and developer-facing gameplay scripting.

* **Native Core:** Runs offscreen frame rendering directly on the GPU, executes the 60/120 Hz physics sub-stepping loop, and manages native memory allocations without Dart garbage collector (GC) interference.

## 2. Core Dependencies & Technology Stack

### A. Rendering & Viewport Layer

| Dependency | Language | Purpose & Role | 
 | ----- | ----- | ----- | 
| **`flutter_gpu`** *(or custom native texture registrar)* | Dart / C++ | Flutter's low-level hardware-accelerated rendering API. Used to draw custom 3D primitives and bind vertex/fragment shaders directly within Flutter, or as a bridge to native textures via `FlutterDesktopTextureRegistrar`. | 
| **`bgfx`** or **`wgpu-native`** | C++ / Rust | Cross-platform rendering abstraction supporting Vulkan, Metal, and DirectX 11/12. It acts as the underlying renderer if you choose a full native engine core. | 
| **`vector_math`** | Dart | High-performance 2D/3D math library (Vectors, Matrices, Quaternions, Frustums, Raycasts) optimized for Dart SIMD operations. | 

### B. Physics, Audio, & Spatial Systems

| Dependency | Language | Purpose & Role | 
 | ----- | ----- | ----- | 
| **Jolt Physics** (or **Rapier**) | C++ / Rust | Multithreaded, modern physics library built for games (used in *Horizon Forbidden West*). Handles rigid body dynamics, character kinematic controllers, continuous collision detection (CCD), and raycasts for FPS mechanics. | 
| **`miniaudio`** | C | Lightweight, cross-platform audio engine with support for 3D spatialized sound, doppler effects, and low-latency playback. | 
| **`dart:ffi`** | Dart | Built-in Dart Foreign Function Interface. Directly invokes native C/C++ exports without overhead or thread stalling. | 

### C. Editor UI & Tooling

| Dependency | Language | Purpose & Role | 
 | ----- | ----- | ----- | 
| **`multi_split_view`** | Dart | Provides resizable, nested horizontal and vertical split panels for editor layouts (Scene tree, Inspector, Console). | 
| **`flutter_docking`** (or custom dock manager) | Dart | Enables drag-and-drop tab docking similar to Unity, Visual Studio, and Blender. | 
| **`file_picker`** | Dart | Native OS dialogs for opening, saving, and importing project folders, 3D models, textures, and scenes. | 
| **`path_provider`** & **`path`** | Dart | Filesystem path management for cross-platform project workspace storage (Windows, macOS, Linux). | 

### D. Asset Pipelines & Formats

| Dependency | Language | Purpose & Role | 
 | ----- | ----- | ----- | 
| **`cgltf`** or **`assimp`** | C / C++ | Fast runtime/import-time parser for standard 3D assets (`.gltf`, `.glb`, `.fbx`, `.obj`). Converts vertex data into your engine's internal binary mesh format. | 
| **`image`** | Dart | Decoding, encoding, and manipulating texture formats (PNG, JPG, TGA) prior to GPU texture upload. | 
| **`flatbuffers`** or **`bincode`** | Multi | High-performance binary serialization for scene files (`.scene`) and compiled game packages, enabling zero-copy deserialization. | 

## 3. Five-Phase Implementation Roadmap

```
[Phase 1: Proof of Concept] ──> [Phase 2: Core Runtime] ──> [Phase 3: Editor Shell] ──> [Phase 4: Gameplay & FPS] ──> [Phase 5: Build & Export]

```

### Phase 1: Viewport & Low-Level Bridge (Months 1–2)

*Goal: Render a native 3D cube inside a Flutter desktop window at 60+ FPS.*

1. **Establish the Rendering Context:**

   * Configure a Flutter Desktop project (Windows/macOS/Linux).

   * Set up an offscreen render target (DirectX 11/12 on Windows, Metal on macOS, Vulkan on Linux) using `bgfx` or raw APIs.

   * Connect the swapchain buffer to Flutter's native `Texture` widget via the desktop texture registrar.

2. **First Triangle & Mesh:**

   * Compile basic vertex and fragment shaders.

   * Upload vertex buffers (positions, UVs, normals).

   * Draw a 3D grid and an untextured cube.

3. **Orbit Camera:**

   * Create an editor camera with perspective projection ($FOV = 60^\circ$, near/far clip planes).

   * Process Flutter mouse events (`Listener`, `GestureDetector`) to orbit, pan, and zoom the camera.

### Phase 2: Scene Architecture & Physics Engine (Months 3–4)

*Goal: Spawn objects, simulate rigid body collisions, and control an entity via Dart.*

1. **Entity-Component-System (ECS) / Scene Graph:**

   * Implement core components:

     * `TransformComponent` (Vector3 position, Quaternion rotation, Vector3 scale).

     * `MeshRendererComponent` (Mesh handle, Material handle).

     * `CameraComponent` (Projection matrices, viewport bounding).

     * `LightComponent` (Directional, Point, Ambient).

2. **Jolt Physics Integration:**

   * Write a C-API wrapper around Jolt Physics and expose it to Dart via `dart:ffi`.

   * Implement rigid bodies: dynamic (crates/balls), static (floors/walls), and kinematic.

   * Add step-world synchronization: run fixed physics updates (e.g., $60\text{ Hz}$) decoupled from variable UI render frames.

3. **Dart Scripting Framework:**

   * Define a `MonoBehaviour`-style lifecycle interface:

     ```
     abstract class GameScript {
       void onStart();
       void onUpdate(double deltaTime);
       void onFixedUpdate(double fixedDeltaTime);
       void onCollision(Collision collision);
     }
     
     ```

### Phase 3: The Unity-Style Desktop Editor (Months 5–6)

*Goal: Assemble a complete desktop workstation interface in Flutter.*

1. **Editor Layout Framework:**

   * Implement a dockable workspace with three primary view modes: **Scene**, **Game**, and **Asset Store/Settings**.

   * Build core panels:

     * **Hierarchy Panel:** TreeView displaying parent-child entity relations.

     * **Inspector Panel:** Dynamic property editors for modifying vectors, colors, textures, and script variables using reflection or code generation.

     * **Project / Asset Browser:** Folder view displaying models, audio, textures, and scripts.

     * **Console:** Logging output for runtime errors, warnings, and print statements.

2. **3D Gizmos & Ray Picking:**

   * Cast rays from editor mouse coordinates through the camera frustum into the physics/BVH world to select entities.

   * Render translation, rotation, and scale gizmos over selected entities.

### Phase 4: FPS & Gameplay Tooling (Months 7–8)

*Goal: Build a working FPS demo directly inside the editor.*

1. **First-Person Character Controller:**

   * Implement a kinematic capsule controller (Jolt Character Virtual).

   * Add WASD movement, slope sliding, stair stepping, and jump mechanics.

   * Implement mouse-look with pointer lock (`PointerLock` via Flutter Desktop).

2. **Shooting & Raycast System:**

   * High-speed raycasts for bullet trajectories and hit-scan weapons.

   * Decal projection for bullet impacts on walls.

3. **Material & Lighting Pipeline:**

   * PBR (Physically Based Rendering) shader pipeline: Albedo, Normal, Roughness, Metallic maps.

   * Directional shadow mapping (Cascaded Shadow Maps for outdoor scenes).

4. **Spatial Audio:**

   * Integrate `miniaudio` to bind 3D sound emitters to entities and a listener to the active camera.

### Phase 5: Serialization, Building & Standalone Export (Months 9+)

*Goal: Export a standalone `.exe` or `.app` without the editor interface.*

1. **Scene Serialization:**

   * Export scene graphs to `.scene` JSON or binary format.

   * Save prefab entities and materials.

2. **Player Runtime Target:**

   * Separate the build into two entry points:

     * `main_editor.dart`: Runs the full UI suite, gizmos, and inspector.

     * `main_player.dart`: Boots directly into full-screen viewport, runs game scripts, and excludes all editor UI overhead.

3. **Asset Cooking / Packaging:**

   * Compress textures into GPU-native formats (BCn on Windows, ASTC on mobile/macOS).

   * Bundle meshes, materials, audio, and scenes into a single `.pak` file for release.

## 4. Key Engineering Risks & Mitigations

| Risk | Impact | Mitigation Strategy | 
 | ----- | ----- | ----- | 
| **Dart GC Latency** | Frame drops during fast-paced FPS action. | Keep per-frame object allocations to near zero. Allocate long-lived native buffers via `dart:ffi` (`calloc` / `malloc`) instead of Dart heap objects. | 
| **Texture Copy Overhead** | High GPU-to-CPU-to-GPU memory transfer overhead. | Use zero-copy hardware shared textures (`FlutterDesktopTextureRegistrar`) so the native renderer draws directly to a surface Flutter can sample. | 
| **Scripting Sandboxing** | User scripts crashing the entire editor. | Enforce try/catch boundaries within script tick loops; provide hot-reload-friendly script registries. | 

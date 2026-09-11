# Minimalist Engine UI/UX Architecture & Implementation Roadmap: 2D (Flame) & 3D

> **Design Objective:** Build a distraction-free, high-performance editor interface inspired by tools like Blender (clean, shortcut-first, single-surface), Zed, and Linear. Avoid the visual clutter and deep nesting common in bloated editors, while retaining full desktop control for **both 2D (powered by Flame Engine)** and **3D (native bridge / viewport)** game authoring.

## 1. UX Design Philosophy: "Minimal Surface, Maximum Control"

Traditional game engines flood the screen with dozens of tabs, tiny text fields, nested menus, and toolbar rows. Our design follows five strict rules across 2D and 3D contexts:

1. **Adaptive Viewport-First Canvas:** The canvas adapts dynamically depending on whether a 2D Flame scene or a 3D native scene is loaded.

   * **2D Mode (Flame):** Embeds Flame's `GameWidget` directly with crisp pixel-grid snapping, orthographic camera controls, and 2D sprite/tile gizmos.

   * **3D Mode (Native Bridge):** Embeds the high-throughput GPU texture bridge with perspective orbit camera controls and 3D translation/rotation gizmos.

2. **Command Palette & Hotkey First (`Ctrl/Cmd + K`):** Any action—spawning a Flame `SpriteComponent`, adding a 3D mesh, toggling tile collision, searching assets, or running the scene—can be triggered in under 2 seconds.

3. **Contextual & Dimension-Aware Disclosure:** If a 2D scene is active, hide 3D-specific clutter (quaternions, directional shadow cascades, depth-bias) and show 2D primitives (`PositionComponent`, `Anchor`, `Sprite`, `Z-Index`, `Box2D/Forge2D`). When 3D is active, switch to 3D transform vectors ($X, Y, Z$) and mesh/PBR shaders.

4. **Zero-Lag Input & Flat Visual Hierarchy:** Monospace numerical readouts, flat high-contrast dark tones, consistent 4px/8px grid units, and zero nested accordion bloat.

5. **Seamless 2D/3D Mode Switcher:** Instant top-bar toggle between 2D and 3D coordinate systems with dedicated tool presets for each.

## 2. Editor Layout Architecture

The UI is organized into a cohesive, responsive grid with collapsable edge drawers and a central adaptive HUD.

```
+---------------------------------------------------------------------------------------+
|  [Logo]  Scene: Level_01 (2D Flame) [▶ Play/⏹] [ Mode: 2D | 3D ] [ Gizmo: W E R ] (60) | Top Bar (36px)
+-------------------+-----------------------------------------------+-------------------+
| Scene Hierarchy   |                                               | Inspector         |
| (Collapsible)     |           ADAPTIVE VIEWPORT CANVAS            | (Collapsible)     |
|                   |                                               |                   |
| ├ World2D         |      [2D Flame GameWidget / 3D Texture]       | Flame Transform   |
| ├ TileMap (Grid)  |                                               |  Pos: [120, 240]  |
| └ PlayerCharacter |          [ Active Tool: Rect / Gizmo ]        |  Angle: 0.0 rad   |
|   ├ SpriteComp    |                                               |  Size: [32, 48]   |
|   ├ Hitbox2D      |   ┌─────────────────────────────────────┐     |  Anchor: Center   |
|   └ ParticleEmitter|  | ⚡ Command Palette [Cmd+K]           |     |                   |
|                   |   └─────────────────────────────────────┘     | SpriteAnimation   |
|                   |                                               |  Frames: 8 (12fps)|
|                   |   [ Mode Toolbar: ⊞ Tilemap ✎ Collision ◈ FX ]| + Add Component   |
+-------------------+-----------------------------------------------+-------------------+
| Bottom Drawer: [ Terminal / Console ]  [ Assets / Spritesheet Slicer ] (Collapsed)    | Footer (28px)
+---------------------------------------------------------------------------------------+

```

### Layout Specifications

| Section | Height / Width | Default State | 2D (Flame) Behavior | 3D Behavior | 
 | ----- | ----- | ----- | ----- | ----- | 
| **Top Bar** | `36px` | Always Visible | Shows scene name, `2D`/`3D` pill switch, Flame tick rate, Play/Step controls. | Shows scene name, 3D camera projection switch, Play/Step controls. | 
| **Left Shelf (Hierarchy)** | `240px` | Pin or Auto-Slide | Lists Flame `Component` tree (`PositionComponent`, `SpriteGroupComponent`, etc.). | Lists 3D Scene Graph nodes and entities. | 
| **Right Shelf (Inspector)** | `300px` | Pin or Auto-Slide | 2D vector inputs ($X, Y$), rotation in radians/degrees, anchor point selector, Sprite/Animation pickers. | 3D vector inputs ($X, Y, Z$), Euler/Quaternions, PBR materials, 3D colliders. | 
| **Bottom Drawer** | Variable (`200px`) | Collapsed (`28px` bar) | Contains Console logs, Asset browser, and integrated **Spritesheet Slicer / Tilemap Palette**. | Contains Console logs, Asset browser, and 3D Mesh / Material import cards. | 
| **Floating HUD Overlays** | Floating widgets | Context-dependent | Orthographic zoom level (`100%`, `200%`, `Pixel-Perfect`), 2D Grid snapping ($8\text{px}, 16\text{px}, 32\text{px}$). | 3D Camera speed, View mode (Lit, Wireframe), Coordinate Space (Local/World). | 

## 3. Minimalist UI Component Library

To keep the application light, responsive, and easy to maintain across both modes:

```
ui_primitives/
  ├── vector2_field.dart       // Compact [X: 0] [Y: 0] field for Flame 2D coordinates
  ├── vector3_field.dart       // Scrubbable [X: 0.0] [Y: 0.0] [Z: 0.0] row for 3D
  ├── anchor_selector.dart     // Minimal 3x3 clickable grid to set Flame Component Anchor
  ├── spritesheet_preview.dart // Lightweight 2D frame picker & slicer widget
  ├── compact_accordion.dart    // Ultra-thin component section with expand/collapse arrow
  ├── command_palette.dart      // Spotlight-style fuzzy search popup (2D & 3D actions)
  ├── hotkey_listener.dart      // Global keyboard accelerator dispatch
  └── status_pill.dart          // Sleek glassmorphism status pill for HUD values

```

### Core Interactions

1. **Scrubbable 2D & 3D Fields:** Drag horizontally on `X` or `Y` to scrub values. In 2D mode, hold `Shift` to snap to integer pixels (preventing texture filtering blur in Flame).

2. **Interactive 2D Anchor Selector:** A small $3 \times 3$ dot matrix widget in the inspector that lets developers switch a Flame component's anchor (`TopLeft`, `Center`, `BottomCenter`, etc.) with one click.

3. **Smart Drag-and-Drop Spawning:**

   * Dragging a `.png` into the 2D viewport automatically wraps it in a Flame `SpriteComponent`.

   * Dragging a `.gltf` into the 3D viewport instantiates it as a 3D mesh entity with transform.

## 4. Five-Phase Implementation Roadmap

```
[Phase 1: Minimal Shell & Dual Viewport] ──> [Phase 2: Flame 2D Engine Core] ──> [Phase 3: 3D Viewport & Native Bridge] ──> [Phase 4: Unified Inspector & Palette] ──> [Phase 5: Polish & Build Export]

```

### Phase 1: Minimalist Shell & Dual-Canvas Architecture (Weeks 1–3)

*Focus: Establish a zero-overhead window skeleton that cleanly swaps between 2D (Flame) and 3D viewports.*

* \[ \] **Unified Window Header:** Integrate custom window chrome (borderless window with 36px top bar and window control integration).

* \[ \] **Dual Viewport Switcher:**

  * `2D Mode`: Mounts Flame's `GameWidget` inside the central stack.

  * `3D Mode`: Mounts native GPU texture buffer widget.

* \[ \] **Single-Key Panel Toggling:**

  * `B`: Toggle Left Sidebar (Hierarchy).

  * `I`: Toggle Right Sidebar (Inspector).

  * `` ` `` (Tilde): Toggle Bottom Console/Asset Drawer.

  * `Tab` or `F11`: Fullscreen Zen canvas mode (collapses all sidebars).

* \[ \] **FPS & Engine Stats Pill:** Minimal readout: `60 FPS | 16.6ms | Mode: 2D (Flame) | 42 Components`.

### Phase 2: Flame 2D Engine Integration & 2D Tooling (Weeks 4–6)

*Focus: Seamless integration of Flame's ECS component tree, spritesheets, and 2D physics.*

* \[ \] **Flame Component Hierarchy Tree:**

  * Inspect Flame's component hierarchy (`Component.children`) in real-time.

  * Visual distinction between `SpriteComponent`, `PositionComponent`, `ShapeHitbox`, and custom logic components.

  * Inline visibility and debug-hitbox toggles.

* \[ \] **2D Interactive Canvas Overlay:**

  * Orthographic pan & zoom using Flutter gestures (`ScrollWheel` for zoom, `Space + Drag` to pan).

  * Pixel-grid visualizer with custom snap increments ($8\text{px}, 16\text{px}, 32\text{px}, 64\text{px}$).

  * 2D selection bounding box with 4-corner scale handles.

* \[ \] **Integrated Spritesheet / Tile Palette Drawer:**

  * Minimal popup to select sprite grids, slice frames, and drag tiles directly into a Flame `TiledComponent` or grid layer.

* \[ \] **Flame Forge2D / Hitbox Inspector:**

  * Add and tweak 2D collision boxes (`CircleHitbox`, `RectangleHitbox`, `PolygonHitbox`) with real-time visual handles in the viewport.

### Phase 3: 3D Viewport & Native Bridge Integration (Weeks 7–9)

*Focus: Connect the high-throughput 3D rendering pipeline alongside the 2D workflow.*

* \[ \] **Native 3D Viewport:**

  * Share GPU texture context via `FlutterDesktopTextureRegistrar` or `flutter_gpu`.

  * Orbit, pan, and first-person fly camera controls.

* \[ \] **3D Gizmo System:**

  * Translation, rotation, and scale gizmos rendered over 3D selections (`W`, `E`, `R` hotkeys).

* \[ \] **3D Component Cards:**

  * 3D Transform ($X, Y, Z$ Position, Rotation, Scale).

  * 3D Rigidbody (Jolt / Rapier) and MeshRenderer bindings.

### Phase 4: Fast Navigation & Unified Command Palette (Weeks 10–12)

*Focus: Eliminate deep menus using a contextual keyboard-first palette.*

* \[ \] **Spotlight Command Palette (`Ctrl/Cmd + K`):**

  * Context-sensitive search index:

    * *2D Actions (Flame):* `Create SpriteComponent`, `Add RectangleHitbox`, `Slice Spritesheet`, `Toggle Flame Debug Mode`, `Toggle Hitbox Outlines`.

    * *3D Actions:* `Create Cube`, `Create Directional Light`, `Toggle Wireframe`, `Add 3D Collider`.

    * *Navigation:* `Switch to 2D Mode`, `Switch to 3D Mode`, `Find Component...`, `Open Script...`.

* \[ \] **Scrubbable Vector Field Primitives:**

  * Reusable `Vector2Field` (for Flame) and `Vector3Field` (for 3D) with drag gestures and direct input.

* \[ \] **Quick Asset Drawer:**

  * Tag-filtered view (`#sprites`, `#audio`, `#mesh`, `#dart`).

  * Instant drag-and-drop into either 2D or 3D viewports.

### Phase 5: Ergonomics, Scripting Sandbox & Standalone Export (Weeks 13–15)

*Focus: Developer ergonomics, build pipelines, and standalone deployment.*

* \[ \] **Dark Monochromatic Color Palette:**

  * Surface 0 (Viewport canvas): `#121316`

  * Surface 1 (Side panels / drawers): `#18191E`

  * Surface 2 (Inputs, cards, search bars): `#22242B`

  * Accent Color 2D (Flame Teal): `#00F5D4`

  * Accent Color 3D (Indigo): `#6366F1`

* \[ \] **Standalone Game Exporter:**

  * For 2D games: Compile clean Flutter + Flame app without any editor UI or debug layers.

  * For 3D games: Compile native player wrapper bundling assets and scripts.

## 5. Sample Core UI Component: Flame 2D Anchor Selector

Here is a minimalist, space-saving $3 \times 3$ anchor picker designed specifically for Flame's `Anchor` values:

```
import 'package:flutter/material.dart';

enum MinimalAnchor {
  topLeft, topCenter, topRight,
  centerLeft, center, centerRight,
  bottomLeft, bottomCenter, bottomRight,
}

class FlameAnchorSelector extends StatelessWidget {
  final MinimalAnchor currentAnchor;
  final ValueChanged<MinimalAnchor> onSelected;

  const FlameAnchorSelector({
    super.key,
    required this.currentAnchor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF22242B),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow([MinimalAnchor.topLeft, MinimalAnchor.topCenter, MinimalAnchor.topRight]),
          const SizedBox(height: 3),
          _buildRow([MinimalAnchor.centerLeft, MinimalAnchor.center, MinimalAnchor.centerRight]),
          const SizedBox(height: 3),
          _buildRow([MinimalAnchor.bottomLeft, MinimalAnchor.bottomCenter, MinimalAnchor.bottomRight]),
        ],
      ),
    );
  }

  Widget _buildRow(List<MinimalAnchor> anchors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: anchors.map((anchor) {
        final isSelected = anchor == currentAnchor;
        return GestureDetector(
          onTap: () => onSelected(anchor),
          child: Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF00F5D4) : const Color(0xFF333642),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }).toList(),
    );
  }
}

```

## 6. Summary of Key UX Shortcuts

| Key Combination | Action | Mode Relevance | UX Benefit | 
 | ----- | ----- | ----- | ----- | 
| `Ctrl / Cmd + K` | Open Command Palette | 2D & 3D | Instant access to any tool, component, or action. | 
| `2` / `3` (in Top Bar) | Toggle 2D Flame / 3D Mode | Global | Quickly switches viewport canvas and inspector schema. | 
| `Space + Drag` | Pan Viewport Canvas | 2D (Flame) | Smooth canvas navigation across expansive tilemaps. | 
| `F` | Focus on Selection | 2D & 3D | Re-centers camera frustum on selected component. | 
| `Cmd / Ctrl + B` | Toggle Hierarchy Shelf | Global | Collapses component tree for extra screen space. | 
| `Cmd / Ctrl + I` | Toggle Inspector Shelf | Global | Collapses property panel. | 
| `Tab` | Zen / Fullscreen Mode | Global | Hides all panels simultaneously for uninterrupted gameplay testing. | 

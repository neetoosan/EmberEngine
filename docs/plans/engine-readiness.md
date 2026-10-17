# Plan: engine readiness (complete 2D, then 3D import)

Two goals:

- **Part A, complete 2D readiness:** any common type of 2D game can be built
  in Ember without writing engine code.
- **Part B, 3D model import:** any model that imports cleanly into Godot also
  imports into Ember (glTF first).

This plan details roadmap Phase 4 ([sellable-roadmap.md](sellable-roadmap.md)).
Items marked (4.x) are the same work as that roadmap row.

## What "ready" means: the 2D genre checklist

A genre counts as ready when a small sample game or automated test plays
through it. Today:

| Genre | Status | Missing |
|---|---|---|
| Platformer | ✅ Ember Quest, 2D Platformer | gamepad |
| Top-down action RPG | ✅ Ember Legends | gamepad |
| Physics puzzle | ✅ Ember Siege | none |
| Arcade / one-button | ✅ Flappy Arcade | none |
| Match-3 / grid puzzle | ✅ Ember Gems | none |
| Card / board game | ✅ Ember Solitaire (`pick`, `layer`, drag in script) | a board-game sample (turns, AI opponent) |
| Visual novel / story | ✅ The Last Ember (Story Player) | localization, more text effects (colour, shake, speed) |
| Shoot-'em-up / bullet hell | ⚠️ | performance at 1,000+ sprites, object pooling |
| Metroidvania / large maps | ⚠️ | big-map performance, map/minimap, room transitions |
| Tower defense | ⚠️ pathfinding exists | waves helper, placement grid, sample |
| Roguelike | ⚠️ | seeded random, procedural rooms/noise helpers |
| Strategy / city builder | ❌ | isometric and hex maps, unit selection, Y-sort |
| Fighting game | ❌ | gamepad, frame-exact hitboxes, input buffer |
| Rhythm game | ❌ | sample-accurate audio timing |
| Local co-op | ❌ | gamepad, several players' input |
| Online multiplayer | ❌ | networking (needs a server decision) |

## Part A: complete 2D readiness

### A1. Input and workflow (biggest everyday friction first)

| # | Work | Done when |
|---|---|---|
| A1.1 | **Gamepad** (4.4): Xbox/PlayStation pads as actions and stick axes on Windows, Android and web; several pads for several players (`Input.player(2).action("jump")`). | Every template is playable on a pad; a 2-player test. |
| A1.2 | **Drag-and-drop import + sprite-sheet slicer** (4.2): drop PNG/WAV/OGG/MP3 onto the editor; slice by grid or auto-detect. | Import a sheet and use its frames in under a minute. |
| A1.3 | **Animation editor** (4.3): pick frames, set FPS and loop, preview; writes Sprite Animator clips. | Clips made without editing JSON. |
| A1.4 | **Prefabs as files** (4.1): `.prefab` assets, edit once and every copy updates; `spawn("Crate")` loads them. | Templates use prefab files instead of hidden entities. |

### A2. World building

| # | Work |
|---|---|
| A2.1 | **Auto-tiling** (rules for edges and corners) and **several tilesets per map** (4.7). |
| A2.2 | **Isometric and hex tilemaps** with the right draw order (Y-sort) for characters walking behind objects. |
| A2.3 | **Tile layers** (background, decoration, collision, foreground) and **big maps in chunks** so only what is on screen is drawn and collided. |
| A2.4 | **Rooms and map:** room transitions with camera bounds, and a minimap / world-map widget. |
| A2.5 | **Procedural helpers:** seeded random (`Random(seed)`), noise, room-and-corridor and cave generators that write into a tilemap. |

### A3. Look and feel

| # | Work |
|---|---|
| A3.1 | **2D lights and shadows:** point and spot lights, ambient darkness, light-blocking tiles. Optional normal maps later. |
| A3.2 | **Sprite shaders:** flash, outline, dissolve, palette swap, wave/distortion, written as Flutter fragment shaders. Those work on Windows, Android and web; checked on all three. |
| A3.3 | **Screen effects and transitions:** fades and wipes between levels, screen flash, slow motion, a vignette, chromatic aberration. |
| A3.4 | **Tweens from Ember Script:** `tween(self, "x", 200, 0.5, "easeOut")` for UI and juice (the engine already has tweens; expose them). |

### A4. Animation

| # | Work |
|---|---|
| A4.1 | **Skeletal 2D animation:** bones, sprites attached to bones, keyframed clips, simple 2-bone IK; an editor timeline. |
| A4.2 | **Import an open skeletal format** (DragonBones JSON; Spine needs its own licence, so only if a user brings a Spine licence). |

### A5. Content, UI and text

| # | Work |
|---|---|
| A5.1 | **Localization** (4.6): string tables, `tr("key")`, a language picker, right-to-left text. |
| A5.2 | **More UI:** text input fields, scroll lists, grids (inventories, card hands), layout containers, sliders and toggles (settings menus), drag-and-drop between slots. |
| A5.3 | **Story tools:** ✅ done in the Story Player (portraits with expressions, choices with conditions, typewriter and `*stress*`, history, Auto/Skip, save slots). Still to do: localization and more text effects (colour, shake, speed). |
| A5.4 | **Audio:** mixer and music crossfade (4.5), sample-accurate timing and beat events for rhythm games, looping music sections. |
| A5.5 | **Video playback** for intros and cutscenes (check package support on Windows, Android and web first). |

### A6. Scale and performance

| # | Work | Done when |
|---|---|---|
| A6.1 | **Sprite batching** (one `drawAtlas` per sheet) and **object pooling** for spawned bullets and particles. | 2,000 moving sprites at 60 fps on a mid laptop and a mid Android phone. |
| A6.2 | **Spatial hashing** for hitboxes and triggers. | 500 enemies colliding without slowdown. |
| A6.3 | **Stress tests in CI** for big tilemaps (500 x 500), many entities, long play sessions (memory). | Numbers tracked per release. |

### A7. Multiplayer (decide scope with the sales model)

| # | Work |
|---|---|
| A7.1 | **Local multiplayer:** several gamepads, split or shared screen (needs A1.1). |
| A7.2 | **Online, small scale:** host/join over WebSocket with a relay, entity sync and player input; online leaderboards. Needs a server, so it ties into the sales-model decision. |

### Order for Part A

A1 (input and workflow), then A6.1 (performance, so bigger games stay
smooth), then A2, A5, A3, A4, A7. Each finished item turns one or more ⚠️/❌
rows of the genre checklist green, preferably with a small sample template.

## Part B: 3D model import (Godot-style, glTF first)

Built in pure Dart so imports and imported games work on Windows, web and
Android. glTF 2.0 (`.gltf` / `.glb`) at the core like Godot, plus a few Unity
ideas: LOD naming, material remap by name, import presets.

### B1. glTF meshes and hierarchy (the core)

| # | Work | Done when |
|---|---|---|
| B1.1 | **glTF/.glb reader** in Dart. It reads the JSON, binary buffers and accessors, every mesh primitive (positions, normals, indices, vertex colours), and nodes with position/rotation/scale and parenting. | Reads glTF sample models from Khronos, Kenney, Quaternius and Blender exports without errors. |
| B1.2 | **Materials:** base colour, metallic/roughness, emissive (including `KHR_materials_emissive_strength`), and transparency. These map to Ember's `Material3D` (colour, glow, opacity). | A Blender material's colour and glow look the same in Ember. |
| B1.3 | **Model assets that save and export:** `MeshRenderer3D` refers to `model.glb#MeshName` instead of keeping the mesh only in memory, so scenes save, reload and export. | Export a game with a model, run it on Windows and web. |
| B1.4 | **Import as a prefab:** a model becomes an entity tree, one child per Blender object, keeping the names. It can be placed in scenes and spawned with `spawn("Robot")`. | Drag a `.glb` into the editor; it appears and can be moved, scaled and saved. |
| B1.5 | **Sidecar `model.glb.import`** (Godot's idea): scale, axis fix, which parts to import. Automatic re-import when the file changes on disk. | Re-exporting from Blender updates every scene that uses the model. |
| B1.6 | **Name hints** (Godot, plus Ember extras): `-col`, `-colonly`, `-convcolonly` (box), `-rigid`, `-trigger`, `-noimp`, `-emit` (glow), `_LOD0`/`_LOD1` (Unity). | A Blender object named `Crate-col` arrives with a working collider. |
| B1.7 | **Budget and Doctor:** triangle count shown on import. The Doctor warns about models that are too heavy for the CPU renderer, or that use features it can't show yet (textures, skinning). | Clear warnings instead of silent slowdowns. |

### B2. Textures

| # | Work |
|---|---|
| B2.1 | **Renderer:** UV coordinates through the vertex loop. Draw textured triangles with Flutter's `drawVertices` plus an image shader (the GPU does the texture work), batched per material. |
| B2.2 | **glTF textures:** base colour and emissive maps, embedded or as separate files, with sampler wrap and filter settings. Normal and roughness maps are ignored at first. |
| B2.3 | **Texture budget:** downscale large images on import (an import setting) to keep web and Android memory low. |

### B3. Animation

| # | Work |
|---|---|
| B3.1 | **Animation Player 3D:** plays glTF animation clips on node position/rotation/scale (rigid parts: doors, turrets, robot arms). Covers loop, blend and speed, with `self.animation.play("walk")` from Ember Script. |
| B3.2 | **Skinned meshes:** skeletons and joints, with skinning in the vertex loop (CPU, like the rest of the renderer). |
| B3.3 | **Shared animations:** a bone map onto a standard humanoid (Godot's bone map / Unity's Humanoid), so one animation set, such as Mixamo, works on many characters. |
| B3.4 | **Blend shapes (morph targets)** for faces and squash and stretch. |

### B4. More formats and polish

| # | Work |
|---|---|
| B4.1 | **OBJ (+ MTL):** simple, very common for props. |
| B4.2 | **`.blend` and FBX via conversion** (desktop editor only): run Blender in the background to convert to glTF, the same thing Godot does. No native FBX reader (the format is closed). |
| B4.3 | **Material remap by name** (Unity): name a material `Metal` in Blender and it uses the project's Metal material. |
| B4.4 | **Import presets** and a **post-import Ember Script hook** (`onImport(model)`) for automatic fixes. |
| B4.5 | **Runtime loading:** games can load `.glb` files while running (mods, user content). |

### Compatibility checks

A test corpus of free CC0 models: Khronos glTF samples, Kenney, Quaternius,
and exports from the user's Blender generator. Each part of B lists which of them
import exactly as they do in Godot. Known gaps, until the renderer grows, are
listed in the README:

- no depth buffer;
- triangle budget of a few thousand per view;
- no normal maps.

### Order and size for Part B

B1 is the most valuable on its own: untextured low-poly models from
Blender. That's also what the user's generator should output first. Then B2
(textures), then B3 (animation), then B4.

Rough sizes: B1 L, B2 M, B3 L, B4 M.

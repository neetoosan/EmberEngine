# Ember Engine

A 2D + 3D game engine and editor written in Flutter/Dart. You build scenes in a
Unity-style editor (hierarchy, inspector, gizmos, command palette), press
**Play** to test them in place, save them as project folders, and export them
as a standalone game you can double-click.

- **3D**: entity/component scenes, a Dart software renderer (perspective,
  lighting, near-plane clipping), first-person character controller with
  collisions, hitscan raycasts, rigid bodies, 3D particles.
- **2D**: Flame-based viewport, tilemaps with solid-tile collision, platformer
  controller (coyote time, jump buffering, variable jump height), 2D particles.
- **Audio**: procedural sound effects (jump, laser, hit, coin, explosion,
  click) with volume buses, ducking and stereo panning, played through the
  speakers.

## Run the editor

```sh
flutter pub get
flutter run -d windows          # also: -d macos / -d linux
```

The **Project Hub** opens first. Pick a starter template:

| Template | What you get when you press Play |
|---|---|
| Flappy Arcade | A complete Flappy Bird-style game: flap between random pipes, score, best score, restart |
| 3D FPS Arena | First-person movement, mouse-look, shooting a target bot |
| 2D Platformer Adventure | Tile platforms, jumping, collectable coins |
| Procedural Particle Playground | Live 2D/3D particle emitters |
| Blank Canvas | Camera + light (3D) or an empty 2D world |

New projects are saved to `Documents/EmberProjects/<Project Name>/`.

### Editor controls

| Keys | Action |
|---|---|
| `Ctrl+S` | Save project |
| `Ctrl+P` | Play / pause |
| `Esc` | Stop and restore the scene to how it was before Play |
| `Ctrl+K` | Command palette |
| `Ctrl+B` / `Ctrl+I` / `` ` `` | Toggle hierarchy / inspector / bottom drawer |
| `W` `E` `R` | Move / rotate / scale gizmo (3D) |
| `Ctrl+D`, `Delete` | Duplicate / delete selected entity |
| Right-drag, middle-drag, wheel | Orbit, pan, zoom the 3D editor camera |

While the game runs, keys go to the game:

- **3D FPS**: `WASD` move, mouse look, click or `F` fire, `Space` jump, `Shift` sprint.
- **2D platformer**: `A`/`D` or arrows move; `Space`, `W` or `Up` jump.

## Project folder format

```text
My Game/
  project.ember.json        manifest: name, pipeline (2D/3D), scene + script index
  scenes/MainScene.scene    JSON scene: entities, components, hierarchy
  scripts/*.dart            notes/scratch code from the in-editor script tab
```

Open an existing project with **Project Hub → Open & Import → Browse Folder**,
or from **Recent Projects**.

## Game code (scripts)

Dart is compiled ahead of time, so real gameplay code lives in the engine
source, not inside project files:

1. Write a `GameScript` subclass in [`lib/game/game_scripts.dart`](lib/game/game_scripts.dart)
   (there is a `HoverBob` example).
2. Register it by name in `registerGameScripts()`.
3. In the editor, add a **Script Component** to an entity and pick your script
   from the dropdown.

Built-in scripts: `FPS Player Controller`, `Platformer 2D Controller`,
`Procedural Rotator`, `Collectible`, `Hover Bob`, and the Flappy Arcade
scripts (`lib/templates/flappy_game.dart` is a complete worked example).

What a script can do:

```dart
class Enemy extends GameScript {
  @override
  void onUpdate(double dt) { /* move, read Input, ... */ }

  @override
  void onTriggerEnter(EmberEntity other) {      // hitbox overlap (non-solid)
    if (other.name == 'Player') destroy();       // removed at end of frame
  }
}
```

- `spawn(entity)` / `destroy([entity])` / `find('Name')` — create and remove objects mid-game.
- `onTriggerEnter/Exit`, `onCollisionEnter/Exit` — needs a **Hitbox 2D** on both entities.
- `EmberEngine.instance.restartScene()` / `switchScene(scene)` — restart or change level.
- `SaveData.instance.getInt('best')` / `setInt(...)` — progress kept between runs.
- `Input.isMouseButtonJustPressed(0)` also covers taps; `Input.instance.mouseWorldPosition` in 2D.

## 2D building blocks

- **Images:** put PNGs in the project's `assets/` folder (Asset Browser → Import),
  then pick them on a **Flame Sprite** (Image field). Sprite sheets: set Sheet
  Columns/Rows and change `frame` from a script to animate.
- **Camera 2D:** set a design size (e.g. 288×512); the game scales to any window
  with bars. Optional follow target and level bounds. Its frame is outlined in the editor.
- **UI Text:** on-screen text (score, messages) anchored to the screen.

## Export a standalone game

Click the **Export** button (share icon) in the editor's top bar.

1. The first time, click **Build player runtime**. This runs
   `flutter build windows --release -t lib/main_player.dart` (the engine
   without the editor) and keeps the result in `build/player_runtime/`.
2. Choose an output folder and click **Export**.

You get `<Output>/<Game Name>/<Game Name>.exe` plus its runtime files and a
`game.emberpkg.json` holding your scenes. Zip that folder to share the game.

The runtime can also be run directly with a game file:

```sh
flutter run -d windows -t lib/main_player.dart            # built-in demo scene
ember_engine.exe path\to\game.emberpkg.json               # a specific game
```

## Tests

```sh
flutter analyze
flutter test
```

## Current limitations

- Rendering is a CPU software rasterizer on a Flutter `Canvas` (painter's
  algorithm). It suits low-poly scenes, not large detailed worlds.
- Sprites and meshes are procedural primitives; image/glTF asset import is
  not implemented yet.
- Physics is box-based (AABB colliders); there is no rotated-box or mesh
  collision.
- Mouse-look uses cursor movement over the viewport (no OS pointer lock).
- Export is automated for desktop builds; mobile/web need a manual
  `flutter build` with `-t lib/main_player.dart`.

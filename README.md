# Ember Engine

A 2D + 3D game engine and editor written in Flutter/Dart. You build scenes in a
Unity-style editor (hierarchy, inspector, gizmos, command palette), press
**Play** to test them in place, save them as project folders, and export them
as a standalone game you can double-click.

- **3D**: entity/component scenes, a Dart software renderer (perspective,
  lighting, near-plane clipping, sky and fog, glowing materials), first-person
  character controller with collisions and mouse capture, hitscan raycasts,
  3D enemy AI and projectiles, rigid bodies, 3D particles.
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
| Ember Arena | A first-person 3D wave shooter: exploding drones, strafing gunners and charging brutes come through four portals; blaster and scatter gun, health and ammo drops, endless waves, best wave and score, music |
| Ember Gems | A match-3 puzzle: swap gems to line up 3+, striped gems from 4, star gems from 5, chain reactions, hints, 3 levels (score goal, collect rubies, break ice), moves, stars, unlocks, music |
| Ember Solitaire | Klondike solitaire, Draw 1 or Draw 3: drag or click cards, stock and waste, undo, hints, auto-finish, score and timer, best time and wins per mode |
| The Last Ember | A short visual novel: two characters with four expressions each, painted backgrounds, three choices, four endings, history log, auto and skip, save/load slots, music |
| Ember Siege | An Angry Birds-style physics game: drag back the slingshot, fling embers, heavy coal and splitting sparks at wood, ice and stone castles that tip, crack and shatter; powder kegs, frost imps, 3 levels, stars, unlocks, best scores, music |
| Ember Legends | A top-down monster-slaying RPG: title screen, village with NPCs, field and dungeon, sword combat, slimes/bats/skeleton archers, the Ember Golem boss, XP & levels, gold, potions, save & continue, music |
| Ember Quest | A Mario-style platformer: 2 levels, stomp slimes, "?" blocks, bricks, power berry, spikes, pits, lives, score, music |
| Flappy Arcade | A complete Flappy Bird-style game: flap between random pipes, score, best score, restart |
| 3D FPS Arena | First-person movement and mouse-look; shoot a strafing target bot (hit counter in Ember Script) |
| 2D Platformer Adventure | One short level to learn from: run, jump a pit, collect 12 coins (three small Ember Scripts) |
| Procedural Particle Playground | 3D fire and spark emitters; Space or click fires bursts |
| Blank Canvas | Camera + light (3D) or an empty 2D world |

New projects are saved to `Documents/EmberProjects/<Project Name>/`.

### Your work is safe

- An orange dot on the save button means there are unsaved changes. Going back
  to the Hub or closing the window asks **Save / Don't Save / Cancel**.
- While you work, a recovery copy is written every minute (and when you press
  Play) to `<project>/.recovery/`. If Ember closes unexpectedly, opening the
  project offers to restore it. Saving removes the copy.
- Errors never close the editor or an exported game; a panel that fails shows a
  short message instead. Details go to a daily log
  (`%APPDATA%/Ember Engine/Ember Engine/logs`).
- **Ember Doctor** (shield icon) checks the project for real: scripts compile,
  Script Components point to existing scripts, buttons/doors/`loadLevel()` lead
  to existing scenes, every image and sound exists, and what each export needs is
  installed. Problems come with an *Open script* / *Save now* button.
- **About** (`Ctrl+K` → About, or the Hub's About tab): version, what's
  included, open-source licences, the log folder and a *Copy problem report*
  button (version, system and recent errors, never your project files).

### Editor controls

| Keys | Action |
|---|---|
| `Ctrl+S` | Save project |
| `Ctrl+Z` / `Ctrl+Y` (or `Ctrl+Shift+Z`) | Undo / redo any scene edit (also the arrows in the top bar) |
| `Ctrl+1` / `Ctrl+2` | Scene / Script workspace |
| `Ctrl+P` | Play / pause |
| `Esc` | Stop and restore the scene to how it was before Play |
| `Ctrl+K` | Command palette |
| `Ctrl+B` / `Ctrl+I` / `` ` `` | Toggle hierarchy / inspector / bottom drawer |
| `W` `E` `R` | Move / rotate / scale gizmo (3D) |
| `Ctrl+D`, `Delete` | Duplicate / delete selected entity |
| Right-drag, middle-drag, wheel | Orbit, pan, zoom the 3D editor camera |

While the game runs, keys go to the game:

- **3D FPS**: `WASD` move, mouse look, click or `F` fire, `Space` jump, `Shift` sprint.
- **Ember Arena**: click the game to capture the mouse (`Esc` frees it).
  `WASD` move, mouse aims, click fires (hold for the blaster), `1`/`2` or `Q`
  switch weapon, `Space` jump, `Shift` sprint.
- **2D platformer / Ember Quest**: `A`/`D` or arrows move; `Space`, `W` or `Up`
  jump (hold for higher); `Shift` run. Land on slimes to squash them, hit
  "?" blocks from below, eat the berry to grow (big heroes break bricks).
- **Ember Gems**: drag a gem onto a neighbour (or click one, then the other)
  to swap them. A hint glows after a few idle seconds.
- **Ember Solitaire**: drag cards, or click one to send it to the best place;
  click the stock to draw. `Ctrl+Z` undoes, `H` shows a hint.
- **The Last Ember**: click, `Space` or `Enter` reads on; click a choice or press
  `1`–`6`; hold `Ctrl` to skip. The pills above the text box open the log, toggle
  Auto/Skip and save or load one of three slots.
- **Ember Siege**: drag the shot back from the slingshot and let go (mouse or
  touch); tap again in flight for its power (sparks split in three, coal slams
  down). Keyboard: arrows aim, `Space` fires, `R` retries.
- **Ember Legends**: `WASD`/arrows move; `Space`, `J` or click swings the sword;
  `E` talks (Elder, Merchant, save crystal); `Q` drinks a potion; `Esc` pauses
  (Resume / Save Game / Quit to Title).

## Project folder format

```text
My Game/
  project.ember.json        manifest: name, pipeline (2D/3D), scene + script index
  scenes/MainScene.scene    JSON scene: entities, components, hierarchy
  scripts/*.dart            notes/scratch code from the in-editor script tab
```

Open an existing project with **Project Hub → Open & Import → Browse Folder**,
or from **Recent Projects**.

## Game code: Ember Script

Click **Script** in the top bar (or `Ctrl+2`; `Ctrl+1` goes back to the scene)
to open the Script workspace. **New** creates a `.ember` script from a template
(top-down player, platformer player, chasing enemy, coin, spawner, HUD).
**Attach to selected** puts it on the entity selected in the scene, or pick it in
an entity's **Script Component**. Press **Play**: scripts run immediately, with
no rebuild, and they also run in exported games.

```dart
var speed = 140;          // top-level variables: one per entity, editable in the Inspector

void onUpdate(dt) {
  self.position = self.position + Input.move * speed * dt;
  if (Input.pressed("Space")) playSound("jump");
}

void onTriggerEnter(other) {
  if (other.hasTag("coin")) {
    destroy(other);
    find("Score").text.text = "Got one!";
  }
}
```

- Dart-like syntax: `var`/`final`, `if`/`else`, `for`, `for (x in list)`, `while`,
  functions, lambdas `(x) => x * 2`, lists, maps, `'Hi $name ${hp + 1}'`.
  Type names (`int x = 1;`) are allowed and ignored.
- Events: `onStart`, `onUpdate(dt)`, `onTriggerEnter(other)`, `onDamaged`,
  `onDeath`, `onKill`, `onInteract(by)`, `onUIAction(action)`, …
- `self` is the entity. `self.x`, `self.position`, `self.health.damage(1)`,
  `self.sprite.flipX`, `self.get("Any Component").anyInspectorField`,
  `self.add("Health")`, `other.call("stun", 2)`, `other.script.speed = 0`.
- Engine: `Input`, `Game`, `find`, `findAll`, `findNearest`, `spawn`, `destroy`,
  `strike`, `after`, `every`, `tween`, `say`, `playSound`, `loadLevel`,
  `saveValue`/`loadValue`, `vec(x, y)`, random and math helpers.
- Grids, cards and drag-and-drop: `pick(Input.mouse, "card")` returns the
  top-most entity under a point (`pickAll` returns all of them, top first);
  `self.layer` reads or sets the draw order and `self.scale` the size, so a
  dragged card can be lifted above the others and tweened back.
- The **API reference** panel (book icon) lists everything with examples, and a
  click inserts it. The editor has autocomplete (`Ctrl+Space`), `Ctrl+F`
  find/replace, `Ctrl+/` comments and smart indentation.
- Errors are marked as you type. Runtime errors appear under **Problems** with
  the line (click to jump) and never crash the editor; an endless loop is
  stopped. `print(...)` goes to **Output** and the Console.
- Edits to a script apply to the running game as soon as they are valid,
  keeping its variables' values.
- The **Ember Gems, Ember Solitaire, Ember Siege, Ember Legends, Ember Quest and Flappy Arcade** templates are written in
  Ember Script: open the Script workspace in a project made from one to read and
  change the hero, monsters, boss, pipes and so on. Their scenes show the prefab
  pattern: hidden "… Template" entities (loot, pipes, sword slash) copied with
  `spawn("Gold Template", position)`. `Game.data` keeps lives, score or
  inventory across levels.

### Compiled scripts (Dart)

Engine-level behaviours can still be written in Dart and compiled in:

1. Write a `GameScript` subclass in [`lib/game/game_scripts.dart`](lib/game/game_scripts.dart)
   (there is a `HoverBob` example).
2. Register it by name in `registerGameScripts()`.
3. In the editor, add a **Script Component** to an entity and pick your script
   from the dropdown (listed under "Built into the engine").

Built-in scripts: `FPS Player Controller`, `Platformer 2D Controller`,
`Procedural Rotator`, `Collectible`, `Hover Bob`, and the template scripts
(`lib/templates/flappy_game.dart`, `quest_game.dart` and `legends_game.dart`
are complete worked examples).

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
- **Sprite Animator:** named clips on a sprite sheet, written like
  `idle=0-1@3; run=2-4@12; jump=5; die=6@1!` (`!` = play once). Scripts call
  `animator.play('run')`; the Platformer 2D Controller does this automatically.
- **Parallax Layer:** backgrounds that scroll slower than the camera and repeat sideways.

## 2D physics (Rigid Body 2D)

Real rigid-body physics (Box2D, via the pure-Dart `forge2d` package, so it runs
on Windows, Android and web). `lib/templates/siege_game.dart` is a complete
worked example.

- **Rigid Body 2D:** dynamic (falls, tumbles, stacks), static or kinematic; box
  or circle fitted to the entity's box; density, friction, bounciness, damping,
  gravity scale, fixed rotation, *Fast Moving* (no tunnelling for projectiles),
  *Sensor* (touch events only) and *Start Asleep* (a tower stays perfectly still
  until something hits it). Orange/grey/blue outlines show colliders in the editor.
- **Painted ground collides:** solid tiles of any Tile Map are colliders for
  rigid bodies, updated when you repaint or a script removes a tile.
- **Joint 2D:** hinge (with optional motor), weld, rope and spring to another
  body or to a fixed point; a *Break Force* makes it snap (`onJointBreak`).
- **Physics World 2D:** gravity and scale for the scene (optional).
- **Scripts:** `onHit(other, impulse, speed)` for impacts (use the impulse for
  damage; resting contacts never count), `self.rigidbody.velocity`,
  `applyImpulse(v)`, `angularVelocity`, `mass`, `sleeping`;
  `Physics.raycast(a, b)`, `Physics.entitiesAt(p)`,
  `Physics.explode(center, radius, strength)`, `Physics.settled`, `Physics.gravity`.
- Also new for 2D: **Line 2D** (bands, ropes, dotted aim lines), camera **Zoom**
  and `camera.shake(amount, seconds)`, and `Input.mouseReleased` for drag-and-release.

## 3D games (first-person, AI, projectiles)

`lib/templates/arena_game.dart` (the **Ember Arena** template) is a complete
worked example. Everything below can be used by any 3D game.

- **Ember Script in 3D:**
  - **Vectors:** `vec3(x, y, z)` with `+ - * /`, `length`, `normalized()`,
    `dot`, `cross`, `distanceTo`, `lerp`, `flat`, `withX/Y/Z`.
  - **Entities:** `self.position` (a Vec3), `z`, `worldPosition`,
    `yaw`/`pitch`/`roll` in degrees, `forward`/`right`/`up`, `lookAt(target)`
    and `turnToward(target, maxDegrees)`. `distanceTo`, `directionTo` and
    `moveToward` work in 3D, and `spawn("Template", vec3(...))` places copies.
  - **Movement:** `self.controller.move(dir, sprint)`, `jump()`, `grounded`.
  - **Physics:** `Physics.raycast(from, to, ignore)` returns a RayHit3D
    (`entity`, `point`, `normal`, `distance`) or null.
    `Physics.lineOfSight(from, to)` checks whether the way is clear. Trigger
    colliders (pickups) don't block either.
  - **Mouse:** `Input.mouseDelta`; `Input.lockMouse()` / `lockMouse(false)`
    and `Input.mouseLocked`.
- **Mouse capture:** first-person games (the stock FPS Player Controller, or a
  script calling `Input.lockMouse()`) capture the mouse on the first click,
  so you can keep turning without hitting the screen edge.
  - Until then the game waits behind a "Click to play" note.
  - `Esc` or switching windows frees the mouse.
  - Works on Windows and in browsers (Pointer Lock).
- **Enemy AI 3D:** three behaviours.
  - **Chaser:** runs up and hits; with *Explodes On Attack* it's a kamikaze drone.
  - **Shooter:** keeps its distance, strafes, and fires dodgeable shots only
    when it can see you.
  - **Charger:** winds up, charges in a straight line, then is dizzy for a moment.
  - All three steer around obstacles and each other, and can hover.
  - Scripts receive `onAttack(target)`, `onFire(shot)` and `onCharge()`, and
    can read `self.enemy.state`.
- **Projectile 3D:** glowing shots with team-aware hits, optional gravity and
  splash damage, and an *Impact Effect* (a particle emitter that bursts where
  it lands).
- **Health in 3D:** hits flash every mesh of the entity red and knock a
  Character Controller 3D back (`health.damage(n, source, pushVec3)`).
- **Look:**
  - **Environment 3D:** a sky gradient and distance fog.
  - **Glow (Emission):** materials that shine in their own colour.
  - **`mesh.flash(color, seconds)`:** flash a mesh from a script.
  - **Tube:** an open cylinder for pipes and rings.
  - **Draw Order Bias:** keeps thin surfaces such as trims, decals and portals
    in front of what they sit on, since there's no depth buffer.
  - Disabling a parent now hides its children's meshes too.
  - 3D particles shrink with distance.
- **Stock overlay:** the viewport draws its own crosshair and controls hint only
  for the stock FPS Player Controller; games with their own player script draw
  their own HUD.

## Visual novels (Story Player)

Put a **Story Player** component on an entity and point it at a `.story` file
(The Last Ember's is `the_last_ember.story`, in the Script workspace). The player
draws the background, the characters, the text box with a typewriter effect,
choices, a history log, Auto/Skip and three save slots plus an autosave, and
it records which endings were found. Edits to the story show while it plays.

```text
@background forge assets/templates/story/forge.png
@character mira "Mira" #F59E0B assets/templates/story/mira.png neutral happy sad surprised
@var trust = 0

label start:
scene forge fade
show mira sad center
mira sad: Come on... just a little longer.
Someone knocks at the door.          (a line with no name is narration)
choice:
  * Open the door {trust += 1} -> open
  * Ask who it is first -> ask
  * The secret option [if trust > 2] -> secret
```

- Characters are sprite sheets with one frame per expression; `who expression:`
  changes it, and characters who aren't speaking are dimmed.
- Commands: `scene`, `show` (left/center/right), `hide`, `music`, `sound`,
  `set trust += 2`, `if trust >= 3 and secret jump label`, `wait 0.5`,
  `event name` (calls `onStoryEvent(name)` in scripts) and `end Ending name`.
- Text can use `{trust}` to show a variable and `*word*` for stress.
- Scripts reach it as `self.story`: `variable("trust")`, `setVariable`,
  `jump("label")`, `label`, `speaker`, `ended`. A title screen opens the story by
  setting `Game.data["storyLoad"]` to `""` (new), `"auto"` (continue), `"1"`–`"3"`
  or `"menu"` (the load screen) before `loadLevel`.
- **Ember Doctor** checks every `.story` file and points to the first mistake
  with its line (an unknown character, label or background, a broken condition).

## Top-down games and RPGs

`lib/templates/legends_game.dart` is a complete worked example of all of these.

- **Top-Down Controller 2D:** 8-way movement that slides along solid tiles;
  call `move(direction, dt)` from a script. Knockback is built in.
- **Health:** hit points with a team (no friendly fire), a hit flash and
  invulnerability time. Scripts get `onDamaged`, `onDeath`, and the attacker gets
  `onKill(victim)` (award XP there). `Combat.strike(scene, rect, team:, damage:)`
  is a sword swing; a **Projectile** is an arrow or fireball.
- **Monster AI:** wander → notice the target (tag `player`) → chase, walking
  around walls with A* pathfinding → melee or ranged attack → give up and go
  home. Sight/attack ranges, damage, cooldown, wind-up, projectile sprite and
  XP reward are all Inspector settings.
- **Door:** touching it (or pressing `E`, if set) fades out and loads another
  scene, placing the player on the entity named in *Arrive At*.
- **Dialogue:** lines like `Elder: Beware the caves.` shown in a typewriter box
  when the player interacts (`Interaction.interact(scene, player)`); game time
  pauses while it is open.
- **UI Button / UI Bar / UI Image:** clickable menus (with hotkeys), health and
  XP bars, rows of hearts. Buttons send their action to every script's
  `onUIAction`.
- **Layers:** a scene can have several tilemaps (e.g. a walkable *Ground* and a
  solid *Obstacles* layer); untick *Collision* on decoration layers and pick the
  layer to paint in the Tile Palette.
- **Progress:** `Inventory` (items + gold), `SaveSlots.save(1, {...})` /
  `load(1)`, `EmberTween.run(...)` for animations, and
  `EmberEngine.instance.timeScale = 0` to pause the game behind a menu.

## Building levels (platformers)

- **Paint tiles:** open the bottom drawer's **Tilemap** tab, pick a tile (turns
  on Paint), then left-drag in the 2D view to paint and right-drag to erase.
  Set the tilemap's *Tileset Image* to draw tiles from your own art.
- **Tile behaviour** (per tile ID, in the palette): Solid, One-way platform,
  Hazard, Breakable brick, "?" block, Used block, Decoration.
  Scripts on the player get `onHeadBump(tile)` (bricks, "?" blocks — call
  `tile.setTile(0)` to break one) and `onTileTouch(tile)` (hazards).
- **Enemies:** the built-in `Patrol Walker` script walks back and forth on a
  Character Controller 2D, turning at walls and ledges; `squash()` it when stomped.
- **Levels:** the scene menu next to the Ember logo creates/switches scenes and
  sets the start scene. From a script: `EmberEngine.instance.loadLevel('Level 2')`;
  `restartScene()` replays the current level. Exported games contain every scene.
- **Music:** `AudioSystem.instance.playMusic('assets/audio/theme.ogg')` (loops),
  or an Audio Source with *looping* + *play on awake*. WAV, MP3 and OGG work.
- Long levels are fine: only tiles near the camera are drawn and only tiles
  near a character are collision-checked.

## Export a standalone game

Click the **Export** button (share icon) in the editor's top bar.

### Name, icon and version

**Project Settings** (command palette, or **Name, icon, version…** in the
Export dialog) sets how the game presents itself:

- **Game name:** window title, app name, browser tab.
- **Version and build number:** the build number must go up for every store
  upload. Ember raises it after each signed Android build.
- **Publisher:** shown in file properties, installers and stores.
- **Icon:** a square PNG, 512x512 is best. Ember makes every size each
  platform needs.
- **Android app id**, plus the **MSIX package name and publisher** copied from
  Microsoft Partner Center.

**Project Doctor** checks these before you export.

### Windows

The first time, click **Build player runtime**. This runs
`flutter build windows --release -t lib/main_player.dart` (the engine without
the editor) and keeps the result in `build/player_runtime/`. Then choose a
format:

- **Game folder (.exe):** `<Output>/<Game>/<Game>.exe` carries the game's
  name, version, publisher and icon. The Visual C++ runtime is bundled, so it
  starts on PCs that don't have it installed. Optional extras:
  - a **ZIP** to share (itch.io, Steam uploads);
  - an **installer** (`<Game> Setup.exe`, per-user, with a Start-menu shortcut
    and an uninstaller). The installer needs [Inno Setup](https://jrsoftware.org)
    (free); without it, only the `.iss` script is written.
- **MSIX package:** `<Game>.msix`. It needs the Windows SDK (MakeAppx,
  MakePri and SignTool), which comes with Visual Studio's "Windows SDK"
  component.
  - **Unsigned:** for uploading to the Microsoft Store, which signs it. The
    package name and publisher must match Partner Center.
  - **Signed with your certificate (.pfx):** for your website or your own PCs.
    The package publisher is taken from the certificate.
  - **Create a test certificate:** makes a self-signed `.pfx` and `.cer` in
    `Documents/Ember Keys`. Each test PC must trust the `.cer` first: open it,
    then Install Certificate → Local Machine → Trusted People. For public
    downloads, use a certificate from a certificate authority, or the Store.

### Web (itch.io)

**Build web player** once. Each export writes a folder and
`<Game>-web.zip` with `index.html` at its root. On itch.io, upload the ZIP as
an HTML game ("This file will be played in the browser").

### Android

Android export does a full Flutter build, so it needs the engine source folder
and the Android SDK.

- **APK:** install it directly on phones and tablets. Without a key it is
  debug-signed.
- **App bundle (.aab):** what Google Play asks you to upload.
- **Signing:** Play builds are signed with your **upload key**. You can create
  one in the dialog (`Documents/Ember Keys/<Game> upload key.p12`) or pick an
  existing keystore.
  - The password can be remembered in Windows Credential Manager. It is never
    stored in the project.
  - Back up the key and its password. Every update of the game must be signed
    with the same key.

### Running the player directly

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

- 3D is basic: primitive meshes drawn by a CPU rasterizer on a Flutter `Canvas`,
  depth-sorted (no depth buffer, no shadows, no textures). It suits low-poly
  scenes of a few thousand triangles (Ember Arena's busiest waves are about 4,500).
- No 3D model (glTF/OBJ) import yet; 2D images and sounds can be imported.
- Export targets are Windows (.exe, installer, MSIX), web and Android (APK,
  signed app bundle); macOS, Linux and iOS export are not available yet.
- No gamepad input yet.
- Stories can't be translated yet (one language per `.story` file), and text
  effects are limited to `*stress*`.
- Mouse capture is available on Windows and the web; on macOS and Linux,
  mouse-look still uses cursor movement over the viewport.

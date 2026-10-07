# Plan: Making Ember Engine sellable

Status: Phase 1 done (2026-10-06); Phases 2–5 not started. Written 2026-10-06.
Sales model: **not decided yet**. Phases 1–4 are needed under any model. Phase 5 depends on
the choice.

Size guide: **S** = a day or less, **M** = a few days, **L** = a week or more.

## Where the engine stands (audit, 2026-10-06)

**Strong already**
- Playable editor with undo/redo, a Script workspace, Ember Script, and five complete games
  (Siege, Legends, Quest, Flappy, 2D Platformer) plus 3D and particle demos.
- Real 2D physics, tilemaps with painting, UI widgets, dialogue, combat and AI.
- Export to Windows, web and Android. 197 automated tests.

**Would hurt a paying customer today**
| Problem | Where |
|---|---|
| The Doctor panel shows hard-coded "passed" results. It claims export readiness for macOS, Linux and iOS, which Ember can't export to. | `lib/editor/panels/doctor_panel.dart` |
| The Engine Info page and the 3D/particle template text advertise things that don't exist: "shadow casting", "GPU particles". | `project_launcher.dart`, `template_manifest.dart` |
| No autosave, no crash recovery, and no "unsaved changes" warning when leaving a project or closing the window. | `ember_editor_app.dart` |
| No crash handler or log file, so if something breaks, neither the user nor we can see why. | `main_editor.dart` |
| The editor and every exported game use the default Flutter icon. | `windows/runner/resources/app_icon.ico` |
| No About screen and no open-source licence notices. Flame, forge2d and others are MIT and need their notices shown. | — |
| Three older templates (2D Platformer, 3D FPS, Particles) ship `.dart` "scripts" that do nothing. They look broken next to the Ember Script templates. | `template_manifest.dart` |
| Android exports are debug-signed, so they can't go on the Play Store. Windows exports are unsigned, so SmartScreen warns. | `game_exporter.dart` |
| No gamepad support, no drag-and-drop import, prefabs only as hidden in-scene entities, no 3D model import. | — |

## Phase 1: Release blockers (trust and data safety)
Goal: nothing in the product lies, and nobody loses work.

**Status (2026-10-06): done, except the optional update check in 1.9.** It needs a
website to check against. Everything else is in, tested and checked in the real
Windows editor.

| # | Work | Size | Done when |
|---|---|---|---|
| 1.1 | **Honest Doctor:** real checks only. Scripts compile (`EmberScripts.problems`), every asset referenced by scenes exists, the export runtimes for Windows/web exist, Flutter is on PATH for Android, the project is saved. Each failure gets a "Fix" or "How to fix" action. | M | Every line reflects a real check; tests cover pass and fail cases. |
| 1.2 | **Honest copy:** rewrite the Engine Info page and template text to describe only what exists. List real platforms: Windows, web, Android. | S | Every claim can be pointed to in code. |
| 1.3 | **Autosave and recovery:** save a recovery copy every 60 s and on Play. After a crash, offer "Restore unsaved changes?" on next open. | M | Killing the editor mid-edit loses at most 60 s of work (tested). |
| 1.4 | **Unsaved-changes prompts:** Save / Don't Save / Cancel when going home, opening another project, or closing the window. Show a dirty marker (●) by the project name. | S | No path out of a project skips the prompt. |
| 1.5 | **Crash handler and logs:** catch Flutter and Dart errors, keep the editor running where possible, write `logs/editor-<date>.log`, add an "Open log folder" button. Export a "report a problem" bundle (log + system info, no project content unless the user ticks it). | M | A thrown error in a panel shows a friendly message, not a red screen. |
| 1.6 | **Branding:** Ember app icon for the editor (Windows/Android/web), window title with version, splash screen. | S | No default Flutter icon anywhere in the editor build. |
| 1.7 | **About and licences:** version, credits, Flutter's licence page (it bundles all package notices automatically), link to the website and support. | S | Licences reachable in two clicks. |
| 1.8 | **Fix the older templates:** rewrite the 2D Platformer and Particles templates in Ember Script. For 3D FPS, add the small 3D Script API they need (move/jump the 3D controller, raycast a shot) and rewrite it too. Remove the dead `.dart` notes. | M | Every template's scripts run, and each has a test that plays it. |
| 1.9 | **Version and update notice:** one version number shown everywhere. Optional "a new version is available" check against a JSON file on the website, off by default and no tracking. | S | — |

## Phase 2: Publishing exports
Goal: a user can ship a game to a store without leaving Ember.

| # | Work | Size | Done when |
|---|---|---|---|
| 2.1 | **Game identity:** icon (pick a PNG; Ember makes .ico / Android / web sizes), display name, version, publisher, all set in a Project Settings window. | M | Exported Windows/web/Android games show the game's own icon and name. |
| 2.2 | **Android release builds:** create or choose a keystore (stored outside the project, password in secure storage), build a signed **AAB** for the Play Store as well as an APK. Explain where to back up the key. | M | Uploads to the Play Console without errors. |
| 2.3 | **Windows installer:** optional setup.exe (Inno Setup or MSIX) with Start menu shortcut and uninstaller. Signing documented: users with a code-signing certificate can plug it in. | M | — |
| 2.4 | **Web for itch.io:** one-click ZIP with the right layout (index.html at the root, relative paths), plus a checklist for the itch.io page settings. | S | The ZIP plays on itch.io as uploaded. |
| 2.5 | **Real-device testing:** play every template on an Android phone, Chrome/Edge/Firefox, and a clean Windows PC without Flutter installed. Fix what breaks, especially audio on web. | M | A test log per platform in `docs/qa/`. |
| 2.6 | **Optional later:** macOS and Linux export (the project folders exist; needs builds and testing on those systems, and Apple notarization for macOS). | L | — |

## Phase 3: First-run experience
Goal: a new user makes something fun in the first 10 minutes, without docs.

| # | Work | Size | Done when |
|---|---|---|---|
| 3.1 | **Welcome flow:** on first launch, "Play a demo" (opens Siege and presses Play) or "Make your first game" (guided tutorial). | S | — |
| 3.2 | **Guided tutorial:** step-by-step overlay that highlights the real UI. Steps: add a sprite, a Rigid Body, a script that jumps on Space, press Play, export. Can be skipped and restarted. | L | A tester who has never used Ember finishes it unaided. |
| 3.3 | **Built-in docs:** a Help panel with the manual (component guides, Ember Script reference already generated from `ScriptApi`, export guides), searchable, works offline. | M | — |
| 3.4 | **Polish pass:** empty states ("No entities yet: add one"), tooltips on every toolbar button, clearer error messages, keyboard-shortcut sheet (`?`). | M | — |
| 3.5 | **Template gallery upgrade:** screenshots or GIF previews on the template cards; a "difficulty / what you'll learn" line. | S | — |

## Phase 4: Engine features users expect
Goal: close the most common gaps people compare engines on. Ordered by expected value.

| # | Work | Size |
|---|---|---|
| 4.1 | **Prefabs as assets:** save an entity as a `.prefab` file (the serializer already supports it), drag into any scene, edit once and update all copies. `spawn("Crate")` loads prefab files. | L |
| 4.2 | **Drag-and-drop import:** drop PNG/WAV/OGG/MP3 files onto the editor; sprite-sheet slicer (grid or auto-detect). | M |
| 4.3 | **Animation editor:** pick frames from a sheet, set FPS and loop, preview; writes Sprite Animator clips. | M |
| 4.4 | **Gamepad support:** Xbox/PlayStation pads as Input actions and a stick axis, on Windows, Android and web. | M |
| 4.5 | **Audio mixer and music crossfade**, per-category volume in exported games (settings menu template). | S |
| 4.6 | **Localization:** string tables per language and `tr("key")` in Ember Script. | M |
| 4.7 | **Tilemap upgrades:** auto-tiling (rules for edges/corners), multiple tilesets per map. | M |
| 4.8 | **3D:** glTF model import, textures on meshes, a third-person controller. Depth sorting stays limited until Flutter supports a GPU depth buffer on all targets (see earlier investigation). | L |
| 4.9 | **AI assistant** (separate plan: [ai-assistant.md](ai-assistant.md)). | L |

## Phase 5: Commercial launch (after choosing the sales model)

| If you choose | Extra work |
|---|---|
| One-time purchase (itch.io / Steam / Gumroad) | Store page, trailer, screenshots; an editor installer; optionally a licence key checked offline (signed key, no server). Steam needs its SDK only for achievements and cloud saves, which aren't required for an engine. |
| Free + Pro | Decide what is Pro (e.g. Android/web export, premium templates, the AI assistant). Offline-verifiable licence key; clear "Pro" badges, never hiding the user's own work behind a paywall. |
| Subscription | Account system, payment provider (Stripe/Paddle), online licence check with an offline grace period, billing and cancellation pages. The most work; usually needs a backend developer. |

Needed in every case:
- An **EULA** for the editor, and a clear statement that games made with Ember belong to their creators.
- A **licence for exported games** (royalty-free, or a revenue threshold).
- A website with docs, a support email or Discord, a privacy policy (even "we collect nothing" must be stated), and refund terms.
- Pricing research against similar tools (GDevelop, Construct, GameMaker, Godot as the free baseline).

## Ongoing (every phase)
- Keep the test suite green; add a test for every bug fixed.
- Performance budgets: editor stays at 60 FPS with 1,000 2D entities; export sizes tracked.
- A changelog shown in the editor ("What's new").
- Back up the repository (the two local commits and all current work are not pushed yet).

## Suggested order
Phase 1 first, because it decides whether a first impression survives. Then Phase 2 (what
customers pay for: shipping games), then 3, then 4. Decide the sales model during Phase 2, so
Phase 5 can start right after.

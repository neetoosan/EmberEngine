import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/event_bus.dart';
import '../../core/scene.dart';
import '../../core/scene_serializer.dart';
import '../../core/game_script.dart';
import '../../core/transform2d.dart';
import '../../core/transform3d.dart';
import '../../subsystems/three_d/camera3d.dart';
import '../../subsystems/three_d/components3d.dart';
import '../../subsystems/three_d/lighting.dart';
import '../../subsystems/three_d/material.dart';
import '../../subsystems/two_d/flame_components.dart';
import '../../subsystems/audio/audio_system.dart';
import '../../subsystems/audio/audio_component.dart';
import '../../subsystems/physics/character_controller3d.dart';
import '../../subsystems/physics/character_controller2d.dart';
import '../../subsystems/particles/particle_system.dart';
import '../theme/ember_theme.dart';

/// Single executable command in the spotlight palette.
class PaletteCommand {
  final String title;
  final String category;
  final IconData icon;
  final String? shortcut;
  final VoidCallback onExecute;

  const PaletteCommand({
    required this.title,
    required this.category,
    required this.icon,
    this.shortcut,
    required this.onExecute,
  });
}

/// Spotlight-style Command Palette dialog (`Ctrl/Cmd + K`).
///
/// Gives instant access to all engine tools, entity creation, view modes,
/// and panel toggles in under 2 seconds.
class CommandPaletteDialog extends StatefulWidget {
  final EmberEngine engine;
  final VoidCallback onToggleHierarchy;
  final VoidCallback onToggleInspector;
  final VoidCallback onToggleBottomDrawer;
  final VoidCallback onToggleZenMode;

  const CommandPaletteDialog({
    super.key,
    required this.engine,
    required this.onToggleHierarchy,
    required this.onToggleInspector,
    required this.onToggleBottomDrawer,
    required this.onToggleZenMode,
  });

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _selectedIndex = 0;
  late List<PaletteCommand> _allCommands;

  @override
  void initState() {
    super.initState();
    _buildCommandsList();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _buildCommandsList() {
    _allCommands = [
      // Mode Switching
      PaletteCommand(
        title: 'Switch to 2D Mode (Flame)',
        category: 'Mode',
        icon: Icons.grid_on,
        shortcut: '2',
        onExecute: () => widget.engine.setMode(EngineMode.twoD),
      ),
      PaletteCommand(
        title: 'Switch to 3D Mode (Native)',
        category: 'Mode',
        icon: Icons.view_in_ar,
        shortcut: '3',
        onExecute: () => widget.engine.setMode(EngineMode.threeD),
      ),

      // Simulation Controls
      PaletteCommand(
        title: 'Play Scene Simulation',
        category: 'Simulation',
        icon: Icons.play_arrow,
        onExecute: () => widget.engine.play(),
      ),
      PaletteCommand(
        title: 'Pause Scene Simulation',
        category: 'Simulation',
        icon: Icons.pause,
        onExecute: () => widget.engine.pause(),
      ),
      PaletteCommand(
        title: 'Step 1 Simulation Frame',
        category: 'Simulation',
        icon: Icons.skip_next,
        onExecute: () => widget.engine.step(),
      ),
      PaletteCommand(
        title: 'Stop & Restore Scene State',
        category: 'Simulation',
        icon: Icons.stop,
        onExecute: () => widget.engine.stop(),
      ),

      // Prefab Spawning
      PaletteCommand(
        title: 'Spawn 3D FPS Player (Capsule + Camera + Audio)',
        category: 'Prefabs',
        icon: Icons.person_pin_circle_outlined,
        onExecute: () {
          final p = EmberEntity(name: 'FPS Player');
          p.addComponent(Transform3DComponent(position: vm.Vector3(0, 1.8, 5)));
          p.addComponent(CameraComponent());
          p.addComponent(CharacterController3DComponent());
          p.addComponent(ScriptComponent(scriptName: 'FPSPlayerController'));
          p.addComponent(AudioSourceComponent(clip: 'laser', is3D: true));
          widget.engine.activeScene.addEntity(p);
          widget.engine.selectEntity(p);
        },
      ),
      PaletteCommand(
        title: 'Spawn 2D Platformer Character (Sprite + Coyote Jump + Audio)',
        category: 'Prefabs',
        icon: Icons.directions_run,
        onExecute: () {
          final p = EmberEntity(name: 'Platformer Player');
          p.addComponent(Transform2DComponent(position: vm.Vector2(100, 200), size: vm.Vector2(48, 48)));
          p.addComponent(FlameSpriteComponent());
          p.addComponent(FlameHitbox2DComponent(shape: Hitbox2DShape.rectangle));
          p.addComponent(CharacterController2DComponent());
          p.addComponent(ScriptComponent(scriptName: 'Platformer2DController'));
          p.addComponent(ParticleEmitter2DComponent(preset: ParticlePreset.sparkBurst));
          p.addComponent(AudioSourceComponent(clip: 'jump', is3D: false));
          widget.engine.activeScene.addEntity(p);
          widget.engine.selectEntity(p);
        },
      ),

      // Entity Spawning (3D)
      PaletteCommand(
        title: 'Create 3D Dynamic Physics Cube',
        category: '3D Objects',
        icon: Icons.view_in_ar_outlined,
        onExecute: () {
          final e = EmberEntity(name: 'Physics Cube');
          e.addComponent(Transform3DComponent(position: vm.Vector3(0, 4, 0)));
          e.addComponent(MeshRenderer3DComponent(primitiveType: MeshPrimitiveType.cube));
          e.addComponent(Collider3DComponent(size: vm.Vector3(1, 1, 1)));
          e.addComponent(RigidBody3DComponent(mass: 2.0));
          widget.engine.activeScene.addEntity(e);
          widget.engine.selectEntity(e);
        },
      ),
      PaletteCommand(
        title: 'Create 3D Fire Particle Emitter',
        category: '3D Objects',
        icon: Icons.local_fire_department,
        onExecute: () {
          final e = EmberEntity(name: '3D Fire FX');
          e.addComponent(Transform3DComponent(position: vm.Vector3(0, 1, 0)));
          e.addComponent(ParticleEmitter3DComponent(preset: ParticlePreset.emberFire));
          widget.engine.activeScene.addEntity(e);
          widget.engine.selectEntity(e);
        },
      ),
      PaletteCommand(
        title: 'Create 3D Cube',
        category: '3D Objects',
        icon: Icons.crop_square,
        onExecute: () {
          final e = EmberEntity(name: 'Cube');
          e.addComponent(Transform3DComponent(position: vm.Vector3(0, 1, 0)));
          e.addComponent(MeshRenderer3DComponent(primitiveType: MeshPrimitiveType.cube));
          widget.engine.activeScene.addEntity(e);
          widget.engine.selectEntity(e);
        },
      ),
      PaletteCommand(
        title: 'Create 3D Sphere',
        category: '3D Objects',
        icon: Icons.circle_outlined,
        onExecute: () {
          final e = EmberEntity(name: 'Sphere');
          e.addComponent(Transform3DComponent(position: vm.Vector3(0, 1, 0)));
          e.addComponent(MeshRenderer3DComponent(
            primitiveType: MeshPrimitiveType.sphere,
            material: Material3D(color: const Color(0xFF10B981)),
          ));
          widget.engine.activeScene.addEntity(e);
          widget.engine.selectEntity(e);
        },
      ),
      PaletteCommand(
        title: 'Create 3D Directional Light',
        category: '3D Objects',
        icon: Icons.wb_sunny_outlined,
        onExecute: () {
          final e = EmberEntity(name: 'Directional Light');
          e.addComponent(Transform3DComponent(position: vm.Vector3(5, 10, 5), euler: vm.Vector3(-50, -30, 0)));
          e.addComponent(LightComponent(type: LightType.directional, intensity: 1.5));
          widget.engine.activeScene.addEntity(e);
          widget.engine.selectEntity(e);
        },
      ),
      PaletteCommand(
        title: 'Create Camera',
        category: '3D Objects',
        icon: Icons.videocam_outlined,
        onExecute: () {
          final e = EmberEntity(name: 'Camera');
          e.addComponent(Transform3DComponent(position: vm.Vector3(0, 3, 7)));
          e.addComponent(CameraComponent());
          widget.engine.activeScene.addEntity(e);
          widget.engine.selectEntity(e);
        },
      ),

      // Entity Spawning (2D Flame)
      PaletteCommand(
        title: 'Create 2D Sprite Component',
        category: '2D Flame',
        icon: Icons.image_outlined,
        onExecute: () {
          final e = EmberEntity(name: 'Sprite Entity');
          e.addComponent(Transform2DComponent(position: vm.Vector2(200, 200), size: vm.Vector2(48, 48)));
          e.addComponent(FlameSpriteComponent());
          widget.engine.activeScene.addEntity(e);
          widget.engine.selectEntity(e);
        },
      ),
      PaletteCommand(
        title: 'Create 2D Tilemap',
        category: '2D Flame',
        icon: Icons.grid_view_rounded,
        onExecute: () {
          final e = EmberEntity(name: 'Tilemap');
          e.addComponent(Transform2DComponent(size: vm.Vector2(512, 384)));
          e.addComponent(FlameTileMapComponent(columns: 16, rows: 12));
          widget.engine.activeScene.addEntity(e);
          widget.engine.selectEntity(e);
        },
      ),
      PaletteCommand(
        title: 'Create 2D Spark Particle FX',
        category: '2D Flame',
        icon: Icons.auto_awesome,
        onExecute: () {
          final e = EmberEntity(name: '2D Sparks');
          e.addComponent(Transform2DComponent(position: vm.Vector2(250, 250)));
          e.addComponent(ParticleEmitter2DComponent(preset: ParticlePreset.sparkBurst));
          widget.engine.activeScene.addEntity(e);
          widget.engine.selectEntity(e);
        },
      ),

      // Audio Synthesizer Testing
      PaletteCommand(
        title: 'Play Laser Synth SFX',
        category: 'Audio Synth',
        icon: Icons.volume_up,
        onExecute: () => AudioSystem.instance.play(clip: 'laser'),
      ),
      PaletteCommand(
        title: 'Play Jump Synth SFX',
        category: 'Audio Synth',
        icon: Icons.volume_up,
        onExecute: () => AudioSystem.instance.play(clip: 'jump'),
      ),
      PaletteCommand(
        title: 'Play Explosion Synth SFX',
        category: 'Audio Synth',
        icon: Icons.volume_up,
        onExecute: () => AudioSystem.instance.play(clip: 'explosion'),
      ),
      PaletteCommand(
        title: 'Play Coin Pickup Synth SFX',
        category: 'Audio Synth',
        icon: Icons.volume_up,
        onExecute: () => AudioSystem.instance.play(clip: 'coin'),
      ),

      // Gizmo Tools
      PaletteCommand(
        title: 'Select Translate Gizmo',
        category: 'Gizmo',
        icon: Icons.open_with,
        shortcut: 'W',
        onExecute: () => widget.engine.setGizmo(GizmoType.translate),
      ),
      PaletteCommand(
        title: 'Select Rotate Gizmo',
        category: 'Gizmo',
        icon: Icons.rotate_right,
        shortcut: 'E',
        onExecute: () => widget.engine.setGizmo(GizmoType.rotate),
      ),
      PaletteCommand(
        title: 'Select Scale Gizmo',
        category: 'Gizmo',
        icon: Icons.aspect_ratio,
        shortcut: 'R',
        onExecute: () => widget.engine.setGizmo(GizmoType.scale),
      ),

      // Serialization & Scenes
      PaletteCommand(
        title: 'Save Active Scene to JSON Log',
        category: 'Serialization',
        icon: Icons.save_alt,
        shortcut: 'Ctrl+S',
        onExecute: () {
          final jsonStr = SceneSerializer.saveSceneToJson(widget.engine.activeScene);
          widget.engine.log('Scene serialized (${jsonStr.length} chars)', source: 'Serializer');
        },
      ),
      PaletteCommand(
        title: 'Load Default 3D Scene (FPS & Solar)',
        category: 'Scenes',
        icon: Icons.refresh,
        onExecute: () => widget.engine.loadScene(EmberScene.createDefault3DScene()),
      ),
      PaletteCommand(
        title: 'Load Default 2D Scene (Platformer & Tilemap)',
        category: 'Scenes',
        icon: Icons.refresh,
        onExecute: () => widget.engine.loadScene(EmberScene.createDefault2DScene()),
      ),

      // Panel Toggles
      PaletteCommand(
        title: 'Toggle Hierarchy Shelf',
        category: 'Panels',
        icon: Icons.account_tree_outlined,
        shortcut: 'Ctrl+B',
        onExecute: widget.onToggleHierarchy,
      ),
      PaletteCommand(
        title: 'Toggle Inspector Shelf',
        category: 'Panels',
        icon: Icons.tune,
        shortcut: 'Ctrl+I',
        onExecute: widget.onToggleInspector,
      ),
      PaletteCommand(
        title: 'Toggle Console / Asset Drawer',
        category: 'Panels',
        icon: Icons.terminal,
        shortcut: '~',
        onExecute: widget.onToggleBottomDrawer,
      ),
      PaletteCommand(
        title: 'Toggle Zen / Fullscreen Canvas',
        category: 'Panels',
        icon: Icons.fullscreen,
        shortcut: 'Tab',
        onExecute: widget.onToggleZenMode,
      ),
    ];
  }

  List<PaletteCommand> get _filteredCommands {
    final q = _queryController.text.trim().toLowerCase();
    if (q.isEmpty) return _allCommands;
    return _allCommands.where((c) {
      return c.title.toLowerCase().contains(q) || c.category.toLowerCase().contains(q);
    }).toList();
  }

  void _executeSelected() {
    final list = _filteredCommands;
    if (list.isEmpty) return;
    final index = _selectedIndex.clamp(0, list.length - 1);
    Navigator.of(context).pop();
    list[index].onExecute();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final list = _filteredCommands;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (list.isNotEmpty) {
        setState(() => _selectedIndex = (_selectedIndex + 1) % list.length);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (list.isNotEmpty) {
        setState(() => _selectedIndex = (_selectedIndex - 1 + list.length) % list.length);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      _executeSelected();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCommands;
    if (_selectedIndex >= filtered.length) {
      _selectedIndex = 0;
    }

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 520,
            constraints: const BoxConstraints(maxHeight: 380),
            decoration: BoxDecoration(
              color: EmberTheme.surfacePanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EmberTheme.borderHighlight, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search Input Header
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: EmberTheme.borderMedium, width: 1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 18, color: EmberTheme.accentEmber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _queryController,
                          style: const TextStyle(fontSize: 13, color: EmberTheme.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Type a command or action...',
                            hintStyle: TextStyle(fontSize: 13, color: EmberTheme.textMuted),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() => _selectedIndex = 0),
                          onSubmitted: (_) => _executeSelected(),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: EmberTheme.surfaceCard,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'ESC to close',
                            style: TextStyle(fontSize: 9, color: EmberTheme.textMuted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Commands Results List
                Flexible(
                  child: filtered.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No matching actions found',
                            style: TextStyle(color: EmberTheme.textMuted, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final cmd = filtered[index];
                            final isSelected = index == _selectedIndex;

                            return InkWell(
                              onTap: () {
                                Navigator.of(context).pop();
                                cmd.onExecute();
                              },
                              child: Container(
                                height: 32,
                                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? EmberTheme.accentEmber.withValues(alpha: 0.2) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                  border: isSelected ? Border.all(color: EmberTheme.accentEmber.withValues(alpha: 0.6)) : null,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      cmd.icon,
                                      size: 14,
                                      color: isSelected ? EmberTheme.accentEmber : EmberTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        cmd.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                          color: isSelected ? Colors.white : EmberTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: EmberTheme.surfaceCard,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        cmd.category,
                                        style: const TextStyle(fontSize: 9, color: EmberTheme.textMuted),
                                      ),
                                    ),
                                    if (cmd.shortcut != null) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: EmberTheme.surfaceCard,
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(color: EmberTheme.borderSubtle),
                                        ),
                                        child: Text(
                                          cmd.shortcut!,
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontFamily: 'monospace',
                                            color: EmberTheme.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

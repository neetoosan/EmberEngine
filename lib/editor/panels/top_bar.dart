import 'package:flutter/material.dart';
import '../../core/engine_loop.dart';
import '../../core/event_bus.dart';
import '../../core/scene_serializer.dart';
import '../theme/ember_theme.dart';
import '../ui_primitives/status_pill.dart';

/// 36px Minimalist Header Top Bar for Ember Engine.
///
/// Houses Logo, Scene Name, Transport Controls (Play/Pause/Step/Stop),
/// 2D/3D Mode Switcher, Gizmo Selectors (W, E, R), Save, Mobile Touch, Power Mode, and Performance Stats Pill.
class EditorTopBar extends StatelessWidget {
  final EmberEngine engine;
  final VoidCallback onOpenCommandPalette;
  final VoidCallback onToggleZenMode;
  final VoidCallback? onToggleVirtualJoystick;
  final bool showVirtualJoystick;
  final VoidCallback? onSaveScene;
  final VoidCallback? onOpenProjectHub;
  final VoidCallback? onOpenDoctor;
  final VoidCallback? onExportGame;

  /// Replaces the plain scene name (e.g. a menu to switch levels).
  final Widget? sceneSelector;

  /// Scene | Script switch.
  final Widget? workspaceSwitch;

  const EditorTopBar({
    super.key,
    required this.engine,
    required this.onOpenCommandPalette,
    required this.onToggleZenMode,
    this.onToggleVirtualJoystick,
    this.showVirtualJoystick = false,
    this.onSaveScene,
    this.onOpenProjectHub,
    this.onOpenDoctor,
    this.onExportGame,
    this.sceneSelector,
    this.workspaceSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final mode = engine.mode;
    final is2D = mode == EngineMode.twoD;
    final playState = engine.playState;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: EmberTheme.surfacePanel,
        border: Border(
          bottom: BorderSide(color: EmberTheme.borderMedium, width: 1),
        ),
      ),
      child: Row(
        children: [
          // 1. Logo & Engine Title
          InkWell(
            onTap: onOpenProjectHub,
            borderRadius: BorderRadius.circular(4),
            child: Tooltip(
              message: 'Project Hub / Switch Project',
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: is2D
                            ? [EmberTheme.accentFlame, const Color(0xFF00B4D8)]
                            : [EmberTheme.accentEmber, const Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.local_fire_department, size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'EMBER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(width: workspaceSwitch == null ? 12 : 8),
          Container(width: 1, height: 16, color: EmberTheme.borderMedium),
          SizedBox(width: workspaceSwitch == null ? 12 : 8),

          if (workspaceSwitch != null) ...[
            workspaceSwitch!,
            const SizedBox(width: 8),
          ],

          // 2. Active Scene (a scene/level menu when a project is open)
          // Flexible: on narrow windows the scene name shrinks instead of overflowing
          Flexible(
            // Most of the free space goes to the scene name, not the spacer after it
            flex: 6,
            child: sceneSelector ??
                Text(
                  engine.activeScene.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: EmberTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
          ),

          const Spacer(),

          // 3. Simulation Transport Controls (Play, Pause, Step, Stop)
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: EmberTheme.surfaceCard,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: EmberTheme.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Play / Pause
                _buildTransportBtn(
                  icon: playState == PlayState.playing ? Icons.pause : Icons.play_arrow,
                  tooltip: playState == PlayState.playing ? 'Pause Simulation' : 'Play Simulation',
                  color: playState == PlayState.playing ? EmberTheme.accentAmber : EmberTheme.accentGreen,
                  isActive: playState == PlayState.playing,
                  onPressed: () {
                    if (playState == PlayState.playing) {
                      engine.pause();
                    } else {
                      engine.play();
                    }
                  },
                ),

                // Step 1 frame
                _buildTransportBtn(
                  icon: Icons.skip_next,
                  tooltip: 'Step 1 Frame',
                  color: EmberTheme.textSecondary,
                  isActive: false,
                  onPressed: () => engine.step(),
                ),

                // Stop
                _buildTransportBtn(
                  icon: Icons.stop,
                  tooltip: 'Stop & Reset Scene',
                  color: playState != PlayState.stopped ? EmberTheme.accentRed : EmberTheme.textMuted,
                  isActive: playState != PlayState.stopped,
                  onPressed: playState != PlayState.stopped ? () => engine.stop() : null,
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // 4. Mode Switcher (2D Flame vs 3D Native)
          Container(
            height: 26,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: EmberTheme.surfaceCard,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: EmberTheme.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModeBtn(
                  label: '2D (Flame)',
                  isSelected: is2D,
                  accentColor: EmberTheme.accentFlame,
                  onPressed: () => engine.setMode(EngineMode.twoD),
                ),
                _buildModeBtn(
                  label: '3D Native',
                  isSelected: !is2D,
                  accentColor: EmberTheme.accentEmber,
                  onPressed: () => engine.setMode(EngineMode.threeD),
                ),
              ],
            ),
          ),

          // 5. Gizmo Selector (in 3D Mode)
          if (!is2D) ...[
            const SizedBox(width: 12),
            Container(
              height: 26,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: EmberTheme.surfaceCard,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: EmberTheme.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildGizmoBtn('W', Icons.open_with, GizmoType.translate, 'Translate (W)'),
                  _buildGizmoBtn('E', Icons.rotate_right, GizmoType.rotate, 'Rotate (E)'),
                  _buildGizmoBtn('R', Icons.aspect_ratio, GizmoType.scale, 'Scale (R)'),
                ],
              ),
            ),
          ],

          const Spacer(),

          // 6. Command Palette Button
          Tooltip(
            message: 'Command Palette (Ctrl+K)',
            child: InkWell(
              onTap: onOpenCommandPalette,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: EmberTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: EmberTheme.borderSubtle),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, size: 13, color: EmberTheme.textSecondary),
                    SizedBox(width: 4),
                    Text(
                      'Ctrl+K',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: EmberTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // 7. Save Project Button
          Tooltip(
            message: 'Save Project (Ctrl+S)',
            child: IconButton(
              icon: const Icon(Icons.save_outlined, size: 16, color: EmberTheme.textSecondary),
              onPressed: onSaveScene ?? () {
                final jsonStr = SceneSerializer.saveSceneToJson(engine.activeScene);
                engine.log('Saved Scene "${engine.activeScene.name}" (${jsonStr.length} chars)', source: 'Serializer');
              },
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              padding: EdgeInsets.zero,
            ),
          ),

          // 7b. Export standalone game
          if (onExportGame != null)
            Tooltip(
              message: 'Export Game (standalone build)',
              child: IconButton(
                icon: const Icon(Icons.ios_share, size: 15, color: EmberTheme.textSecondary),
                onPressed: onExportGame,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
              ),
            ),

          const SizedBox(width: 4),

          // 8. Virtual Touch Controls Toggle
          if (onToggleVirtualJoystick != null)
            Tooltip(
              message: showVirtualJoystick ? 'Hide Touch Controls' : 'Show Virtual Touch Controls',
              child: IconButton(
                icon: Icon(
                  Icons.sports_esports_outlined,
                  size: 16,
                  color: showVirtualJoystick ? EmberTheme.accentFlame : EmberTheme.textMuted,
                ),
                onPressed: onToggleVirtualJoystick,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
              ),
            ),

          const SizedBox(width: 4),

          // 9. Power Mode Toggle
          Tooltip(
            message: 'Power Mode: ${engine.powerMode.name} (Click to toggle)',
            child: InkWell(
              onTap: () {
                final nextMode = engine.powerMode == PowerMode.performance60
                    ? PowerMode.batterySaver30
                    : (engine.powerMode == PowerMode.batterySaver30 ? PowerMode.uncapped : PowerMode.performance60);
                engine.setPowerMode(nextMode);
              },
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: engine.powerMode == PowerMode.batterySaver30
                      ? EmberTheme.accentAmber.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Icon(
                  engine.powerMode == PowerMode.batterySaver30 ? Icons.battery_saver : Icons.bolt,
                  size: 15,
                  color: engine.powerMode == PowerMode.batterySaver30
                      ? EmberTheme.accentAmber
                      : EmberTheme.accentGreen,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // 10. Performance Status Pill
          StatusPill(
            fps: engine.fps,
            frameTimeMs: engine.frameTimeMs,
            modeName: is2D ? '2D' : '3D',
            entityCount: engine.entityCount,
            accentColor: is2D ? EmberTheme.accentFlame : EmberTheme.accentEmber,
          ),

          const SizedBox(width: 8),

          // 11. Zen / Fullscreen Mode Button
          Tooltip(
            message: 'Zen Mode (Tab)',
            child: IconButton(
              icon: const Icon(Icons.fullscreen, size: 16, color: EmberTheme.textSecondary),
              onPressed: onToggleZenMode,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              padding: EdgeInsets.zero,
            ),
          ),

          if (onOpenDoctor != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Ember Doctor & Build Diagnostics',
              child: IconButton(
                icon: const Icon(Icons.health_and_safety_outlined, size: 16, color: Colors.greenAccent),
                onPressed: onOpenDoctor,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
              ),
            ),
          ],

          if (onOpenProjectHub != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Project Hub',
              child: IconButton(
                icon: const Icon(Icons.home_outlined, size: 16, color: EmberTheme.textSecondary),
                onPressed: onOpenProjectHub,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransportBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    required bool isActive,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Icon(
            icon,
            size: 14,
            color: onPressed == null ? EmberTheme.textMuted : color,
          ),
        ),
      ),
    );
  }

  Widget _buildModeBtn({
    required String label,
    required bool isSelected,
    required Color accentColor,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: isSelected ? Border.all(color: accentColor, width: 1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? accentColor : EmberTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildGizmoBtn(String keyLabel, IconData icon, GizmoType gizmo, String tooltip) {
    final isSelected = engine.activeGizmo == gizmo;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => engine.setGizmo(gizmo),
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? EmberTheme.accentEmber : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: isSelected ? Colors.white : EmberTheme.textSecondary),
              const SizedBox(width: 3),
              Text(
                keyLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : EmberTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

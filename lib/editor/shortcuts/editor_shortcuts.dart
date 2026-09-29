import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/engine_loop.dart';
import '../../core/event_bus.dart';

/// Global keyboard accelerator handler for Ember Engine Desktop Editor.
class EditorShortcutsWrapper extends StatelessWidget {
  final EmberEngine engine;
  final Widget child;
  final VoidCallback onOpenCommandPalette;
  final VoidCallback onToggleHierarchy;
  final VoidCallback onToggleInspector;
  final VoidCallback onToggleBottomDrawer;
  final VoidCallback onToggleZenMode;
  final VoidCallback? onSave;

  const EditorShortcutsWrapper({
    super.key,
    required this.engine,
    required this.child,
    required this.onOpenCommandPalette,
    required this.onToggleHierarchy,
    required this.onToggleInspector,
    required this.onToggleBottomDrawer,
    required this.onToggleZenMode,
    this.onSave,
  });

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final key = event.logicalKey;
    final isRunning = engine.playState != PlayState.stopped;

    // Esc -> Stop simulation and restore the edited scene
    if (key == LogicalKeyboardKey.escape && isRunning) {
      engine.stop();
      return KeyEventResult.handled;
    }

    // Ctrl/Cmd + P -> Play / Pause
    if (isCtrlOrCmd && key == LogicalKeyboardKey.keyP) {
      engine.playState == PlayState.playing ? engine.pause() : engine.play();
      return KeyEventResult.handled;
    }

    // Ctrl/Cmd + S -> Save project
    if (isCtrlOrCmd && key == LogicalKeyboardKey.keyS && onSave != null) {
      onSave!();
      return KeyEventResult.handled;
    }

    // While the game runs, plain keys belong to gameplay (read through Input).
    if (isRunning && !isCtrlOrCmd) return KeyEventResult.ignored;

    // Ctrl/Cmd + K -> Command Palette
    if (isCtrlOrCmd && key == LogicalKeyboardKey.keyK) {
      onOpenCommandPalette();
      return KeyEventResult.handled;
    }

    // Ctrl/Cmd + B -> Toggle Hierarchy
    if (isCtrlOrCmd && key == LogicalKeyboardKey.keyB) {
      onToggleHierarchy();
      return KeyEventResult.handled;
    }

    // Ctrl/Cmd + I -> Toggle Inspector
    if (isCtrlOrCmd && key == LogicalKeyboardKey.keyI) {
      onToggleInspector();
      return KeyEventResult.handled;
    }

    // ` (Tilde) -> Toggle Bottom Drawer
    if (key == LogicalKeyboardKey.backquote || key == LogicalKeyboardKey.f12) {
      onToggleBottomDrawer();
      return KeyEventResult.handled;
    }

    // Tab or F11 -> Zen / Fullscreen mode
    if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.f11) {
      onToggleZenMode();
      return KeyEventResult.handled;
    }

    // Non-Ctrl shortcuts when not in a text field
    if (!isCtrlOrCmd) {
      // 2 -> Switch to 2D Mode
      if (key == LogicalKeyboardKey.digit2) {
        engine.setMode(EngineMode.twoD);
        return KeyEventResult.handled;
      }
      // 3 -> Switch to 3D Mode
      if (key == LogicalKeyboardKey.digit3) {
        engine.setMode(EngineMode.threeD);
        return KeyEventResult.handled;
      }

      // W, E, R -> Gizmo Selectors (in 3D mode)
      if (engine.mode == EngineMode.threeD) {
        if (key == LogicalKeyboardKey.keyW) {
          engine.setGizmo(GizmoType.translate);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyE) {
          engine.setGizmo(GizmoType.rotate);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyR) {
          engine.setGizmo(GizmoType.scale);
          return KeyEventResult.handled;
        }
      }

      // Delete / Backspace -> Delete Selected Entity
      if (key == LogicalKeyboardKey.delete) {
        final selected = engine.selectedEntity;
        if (selected != null) {
          engine.activeScene.removeEntity(selected);
          engine.selectEntity(null);
          return KeyEventResult.handled;
        }
      }
    } else {
      // Ctrl + D -> Duplicate Selected Entity
      if (key == LogicalKeyboardKey.keyD) {
        final selected = engine.selectedEntity;
        if (selected != null) {
          final copy = selected.clone();
          engine.activeScene.addEntity(copy);
          engine.selectEntity(copy);
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: child,
    );
  }
}

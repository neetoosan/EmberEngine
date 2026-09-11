import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/engine_loop.dart';
import '../../core/transform2d.dart';
import 'flame_game.dart';

/// Interactive Viewport Widget for the 2D Flame Subsystem.
///
/// Provides pan/zoom gestures, entity selection, drag-to-move,
/// pixel grid snap controls, and HUD overlays.
class FlameViewportWidget extends StatefulWidget {
  final EmberEngine engine;

  const FlameViewportWidget({super.key, required this.engine});

  @override
  State<FlameViewportWidget> createState() => _FlameViewportWidgetState();
}

class _FlameViewportWidgetState extends State<FlameViewportWidget> {
  late EmberFlameGame _game;
  Offset? _lastPanPos;
  bool _isDraggingEntity = false;
  vm.Vector2 _dragStartEntityPos = vm.Vector2.zero();
  vm.Vector2 _dragStartWorldPos = vm.Vector2.zero();
  Offset _mousePos = Offset.zero;

  @override
  void initState() {
    super.initState();
    _game = EmberFlameGame(engine: widget.engine);
    widget.engine.addListener(_onEngineChange);
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngineChange);
    super.dispose();
  }

  void _onEngineChange() {
    if (mounted) setState(() {});
  }

  void _handlePointerDown(PointerDownEvent event) {
    _lastPanPos = event.localPosition;

    if (event.buttons == kPrimaryMouseButton) {
      final picked = _game.pickEntity(event.localPosition);
      widget.engine.selectEntity(picked);

      if (picked != null) {
        final t2d = picked.getComponent<Transform2DComponent>();
        if (t2d != null) {
          _isDraggingEntity = true;
          _dragStartEntityPos = t2d.position.clone();
          _dragStartWorldPos = _game.screenToWorld(event.localPosition);
        }
      } else {
        _isDraggingEntity = false;
      }
      setState(() {});
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _mousePos = event.localPosition;

    if (_isDraggingEntity && widget.engine.selectedEntity != null) {
      final t2d = widget.engine.selectedEntity!.getComponent<Transform2DComponent>();
      if (t2d != null) {
        final currentWorld = _game.screenToWorld(event.localPosition);
        final delta = currentWorld - _dragStartWorldPos;
        var newPos = _dragStartEntityPos + delta;

        // Snap to grid if enabled or Shift is held
        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
        if (isShiftPressed || _game.showGrid) {
          final snap = _game.gridSnap;
          newPos = vm.Vector2(
            (newPos.x / snap).round() * snap,
            (newPos.y / snap).round() * snap,
          );
        }
        t2d.position = newPos;
        setState(() {});
        return;
      }
    }

    // Pan camera if middle button, secondary button, or Space is held
    final isSpacePressed = HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);
    if (event.buttons == kMiddleMouseButton ||
        event.buttons == kSecondaryMouseButton ||
        (event.buttons == kPrimaryMouseButton && isSpacePressed)) {
      if (_lastPanPos != null) {
        final delta = event.localPosition - _lastPanPos!;
        _game.panOffset += vm.Vector2(delta.dx, delta.dy);
        setState(() {});
      }
    }
    _lastPanPos = event.localPosition;
    setState(() {});
  }

  void _handlePointerUp(PointerUpEvent event) {
    _isDraggingEntity = false;
    _lastPanPos = null;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final zoomFactor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
      _game.zoom = (_game.zoom * zoomFactor).clamp(0.1, 8.0);
      setState(() {});
    }
  }

  void _focusSelected() {
    final selected = widget.engine.selectedEntity;
    if (selected == null) return;
    final t2d = selected.getComponent<Transform2DComponent>();
    if (t2d == null) return;

    _game.panOffset = vm.Vector2(-t2d.worldPosition.x * _game.zoom, -t2d.worldPosition.y * _game.zoom);
    setState(() {});
  }

  void _resetCamera() {
    _game.panOffset = vm.Vector2.zero();
    _game.zoom = 1.0;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final worldMouse = _game.screenToWorld(_mousePos);

    return Stack(
      children: [
        // 1. Flame Game Surface
        Positioned.fill(
          child: Listener(
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerUp,
            onPointerSignal: _handlePointerSignal,
            child: GameWidget(game: _game),
          ),
        ),

        // 2. Top-Left Floating Controls HUD
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF18191E).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2C2E38)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Zoom Readout
                Text(
                  '${(_game.zoom * 100).toInt()}%',
                  style: const TextStyle(
                    color: Color(0xFF00F5D4),
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 14, color: const Color(0xFF2C2E38)),
                const SizedBox(width: 8),

                // Grid Snap Selector
                const Text(
                  'Snap:',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                const SizedBox(width: 4),
                DropdownButtonHideUnderline(
                  child: DropdownButton<double>(
                    value: _game.gridSnap,
                    dropdownColor: const Color(0xFF22242B),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 8.0, child: Text('8px')),
                      DropdownMenuItem(value: 16.0, child: Text('16px')),
                      DropdownMenuItem(value: 32.0, child: Text('32px')),
                      DropdownMenuItem(value: 64.0, child: Text('64px')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _game.gridSnap = val);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 14, color: const Color(0xFF2C2E38)),
                const SizedBox(width: 4),

                // Grid Toggle
                IconButton(
                  icon: Icon(
                    _game.showGrid ? Icons.grid_on : Icons.grid_off,
                    size: 14,
                    color: _game.showGrid ? const Color(0xFF00F5D4) : const Color(0xFF64748B),
                  ),
                  tooltip: 'Toggle Grid',
                  onPressed: () => setState(() => _game.showGrid = !_game.showGrid),
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  padding: EdgeInsets.zero,
                ),

                // Hitbox Toggle
                IconButton(
                  icon: Icon(
                    _game.showHitboxes ? Icons.check_box_outline_blank : Icons.check_box_outline_blank_outlined,
                    size: 14,
                    color: _game.showHitboxes ? const Color(0xFF22C55E) : const Color(0xFF64748B),
                  ),
                  tooltip: 'Toggle Hitboxes',
                  onPressed: () => setState(() => _game.showHitboxes = !_game.showHitboxes),
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  padding: EdgeInsets.zero,
                ),

                // Focus on selected (F)
                IconButton(
                  icon: const Icon(Icons.center_focus_strong, size: 14, color: Color(0xFF94A3B8)),
                  tooltip: 'Focus Selected (F)',
                  onPressed: _focusSelected,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  padding: EdgeInsets.zero,
                ),

                // Reset Camera
                IconButton(
                  icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF94A3B8)),
                  tooltip: 'Reset Viewport',
                  onPressed: _resetCamera,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),

        // 3. Bottom-Right Cursor Coordinates HUD
        Positioned(
          bottom: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF18191E).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF2C2E38)),
            ),
            child: Text(
              'X: ${worldMouse.x.round()}  Y: ${worldMouse.y.round()}',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

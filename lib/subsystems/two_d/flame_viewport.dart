import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/assets.dart';
import '../../core/engine_loop.dart';
import '../../core/event_bus.dart';
import '../../core/input.dart';
import '../../core/transform2d.dart';
import '../../editor/tile_brush.dart';
import '../physics/character_controller2d.dart';
import 'camera2d.dart';
import 'flame_components.dart';
import 'tilemap_editor.dart';
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
    widget.engine.frame.addListener(_onEngineChange); // camera follow runs every frame
    EmberAssets.instance.addListener(_onEditorVisualChange); // images finishing loading
    TileBrush.instance.addListener(_onEditorVisualChange);
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngineChange);
    widget.engine.frame.removeListener(_onEngineChange);
    EmberAssets.instance.removeListener(_onEditorVisualChange);
    TileBrush.instance.removeListener(_onEditorVisualChange);
    super.dispose();
  }

  void _onEditorVisualChange() {
    if (mounted) setState(() {});
  }

  /// While editing, Flame's continuous game loop is paused and exactly one
  /// frame is drawn after each rebuild (edits, pan/zoom, brush moves, image
  /// loads) instead of repainting 60 times a second. Playing resumes the loop.
  void _syncRenderLoop() {
    final running = widget.engine.playState != PlayState.stopped;
    if (running) {
      if (_game.paused) _game.resumeEngine();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.engine.playState != PlayState.stopped) return;
      if (!_game.paused) _game.pauseEngine();
      _game.stepEngine();
    });
  }

  /// The scene the editor view was last framed for.
  Object? _framedScene;

  /// When a new scene with a Camera 2D is shown in the editor, centre and zoom
  /// the view on what the game camera will see.
  void _frameCameraIfNewScene() {
    final scene = widget.engine.activeScene;
    if (identical(scene, _framedScene) || !_game.hasLayout) return;
    if (widget.engine.playState != PlayState.stopped) return;
    _framedScene = scene;
    final cam = Camera2DComponent.findIn(scene);
    if (cam == null || cam.designWidth <= 0 || cam.designHeight <= 0) return;
    final fit = 0.9 * [_game.size.x / cam.designWidth, _game.size.y / cam.designHeight].reduce((a, b) => a < b ? a : b);
    _game.zoom = fit.clamp(0.1, 8.0);
    _game.panOffset = vm.Vector2(-cam.position.x * _game.zoom, -cam.position.y * _game.zoom);
  }

  void _onEngineChange() {
    _frameCameraIfNewScene();
    if (widget.engine.playState == PlayState.playing &&
        Camera2DComponent.findIn(widget.engine.activeScene) == null) {
      _followPlayer();
    }
    if (mounted) setState(() {});
  }

  bool get _isRunning => widget.engine.playState != PlayState.stopped;

  void _forwardGamePointer(PointerEvent event) {
    Input.onMouseMove(
      vm.Vector2(event.localPosition.dx, event.localPosition.dy),
      vm.Vector2(event.delta.dx, event.delta.dy),
    );
    Input.instance.mouseWorldPosition = _game.screenToWorld(event.localPosition);
  }

  static int _buttonIndex(int buttons) {
    if (buttons & kSecondaryMouseButton != 0) return 2;
    if (buttons & kMiddleMouseButton != 0) return 1;
    return 0;
  }

  /// Keeps the camera centred on the player character while the game runs.
  void _followPlayer() {
    for (final e in widget.engine.activeScene.allEntities) {
      if (!e.enabled || !e.hasComponent<CharacterController2DComponent>()) continue;
      final t2d = e.getComponent<Transform2DComponent>();
      if (t2d == null) return;
      final target = vm.Vector2(-t2d.worldPosition.x * _game.zoom, -t2d.worldPosition.y * _game.zoom);
      _game.panOffset += (target - _game.panOffset) * 0.15;
      return;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _lastPanPos = event.localPosition;
    if (_isRunning) {
      // Clicks and touches are gameplay input while the game runs
      _forwardGamePointer(event);
      Input.onMouseDown(_buttonIndex(event.buttons));
      return;
    }

    // Tile painting: left paints, right erases (middle still pans)
    if (TileBrush.instance.enabled &&
        (event.buttons == kPrimaryMouseButton || event.buttons == kSecondaryMouseButton) &&
        tilemapTarget(widget.engine) != null) {
      _paintErase = event.buttons == kSecondaryMouseButton;
      _isPainting = true;
      _paintAt(event.localPosition);
      return;
    }

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
    if (_isRunning) {
      _forwardGamePointer(event);
      return;
    }

    if (_isPainting) {
      _paintAt(event.localPosition);
      return;
    }

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
    // PointerUp carries the buttons still held, not the released one: release all.
    for (final b in const [0, 1, 2]) {
      Input.onMouseUp(b);
    }
    _isDraggingEntity = false;
    _isPainting = false;
    _lastPanPos = null;
  }

  void _handlePointerHover(PointerHoverEvent event) {
    if (_isRunning) {
      _forwardGamePointer(event);
      return;
    }
    _updateBrushPreview(event.localPosition);
  }

  // --- Tile painting ---

  bool _isPainting = false;
  bool _paintErase = false;

  /// The tilemap cell under [screen], with its map.
  (FlameTileMapComponent, int, int)? _cellUnder(Offset screen) {
    final map = tilemapTarget(widget.engine)?.getComponent<FlameTileMapComponent>();
    if (map == null) return null;
    final w = _game.screenToWorld(screen);
    final cell = map.cellAt(w.x, w.y);
    return cell == null ? null : (map, cell.$1, cell.$2);
  }

  void _paintAt(Offset screen) {
    final hit = _cellUnder(screen);
    if (hit == null) return;
    final (map, c, r) = hit;
    map.setTile(c, r, _paintErase ? 0 : TileBrush.instance.tileId);
    _updateBrushPreview(screen);
  }

  void _updateBrushPreview(Offset screen) {
    Rect? rect;
    if (TileBrush.instance.enabled) {
      final hit = _cellUnder(screen);
      if (hit != null) rect = hit.$1.cellRect(hit.$2, hit.$3);
    }
    if (rect != _game.brushRect) setState(() => _game.brushRect = rect);
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
    _syncRenderLoop();
    final worldMouse = _game.screenToWorld(_mousePos);
    if (!identical(widget.engine.activeScene, _framedScene)) {
      // The game view only has a size after layout; frame the camera then.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final before = _framedScene;
        _frameCameraIfNewScene();
        if (!identical(before, _framedScene)) setState(() {});
      });
    }

    return Stack(
      children: [
        // 1. Flame Game Surface
        Positioned.fill(
          child: Listener(
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerHover: _handlePointerHover,
            onPointerUp: _handlePointerUp,
            onPointerSignal: _handlePointerSignal,
            child: GameWidget(game: _game),
          ),
        ),

        if (widget.engine.playState == PlayState.stopped) ...[

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
      ],
    );
  }
}

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/event_bus.dart';
import '../../core/input.dart';
import '../../core/transform3d.dart';
import '../physics/character_controller3d.dart';
import '../ui/ui_widgets.dart';
import 'camera3d.dart';
import 'components3d.dart';
import 'gizmos3d.dart';
import 'renderer3d.dart';

/// 3D Viewport Widget for Ember Engine.
///
/// Handles 3D camera navigation (orbit, pan, zoom), entity ray picking,
/// transform gizmo manipulation, and floating HUD overlays.
class Viewport3DWidget extends StatefulWidget {
  final EmberEngine engine;

  const Viewport3DWidget({super.key, required this.engine});

  @override
  State<Viewport3DWidget> createState() => _Viewport3DWidgetState();
}

class _Viewport3DWidgetState extends State<Viewport3DWidget> {
  final OrbitCameraController _cameraController = OrbitCameraController();
  final Gizmo3DHandler _gizmoHandler = Gizmo3DHandler();

  Offset? _lastMousePos;
  bool _isWireframe = false;
  bool _showGrid = true;
  Size _viewportSize = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.engine.addListener(_onEngineChanged);
    widget.engine.frame.addListener(_onEngineChanged); // the game view moves every frame
    _cameraController.azimuth = 0.6;
    _cameraController.elevation = 0.4;
    _cameraController.distance = 9.0;
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngineChanged);
    widget.engine.frame.removeListener(_onEngineChanged);
    super.dispose();
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  /// True while a simulation runs and the scene has a camera to look through.
  bool get _isGameView =>
      widget.engine.playState != PlayState.stopped && _findGameCamera() != null;

  /// The scene's main camera entity (first enabled camera marked main, else any).
  EmberEntity? _findGameCamera() {
    EmberEntity? fallback;
    for (final e in widget.engine.activeScene.allEntities) {
      if (!e.enabled) continue;
      final cam = e.getComponent<CameraComponent>();
      if (cam == null || !cam.enabled || !e.hasComponent<Transform3DComponent>()) continue;
      if (cam.isMainCamera) return e;
      fallback ??= e;
    }
    return fallback;
  }

  static int _buttonIndex(int buttons) {
    if (buttons & kSecondaryMouseButton != 0) return 2;
    if (buttons & kMiddleMouseButton != 0) return 1;
    return 0;
  }

  void _forwardGamePointer(PointerEvent event) {
    Input.onMouseMove(
      Vector2(event.localPosition.dx, event.localPosition.dy),
      Vector2(event.delta.dx, event.delta.dy),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _lastMousePos = event.localPosition;

    if (_isGameView) {
      Input.onMouseDown(_buttonIndex(event.buttons));
      return;
    }

    if (event.buttons == kPrimaryMouseButton) {
      final selected = widget.engine.selectedEntity;
      final camPos = _cameraController.getPosition();
      final camRot = _cameraController.getRotation();

      // 1. Check Gizmo Hit Test first
      if (selected != null) {
        final hitAxis = _gizmoHandler.hitTestGizmo(
          mouseScreen: event.localPosition,
          selected: selected,
          size: _viewportSize,
          cameraPosition: camPos,
          cameraRotation: camRot,
        );

        if (hitAxis != GizmoAxis.none) {
          _gizmoHandler.activeAxis = hitAxis;
          setState(() {});
          return;
        }
      }

      // 2. Raycast picking for entity selection
      final picked = _raycastPickEntity(event.localPosition);
      widget.engine.selectEntity(picked);
      setState(() {});
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_isGameView) {
      _forwardGamePointer(event);
      return;
    }
    if (_lastMousePos != null) {
      final delta = event.localPosition - _lastMousePos!;
      final isAltPressed = HardwareKeyboard.instance.isAltPressed;

      // Gizmo dragging
      if (_gizmoHandler.activeAxis != GizmoAxis.none) {
        _gizmoHandler.handleDrag(
          delta: delta,
          engine: widget.engine,
          cameraPosition: _cameraController.getPosition(),
          cameraRotation: _cameraController.getRotation(),
        );
        setState(() {});
      }
      // Camera Orbit (Right button or Alt + Left button)
      else if (event.buttons == kSecondaryMouseButton ||
          (event.buttons == kPrimaryMouseButton && isAltPressed)) {
        _cameraController.orbit(delta.dx, delta.dy);
        setState(() {});
      }
      // Camera Pan (Middle button or Space + Left button)
      else if (event.buttons == kMiddleMouseButton) {
        _cameraController.pan(delta.dx, delta.dy);
        setState(() {});
      }
    }
    _lastMousePos = event.localPosition;
  }

  void _handlePointerUp(PointerUpEvent event) {
    // Release every button; PointerUp carries the buttons still held, not the released one.
    for (final b in const [0, 1, 2]) {
      Input.onMouseUp(b);
    }
    _gizmoHandler.activeAxis = GizmoAxis.none;
    _lastMousePos = null;
    setState(() {});
  }

  void _handlePointerHover(PointerHoverEvent event) {
    if (_isGameView) _forwardGamePointer(event);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_isGameView) return;
    if (event is PointerScrollEvent) {
      final zoomFactor = event.scrollDelta.dy > 0 ? 1.1 : 0.9;
      _cameraController.zoom(zoomFactor);
      setState(() {});
    }
  }

  EmberEntity? _raycastPickEntity(Offset screenPos) {
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) return null;

    final camPos = _cameraController.getPosition();
    final camRot = _cameraController.getRotation();
    final camComp = CameraComponent();
    final ray = camComp.screenPointToRay(screenPos, _viewportSize, camPos, camRot);

    EmberEntity? closestEntity;
    double minDistance = double.infinity;

    for (final entity in widget.engine.activeScene.allEntities) {
      if (!entity.enabled) continue;
      final t3d = entity.getComponent<Transform3DComponent>();
      final mr = entity.getComponent<MeshRenderer3DComponent>();
      if (t3d == null || mr == null) continue;

      // Sphere intersection test against entity bounds
      final center = t3d.worldPosition;
      final radius = mr.mesh.bounds.radius * t3d.worldScale.length * 0.6;

      final toCenter = center - ray.origin;
      final tca = toCenter.dot(ray.direction);
      if (tca < 0) continue;

      final d2 = toCenter.dot(toCenter) - tca * tca;
      if (d2 > radius * radius) continue;

      final thc = math.sqrt(radius * radius - d2);
      final t0 = tca - thc;

      if (t0 < minDistance) {
        minDistance = t0;
        closestEntity = entity;
      }
    }

    return closestEntity;
  }

  void _focusSelected() {
    final selected = widget.engine.selectedEntity;
    if (selected == null) return;
    final t3d = selected.getComponent<Transform3DComponent>();
    if (t3d == null) return;

    _cameraController.focusOn(t3d.worldPosition);
    setState(() {});
  }

  void _resetCamera() {
    _cameraController.target = Vector3.zero();
    _cameraController.distance = 9.0;
    _cameraController.azimuth = 0.6;
    _cameraController.elevation = 0.4;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // While playing, look through the scene's own camera; otherwise use the editor orbit camera.
    final gameCam = widget.engine.playState != PlayState.stopped ? _findGameCamera() : null;
    final isGameView = gameCam != null;
    Vector3 camPos = _cameraController.getPosition();
    Quaternion camRot = _cameraController.getRotation();
    CameraComponent? camComp;
    if (gameCam != null) {
      final t = gameCam.getComponent<Transform3DComponent>()!;
      final cc = gameCam.getComponent<CharacterController3DComponent>();
      camPos = t.worldPosition + (cc?.eyeOffset ?? Vector3.zero());
      camRot = t.rotation;
      camComp = gameCam.getComponent<CameraComponent>();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            // 1. 3D Render Canvas
            Positioned.fill(
              child: MouseRegion(
                cursor: isGameView ? SystemMouseCursors.precise : MouseCursor.defer,
                child: Listener(
                  onPointerDown: _handlePointerDown,
                  onPointerMove: _handlePointerMove,
                  onPointerHover: _handlePointerHover,
                  onPointerUp: _handlePointerUp,
                  onPointerSignal: _handlePointerSignal,
                  child: CustomPaint(
                    size: _viewportSize,
                    painter: _Renderer3DPainter(
                      engine: widget.engine,
                      cameraPosition: camPos,
                      cameraRotation: camRot,
                      cameraComp: camComp,
                      gizmoHandler: _gizmoHandler,
                      wireframe: _isWireframe,
                      showGrid: _showGrid && !isGameView,
                      isGameView: isGameView,
                    ),
                  ),
                ),
              ),
            ),

            if (isGameView) ...[
              // Crosshair
              const Center(
                child: IgnorePointer(
                  child: Icon(Icons.add, size: 22, color: Color(0xCCFFFFFF)),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                child: IgnorePointer(
                  child: Text(
                    'WASD move · Mouse look · Click/F fire · Space jump · Shift sprint',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
            if (!isGameView) ...[

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
                    // View mode: Lit / Wireframe
                    InkWell(
                      onTap: () => setState(() => _isWireframe = !_isWireframe),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              _isWireframe ? Icons.blur_linear : Icons.wb_sunny_outlined,
                              size: 13,
                              color: const Color(0xFF6366F1),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isWireframe ? 'Wireframe' : 'Lit (PBR)',
                              style: const TextStyle(
                                color: Color(0xFFE2E8F0),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(width: 1, height: 14, color: const Color(0xFF2C2E38)),
                    const SizedBox(width: 6),

                    // Grid Toggle
                    IconButton(
                      icon: Icon(
                        _showGrid ? Icons.grid_on : Icons.grid_off,
                        size: 14,
                        color: _showGrid ? const Color(0xFF6366F1) : const Color(0xFF64748B),
                      ),
                      tooltip: 'Toggle 3D Grid',
                      onPressed: () => setState(() => _showGrid = !_showGrid),
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

            // 3. Top-Right Gizmo Selection Quick Pill
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF18191E).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF2C2E38)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildGizmoButton(GizmoType.translate, Icons.open_with, 'Translate (W)'),
                    _buildGizmoButton(GizmoType.rotate, Icons.rotate_right, 'Rotate (E)'),
                    _buildGizmoButton(GizmoType.scale, Icons.aspect_ratio, 'Scale (R)'),
                  ],
                ),
              ),
            ),

            // 4. Bottom-Right Camera Distance HUD
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
                  'Dist: ${_cameraController.distance.toStringAsFixed(1)}m',
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
      },
    );
  }

  Widget _buildGizmoButton(GizmoType type, IconData icon, String tooltip) {
    final isSelected = widget.engine.activeGizmo == type;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => widget.engine.setGizmo(type),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 14,
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}

class _Renderer3DPainter extends CustomPainter {
  final EmberEngine engine;
  final Vector3 cameraPosition;
  final Quaternion cameraRotation;
  final CameraComponent? cameraComp;
  final Gizmo3DHandler gizmoHandler;
  final bool wireframe;
  final bool showGrid;
  final bool isGameView;

  _Renderer3DPainter({
    required this.engine,
    required this.cameraPosition,
    required this.cameraRotation,
    this.cameraComp,
    required this.gizmoHandler,
    required this.wireframe,
    required this.showGrid,
    this.isGameView = false,
  }) : super(repaint: Listenable.merge([engine, engine.frame]));

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Clear Viewport Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF121316),
    );

    // 2. Render 3D Scene
    Renderer3D.renderScene(
      canvas: canvas,
      size: size,
      engine: engine,
      cameraPosition: cameraPosition,
      cameraRotation: cameraRotation,
      cameraComp: cameraComp,
      wireframeOverride: wireframe,
      showGrid: showGrid,
      showSelection: !isGameView,
    );

    // On-screen UI text (score, messages)
    UIRenderer.paintAll(canvas, Offset.zero & size, 1.0, engine.activeScene);

    // 3. Render 3D Transform Gizmo (editor view only)
    if (isGameView) return;
    gizmoHandler.renderGizmo(
      canvas: canvas,
      size: size,
      engine: engine,
      cameraPosition: cameraPosition,
      cameraRotation: cameraRotation,
    );
  }

  @override
  bool shouldRepaint(covariant _Renderer3DPainter oldDelegate) => true;
}

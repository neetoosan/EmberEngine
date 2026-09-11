import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import '../../core/engine_loop.dart';
import '../../core/event_bus.dart';
import '../../core/entity.dart';
import '../../core/transform3d.dart';
import 'camera3d.dart';

/// Active axis being manipulated by a 3D gizmo.
enum GizmoAxis {
  none,
  x,
  y,
  z,
  all,
}

/// Interactive 3D Transform Gizmo renderer and mouse interaction handler.
class Gizmo3DHandler {
  GizmoAxis activeAxis = GizmoAxis.none;
  Vector3? dragStartWorldPos;
  Vector3? dragStartEntityPos;
  Vector3? dragStartEntityScale;
  Vector3? dragStartEntityEuler;

  static const double handleLength = 1.6;
  static const double pickThreshold = 20.0; // pixels

  /// Renders the active transform gizmo (Translate, Rotate, Scale) over the selected entity.
  void renderGizmo({
    required Canvas canvas,
    required Size size,
    required EmberEngine engine,
    required Vector3 cameraPosition,
    required Quaternion cameraRotation,
    CameraComponent? cameraComp,
  }) {
    final selected = engine.selectedEntity;
    if (selected == null || engine.activeGizmo == GizmoType.none) return;

    final t3d = selected.getComponent<Transform3DComponent>();
    if (t3d == null) return;

    final origin = t3d.worldPosition;
    final camera = cameraComp ?? CameraComponent();
    final aspect = size.width / size.height;
    final viewProj = camera.getProjectionMatrix(aspect) * camera.getViewMatrix(cameraPosition, cameraRotation);

    // Dynamic scale so gizmo maintains constant size on screen regardless of camera distance
    final dist = (cameraPosition - origin).length;
    final scaleFactor = math.max(0.2, dist * 0.12);

    final originScreen = _project(origin, viewProj, size);
    if (originScreen == null) return;

    switch (engine.activeGizmo) {
      case GizmoType.translate:
        _renderTranslateGizmo(canvas, origin, originScreen, scaleFactor, viewProj, size);
        break;
      case GizmoType.rotate:
        _renderRotateGizmo(canvas, origin, scaleFactor, viewProj, size);
        break;
      case GizmoType.scale:
        _renderScaleGizmo(canvas, origin, originScreen, scaleFactor, viewProj, size);
        break;
      case GizmoType.none:
        break;
    }
  }

  void _renderTranslateGizmo(
    Canvas canvas,
    Vector3 origin,
    Offset originScreen,
    double scale,
    Matrix4 viewProj,
    Size size,
  ) {
    final xTip = origin + Vector3(handleLength * scale, 0, 0);
    final yTip = origin + Vector3(0, handleLength * scale, 0);
    final zTip = origin + Vector3(0, 0, handleLength * scale);

    final pX = _project(xTip, viewProj, size);
    final pY = _project(yTip, viewProj, size);
    final pZ = _project(zTip, viewProj, size);

    // X Axis (Red)
    if (pX != null) {
      _drawAxisLine(canvas, originScreen, pX, const Color(0xFFEF4444), activeAxis == GizmoAxis.x);
      _drawArrowHead(canvas, originScreen, pX, const Color(0xFFEF4444));
    }

    // Y Axis (Green)
    if (pY != null) {
      _drawAxisLine(canvas, originScreen, pY, const Color(0xFF22C55E), activeAxis == GizmoAxis.y);
      _drawArrowHead(canvas, originScreen, pY, const Color(0xFF22C55E));
    }

    // Z Axis (Blue)
    if (pZ != null) {
      _drawAxisLine(canvas, originScreen, pZ, const Color(0xFF3B82F6), activeAxis == GizmoAxis.z);
      _drawArrowHead(canvas, originScreen, pZ, const Color(0xFF3B82F6));
    }
  }

  void _renderRotateGizmo(Canvas canvas, Vector3 origin, double scale, Matrix4 viewProj, Size size) {
    const segments = 32;
    final r = handleLength * scale * 0.8;

    // X Ring (YZ plane, Red)
    _drawRing(canvas, origin, r, Vector3(1, 0, 0), const Color(0xFFEF4444), viewProj, size, segments, activeAxis == GizmoAxis.x);

    // Y Ring (XZ plane, Green)
    _drawRing(canvas, origin, r, Vector3(0, 1, 0), const Color(0xFF22C55E), viewProj, size, segments, activeAxis == GizmoAxis.y);

    // Z Ring (XY plane, Blue)
    _drawRing(canvas, origin, r, Vector3(0, 0, 1), const Color(0xFF3B82F6), viewProj, size, segments, activeAxis == GizmoAxis.z);
  }

  void _renderScaleGizmo(
    Canvas canvas,
    Vector3 origin,
    Offset originScreen,
    double scale,
    Matrix4 viewProj,
    Size size,
  ) {
    final xTip = origin + Vector3(handleLength * scale, 0, 0);
    final yTip = origin + Vector3(0, handleLength * scale, 0);
    final zTip = origin + Vector3(0, 0, handleLength * scale);

    final pX = _project(xTip, viewProj, size);
    final pY = _project(yTip, viewProj, size);
    final pZ = _project(zTip, viewProj, size);

    if (pX != null) {
      _drawAxisLine(canvas, originScreen, pX, const Color(0xFFEF4444), activeAxis == GizmoAxis.x);
      _drawCubeTip(canvas, pX, const Color(0xFFEF4444));
    }
    if (pY != null) {
      _drawAxisLine(canvas, originScreen, pY, const Color(0xFF22C55E), activeAxis == GizmoAxis.y);
      _drawCubeTip(canvas, pY, const Color(0xFF22C55E));
    }
    if (pZ != null) {
      _drawAxisLine(canvas, originScreen, pZ, const Color(0xFF3B82F6), activeAxis == GizmoAxis.z);
      _drawCubeTip(canvas, pZ, const Color(0xFF3B82F6));
    }
  }

  void _drawAxisLine(Canvas canvas, Offset p0, Offset p1, Color color, bool isActive) {
    final paint = Paint()
      ..color = isActive ? Colors.white : color
      ..strokeWidth = isActive ? 3.5 : 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p0, p1, paint);
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Color color) {
    final dir = (to - from);
    if (dir.distance == 0) return;
    final norm = Offset(dir.dx / dir.distance, dir.dy / dir.distance);
    final perp = Offset(-norm.dy, norm.dx);

    const length = 10.0;
    const width = 5.0;

    final path = Path()
      ..moveTo(to.dx + norm.dx * 3, to.dy + norm.dy * 3)
      ..lineTo(to.dx - norm.dx * length + perp.dx * width, to.dy - norm.dy * length + perp.dy * width)
      ..lineTo(to.dx - norm.dx * length - perp.dx * width, to.dy - norm.dy * length - perp.dy * width)
      ..close();

    final paint = Paint()..color = color;
    canvas.drawPath(path, paint);
  }

  void _drawCubeTip(Canvas canvas, Offset to, Color color) {
    const sz = 8.0;
    final rect = Rect.fromCenter(center: to, width: sz, height: sz);
    final paint = Paint()..color = color;
    canvas.drawRect(rect, paint);
  }

  void _drawRing(
    Canvas canvas,
    Vector3 center,
    double radius,
    Vector3 axis,
    Color color,
    Matrix4 viewProj,
    Size size,
    int segments,
    bool isActive,
  ) {
    final points = <Offset?>[];

    Vector3 u, v;
    if (axis.x.abs() > 0.5) {
      u = Vector3(0, 1, 0);
      v = Vector3(0, 0, 1);
    } else if (axis.y.abs() > 0.5) {
      u = Vector3(1, 0, 0);
      v = Vector3(0, 0, 1);
    } else {
      u = Vector3(1, 0, 0);
      v = Vector3(0, 1, 0);
    }

    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * math.pi;
      final p = center + u * (math.cos(angle) * radius) + v * (math.sin(angle) * radius);
      points.add(_project(p, viewProj, size));
    }

    final paint = Paint()
      ..color = isActive ? Colors.white : color.withValues(alpha: 0.9)
      ..strokeWidth = isActive ? 3.0 : 2.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      if (p0 != null && p1 != null) {
        canvas.drawLine(p0, p1, paint);
      }
    }
  }

  /// Hit-tests mouse screen point against gizmo axes.
  GizmoAxis hitTestGizmo({
    required Offset mouseScreen,
    required EmberEntity selected,
    required Size size,
    required Vector3 cameraPosition,
    required Quaternion cameraRotation,
    CameraComponent? cameraComp,
  }) {
    final t3d = selected.getComponent<Transform3DComponent>();
    if (t3d == null) return GizmoAxis.none;

    final origin = t3d.worldPosition;
    final camera = cameraComp ?? CameraComponent();
    final aspect = size.width / size.height;
    final viewProj = camera.getProjectionMatrix(aspect) * camera.getViewMatrix(cameraPosition, cameraRotation);

    final dist = (cameraPosition - origin).length;
    final scale = math.max(0.2, dist * 0.12);

    final p0 = _project(origin, viewProj, size);
    if (p0 == null) return GizmoAxis.none;

    final pX = _project(origin + Vector3(handleLength * scale, 0, 0), viewProj, size);
    final pY = _project(origin + Vector3(0, handleLength * scale, 0), viewProj, size);
    final pZ = _project(origin + Vector3(0, 0, handleLength * scale), viewProj, size);

    // Check distance to each axis segment
    if (pY != null && _distToSegment(mouseScreen, p0, pY) < pickThreshold) {
      return GizmoAxis.y;
    }
    if (pX != null && _distToSegment(mouseScreen, p0, pX) < pickThreshold) {
      return GizmoAxis.x;
    }
    if (pZ != null && _distToSegment(mouseScreen, p0, pZ) < pickThreshold) {
      return GizmoAxis.z;
    }

    return GizmoAxis.none;
  }

  /// Updates entity transform when dragging an active gizmo axis.
  void handleDrag({
    required Offset delta,
    required EmberEngine engine,
    required Vector3 cameraPosition,
    required Quaternion cameraRotation,
  }) {
    final selected = engine.selectedEntity;
    if (selected == null || activeAxis == GizmoAxis.none) return;

    final t3d = selected.getComponent<Transform3DComponent>();
    if (t3d == null) return;

    final sensitivity = 0.02;

    switch (engine.activeGizmo) {
      case GizmoType.translate:
        if (activeAxis == GizmoAxis.x) {
          t3d.position += Vector3(delta.dx * sensitivity, 0, 0);
        } else if (activeAxis == GizmoAxis.y) {
          t3d.position += Vector3(0, -delta.dy * sensitivity, 0);
        } else if (activeAxis == GizmoAxis.z) {
          t3d.position += Vector3(0, 0, delta.dy * sensitivity);
        }
        break;

      case GizmoType.rotate:
        final rotDelta = delta.dx * 1.5;
        if (activeAxis == GizmoAxis.y) {
          t3d.euler = t3d.euler + Vector3(0, rotDelta, 0);
        } else if (activeAxis == GizmoAxis.x) {
          t3d.euler = t3d.euler + Vector3(rotDelta, 0, 0);
        } else if (activeAxis == GizmoAxis.z) {
          t3d.euler = t3d.euler + Vector3(0, 0, rotDelta);
        }
        break;

      case GizmoType.scale:
        final scaleDelta = delta.dx * 0.02;
        if (activeAxis == GizmoAxis.x) {
          t3d.scale = Vector3(math.max(0.05, t3d.scale.x + scaleDelta), t3d.scale.y, t3d.scale.z);
        } else if (activeAxis == GizmoAxis.y) {
          t3d.scale = Vector3(t3d.scale.x, math.max(0.05, t3d.scale.y - delta.dy * 0.02), t3d.scale.z);
        } else if (activeAxis == GizmoAxis.z) {
          t3d.scale = Vector3(t3d.scale.x, t3d.scale.y, math.max(0.05, t3d.scale.z + scaleDelta));
        }
        break;

      case GizmoType.none:
        break;
    }
  }

  double _distToSegment(Offset p, Offset v, Offset w) {
    final l2 = (v - w).distanceSquared;
    if (l2 == 0) return (p - v).distance;
    final t = math.max(0.0, math.min(1.0, ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2));
    final projection = Offset(v.dx + t * (w.dx - v.dx), v.dy + t * (w.dy - v.dy));
    return (p - projection).distance;
  }

  Offset? _project(Vector3 point, Matrix4 viewProj, Size size) {
    final clip = viewProj * Vector4(point.x, point.y, point.z, 1.0);
    if (clip.w <= 0.05) return null;

    final invW = 1.0 / clip.w;
    final ndcX = clip.x * invW;
    final ndcY = clip.y * invW;

    final sx = (ndcX + 1.0) * 0.5 * size.width;
    final sy = (1.0 - ndcY) * 0.5 * size.height;
    return Offset(sx, sy);
  }
}

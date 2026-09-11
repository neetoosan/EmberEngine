import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/transform3d.dart';
import 'camera3d.dart';
import 'components3d.dart';
import 'lighting.dart';

/// Screen-space projected triangle ready for rasterization.
class ProjectedTriangle {
  final Offset p0;
  final Offset p1;
  final Offset p2;
  final double depth; // Distance to camera for depth sorting
  final Color color;
  final bool wireframe;
  final EmberEntity entity;

  ProjectedTriangle({
    required this.p0,
    required this.p1,
    required this.p2,
    required this.depth,
    required this.color,
    required this.wireframe,
    required this.entity,
  });
}

/// Real-time 3D Engine Renderer for Ember Engine.
///
/// Executes matrix transformation, perspective projection, backface culling,
/// Blinn-Phong lighting, depth sorting, and ground grid rendering on a Flutter Canvas.
class Renderer3D {
  static void renderScene({
    required Canvas canvas,
    required Size size,
    required EmberEngine engine,
    required Vector3 cameraPosition,
    required Quaternion cameraRotation,
    CameraComponent? cameraComp,
    bool wireframeOverride = false,
    bool showGrid = true,
  }) {
    if (size.width <= 0 || size.height <= 0) return;

    final camera = cameraComp ?? CameraComponent();
    final aspect = size.width / size.height;
    final viewMatrix = camera.getViewMatrix(cameraPosition, cameraRotation);
    final projMatrix = camera.getProjectionMatrix(aspect);
    final viewProjMatrix = projMatrix * viewMatrix;

    // 1. Render 3D Ground Grid
    if (showGrid) {
      _renderGroundGrid(canvas, size, viewProjMatrix, cameraPosition);
    }

    // 2. Collect Lights
    final lights = <LightComponent>[];
    for (final entity in engine.activeScene.allEntities) {
      if (!entity.enabled) continue;
      final light = entity.getComponent<LightComponent>();
      if (light != null && light.enabled) {
        lights.add(light);
      }
    }

    // 3. Project all meshes into screen space
    final projectedTriangles = <ProjectedTriangle>[];

    for (final entity in engine.activeScene.allEntities) {
      if (!entity.enabled) continue;
      final t3d = entity.getComponent<Transform3DComponent>();
      final mr = entity.getComponent<MeshRenderer3DComponent>();
      if (t3d == null || mr == null || !mr.enabled) continue;

      final worldMatrix = t3d.worldMatrix;
      final worldViewProj = viewProjMatrix * worldMatrix;
      final mesh = mr.mesh;
      final mat = mr.material;
      final isWireframe = wireframeOverride || mat.wireframe;

      // Transform all vertices for this mesh
      final screenVertices = <Offset?>[];
      final worldPositions = <Vector3>[];
      final viewDepths = <double>[];

      for (final v in mesh.vertices) {
        // World position
        final wPos4 = worldMatrix * Vector4(v.position.x, v.position.y, v.position.z, 1.0);
        final wPos = Vector3(wPos4.x, wPos4.y, wPos4.z);
        worldPositions.add(wPos);

        // Clip space position
        final clipPos = worldViewProj * Vector4(v.position.x, v.position.y, v.position.z, 1.0);

        // Near-plane clipping guard
        if (clipPos.w <= 0.05) {
          screenVertices.add(null);
          viewDepths.add(100000.0);
          continue;
        }

        // Perspective divide -> NDC space (-1 to 1)
        final invW = 1.0 / clipPos.w;
        final ndcX = clipPos.x * invW;
        final ndcY = clipPos.y * invW;

        // Viewport screen mapping
        final sx = (ndcX + 1.0) * 0.5 * size.width;
        final sy = (1.0 - ndcY) * 0.5 * size.height;

        screenVertices.add(Offset(sx, sy));
        viewDepths.add(clipPos.w);
      }

      // Process triangles
      for (final tri in mesh.triangles) {
        final p0 = screenVertices[tri.a];
        final p1 = screenVertices[tri.b];
        final p2 = screenVertices[tri.c];

        if (p0 == null || p1 == null || p2 == null) continue;

        // Backface Culling in screen space (cross product)
        final cross = (p1.dx - p0.dx) * (p2.dy - p0.dy) - (p1.dy - p0.dy) * (p2.dx - p0.dx);
        if (cross <= 0) continue; // Culled

        // Depth (average distance to camera)
        final avgDepth = (viewDepths[tri.a] + viewDepths[tri.b] + viewDepths[tri.c]) / 3.0;

        // Calculate Lighting
        final w0 = worldPositions[tri.a];
        final w1 = worldPositions[tri.b];
        final w2 = worldPositions[tri.c];
        final faceNormal = (w1 - w0).cross(w2 - w0).normalized();
        final centroid = (w0 + w1 + w2) * (1.0 / 3.0);

        final shadedColor = _calculateLighting(
          baseColor: mat.color,
          roughness: mat.roughness,
          metallic: mat.metallic,
          worldPos: centroid,
          normal: faceNormal,
          camPos: cameraPosition,
          lights: lights,
        );

        projectedTriangles.add(ProjectedTriangle(
          p0: p0,
          p1: p1,
          p2: p2,
          depth: avgDepth,
          color: shadedColor,
          wireframe: isWireframe,
          entity: entity,
        ));
      }
    }

    // 4. Depth Sorting (Painter's algorithm: farthest first)
    projectedTriangles.sort((a, b) => b.depth.compareTo(a.depth));

    // 5. Draw Triangles
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final path = Path();

    for (final tri in projectedTriangles) {
      path.reset();
      path.moveTo(tri.p0.dx, tri.p0.dy);
      path.lineTo(tri.p1.dx, tri.p1.dy);
      path.lineTo(tri.p2.dx, tri.p2.dy);
      path.close();

      if (tri.wireframe) {
        wirePaint.color = tri.color;
        canvas.drawPath(path, wirePaint);
      } else {
        fillPaint.color = tri.color;
        canvas.drawPath(path, fillPaint);
      }
    }

    // 6. Draw Selected Entity Highlight Outline
    _renderSelectionHighlight(canvas, engine.selectedEntity, viewProjMatrix, size);
  }

  static Color _calculateLighting({
    required Color baseColor,
    required double roughness,
    required double metallic,
    required Vector3 worldPos,
    required Vector3 normal,
    required Vector3 camPos,
    required List<LightComponent> lights,
  }) {
    // Ambient light base
    double r = 0.25;
    double g = 0.25;
    double b = 0.25;

    final viewDir = (camPos - worldPos).normalized();

    if (lights.isEmpty) {
      // Default directional sunlight if no lights in scene
      final sunDir = Vector3(0.5, 1.0, 0.8).normalized();
      final diff = math.max(0.0, normal.dot(sunDir));
      r += diff * 0.75;
      g += diff * 0.75;
      b += diff * 0.75;

      // Specular highlight
      final halfDir = (sunDir + viewDir).normalized();
      final spec = math.pow(math.max(0.0, normal.dot(halfDir)), (1.0 - roughness) * 64.0 + 4.0);
      r += spec * (0.3 + metallic * 0.5);
      g += spec * (0.3 + metallic * 0.5);
      b += spec * (0.3 + metallic * 0.5);
    } else {
      for (final light in lights) {
        if (light.type == LightType.ambient) {
          final lr = light.color.r * light.intensity;
          final lg = light.color.g * light.intensity;
          final lb = light.color.b * light.intensity;
          r += lr;
          g += lg;
          b += lb;
        } else if (light.type == LightType.directional) {
          // Direction from transform rotation or default
          final t = light.entity?.getComponent<Transform3DComponent>();
          final dir = t != null ? -t.forward.normalized() : Vector3(0.5, 1.0, 0.5).normalized();

          final diff = math.max(0.0, normal.dot(dir)) * light.intensity;
          r += light.color.r * diff;
          g += light.color.g * diff;
          b += light.color.b * diff;

          // Specular
          final halfDir = (dir + viewDir).normalized();
          final spec = math.pow(math.max(0.0, normal.dot(halfDir)), (1.0 - roughness) * 64.0 + 4.0) * light.intensity;
          r += spec * (0.2 + metallic * 0.6);
          g += spec * (0.2 + metallic * 0.6);
          b += spec * (0.2 + metallic * 0.6);
        } else if (light.type == LightType.point) {
          final lPos = light.entity?.getComponent<Transform3DComponent>()?.worldPosition ?? Vector3.zero();
          final toLight = lPos - worldPos;
          final dist = toLight.length;
          if (dist > light.range) continue;

          final dir = toLight.normalized();
          final atten = (1.0 - (dist / light.range)).clamp(0.0, 1.0);
          final diff = math.max(0.0, normal.dot(dir)) * light.intensity * atten;

          r += light.color.r * diff;
          g += light.color.g * diff;
          b += light.color.b * diff;
        }
      }
    }

    final finalR = (baseColor.r * r).clamp(0.0, 1.0);
    final finalG = (baseColor.g * g).clamp(0.0, 1.0);
    final finalB = (baseColor.b * b).clamp(0.0, 1.0);

    return Color.from(
      alpha: baseColor.a,
      red: finalR,
      green: finalG,
      blue: finalB,
    );
  }

  static void _renderGroundGrid(Canvas canvas, Size size, Matrix4 viewProj, Vector3 camPos) {
    const gridExtents = 10.0;
    const gridSpacing = 1.0;

    final gridPaint = Paint()
      ..color = const Color(0xFF222630)
      ..strokeWidth = 1.0;

    final xAxisPaint = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.8) // Red X
      ..strokeWidth = 1.5;

    final zAxisPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.8) // Blue Z
      ..strokeWidth = 1.5;

    // Draw lines along X and Z
    for (double i = -gridExtents; i <= gridExtents; i += gridSpacing) {
      // Parallel to X axis (varies in X, constant Z)
      final p0 = _projectPoint(Vector3(-gridExtents, 0.0, i), viewProj, size);
      final p1 = _projectPoint(Vector3(gridExtents, 0.0, i), viewProj, size);
      if (p0 != null && p1 != null) {
        canvas.drawLine(p0, p1, (i.abs() < 0.001) ? xAxisPaint : gridPaint);
      }

      // Parallel to Z axis (varies in Z, constant X)
      final q0 = _projectPoint(Vector3(i, 0.0, -gridExtents), viewProj, size);
      final q1 = _projectPoint(Vector3(i, 0.0, gridExtents), viewProj, size);
      if (q0 != null && q1 != null) {
        canvas.drawLine(q0, q1, (i.abs() < 0.001) ? zAxisPaint : gridPaint);
      }
    }
  }

  static void _renderSelectionHighlight(Canvas canvas, EmberEntity? selected, Matrix4 viewProj, Size size) {
    if (selected == null) return;
    final t3d = selected.getComponent<Transform3DComponent>();
    final mr = selected.getComponent<MeshRenderer3DComponent>();
    if (t3d == null || mr == null) return;

    final bounds = mr.mesh.bounds;
    final worldMatrix = t3d.worldMatrix;

    // 8 Bounding box corners
    final corners = [
      Vector3(bounds.min.x, bounds.min.y, bounds.min.z),
      Vector3(bounds.max.x, bounds.min.y, bounds.min.z),
      Vector3(bounds.max.x, bounds.max.y, bounds.min.z),
      Vector3(bounds.min.x, bounds.max.y, bounds.min.z),
      Vector3(bounds.min.x, bounds.min.y, bounds.max.z),
      Vector3(bounds.max.x, bounds.min.y, bounds.max.z),
      Vector3(bounds.max.x, bounds.max.y, bounds.max.z),
      Vector3(bounds.min.x, bounds.max.y, bounds.max.z),
    ];

    final screenCorners = <Offset?>[];
    for (final c in corners) {
      final wPos4 = worldMatrix * Vector4(c.x, c.y, c.z, 1.0);
      final wPos = Vector3(wPos4.x, wPos4.y, wPos4.z);
      screenCorners.add(_projectPoint(wPos, viewProj, size));
    }

    final outlinePaint = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha: 0.85) // Ember Indigo
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Connect 12 edges
    final edges = [
      [0, 1], [1, 2], [2, 3], [3, 0],
      [4, 5], [5, 6], [6, 7], [7, 4],
      [0, 4], [1, 5], [2, 6], [3, 7],
    ];

    for (final edge in edges) {
      final pA = screenCorners[edge[0]];
      final pB = screenCorners[edge[1]];
      if (pA != null && pB != null) {
        canvas.drawLine(pA, pB, outlinePaint);
      }
    }
  }

  static Offset? _projectPoint(Vector3 point, Matrix4 viewProj, Size size) {
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

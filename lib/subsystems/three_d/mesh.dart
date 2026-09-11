import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// Single vertex in 3D model space.
class Vertex3D {
  final Vector3 position;
  final Vector3 normal;
  final Vector2 uv;
  final Color color;

  const Vertex3D({
    required this.position,
    required this.normal,
    required this.uv,
    this.color = Colors.white,
  });

  Vertex3D copyWith({
    Vector3? position,
    Vector3? normal,
    Vector2? uv,
    Color? color,
  }) {
    return Vertex3D(
      position: position ?? this.position,
      normal: normal ?? this.normal,
      uv: uv ?? this.uv,
      color: color ?? this.color,
    );
  }
}

/// A 3D triangle indexing three vertices.
class Triangle3D {
  final int a;
  final int b;
  final int c;
  final Vector3? normal;

  const Triangle3D(this.a, this.b, this.c, [this.normal]);
}

/// Axis-Aligned Bounding Box in 3D space.
class AABB3D {
  final Vector3 min;
  final Vector3 max;

  AABB3D(this.min, this.max);

  Vector3 get center => (min + max) * 0.5;
  Vector3 get size => max - min;
  double get radius => size.length * 0.5;

  factory AABB3D.fromVertices(List<Vertex3D> vertices) {
    if (vertices.isEmpty) {
      return AABB3D(Vector3.zero(), Vector3.zero());
    }
    final min = vertices.first.position.clone();
    final max = vertices.first.position.clone();

    for (final v in vertices) {
      min.x = math.min(min.x, v.position.x);
      min.y = math.min(min.y, v.position.y);
      min.z = math.min(min.z, v.position.z);

      max.x = math.max(max.x, v.position.x);
      max.y = math.max(max.y, v.position.y);
      max.z = math.max(max.z, v.position.z);
    }
    return AABB3D(min, max);
  }
}

/// 3D Geometry mesh consisting of vertices, triangle indices, and bounding volume.
class Mesh3D {
  final String name;
  final List<Vertex3D> vertices;
  final List<Triangle3D> triangles;
  late final AABB3D bounds;

  Mesh3D({
    required this.name,
    required this.vertices,
    required this.triangles,
    AABB3D? bounds,
  }) {
    this.bounds = bounds ?? AABB3D.fromVertices(vertices);
  }

  /// Calculates face normals for triangles without precomputed normals.
  void computeFaceNormals() {
    for (int i = 0; i < triangles.length; i++) {
      final tri = triangles[i];
      final p0 = vertices[tri.a].position;
      final p1 = vertices[tri.b].position;
      final p2 = vertices[tri.c].position;

      final v0 = p1 - p0;
      final v1 = p2 - p0;
      final norm = v0.cross(v1).normalized();

      triangles[i] = Triangle3D(tri.a, tri.b, tri.c, norm);
    }
  }
}

import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'mesh.dart';

/// Factory for generating procedural 3D geometric meshes.
class MeshPrimitives {
  /// Generates an 8-vertex, 12-triangle 3D cube mesh.
  static Mesh3D createCube({double size = 1.0}) {
    final h = size * 0.5;

    // 24 vertices (4 per face for correct normals)
    final vertices = <Vertex3D>[
      // Front face (+Z)
      Vertex3D(position: Vector3(-h, -h, h), normal: Vector3(0, 0, 1), uv: Vector2(0, 0)),
      Vertex3D(position: Vector3(h, -h, h), normal: Vector3(0, 0, 1), uv: Vector2(1, 0)),
      Vertex3D(position: Vector3(h, h, h), normal: Vector3(0, 0, 1), uv: Vector2(1, 1)),
      Vertex3D(position: Vector3(-h, h, h), normal: Vector3(0, 0, 1), uv: Vector2(0, 1)),

      // Back face (-Z)
      Vertex3D(position: Vector3(h, -h, -h), normal: Vector3(0, 0, -1), uv: Vector2(0, 0)),
      Vertex3D(position: Vector3(-h, -h, -h), normal: Vector3(0, 0, -1), uv: Vector2(1, 0)),
      Vertex3D(position: Vector3(-h, h, -h), normal: Vector3(0, 0, -1), uv: Vector2(1, 1)),
      Vertex3D(position: Vector3(h, h, -h), normal: Vector3(0, 0, -1), uv: Vector2(0, 1)),

      // Top face (+Y)
      Vertex3D(position: Vector3(-h, h, h), normal: Vector3(0, 1, 0), uv: Vector2(0, 0)),
      Vertex3D(position: Vector3(h, h, h), normal: Vector3(0, 1, 0), uv: Vector2(1, 0)),
      Vertex3D(position: Vector3(h, h, -h), normal: Vector3(0, 1, 0), uv: Vector2(1, 1)),
      Vertex3D(position: Vector3(-h, h, -h), normal: Vector3(0, 1, 0), uv: Vector2(0, 1)),

      // Bottom face (-Y)
      Vertex3D(position: Vector3(-h, -h, -h), normal: Vector3(0, -1, 0), uv: Vector2(0, 0)),
      Vertex3D(position: Vector3(h, -h, -h), normal: Vector3(0, -1, 0), uv: Vector2(1, 0)),
      Vertex3D(position: Vector3(h, -h, h), normal: Vector3(0, -1, 0), uv: Vector2(1, 1)),
      Vertex3D(position: Vector3(-h, -h, h), normal: Vector3(0, -1, 0), uv: Vector2(0, 1)),

      // Right face (+X)
      Vertex3D(position: Vector3(h, -h, h), normal: Vector3(1, 0, 0), uv: Vector2(0, 0)),
      Vertex3D(position: Vector3(h, -h, -h), normal: Vector3(1, 0, 0), uv: Vector2(1, 0)),
      Vertex3D(position: Vector3(h, h, -h), normal: Vector3(1, 0, 0), uv: Vector2(1, 1)),
      Vertex3D(position: Vector3(h, h, h), normal: Vector3(1, 0, 0), uv: Vector2(0, 1)),

      // Left face (-X)
      Vertex3D(position: Vector3(-h, -h, -h), normal: Vector3(-1, 0, 0), uv: Vector2(0, 0)),
      Vertex3D(position: Vector3(-h, -h, h), normal: Vector3(-1, 0, 0), uv: Vector2(1, 0)),
      Vertex3D(position: Vector3(-h, h, h), normal: Vector3(-1, 0, 0), uv: Vector2(1, 1)),
      Vertex3D(position: Vector3(-h, h, -h), normal: Vector3(-1, 0, 0), uv: Vector2(0, 1)),
    ];

    final triangles = <Triangle3D>[];
    for (int i = 0; i < 6; i++) {
      final base = i * 4;
      triangles.add(Triangle3D(base, base + 1, base + 2));
      triangles.add(Triangle3D(base, base + 2, base + 3));
    }

    final mesh = Mesh3D(name: 'Cube', vertices: vertices, triangles: triangles);
    mesh.computeFaceNormals();
    return mesh;
  }

  /// Generates a UV sphere mesh.
  static Mesh3D createSphere({
    double radius = 0.5,
    int latSegments = 12,
    int lonSegments = 16,
  }) {
    final vertices = <Vertex3D>[];
    final triangles = <Triangle3D>[];

    for (int lat = 0; lat <= latSegments; lat++) {
      final theta = lat * math.pi / latSegments;
      final sinTheta = math.sin(theta);
      final cosTheta = math.cos(theta);

      for (int lon = 0; lon <= lonSegments; lon++) {
        final phi = lon * 2 * math.pi / lonSegments;
        final sinPhi = math.sin(phi);
        final cosPhi = math.cos(phi);

        final x = cosPhi * sinTheta;
        final y = cosTheta;
        final z = sinPhi * sinTheta;

        final pos = Vector3(x * radius, y * radius, z * radius);
        final norm = Vector3(x, y, z).normalized();
        final uv = Vector2(lon / lonSegments, lat / latSegments);

        vertices.add(Vertex3D(position: pos, normal: norm, uv: uv));
      }
    }

    for (int lat = 0; lat < latSegments; lat++) {
      for (int lon = 0; lon < lonSegments; lon++) {
        final first = lat * (lonSegments + 1) + lon;
        final second = first + lonSegments + 1;

        triangles.add(Triangle3D(first, second, first + 1));
        triangles.add(Triangle3D(second, second + 1, first + 1));
      }
    }

    final mesh = Mesh3D(name: 'Sphere', vertices: vertices, triangles: triangles);
    mesh.computeFaceNormals();
    return mesh;
  }

  /// Generates a horizontal ground plane mesh.
  static Mesh3D createPlane({
    double width = 10.0,
    double depth = 10.0,
    int subX = 4,
    int subZ = 4,
  }) {
    final vertices = <Vertex3D>[];
    final triangles = <Triangle3D>[];

    final halfW = width * 0.5;
    final halfD = depth * 0.5;

    for (int z = 0; z <= subZ; z++) {
      final fz = z / subZ;
      final posZ = -halfD + fz * depth;

      for (int x = 0; x <= subX; x++) {
        final fx = x / subX;
        final posX = -halfW + fx * width;

        vertices.add(Vertex3D(
          position: Vector3(posX, 0.0, posZ),
          normal: Vector3(0.0, 1.0, 0.0),
          uv: Vector2(fx, fz),
        ));
      }
    }

    for (int z = 0; z < subZ; z++) {
      for (int x = 0; x < subX; x++) {
        final row1 = z * (subX + 1);
        final row2 = (z + 1) * (subX + 1);

        triangles.add(Triangle3D(row1 + x, row2 + x, row1 + x + 1));
        triangles.add(Triangle3D(row1 + x + 1, row2 + x, row2 + x + 1));
      }
    }

    final mesh = Mesh3D(name: 'Plane', vertices: vertices, triangles: triangles);
    mesh.computeFaceNormals();
    return mesh;
  }

  /// Generates a 3D cylinder mesh.
  static Mesh3D createCylinder({
    double radius = 0.5,
    double height = 1.0,
    int segments = 16,
  }) {
    final vertices = <Vertex3D>[];
    final triangles = <Triangle3D>[];
    final halfH = height * 0.5;

    // Side vertices
    for (int i = 0; i <= segments; i++) {
      final u = i / segments;
      final angle = u * 2 * math.pi;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      final normal = Vector3(cosA, 0.0, sinA).normalized();

      // Top vertex
      vertices.add(Vertex3D(
        position: Vector3(cosA * radius, halfH, sinA * radius),
        normal: normal,
        uv: Vector2(u, 1.0),
      ));

      // Bottom vertex
      vertices.add(Vertex3D(
        position: Vector3(cosA * radius, -halfH, sinA * radius),
        normal: normal,
        uv: Vector2(u, 0.0),
      ));
    }

    // Side triangles
    for (int i = 0; i < segments; i++) {
      final top1 = i * 2;
      final bot1 = top1 + 1;
      final top2 = top1 + 2;
      final bot2 = top1 + 3;

      triangles.add(Triangle3D(top1, bot1, top2));
      triangles.add(Triangle3D(top2, bot1, bot2));
    }

    final mesh = Mesh3D(name: 'Cylinder', vertices: vertices, triangles: triangles);
    mesh.computeFaceNormals();
    return mesh;
  }

  /// Generates a 3D pyramid mesh.
  static Mesh3D createPyramid({
    double baseSize = 1.0,
    double height = 1.0,
  }) {
    final h = baseSize * 0.5;
    final vertices = <Vertex3D>[
      // Apex
      Vertex3D(position: Vector3(0, height, 0), normal: Vector3(0, 1, 0), uv: Vector2(0.5, 1.0)),
      // Base corners
      Vertex3D(position: Vector3(-h, 0, h), normal: Vector3(0, -1, 0), uv: Vector2(0, 0)),
      Vertex3D(position: Vector3(h, 0, h), normal: Vector3(0, -1, 0), uv: Vector2(1, 0)),
      Vertex3D(position: Vector3(h, 0, -h), normal: Vector3(0, -1, 0), uv: Vector2(1, 1)),
      Vertex3D(position: Vector3(-h, 0, -h), normal: Vector3(0, -1, 0), uv: Vector2(0, 1)),
    ];

    final triangles = <Triangle3D>[
      // Sides
      Triangle3D(0, 1, 2),
      Triangle3D(0, 2, 3),
      Triangle3D(0, 3, 4),
      Triangle3D(0, 4, 1),
      // Base
      Triangle3D(1, 4, 3),
      Triangle3D(1, 3, 2),
    ];

    final mesh = Mesh3D(name: 'Pyramid', vertices: vertices, triangles: triangles);
    mesh.computeFaceNormals();
    return mesh;
  }
}

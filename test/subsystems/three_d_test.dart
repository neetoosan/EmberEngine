import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/subsystems/three_d/camera3d.dart';
import 'package:ember_engine/subsystems/three_d/gizmos3d.dart';
import 'package:ember_engine/subsystems/three_d/material.dart';
import 'package:ember_engine/subsystems/three_d/primitives.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ember Engine 3D Subsystem Tests', () {
    test('MeshPrimitives geometry generation', () {
      // 1. Cube
      final cube = MeshPrimitives.createCube(size: 2.0);
      expect(cube.name, 'Cube');
      expect(cube.vertices.length, 24);
      expect(cube.triangles.length, 12);
      expect(cube.bounds.size.x, closeTo(2.0, 0.001));

      // 2. Sphere
      final sphere = MeshPrimitives.createSphere(radius: 1.0, latSegments: 8, lonSegments: 8);
      expect(sphere.name, 'Sphere');
      expect(sphere.vertices.isNotEmpty, isTrue);
      expect(sphere.triangles.isNotEmpty, isTrue);

      // 3. Plane
      final plane = MeshPrimitives.createPlane(width: 4.0, depth: 4.0, subX: 2, subZ: 2);
      expect(plane.name, 'Plane');
      expect(plane.bounds.size.x, closeTo(4.0, 0.001));

      // 4. Cylinder
      final cyl = MeshPrimitives.createCylinder(radius: 0.5, height: 2.0, segments: 8);
      expect(cyl.name, 'Cylinder');
      expect(cyl.bounds.size.y, closeTo(2.0, 0.001));

      // 5. Pyramid
      final pyr = MeshPrimitives.createPyramid(baseSize: 2.0, height: 3.0);
      expect(pyr.name, 'Pyramid');
      expect(pyr.triangles.length, 6);
    });

    test('Material3D serialization and cloning', () {
      final mat = Material3D(
        color: const Color(0xFF6366F1),
        roughness: 0.25,
        metallic: 0.8,
        wireframe: true,
        opacity: 0.9,
      );

      final json = mat.toJson();
      final restored = Material3D.fromJson(json);

      expect(restored.roughness, 0.25);
      expect(restored.metallic, 0.8);
      expect(restored.wireframe, isTrue);
      expect(restored.opacity, 0.9);

      final clone = mat.clone();
      expect(clone.roughness, 0.25);
      expect(clone.metallic, 0.8);
    });

    test('CameraComponent matrices and ray casting', () {
      final cam = CameraComponent(fov: 60.0, near: 0.1, far: 100.0);
      final view = cam.getViewMatrix(Vector3(0, 0, 5), Quaternion.identity());
      expect(view, isNotNull);

      final proj = cam.getProjectionMatrix(16.0 / 9.0);
      expect(proj, isNotNull);

      // Screen center ray should point directly forward (-Z)
      final ray = cam.screenPointToRay(
        const Offset(400, 300),
        const Size(800, 600),
        Vector3(0, 0, 5),
        Quaternion.identity(),
      );

      expect(ray.direction.z, closeTo(-1.0, 0.05));
      expect(ray.direction.x.abs(), lessThan(0.05));
      expect(ray.direction.y.abs(), lessThan(0.05));
    });

    test('OrbitCameraController orbit and pan operations', () {
      final controller = OrbitCameraController();
      controller.distance = 10.0;
      controller.azimuth = 0.0;
      controller.elevation = 0.0;

      final initialPos = controller.getPosition();
      expect(initialPos.z, closeTo(10.0, 0.001));

      // Orbit 90 degrees around Y (azimuth = pi/2)
      controller.orbit(math.pi * 50.0, 0); // deltaX * 0.01
      expect(controller.getPosition(), isNot(initialPos));

      // Pan
      final oldTarget = controller.target.clone();
      controller.pan(10.0, 10.0);
      expect(controller.target, isNot(oldTarget));

      // Zoom
      controller.zoom(0.5);
      expect(controller.distance, 5.0);
    });

    test('Gizmo3DHandler axis hit testing', () {
      final handler = Gizmo3DHandler();
      final entity = EmberEntity(name: 'GizmoTarget');
      entity.addComponent(Transform3DComponent(position: Vector3(0, 0, 0)));

      final camPos = Vector3(0, 0, 5);
      final camRot = Quaternion.identity();
      const viewportSize = Size(800, 600);

      // Center of screen (400, 300) should project to (0, 0, 0)
      // Y handle extends upwards (smaller dy in screen coordinates)
      final hitAxisY = handler.hitTestGizmo(
        mouseScreen: const Offset(400, 260),
        selected: entity,
        size: viewportSize,
        cameraPosition: camPos,
        cameraRotation: camRot,
      );

      expect(hitAxisY, GizmoAxis.y);

      // Miss test
      final hitMiss = handler.hitTestGizmo(
        mouseScreen: const Offset(100, 100),
        selected: entity,
        size: viewportSize,
        cameraPosition: camPos,
        cameraRotation: camRot,
      );
      expect(hitMiss, GizmoAxis.none);
    });
  });
}

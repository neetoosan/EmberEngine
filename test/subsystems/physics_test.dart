import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/subsystems/three_d/components3d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/physics/physics_world3d.dart';
import 'package:ember_engine/subsystems/physics/physics_world2d.dart';
import 'package:ember_engine/subsystems/physics/character_controller3d.dart';
import 'package:ember_engine/subsystems/physics/character_controller2d.dart';

void main() {
  group('Physics 3D Subsystem Tests', () {
    test('RigidBody3D accelerates under gravity and is clamped at ground', () {
      final scene = EmberScene(name: 'PhysicsTest');
      final cube = EmberEntity(name: 'FallingCube');
      final t3d = Transform3DComponent(position: Vector3(0, 10, 0));
      final rb = RigidBody3DComponent(mass: 1.0, useGravity: true);
      final col = Collider3DComponent(size: Vector3(1, 1, 1));

      cube.addComponent(t3d);
      cube.addComponent(rb);
      cube.addComponent(col);
      scene.addEntity(cube);

      // Step physics for 0.5s (30 steps of 1/60s)
      for (int i = 0; i < 30; i++) {
        PhysicsWorld3D.step(scene, 1.0 / 60.0);
      }

      expect(t3d.position.y, lessThan(10.0));
      expect(rb.velocity.y, lessThan(0.0));

      // Step physics for 3.0s until ground contact
      for (int i = 0; i < 180; i++) {
        PhysicsWorld3D.step(scene, 1.0 / 60.0);
      }

      // Ground plane resolution holds object at half extents (0.5)
      expect(t3d.position.y, closeTo(0.5, 0.05));
    });

    test('PhysicsWorld3D.raycast detects closest colliding box entity', () {
      final scene = EmberScene(name: 'RaycastTest');
      final target = EmberEntity(name: 'TargetCube');
      target.addComponent(Transform3DComponent(position: Vector3(0, 0, 10)));
      target.addComponent(Collider3DComponent(size: Vector3(2, 2, 2)));
      scene.addEntity(target);

      final hit = PhysicsWorld3D.raycast(
        scene: scene,
        origin: Vector3(0, 0, 0),
        direction: Vector3(0, 0, 1),
        maxDistance: 50.0,
      );

      expect(hit, isNotNull);
      expect(hit!.entity.name, equals('TargetCube'));
      expect(hit.distance, closeTo(9.0, 0.01)); // 10 - half-depth 1 = 9.0
    });

    test('CharacterController3DComponent moves kinematically and jumps', () {
      final cc = CharacterController3DComponent(walkSpeed: 6.0, jumpForce: 8.0);
      final t3d = Transform3DComponent(position: Vector3(0, 0.5, 0));
      final entity = EmberEntity(name: 'FPSChar');
      entity.addComponent(t3d);
      entity.addComponent(cc);

      // Horizontal movement
      cc.move(Vector3(1, 0, 0), 1.0 / 60.0);
      expect(t3d.position.x, greaterThan(0.0));

      // Jump
      cc.jump();
      expect(cc.isGrounded, isFalse);
    });
  });

  group('Physics 2D Subsystem Tests', () {
    test('PhysicsWorld2D resolves AABB collisions against solid hitboxes', () {
      final scene = EmberScene(name: 'Physics2DTest');

      final wall = EmberEntity(name: 'SolidWall');
      wall.addComponent(Transform2DComponent(position: Vector2(200, 200), size: Vector2(100, 100)));
      wall.addComponent(FlameHitbox2DComponent(shape: Hitbox2DShape.rectangle, isSolid: true));
      scene.addEntity(wall);

      final mover = EmberEntity(name: 'Mover');
      final moverT = Transform2DComponent(position: Vector2(180, 200), size: Vector2(40, 40));
      mover.addComponent(moverT);
      mover.addComponent(FlameHitbox2DComponent(shape: Hitbox2DShape.rectangle, isSolid: true));
      scene.addEntity(mover);

      PhysicsWorld2D.step(scene, 1.0 / 60.0);

      // Overlap resolution should push mover out along X axis
      expect(moverT.position.x, lessThanOrEqualTo(180.0));
    });

    test('CharacterController2DComponent implements Coyote Time and Jump Buffering', () {
      final cc = CharacterController2DComponent(
        moveSpeed: 200.0,
        jumpVelocity: 400.0,
        coyoteTimeDuration: 0.12,
        jumpBufferDuration: 0.10,
        groundY: 500.0,
      );
      final t2d = Transform2DComponent(position: Vector2(100, 500));
      final entity = EmberEntity(name: 'PlatformerChar');
      entity.addComponent(t2d);
      entity.addComponent(cc);

      // 1. Initially grounded
      cc.update(entity, 1.0 / 60.0);
      expect(cc.isGrounded, isTrue);

      // 2. Walk off a ledge (position drops past ground)
      t2d.position = Vector2(100, 480);
      cc.update(entity, 1.0 / 60.0);

      // Within 120ms coyote window, jump succeeds even when airborne!
      expect(cc.canJump, isTrue);
      cc.jump();
      expect(cc.velocity.y, lessThan(0.0)); // Negative is upwards in 2D Screen coords

      // 3. Jump buffering: press jump 50ms before touching ground
      cc.bufferJump();
      expect(cc.isJumpBuffered, isTrue);
    });
  });
}

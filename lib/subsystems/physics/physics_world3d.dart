import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';
import '../../core/entity.dart';
import '../../core/scene.dart';
import '../../core/transform3d.dart';
import '../three_d/components3d.dart';

/// 3D Raycast Hit result.
class RaycastHit3D {
  final EmberEntity entity;
  final Vector3 point;
  final Vector3 normal;
  final double distance;

  RaycastHit3D({
    required this.entity,
    required this.point,
    required this.normal,
    required this.distance,
  });
}

/// High-performance 3D Physics Simulation World for Ember Engine.
///
/// Implements:
/// - RigidBody dynamics (Gravity, Drag, Velocity integration)
/// - Collision resolution with static Colliders and Ground Plane
/// - High-speed Raycasting for hitscan weapons and line-of-sight checks
class PhysicsWorld3D {
  static Vector3 gravity = Vector3(0.0, -9.81, 0.0);

  /// Fixed-timestep physics simulation step (e.g. 60Hz = 0.0166s).
  static void step(EmberScene scene, double fixedDt) {
    final entities = scene.allEntities;

    // 1. Integrate rigid bodies
    for (final entity in entities) {
      if (!entity.enabled) continue;
      final rb = entity.getComponent<RigidBody3DComponent>();
      final t3d = entity.getComponent<Transform3DComponent>();
      if (rb == null || t3d == null || !rb.enabled || rb.isKinematic) continue;

      // Apply Gravity
      if (rb.useGravity) {
        rb.velocity += gravity * fixedDt;
      }

      // Apply Linear Drag
      final dragFactor = math.max(0.0, 1.0 - rb.drag * fixedDt);
      rb.velocity *= dragFactor;

      // Integrate Position
      t3d.position += rb.velocity * fixedDt;

      // Ground plane collision resolution (at y = 0.0 or collider bound)
      final col = entity.getComponent<Collider3DComponent>();
      final halfH = col != null ? (col.size.y / 2.0) * t3d.scale.y : 0.5 * t3d.scale.y;

      if (t3d.position.y - halfH < 0.0) {
        t3d.position = Vector3(t3d.position.x, halfH, t3d.position.z);
        if (rb.velocity.y < 0) {
          rb.velocity = Vector3(rb.velocity.x * 0.8, -rb.velocity.y * 0.25, rb.velocity.z * 0.8);
          if (rb.velocity.y.abs() < 0.2) {
            rb.velocity = Vector3(rb.velocity.x * 0.8, 0.0, rb.velocity.z * 0.8);
          }
        }
      }
    }

    // 2. Inter-entity collision checks (AABB / Sphere)
    for (int i = 0; i < entities.length; i++) {
      final eA = entities[i];
      if (!eA.enabled) continue;
      final rbA = eA.getComponent<RigidBody3DComponent>();
      final colA = eA.getComponent<Collider3DComponent>();
      final tA = eA.getComponent<Transform3DComponent>();
      if (rbA == null || colA == null || tA == null || rbA.isKinematic) continue;

      for (int j = 0; j < entities.length; j++) {
        if (i == j) continue;
        final eB = entities[j];
        if (!eB.enabled) continue;
        final colB = eB.getComponent<Collider3DComponent>();
        final tB = eB.getComponent<Transform3DComponent>();
        if (colB == null || tB == null) continue;

        _resolveColliderPair(eA, tA, rbA, colA, eB, tB, colB);
      }
    }
  }

  static void _resolveColliderPair(
    EmberEntity eA,
    Transform3DComponent tA,
    RigidBody3DComponent rbA,
    Collider3DComponent colA,
    EmberEntity eB,
    Transform3DComponent tB,
    Collider3DComponent colB,
  ) {
    if (colA.isTrigger || colB.isTrigger) return;

    final posA = tA.worldPosition + colA.center;
    final posB = tB.worldPosition + colB.center;
    final halfA = Vector3(
      colA.size.x * tA.scale.x * 0.5,
      colA.size.y * tA.scale.y * 0.5,
      colA.size.z * tA.scale.z * 0.5,
    );
    final halfB = Vector3(
      colB.size.x * tB.scale.x * 0.5,
      colB.size.y * tB.scale.y * 0.5,
      colB.size.z * tB.scale.z * 0.5,
    );

    // AABB Overlap check
    final dx = posA.x - posB.x;
    final px = (halfA.x + halfB.x) - dx.abs();
    if (px <= 0) return;

    final dy = posA.y - posB.y;
    final py = (halfA.y + halfB.y) - dy.abs();
    if (py <= 0) return;

    final dz = posA.z - posB.z;
    final pz = (halfA.z + halfB.z) - dz.abs();
    if (pz <= 0) return;

    // Minimum penetration resolution
    if (px < py && px < pz) {
      final sign = dx > 0 ? 1.0 : -1.0;
      tA.position += Vector3(px * sign, 0, 0);
      rbA.velocity = Vector3(-rbA.velocity.x * 0.3, rbA.velocity.y, rbA.velocity.z);
    } else if (py < px && py < pz) {
      final sign = dy > 0 ? 1.0 : -1.0;
      tA.position += Vector3(0, py * sign, 0);
      rbA.velocity = Vector3(rbA.velocity.x, -rbA.velocity.y * 0.3, rbA.velocity.z);
    } else {
      final sign = dz > 0 ? 1.0 : -1.0;
      tA.position += Vector3(0, 0, pz * sign);
      rbA.velocity = Vector3(rbA.velocity.x, rbA.velocity.y, -rbA.velocity.z * 0.3);
    }
  }

  /// High-speed 3D Raycast against scene colliders.
  static RaycastHit3D? raycast({
    required EmberScene scene,
    required Vector3 origin,
    required Vector3 direction,
    double maxDistance = 100.0,
    EmberEntity? ignoreEntity,
  }) {
    final normDir = direction.normalized();
    RaycastHit3D? closestHit;
    double minDistance = maxDistance;

    for (final entity in scene.allEntities) {
      if (!entity.enabled || entity == ignoreEntity) continue;
      final t3d = entity.getComponent<Transform3DComponent>();
      final col = entity.getComponent<Collider3DComponent>();
      if (t3d == null || col == null) continue;

      final center = t3d.worldPosition + col.center;
      final halfSize = Vector3(
        col.size.x * t3d.scale.x * 0.5,
        col.size.y * t3d.scale.y * 0.5,
        col.size.z * t3d.scale.z * 0.5,
      );

      // Ray-AABB intersection
      final min = center - halfSize;
      final max = center + halfSize;

      double tmin = (min.x - origin.x) / normDir.x;
      double tmax = (max.x - origin.x) / normDir.x;
      if (tmin > tmax) {
        final tmp = tmin;
        tmin = tmax;
        tmax = tmp;
      }

      double tymin = (min.y - origin.y) / normDir.y;
      double tymax = (max.y - origin.y) / normDir.y;
      if (tymin > tymax) {
        final tmp = tymin;
        tymin = tymax;
        tymax = tmp;
      }

      if ((tmin > tymax) || (tymin > tmax)) continue;

      if (tymin > tmin) tmin = tymin;
      if (tymax < tmax) tmax = tymax;

      double tzmin = (min.z - origin.z) / normDir.z;
      double tzmax = (max.z - origin.z) / normDir.z;
      if (tzmin > tzmax) {
        final tmp = tzmin;
        tzmin = tzmax;
        tzmax = tmp;
      }

      if ((tmin > tzmax) || (tzmin > tmax)) continue;

      if (tzmin > tmin) tmin = tzmin;
      if (tzmax < tmax) tmax = tzmax;

      if (tmin >= 0 && tmin < minDistance) {
        minDistance = tmin;
        final hitPoint = origin + normDir * tmin;
        final normal = _calculateAABBNormal(hitPoint, center, halfSize);

        closestHit = RaycastHit3D(
          entity: entity,
          point: hitPoint,
          normal: normal,
          distance: tmin,
        );
      }
    }

    return closestHit;
  }

  static Vector3 _calculateAABBNormal(Vector3 hitPoint, Vector3 center, Vector3 half) {
    final local = hitPoint - center;
    final nx = local.x.abs() / half.x;
    final ny = local.y.abs() / half.y;
    final nz = local.z.abs() / half.z;

    if (nx > ny && nx > nz) {
      return Vector3(local.x > 0 ? 1 : -1, 0, 0);
    } else if (ny > nx && ny > nz) {
      return Vector3(0, local.y > 0 ? 1 : -1, 0);
    } else {
      return Vector3(0, 0, local.z > 0 ? 1 : -1);
    }
  }
}

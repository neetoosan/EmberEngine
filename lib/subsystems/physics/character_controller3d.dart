import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/transform3d.dart';
import '../three_d/components3d.dart';

/// 3D Kinematic Character Controller (Capsule).
///
/// Handles robust FPS/third-person character mechanics:
/// - Kinematic WASD movement with acceleration and friction
/// - Gravity, jumping, and ground detection
/// - Slope sliding and collision push-out
class CharacterController3DComponent extends EmberComponent {
  double walkSpeed;
  double sprintSpeed;
  double jumpForce;
  double gravity;
  double height;
  double radius;

  /// Maximum ledge height the character walks up without jumping.
  double stepHeight = 0.35;

  final Vector3 _velocity = Vector3.zero();
  bool _isGrounded = false;
  final double _groundCheckDistance = 0.15;

  CharacterController3DComponent({
    this.walkSpeed = 6.0,
    this.sprintSpeed = 10.0,
    this.jumpForce = 6.5,
    this.gravity = 18.0,
    this.height = 1.8,
    this.radius = 0.4,
  });

  bool get isGrounded => _isGrounded;
  Vector3 get velocity => _velocity;

  /// Moves the kinematic character in local or world space.
  void move(Vector3 inputDirection, [dynamic isSprintingOrDt = false, double? maybeDt]) {
    final t3d = entity?.getComponent<Transform3DComponent>();
    if (t3d == null) return;

    final bool isSprinting;
    final double dt;
    if (isSprintingOrDt is bool) {
      isSprinting = isSprintingOrDt;
      dt = maybeDt ?? (1.0 / 60.0);
    } else if (isSprintingOrDt is num) {
      isSprinting = false;
      dt = isSprintingOrDt.toDouble();
    } else {
      isSprinting = false;
      dt = 1.0 / 60.0;
    }

    final targetSpeed = isSprinting ? sprintSpeed : walkSpeed;
    final moveDir = inputDirection.length2 > 0 ? inputDirection.normalized() : Vector3.zero();

    // Smooth horizontal acceleration
    final targetVelX = moveDir.x * targetSpeed;
    final targetVelZ = moveDir.z * targetSpeed;

    _velocity.x += (targetVelX - _velocity.x) * math.min(1.0, dt * 12.0);
    _velocity.z += (targetVelZ - _velocity.z) * math.min(1.0, dt * 12.0);

    // Apply gravity. While grounded, keep a small downward push so ground
    // contact is re-detected every frame (and we follow ramps / step down).
    if (_isGrounded && _velocity.y <= 0) {
      _velocity.y = -2.0;
    } else {
      _velocity.y -= gravity * dt;
    }

    // Integrate position
    final pos = t3d.position + _velocity * dt;
    final halfH = height * 0.5;
    _isGrounded = false;

    // World floor at y = 0.0
    if (pos.y - halfH <= _groundCheckDistance && _velocity.y <= 0) {
      pos.y = halfH;
      _isGrounded = true;
      _velocity.y = 0.0;
    }

    // Solid colliders in the same scene (walls, crates, platforms)
    final self = entity;
    final scene = self?.scene;
    if (scene != null) {
      for (final other in scene.allEntities) {
        if (identical(other, self) || !other.enabled) continue;
        final col = other.getComponent<Collider3DComponent>();
        final ot = other.getComponent<Transform3DComponent>();
        if (col == null || ot == null || !col.enabled || col.isTrigger) continue;
        _resolveAgainstBox(pos, halfH, ot.worldPosition + col.center, Vector3(
          col.size.x * ot.worldScale.x * 0.5,
          col.size.y * ot.worldScale.y * 0.5,
          col.size.z * ot.worldScale.z * 0.5,
        ));
      }
    }

    t3d.position = pos;
  }

  /// Pushes the character's bounding box ([pos], [halfH], [radius]) out of a
  /// static box along the axis of least penetration. Low obstacles (at most
  /// [stepHeight] above the feet) are stepped onto instead of blocking.
  void _resolveAgainstBox(Vector3 pos, double halfH, Vector3 center, Vector3 half) {
    final dx = pos.x - center.x;
    final px = (radius + half.x) - dx.abs();
    if (px <= 0) return;
    final dz = pos.z - center.z;
    final pz = (radius + half.z) - dz.abs();
    if (pz <= 0) return;
    final dy = pos.y - center.y;
    final py = (halfH + half.y) - dy.abs();
    if (py <= 0) return;

    final landing = dy > 0 && (py <= stepHeight || (py < px && py < pz));
    if (landing) {
      pos.y += py;
      if (_velocity.y <= 0) {
        _velocity.y = 0.0;
        _isGrounded = true;
      }
    } else if (py < px && py < pz) {
      // Head bump
      pos.y -= py;
      if (_velocity.y > 0) _velocity.y = 0.0;
    } else if (px < pz) {
      pos.x += dx > 0 ? px : -px;
      _velocity.x = 0.0;
    } else {
      pos.z += dz > 0 ? pz : -pz;
      _velocity.z = 0.0;
    }
  }

  /// Eye position for first-person cameras (near the top of the capsule).
  Vector3 get eyeOffset => Vector3(0.0, height * 0.4, 0.0);

  /// Triggers a jump if character is currently on the ground.
  bool jump() {
    if (_isGrounded) {
      _velocity.y = jumpForce;
      _isGrounded = false;
      return true;
    }
    return false;
  }

  @override
  String get displayName => 'Character Controller 3D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<double>(
          name: 'walkSpeed',
          label: 'Walk Speed (m/s)',
          type: InspectableType.number,
          getter: () => walkSpeed,
          setter: (val) {
            walkSpeed = val;
            notifyListeners();
          },
          min: 1.0,
          max: 20.0,
          step: 0.5,
        ),
        InspectableProperty<double>(
          name: 'sprintSpeed',
          label: 'Sprint Speed (m/s)',
          type: InspectableType.number,
          getter: () => sprintSpeed,
          setter: (val) {
            sprintSpeed = val;
            notifyListeners();
          },
          min: 2.0,
          max: 30.0,
          step: 0.5,
        ),
        InspectableProperty<double>(
          name: 'jumpForce',
          label: 'Jump Force',
          type: InspectableType.number,
          getter: () => jumpForce,
          setter: (val) {
            jumpForce = val;
            notifyListeners();
          },
          min: 1.0,
          max: 20.0,
          step: 0.5,
        ),
        InspectableProperty<double>(
          name: 'gravity',
          label: 'Gravity (m/s²)',
          type: InspectableType.number,
          getter: () => gravity,
          setter: (val) {
            gravity = val;
            notifyListeners();
          },
          min: 0.0,
          max: 50.0,
          step: 1.0,
        ),
        InspectableProperty<double>(
          name: 'height',
          label: 'Capsule Height',
          type: InspectableType.number,
          getter: () => height,
          setter: (val) {
            height = val;
            notifyListeners();
          },
          min: 0.5,
          max: 3.0,
          step: 0.1,
        ),
        InspectableProperty<double>(
          name: 'radius',
          label: 'Capsule Radius',
          type: InspectableType.number,
          getter: () => radius,
          setter: (val) {
            radius = val;
            notifyListeners();
          },
          min: 0.1,
          max: 1.5,
          step: 0.05,
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'walkSpeed': walkSpeed,
      'sprintSpeed': sprintSpeed,
      'jumpForce': jumpForce,
      'gravity': gravity,
      'height': height,
      'radius': radius,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    walkSpeed = (json['walkSpeed'] as num?)?.toDouble() ?? 6.0;
    sprintSpeed = (json['sprintSpeed'] as num?)?.toDouble() ?? 10.0;
    jumpForce = (json['jumpForce'] as num?)?.toDouble() ?? 6.5;
    gravity = (json['gravity'] as num?)?.toDouble() ?? 18.0;
    height = (json['height'] as num?)?.toDouble() ?? 1.8;
    radius = (json['radius'] as num?)?.toDouble() ?? 0.4;
    notifyListeners();
  }

  @override
  CharacterController3DComponent clone() {
    return CharacterController3DComponent(
      walkSpeed: walkSpeed,
      sprintSpeed: sprintSpeed,
      jumpForce: jumpForce,
      gravity: gravity,
      height: height,
      radius: radius,
    );
  }
}

/// Registers 3D Character Controller in ComponentRegistry.
void registerCharacterController3D() {
  ComponentRegistry.register('Character Controller 3D', (json) {
    final comp = CharacterController3DComponent();
    comp.fromJson(json);
    return comp;
  });
}

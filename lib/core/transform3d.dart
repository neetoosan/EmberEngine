import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';
import 'component.dart';
import 'inspectable.dart';

/// 3D Transform component in the Ember Engine ECS architecture.
///
/// Stores local position, rotation (Quaternion + Euler angles), and scale.
/// Propagates parent-child transforms down the scene graph:
/// [worldMatrix] = parent.[worldMatrix] * [localMatrix].
class Transform3DComponent extends EmberComponent {
  Vector3 _position;
  Quaternion _rotation;
  Vector3 _euler; // in degrees (X: Pitch, Y: Yaw, Z: Roll)
  Vector3 _scale;

  // Cached matrices and dirtiness flags
  Matrix4 _localMatrix = Matrix4.identity();
  Matrix4 _worldMatrix = Matrix4.identity();
  bool _isDirty = true;

  Transform3DComponent({
    Vector3? position,
    Quaternion? rotation,
    Vector3? euler,
    Vector3? scale,
  })  : _position = position ?? Vector3.zero(),
        _rotation = rotation ?? Quaternion.identity(),
        _euler = euler ?? Vector3.zero(),
        _scale = scale ?? Vector3(1.0, 1.0, 1.0) {
    if (euler != null && rotation == null) {
      _updateQuaternionFromEuler();
    } else if (rotation != null && euler == null) {
      _updateEulerFromQuaternion();
    }
    _recomputeLocalMatrix();
  }

  // --- Getters & Setters ---

  Vector3 get position => _position;
  set position(Vector3 val) {
    _position = val;
    setDirty();
  }

  Quaternion get rotation => _rotation;
  set rotation(Quaternion val) {
    _rotation = val;
    _updateEulerFromQuaternion();
    setDirty();
  }

  Vector3 get euler => _euler;
  set euler(Vector3 degrees) {
    _euler = degrees;
    _updateQuaternionFromEuler();
    setDirty();
  }

  Vector3 get scale => _scale;
  set scale(Vector3 val) {
    _scale = val;
    setDirty();
  }

  void setDirty() {
    _isDirty = true;
    _recomputeLocalMatrix();
    notifyListeners();
  }

  // --- Directional Vectors (in local space) ---

  /// Forward direction vector (along positive Z or negative Z; standard right-handed: -Z is forward).
  Vector3 get forward {
    return _rotation.rotate(Vector3(0.0, 0.0, -1.0));
  }

  /// Right direction vector (along positive X).
  Vector3 get right {
    return _rotation.rotate(Vector3(1.0, 0.0, 0.0));
  }

  /// Up direction vector (along positive Y).
  Vector3 get up {
    return _rotation.rotate(Vector3(0.0, 1.0, 0.0));
  }

  // --- Matrices ---

  /// The local transformation matrix (TRS: Translation * Rotation * Scale).
  Matrix4 get localMatrix {
    if (_isDirty) {
      _recomputeLocalMatrix();
    }
    return _localMatrix;
  }

  void _recomputeLocalMatrix() {
    _localMatrix = Matrix4.compose(_position, _rotation, _scale);
    _isDirty = false;
  }

  /// The world transformation matrix, recursively resolved from parent hierarchy.
  Matrix4 get worldMatrix {
    final parentEntity = entity?.parent;
    final parentTransform = parentEntity?.getComponent<Transform3DComponent>();

    if (parentTransform != null) {
      _worldMatrix = parentTransform.worldMatrix * localMatrix;
    } else {
      _worldMatrix = localMatrix.clone();
    }
    return _worldMatrix;
  }

  /// World space position.
  Vector3 get worldPosition {
    final m = worldMatrix;
    return Vector3(m.storage[12], m.storage[13], m.storage[14]);
  }

  /// World space scale.
  Vector3 get worldScale {
    final m = worldMatrix;
    final sx = Vector3(m.storage[0], m.storage[1], m.storage[2]).length;
    final sy = Vector3(m.storage[4], m.storage[5], m.storage[6]).length;
    final sz = Vector3(m.storage[8], m.storage[9], m.storage[10]).length;
    return Vector3(sx, sy, sz);
  }

  // --- Operations ---

  void translate(Vector3 delta) {
    _position += delta;
    setDirty();
  }

  void rotateX(double radians) {
    _rotation = _rotation * Quaternion.axisAngle(Vector3(1, 0, 0), radians);
    _updateEulerFromQuaternion();
    setDirty();
  }

  void rotateY(double radians) {
    _rotation = _rotation * Quaternion.axisAngle(Vector3(0, 1, 0), radians);
    _updateEulerFromQuaternion();
    setDirty();
  }

  void rotateZ(double radians) {
    _rotation = _rotation * Quaternion.axisAngle(Vector3(0, 0, 1), radians);
    _updateEulerFromQuaternion();
    setDirty();
  }

  void lookAt(Vector3 target, [Vector3? upVec]) {
    final upDirection = upVec ?? Vector3(0, 1, 0);
    final forwardDir = (target - _position).normalized();
    if (forwardDir.length2 == 0) return;

    final rightDir = forwardDir.cross(upDirection).normalized();
    final actualUp = rightDir.cross(forwardDir).normalized();

    final rotMatrix = Matrix3(
      rightDir.x, actualUp.x, -forwardDir.x,
      rightDir.y, actualUp.y, -forwardDir.y,
      rightDir.z, actualUp.z, -forwardDir.z,
    );

    _rotation = Quaternion.fromRotation(rotMatrix);
    _updateEulerFromQuaternion();
    setDirty();
  }

  // --- Helper conversions ---

  void _updateQuaternionFromEuler() {
    final radX = _euler.x * math.pi / 180.0;
    final radY = _euler.y * math.pi / 180.0;
    final radZ = _euler.z * math.pi / 180.0;

    final qx = Quaternion.axisAngle(Vector3(1, 0, 0), radX);
    final qy = Quaternion.axisAngle(Vector3(0, 1, 0), radY);
    final qz = Quaternion.axisAngle(Vector3(0, 0, 1), radZ);

    _rotation = qy * qx * qz;
  }

  void _updateEulerFromQuaternion() {
    // Extract Euler angles (in degrees) from rotation matrix
    final m = _rotation.asRotationMatrix();
    double pitch, yaw, roll;

    // Standard YXZ or ZYX decomposition
    if (m.entry(1, 2) < 0.999 && m.entry(1, 2) > -0.999) {
      pitch = math.asin(-m.entry(1, 2));
      yaw = math.atan2(m.entry(0, 2), m.entry(2, 2));
      roll = math.atan2(m.entry(1, 0), m.entry(1, 1));
    } else {
      // Gimbal lock
      pitch = m.entry(1, 2) <= -0.999 ? math.pi / 2 : -math.pi / 2;
      yaw = math.atan2(-m.entry(2, 0), m.entry(0, 0));
      roll = 0.0;
    }

    _euler = Vector3(
      pitch * 180.0 / math.pi,
      yaw * 180.0 / math.pi,
      roll * 180.0 / math.pi,
    );
  }

  // --- Inspector Metadata ---

  @override
  String get displayName => 'Transform 3D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<Vector3>(
          name: 'position',
          label: 'Position',
          type: InspectableType.vector3,
          getter: () => _position,
          setter: (val) => position = val,
          step: 0.1,
          tooltip: 'Local position in 3D space',
        ),
        InspectableProperty<Vector3>(
          name: 'euler',
          label: 'Rotation',
          type: InspectableType.vector3,
          getter: () => _euler,
          setter: (val) => euler = val,
          step: 1.0,
          tooltip: 'Local rotation angles in degrees (X, Y, Z)',
        ),
        InspectableProperty<Vector3>(
          name: 'scale',
          label: 'Scale',
          type: InspectableType.vector3,
          getter: () => _scale,
          setter: (val) => scale = val,
          step: 0.05,
          tooltip: 'Local scale multipliers along X, Y, Z',
        ),
      ];

  // --- Serialization ---

  @override
  Map<String, dynamic> toJson() {
    return {
      'position': [_position.x, _position.y, _position.z],
      'rotation': [_rotation.x, _rotation.y, _rotation.z, _rotation.w],
      'euler': [_euler.x, _euler.y, _euler.z],
      'scale': [_scale.x, _scale.y, _scale.z],
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    if (json.containsKey('position')) {
      final p = json['position'] as List<dynamic>;
      _position = Vector3(
        (p[0] as num).toDouble(),
        (p[1] as num).toDouble(),
        (p[2] as num).toDouble(),
      );
    }
    if (json.containsKey('rotation')) {
      final r = json['rotation'] as List<dynamic>;
      _rotation = Quaternion(
        (r[0] as num).toDouble(),
        (r[1] as num).toDouble(),
        (r[2] as num).toDouble(),
        (r[3] as num).toDouble(),
      );
    }
    if (json.containsKey('euler')) {
      final e = json['euler'] as List<dynamic>;
      _euler = Vector3(
        (e[0] as num).toDouble(),
        (e[1] as num).toDouble(),
        (e[2] as num).toDouble(),
      );
    }
    if (json.containsKey('scale')) {
      final s = json['scale'] as List<dynamic>;
      _scale = Vector3(
        (s[0] as num).toDouble(),
        (s[1] as num).toDouble(),
        (s[2] as num).toDouble(),
      );
    }
    setDirty();
  }

  @override
  Transform3DComponent clone() {
    return Transform3DComponent(
      position: _position.clone(),
      rotation: _rotation.clone(),
      euler: _euler.clone(),
      scale: _scale.clone(),
    );
  }
}

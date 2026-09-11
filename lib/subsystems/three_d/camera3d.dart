import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import '../../core/component.dart';
import '../../core/inspectable.dart';

/// Supported camera projection types.
enum CameraProjection {
  perspective,
  orthographic,
}

/// 3D Ray for mouse picking and physics casting.
class Ray3D {
  final Vector3 origin;
  final Vector3 direction;

  Ray3D(this.origin, Vector3 dir) : direction = dir.normalized();

  Vector3 getPoint(double t) => origin + direction * t;
}

/// 3D Camera component in Ember Engine.
class CameraComponent extends EmberComponent {
  double _fov; // degrees
  double _near;
  double _far;
  double _orthoSize;
  CameraProjection _projection;
  bool _isMainCamera;

  CameraComponent({
    this._fov = 60.0,
    this._near = 0.1,
    this._far = 1000.0,
    this._orthoSize = 5.0,
    this._projection = CameraProjection.perspective,
    this._isMainCamera = true,
  });

  double get fov => _fov;
  set fov(double val) {
    _fov = val.clamp(10.0, 120.0);
    notifyListeners();
  }

  double get near => _near;
  set near(double val) {
    _near = val.clamp(0.01, 100.0);
    notifyListeners();
  }

  double get far => _far;
  set far(double val) {
    _far = val.clamp(10.0, 10000.0);
    notifyListeners();
  }

  double get orthoSize => _orthoSize;
  set orthoSize(double val) {
    _orthoSize = val.clamp(0.5, 100.0);
    notifyListeners();
  }

  CameraProjection get projection => _projection;
  set projection(CameraProjection val) {
    _projection = val;
    notifyListeners();
  }

  bool get isMainCamera => _isMainCamera;
  set isMainCamera(bool val) {
    _isMainCamera = val;
    notifyListeners();
  }

  /// Calculates the view matrix given camera world position and rotation.
  Matrix4 getViewMatrix(Vector3 position, Quaternion rotation) {
    final eye = position;
    // Standard right-handed view direction (-Z is forward)
    final forward = rotation.rotate(Vector3(0, 0, -1));
    final up = rotation.rotate(Vector3(0, 1, 0));
    final target = eye + forward;

    return makeViewMatrix(eye, target, up);
  }

  /// Calculates the projection matrix for a given viewport aspect ratio.
  Matrix4 getProjectionMatrix(double aspectRatio) {
    if (_projection == CameraProjection.perspective) {
      final fovRad = _fov * math.pi / 180.0;
      return makePerspectiveMatrix(fovRad, aspectRatio, _near, _far);
    } else {
      final halfH = _orthoSize * 0.5;
      final halfW = halfH * aspectRatio;
      return makeOrthographicMatrix(-halfW, halfW, -halfH, halfH, _near, _far);
    }
  }

  /// Casts a ray from screen coordinates into the 3D world.
  Ray3D screenPointToRay(
    Offset screenPoint,
    Size viewportSize,
    Vector3 camPos,
    Quaternion camRot,
  ) {
    final ndcX = (2.0 * screenPoint.dx / viewportSize.width) - 1.0;
    final ndcY = 1.0 - (2.0 * screenPoint.dy / viewportSize.height);

    final aspect = viewportSize.width / viewportSize.height;
    final proj = getProjectionMatrix(aspect);
    final view = getViewMatrix(camPos, camRot);

    final viewProj = proj * view;
    final invViewProj = Matrix4.inverted(viewProj);

    final nearPointNdc = Vector4(ndcX, ndcY, -1.0, 1.0);
    final farPointNdc = Vector4(ndcX, ndcY, 1.0, 1.0);

    final nearWorld = invViewProj * nearPointNdc;
    final farWorld = invViewProj * farPointNdc;

    final nearPos = Vector3(
      nearWorld.x / nearWorld.w,
      nearWorld.y / nearWorld.w,
      nearWorld.z / nearWorld.w,
    );
    final farPos = Vector3(
      farWorld.x / farWorld.w,
      farWorld.y / farWorld.w,
      farWorld.z / farWorld.w,
    );

    final dir = (farPos - nearPos).normalized();
    return Ray3D(nearPos, dir);
  }

  @override
  String get displayName => 'Camera';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<double>(
          name: 'fov',
          label: 'Field of View',
          type: InspectableType.number,
          getter: () => _fov,
          setter: (val) => fov = val,
          min: 15.0,
          max: 120.0,
          step: 1.0,
          tooltip: 'Perspective field of view in degrees',
        ),
        InspectableProperty<double>(
          name: 'near',
          label: 'Near Clip Plane',
          type: InspectableType.number,
          getter: () => _near,
          setter: (val) => near = val,
          min: 0.01,
          max: 10.0,
          step: 0.05,
        ),
        InspectableProperty<double>(
          name: 'far',
          label: 'Far Clip Plane',
          type: InspectableType.number,
          getter: () => _far,
          setter: (val) => far = val,
          min: 10.0,
          max: 5000.0,
          step: 10.0,
        ),
        InspectableProperty<CameraProjection>(
          name: 'projection',
          label: 'Projection',
          type: InspectableType.options,
          getter: () => _projection,
          setter: (val) => projection = val,
          options: CameraProjection.values.map((p) => p.name).toList(),
        ),
        InspectableProperty<bool>(
          name: 'isMainCamera',
          label: 'Main Camera',
          type: InspectableType.boolean,
          getter: () => _isMainCamera,
          setter: (val) => isMainCamera = val,
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'fov': _fov,
      'near': _near,
      'far': _far,
      'orthoSize': _orthoSize,
      'projection': _projection.name,
      'isMainCamera': _isMainCamera,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    _fov = (json['fov'] as num?)?.toDouble() ?? 60.0;
    _near = (json['near'] as num?)?.toDouble() ?? 0.1;
    _far = (json['far'] as num?)?.toDouble() ?? 1000.0;
    _orthoSize = (json['orthoSize'] as num?)?.toDouble() ?? 5.0;
    final pName = json['projection'] as String? ?? 'perspective';
    _projection = CameraProjection.values.firstWhere(
      (p) => p.name == pName,
      orElse: () => CameraProjection.perspective,
    );
    _isMainCamera = json['isMainCamera'] as bool? ?? true;
    notifyListeners();
  }

  @override
  CameraComponent clone() {
    return CameraComponent(
      fov: _fov,
      near: _near,
      far: _far,
      orthoSize: _orthoSize,
      projection: _projection,
      isMainCamera: _isMainCamera,
    );
  }
}

/// Orbit Camera Controller for 3D Viewport navigation (Orbit, Pan, Zoom).
class OrbitCameraController {
  Vector3 target = Vector3.zero();
  double distance = 8.0;
  double azimuth = 0.6; // yaw (radians)
  double elevation = 0.4; // pitch (radians)

  void orbit(double deltaX, double deltaY) {
    azimuth -= deltaX * 0.01;
    elevation = (elevation + deltaY * 0.01).clamp(-math.pi * 0.48, math.pi * 0.48);
  }

  void pan(double deltaX, double deltaY) {
    final forward = getForward();
    final right = forward.cross(Vector3(0, 1, 0)).normalized();
    final up = right.cross(forward).normalized();

    final factor = distance * 0.002;
    target -= right * (deltaX * factor) - up * (deltaY * factor);
  }

  void zoom(double factor) {
    distance = (distance * factor).clamp(0.5, 200.0);
  }

  void focusOn(Vector3 newTarget, [double? newDistance]) {
    target = newTarget.clone();
    if (newDistance != null) {
      distance = newDistance;
    }
  }

  Vector3 getPosition() {
    final cosElev = math.cos(elevation);
    final sinElev = math.sin(elevation);
    final cosAzim = math.cos(azimuth);
    final sinAzim = math.sin(azimuth);

    final offset = Vector3(
      distance * cosElev * sinAzim,
      distance * sinElev,
      distance * cosElev * cosAzim,
    );
    return target + offset;
  }

  Quaternion getRotation() {
    final pos = getPosition();
    final forward = (target - pos).normalized();
    final right = forward.cross(Vector3(0, 1, 0)).normalized();
    final up = right.cross(forward).normalized();

    final rotM = Matrix3(
      right.x, up.x, -forward.x,
      right.y, up.y, -forward.y,
      right.z, up.z, -forward.z,
    );
    return Quaternion.fromRotation(rotM);
  }

  Vector3 getForward() {
    final pos = getPosition();
    return (target - pos).normalized();
  }
}

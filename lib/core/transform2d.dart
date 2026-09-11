import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';
import 'component.dart';
import 'inspectable.dart';

/// Alignment anchor for 2D components, corresponding to standard 2D / Flame anchors.
enum EmberAnchor {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight;

  /// Returns normalized offset (0.0 to 1.0) for this anchor.
  Vector2 get normalizedOffset {
    switch (this) {
      case EmberAnchor.topLeft:
        return Vector2(0.0, 0.0);
      case EmberAnchor.topCenter:
        return Vector2(0.5, 0.0);
      case EmberAnchor.topRight:
        return Vector2(1.0, 0.0);
      case EmberAnchor.centerLeft:
        return Vector2(0.0, 0.5);
      case EmberAnchor.center:
        return Vector2(0.5, 0.5);
      case EmberAnchor.centerRight:
        return Vector2(1.0, 0.5);
      case EmberAnchor.bottomLeft:
        return Vector2(0.0, 1.0);
      case EmberAnchor.bottomCenter:
        return Vector2(0.5, 1.0);
      case EmberAnchor.bottomRight:
        return Vector2(1.0, 1.0);
    }
  }

  String get displayName {
    switch (this) {
      case EmberAnchor.topLeft:
        return 'Top Left';
      case EmberAnchor.topCenter:
        return 'Top Center';
      case EmberAnchor.topRight:
        return 'Top Right';
      case EmberAnchor.centerLeft:
        return 'Center Left';
      case EmberAnchor.center:
        return 'Center';
      case EmberAnchor.centerRight:
        return 'Center Right';
      case EmberAnchor.bottomLeft:
        return 'Bottom Left';
      case EmberAnchor.bottomCenter:
        return 'Bottom Center';
      case EmberAnchor.bottomRight:
        return 'Bottom Right';
    }
  }
}

/// 2D Transform component in the Ember Engine ECS architecture.
///
/// Handles 2D positioning, rotation (radians/degrees), scaling, size, and anchor alignment.
class Transform2DComponent extends EmberComponent {
  Vector2 _position;
  double _rotation; // radians
  Vector2 _scale;
  Vector2 _size;
  EmberAnchor _anchor;
  int _zIndex;

  Transform2DComponent({
    Vector2? position,
    this._rotation = 0.0,
    Vector2? scale,
    Vector2? size,
    this._anchor = EmberAnchor.topLeft,
    this._zIndex = 0,
  })  : _position = position ?? Vector2.zero(),
        _scale = scale ?? Vector2(1.0, 1.0),
        _size = size ?? Vector2(32.0, 32.0);

  // --- Getters & Setters ---

  Vector2 get position => _position;
  set position(Vector2 val) {
    _position = val;
    notifyListeners();
  }

  double get rotation => _rotation;
  set rotation(double radians) {
    _rotation = radians;
    notifyListeners();
  }

  double get rotationDegrees => _rotation * 180.0 / math.pi;
  set rotationDegrees(double degrees) {
    _rotation = degrees * math.pi / 180.0;
    notifyListeners();
  }

  Vector2 get scale => _scale;
  set scale(Vector2 val) {
    _scale = val;
    notifyListeners();
  }

  Vector2 get size => _size;
  set size(Vector2 val) {
    _size = val;
    notifyListeners();
  }

  EmberAnchor get anchor => _anchor;
  set anchor(EmberAnchor val) {
    _anchor = val;
    notifyListeners();
  }

  int get zIndex => _zIndex;
  set zIndex(int val) {
    _zIndex = val;
    notifyListeners();
  }

  // --- World Calculations ---

  Vector2 get worldPosition {
    final parentTransform = entity?.parent?.getComponent<Transform2DComponent>();
    if (parentTransform != null) {
      final parentWorld = parentTransform.worldPosition;
      final parentRot = parentTransform.worldRotation;
      final parentScale = parentTransform.worldScale;

      // Scale then rotate local position
      final scaledX = _position.x * parentScale.x;
      final scaledY = _position.y * parentScale.y;

      final cosR = math.cos(parentRot);
      final sinR = math.sin(parentRot);

      final rotatedX = scaledX * cosR - scaledY * sinR;
      final rotatedY = scaledX * sinR + scaledY * cosR;

      return Vector2(parentWorld.x + rotatedX, parentWorld.y + rotatedY);
    }
    return _position.clone();
  }

  double get worldRotation {
    final parentTransform = entity?.parent?.getComponent<Transform2DComponent>();
    if (parentTransform != null) {
      return parentTransform.worldRotation + _rotation;
    }
    return _rotation;
  }

  Vector2 get worldScale {
    final parentTransform = entity?.parent?.getComponent<Transform2DComponent>();
    if (parentTransform != null) {
      final ps = parentTransform.worldScale;
      return Vector2(ps.x * _scale.x, ps.y * _scale.y);
    }
    return _scale.clone();
  }

  /// Calculates top-left position offset adjusted by the current anchor.
  Vector2 get anchorOffset {
    final norm = _anchor.normalizedOffset;
    return Vector2(_size.x * norm.x * _scale.x, _size.y * norm.y * _scale.y);
  }

  // --- Inspector Metadata ---

  @override
  String get displayName => 'Transform 2D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<Vector2>(
          name: 'position',
          label: 'Position',
          type: InspectableType.vector2,
          getter: () => _position,
          setter: (val) => position = val,
          step: 1.0,
          tooltip: '2D pixel coordinates (X, Y)',
        ),
        InspectableProperty<double>(
          name: 'rotation',
          label: 'Angle (deg)',
          type: InspectableType.number,
          getter: () => rotationDegrees,
          setter: (val) => rotationDegrees = val,
          step: 1.0,
          tooltip: 'Rotation angle in degrees',
        ),
        InspectableProperty<Vector2>(
          name: 'size',
          label: 'Size',
          type: InspectableType.vector2,
          getter: () => _size,
          setter: (val) => size = val,
          step: 1.0,
          tooltip: 'Dimensions in pixels (Width, Height)',
        ),
        InspectableProperty<Vector2>(
          name: 'scale',
          label: 'Scale',
          type: InspectableType.vector2,
          getter: () => _scale,
          setter: (val) => scale = val,
          step: 0.1,
          tooltip: 'Scale factor (X, Y)',
        ),
        InspectableProperty<EmberAnchor>(
          name: 'anchor',
          label: 'Anchor',
          type: InspectableType.anchor,
          getter: () => _anchor,
          setter: (val) => anchor = val,
          options: EmberAnchor.values.map((a) => a.name).toList(),
          tooltip: 'Origin anchor point',
        ),
        InspectableProperty<int>(
          name: 'zIndex',
          label: 'Z-Index',
          type: InspectableType.integer,
          getter: () => _zIndex,
          setter: (val) => zIndex = val,
          step: 1.0,
          tooltip: 'Rendering order layer',
        ),
      ];

  // --- Serialization ---

  @override
  Map<String, dynamic> toJson() {
    return {
      'position': [_position.x, _position.y],
      'rotation': _rotation,
      'scale': [_scale.x, _scale.y],
      'size': [_size.x, _size.y],
      'anchor': _anchor.name,
      'zIndex': _zIndex,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    if (json.containsKey('position')) {
      final p = json['position'] as List<dynamic>;
      _position = Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble());
    }
    if (json.containsKey('rotation')) {
      _rotation = (json['rotation'] as num).toDouble();
    }
    if (json.containsKey('scale')) {
      final s = json['scale'] as List<dynamic>;
      _scale = Vector2((s[0] as num).toDouble(), (s[1] as num).toDouble());
    }
    if (json.containsKey('size')) {
      final sz = json['size'] as List<dynamic>;
      _size = Vector2((sz[0] as num).toDouble(), (sz[1] as num).toDouble());
    }
    if (json.containsKey('anchor')) {
      final aName = json['anchor'] as String;
      _anchor = EmberAnchor.values.firstWhere(
        (a) => a.name == aName,
        orElse: () => EmberAnchor.topLeft,
      );
    }
    if (json.containsKey('zIndex')) {
      _zIndex = json['zIndex'] as int? ?? 0;
    }
    notifyListeners();
  }

  @override
  Transform2DComponent clone() {
    return Transform2DComponent(
      position: _position.clone(),
      rotation: _rotation,
      scale: _scale.clone(),
      size: _size.clone(),
      anchor: _anchor,
      zIndex: _zIndex,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import 'material.dart';
import 'mesh.dart';
import 'primitives.dart';
import 'camera3d.dart';
import 'lighting.dart';

/// Available procedural geometric primitives for MeshRenderer3D.
enum MeshPrimitiveType {
  cube,
  sphere,
  plane,
  cylinder,
  pyramid,
  custom,
}

/// 3D Mesh Renderer component.
///
/// Holds the 3D mesh geometry and material for rendering in the 3D viewport.
class MeshRenderer3DComponent extends EmberComponent {
  MeshPrimitiveType _primitiveType;
  late Material3D _material;
  late Mesh3D _mesh;
  bool _castShadows;
  bool _receiveShadows;

  MeshRenderer3DComponent({
    this._primitiveType = MeshPrimitiveType.cube,
    Material3D? material,
    Mesh3D? customMesh,
    this._castShadows = true,
    this._receiveShadows = true,
  }) {
    _material = material ?? Material3D();
    if (customMesh != null) {
      _mesh = customMesh;
      _primitiveType = MeshPrimitiveType.custom;
    } else {
      _rebuildMesh();
    }
  }

  MeshPrimitiveType get primitiveType => _primitiveType;
  set primitiveType(MeshPrimitiveType type) {
    if (_primitiveType == type) return;
    _primitiveType = type;
    _rebuildMesh();
    notifyListeners();
  }

  Material3D get material => _material;
  set material(Material3D mat) {
    _material = mat;
    notifyListeners();
  }

  Mesh3D get mesh => _mesh;
  set mesh(Mesh3D newMesh) {
    _mesh = newMesh;
    _primitiveType = MeshPrimitiveType.custom;
    notifyListeners();
  }

  bool get castShadows => _castShadows;
  set castShadows(bool val) {
    _castShadows = val;
    notifyListeners();
  }

  bool get receiveShadows => _receiveShadows;
  set receiveShadows(bool val) {
    _receiveShadows = val;
    notifyListeners();
  }

  void _rebuildMesh() {
    switch (_primitiveType) {
      case MeshPrimitiveType.cube:
        _mesh = MeshPrimitives.createCube();
        break;
      case MeshPrimitiveType.sphere:
        _mesh = MeshPrimitives.createSphere();
        break;
      case MeshPrimitiveType.plane:
        _mesh = MeshPrimitives.createPlane();
        break;
      case MeshPrimitiveType.cylinder:
        _mesh = MeshPrimitives.createCylinder();
        break;
      case MeshPrimitiveType.pyramid:
        _mesh = MeshPrimitives.createPyramid();
        break;
      case MeshPrimitiveType.custom:
        // Keep existing custom mesh
        break;
    }
  }

  @override
  String get displayName => 'Mesh Renderer 3D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<MeshPrimitiveType>(
          name: 'primitiveType',
          label: 'Primitive Mesh',
          type: InspectableType.options,
          getter: () => _primitiveType,
          setter: (val) => primitiveType = val,
          options: MeshPrimitiveType.values.map((p) => p.name).toList(),
          tooltip: 'Procedural primitive or custom 3D mesh',
        ),
        InspectableProperty<Color>(
          name: 'color',
          label: 'Albedo Color',
          type: InspectableType.color,
          getter: () => _material.color,
          setter: (val) {
            _material.color = val;
            notifyListeners();
          },
        ),
        InspectableProperty<double>(
          name: 'roughness',
          label: 'Roughness',
          type: InspectableType.number,
          getter: () => _material.roughness,
          setter: (val) {
            _material.roughness = val;
            notifyListeners();
          },
          min: 0.0,
          max: 1.0,
          step: 0.05,
        ),
        InspectableProperty<double>(
          name: 'metallic',
          label: 'Metallic',
          type: InspectableType.number,
          getter: () => _material.metallic,
          setter: (val) {
            _material.metallic = val;
            notifyListeners();
          },
          min: 0.0,
          max: 1.0,
          step: 0.05,
        ),
        InspectableProperty<bool>(
          name: 'wireframe',
          label: 'Wireframe Mode',
          type: InspectableType.boolean,
          getter: () => _material.wireframe,
          setter: (val) {
            _material.wireframe = val;
            notifyListeners();
          },
        ),
        InspectableProperty<bool>(
          name: 'castShadows',
          label: 'Cast Shadows',
          type: InspectableType.boolean,
          getter: () => _castShadows,
          setter: (val) => castShadows = val,
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'primitiveType': _primitiveType.name,
      'material': _material.toJson(),
      'castShadows': _castShadows,
      'receiveShadows': _receiveShadows,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    final pName = json['primitiveType'] as String? ?? 'cube';
    _primitiveType = MeshPrimitiveType.values.firstWhere(
      (p) => p.name == pName,
      orElse: () => MeshPrimitiveType.cube,
    );
    if (json.containsKey('material')) {
      _material = Material3D.fromJson(json['material'] as Map<String, dynamic>);
    }
    _castShadows = json['castShadows'] as bool? ?? true;
    _receiveShadows = json['receiveShadows'] as bool? ?? true;
    _rebuildMesh();
    notifyListeners();
  }

  @override
  MeshRenderer3DComponent clone() {
    return MeshRenderer3DComponent(
      primitiveType: _primitiveType,
      material: _material.clone(),
      customMesh: _primitiveType == MeshPrimitiveType.custom ? _mesh : null,
      castShadows: _castShadows,
      receiveShadows: _receiveShadows,
    );
  }
}

/// 3D Collider shapes.
enum Collider3DType {
  box,
  sphere,
  capsule,
}

/// 3D Collider component for physics and raycast hit detection.
class Collider3DComponent extends EmberComponent {
  Collider3DType _type;
  Vector3 _size;
  Vector3 _center;
  bool _isTrigger;

  Collider3DComponent({
    this.type = Collider3DType.box,
    Vector3? size,
    Vector3? center,
    this.isTrigger = false,
  })  : _type = type,
        _size = size ?? Vector3(1.0, 1.0, 1.0),
        _center = center ?? Vector3.zero(),
        _isTrigger = isTrigger;

  Collider3DType type;
  bool isTrigger;

  Vector3 get size => _size;
  set size(Vector3 val) {
    _size = val;
    notifyListeners();
  }

  Vector3 get center => _center;
  set center(Vector3 val) {
    _center = val;
    notifyListeners();
  }

  @override
  String get displayName => 'Collider 3D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<Collider3DType>(
          name: 'type',
          label: 'Collider Shape',
          type: InspectableType.options,
          getter: () => _type,
          setter: (val) {
            _type = val;
            notifyListeners();
          },
          options: Collider3DType.values.map((c) => c.name).toList(),
        ),
        InspectableProperty<Vector3>(
          name: 'size',
          label: 'Extents / Size',
          type: InspectableType.vector3,
          getter: () => _size,
          setter: (val) => size = val,
          step: 0.1,
        ),
        InspectableProperty<Vector3>(
          name: 'center',
          label: 'Offset Center',
          type: InspectableType.vector3,
          getter: () => _center,
          setter: (val) => center = val,
          step: 0.1,
        ),
        InspectableProperty<bool>(
          name: 'isTrigger',
          label: 'Is Trigger',
          type: InspectableType.boolean,
          getter: () => _isTrigger,
          setter: (val) {
            _isTrigger = val;
            notifyListeners();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': _type.name,
      'size': [_size.x, _size.y, _size.z],
      'center': [_center.x, _center.y, _center.z],
      'isTrigger': _isTrigger,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    final tName = json['type'] as String? ?? 'box';
    _type = Collider3DType.values.firstWhere(
      (c) => c.name == tName,
      orElse: () => Collider3DType.box,
    );
    if (json.containsKey('size')) {
      final s = json['size'] as List<dynamic>;
      _size = Vector3((s[0] as num).toDouble(), (s[1] as num).toDouble(), (s[2] as num).toDouble());
    }
    if (json.containsKey('center')) {
      final c = json['center'] as List<dynamic>;
      _center = Vector3((c[0] as num).toDouble(), (c[1] as num).toDouble(), (c[2] as num).toDouble());
    }
    _isTrigger = json['isTrigger'] as bool? ?? false;
    notifyListeners();
  }

  @override
  Collider3DComponent clone() {
    return Collider3DComponent(
      type: _type,
      size: _size.clone(),
      center: _center.clone(),
      isTrigger: _isTrigger,
    );
  }
}

/// 3D RigidBody component for dynamics simulation.
class RigidBody3DComponent extends EmberComponent {
  double _mass;
  double _drag;
  bool _useGravity;
  bool _isKinematic;
  Vector3 _velocity;

  RigidBody3DComponent({
    this.mass = 1.0,
    this.drag = 0.05,
    this.useGravity = true,
    this.isKinematic = false,
    Vector3? velocity,
  })  : _mass = mass,
        _drag = drag,
        _useGravity = useGravity,
        _isKinematic = isKinematic,
        _velocity = velocity ?? Vector3.zero();

  double mass;
  double drag;
  bool useGravity;
  bool isKinematic;

  Vector3 get velocity => _velocity;
  set velocity(Vector3 val) {
    _velocity = val;
    notifyListeners();
  }

  @override
  String get displayName => 'RigidBody 3D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<double>(
          name: 'mass',
          label: 'Mass (kg)',
          type: InspectableType.number,
          getter: () => _mass,
          setter: (val) {
            _mass = val.clamp(0.01, 100000.0);
            notifyListeners();
          },
          min: 0.1,
          max: 100.0,
          step: 0.5,
        ),
        InspectableProperty<double>(
          name: 'drag',
          label: 'Linear Drag',
          type: InspectableType.number,
          getter: () => _drag,
          setter: (val) {
            _drag = val.clamp(0.0, 10.0);
            notifyListeners();
          },
          min: 0.0,
          max: 1.0,
          step: 0.05,
        ),
        InspectableProperty<bool>(
          name: 'useGravity',
          label: 'Use Gravity',
          type: InspectableType.boolean,
          getter: () => _useGravity,
          setter: (val) {
            _useGravity = val;
            notifyListeners();
          },
        ),
        InspectableProperty<bool>(
          name: 'isKinematic',
          label: 'Is Kinematic',
          type: InspectableType.boolean,
          getter: () => _isKinematic,
          setter: (val) {
            _isKinematic = val;
            notifyListeners();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'mass': _mass,
      'drag': _drag,
      'useGravity': _useGravity,
      'isKinematic': _isKinematic,
      'velocity': [_velocity.x, _velocity.y, _velocity.z],
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    _mass = (json['mass'] as num?)?.toDouble() ?? 1.0;
    _drag = (json['drag'] as num?)?.toDouble() ?? 0.05;
    _useGravity = json['useGravity'] as bool? ?? true;
    _isKinematic = json['isKinematic'] as bool? ?? false;
    if (json.containsKey('velocity')) {
      final v = json['velocity'] as List<dynamic>;
      _velocity = Vector3((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble());
    }
    notifyListeners();
  }

  @override
  RigidBody3DComponent clone() {
    return RigidBody3DComponent(
      mass: _mass,
      drag: _drag,
      useGravity: _useGravity,
      isKinematic: _isKinematic,
      velocity: _velocity.clone(),
    );
  }
}

/// Registers all 3D engine components into the central ComponentRegistry.
void register3DComponents() {
  ComponentRegistry.register('Mesh Renderer 3D', (json) {
    final comp = MeshRenderer3DComponent();
    comp.fromJson(json);
    return comp;
  });

  ComponentRegistry.register('Camera', (json) {
    final comp = CameraComponent();
    comp.fromJson(json);
    return comp;
  });

  ComponentRegistry.register('Light', (json) {
    final comp = LightComponent();
    comp.fromJson(json);
    return comp;
  });

  ComponentRegistry.register('Collider 3D', (json) {
    final comp = Collider3DComponent();
    comp.fromJson(json);
    return comp;
  });

  ComponentRegistry.register('RigidBody 3D', (json) {
    final comp = RigidBody3DComponent();
    comp.fromJson(json);
    return comp;
  });
}

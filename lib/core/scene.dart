import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';
import 'entity.dart';
import 'transform3d.dart';
import 'transform2d.dart';
import 'game_script.dart';

/// Represents an entire game scene in Ember Engine.
///
/// Holds the hierarchy of root entities, propagates frame updates,
/// and handles serialization to/from JSON.
class EmberScene with ChangeNotifier {
  String name;
  final List<EmberEntity> _rootEntities = [];

  EmberScene({
    this.name = 'New Scene',
    List<EmberEntity>? entities,
  }) {
    if (entities != null) {
      for (final e in entities) {
        addEntity(e);
      }
    }
  }

  /// List of top-level root entities in the scene hierarchy.
  List<EmberEntity> get rootEntities => List.unmodifiable(_rootEntities);

  /// Flattened list of all entities in the scene (roots and all descendants).
  List<EmberEntity> get allEntities {
    final list = <EmberEntity>[];
    for (final root in _rootEntities) {
      list.add(root);
      list.addAll(root.getAllDescendants());
    }
    return list;
  }

  /// Adds a root entity to the scene.
  void addEntity(EmberEntity entity) {
    if (!_rootEntities.contains(entity)) {
      _rootEntities.add(entity);
      entity.addListener(notifyListeners);
      notifyListeners();
    }
  }

  /// Removes an entity from the scene.
  bool removeEntity(EmberEntity entity) {
    if (_rootEntities.remove(entity)) {
      entity.removeListener(notifyListeners);
      entity.destroy();
      notifyListeners();
      return true;
    }
    // Check if it's a child entity
    final parent = entity.parent;
    if (parent != null) {
      parent.removeChild(entity);
      entity.destroy();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Finds an entity by its unique ID.
  EmberEntity? findEntityById(String id) {
    for (final e in allEntities) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Finds an entity by its display name.
  EmberEntity? findEntityByName(String name) {
    for (final e in allEntities) {
      if (e.name == name) return e;
    }
    return null;
  }

  // --- Lifecycle Dispatch ---

  void awake() {
    for (final entity in _rootEntities) {
      entity.awake();
    }
  }

  void start() {
    for (final entity in _rootEntities) {
      entity.start();
    }
  }

  void update(double dt) {
    for (final entity in _rootEntities) {
      entity.update(dt);
    }
  }

  void fixedUpdate(double fixedDt) {
    for (final entity in _rootEntities) {
      entity.fixedUpdate(fixedDt);
    }
  }

  void destroy() {
    for (final entity in List<EmberEntity>.from(_rootEntities)) {
      entity.removeListener(notifyListeners);
      entity.destroy();
    }
    _rootEntities.clear();
    notifyListeners();
  }

  // --- Serialization ---

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'entities': _rootEntities.map((e) => e.toJson()).toList(),
    };
  }

  factory EmberScene.fromJson(Map<String, dynamic> json) {
    _ensureCoreComponentsRegistered();

    final scene = EmberScene(
      name: json['name'] as String? ?? 'Untitled Scene',
    );

    final rawEntities = json['entities'] as List<dynamic>? ?? [];
    for (final rawEnt in rawEntities) {
      final entity = EmberEntity.fromJson(rawEnt as Map<String, dynamic>);
      scene.addEntity(entity);
    }

    return scene;
  }

  /// Clones the entire scene with all entities and components.
  EmberScene clone({String? newName}) {
    final copy = EmberScene(name: newName ?? '$name (Copy)');
    for (final root in _rootEntities) {
      copy.addEntity(root.clone());
    }
    return copy;
  }

  // --- Factory Templates ---

  /// Creates a starter 3D scene with camera, light, floor plane, and a cube.
  static EmberScene createDefault3DScene() {
    _ensureCoreComponentsRegistered();

    final scene = EmberScene(name: 'Level_01 (3D)');

    // 1. Main Camera
    final camera = EmberEntity(name: 'Main Camera');
    camera.addComponent(Transform3DComponent(
      position: Vector3(0.0, 3.0, 7.0),
      euler: Vector3(-20.0, 0.0, 0.0),
    ));
    scene.addEntity(camera);

    // 2. Directional Light (Sun)
    final sun = EmberEntity(name: 'Directional Light');
    sun.addComponent(Transform3DComponent(
      position: Vector3(5.0, 10.0, 5.0),
      euler: Vector3(45.0, -30.0, 0.0),
    ));
    scene.addEntity(sun);

    // 3. Ground Plane
    final ground = EmberEntity(name: 'Ground Plane');
    ground.addComponent(Transform3DComponent(
      position: Vector3(0.0, -0.5, 0.0),
      scale: Vector3(10.0, 0.1, 10.0),
    ));
    scene.addEntity(ground);

    // 4. Default Hero Cube
    final cube = EmberEntity(name: 'Hero Cube');
    cube.addComponent(Transform3DComponent(
      position: Vector3(0.0, 1.0, 0.0),
      scale: Vector3(1.5, 1.5, 1.5),
      euler: Vector3(15.0, 30.0, 0.0),
    ));
    scene.addEntity(cube);

    return scene;
  }

  /// Creates a starter 2D scene with player, tilemap root, and camera.
  static EmberScene createDefault2DScene() {
    _ensureCoreComponentsRegistered();

    final scene = EmberScene(name: 'Level_01 (2D Flame)');

    // 1. Player Character
    final player = EmberEntity(name: 'PlayerCharacter');
    player.addComponent(Transform2DComponent(
      position: Vector2(160.0, 240.0),
      size: Vector2(48.0, 48.0),
      anchor: EmberAnchor.center,
    ));
    scene.addEntity(player);

    // 2. World2D / TileMap
    final world = EmberEntity(name: 'World2D');
    world.addComponent(Transform2DComponent(
      position: Vector2(0.0, 0.0),
      size: Vector2(800.0, 600.0),
    ));
    scene.addEntity(world);

    // 3. Enemy Spawner
    final spawner = EmberEntity(name: 'EnemySpawner');
    spawner.addComponent(Transform2DComponent(
      position: Vector2(320.0, 120.0),
      size: Vector2(32.0, 32.0),
      anchor: EmberAnchor.center,
    ));
    scene.addEntity(spawner);

    return scene;
  }

  static bool _registered = false;
  static void _ensureCoreComponentsRegistered() {
    if (_registered) return;
    _registered = true;

    ComponentRegistry.register('Transform 3D', (json) {
      final comp = Transform3DComponent();
      comp.fromJson(json);
      return comp;
    });

    ComponentRegistry.register('Transform 2D', (json) {
      final comp = Transform2DComponent();
      comp.fromJson(json);
      return comp;
    });

    ComponentRegistry.register('Script Component', (json) {
      final comp = ScriptComponent();
      comp.fromJson(json);
      return comp;
    });
  }
}

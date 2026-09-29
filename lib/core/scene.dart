import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'entity.dart';
import 'transform3d.dart';
import 'transform2d.dart';
import 'game_script.dart';
import 'gameplay_scripts.dart';
import '../subsystems/audio/audio_component.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/physics/character_controller2d.dart';
import '../subsystems/physics/character_controller3d.dart';
import '../subsystems/three_d/camera3d.dart';
import '../subsystems/three_d/components3d.dart';
import '../subsystems/three_d/lighting.dart';
import '../subsystems/three_d/material.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/parallax.dart';
import '../subsystems/two_d/sprite_animator.dart';
import '../subsystems/ui/ui_text.dart';
import '../templates/flappy_game.dart';
import '../templates/quest_game.dart';

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

  final List<EmberEntity> _pendingDestroy = [];

  /// True while the simulation is playing this scene. Entities added while
  /// running are awoken and started immediately (e.g. spawned bullets, pipes).
  bool isRunning = false;

  /// Adds a root entity to the scene.
  void addEntity(EmberEntity entity) {
    if (!_rootEntities.contains(entity)) {
      _rootEntities.add(entity);
      entity.bindScene(this);
      entity.addListener(notifyListeners);
      if (isRunning) {
        entity.awake();
        entity.start();
      }
      notifyListeners();
    }
  }

  /// Removes [entity] at the end of the current frame. Safe to call from a
  /// script, including on the script's own entity.
  void destroyLater(EmberEntity entity) {
    if (!_pendingDestroy.contains(entity)) _pendingDestroy.add(entity);
  }

  /// Applies every [destroyLater] request. Called by the engine after updates.
  void flushDestroyed() {
    if (_pendingDestroy.isEmpty) return;
    final batch = List<EmberEntity>.from(_pendingDestroy);
    _pendingDestroy.clear();
    for (final e in batch) {
      removeEntity(e);
    }
  }

  /// Removes an entity from the scene.
  bool removeEntity(EmberEntity entity) {
    if (_rootEntities.remove(entity)) {
      entity.removeListener(notifyListeners);
      entity.bindScene(null);
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

  /// Shorthand alias for findEntityById.
  EmberEntity? findById(String id) => findEntityById(id);

  /// Finds an entity by its display name.
  EmberEntity? findEntityByName(String name) {
    for (final e in allEntities) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// Shorthand alias for findEntityByName.
  EmberEntity? findByName(String name) => findEntityByName(name);

  /// Alias for findEntityByName.
  EmberEntity? getEntityByName(String name) => findEntityByName(name);

  // --- Lifecycle Dispatch ---
  // Each pass iterates a snapshot so scripts may add or remove entities mid-frame.

  void awake() {
    for (final entity in List<EmberEntity>.from(_rootEntities)) {
      entity.awake();
    }
  }

  void start() {
    for (final entity in List<EmberEntity>.from(_rootEntities)) {
      entity.start();
    }
  }

  void update(double dt) {
    for (final entity in List<EmberEntity>.from(_rootEntities)) {
      if (entity.scene == this) entity.update(dt);
    }
  }

  void fixedUpdate(double fixedDt) {
    for (final entity in List<EmberEntity>.from(_rootEntities)) {
      if (entity.scene == this) entity.fixedUpdate(fixedDt);
    }
  }

  void destroy() {
    isRunning = false;
    _pendingDestroy.clear();
    for (final entity in List<EmberEntity>.from(_rootEntities)) {
      entity.removeListener(notifyListeners);
      entity.bindScene(null);
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

  /// Creates a starter 3D scene with camera, light, ground plane, character controller, and cube.
  static EmberScene createDefault3DScene() {
    _ensureCoreComponentsRegistered();

    final scene = EmberScene(name: 'Level_01 (3D Arena)');

    // 1. Main Camera / Player
    final player = EmberEntity(name: 'Player (FPS)');
    player.addComponent(Transform3DComponent(
      position: Vector3(0.0, 0.9, 6.0),
      euler: Vector3(0.0, 0.0, 0.0),
    ));
    player.addComponent(CameraComponent());
    player.addComponent(CharacterController3DComponent(walkSpeed: 7.0, jumpForce: 7.0));
    player.addComponent(ScriptComponent(scriptName: 'FPS Player Controller'));
    player.addComponent(AudioSourceComponent(clip: 'laser', is3D: true));
    scene.addEntity(player);

    // 2. Directional Light (Sun)
    final sun = EmberEntity(name: 'Directional Light');
    sun.addComponent(Transform3DComponent(
      position: Vector3(5.0, 10.0, 5.0),
      euler: Vector3(-45.0, -30.0, 0.0), // negative pitch = pointing down
    ));
    sun.addComponent(LightComponent(type: LightType.directional, intensity: 1.2));
    scene.addEntity(sun);

    // 3. Ground Plane
    final ground = EmberEntity(name: 'Ground Plane');
    ground.addComponent(Transform3DComponent(
      position: Vector3(0.0, -0.1, 0.0),
      scale: Vector3(12.0, 0.2, 12.0),
    ));
    ground.addComponent(MeshRenderer3DComponent(
      primitiveType: MeshPrimitiveType.plane,
      material: Material3D(color: const Color(0xFF334155), roughness: 0.8),
    ));
    // Collider size is in local units and is multiplied by the transform scale.
    ground.addComponent(Collider3DComponent());
    scene.addEntity(ground);

    // 4. Interactive Hero Cube with Rotator script and particles
    final cube = EmberEntity(name: 'Hero Cube');
    cube.addComponent(Transform3DComponent(
      position: Vector3(0.0, 1.2, 0.0),
      scale: Vector3(1.4, 1.4, 1.4),
      euler: Vector3(15.0, 30.0, 0.0),
    ));
    cube.addComponent(MeshRenderer3DComponent(
      primitiveType: MeshPrimitiveType.cube,
      material: Material3D(color: const Color(0xFF6366F1), metallic: 0.3, roughness: 0.4),
    ));
    cube.addComponent(Collider3DComponent());
    cube.addComponent(RigidBody3DComponent(mass: 2.0));
    cube.addComponent(ScriptComponent(scriptName: 'Procedural Rotator'));
    cube.addComponent(ParticleEmitter3DComponent(preset: ParticlePreset.emberFire));
    scene.addEntity(cube);

    // 5. Crates to climb and shoot at
    for (final (i, pos) in [Vector3(-3.5, 0.5, 1.0), Vector3(-3.5, 1.5, 1.0), Vector3(3.5, 0.5, -1.5)].indexed) {
      final crate = EmberEntity(name: 'Crate_${i + 1}');
      crate.addComponent(Transform3DComponent(position: pos));
      crate.addComponent(MeshRenderer3DComponent(
        primitiveType: MeshPrimitiveType.cube,
        material: Material3D(color: const Color(0xFFB45309), roughness: 0.9),
      ));
      crate.addComponent(Collider3DComponent());
      crate.addComponent(ParticleEmitter3DComponent(preset: ParticlePreset.sparkBurst, spawnRate: 0.0));
      scene.addEntity(crate);
    }

    // 6. Pickups
    for (final (i, pos) in [Vector3(-3.5, 2.6, 1.0), Vector3(3.5, 1.5, -1.5), Vector3(0.0, 0.8, -4.0)].indexed) {
      final coin = EmberEntity(name: 'Coin_${i + 1}');
      coin.addComponent(Transform3DComponent(position: pos, scale: Vector3(0.4, 0.4, 0.4)));
      coin.addComponent(MeshRenderer3DComponent(
        primitiveType: MeshPrimitiveType.sphere,
        material: Material3D(color: const Color(0xFFFACC15), metallic: 0.8, roughness: 0.2),
      ));
      coin.addComponent(ScriptComponent(scriptName: 'Collectible'));
      scene.addEntity(coin);
    }

    return scene;
  }

  /// Creates a starter 2D scene with platformer character, tilemap, and particle emitters.
  static EmberScene createDefault2DScene() {
    _ensureCoreComponentsRegistered();

    final scene = EmberScene(name: 'Level_01 (2D Flame)');

    // 1. Player Character with Platformer Controller
    final player = EmberEntity(name: 'PlayerCharacter');
    player.addComponent(Transform2DComponent(
      position: Vector2(160.0, 240.0),
      size: Vector2(48.0, 48.0),
      anchor: EmberAnchor.center,
    ));
    player.addComponent(FlameSpriteComponent());
    player.addComponent(FlameHitbox2DComponent(shape: Hitbox2DShape.rectangle, size: Vector2(40.0, 44.0)));
    player.addComponent(CharacterController2DComponent(moveSpeed: 240.0, jumpVelocity: 450.0));
    player.addComponent(ScriptComponent(scriptName: 'Platformer 2D Controller'));
    player.addComponent(ParticleEmitter2DComponent(preset: ParticlePreset.sparkBurst, spawnRate: 0.0)); // bursts on jump
    player.addComponent(AudioSourceComponent(clip: 'jump', is3D: false));
    scene.addEntity(player);

    // 2. World2D / TileMap
    final world = EmberEntity(name: 'World2D');
    world.addComponent(Transform2DComponent(
      position: Vector2(0.0, 0.0),
      size: Vector2(800.0, 600.0),
    ));
    // Solid tiles (id > 0): a two-row floor plus one floating platform
    final tiles = List<int>.filled(16 * 12, 0);
    for (int c = 0; c < 16; c++) {
      tiles[10 * 16 + c] = 1;
      tiles[11 * 16 + c] = 1;
    }
    for (int c = 6; c <= 9; c++) {
      tiles[7 * 16 + c] = 5;
    }
    world.addComponent(FlameTileMapComponent(columns: 16, rows: 12, tiles: tiles));
    scene.addEntity(world);

    // Coins to collect
    for (final (i, pos) in [Vector2(256.0, 196.0), Vector2(420.0, 290.0), Vector2(64.0, 290.0)].indexed) {
      final coin = EmberEntity(name: 'Coin_${i + 1}');
      coin.addComponent(Transform2DComponent(position: pos, size: Vector2(20.0, 20.0), anchor: EmberAnchor.center));
      coin.addComponent(FlameSpriteComponent(tint: const Color(0xFFFACC15)));
      coin.addComponent(ScriptComponent(scriptName: 'Collectible'));
      scene.addEntity(coin);
    }

    // 3. Enemy Spawner with Embers
    final spawner = EmberEntity(name: 'EnemySpawner');
    spawner.addComponent(Transform2DComponent(
      position: Vector2(320.0, 160.0),
      size: Vector2(36.0, 36.0),
      anchor: EmberAnchor.center,
    ));
    spawner.addComponent(FlameSpriteComponent(tint: const Color(0xFFEF4444)));
    spawner.addComponent(ParticleEmitter2DComponent(preset: ParticlePreset.emberFire));
    scene.addEntity(spawner);

    return scene;
  }

  /// An empty level to start from: in 2D a Camera 2D and a tilemap with a
  /// floor; in 3D a light and a camera.
  static EmberScene starterFor(String name, {required bool is2D}) {
    _ensureCoreComponentsRegistered();
    final scene = EmberScene(name: name);
    if (is2D) {
      scene.addEntity(EmberEntity(name: 'Camera')
        ..addComponent(Transform2DComponent(position: Vector2(320, 180), size: Vector2.zero()))
        ..addComponent(Camera2DComponent(designWidth: 640, designHeight: 360, backgroundColor: const Color(0xFF6CB4EE))));
      final tiles = List<int>.filled(60 * 12, 0);
      for (var c = 0; c < 60; c++) {
        tiles[10 * 60 + c] = 1;
        tiles[11 * 60 + c] = 1;
      }
      scene.addEntity(EmberEntity(name: 'Level')
        ..addComponent(Transform2DComponent(size: Vector2.zero()))
        ..addComponent(FlameTileMapComponent(columns: 60, rows: 12, tileSize: 32, tiles: tiles)));
    } else {
      scene.addEntity(EmberEntity(name: 'Directional Light')
        ..addComponent(Transform3DComponent(position: Vector3(5, 10, 5), euler: Vector3(-45, -45, 0)))
        ..addComponent(LightComponent(type: LightType.directional)));
      scene.addEntity(EmberEntity(name: 'Main Camera')
        ..addComponent(Transform3DComponent(position: Vector3(0, 3, 8), euler: Vector3(-15, 0, 0)))
        ..addComponent(CameraComponent()));
    }
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

    register3DComponents();
    registerFlameComponents();
    registerAudioComponents();
    registerParticleComponents();
    registerCharacterController3D();
    registerCharacterController2D();
    registerCamera2D();
    registerParallax();
    registerSpriteAnimator();
    registerUIComponents();
    registerStandardGameplayScripts();
    registerFlappyScripts();
    registerQuestScripts();
  }
}

/// Registers all engine subsystems and components globally.
void registerAllSubsystems() => EmberScene._ensureCoreComponentsRegistered();


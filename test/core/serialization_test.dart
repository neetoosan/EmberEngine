import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/scene_serializer.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/subsystems/three_d/components3d.dart';
import 'package:ember_engine/subsystems/three_d/camera3d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/audio/audio_component.dart';
import 'package:ember_engine/subsystems/physics/character_controller3d.dart';
import 'package:ember_engine/subsystems/physics/character_controller2d.dart';
import 'package:ember_engine/subsystems/particles/particle_system.dart';

void main() {
  setUpAll(() {
    registerAllSubsystems();
  });

  group('Scene & Prefab Serialization Tests', () {
    test('3D Scene round-trip serialization maintains entity structure and components', () {
      final scene = EmberScene.createDefault3DScene();
      final originalCount = scene.allEntities.length;

      final jsonStr = SceneSerializer.saveSceneToJson(scene);
      expect(jsonStr, isNotEmpty);

      final loadedScene = SceneSerializer.loadSceneFromJson(jsonStr);
      expect(loadedScene.name, equals(scene.name));
      expect(loadedScene.allEntities.length, equals(originalCount));

      // Verify specific player entity
      final player = loadedScene.findByName('Player (FPS)');
      expect(player, isNotNull);
      expect(player!.hasComponent<Transform3DComponent>(), isTrue);
      expect(player.hasComponent<CameraComponent>(), isTrue);
      expect(player.hasComponent<CharacterController3DComponent>(), isTrue);
      expect(player.hasComponent<AudioSourceComponent>(), isTrue);

      final cc = player.getComponent<CharacterController3DComponent>()!;
      expect(cc.walkSpeed, equals(7.0));
      expect(cc.jumpForce, equals(7.0));
    });

    test('2D Scene round-trip serialization maintains Flame components and tilemaps', () {
      final scene = EmberScene.createDefault2DScene();
      final jsonStr = SceneSerializer.saveSceneToJson(scene);
      final loadedScene = SceneSerializer.loadSceneFromJson(jsonStr);

      final player = loadedScene.findByName('PlayerCharacter');
      expect(player, isNotNull);
      expect(player!.hasComponent<Transform2DComponent>(), isTrue);
      expect(player.hasComponent<FlameSpriteComponent>(), isTrue);
      expect(player.hasComponent<CharacterController2DComponent>(), isTrue);
      expect(player.hasComponent<ParticleEmitter2DComponent>(), isTrue);

      final world = loadedScene.findByName('World2D');
      expect(world, isNotNull);
      expect(world!.hasComponent<FlameTileMapComponent>(), isTrue);
    });

    test('Prefab serialization and instantiation generates new unique IDs and copies hierarchy', () {
      final parent = EmberEntity(name: 'TurretBase');
      parent.addComponent(Transform3DComponent(position: Vector3(10, 0, 5)));
      parent.addComponent(MeshRenderer3DComponent(primitiveType: MeshPrimitiveType.cylinder));

      final gun = EmberEntity(name: 'TurretGun');
      gun.addComponent(Transform3DComponent(position: Vector3(0, 1.5, 0)));
      gun.addComponent(AudioSourceComponent(clip: 'laser'));
      parent.addChild(gun);

      final prefabJson = SceneSerializer.serializePrefab(parent);
      expect(prefabJson, isNotEmpty);

      // Instantiate into scene
      final scene = EmberScene(name: 'CombatArena');
      final clone = SceneSerializer.instantiatePrefab(prefabJson, scene: scene);

      expect(clone.id, isNot(equals(parent.id)));
      expect(clone.name, equals('TurretBase'));
      expect(clone.children.length, equals(1));
      expect(clone.children.first.id, isNot(equals(gun.id)));
      expect(clone.children.first.name, equals('TurretGun'));
      expect(scene.allEntities.length, equals(2));
    });
  });
}

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/subsystems/audio/audio_output.dart';
import 'package:ember_engine/subsystems/physics/character_controller2d.dart';
import 'package:ember_engine/subsystems/physics/character_controller3d.dart';
import 'package:ember_engine/subsystems/three_d/components3d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';

void main() {
  setUpAll(registerAllSubsystems);

  const dt = 1.0 / 60.0;

  group('3D character collisions', () {
    EmberEntity makePlayer(EmberScene scene, Vector3 pos) {
      final player = EmberEntity(name: 'Player');
      player.addComponent(Transform3DComponent(position: pos));
      player.addComponent(CharacterController3DComponent());
      scene.addEntity(player);
      return player;
    }

    EmberEntity makeBox(EmberScene scene, Vector3 pos, Vector3 scale) {
      final box = EmberEntity(name: 'Box');
      box.addComponent(Transform3DComponent(position: pos, scale: scale));
      box.addComponent(Collider3DComponent());
      scene.addEntity(box);
      return box;
    }

    test('lands and stays grounded on top of a crate', () {
      final scene = EmberScene();
      makeBox(scene, Vector3(0, 0.5, 0), Vector3(2, 1, 2)); // top at y = 1
      final player = makePlayer(scene, Vector3(0, 3, 0));
      final cc = player.getComponent<CharacterController3DComponent>()!;
      final t = player.getComponent<Transform3DComponent>()!;

      for (var i = 0; i < 120; i++) {
        cc.move(Vector3.zero(), false, dt);
      }
      expect(cc.isGrounded, isTrue);
      expect(t.position.y, closeTo(1.0 + cc.height / 2, 0.05));
    });

    test('walls block horizontal movement', () {
      final scene = EmberScene();
      makeBox(scene, Vector3(0, 2, -3), Vector3(6, 4, 1)); // wall face at z = -2.5
      final player = makePlayer(scene, Vector3(0, 0.9, 0));
      final cc = player.getComponent<CharacterController3DComponent>()!;
      final t = player.getComponent<Transform3DComponent>()!;

      for (var i = 0; i < 180; i++) {
        cc.move(Vector3(0, 0, -1), false, dt);
      }
      expect(t.position.z, greaterThanOrEqualTo(-2.5 + cc.radius - 0.01));
    });

    test('walks up low steps without jumping', () {
      final scene = EmberScene();
      makeBox(scene, Vector3(0, 0.1, -2), Vector3(4, 0.2, 2)); // 20cm step
      final player = makePlayer(scene, Vector3(0, 0.9, 0));
      final cc = player.getComponent<CharacterController3DComponent>()!;
      final t = player.getComponent<Transform3DComponent>()!;

      // ~0.5 s of walking: far enough to be on the step, not past its end at z = -3
      for (var i = 0; i < 30; i++) {
        cc.move(Vector3(0, 0, -1), false, dt);
      }
      expect(t.position.z, inInclusiveRange(-3.3, -1.5));
      expect(t.position.y, closeTo(0.2 + cc.height / 2, 0.05));
    });
  });

  test('2D character lands on solid tilemap tiles', () {
    final scene = EmberScene();
    final world = EmberEntity(name: 'World');
    world.addComponent(Transform2DComponent());
    final tiles = List<int>.filled(10 * 10, 0);
    for (var c = 0; c < 10; c++) {
      tiles[8 * 10 + c] = 1; // floor row: y 256..288
    }
    world.addComponent(FlameTileMapComponent(columns: 10, rows: 10, tiles: tiles));
    scene.addEntity(world);

    final player = EmberEntity(name: 'Player');
    final t = Transform2DComponent(position: Vector2(100, 100), size: Vector2(32, 32));
    player.addComponent(t);
    final cc = CharacterController2DComponent(groundY: 10000);
    player.addComponent(cc);
    scene.addEntity(player);

    for (var i = 0; i < 120; i++) {
      cc.updateMovement(horizontalInput: 0, isJumpPressed: false, isJumpJustPressed: false, dt: dt);
    }
    expect(cc.isGrounded, isTrue);
    expect(t.position.y + 32, closeTo(256, 0.01));
  });

  test('Collectible pickups disappear when the player touches them', () {
    final scene = EmberScene();
    final player = EmberEntity(name: 'Player');
    player.addComponent(Transform2DComponent(position: Vector2(100, 100), size: Vector2(32, 32)));
    player.addComponent(CharacterController2DComponent());
    scene.addEntity(player);

    final coin = EmberEntity(name: 'Coin');
    coin.addComponent(Transform2DComponent(position: Vector2(110, 110), size: Vector2(16, 16)));
    coin.addComponent(ScriptComponent(scriptName: 'Collectible'));
    scene.addEntity(coin);

    final far = EmberEntity(name: 'FarCoin');
    far.addComponent(Transform2DComponent(position: Vector2(900, 900), size: Vector2(16, 16)));
    far.addComponent(ScriptComponent(scriptName: 'Collectible'));
    scene.addEntity(far);

    scene.update(dt);
    expect(coin.enabled, isFalse);
    expect(far.enabled, isTrue);
  });

  test('WAV encoder writes a valid 16-bit PCM header', () {
    final buffer = AudioOutput.synthesize('coin')!;
    final wav = AudioOutput.encodeWav(buffer.samples, 44100);
    final data = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(22, Endian.little), 1); // mono
    expect(data.getUint32(24, Endian.little), 44100);
    expect(data.getUint16(34, Endian.little), 16);
    expect(data.getUint32(40, Endian.little), buffer.samples.length * 2);
    expect(wav.length, 44 + buffer.samples.length * 2);
    expect(AudioOutput.synthesize('unknown_clip'), isNull);
  });

  test('default scenes include playable controllers and pickups', () {
    final s3 = EmberScene.createDefault3DScene();
    final fps = s3.findByName('Player (FPS)')!;
    expect(fps.getComponent<ScriptComponent>()!.scriptInstance, isNotNull);
    expect(s3.allEntities.where((e) => e.name.startsWith('Coin_')), hasLength(3));

    final s2 = EmberScene.createDefault2DScene();
    final map = s2.findByName('World2D')!.getComponent<FlameTileMapComponent>()!;
    expect(map.tiles.where((t) => t > 0), isNotEmpty);
  });
}

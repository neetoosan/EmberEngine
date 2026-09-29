import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/gameplay_scripts.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/scene_serializer.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/subsystems/audio/audio_system.dart';
import 'package:ember_engine/subsystems/physics/character_controller2d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/two_d/parallax.dart';
import 'package:ember_engine/subsystems/two_d/sprite_animator.dart';

const dt = 1 / 60;

/// Breaks bricks it bumps and records hazard touches.
class _Bumper extends GameScript {
  static final List<String> log = [];
  @override
  void onHeadBump(TileHit tile) {
    log.add('bump:${tile.col},${tile.row}:${tile.kind.name}');
    if (tile.kind == TileKind.breakable) tile.setTile(0);
  }

  @override
  void onTileTouch(TileHit tile) => log.add('touch:${tile.kind.name}');
}

/// A scene with a tilemap (32px tiles) and a 32x32 character; returns both.
(EmberScene, FlameTileMapComponent, EmberEntity) _level({int columns = 20, int rows = 12}) {
  final scene = EmberScene();
  final map = FlameTileMapComponent(columns: columns, rows: rows);
  scene.addEntity(EmberEntity(name: 'Level')
    ..addComponent(Transform2DComponent(size: Vector2.zero()))
    ..addComponent(map));
  final hero = EmberEntity(name: 'Hero')
    ..addComponent(Transform2DComponent(position: Vector2(64, 64), size: Vector2(32, 32)))
    ..addComponent(CharacterController2DComponent(groundY: 100000))
    ..addComponent(ScriptComponent(scriptName: 'Test Bumper'));
  scene.addEntity(hero);
  return (scene, map, hero);
}

void _run(EmberEntity hero, double seconds, {double input = 0, bool jump = false}) {
  final cc = hero.getComponent<CharacterController2DComponent>()!;
  for (var i = 0; i < (seconds * 60).round(); i++) {
    cc.updateMovement(horizontalInput: input, isJumpPressed: jump, isJumpJustPressed: jump && i == 0, dt: dt);
  }
}

double _y(EmberEntity e) => e.getComponent<Transform2DComponent>()!.position.y;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerAllSubsystems();
    ScriptRegistry.register('Test Bumper', () => _Bumper());
  });
  setUp(_Bumper.log.clear);

  group('tiles', () {
    test('one-way platforms hold you from above and let you jump up through', () {
      final (_, map, hero) = _level();
      map.setKind(5, TileKind.oneWay);
      for (var c = 0; c < 20; c++) {
        map.setTile(c, 10, 1); // floor: top at y=320
        map.setTile(c, 6, 5); // one-way ledge: top at y=192
      }
      hero.getComponent<Transform2DComponent>()!.position = Vector2(64, 250); // between floor and ledge
      hero.getComponent<CharacterController2DComponent>()!.jumpVelocity = 600; // ~180px jump; ledge is 128px up
      _run(hero, 1.0);
      expect(_y(hero), closeTo(320 - 32, 0.01), reason: 'falls to the solid floor');

      _run(hero, 0.35, jump: true); // jump up through the ledge
      _run(hero, 1.0);
      expect(_y(hero), closeTo(192 - 32, 0.01), reason: 'lands on top of the one-way ledge');
    });

    test('head bumps report the tile overhead, which a script can break', () {
      final (_, map, hero) = _level();
      map.setKind(3, TileKind.breakable);
      for (var c = 0; c < 20; c++) {
        map.setTile(c, 10, 1); // floor at y=320
      }
      map.setTile(2, 6, 3); // brick right above the hero (x 64..96, y 192..224)
      hero.getComponent<Transform2DComponent>()!.position = Vector2(64, 288);
      _run(hero, 0.1); // settle
      _run(hero, 0.4, jump: true);
      expect(_Bumper.log, contains('bump:2,6:breakable'));
      expect(map.getTile(2, 6), 0, reason: 'script broke the brick');
    });

    test('hazard tiles are not solid but report touches', () {
      final (_, map, hero) = _level();
      map.setKind(4, TileKind.hazard);
      for (var c = 0; c < 20; c++) {
        map.setTile(c, 10, 1);
      }
      map.setTile(2, 9, 4); // spikes on the floor under the hero
      hero.getComponent<Transform2DComponent>()!.position = Vector2(64, 200);
      _run(hero, 1.0);
      expect(_y(hero), closeTo(320 - 32, 0.01), reason: 'falls through the hazard onto the floor');
      expect(_Bumper.log, contains('touch:hazard'));
    });

    test('long levels only touch nearby tiles (collision stays fast)', () {
      final (_, map, hero) = _level(columns: 2000, rows: 15);
      for (var c = 0; c < 2000; c++) {
        map.setTile(c, 12, 1);
      }
      expect(map.tilesIn(const Rect.fromLTWH(100, 350, 40, 40)).length, lessThanOrEqualTo(4));
      final watch = Stopwatch()..start();
      _run(hero, 10, input: 1); // 600 frames running along a 64,000px level
      watch.stop();
      expect(hero.getComponent<Transform2DComponent>()!.position.x, greaterThan(1500));
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });

    test('tileset, tile kinds and resize survive save/load', () {
      final map = FlameTileMapComponent(columns: 4, rows: 3, tilesetPath: 'assets/tiles.png', tilesetColumns: 5, tilesetTileSize: 16);
      map.setTile(3, 2, 7);
      map.setKind(7, TileKind.question);
      map.columns = 6; // widening keeps (3,2)
      expect(map.getTile(3, 2), 7);
      map.rows = 2; // shrinking drops row 2
      expect(map.getTile(3, 2), 0);
      map.setTile(1, 1, 7);

      final copy = FlameTileMapComponent()..fromJson(map.toJson());
      expect(copy.columns, 6);
      expect(copy.getTile(1, 1), 7);
      expect(copy.kindOf(7), TileKind.question);
      expect(copy.kindOf(1), TileKind.solid);
      expect(copy.tilesetPath, 'assets/tiles.png');
      expect(copy.tilesetColumns, 5);
    });
  });

  test('sprite animator: named clips, looping and play-once', () {
    final e = EmberEntity(name: 'Anim')
      ..addComponent(FlameSpriteComponent(columns: 8))
      ..addComponent(SpriteAnimatorComponent(clips: 'idle=0-1@2; run=2-4@10; die=6-7@4!', defaultClip: 'idle'));
    final anim = e.getComponent<SpriteAnimatorComponent>()!;
    final sprite = e.getComponent<FlameSpriteComponent>()!;
    expect(anim.clips.map((c) => c.name), ['idle', 'run', 'die']);

    anim.play('run');
    for (var i = 0; i < 12; i++) {
      anim.onUpdate(0.05); // 10 fps → one frame every 0.1 s
      expect(sprite.frame, inInclusiveRange(2, 4));
    }
    anim.play('die');
    for (var i = 0; i < 20; i++) {
      anim.onUpdate(0.1);
    }
    expect(sprite.frame, 7, reason: 'play-once clip holds its last frame');
    expect(anim.isFinished, isTrue);

    final copy = SpriteAnimatorComponent()..fromJson(anim.toJson());
    expect(copy.clipSpec, anim.clipSpec);
    expect(SpriteAnimatorComponent.parseClips('bad; x=3@5'), hasLength(1));
  });

  test('parallax layer settings round-trip', () {
    final p = ParallaxLayerComponent(factorX: 0.25, factorY: 0.9, repeatX: false);
    final copy = ParallaxLayerComponent()..fromJson(p.toJson());
    expect(copy.factorX, 0.25);
    expect(copy.repeatX, isFalse);
  });

  test('patrol walker turns at walls and at ledges', () {
    final (scene, map, _) = _level();
    for (var c = 2; c < 10; c++) {
      map.setTile(c, 10, 1); // platform x 64..320 (ledges at both ends)
    }
    map.setTile(9, 9, 1); // wall at the right end
    final enemy = EmberEntity(name: 'Enemy', tags: {'enemy'})
      ..addComponent(Transform2DComponent(position: Vector2(160, 288), size: Vector2(28, 32)))
      ..addComponent(CharacterController2DComponent(moveSpeed: 80, groundY: 100000))
      ..addComponent(ScriptComponent(scriptName: 'Patrol Walker'));
    scene.addEntity(enemy);
    final walker = enemy.getComponent<ScriptComponent>()!.scriptInstance as PatrolWalker;

    var minX = 1e9, maxX = -1e9;
    for (var i = 0; i < 60 * 10; i++) {
      walker.onUpdate(dt);
      final x = enemy.getComponent<Transform2DComponent>()!.position.x;
      minX = x < minX ? x : minX;
      maxX = x > maxX ? x : maxX;
    }
    expect(minX, greaterThanOrEqualTo(62), reason: 'turned at the left ledge instead of falling');
    expect(maxX, lessThanOrEqualTo(288 - 28 + 1), reason: 'turned at the wall');
    expect(_y(enemy), closeTo(320 - 32, 0.01), reason: 'still on the platform');

    walker.squash();
    expect(enemy.getComponent<FlameHitbox2DComponent>(), isNull);
    expect(walker.squashed, isTrue);
  });

  test('levels: loadLevel switches scenes and restart replays the current level', () {
    final engine = EmberEngine.instance;
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    final level1 = EmberScene.starterFor('Level 1', is2D: true);
    final level2 = EmberScene.starterFor('Level 2', is2D: true)..addEntity(EmberEntity(name: 'OnlyInLevel2'));
    final library = {'Level 1': level1.toJson(), 'Level 2': level2.toJson()};
    engine.sceneLibrary = () => library;
    engine.loadScene(EmberScene.fromJson(library['Level 1']!));

    engine.step();
    expect(engine.loadLevel('Nope'), isFalse);
    expect(engine.loadLevel('Level 2'), isTrue);
    engine.step();
    expect(engine.activeScene.name, 'Level 2');
    expect(engine.activeScene.findByName('OnlyInLevel2'), isNotNull);

    engine.restartScene();
    engine.step();
    expect(engine.activeScene.name, 'Level 2', reason: 'restart replays the current level');

    engine.stop();
    expect(engine.activeScene.name, 'Level 1', reason: 'Stop returns to the scene being edited');
    engine.sceneLibrary = null;
  });

  test('music loops, replaces the previous track, and stops with stopAll', () {
    final backend = _FakeBackend();
    final audio = AudioSystem.instance..backend = backend;
    addTearDown(() => audio.backend = null);

    final a = audio.playMusic('assets/audio/a.ogg');
    expect(a.isLooping, isTrue);
    expect(audio.playMusic('assets/audio/a.ogg'), same(a), reason: 'same track keeps playing');
    audio.playMusic('assets/audio/b.ogg');
    expect(backend.stopped, contains(a.id));
    for (var i = 0; i < 600; i++) {
      audio.update(dt); // 10 s: looping music must not expire
    }
    expect(audio.music?.clip, 'assets/audio/b.ogg');
    audio.stopAll();
    expect(audio.music, isNull);
    expect(backend.stoppedAll, isTrue);
  });

  test('starter scenes: 2D has a camera and floor, 3D a light and camera', () {
    final s2 = EmberScene.starterFor('L', is2D: true);
    expect(s2.findByName('Camera'), isNotNull);
    expect(s2.findByName('Level')!.getComponent<FlameTileMapComponent>()!.getTile(0, 10), 1);
    final s3 = EmberScene.starterFor('L3', is2D: false);
    expect(s3.allEntities.map((e) => e.name), containsAll(['Directional Light', 'Main Camera']));
    // And both survive serialization
    expect(SceneSerializer.deserializeScene(SceneSerializer.serializeScene(s2)).allEntities.length, s2.allEntities.length);
  });
}

class _FakeBackend implements AudioBackend {
  final List<int> played = [];
  final List<int> stopped = [];
  bool stoppedAll = false;
  @override
  void play(AudioVoice voice, double volume, double pan) => played.add(voice.id);
  @override
  void stop(AudioVoice voice) => stopped.add(voice.id);
  @override
  void stopAll() => stoppedAll = true;
}

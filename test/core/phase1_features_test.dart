import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/assets.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/scene_serializer.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/hub/project_storage.dart';
import 'package:ember_engine/subsystems/physics/physics_world2d.dart';
import 'package:ember_engine/subsystems/two_d/camera2d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';

/// Spawns a child every frame and destroys itself on frame 3.
class _Spawner extends GameScript {
  int frames = 0;
  @override
  void onUpdate(double dt) {
    frames++;
    spawn(EmberEntity(name: 'Spawned_$frames')..addComponent(ScriptComponent(scriptName: 'Test Probe')));
    if (frames == 3) destroy();
  }
}

/// Records lifecycle and contact callbacks.
class _Probe extends GameScript {
  static final List<String> events = [];
  @override
  void onStart() => events.add('start:${entity!.name}');
  @override
  void onTriggerEnter(EmberEntity other) => events.add('enter:${entity!.name}<-${other.name}');
  @override
  void onTriggerExit(EmberEntity other) => events.add('exit:${entity!.name}<-${other.name}');
  @override
  void onCollisionEnter(EmberEntity other) => events.add('hit:${entity!.name}<-${other.name}');
}

/// Asks the engine to restart after 2 frames.
class _Restarter extends GameScript {
  int frames = 0;
  @override
  void onUpdate(double dt) {
    if (++frames == 2) EmberEngine.instance.restartScene();
  }
}

EmberEntity _box(String name, Vector2 pos, {bool solid = false, String? script}) {
  final e = EmberEntity(name: name);
  e.addComponent(Transform2DComponent(position: pos, size: Vector2(20, 20)));
  e.addComponent(FlameHitbox2DComponent(size: Vector2(20, 20), isSolid: solid));
  if (script != null) e.addComponent(ScriptComponent(scriptName: script));
  return e;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerAllSubsystems();
    ScriptRegistry.register('Test Spawner', () => _Spawner());
    ScriptRegistry.register('Test Probe', () => _Probe());
    ScriptRegistry.register('Test Restarter', () => _Restarter());
  });

  setUp(_Probe.events.clear);

  test('scripts can spawn and destroy entities mid-frame; spawned ones start immediately', () {
    final scene = EmberScene();
    scene.addEntity(EmberEntity(name: 'Spawner')..addComponent(ScriptComponent(scriptName: 'Test Spawner')));
    scene.awake();
    scene.start();
    scene.isRunning = true;

    for (var i = 0; i < 5; i++) {
      scene.update(1 / 60);
      scene.flushDestroyed();
    }
    expect(scene.findByName('Spawner'), isNull, reason: 'destroyed itself on frame 3');
    expect(scene.allEntities.where((e) => e.name.startsWith('Spawned_')), hasLength(3));
    expect(_Probe.events.where((e) => e.startsWith('start:Spawned_')), hasLength(3));
  });

  test('2D trigger and collision events fire once on enter and on exit', () {
    final scene = EmberScene();
    final bird = _box('Bird', Vector2(0, 0), script: 'Test Probe');
    final gate = _box('Gate', Vector2(10, 0), script: 'Test Probe');
    final wall = _box('Wall', Vector2(500, 0), solid: true, script: 'Test Probe');
    final block = _box('Block', Vector2(505, 0), solid: true);
    for (final e in [bird, gate, wall, block]) {
      scene.addEntity(e);
    }

    PhysicsWorld2D.step(scene, 1 / 60);
    PhysicsWorld2D.step(scene, 1 / 60); // still overlapping: no duplicate enter
    expect(_Probe.events.where((e) => e == 'enter:Bird<-Gate'), hasLength(1));
    expect(_Probe.events, contains('enter:Gate<-Bird'));
    expect(_Probe.events, contains('hit:Wall<-Block'));

    bird.getComponent<Transform2DComponent>()!.position = Vector2(-200, 0);
    PhysicsWorld2D.step(scene, 1 / 60);
    expect(_Probe.events, contains('exit:Bird<-Gate'));
  });

  testWidgets('restartScene reloads the play snapshot after the current frame', (tester) async {
    final engine = EmberEngine.instance;
    engine.stop();
    engine.setMode(EngineMode.twoD);
    final scene = EmberScene(name: 'RestartTest');
    scene.addEntity(EmberEntity(name: 'R')..addComponent(ScriptComponent(scriptName: 'Test Restarter')));
    engine.loadScene(scene);

    engine.step(); // frame 1 (starts play + pause)
    final before = engine.activeScene;
    engine.step(); // frame 2 requests restart; applied at end of frame
    expect(identical(engine.activeScene, before), isFalse);
    expect(engine.activeScene.name, 'RestartTest');
    expect(engine.activeScene.isRunning, isTrue);
    engine.stop();
  });

  test('Camera 2D letterboxes the design size, follows its target and respects bounds', () {
    final scene = EmberScene();
    final cam = EmberEntity(name: 'Cam')
      ..addComponent(Transform2DComponent())
      ..addComponent(Camera2DComponent(
        designWidth: 288,
        designHeight: 512,
        followTarget: 'Hero',
        smoothing: 0,
        boundsEnabled: true,
        boundsMin: Vector2(0, 0),
        boundsMax: Vector2(1000, 512),
      ));
    final hero = EmberEntity(name: 'Hero')..addComponent(Transform2DComponent(position: Vector2(600, 100)));
    scene.addEntity(cam);
    scene.addEntity(hero);

    final c = cam.getComponent<Camera2DComponent>()!;
    c.onUpdate(1 / 60);
    // x follows the hero; y is pinned because the level is exactly one screen tall
    expect(c.position.x, closeTo(600, 0.001));
    expect(c.position.y, closeTo(256, 0.001));

    hero.getComponent<Transform2DComponent>()!.position = Vector2(20, 100);
    c.onUpdate(1 / 60);
    expect(c.position.x, closeTo(144, 0.001), reason: 'clamped to left edge + half width');

    final view = c.viewFor(const Size(1280, 720));
    expect(view.zoom, closeTo(720 / 512, 1e-9));
    expect(view.viewport.height, closeTo(720, 1e-9));
    expect(view.viewport.width, closeTo(288 * 720 / 512, 1e-9));
    final world = view.screenToWorld(view.worldToScreen(Vector2(200, 300)));
    expect(world.x, closeTo(200, 1e-9));
    expect(world.y, closeTo(300, 1e-9));
  });

  test('UI Text and Camera 2D survive save/load; UI Text paints without errors', () {
    final scene = EmberScene(name: 'UI');
    scene.addEntity(EmberEntity(name: 'Score')
      ..addComponent(UITextComponent(text: 'Score: 7', fontSize: 30, anchor: EmberAnchor.topLeft)));
    scene.addEntity(EmberEntity(name: 'Cam')
      ..addComponent(Transform2DComponent())
      ..addComponent(Camera2DComponent(designWidth: 320, designHeight: 240, followTarget: 'X')));

    final loaded = SceneSerializer.deserializeScene(SceneSerializer.serializeScene(scene));
    final text = loaded.findByName('Score')!.getComponent<UITextComponent>()!;
    expect(text.text, 'Score: 7');
    expect(text.fontSize, 30);
    expect(text.anchor, EmberAnchor.topLeft);
    final cam = loaded.findByName('Cam')!.getComponent<Camera2DComponent>()!;
    expect(cam.designWidth, 320);
    expect(cam.followTarget, 'X');

    final recorder = ui.PictureRecorder();
    UITextComponent.paintAll(Canvas(recorder), const Rect.fromLTWH(0, 0, 320, 240), 1.0, loaded);
    recorder.endRecording();
  });

  test('sprite sheet fields round-trip; frame wraps around the sheet', () {
    final s = FlameSpriteComponent(assetPath: 'assets/sprites/bird.png', columns: 3, rows: 1);
    s.frame = 4;
    expect(s.frame, 1);
    final copy = FlameSpriteComponent()..fromJson(s.toJson());
    expect(copy.columns, 3);
    expect(copy.frame, 1);
    expect(copy.assetPath, 'assets/sprites/bird.png');
  });

  test('SaveData works in memory when no storage is available', () async {
    await SaveData.instance.open('Test Game');
    expect(SaveData.instance.getInt('best'), 0);
    SaveData.instance.setInt('best', 42);
    expect(SaveData.instance.getInt('best'), 42);
  });

  testWidgets('EmberAssets loads PNGs from the project folder', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('ember_assets_test');
    addTearDown(() => tmp.deleteSync(recursive: true));

    await tester.runAsync(() async {
      // Make a real 12x8 PNG
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 12, 8), Paint()..color = const Color(0xFFFF0000));
      final img = await recorder.endRecording().toImage(12, 8);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${tmp.path}/assets/sprites/red.png')..createSync(recursive: true);
      file.writeAsBytesSync(png!.buffer.asUint8List());

      EmberAssets.instance.root = tmp.path;
      final loaded = await EmberAssets.instance.load('assets/sprites/red.png');
      expect(loaded, isNotNull);
      expect(loaded!.width, 12);
      expect(EmberAssets.instance.image('assets/sprites/red.png'), same(loaded));

      expect(await EmberAssets.instance.load('assets/sprites/missing.png'), isNull);
      expect(EmberAssets.instance.isMissing('assets/sprites/missing.png'), isTrue);
    });
    EmberAssets.instance.root = null;
  });

  test('projects list every assets/ path their scenes reference', () {
    final project = EmberProject(id: 'p', name: 'P');
    final scene = EmberScene(name: 'MainScene');
    scene.addEntity(EmberEntity(name: 'A')..addComponent(FlameSpriteComponent(assetPath: 'assets/sprites/a.png')));
    scene.addEntity(EmberEntity(name: 'B')..addComponent(FlameSpriteComponent(assetPath: 'assets/sprites/b.png')));
    project.scenes['MainScene'] = scene;
    expect(ProjectStorage.referencedAssetPaths(project), {'assets/sprites/a.png', 'assets/sprites/b.png'});
  });
}

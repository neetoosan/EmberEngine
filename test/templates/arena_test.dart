import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/painting.dart' show Canvas, Size;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/mouse_lock.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/three_d/renderer3d.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';
import 'package:ember_engine/templates/arena_game.dart';
import 'package:ember_engine/templates/arena_scripts.dart';

EmberEngine get engine => EmberEngine.instance;
EmberScene get scene => engine.activeScene;

EmberScriptBehavior scriptOf(String name) => scene.findByName(name)!.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
Object? arena(String field) => scriptOf('Arena').field(field);
String text(String name) => scene.findByName(name)!.getComponent<UITextComponent>()!.text;
EmberEntity get player => scene.findByName('Player')!;
List<EmberEntity> get robots => [for (final e in scene.allEntities) if (e.enabled && e.tags.contains('enemy')) e];

void start(EmberScene s) {
  engine.stop();
  EmberScripts.instance.loadAll(arenaScripts);
  engine.loadScene(s);
  engine.step();
}

void runUntil(bool Function() done, double maxSeconds, {void Function()? each}) {
  for (var i = 0; i < maxSeconds * 60 && !done(); i++) {
    each?.call();
    engine.step();
  }
}

/// Turns the player toward the nearest robot (what a human does with the mouse).
void aimAtNearest() {
  final eye = player.getComponent<Transform3DComponent>()!.worldPosition + Vector3(0, 0.72, 0);
  EmberEntity? best;
  var bestD = double.infinity;
  for (final r in robots) {
    final d = r.getComponent<Transform3DComponent>()!.worldPosition.distanceTo(eye);
    if (d < bestD) {
      bestD = d;
      best = r;
    }
  }
  if (best == null) return;
  final d = best.getComponent<Transform3DComponent>()!.worldPosition - eye;
  final yaw = math.atan2(-d.x, -d.z) * 180 / math.pi;
  final pitch = math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z)) * 180 / math.pi;
  player.getComponent<Transform3DComponent>()!.euler = Vector3(pitch, yaw, 0);
  scriptOf('Player').setField('_pitch', pitch);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('arena test');
    for (final key in ['arena_best_wave', 'arena_best_score']) {
      SaveData.instance.remove(key);
    }
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.threeD);
  });

  tearDown(() {
    Input.reset();
    engine.stop();
    MouseLock.reset();
  });

  test('the template has a title and the arena, scripts that compile and assets on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.arena).createProject(name: 'Arena');
    expect(project.scenes.keys, containsAll([Arena.title, Arena.level]));
    expect(project.defaultSceneName, Arena.title);
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in arenaScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Arena.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    // Scenes survive a save / load round trip (what the editor and exports do)
    final again = EmberScene.fromJson(project.scenes[Arena.level]!.toJson());
    expect(again.findByName('Brute')!.children.map((c) => c.name), contains('Eye'));
  });

  test('the title camera circles the arena and shows the best run', () {
    SaveData.instance.setInt('arena_best_wave', 7);
    start(buildArenaTitle());
    final cam = scene.findByName('Title Camera')!.getComponent<Transform3DComponent>()!;
    final before = cam.position.clone();
    runUntil(() => false, 2);
    expect(cam.position.distanceTo(before), greaterThan(1));
    expect(cam.forward.y, lessThan(-0.2), reason: 'looks down at the arena');
    expect(text('BestText'), contains('wave 7'));
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('wave 1: robots come through the portals and the player can clear it; then wave 2 starts', () {
    start(buildArenaLevel());
    expect(MouseLock.wanted, isTrue, reason: 'the player script asks for mouse capture');
    expect(text('Banner'), 'GET READY');
    runUntil(() => arena('state') == 'fight', 4);
    expect(arena('wave'), 1);
    expect(text('WaveText'), 'WAVE 1');
    // Each robot appears at a portal (checked on the frame it arrives)
    final seen = <EmberEntity>{};
    runUntil(() => seen.length >= 3, 4, each: () {
      for (final r in robots) {
        if (!seen.add(r)) continue;
        final p = r.getComponent<Transform3DComponent>()!.worldPosition;
        expect(math.max(p.x.abs(), p.z.abs()), greaterThan(11), reason: '${r.name} came from a portal');
      }
    });
    expect(seen.length, 3);
    // Fight: aim at the nearest robot and hold the trigger
    Input.onMouseDown(0);
    runUntil(() => arena('state') == 'break' || (player.getComponent<HealthComponent>()!.isDead), 40, each: aimAtNearest);
    Input.onMouseUp(0);
    expect(player.getComponent<HealthComponent>()!.isDead, isFalse, reason: 'wave 1 is beatable');
    expect(arena('state'), 'break');
    expect(arena('score') as int, greaterThanOrEqualTo(150), reason: 'kills plus the wave bonus');
    expect(text('Banner'), 'WAVE 1 CLEARED');
    expect(scene.allEntities.where((e) => e.enabled && e.tags.contains('pickup')).length, greaterThanOrEqualTo(2), reason: 'supplies on the pads');
    runUntil(() => arena('wave') == 2, 7);
    expect(arena('wave'), 2);
    expect((arena('queue') as List).where((k) => k == 'Gunner'), isNotEmpty, reason: 'gunners join in wave 2');
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('the scatter gun uses shells; pickups give health and shells back', () {
    start(buildArenaLevel());
    final p = scriptOf('Player');
    Input.onKeyDown(LogicalKeyboardKey.digit2);
    engine.step();
    Input.onKeyUp(LogicalKeyboardKey.digit2);
    expect(text('WeaponText'), '2  SCATTER');
    expect(text('AmmoText'), '12 / 40');
    Input.onMouseDown(0);
    engine.step();
    Input.onMouseUp(0);
    expect(p.field('ammo'), 11);
    // Hurt, then walk over a health pack and an ammo crate
    player.getComponent<HealthComponent>()!.damage(40, source: scene.findByName('Arena'));
    engine.step();
    final hp = player.getComponent<HealthComponent>()!;
    expect(hp.health, 60);
    expect(scene.findByName('HurtFlash')!.enabled, isTrue);
    final at = player.getComponent<Transform3DComponent>()!.worldPosition;
    final pack = scene.findByName('Health Pack')!.clone()..enabled = true;
    pack.getComponent<Transform3DComponent>()!.position = at + Vector3(0, -0.2, 0);
    final crate = scene.findByName('Ammo Crate')!.clone()..enabled = true;
    crate.getComponent<Transform3DComponent>()!.position = at + Vector3(0.3, -0.2, 0);
    scene
      ..addEntity(pack)
      ..addEntity(crate);
    runUntil(() => false, 0.5);
    expect(hp.health, 90);
    expect(p.field('ammo'), 23);
    expect(pack.scene, isNull);
    expect(crate.scene, isNull);
    expect(scene.findByName('HurtFlash')!.enabled, isFalse, reason: 'the red flash fades');
    expect(scene.findByName('HealthBar')!.getComponent<UIBarComponent>()!.label, 'HP 90');
  });

  test('when the player falls the game is over: panel, best run saved, mouse released; Fight again restarts', () {
    start(buildArenaLevel());
    runUntil(() => arena('state') == 'fight', 4);
    scriptOf('Arena').setField('score', 1234);
    player.getComponent<HealthComponent>()!.damage(1000, source: scene.findByName('Arena'));
    engine.step();
    expect(arena('state'), 'over');
    for (final name in ['GameOverPanel', 'GameOverTitle', 'GameOverStats', 'RetryButton', 'MenuButton']) {
      expect(scene.findByName(name)!.enabled, isTrue, reason: name);
    }
    expect(text('GameOverStats'), contains('wave 1 with 1234 points'));
    expect(SaveData.instance.getInt('arena_best_score'), 1234);
    expect(SaveData.instance.getInt('arena_best_wave'), 1);
    expect(MouseLock.wanted, isFalse, reason: 'the mouse is free to click the buttons');
    // Robots stop when their target is down
    runUntil(() => false, 1);
    expect(robots.every((r) => r.getComponent<HealthComponent>()!.health > 0), isTrue);

    scriptOf('Arena').onUIAction('retry'); // the "Fight again" button
    runUntil(() => false, 0.2);
    expect(arena('state'), 'start');
    expect(arena('score'), 0);
    expect(scene.findByName('GameOverPanel')!.enabled, isFalse);
  });

  test('a busy wave renders within the frame budget', () {
    start(buildArenaLevel());
    // Put a full arena of robots in front of the player
    for (final kind in ['Drone', 'Drone', 'Drone', 'Drone', 'Gunner', 'Gunner', 'Gunner', 'Gunner', 'Brute', 'Brute', 'Drone', 'Gunner']) {
      final copy = scene.findByName(kind)!.clone()..enabled = true;
      copy.getComponent<Transform3DComponent>()!.position = Vector3((robots.length % 6 - 2.5) * 3, kind == 'Drone' ? 1.6 : 1.0, -4.0 - robots.length);
      scene.addEntity(copy);
    }
    engine.step();
    final cam = player.getComponent<Transform3DComponent>()!;
    final times = <double>[];
    for (var i = 0; i < 25; i++) {
      final sw = Stopwatch()..start();
      Renderer3D.renderScene(
        canvas: Canvas(ui.PictureRecorder()),
        size: const Size(1280, 720),
        engine: engine,
        cameraPosition: cam.worldPosition + Vector3(0, 0.72, 0),
        cameraRotation: cam.rotation,
        showGrid: false,
        showSelection: false,
      );
      if (i >= 5) times.add(sw.elapsedMicroseconds / 1000);
    }
    times.sort();
    // ignore: avoid_print
    print('arena frame: best ${times.first.toStringAsFixed(1)} ms, median ${times[times.length ~/ 2].toStringAsFixed(1)} ms, '
        '${Renderer3D.stats.triangles} triangles, ${Renderer3D.stats.objects} meshes');
    // The best frame: other test files running at the same time slow the median down
    expect(times.first, lessThan(12), reason: 'CPU side of a frame (debug build; release is faster)');
    expect(Renderer3D.stats.triangles, lessThan(4000));
  });
}

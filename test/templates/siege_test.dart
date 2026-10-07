import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/physics/rigid_body2d.dart';
import 'package:ember_engine/subsystems/two_d/line2d.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';
import 'package:ember_engine/templates/siege_game.dart';
import 'package:ember_engine/templates/siege_scripts.dart';

EmberEngine get engine => EmberEngine.instance;

EmberScriptBehavior scriptOf(String name) =>
    engine.activeScene.findByName(name)!.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
String get state => scriptOf('Siege').field('state') as String;
int get score => scriptOf('Siege').field('score') as int;
int get imps => engine.activeScene.allEntities.where((e) => e.enabled && e.tags.contains('imp')).length;
String text(String name) => engine.activeScene.findByName(name)!.getComponent<UITextComponent>()!.text;

void start(EmberScene scene) {
  engine.stop();
  EmberScripts.instance.loadAll(siegeScripts);
  engine.loadScene(scene);
  engine.step();
}

void runUntil(bool Function() done, double maxSeconds) {
  for (var i = 0; i < maxSeconds * 60 && !done(); i++) {
    engine.step();
  }
}

void waitToAim() => runUntil(() => state == 'aiming' || state == 'won' || state == 'lost', 4);

/// Fires each (angle, strength) shot once the slingshot is loaded, waiting for the castle to settle in between.
void playShots(List<(double, double)> shots) {
  for (final (angle, strength) in shots) {
    waitToAim();
    if (state != 'aiming') return;
    scriptOf('Slingshot').callFunction('fireAt', [angle, strength]);
    runUntil(() => state != 'flying' && state != 'settling', 14);
  }
  runUntil(() => state == 'won' || state == 'lost' || state == 'aiming', 6);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('siege test');
    for (final key in ['siege_unlocked', for (final l in Siege.levels) ...['siege_stars_$l', 'siege_best_$l']]) {
      SaveData.instance.remove(key);
    }
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
  });

  tearDown(() {
    Input.reset();
    engine.stop();
  });

  test('the template has a title and three levels, scripts that compile and art on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.siege).createProject(name: 'Siege');
    expect(project.scenes.keys, containsAll([Siege.title, ...Siege.levels]));
    expect(project.defaultSceneName, Siege.title);
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in siegeScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Siege.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  for (final (name, build) in [('Level 1', buildSiegeLevel1), ('Level 2', buildSiegeLevel2), ('Level 3', buildSiegeLevel3)]) {
    test('$name stands perfectly still until something hits it', () {
      start(build());
      final pieces = {
        for (final e in engine.activeScene.allEntities)
          if (e.tags.contains('breakable')) e: e.getComponent<Transform2DComponent>()!.position.clone(),
      };
      final impsAtStart = imps;
      expect(impsAtStart, greaterThanOrEqualTo(3));
      runUntil(() => false, 4);
      for (final MapEntry(key: e, value: p) in pieces.entries) {
        expect(e.getComponent<Transform2DComponent>()!.position, p, reason: '${e.name} moved by itself');
      }
      expect(imps, impsAtStart);
      expect(state, 'aiming', reason: 'the first shot is on the slingshot');
      expect(EmberScripts.instance.problems, isEmpty);
    });
  }

  test('Level 1: one well-aimed shot breaks the siege, saving stars and unlocking Level 2', () {
    start(buildSiegeLevel1());
    playShots([(25, 1.0)]);
    expect(imps, 0);
    expect(state, 'won');
    expect(score, greaterThanOrEqualTo(28000), reason: 'two unused shots: three stars');
    expect(SaveData.instance.getInt('siege_stars_Level 1'), 3);
    expect(SaveData.instance.getInt('siege_unlocked'), 2);
    expect(SaveData.instance.getInt('siege_best_Level 1'), score);
    expect(engine.activeScene.findByName('ResultsPanel')!.enabled, isTrue);
    expect(text('ResultsTitle'), 'SIEGE BROKEN!');
    expect(engine.activeScene.findByName('ResultsStars')!.getComponent<UIImageComponent>()!.filled, 3);
    final next = engine.activeScene.findByName('NextButton')!;
    expect(next.enabled, isTrue);
    expect(next.getComponent<UIButtonComponent>()!.action, 'level:Level 2');
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('Level 2 takes two shots (ember, then coal); a saved level replays the same', () {
    // Through save/load first: levels must play identically from their saved JSON
    start(EmberScene.fromJson(buildSiegeLevel2().toJson()));
    playShots([(55, 0.9)]);
    expect(imps, 1, reason: 'the first shot leaves one imp');
    expect(state, 'aiming');
    playShots([(45, 1.0)]);
    expect(state, 'won');
    expect(SaveData.instance.getInt('siege_unlocked'), 3);
  });

  test('Level 3 (the last) can be won; there is no Next button', () {
    start(buildSiegeLevel3());
    playShots([(40, 0.9)]);
    expect(state, 'won');
    expect(engine.activeScene.findByName('NextButton')!.enabled, isFalse);
    expect(engine.activeScene.findByName('MenuButton')!.enabled, isTrue);
  });

  test('missing with every shot loses the level', () {
    start(buildSiegeLevel1());
    playShots([(80, 0.4), (80, 0.4), (80, 0.4)]);
    expect(state, 'lost');
    expect(text('ResultsTitle'), 'OUT OF SHOTS');
    expect(text('ResultsScore'), '3 frost imps survived');
    expect(engine.activeScene.findByName('NextButton')!.enabled, isFalse);
    expect(SaveData.instance.has('siege_stars_Level 1'), isFalse);
  });

  test('dragging the shot back with the mouse (or a finger) and letting go launches it', () {
    start(buildSiegeLevel1());
    waitToAim();
    final pouch = scriptOf('Slingshot').callFunction('pouch', []) as Vector2;
    final shot = engine.activeScene.allEntities.firstWhere((e) => e.name == 'Ember' && e.enabled);
    expect(shot.getComponent<Transform2DComponent>()!.position, pouch);

    Input.instance.mouseWorldPosition = pouch.clone();
    Input.onMouseDown(0);
    engine.step();
    Input.instance.mouseWorldPosition = pouch + Vector2(-90, 60); // pull back and down
    engine.step();
    expect(shot.getComponent<Transform2DComponent>()!.position.distanceTo(pouch + Vector2(-90, 60)), lessThan(1),
        reason: 'the shot follows the drag (within the max pull)');
    final dots = engine.activeScene.findByName('Trajectory')!.getComponent<Line2DComponent>()!;
    expect(dots.points.length, 14, reason: 'aim preview while dragging');
    expect(dots.points.last.x, greaterThan(pouch.x + 100), reason: 'the preview points forward');
    Input.onMouseUp(0);
    engine.step();
    expect(state, 'flying');
    runUntil(() => false, 0.3);
    expect(shot.getComponent<Transform2DComponent>()!.position.x, greaterThan(pouch.x + 50), reason: 'flies forward');
    expect(shot.getComponent<Transform2DComponent>()!.position.y, lessThan(pouch.y), reason: 'and up');
  });

  test('a spark splits in three when tapped in flight', () {
    start(buildSiegeLevel3());
    waitToAim();
    scriptOf('Slingshot').callFunction('fireAt', [30.0, 0.9]);
    runUntil(() => false, 0.25);
    int sparks() => engine.activeScene.allEntities.where((e) => e.name == 'Spark' && e.enabled).length;
    expect(sparks(), 1);
    Input.onKeyDown(LogicalKeyboardKey.space);
    engine.step();
    Input.onKeyUp(LogicalKeyboardKey.space);
    engine.step();
    expect(sparks(), 3);
    final speeds = [
      for (final e in engine.activeScene.allEntities)
        if (e.name == 'Spark' && e.enabled) e.getComponent<RigidBody2DComponent>()!.velocity.length,
    ];
    expect(speeds.every((s) => s > 400), isTrue, reason: 'all three keep flying: $speeds');
  });

  test('a powder keg blows up: pieces nearby fly and break, and the other keg goes off too', () {
    start(buildSiegeLevel3());
    waitToAim();
    final keg = engine.activeScene.allEntities.firstWhere((e) => e.name == 'Powder Keg');
    final kegPos = keg.getComponent<Transform2DComponent>()!.position.clone();
    final before = engine.activeScene.allEntities.where((e) => e.tags.contains('breakable')).length;
    final scoreBefore = score;
    (keg.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior).callFunction('explode', []);
    runUntil(() => false, 2);
    expect(keg.scene, isNull, reason: 'the keg is gone');
    expect(engine.activeScene.allEntities.where((e) => e.tags.contains('breakable')).length, lessThan(before - 1),
        reason: 'the blast broke more than the keg');
    expect(score, greaterThan(scoreBefore + 500));
    expect(engine.activeScene.allEntities.where((e) => e.name == 'Powder Keg').length, 0, reason: 'chain reaction: the second keg went too');
    expect(kegPos.x, closeTo(1060, 1));
  });

  test('the title screen shows saved stars and locks levels not reached yet', () {
    SaveData.instance.setInt('siege_unlocked', 2);
    SaveData.instance.setInt('siege_stars_Level 1', 2);
    start(buildSiegeTitle());
    UIButtonComponent button(int i) => engine.activeScene.findByName('Level$i Button')!.getComponent<UIButtonComponent>()!;
    UIImageComponent stars(int i) => engine.activeScene.findByName('Level$i Stars')!.getComponent<UIImageComponent>()!;
    expect(button(1).action, 'level:Level 1');
    expect(stars(1).filled, 2);
    expect(button(2).action, 'level:Level 2');
    expect(button(3).text, 'Locked');
    expect(button(3).action, '');
    expect(EmberScripts.instance.problems, isEmpty);
  });
}

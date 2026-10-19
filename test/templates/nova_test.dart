import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/api.dart' show spawnCopy;
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/two_d/bullet_pool.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';
import 'package:ember_engine/templates/nova_game.dart';
import 'package:ember_engine/templates/nova_scripts.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';

EmberEngine get engine => EmberEngine.instance;
EmberEntity find(String name) => engine.activeScene.findByName(name)!;
EmberScriptBehavior scriptOf(EmberEntity e) => e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
EmberScriptBehavior get stage => scriptOf(find('Stage'));
EmberScriptBehavior get player => scriptOf(find('Ship'));
Object? field(String name) => stage.field(name);
String text(String name) => find(name).getComponent<UITextComponent>()!.text;
BulletPool2DComponent pool(String name) => find(name).getComponent<BulletPool2DComponent>()!;
List<EmberEntity> enemies() => engine.activeScene.allEntities.where((e) => e.enabled && e.tags.contains('enemy')).toList();

extension on EmberEntity {
  Transform2DComponent get _t => getComponent<Transform2DComponent>()!;
  double get x => _t.position.x;
  double get y => _t.position.y;
  set position(Vector2 p) => _t.position = p;
  bool get alive => engine.activeScene.allEntities.contains(this);
  Object? call(String fn, List<Object?> args) => scriptOf(this).callFunction(fn, args);
}

void startStage() {
  engine.stop();
  final project = TemplateCatalog.getByType(ProjectTemplateType.nova).createProject(name: 'Nova Test');
  EmberScripts.instance.loadAll(project.scripts);
  final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
  engine.sceneLibrary = () => levels;
  engine.loadScene(project.scenes[Nova.stage]!);
  engine.step();
}

void run(double seconds, {bool Function()? until}) {
  for (var i = 0; i < seconds * 60; i++) {
    if (until != null && until()) return;
    engine.step();
  }
}

/// Moves the ship out of harm's way (and keeps it there) while [seconds] pass.
void runSafely(double seconds, {bool Function()? until}) {
  for (var i = 0; i < seconds * 60; i++) {
    if (until != null && until()) return;
    pool('Enemy Shots').clear();
    find('Ship').getComponent<HealthComponent>()!.enabled = false;
    engine.step();
  }
  find('Ship').getComponent<HealthComponent>()!.enabled = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('nova test');
    SaveData.instance.remove('nova_best');
    SaveData.instance.remove('nova_loop');
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() {
    Input.reset();
    engine.timeScale = 1;
    engine.stop();
  });

  test('the template: title and stage, scripts that compile, art and sound on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.nova).createProject(name: 'Nova');
    expect(project.scenes.keys, containsAll([Nova.title, Nova.stage]));
    expect(project.defaultSceneName, Nova.title);
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in novaScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Nova.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/templates/nova/'));
  });

  test('the ship fires by itself, flies with the keys and stays on screen', () {
    startStage();
    run(0.5);
    expect(pool('Player Shots').count, greaterThan(4));
    final ship = find('Ship');
    final x = ship.x;
    Input.onKeyDown(LogicalKeyboardKey.arrowRight);
    run(0.5);
    Input.onKeyUp(LogicalKeyboardKey.arrowRight);
    expect(ship.x, closeTo(x + 170, 6));
    Input.onKeyDown(LogicalKeyboardKey.arrowUp);
    run(3);
    Input.onKeyUp(LogicalKeyboardKey.arrowUp);
    expect(ship.y, 34, reason: 'kept on screen');
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('waves arrive on time, enemies shoot, and destroying them scores and drops crystals', () {
    startStage();
    runSafely(2.2);
    expect(enemies().where((e) => e.name == 'Drone'), isNotEmpty, reason: 'the first drones at 2 s');
    // Put a drone in front of the guns
    final drone = enemies().firstWhere((e) => e.name == 'Drone');
    find('Ship').position = Vector2(drone.x - 200, drone.y);
    runSafely(1.5, until: () => !drone.alive);
    expect(drone.alive, isFalse);
    expect(field('kills'), greaterThanOrEqualTo(1));
    expect(field('score'), greaterThanOrEqualTo(100));
    expect(engine.activeScene.allEntities.where((e) => e.enabled && e.name == 'Crystal'), isNotEmpty);
    runSafely(1);
    expect(text('ScoreText'), isNot('0'));
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('crystals fly to the ship and raise the multiplier; grazing scores', () {
    startStage();
    run(0.1);
    final crystal = engine.activeScene.findByName('Crystal')!;
    spawnCopy(crystal, Vector2(300, 270));
    final mult = field('mult') as num;
    runSafely(1.5);
    expect(field('mult'), greaterThan(mult));
    expect(crystal.enabled, isFalse, reason: 'the template stays hidden');

    final score = field('score') as num;
    find('Ship').position = Vector2(300, 270);
    pool('Enemy Shots').fire(900, 284, 180, 900, radius: 4);
    run(0.9);
    expect(field('grazes'), 1);
    expect(field('score'), greaterThan(score));
    expect(field('lives'), 3, reason: 'a graze is not a hit');
  });

  test('a hit costs a life and a power level, clears the bullets, and the ship comes back blinking', () {
    startStage();
    run(2.2); // spawn protection over
    stage.callFunction('collect', ['power']);
    expect(field('power'), 2);
    final ship = find('Ship');
    pool('Enemy Shots').ring(ship.x - 300, ship.y, 1, 0); // a decoy elsewhere
    pool('Enemy Shots').fire(ship.x + 200, ship.y, 180, 900, radius: 6);
    run(0.4);
    expect(field('lives'), 2);
    expect(field('power'), 1);
    expect(field('mult'), 1.0);
    expect(pool('Enemy Shots').count, 0);
    expect(player.field('dead'), isTrue);
    run(1.6);
    expect(player.field('dead'), isFalse);
    expect(ship.getComponent<HealthComponent>()!.enabled, isFalse, reason: 'protected while blinking');
    run(2.5);
    expect(ship.getComponent<HealthComponent>()!.enabled, isTrue);
  });

  test('a bomb clears every bullet, hurts every enemy and is used up; a shield takes one hit', () {
    startStage();
    run(2.2);
    pool('Enemy Shots').ring(700, 270, 40, 0);
    Input.onKeyDown(LogicalKeyboardKey.keyX);
    engine.step();
    Input.onKeyUp(LogicalKeyboardKey.keyX);
    expect(pool('Enemy Shots').count, 0);
    expect(field('bombs'), 1);
    expect(field('score'), greaterThanOrEqualTo(400), reason: '10 points per bullet cleared');
    run(2.2);

    find('Ship').call('collect', ['shield']);
    expect(find('Ship').findChild('Shield')!.enabled, isTrue);
    pool('Enemy Shots').fire(find('Ship').x + 150, find('Ship').y, 180, 900, radius: 6);
    run(0.4);
    expect(field('lives'), 3, reason: 'the shield took it');
    expect(find('Ship').findChild('Shield')!.enabled, isFalse);
  });

  test('after the waves: a warning, the boss, three phases, and stage clear with a bonus', () {
    startStage();
    stage.setField('stageLength', 1.0);
    for (final e in enemies()) {
      e.enabled = false;
    }
    runSafely(1.5);
    expect(field('state'), 'warning');
    runSafely(3.5);
    expect(field('state'), 'boss');
    final boss = enemies().firstWhere((e) => e.name == 'Boss');
    runSafely(8, until: () => scriptOf(boss).field('phase') == 1);
    expect(scriptOf(boss).field('phase'), 1);
    expect(find('BossBar').enabled, isTrue);
    final health = boss.getComponent<HealthComponent>()!;
    runSafely(1.2);
    health.damage(health.maxHealth * 0.4);
    runSafely(0.2);
    expect(scriptOf(boss).field('phase'), 2);
    runSafely(1.5);
    expect(pool('Enemy Shots').count, 0, reason: 'cleared each frame by this test');
    health.damage(health.maxHealth * 0.3);
    runSafely(0.2);
    expect(scriptOf(boss).field('phase'), 3);
    health.damage(health.health);
    runSafely(7, until: () => field('state') == 'clear');
    expect(field('state'), 'clear');
    expect(find('NextButton').enabled, isTrue);
    expect(text('ResultsTitle'), 'STAGE CLEAR');
    expect(field('score'), greaterThan(50000));
    expect(SaveData.instance.getInt('nova_best'), field('score'));
    expect(EmberScripts.instance.problems, isEmpty);

    // The next loop keeps score, lives, bombs and power, and is harder
    final score = field('score');
    UIRenderer.dispatch(engine.activeScene, 'next');
    run(1.5, until: () => field('loop') == 2);
    expect(field('loop'), 2);
    expect(field('score'), score);
  });

  test('losing every life ends the game; Retry starts over', () {
    startStage();
    for (var i = 0; i < 3 && field('lives') != 0; i++) {
      run(6, until: () => find('Ship').getComponent<HealthComponent>()!.enabled && player.field('dead') == false);
      final ship = find('Ship');
      pool('Enemy Shots').fire(ship.x + 100, ship.y, 180, 900, radius: 6);
      run(0.3);
    }
    expect(field('lives'), 0);
    expect(field('state'), 'over');
    run(2);
    expect(text('ResultsTitle'), 'GAME OVER');
    expect(find('RetryButton').enabled, isTrue);
    UIRenderer.dispatch(engine.activeScene, 'retry');
    run(1.5, until: () => field('lives') == 3);
    expect(field('lives'), 3);
    expect(field('loop'), 1);
  });

  test('P pauses the game and freezes the bullets', () {
    startStage();
    pool('Enemy Shots').fire(480, 100, 90, 100);
    Input.onKeyDown(LogicalKeyboardKey.keyP);
    engine.step();
    Input.onKeyUp(LogicalKeyboardKey.keyP);
    expect(find('PausedText').enabled, isTrue);
    final y = pool('Enemy Shots').bullets.first.y;
    run(1);
    expect(pool('Enemy Shots').bullets.first.y, y);
    UIRenderer.dispatch(engine.activeScene, 'resume');
    run(0.2);
    expect(pool('Enemy Shots').bullets.first.y, greaterThan(y));
  });

  test('the title shows the best score and starts the stage', () {
    SaveData.instance.setInt('nova_best', 12345);
    engine.stop();
    final project = TemplateCatalog.getByType(ProjectTemplateType.nova).createProject(name: 'Nova Test');
    EmberScripts.instance.loadAll(project.scripts);
    final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
    engine.sceneLibrary = () => levels;
    engine.loadScene(project.scenes[Nova.title]!);
    engine.step();
    expect(text('BestText'), contains('12345'));
    UIRenderer.dispatch(engine.activeScene, 'start');
    run(1.5, until: () => engine.activeScene.name == Nova.stage);
    expect(engine.activeScene.name, Nova.stage);
  });
}

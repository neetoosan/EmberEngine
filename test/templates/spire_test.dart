import 'dart:io';
import 'package:flutter/services.dart';
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
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/physics/character_controller2d.dart';
import 'package:ember_engine/subsystems/two_d/camera2d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/ui/minimap.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/templates/spire_game.dart';
import 'package:ember_engine/templates/spire_layout.dart';
import 'package:ember_engine/templates/spire_scripts.dart';
import 'package:vector_math/vector_math_64.dart';

EmberEngine get engine => EmberEngine.instance;
EmberEntity find(String name) => engine.activeScene.findByName(name)!;
EmberScriptBehavior scriptOf(EmberEntity e) => e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
EmberScriptBehavior get game => scriptOf(find('World'));
String text(String name) => find(name).getComponent<UITextComponent>()!.text;
EmberEntity get hero => find('Hero');
CharacterController2DComponent get ctl => hero.getComponent<CharacterController2DComponent>()!;
Vector2 pos(EmberEntity e) => e.getComponent<Transform2DComponent>()!.position;
void place(EmberEntity e, Vector2 at) => e.getComponent<Transform2DComponent>()!.position = at;
Vector2 cell(int c, int r) => Vector2(c * 32 + 16, r * 32 + 16);

void startWorld({bool resume = false}) {
  engine.stop();
  final project = TemplateCatalog.getByType(ProjectTemplateType.spire).createProject(name: 'Spire Test');
  EmberScripts.instance.loadAll(project.scripts);
  final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
  engine.sceneLibrary = () => levels;
  engine.loadScene(project.scenes[Spire.world]!);
  engine.step();
  if (resume) {
    EmberScripts.instance.gameData['spireContinue'] = true;
    engine.restartScene();
    engine.step();
  }
}

void run(double seconds, {bool Function()? until}) {
  for (var i = 0; i < seconds * 60; i++) {
    if (until != null && until()) return;
    engine.step();
  }
}

void hold(LogicalKeyboardKey k) => Input.onKeyDown(k);
void release(LogicalKeyboardKey k) => Input.onKeyUp(k);
void tap(LogicalKeyboardKey k) {
  Input.onKeyDown(k);
  engine.step();
  Input.onKeyUp(k);
}

/// A bare body with the hero's controller on the real map, for testing reach.
(EmberEntity, CharacterController2DComponent) body(Vector2 at, {int airJumps = 0, bool wallJump = false, double dash = 0}) {
  engine.stop();
  final project = TemplateCatalog.getByType(ProjectTemplateType.spire).createProject(name: 'Reach');
  final world = project.scenes[Spire.world]!.findByName('World')!;
  final c = CharacterController2DComponent(moveSpeed: 230, jumpVelocity: 640, gravity: 1600, groundY: 1e6, airJumps: airJumps, wallJump: wallJump, dashSpeed: dash);
  final e = EmberEntity(name: 'Body')
    ..addComponent(Transform2DComponent(position: at, size: Vector2(20, 36), anchor: EmberAnchor.center))
    ..addComponent(c);
  final scene = EmberScene(name: 'Reach')
    ..addEntity(EmberEntity(name: 'World')
      ..addComponent(Transform2DComponent(position: Vector2.zero(), size: Vector2(SpireLayout.columns * 32.0, SpireLayout.rows * 32.0)))
      ..addComponent(world.getComponent<FlameTileMapComponent>()!.clone()))
    ..addEntity(e);
  engine.loadScene(scene);
  engine.step();
  return (e, c);
}

void steps(CharacterController2DComponent c, int n, {double x = 0, bool held = false, bool pressed = false}) {
  for (var i = 0; i < n; i++) {
    c.updateMovement(horizontalInput: x, isJumpPressed: held || pressed, isJumpJustPressed: pressed && i == 0, dt: 1 / 60);
  }
}

bool onSpikes(EmberEntity e) {
  final m = engine.activeScene.findByName('World')!.getComponent<FlameTileMapComponent>()!;
  final p = pos(e);
  return m.getTile((p.x / 32).floor(), ((p.y + 20) / 32).floor()) == 7;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('spire test');
    SaveData.instance.remove('spire_save');
    SaveData.instance.remove('spire_best');
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() {
    Input.reset();
    engine.timeScale = 1;
    engine.stop();
  });

  test('the template: title and world, scripts that compile, art and sound on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.spire).createProject(name: 'Spire');
    expect(project.scenes.keys, containsAll([Spire.title, Spire.world]));
    expect(project.defaultSceneName, Spire.title);
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in spireScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Spire.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/templates/spire/'));
  });

  test('a new game starts in Cinder Hollow: walls auto-tiled, the camera keeps to the room, the minimap fills in', () {
    startWorld();
    run(0.5);
    expect(EmberScripts.instance.problems, isEmpty);
    final m = find('World').getComponent<FlameTileMapComponent>()!;
    expect(m.tiles.contains(1), isFalse);
    expect(m.tiles.where((t) => t >= 10 && t <= 25).length, greaterThan(1500));
    expect(text('RoomText'), 'Cinder Hollow');
    final cam = find('Camera').getComponent<Camera2DComponent>()!;
    expect(cam.room?.entity?.name, 'Cinder Hollow');
    expect(cam.position.x, closeTo(480, 1));
    expect(cam.position.y, closeTo(17 * 32 + 272, 1));
    final mini = find('Minimap').getComponent<UIMinimapComponent>()!;
    expect(mini.exploredFraction, closeTo(1 / 9, 0.01));
    expect(ctl.airJumps, 0);
    expect(ctl.dashSpeed, 0);
  });

  test('run, jump and swing: a crawler is cut down', () {
    startWorld();
    run(1);
    final start = pos(hero).clone();
    hold(LogicalKeyboardKey.keyD);
    run(0.5);
    release(LogicalKeyboardKey.keyD);
    expect(pos(hero).x - start.x, greaterThan(60));
    hold(LogicalKeyboardKey.space);
    run(0.3);
    expect(ctl.isGrounded, isFalse);
    release(LogicalKeyboardKey.space);
    run(1.5);
    expect(ctl.isGrounded, isTrue);

    final crawler = engine.activeScene.allEntities.firstWhere((e) => e.name == 'Crawler' && e.enabled);
    place(crawler, pos(hero) + Vector2(36, -2));
    hero.getComponent<HealthComponent>()!.enabled = false; // don't get bumped meanwhile
    for (var i = 0; i < 4 && engine.activeScene.allEntities.contains(crawler); i++) {
      ctl.facing = 1;
      tap(LogicalKeyboardKey.keyJ);
      run(0.4);
      if (engine.activeScene.allEntities.contains(crawler)) place(crawler, pos(hero) + Vector2(36, -2));
    }
    run(0.1);
    expect(engine.activeScene.allEntities.contains(crawler), isFalse);
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('orbs give abilities that are saved at once; spikes cost a heart and put you back on solid ground', () {
    startWorld();
    run(0.5);
    place(hero, pos(find('Double Jump Orb')));
    run(0.2);
    expect(ctl.airJumps, 1);
    expect(text('Banner'), 'DOUBLE JUMP');
    expect((SaveData.instance.getMap('spire_save')!['abilities'] as Map)['double'], isTrue);
    expect(engine.activeScene.findByName('Double Jump Orb'), isNull);

    run(3);
    final safe = pos(hero).clone();
    final spikes = SpireLayout.grid();
    var spike = Vector2.zero();
    for (var r = 0; r < spikes.length && spike == Vector2.zero(); r++) {
      final c = spikes[r].indexOf('^');
      if (c >= 0) spike = cell(c, r - 1);
    }
    place(hero, spike);
    run(0.5);
    expect(hero.getComponent<HealthComponent>()!.health, 3);
    expect(pos(hero).distanceTo(spike), greaterThan(100), reason: 'back where it last stood safely');
    expect(pos(hero).distanceTo(safe), lessThan(80));
  });

  test('the Sunken Halls pits need the dash; the Crystal Gallery shaft needs the wall jump', () {
    // Left pit of the Sunken Halls: floor ends at column 8 of the room (map column 38), row 14 (map row 48)
    bool crossed(double dash, int airJumps) {
      final (e, c) = body(cell(30 + 8, 34 + 14), airJumps: airJumps, dash: dash);
      steps(c, 30);
      steps(c, 1, x: -1, pressed: true);
      steps(c, 8, x: -1, held: true);
      if (airJumps > 0) steps(c, 1, x: -1, pressed: true);
      if (dash > 0) c.dash();
      steps(c, 50, x: -1, held: true);
      return pos(e).x < (30 + 3) * 32 && !onSpikes(e);
    }

    expect(crossed(0, 1), isFalse, reason: 'double jump alone hits the low ceiling and falls short');
    expect(crossed(720, 1), isTrue, reason: 'the dash carries you over');

    // Crystal Gallery shaft (columns 86-88), from the gallery floor up into the Upper Spire
    double climb(bool wallJump) {
      final (e, c) = body(cell(60 + 27, 17 + 14), airJumps: 1, wallJump: wallJump);
      steps(c, 30);
      var side = 1.0;
      for (var i = 0; i < 400; i++) {
        final jump = c.isGrounded || c.onWall != 0 || (i % 40 == 10);
        if (c.onWall != 0) side = -c.onWall.toDouble();
        steps(c, 1, x: c.onWall != 0 ? c.onWall.toDouble() : side, pressed: jump);
        steps(c, 5, x: side, held: true);
      }
      return pos(e).y;
    }

    expect(climb(false), greaterThan(17 * 32.0), reason: 'stuck in the gallery');
    expect(climb(true), lessThan(17 * 32.0), reason: 'zig-zagged up into the Upper Spire');
  });

  test('resting at a shrine saves; falling brings you back there with everything you found', () {
    startWorld();
    run(0.5);
    final shrine = engine.activeScene.allEntities.firstWhere((e) => e.tags.contains('save'));
    final shrineAt = pos(shrine).clone();
    place(hero, shrineAt + Vector2(10, 0));
    run(0.3);
    expect(text('Prompt'), contains('rest'));
    tap(LogicalKeyboardKey.keyW);
    run(0.1);
    expect(SaveData.instance.getMap('spire_save')!['spawn'], isNotNull);
    place(hero, pos(find('Double Jump Orb')));
    run(0.2);

    final h = hero.getComponent<HealthComponent>()!..invulnerableTime = 0;
    for (var i = 0; i < 4; i++) {
      h.damage(1);
    }
    run(2.5, until: () => game.field('state') == 'play' && game.field('deaths') == 1);
    run(0.2);
    expect(game.field('deaths'), 1);
    expect(ctl.airJumps, 1, reason: 'the double jump was kept');
    expect(pos(hero).distanceTo(shrineAt), lessThan(40));
    expect(engine.activeScene.findByName('Double Jump Orb'), isNull);
    expect(hero.getComponent<HealthComponent>()!.health, 4);
  });

  test('the Thornback wakes in its throne room; beating it reveals the Ember Heart, which ends the game', () {
    startWorld();
    run(0.5);
    hero.getComponent<HealthComponent>()!.enabled = false;
    place(hero, cell(20, 12));
    run(1);
    expect(text('RoomText'), 'Ember Throne');
    expect(find('BossBar').enabled, isTrue);
    final boss = find('Thornback');
    expect(scriptOf(boss).field('state'), isNot('sleep'));
    run(4);
    expect(EmberScripts.instance.problems, isEmpty, reason: 'it walks, charges and slams');
    final bh = boss.getComponent<HealthComponent>()!..invulnerableTime = 0;
    bh.damage(bh.maxHealth);
    run(0.2);
    expect(find('Ember Heart').enabled, isTrue);
    expect(game.field('bossDown'), isTrue);
    place(hero, pos(find('Ember Heart')));
    run(0.3);
    expect(game.field('state'), 'won');
    expect(text('ResultsTitle'), 'THE EMBER HEART');
    expect(SaveData.instance.has('spire_best'), isTrue);
    expect(SaveData.instance.has('spire_save'), isFalse);
  });

  test('walking right from the start picks up the double jump before the hole to the Sunken Halls', () {
    startWorld();
    run(0.5);
    hero.getComponent<HealthComponent>()!.enabled = false;
    hold(LogicalKeyboardKey.keyD);
    run(12, until: () => pos(hero).y > 34 * 32);
    release(LogicalKeyboardKey.keyD);
    expect(ctl.airJumps, 1);
  });

  test('the title offers Continue only when there is a save', () {
    void title() {
      engine.stop();
      final project = TemplateCatalog.getByType(ProjectTemplateType.spire).createProject(name: 'Spire');
      EmberScripts.instance.loadAll(project.scripts);
      engine.loadScene(project.scenes[Spire.title]!);
      engine.step();
    }

    title();
    expect(find('ContinueButton').enabled, isFalse);
    SaveData.instance.setMap('spire_save', {'abilities': {'double': true, 'dash': false, 'wall': false}});
    title();
    expect(find('ContinueButton').enabled, isTrue);
    expect(EmberScripts.instance.problems, isEmpty);
  });
}

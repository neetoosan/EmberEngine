import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/project_storage.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/physics/character_controller2d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/templates/quest_game.dart';
import 'package:ember_engine/templates/quest_scripts.dart';

EmberEngine get engine => EmberEngine.instance;
EmberEntity? get heroEntity => engine.activeScene.findByName('Hero');
EmberScriptBehavior get hero => heroEntity!.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
Transform2DComponent get heroT => heroEntity!.getComponent<Transform2DComponent>()!;
CharacterController2DComponent get heroCc => heroEntity!.getComponent<CharacterController2DComponent>()!;
FlameTileMapComponent get map => engine.activeScene.findByName('Level')!.getComponent<FlameTileMapComponent>()!;
String text(String e) => engine.activeScene.findByName(e)!.getComponent<UITextComponent>()!.text;

/// Lives, score, coins and size are kept in Game.data by the hero script.
Map<Object?, Object?> get session => EmberScripts.instance.gameData;
String get heroState => hero.field('state') as String;

bool isSquashed(EmberEntity enemy) {
  final s = enemy.getComponent<ScriptComponent>()?.scriptInstance;
  return s is EmberScriptBehavior && s.field('squashed') == true;
}

void frames(int n, {Set<LogicalKeyboardKey> hold = const {}}) {
  for (var i = 0; i < n; i++) {
    for (final k in hold) {
      Input.onKeyDown(k);
    }
    engine.step();
  }
  for (final k in hold) {
    Input.onKeyUp(k);
  }
}

/// Puts the hero's feet at the bottom of cell ([c], [r]) standing still.
void placeHero(int c, int r) {
  heroT.position = Vector2(c * 32 + 16.0, (r + 1) * 32.0);
  heroCc.velocity.setValues(0, 0);
}

void jump({int hold = 20}) => frames(hold, hold: {LogicalKeyboardKey.space});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Map<String, dynamic>> library;

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    EmberScripts.instance.loadAll(questScripts);
    library = {'Level 1': buildQuestLevel1().toJson(), 'Level 2': buildQuestLevel2().toJson()};
    engine.sceneLibrary = () => library;
    engine.loadScene(EmberScene.fromJson(library['Level 1']!));
    engine.step();
  });

  tearDown(() {
    expect(EmberScripts.instance.problems.map((p) => '$p'), isEmpty, reason: 'scripts ran without errors');
    engine.stop();
    engine.sceneLibrary = null;
  });

  test('template: two levels, starts in Level 1, editable scripts, all art and music bundled', () async {
    final project = TemplateCatalog.getByType(ProjectTemplateType.quest).createProject(name: 'Quest');
    expect(project.scenes.keys, ['Level 1', 'Level 2']);
    expect(project.defaultSceneName, 'Level 1');
    expect(project.scripts.keys, containsAll(questScripts.keys));
    for (final e in project.scripts.entries) {
      expect(EmberScripts.check(e.key, e.value), isNull, reason: e.key);
    }
    final files = {...ProjectStorage.referencedAssetPaths(project), ...project.assets};
    expect(files, contains(Quest.music));
    for (final f in files) {
      expect((await rootBundle.load(f)).lengthInBytes, greaterThan(0), reason: f);
    }
    expect(text('Hud'), contains('WORLD 1-1'));
    expect(text('Banner'), 'WORLD 1-1');
  });

  test('runs right and jumps', () {
    final x0 = heroT.position.x;
    frames(30, hold: {LogicalKeyboardKey.keyD});
    expect(heroT.position.x, greaterThan(x0 + 60));
    expect(heroCc.isGrounded, isTrue);
    final y0 = heroT.position.y;
    jump(hold: 12);
    expect(heroT.position.y, lessThan(y0 - 50));
  });

  test('"?" block gives a coin and becomes used', () {
    placeHero(10, 9); // coin block at (10, 6)
    frames(5);
    jump();
    expect(map.getTile(10, 6), Quest.usedBlock);
    expect(session['coins'], 1);
    frames(1);
    expect(text('Hud'), contains('COINS x01'));
  });

  test('power block spawns a berry; eating it makes the hero big, and big heroes break bricks', () {
    // Keep slimes out of this test (Slime_1 would walk over and interrupt)
    for (final e in engine.activeScene.allEntities.where((e) => e.tags.contains('enemy')).toList()) {
      engine.activeScene.removeEntity(e);
    }
    placeHero(15, 9); // power block at (15, 6)
    frames(5);
    jump();
    expect(map.getTile(15, 6), Quest.usedBlock);
    final berry = engine.activeScene.rootEntities.where((e) => e.name == 'Berry Template' && e.enabled).firstOrNull;
    expect(berry, isNotNull, reason: 'a copy of the berry template was spawned');

    // The berry slides off the block and lands; then the hero touches it
    frames(150);
    final bt = berry!.getComponent<Transform2DComponent>()!;
    expect(bt.position.y, closeTo(320, 0.5), reason: 'berry landed on the ground');
    heroT.position = Vector2(bt.position.x, 320);
    frames(10);
    expect(hero.field('big'), isTrue);
    expect(heroT.size.y, 48);
    expect(berry.scene, isNull);

    // A small hero only bumps bricks; a big one breaks them
    placeHero(14, 9); // brick at (14, 6)
    frames(5);
    jump();
    expect(map.getTile(14, 6), 0, reason: 'big hero broke the brick');
  });

  test('small heroes cannot break bricks', () {
    placeHero(14, 9);
    frames(5);
    jump();
    expect(map.getTile(14, 6), Quest.brick);
  });

  test('landing on a slime squashes it and bounces; walking into one hurts', () {
    final slime = engine.activeScene.findByName('Slime_1')!;
    final st = slime.getComponent<Transform2DComponent>()!;
    // Drop onto it from above
    heroT.position = Vector2(st.position.x, st.position.y - 90);
    heroCc.velocity.setValues(0, 0);
    frames(40);
    expect(isSquashed(slime), isTrue);
    expect(session['score'] as int, greaterThanOrEqualTo(100));
    expect(heroState, 'playing');

    // Walk into the next slime while small: the hero dies and loses a life
    final other = engine.activeScene.findByName('Slime_2')!.getComponent<Transform2DComponent>()!;
    heroT.position = Vector2(other.position.x - 60, other.position.y);
    heroCc.velocity.setValues(0, 0);
    for (var i = 0; i < 120 && heroState == 'playing'; i++) {
      frames(1, hold: {LogicalKeyboardKey.keyD});
    }
    expect(heroState, 'dead');
    final deadScene = engine.activeScene;
    frames(160); // death animation, then the level restarts
    expect(session['lives'], 2);
    expect(identical(engine.activeScene, deadScene), isFalse);
    expect(engine.activeScene.name, 'Level 1');
    expect(heroState, 'playing');
  });

  test('a big hero that gets hurt shrinks and blinks instead of dying', () {
    session['big'] = true;
    engine.restartScene();
    engine.step();
    expect(hero.field('big'), isTrue);
    hero.callFunction('hurt', []);
    expect(hero.field('big'), isFalse);
    expect(hero.field('invulnerable') as double, greaterThan(0));
    hero.callFunction('hurt', []); // still invulnerable
    expect(heroState, 'playing');
  });

  test('falling into a pit costs a life; losing the last life is game over', () {
    session['lives'] = 1;
    placeHero(45, 5); // above the first pit (45-46)
    frames(60);
    expect(heroState, 'dead');
    frames(160);
    expect(text('Banner'), 'GAME OVER');
    frames(200);
    expect(session['lives'], 3, reason: 'game restarted from scratch');
    expect(engine.activeScene.name, 'Level 1');
  });

  test('reaching the flag clears Level 1, loads Level 2, and clearing it wins', () {
    final goal = engine.activeScene.findByName('Goal')!.getComponent<Transform2DComponent>()!;
    placeHero((goal.position.x / 32).floor() - 1, 9);
    frames(40, hold: {LogicalKeyboardKey.keyD});
    expect(heroState, 'cleared');
    expect(text('Banner'), 'LEVEL CLEAR!');
    frames(190); // celebration, then a short fade
    expect(engine.activeScene.name, 'Level 2');
    expect(text('Hud'), contains('WORLD 1-2'));

    final goal2 = engine.activeScene.findByName('Goal')!.getComponent<Transform2DComponent>()!;
    placeHero((goal2.position.x / 32).floor() - 1, 9);
    frames(40, hold: {LogicalKeyboardKey.keyD});
    frames(170);
    expect(text('Banner'), contains('YOU WIN'));
  });

  /// Holds right and run; jumps at walls, before pits, spikes and nearby slimes.
  bool autopilot(String level, {int maxSeconds = 60}) {
    engine.loadLevel(level);
    engine.step();
    session['lives'] = 99;
    for (var i = 0; i < maxSeconds * 60; i++) {
      if (engine.activeScene.name != level) return true; // moved on to the next level
      final h = heroEntity;
      if (h == null) continue;
      if (heroState == 'cleared') {
        frames(1);
        continue;
      }
      final t = heroT, cc = heroCc;
      final aheadX = t.position.x + 26;
      final pitAhead = cc.isGrounded && !cc.hasGroundAt(aheadX + 10, t.position.y + 8);
      final enemyAhead = engine.activeScene.allEntities.any((e) {
        if (!e.tags.contains('enemy') || isSquashed(e)) return false;
        final et = e.getComponent<Transform2DComponent>()!;
        final dx = et.position.x - t.position.x;
        return dx > 0 && dx < 90 && (et.position.y - t.position.y).abs() < 40;
      });
      final hazardAhead = map
          .tilesIn(Rect.fromLTWH(t.position.x + 10, t.position.y - 20, 50, 16))
          .any((tile) => tile.kind == TileKind.hazard);
      final wantJump = cc.hitWall || pitAhead || enemyAhead || hazardAhead || !cc.isGrounded && cc.velocity.y < 0;
      frames(1, hold: {LogicalKeyboardKey.keyD, LogicalKeyboardKey.shiftLeft, if (wantJump) LogicalKeyboardKey.space});
    }
    return false;
  }

  test('an autopilot that just runs and jumps can finish both levels', () {
    expect(autopilot('Level 1'), isTrue, reason: 'Level 1 is completable');
    expect(autopilot('Level 2'), isTrue, reason: 'Level 2 is completable');
  });
}

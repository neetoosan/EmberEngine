import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/project_storage.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/subsystems/ai/monster_ai.dart';
import 'package:ember_engine/subsystems/ai/pathfinding.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/physics/tile_collision.dart';
import 'package:ember_engine/subsystems/ui/dialogue.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';
import 'package:ember_engine/templates/legends_game.dart';

EmberEngine get engine => EmberEngine.instance;
EmberScene get scene => engine.activeScene;
EmberEntity? get heroEntity => scene.findByName('Hero');
LegendsHero get hero => heroEntity!.getComponent<ScriptComponent>()!.scriptInstance as LegendsHero;
HealthComponent get heroHealth => heroEntity!.getComponent<HealthComponent>()!;
Vector2 get heroCenter => Legends.centerOf(heroEntity!);
String text(String e) => scene.findByName(e)!.getComponent<UITextComponent>()!.text;

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

/// Taps [key] for one frame.
void tap(LogicalKeyboardKey key) {
  Input.onKeyDown(key);
  engine.step();
  Input.onKeyUp(key);
  engine.step();
}

/// Moves the hero so its body centre is at [c].
void placeHero(Vector2 c) {
  final t = heroEntity!.getComponent<Transform2DComponent>()!;
  t.position = t.position + (c - heroCenter);
}

Vector2 cell(int c, int r) => Vector2((c + 0.5) * 32, (r + 0.5) * 32);

void clearMonsters() {
  for (final e in scene.allEntities.where((e) => e.tags.contains('monster')).toList()) {
    scene.removeEntity(e);
  }
}

List<EmberEntity> get monsters => scene.allEntities.where((e) => e.tags.contains('monster') && e.enabled).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Map<String, dynamic>> library;

  void start(String name) {
    engine.loadScene(EmberScene.fromJson(library[name]!));
    engine.step();
  }

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    LegendsSession.reset();
    SaveSlots.delete(Legends.saveSlot);
    Legends.rng = math.Random(7);
    library = {
      Legends.title: buildLegendsTitle().toJson(),
      Legends.village: buildLegendsVillage().toJson(),
      Legends.field: buildLegendsField().toJson(),
      Legends.dungeon: buildLegendsDungeon().toJson(),
    };
    engine.sceneLibrary = () => library;
  });

  tearDown(() {
    engine.stop();
    engine.sceneLibrary = null;
  });

  test('template: four scenes, starts on the title, all art and music bundled', () async {
    final project = TemplateCatalog.getByType(ProjectTemplateType.legends).createProject(name: 'Legends');
    expect(project.scenes.keys, [Legends.title, Legends.village, Legends.field, Legends.dungeon]);
    expect(project.defaultSceneName, Legends.title);
    final files = {...ProjectStorage.referencedAssetPaths(project), ...project.assets};
    expect(files, containsAll([Legends.music, Legends.dungeonMusic, '${Legends.art}/arrow.png', '${Legends.art}/slash.png']));
    for (final f in files) {
      expect((await rootBundle.load(f)).lengthInBytes, greaterThan(0), reason: f);
    }
    // Every game scene has a hero and a HUD
    for (final name in [Legends.village, Legends.field, Legends.dungeon]) {
      final s = project.scenes[name]!;
      expect(s.findByName('Hero'), isNotNull, reason: name);
      expect(s.findByName('Hearts'), isNotNull, reason: name);
    }
  });

  test('title: New Game goes to the village; Continue only shows with a save', () {
    start(Legends.title);
    expect(scene.findByName('Continue')!.enabled, isFalse);
    UIRenderer.dispatch(scene, 'new');
    frames(2);
    expect(scene.name, Legends.village);
    expect(text('Banner'), 'Oakvale Village');
    expect(text('Hint'), contains('Elder'));

    Legends.save(heroEntity!);
    engine.loadLevel(Legends.title);
    frames(2);
    expect(scene.findByName('Continue')!.enabled, isTrue);
  });

  test('walks, is blocked by trees and water, and travels through doors', () {
    start(Legends.village);
    final c0 = heroCenter.clone();
    frames(30, hold: {LogicalKeyboardKey.keyD});
    expect(heroCenter.x, greaterThan(c0.x + 40));
    frames(200, hold: {LogicalKeyboardKey.keyS});
    expect(heroCenter.y, lessThan(19 * 32), reason: 'tree border stops the hero');

    placeHero(cell(27, 9));
    for (var i = 0; i < 60 && scene.name == Legends.village; i++) {
      frames(1, hold: {LogicalKeyboardKey.keyD});
    }
    expect(scene.name, Legends.field);
    expect(heroCenter.distanceTo(cell(1, 13)), lessThan(4), reason: 'arrives at "From Village"');
    frames(30); // fade back in
    expect(UIRenderer.fade, 0);

    // ...and back: the door you arrive next to does not bounce you back
    frames(40, hold: {LogicalKeyboardKey.keyA});
    expect(scene.name, Legends.village);
    expect(heroCenter.distanceTo(cell(28, 10)), lessThan(40));
  });

  test('sword kills a slime: XP, loot, and the loot can be picked up', () {
    start(Legends.field);
    clearMonsters();
    placeHero(cell(5, 20));
    final slime = LegendsLevelBuilder.monster('s', heroCenter + Vector2(34, 0), 'Test Slime');
    scene.addEntity(slime);
    frames(3, hold: {LogicalKeyboardKey.keyD}); // face right
    for (var i = 0; i < 6 && slime.scene != null; i++) {
      tap(LogicalKeyboardKey.space);
      frames(20);
    }
    expect(slime.scene, isNull, reason: 'slime slain');
    expect(LegendsSession.xp, 3);

    final gold0 = LegendsSession.inventory.gold;
    Legends.spawnPickup(scene, 'gold', heroCenter, amount: 4);
    frames(20);
    expect(LegendsSession.inventory.gold, gold0 + 4);
    expect(text('Info'), contains('Gold ${gold0 + 4}'));
  });

  test('levels up from XP: more hearts and a full heal', () {
    start(Legends.field);
    clearMonsters();
    heroHealth.damage(2);
    final bat = LegendsLevelBuilder.monster('v', Vector2.zero(), 'Bat');
    scene.addEntity(bat);
    LegendsSession.xp = LegendsSession.xpToNext - 1;
    hero.onKill(bat);
    expect(LegendsSession.level, 2);
    expect(heroHealth.maxHealth, 6);
    expect(heroHealth.health, 6);
    frames(1);
    expect(scene.findByName('Hearts')!.getComponent<UIImageComponent>()!.count, 6);
    expect(text('Banner'), contains('LEVEL UP'));
  });

  test('monsters notice, chase and hurt the hero', () {
    start(Legends.field);
    clearMonsters();
    placeHero(cell(10, 20));
    final slime = LegendsLevelBuilder.monster('s', cell(13, 20), 'Chaser');
    scene.addEntity(slime);
    frames(240);
    expect(heroHealth.health, lessThan(5));
    expect(slime.getComponent<MonsterAIComponent>()!.state, isNot(MonsterState.wander));
  });

  test('elder dialogue pauses the game; merchant sells potions; Q drinks one', () {
    start(Legends.village);
    placeHero(cell(15, 8)); // just below the Elder
    tap(LogicalKeyboardKey.keyE);
    expect(DialogueSystem.instance.isOpen, isTrue);
    expect(engine.timeScale, 0);
    expect(LegendsSession.metElder, isTrue);
    for (var i = 0; i < 12 && DialogueSystem.instance.isOpen; i++) {
      tap(LogicalKeyboardKey.enter);
    }
    expect(DialogueSystem.instance.isOpen, isFalse);
    expect(engine.timeScale, 1);

    LegendsSession.inventory.addGold(12);
    placeHero(cell(21, 11)); // below the Merchant
    tap(LogicalKeyboardKey.keyE);
    expect(LegendsSession.inventory.count('Potion'), 1);
    expect(LegendsSession.inventory.gold, 2);
    while (DialogueSystem.instance.isOpen) {
      tap(LogicalKeyboardKey.enter);
    }

    heroHealth.damage(3);
    frames(70); // wait out invulnerability flash
    tap(LogicalKeyboardKey.keyQ);
    expect(heroHealth.health, 5);
    expect(LegendsSession.inventory.count('Potion'), 0);
  });

  test('pause menu stops the game and resumes it', () {
    start(Legends.field);
    tap(LogicalKeyboardKey.escape);
    expect(engine.timeScale, 0);
    expect(scene.findByName('Menu Resume')!.enabled, isTrue);
    final c = heroCenter.clone();
    frames(20, hold: {LogicalKeyboardKey.keyD});
    expect(heroCenter, c, reason: 'frozen while paused');
    UIRenderer.dispatch(scene, 'resume');
    engine.step();
    expect(engine.timeScale, 1);
    expect(scene.findByName('Menu Resume')!.enabled, isFalse);
  });

  test('save crystal heals and saves; dying reloads the save with progress kept', () {
    start(Legends.village);
    LegendsSession.addXp(12); // level 2
    heroHealth.damage(2);
    placeHero(cell(16, 9)); // below the crystal
    tap(LogicalKeyboardKey.keyE);
    expect(heroHealth.health, heroHealth.maxHealth);
    expect(SaveSlots.exists(Legends.saveSlot), isTrue);
    while (DialogueSystem.instance.isOpen) {
      tap(LogicalKeyboardKey.enter);
    }

    engine.loadLevel(Legends.field);
    frames(3);
    LegendsSession.inventory.addGold(50); // not saved: lost on death
    heroHealth.damage(99);
    expect(text('Banner'), contains('FALLEN'));
    frames(200);
    expect(scene.name, Legends.village);
    expect(LegendsSession.level, 2);
    expect(LegendsSession.inventory.gold, 0);
    expect(heroCenter.distanceTo(cell(16, 9)), lessThan(4), reason: 'back where the game was saved');
    expect(heroHealth.health, heroHealth.maxHealth);
  });

  test('the Ember Golem wakes up, fires rings of fireballs, and its death wins the game', () {
    start(Legends.dungeon);
    final golem = scene.findByName('Ember Golem_1')!;
    expect(scene.findByName('Boss Bar')!.enabled, isFalse);
    placeHero(cell(15, 9));
    heroHealth.maxHealth = 99;
    heroHealth.health = 99;
    frames(60 * 6);
    expect(scene.findByName('Boss Bar')!.enabled, isTrue);
    expect(heroHealth.health, lessThan(99), reason: 'fireballs hit');

    final boss = golem.getComponent<HealthComponent>()!;
    while (!boss.isDead) {
      boss.damage(5, source: heroEntity);
      frames(12);
    }
    frames(2);
    expect(golem.scene, isNull);
    expect(LegendsSession.bossDefeated, isTrue);
    expect(scene.findByName('Boss Bar')!.enabled, isFalse);
    expect(scene.allEntities.where((e) => e.tags.contains('pickup')).length, greaterThanOrEqualTo(6));
    expect(text('Hint'), contains('Elder'));
  });

  test('autopilot: a bot clears the field, enters the Ember Depths and slays the Golem', () {
    start(Legends.village);
    // Walk to the east door
    expect(botWalkTo(cell(29, 9), maxFrames: 60 * 20, until: () => scene.name == Legends.field), isTrue, reason: 'reached the field');

    var deaths = 0;
    final killsBefore = <String>{};
    final result = botHunt(
      maxFrames: 60 * 60 * 8,
      onDeath: () => deaths++,
      onScene: (name) => killsBefore.add(name),
    );
    expect(killsBefore, containsAll([Legends.field, Legends.dungeon]), reason: 'fought through both areas');
    expect(result, isTrue, reason: 'Golem defeated (level ${LegendsSession.level}, deaths $deaths, scene ${scene.name})');
    expect(LegendsSession.bossDefeated, isTrue);
    expect(LegendsSession.level, greaterThan(2));
    // ignore: avoid_print
    print('autopilot: level ${LegendsSession.level}, deaths $deaths, gold ${LegendsSession.inventory.gold}, '
        'game time ${(_botFrames / 60).toStringAsFixed(0)}s');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

// ---------------------------------------------------------------------------
// Bot

final _keys = {
  'left': LogicalKeyboardKey.keyA,
  'right': LogicalKeyboardKey.keyD,
  'up': LogicalKeyboardKey.keyW,
  'down': LogicalKeyboardKey.keyS,
};

/// One frame of input: move along [dir] (8-way keys) and optionally swing.
void botFrame(Vector2 dir, {bool attack = false}) {
  final want = <LogicalKeyboardKey>{
    if (dir.x > 0.35) _keys['right']!,
    if (dir.x < -0.35) _keys['left']!,
    if (dir.y > 0.35) _keys['down']!,
    if (dir.y < -0.35) _keys['up']!,
  };
  for (final k in _keys.values) {
    if (want.contains(k)) {
      Input.onKeyDown(k);
    } else {
      Input.onKeyUp(k);
    }
  }
  if (attack) Input.onKeyDown(LogicalKeyboardKey.space);
  engine.step();
  if (attack) Input.onKeyUp(LogicalKeyboardKey.space);
}

void botRelease() {
  for (final k in _keys.values) {
    Input.onKeyUp(k);
  }
}

List<Vector2>? _path;
int _pathAge = 0;

/// Direction from the hero toward [goal], around walls.
Vector2 botSteer(Vector2 goal) {
  final me = heroCenter;
  if (TileCollision.lineClear(scene, Offset(me.x, me.y), Offset(goal.x, goal.y), step: 6)) {
    _path = null;
    return (goal - me).normalized();
  }
  if (_path == null || _path!.isEmpty || ++_pathAge > 20) {
    _path = Pathfinder.findPath(scene, me, goal);
    _pathAge = 0;
  }
  final p = _path;
  if (p == null || p.isEmpty) return (goal - me).normalized();
  while (p.length > 1 && me.distanceTo(p.first) < 10) {
    p.removeAt(0);
  }
  return (p.first - me).normalized();
}

bool botWalkTo(Vector2 goal, {required int maxFrames, required bool Function() until}) {
  for (var i = 0; i < maxFrames; i++) {
    if (until()) {
      botRelease();
      return true;
    }
    if (heroEntity == null) {
      engine.step();
      continue;
    }
    botFrame(botSteer(goal));
  }
  botRelease();
  return until();
}

/// Hunts every monster in the field, goes down the cave, and fights through
/// the dungeon to the Golem. Returns true once the Golem is dead.
int _botFrames = 0;

bool botHunt({required int maxFrames, void Function()? onDeath, void Function(String scene)? onScene}) {
  var wasDead = false;
  var stuck = 0;
  var lastPos = Vector2.zero();
  for (var i = 0; i < maxFrames; i++) {
    _botFrames = i;
    onScene?.call(scene.name);
    if (LegendsSession.bossDefeated) {
      botRelease();
      return true;
    }
    final h = heroEntity;
    if (h == null) {
      engine.step();
      continue;
    }
    final health = h.getComponent<HealthComponent>()!;
    if (health.isDead) {
      if (!wasDead) onDeath?.call();
      wasDead = true;
      botFrame(Vector2.zero());
      continue;
    }
    wasDead = false;
    if (DialogueSystem.instance.isOpen) {
      tap(LogicalKeyboardKey.enter);
      continue;
    }
    if (health.health <= 2 && LegendsSession.inventory.count('Potion') > 0) {
      tap(LogicalKeyboardKey.keyQ);
    }

    final me = heroCenter;
    // Back in the village after dying: head out again
    if (scene.name == Legends.village) {
      botFrame(botSteer(cell(29, 9)));
      continue;
    }

    final targets = monsters;
    EmberEntity? target;
    var best = double.infinity;
    for (final m in targets) {
      final d = Legends.centerOf(m).distanceTo(me);
      if (d < best) {
        best = d;
        target = m;
      }
    }

    // Grab nearby hearts when hurt
    if (health.health < health.maxHealth - 1) {
      for (final p in scene.allEntities.where((e) => e.tags.contains('pickup'))) {
        final pc = Legends.centerOf(p);
        if (pc.distanceTo(me) < 90 && best > 70) {
          target = p;
          best = pc.distanceTo(me);
          break;
        }
      }
    }

    if (target == null) {
      // Field cleared (or dungeon wing cleared): head for the cave
      if (scene.name == Legends.field) {
        botFrame(botSteer(cell(33, 1)));
      } else {
        botFrame(Vector2.zero());
      }
      continue;
    }

    final tc = Legends.centerOf(target);
    final d = tc - me;
    final isMonster = target.tags.contains('monster');
    // Line up on one axis, then swing when close
    final aligned = d.x.abs() < 14 || d.y.abs() < 14;
    final close = d.length < (target.tags.contains('boss') ? 48 : 36);
    if (isMonster && close && aligned) {
      final face = d.x.abs() > d.y.abs() ? Vector2(d.x.sign, 0) : Vector2(0, d.y.sign);
      botFrame(face * 0.5, attack: !hero.isSwinging);
    } else {
      var dir = botSteer(tc);
      if (isMonster && close) {
        // Close but diagonal: straighten out on the shorter axis
        dir = d.x.abs() < d.y.abs() ? Vector2(d.x.sign, 0) : Vector2(0, d.y.sign);
      }
      botFrame(dir);
    }

    // Unstick if pinned against something
    if (me.distanceTo(lastPos) < 0.2) {
      if (++stuck > 45) {
        for (var j = 0; j < 12; j++) {
          botFrame(Vector2(math.cos(i * 1.7), math.sin(i * 1.7)));
        }
        stuck = 0;
        _path = null;
      }
    } else {
      stuck = 0;
    }
    lastPos = me.clone();
  }
  botRelease();
  return LegendsSession.bossDefeated;
}

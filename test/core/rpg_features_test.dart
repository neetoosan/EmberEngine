import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/inventory.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/scene_serializer.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/core/tween.dart';
import 'package:ember_engine/subsystems/ai/monster_ai.dart';
import 'package:ember_engine/subsystems/ai/pathfinding.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/two_d/door.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/two_d/top_down_controller.dart';
import 'package:ember_engine/subsystems/ui/dialogue.dart';

const dt = 1 / 60;

/// Records combat callbacks.
class _Recorder extends GameScript {
  static final List<String> log = [];
  @override
  void onDamaged(double amount, EmberEntity? source) => log.add('${entity!.name} hurt $amount');
  @override
  void onDeath(EmberEntity? killer) => log.add('${entity!.name} died');
  @override
  void onKill(EmberEntity victim) => log.add('${entity!.name} killed ${victim.name}');
}

/// A running scene with an empty 20x15 collision tilemap (32px tiles).
(EmberScene, FlameTileMapComponent) _world() {
  final scene = EmberScene();
  final map = FlameTileMapComponent(columns: 20, rows: 15);
  scene.addEntity(EmberEntity(name: 'Level')
    ..addComponent(Transform2DComponent(size: Vector2.zero()))
    ..addComponent(map));
  scene.isRunning = true;
  return (scene, map);
}

EmberEntity _actor(String name, Vector2 pos, {String team = 'monster', double hp = 3, Set<String>? tags, double speed = 140}) =>
    EmberEntity(name: name, tags: tags)
      ..addComponent(Transform2DComponent(position: pos, size: Vector2(24, 24)))
      ..addComponent(FlameHitbox2DComponent(size: Vector2(20, 20), offset: Vector2(2, 2), isSolid: false, debugDraw: false))
      ..addComponent(TopDownController2DComponent(moveSpeed: speed))
      ..addComponent(HealthComponent(maxHealth: hp, team: team, invulnerableTime: 0.2))
      ..addComponent(ScriptComponent(scriptName: 'Test Recorder'));

void _tick(EmberScene scene, double seconds) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    scene.update(dt);
    scene.flushDestroyed();
  }
}

Vector2 _pos(EmberEntity e) => e.getComponent<Transform2DComponent>()!.position;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerAllSubsystems();
    ScriptRegistry.register('Test Recorder', () => _Recorder());
  });
  setUp(() {
    _Recorder.log.clear();
    EmberTween.clear();
  });

  group('top-down movement', () {
    test('moves in 8 directions and slides along walls', () {
      final (scene, map) = _world();
      for (var r = 0; r < 15; r++) {
        map.setTile(10, r, 1); // wall at x = 320..352
      }
      final hero = _actor('Hero', Vector2(200, 200), team: 'player');
      scene.addEntity(hero);
      final mover = hero.getComponent<TopDownController2DComponent>()!;
      for (var i = 0; i < 120; i++) {
        mover.move(Vector2(1, 1), dt);
      }
      // Blocked on x by the wall (hitbox right edge = x + 22), still slid down
      expect(_pos(hero).x + 22, closeTo(320, 0.01));
      expect(_pos(hero).y, greaterThan(300));
      expect(mover.facing, anyOf(Facing.right, Facing.down));
      expect(mover.hitWall, isTrue);
    });
  });

  group('pathfinding', () {
    test('finds a way around a wall without cutting corners', () {
      final (scene, map) = _world();
      for (var r = 0; r < 12; r++) {
        map.setTile(8, r, 1); // wall with a gap at rows 12-14
      }
      final path = Pathfinder.findPath(scene, Vector2(100, 100), Vector2(500, 100))!;
      expect(path, isNotEmpty);
      expect(path.last, Vector2(500, 100));
      expect(path.any((p) => p.y > 12 * 32), isTrue, reason: 'goes through the gap');
      for (final p in path) {
        expect(Pathfinder.isWalkable(scene, p.x, p.y), isTrue);
      }
    });

    test('returns null when the goal is walled off, and updates when tiles change', () {
      final (scene, map) = _world();
      for (var r = 0; r < 15; r++) {
        map.setTile(8, r, 1);
      }
      expect(Pathfinder.findPath(scene, Vector2(100, 100), Vector2(500, 100)), isNull);
      map.setTile(8, 3, 0); // open a door
      expect(Pathfinder.findPath(scene, Vector2(100, 100), Vector2(500, 100)), isNotNull);
    });
  });

  group('combat', () {
    test('strike respects teams, invulnerability, death and kill credit', () {
      final (scene, _) = _world();
      final hero = _actor('Hero', Vector2(100, 100), team: 'player');
      final slime = _actor('Slime', Vector2(130, 100), hp: 2);
      final buddy = _actor('Buddy', Vector2(130, 130), team: 'player');
      scene..addEntity(hero)..addEntity(slime)..addEntity(buddy);
      final area = Combat.bodyOf(slime).inflate(40);

      expect(Combat.strike(scene, area, team: 'player', damage: 1, source: hero), [slime]);
      expect(Combat.strike(scene, area, team: 'player', damage: 1, source: hero), isEmpty, reason: 'invulnerable');
      _tick(scene, 0.3);
      Combat.strike(scene, area, team: 'player', damage: 1, source: hero);
      _tick(scene, dt);
      expect(slime.scene, isNull, reason: 'removed on death');
      expect(buddy.getComponent<HealthComponent>()!.health, 3, reason: 'no friendly fire');
      expect(_Recorder.log, ['Slime hurt 1.0', 'Slime hurt 1.0', 'Slime died', 'Hero killed Slime']);
    });

    test('projectiles hit enemies, credit their owner, and stop at walls', () {
      final (scene, map) = _world();
      map.setTile(15, 3, 1);
      final archer = _actor('Archer', Vector2(40, 100));
      final hero = _actor('Hero', Vector2(200, 100), team: 'player', hp: 5);
      scene..addEntity(archer)..addEntity(hero);
      final ai = MonsterAIComponent(ranged: true, attackDamage: 2);
      final shot = ai.spawnProjectile(scene, archer, Vector2(80, 112), Vector2(1, 0), 'monster');
      _tick(scene, 1);
      expect(hero.getComponent<HealthComponent>()!.health, 3);
      expect(shot.scene, isNull);

      // A shot into a wall disappears
      final miss = ai.spawnProjectile(scene, archer, Vector2(400, 112), Vector2(1, 0), 'monster');
      _tick(scene, 0.5);
      expect(miss.scene, isNull);
      expect(hero.getComponent<HealthComponent>()!.health, 3);
    });
  });

  group('monster AI', () {
    test('notices, chases around a wall, and attacks the player', () {
      final (scene, map) = _world();
      for (var r = 2; r < 15; r++) {
        map.setTile(8, r, 1);
      }
      final hero = _actor('Hero', Vector2(360, 300), team: 'player', hp: 10, tags: {'player'});
      final orc = _actor('Orc', Vector2(180, 30), speed: 90)
        ..addComponent(MonsterAIComponent(sightRange: 400, loseRange: 800, attackDamage: 1, wander: false, touchDamage: 0));
      scene..addEntity(hero)..addEntity(orc);
      final ai = orc.getComponent<MonsterAIComponent>()!;
      _tick(scene, 0.1);
      expect(ai.state, MonsterState.wander, reason: 'wall blocks line of sight');

      hero.getComponent<Transform2DComponent>()!.position = Vector2(360, 30); // visible over the wall's top gap
      _tick(scene, 0.2);
      expect(ai.state, MonsterState.chase);
      hero.getComponent<Transform2DComponent>()!.position = Vector2(360, 300); // hide behind the wall again
      _tick(scene, 8);
      expect(hero.getComponent<HealthComponent>()!.health, lessThan(10), reason: 'reached and hit the hero');
      expect(_pos(orc).x, greaterThan(8 * 32), reason: 'went around the wall');
    });

    test('gives up and returns home when the target leaves', () {
      final (scene, _) = _world();
      final hero = _actor('Hero', Vector2(250, 100), team: 'player', tags: {'player'});
      final bat = _actor('Bat', Vector2(100, 100))..addComponent(MonsterAIComponent(sightRange: 200, loseRange: 260, wander: false, touchDamage: 0));
      scene..addEntity(hero)..addEntity(bat);
      final ai = bat.getComponent<MonsterAIComponent>()!;
      _tick(scene, 0.5);
      expect(ai.state, isNot(MonsterState.wander));
      hero.getComponent<Transform2DComponent>()!.position = Vector2(620, 460);
      _tick(scene, 6);
      expect(ai.state, MonsterState.wander);
      expect(_pos(bat).distanceTo(Vector2(100, 100)), lessThan(12));
    });

    test('serializes its settings', () {
      final scene = EmberScene()
        ..addEntity(EmberEntity(name: 'Skel')
          ..addComponent(Transform2DComponent())
          ..addComponent(MonsterAIComponent(ranged: true, xpReward: 12, projectileAsset: 'arrow.png')));
      final copy = SceneSerializer.deserializeScene(SceneSerializer.serializeScene(scene));
      final ai = copy.findByName('Skel')!.getComponent<MonsterAIComponent>()!;
      expect(ai.ranged, isTrue);
      expect(ai.xpReward, 12);
      expect(ai.projectileAsset, 'arrow.png');
    });
  });

  group('tweens & dialogue', () {
    test('tween eases a value and completes', () {
      var v = 0.0;
      var done = false;
      EmberTween.run(1, (t) => v = t * 10, onComplete: () => done = true);
      EmberTween.update(0.5);
      expect(v, closeTo(5, 0.01));
      EmberTween.update(0.6);
      expect(v, 10);
      expect(done, isTrue);
    });

    test('dialogue types out, advances and finishes', () {
      final d = DialogueSystem.instance;
      var finished = false;
      d.start(DialogueSystem.parse('Elder: Beware the caves.\nHero: I will.'), onFinished: () => finished = true);
      expect(d.current!.speaker, 'Elder');
      d.advance(); // completes typing
      d.advance(); // next line
      expect(d.current!.speaker, 'Hero');
      d.advance();
      d.advance();
      expect(d.isOpen, isFalse);
      expect(finished, isTrue);
    });
  });

  group('doors & interaction', () {
    test('places the player on a named spawn marker', () {
      final (scene, _) = _world();
      final hero = _actor('Hero', Vector2(10, 10), team: 'player', tags: {'player'});
      scene
        ..addEntity(hero)
        ..addEntity(EmberEntity(name: 'From Village')..addComponent(Transform2DComponent(position: Vector2(300, 200), size: Vector2(32, 32))));
      expect(Doors.placeAt(scene, hero, 'From Village'), isTrue);
      final body = Combat.bodyOf(hero);
      expect(body.center.dx, closeTo(316, 0.01));
      expect(body.center.dy, closeTo(216, 0.01));
      expect(Doors.placeAt(scene, hero, 'Nowhere'), isFalse);
    });

    test('interact opens the nearest NPC dialogue', () {
      final (scene, _) = _world();
      final hero = _actor('Hero', Vector2(100, 100), team: 'player', tags: {'player'});
      final elder = EmberEntity(name: 'Elder')
        ..addComponent(Transform2DComponent(position: Vector2(130, 100), size: Vector2(24, 24)))
        ..addComponent(DialogueComponent(lines: 'Elder: Slay the slimes!'));
      scene..addEntity(hero)..addEntity(elder);
      expect(Interaction.interact(scene, hero), elder);
      expect(DialogueSystem.instance.current!.text, 'Slay the slimes!');
      DialogueSystem.instance.close();
      elder.getComponent<Transform2DComponent>()!.position = Vector2(400, 400);
      expect(Interaction.interact(scene, hero), isNull);
    });
  });

  group('inventory & save slots', () {
    test('inventory stacks, takes and round-trips', () {
      final inv = Inventory()
        ..add('Potion', 2)
        ..add('Key')
        ..addGold(30);
      expect(inv.take('Potion'), isTrue);
      expect(inv.take('Key', 2), isFalse);
      expect(inv.spend(40), isFalse);
      final copy = Inventory()..fromJson(inv.toJson());
      expect(copy.items, {'Potion': 1, 'Key': 1});
      expect(copy.gold, 30);
    });

    test('save slots store, list and delete games', () {
      SaveSlots.save(2, {'level': 'Dungeon', 'hp': 4});
      expect(SaveSlots.exists(2), isTrue);
      expect(SaveSlots.load(2)!['level'], 'Dungeon');
      expect(SaveSlots.latest(), 2);
      SaveSlots.delete(2);
      expect(SaveSlots.exists(2), isFalse);
    });
  });
}

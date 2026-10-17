import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/mouse_lock.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/ai/enemy_ai3d.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/combat/projectile3d.dart';
import 'package:ember_engine/subsystems/physics/character_controller3d.dart';
import 'package:ember_engine/subsystems/three_d/components3d.dart';

EmberEngine get engine => EmberEngine.instance;

EmberEntity thing(String name, Vector3 at, {String? script, Set<String>? tags, Vector3? size}) {
  final e = EmberEntity(name: name, tags: tags)..addComponent(Transform3DComponent(position: at));
  if (size != null) e.addComponent(Collider3DComponent(size: size));
  if (script != null) e.addComponent(ScriptComponent(scriptName: script));
  return e;
}

EmberEntity player(Vector3 at, {double hp = 100}) => EmberEntity(name: 'Player', tags: {'player'})
  ..addComponent(Transform3DComponent(position: at))
  ..addComponent(CharacterController3DComponent())
  ..addComponent(HealthComponent(maxHealth: hp, team: 'player', invulnerableTime: 0, destroyOnDeath: false));

EmberEntity robot(String name, Vector3 at, EnemyAI3DComponent ai, {double hp = 5}) => EmberEntity(name: name, tags: {'enemy'})
  ..addComponent(Transform3DComponent(position: at))
  ..addComponent(Collider3DComponent(size: Vector3(0.9, 1.8, 0.9)))
  ..addComponent(CharacterController3DComponent())
  ..addComponent(HealthComponent(maxHealth: hp, team: 'monster', invulnerableTime: 0))
  ..addComponent(ai);

/// A variable of the entity's Ember Script.
Object? field(EmberEntity e, String name) => (e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior).field(name);

void frames(int n) {
  for (var i = 0; i < n; i++) {
    engine.step();
  }
}

/// Fake capture backend that records calls.
class FakeLock implements MouseLockBackend {
  bool on = false;
  (double, double) pending = (0, 0);
  @override
  bool get supported => true;
  @override
  bool get locked => on;
  @override
  void lock() => on = true;
  @override
  void unlock() => on = false;
  @override
  (double, double) takeDelta() {
    final d = pending;
    pending = (0, 0);
    return d;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.threeD);
    EmberScripts.instance.loadAll({});
  });
  tearDown(engine.stop);

  test('Ember Script has 3D vectors and can turn, aim and measure in 3D', () {
    EmberScripts.instance.loadAll({
      'probe.ember': '''
        var log = [];
        void onStart() {
          var a = vec3(1, 2, 3);
          var b = a + vec3(1, 0, -3) * 2;
          log.add("\$b");
          log.add(a.dot(vec3(1, 1, 1)));
          log.add("\${vec3(1, 0, 0).cross(vec3(0, 1, 0))}");
          log.add(vec3(3, 4, 0).length);
          log.add("\${-a}");
          self.lookAt(find("Target"));
          log.add(round(self.yaw));
          log.add(round(self.forward.x * 100));
          log.add(round(self.distanceTo(find("Target"))));
          log.add("\${self.directionTo(vec3(0, 0, -10))}");
          self.yaw = 0;
          log.add(round(self.turnToward(find("Target"), 30)));
          log.add(round(self.yaw));
          self.position = vec3(0, 1, 2);
          log.add("\${self.position}");
          log.add("\${self.position.flat}");
        }
      ''',
    });
    final scene = EmberScene(name: 'S')
      ..addEntity(thing('Probe', Vector3.zero(), script: 'probe.ember'))
      ..addEntity(thing('Target', Vector3(10, 0, 0)));
    engine.loadScene(scene);
    frames(1);
    final log = field(scene.findByName('Probe')!, 'log') as List;
    expect(log, [
      'Vec3(3, 2, -3)',
      6.0,
      'Vec3(0, 0, 1)',
      5.0,
      'Vec3(-1, -2, -3)',
      -90, // facing +X
      100,
      10,
      'Vec3(0, 0, -1)',
      60, // 90° to turn, 30 done
      -30,
      'Vec3(0, 1, 2)',
      'Vec3(0, 0, 2)',
    ]);
  });

  test('3D raycasts and line of sight in Ember Script; pickups (triggers) do not block', () {
    EmberScripts.instance.loadAll({
      'eye.ember': '''
        var hit = "";
        var clear = false;
        var blocked = true;
        void onStart() {
          var h = Physics.raycast(vec3(0, 1, 0), vec3(0, 1, -20));
          hit = h.entity.name + " " + round(h.distance) + " \${h.normal}";
          clear = Physics.lineOfSight(vec3(0, 1, 0), vec3(5, 1, 0));
          blocked = Physics.lineOfSight(vec3(0, 1, 0), vec3(0, 1, -20));
        }
      ''',
    });
    final pickup = thing('Pickup', Vector3(0, 1, -3), size: Vector3.all(1));
    pickup.getComponent<Collider3DComponent>()!.isTrigger = true;
    final scene = EmberScene(name: 'S')
      ..addEntity(thing('Eye', Vector3.zero(), script: 'eye.ember'))
      ..addEntity(pickup)
      ..addEntity(thing('Wall', Vector3(0, 1, -8), size: Vector3(4, 4, 2)));
    engine.loadScene(scene);
    frames(1);
    final eye = scene.findByName('Eye')!;
    expect(field(eye, 'hit'), 'Wall 7 Vec3(0, 0, 1)');
    expect(field(eye, 'clear'), isTrue);
    expect(field(eye, 'blocked'), isFalse);
  });

  test('a 3D shot hurts the first enemy it touches, never its own team, and stops at walls', () {
    final p = player(Vector3(0, 0.9, 0));
    final target = robot('Bot', Vector3(0, 0.9, -6), EnemyAI3DComponent(sightRange: 0));
    final friend = robot('Friend', Vector3(4, 0.9, -6), EnemyAI3DComponent(sightRange: 0));
    final scene = EmberScene(name: 'S')
      ..addEntity(p)
      ..addEntity(target)
      ..addEntity(friend)
      ..addEntity(thing('Wall', Vector3(-4, 1, -6), size: Vector3(1, 3, 1)));
    engine.loadScene(scene);
    frames(1);
    final hit = Projectile3DComponent.orb(position: Vector3(0, 1, -1), velocity: Vector3(0, 0, -30), team: 'player', damage: 2, owner: p);
    // A monster's shot passes its teammate; the wall stops another
    final passing = Projectile3DComponent.orb(position: Vector3(4, 1, -3), velocity: Vector3(0, 0, -30), team: 'monster', damage: 2);
    final walled = Projectile3DComponent.orb(position: Vector3(-4, 1, -3), velocity: Vector3(0, 0, -30), team: 'player', damage: 2);
    scene
      ..addEntity(hit)
      ..addEntity(passing)
      ..addEntity(walled);
    frames(30);
    expect(target.getComponent<HealthComponent>()!.health, 3);
    expect(hit.scene, isNull);
    expect(friend.getComponent<HealthComponent>()!.health, 5);
    expect(passing.scene, isNotNull);
    expect(passing.getComponent<Transform3DComponent>()!.position.z, lessThan(-10), reason: 'flew on past its teammate');
    expect(walled.scene, isNull, reason: 'stopped at the wall (it would still be flying, like the monster shot)');
  });

  test('a splash shot damages everything nearby, less further out', () {
    final a = robot('A', Vector3(0, 0.9, -5), EnemyAI3DComponent(sightRange: 0), hp: 10);
    final b = robot('B', Vector3(2.5, 0.9, -5), EnemyAI3DComponent(sightRange: 0), hp: 10);
    final far = robot('Far', Vector3(8, 0.9, -5), EnemyAI3DComponent(sightRange: 0), hp: 10);
    final scene = EmberScene(name: 'S')
      ..addEntity(a)
      ..addEntity(b)
      ..addEntity(far);
    engine.loadScene(scene);
    frames(1);
    scene.addEntity(Projectile3DComponent.orb(position: Vector3(0, 1, -2), velocity: Vector3(0, 0, -20), team: 'player', damage: 4, splashRadius: 3));
    frames(20);
    final ha = a.getComponent<HealthComponent>()!.health, hb = b.getComponent<HealthComponent>()!.health;
    expect(ha, lessThan(7));
    expect(hb, allOf(lessThan(10), greaterThan(ha)));
    expect(far.getComponent<HealthComponent>()!.health, 10);
  });

  test('Enemy AI 3D: a chaser closes in and attacks once per cooldown', () {
    final p = player(Vector3(0, 0.9, 0));
    final bot = robot('Chaser', Vector3(0, 0.9, -12), EnemyAI3DComponent(moveSpeed: 6, attackDamage: 10, attackCooldown: 1));
    final scene = EmberScene(name: 'S')
      ..addEntity(p)
      ..addEntity(bot);
    engine.loadScene(scene);
    frames(120); // 2 s: about 1.7 s to arrive, then one hit
    final hp = p.getComponent<HealthComponent>()!;
    expect(hp.health, 90);
    final botPos = bot.getComponent<Transform3DComponent>()!.worldPosition;
    expect(botPos.z, greaterThan(-2.5), reason: 'it came to the player');
    expect(bot.getComponent<Transform3DComponent>()!.forward.z, greaterThan(0.9), reason: 'it faces the player (+Z)');
    frames(60);
    expect(hp.health, 80, reason: 'the next hit after the cooldown');
  });

  test('Enemy AI 3D: a self-destructing drone explodes next to the player and is gone', () {
    final p = player(Vector3(0, 0.9, 0));
    final drone = robot('Drone', Vector3(0, 0.9, -6),
        EnemyAI3DComponent(moveSpeed: 8, attackDamage: 15, selfDestruct: true, explosionRadius: 3, hoverHeight: 1.4), hp: 2);
    final scene = EmberScene(name: 'S')
      ..addEntity(p)
      ..addEntity(drone);
    engine.loadScene(scene);
    frames(90);
    expect(drone.scene, isNull, reason: 'it blew itself up');
    expect(p.getComponent<HealthComponent>()!.health, 85);
  });

  test('Enemy AI 3D: a shooter keeps its distance, strafes and fires shots that hurt', () {
    final p = player(Vector3(0, 0.9, 0));
    final gunner = robot('Gunner', Vector3(0, 0.9, -25),
        EnemyAI3DComponent(behavior: EnemyBehavior3D.shooter, moveSpeed: 5, preferredDistance: 10, fireCooldown: 0.8, shotDamage: 5, shotSpeed: 25));
    final scene = EmberScene(name: 'S')
      ..addEntity(p)
      ..addEntity(gunner);
    engine.loadScene(scene);
    frames(360); // 6 s
    final d = gunner.getComponent<Transform3DComponent>()!.worldPosition.distanceTo(Vector3(0, 0.9, 0));
    expect(d, inInclusiveRange(6, 14), reason: 'about 10 m away');
    expect(p.getComponent<HealthComponent>()!.health, lessThan(100), reason: 'its shots landed');
    expect(['strafe', 'chase', 'retreat'], contains(gunner.getComponent<EnemyAI3DComponent>()!.state));
  });

  test('Enemy AI 3D: a shooter does not fire through walls', () {
    final p = player(Vector3(0, 0.9, 0));
    final gunner = robot('Gunner', Vector3(0, 0.9, -10),
        EnemyAI3DComponent(behavior: EnemyBehavior3D.shooter, moveSpeed: 0, preferredDistance: 10, fireCooldown: 0.3));
    var shots = 0;
    final scene = EmberScene(name: 'S')
      ..addEntity(p)
      ..addEntity(gunner)
      ..addEntity(thing('Wall', Vector3(0, 1.5, -5), size: Vector3(6, 3, 1)));
    engine.loadScene(scene);
    for (var i = 0; i < 120; i++) {
      engine.step();
      shots += scene.allEntities.where((e) => e.tags.contains('projectile')).length;
    }
    expect(shots, 0);
  });

  test('Enemy AI 3D: a charger winds up, charges, hits hard and is dizzy afterwards', () {
    final p = player(Vector3(0, 0.9, 0));
    final brute = robot('Brute', Vector3(0, 0.9, -10),
        EnemyAI3DComponent(behavior: EnemyBehavior3D.charger, moveSpeed: 2, chargeSpeed: 14, chargeRange: 12, attackDamage: 25, windup: 0.5),
        hp: 20);
    final scene = EmberScene(name: 'S')
      ..addEntity(p)
      ..addEntity(brute);
    engine.loadScene(scene);
    final ai = brute.getComponent<EnemyAI3DComponent>()!;
    final hp = p.getComponent<HealthComponent>()!;
    final seen = <String>[];
    double? afterCharge;
    for (var i = 0; i < 150; i++) {
      engine.step();
      if (seen.isEmpty || seen.last != ai.state) seen.add(ai.state);
      if (ai.state == 'dizzy') afterCharge ??= hp.health;
    }
    expect(seen.take(3), ['windup', 'charge', 'dizzy'], reason: 'already within charge range');
    expect(afterCharge, 75, reason: 'the charge hit once, for 25');
  });

  test('enemies spread out instead of stacking on the same spot', () {
    final p = player(Vector3(0, 0.9, 0));
    final scene = EmberScene(name: 'S')..addEntity(p);
    for (var i = 0; i < 5; i++) {
      scene.addEntity(robot('Bot $i', Vector3(i * 0.3, 0.9, -15), EnemyAI3DComponent(moveSpeed: 5, attackRange: 1.2)));
    }
    engine.loadScene(scene);
    frames(240);
    final bots = scene.allEntities.where((e) => e.tags.contains('enemy')).toList();
    for (var i = 0; i < bots.length; i++) {
      for (var j = i + 1; j < bots.length; j++) {
        final a = bots[i].getComponent<Transform3DComponent>()!.worldPosition, b = bots[j].getComponent<Transform3DComponent>()!.worldPosition;
        expect(Vector3(a.x - b.x, 0, a.z - b.z).length, greaterThan(0.6), reason: '${bots[i].name} / ${bots[j].name}');
      }
    }
  });

  test('a hit flashes every mesh of a 3D entity and knocks a character back', () {
    final p = player(Vector3(0, 0.9, 0));
    final body = EmberEntity(name: 'Body')
      ..addComponent(Transform3DComponent())
      ..addComponent(MeshRenderer3DComponent());
    p.addChild(body);
    final scene = EmberScene(name: 'S')..addEntity(p);
    engine.loadScene(scene);
    frames(1);
    p.getComponent<HealthComponent>()!.damage(5, push: Vector3(10, 0, 0));
    expect(body.getComponent<MeshRenderer3DComponent>()!.flashAmount, greaterThan(0.9));
    expect(body.getComponent<MeshRenderer3DComponent>()!.flashColor, const Color(0xFFFF4D4D));
    final cc = p.getComponent<CharacterController3DComponent>()!;
    for (var i = 0; i < 30; i++) {
      cc.move(Vector3.zero(), false, 1 / 60); // what its controller script does every frame
      engine.step();
    }
    expect(p.getComponent<Transform3DComponent>()!.position.x, greaterThan(0.8));
    expect(body.getComponent<MeshRenderer3DComponent>()!.flashAmount, 0);
  });

  test('mouse capture: wanted by the FPS controller, taken on click, movement turns the view, Escape and Stop release it', () {
    final fake = FakeLock();
    MouseLock.backendOverride = fake;
    addTearDown(() {
      MouseLock.reset();
      MouseLock.backendOverride = null;
    });
    final fps = EmberEntity(name: 'Player')
      ..addComponent(Transform3DComponent(position: Vector3(0, 0.9, 0)))
      ..addComponent(CharacterController3DComponent())
      ..addComponent(ScriptComponent(scriptName: 'FPS Player Controller'));
    final scene = EmberScene(name: 'S')..addEntity(fps);
    engine.loadScene(scene);
    engine.play();
    engine.step();
    expect(MouseLock.wanted, isTrue);
    MouseLock.lock(); // what the viewport does on the first click
    fake.pending = (100, 0);
    engine.play();
    engine.tick(1 / 60);
    final yaw = fps.getComponent<Transform3DComponent>()!.euler.y;
    expect(yaw, closeTo(-15, 0.01), reason: '100 px at 0.15°/px turns right');
    Input.onKeyDown(LogicalKeyboardKey.escape);
    engine.tick(1 / 60);
    Input.onKeyUp(LogicalKeyboardKey.escape);
    expect(fake.on, isFalse);
    MouseLock.lock();
    engine.stop();
    expect(fake.on, isFalse);
    expect(MouseLock.wanted, isFalse);
  });
}

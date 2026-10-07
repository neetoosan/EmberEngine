import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/physics/rigid_body2d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';

EmberEngine get engine => EmberEngine.instance;

/// A box (or ball) entity centred at [at].
EmberEntity body(String name, Vector2 at, Vector2 size,
    {RigidBodyType2D type = RigidBodyType2D.dynamic, BodyShape2D shape = BodyShape2D.box, double restitution = 0.1,
    bool bullet = false, bool sensor = false, bool asleep = false, double density = 1, String? script}) {
  final e = EmberEntity(name: name)
    ..addComponent(Transform2DComponent(position: at, size: size, anchor: EmberAnchor.center))
    ..addComponent(RigidBody2DComponent(
        bodyType: type, shape: shape, restitution: restitution, bullet: bullet, sensor: sensor, startAsleep: asleep, density: density));
  if (script != null) e.addComponent(ScriptComponent(scriptName: script));
  return e;
}

EmberEntity ground({double top = 400}) => body('Ground', Vector2(0, top + 50), Vector2(4000, 100), type: RigidBodyType2D.static);

Transform2DComponent t(String name) => engine.activeScene.findByName(name)!.getComponent<Transform2DComponent>()!;
RigidBody2DComponent rb(String name) => engine.activeScene.findByName(name)!.getComponent<RigidBody2DComponent>()!;
EmberScriptBehavior script(String name) =>
    engine.activeScene.findByName(name)!.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;

void play(EmberScene scene) {
  engine.loadScene(scene);
  engine.step();
}

void run(double seconds) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    engine.step();
  }
}

const recorder = '''
var hits = 0;
var maxImpulse = 0.0;
var enters = 0;
var triggers = 0;
var broke = 0;
void onHit(other, impulse, speed) {
  hits++;
  maxImpulse = max(maxImpulse, impulse);
}
void onCollisionEnter(other) { enters++; }
void onTriggerEnter(other) { triggers++; }
void onJointBreak(joint) { broke++; }
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    EmberScripts.instance.loadAll({'recorder.ember': recorder});
  });

  tearDown(() => engine.stop());

  test('a box falls, lands on the ground and goes to sleep', () {
    play(EmberScene()
      ..addEntity(ground())
      ..addEntity(body('Box', Vector2(100, 100), Vector2(32, 32))));
    run(3);
    expect(t('Box').position.y, closeTo(400 - 16, 1.0), reason: 'resting on top of the ground');
    expect(t('Box').rotation.abs(), lessThan(0.01));
    expect(rb('Box').sleeping, isTrue);
    expect(RigidWorld2D.of(engine.activeScene)!.settled, isTrue);
  });

  test('a stack of boxes stays standing', () {
    final scene = EmberScene()..addEntity(ground());
    for (var i = 0; i < 6; i++) {
      scene.addEntity(body('B$i', Vector2(300, 400 - 16 - i * 32.0), Vector2(32, 32)));
    }
    play(scene);
    run(5);
    for (var i = 0; i < 6; i++) {
      expect(t('B$i').position.x, closeTo(300, 2), reason: 'B$i drifted sideways');
      expect(t('B$i').position.y, closeTo(400 - 16 - i * 32.0, 2), reason: 'B$i sank or jumped');
      expect(t('B$i').rotation.abs(), lessThan(0.05), reason: 'B$i tipped');
    }
  });

  test('a tower that starts asleep stays perfectly still until something hits it', () {
    final scene = EmberScene()..addEntity(ground());
    for (var i = 0; i < 4; i++) {
      scene.addEntity(body('T$i', Vector2(600, 400 - 48 - i * 96.0), Vector2(24, 96), asleep: true));
    }
    play(scene);
    run(2);
    for (var i = 0; i < 4; i++) {
      expect(t('T$i').position, Vector2(600, 400 - 48 - i * 96.0), reason: 'untouched');
    }
    // A heavy ball knocks the top of the tower over
    engine.activeScene.addEntity(body('Ball', Vector2(400, 60), Vector2(28, 28), shape: BodyShape2D.circle, density: 6)
      ..getComponent<RigidBody2DComponent>()!.velocity = Vector2(700, 0));
    run(3);
    expect(t('T3').position.x, greaterThan(640), reason: 'the top piece was knocked off');
  });

  test('restitution makes a ball bounce back up', () {
    play(EmberScene()
      ..addEntity(ground())
      ..addEntity(body('Ball', Vector2(100, 100), Vector2(30, 30), shape: BodyShape2D.circle, restitution: 0.8)));
    var landed = false;
    var highestAfter = double.infinity;
    for (var i = 0; i < 240; i++) {
      engine.step();
      final y = t('Ball').position.y;
      if (y > 380) landed = true;
      if (landed) highestAfter = math.min(highestAfter, y);
    }
    expect(landed, isTrue);
    expect(highestAfter, lessThan(250), reason: 'bounced well above the ground');
  });

  test('a fast "bullet" never tunnels through a thin wall', () {
    play(EmberScene()
      ..addEntity(body('Wall', Vector2(500, 200), Vector2(6, 300), type: RigidBodyType2D.static))
      ..addEntity(body('Shot', Vector2(100, 200), Vector2(12, 12), shape: BodyShape2D.circle, bullet: true)
        ..getComponent<RigidBody2DComponent>()!.gravityScale = 0
        ..getComponent<RigidBody2DComponent>()!.velocity = Vector2(6000, 0)));
    run(1);
    expect(t('Shot').position.x, lessThan(500), reason: 'stopped by the wall');
  });

  test('impacts reach scripts as onHit with an impulse; resting contacts do not', () {
    play(EmberScene()
      ..addEntity(ground())
      ..addEntity(body('Crate', Vector2(200, 100), Vector2(32, 32), script: 'recorder.ember')));
    run(2);
    final s = script('Crate');
    expect(s.field('hits'), greaterThan(0));
    expect(s.field('enters'), greaterThanOrEqualTo(1), reason: 'touched the ground (a small bounce may touch twice)');
    // 1 kg landing at ~sqrt(2 * 980 * 284) ≈ 750 px/s
    expect(s.field('maxImpulse') as double, inInclusiveRange(400, 1200));
    final hitsAfterLanding = s.field('hits');
    final entersAfterLanding = s.field('enters');
    run(3);
    expect(s.field('hits'), hitsAfterLanding, reason: 'sitting still is not a hit');
    expect(s.field('enters'), entersAfterLanding, reason: 'still touching, no new contact');
  });

  test('sensors report touches without blocking', () {
    play(EmberScene()
      ..addEntity(ground())
      ..addEntity(body('Zone', Vector2(200, 250), Vector2(200, 40), type: RigidBodyType2D.static, sensor: true, script: 'recorder.ember'))
      ..addEntity(body('Rock', Vector2(200, 100), Vector2(20, 20))));
    run(2);
    expect(script('Zone').field('triggers'), 1);
    expect(t('Rock').position.y, closeTo(390, 1.5), reason: 'fell through the sensor onto the ground');
  });

  test('hinge, rope and breakable joints', () {
    final pendulum = body('Bob', Vector2(300, 200), Vector2(20, 20), shape: BodyShape2D.circle)
      ..addComponent(PhysicsJoint2DComponent(jointType: JointType2D.rope, connectedAnchor: Vector2(-120, 0)));
    final hanging = body('Weight', Vector2(600, 150), Vector2(30, 30), density: 5, script: 'recorder.ember')
      ..addComponent(PhysicsJoint2DComponent(jointType: JointType2D.hinge, anchor: Vector2(0, -60), breakForce: 1000));
    play(EmberScene()
      ..addEntity(pendulum)
      ..addEntity(hanging));
    final pivot = Vector2(180, 200);
    var maxDist = 0.0;
    var swungBelow = false;
    for (var i = 0; i < 120; i++) {
      engine.step();
      maxDist = math.max(maxDist, t('Bob').position.distanceTo(pivot));
      if (t('Bob').position.y > 290) swungBelow = true;
    }
    expect(swungBelow, isTrue, reason: 'the bob swings down on its rope');
    expect(maxDist, lessThan(122), reason: 'never further than the rope length');
    // The heavy weight (5 kg ≈ 4900 force) snaps its 1000-strength hinge
    expect(script('Weight').field('broke'), 1);
    expect(engine.activeScene.findByName('Weight')!.getComponent<PhysicsJoint2DComponent>()!.broken, isTrue);
    expect(t('Weight').position.y, greaterThan(400), reason: 'falls once the joint snapped');
  });

  test('painted tilemap ground is solid for rigid bodies, and updates when tiles change', () {
    final tiles = List<int>.filled(20 * 10, 0);
    for (var c = 0; c < 20; c++) {
      tiles[8 * 20 + c] = 1;
    }
    final map = FlameTileMapComponent(columns: 20, rows: 10, tileSize: 32, tiles: tiles);
    play(EmberScene()
      ..addEntity(EmberEntity(name: 'Level')
        ..addComponent(Transform2DComponent(size: Vector2.zero()))
        ..addComponent(map))
      ..addEntity(body('Ball', Vector2(160, 100), Vector2(24, 24), shape: BodyShape2D.circle)));
    run(2);
    expect(t('Ball').position.y, closeTo(8 * 32 - 12, 1.5), reason: 'rests on row 8');
    // Dig a hole under the ball (it sits on the edge between columns 4 and 5)
    map.setTile(4, 8, 0);
    map.setTile(5, 8, 0);
    rb('Ball').wake();
    run(2);
    expect(t('Ball').position.y, greaterThan(8 * 32 + 20), reason: 'falls through the hole');
  });

  test('spawned bodies take the velocity set before they exist; explosions push bodies away', () {
    play(EmberScene()..addEntity(ground()));
    final shot = body('Shot', Vector2(100, 300), Vector2(20, 20), shape: BodyShape2D.circle);
    engine.activeScene.addEntity(shot);
    shot.getComponent<RigidBody2DComponent>()!.velocity = Vector2(400, -300);
    engine.step();
    expect(rb('Shot').velocity.x, closeTo(400, 5));
    expect(t('Shot').position.x, greaterThan(100));

    engine.activeScene.addEntity(body('Left', Vector2(560, 384), Vector2(32, 32)));
    engine.activeScene.addEntity(body('Right', Vector2(640, 384), Vector2(32, 32)));
    run(1);
    final pushed = RigidWorld2D.of(engine.activeScene)!.explode(Vector2(600, 390), 120, 600);
    expect(pushed.map((p) => p.$1.name), containsAll(['Left', 'Right']));
    engine.step();
    expect(rb('Left').velocity.x, lessThan(-50));
    expect(rb('Right').velocity.x, greaterThan(50));
  });

  test('raycasts, point queries and script teleports', () {
    play(EmberScene()
      ..addEntity(ground())
      ..addEntity(body('Crate', Vector2(300, 384), Vector2(32, 32))));
    run(1);
    final world = RigidWorld2D.of(engine.activeScene)!;
    final hit = world.raycast(Vector2(0, 384), Vector2(800, 384))!;
    expect(hit.entity.name, 'Crate');
    expect(hit.point.x, closeTo(284, 1));
    expect(world.entitiesAt(Vector2(300, 384)).map((e) => e.name), ['Crate']);

    t('Crate').position = Vector2(700, 200); // moved by a script
    run(2);
    expect(t('Crate').position.x, closeTo(700, 1));
    expect(t('Crate').position.y, closeTo(384, 1), reason: 'fell from where it was put');
  });

  test('rigid bodies, joints and world settings survive save and load', () {
    final scene = EmberScene()
      ..addEntity(EmberEntity(name: 'Settings')..addComponent(PhysicsWorld2DComponent(gravity: Vector2(0, 500), pixelsPerMeter: 50)))
      ..addEntity(body('Ball', Vector2(10, 20), Vector2(30, 30), shape: BodyShape2D.circle, restitution: 0.7, bullet: true, asleep: true)
        ..addComponent(PhysicsJoint2DComponent(jointType: JointType2D.spring, connectedTo: 'Other', length: 80, breakForce: 900)));
    final back = EmberScene.fromJson(scene.toJson());
    final b = back.findByName('Ball')!.getComponent<RigidBody2DComponent>()!;
    expect(b.shape, BodyShape2D.circle);
    expect(b.restitution, 0.7);
    expect(b.bullet, isTrue);
    expect(b.startAsleep, isTrue);
    final j = back.findByName('Ball')!.getComponent<PhysicsJoint2DComponent>()!;
    expect(j.jointType, JointType2D.spring);
    expect(j.connectedTo, 'Other');
    expect(j.breakForce, 900);
    final w = back.findByName('Settings')!.getComponent<PhysicsWorld2DComponent>()!;
    expect(w.gravity, Vector2(0, 500));
    expect(w.pixelsPerMeter, 50);
  });
}

import 'dart:math' as math;
import 'dart:ui';
import 'package:flame/game.dart' as flame;
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/two_d/bullet_pool.dart';
import 'package:ember_engine/subsystems/two_d/flame_game.dart';
import 'package:ember_engine/subsystems/two_d/line2d.dart';
import 'package:ember_engine/subsystems/two_d/path_follower.dart';
import 'package:vector_math/vector_math_64.dart';

EmberEngine get engine => EmberEngine.instance;

EmberEntity pathEntity() => EmberEntity(name: 'Path')
  ..addComponent(Transform2DComponent())
  ..addComponent(Line2DComponent(points: [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)], width: 0));

EmberEntity walker(String name, {double speed = 50, String script = ''}) {
  final e = EmberEntity(name: name)
    ..tags.add('enemy')
    ..addComponent(Transform2DComponent(size: Vector2(10, 10), anchor: EmberAnchor.center))
    ..addComponent(PathFollower2DComponent(speed: speed, rotate: true))
    ..addComponent(HealthComponent(maxHealth: 10, invulnerableTime: 0, destroyOnDeath: false, showBar: true));
  if (script.isNotEmpty) e.addComponent(ScriptComponent(scriptName: script));
  return e;
}

void start(List<EmberEntity> entities, [Map<String, String> scripts = const {}]) {
  engine.stop();
  EmberScripts.instance.loadAll(scripts);
  final scene = EmberScene(name: 'Path');
  for (final e in entities) {
    scene.addEntity(e);
  }
  engine.loadScene(scene);
  engine.step();
}

void steps(int n) {
  for (var i = 0; i < n; i++) {
    engine.step();
  }
}

Vector2 pos(EmberEntity e) => e.getComponent<Transform2DComponent>()!.position;
EmberScriptBehavior script(EmberEntity e) => e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() => engine.stop());

  test('a follower walks the path, turns at corners, reports progress and says when it is at the end', () {
    final w = walker('W', script: 'w.ember');
    start([pathEntity(), w], {'w.ember': 'var ended = 0;\nvoid onPathEnd() { ended++; }\n'});
    final f = w.getComponent<PathFollower2DComponent>()!;
    expect(pos(w).x, closeTo(50 / 60, 1e-6), reason: 'one frame from the first point');
    steps(59);
    expect(pos(w).x, closeTo(50, 1e-6));
    expect(f.progress, closeTo(0.25, 0.01));
    steps(90);
    expect(pos(w).x, closeTo(100, 0.01));
    expect(pos(w).y, closeTo(25, 1));
    expect(w.getComponent<Transform2DComponent>()!.rotation, closeTo(math.pi / 2, 1e-9), reason: 'faces down the second leg');
    steps(120);
    expect(f.done, isTrue);
    expect(pos(w), Vector2(100, 100));
    expect(script(w).field('ended'), 1);
    steps(10);
    expect(script(w).field('ended'), 1, reason: 'only once');
  });

  test('slow, loop and saving', () {
    final w = walker('W', speed: 100);
    start([pathEntity(), w]);
    final f = w.getComponent<PathFollower2DComponent>()!;
    f.slow(0.5, 1);
    final before = f.distance;
    steps(30);
    expect(f.distance - before, closeTo(25, 0.01));
    expect(f.slowed, isTrue);
    steps(60);
    expect(f.slowed, isFalse);
    f.loop = true;
    steps(200);
    expect(f.done, isFalse);
    expect(f.distance, lessThan(200));

    final copy = PathFollower2DComponent()..fromJson(PathFollower2DComponent(path: 'Road', speed: 33, loop: true, rotate: true).toJson());
    expect((copy.path, copy.speed, copy.loop, copy.rotate), ('Road', 33.0, true, true));
  });

  test('homing bullets chase a moving target; splash hits everything near; hits are reported', () {
    final a = walker('A', speed: 80), b = walker('B', speed: 80);
    final gun = EmberEntity(name: 'Gun')
      ..addComponent(Transform2DComponent())
      ..addComponent(BulletPool2DComponent(team: 'player'))
      ..addComponent(ScriptComponent(scriptName: 'gun.ember'));
    start([pathEntity(), a, b, gun], {'gun.ember': 'var hits = [];\nvoid onBulletHit(at, victim) { hits.add(victim.name); }\n'});
    b.getComponent<PathFollower2DComponent>()!.distance = 8; // right behind A
    steps(20);
    final pool = gun.getComponent<BulletPool2DComponent>()!;
    pool.fire(50, 80, 180, 300, target: a, damage: 3); // fired away from it
    steps(90);
    expect(a.getComponent<HealthComponent>()!.health, 7, reason: 'turned round and hit');
    expect(script(gun).field('hits'), ['A']);

    pool.fire(0, 0, 0, 400, target: b, damage: 2, splash: 40);
    steps(90);
    expect(a.getComponent<HealthComponent>()!.health, 5, reason: 'caught in the blast');
    expect(b.getComponent<HealthComponent>()!.health, 8);
  });

  test('findInRange, snap and Line 2D distanceTo from scripts', () {
    const src = '''
var near = [];
var cell = null;
var away = 0;
void onStart() {
  near = findInRange("enemy", vec(0, 0), 30).map((e) => e.name);
  cell = snap(vec(87, 13), 40);
  away = find("Path").line.distanceTo(vec(50, 30));
}
''';
    final a = walker('A'), b = walker('B');
    start([pathEntity(), a, b, EmberEntity(name: 'Q')..addComponent(ScriptComponent(scriptName: 'q.ember'))], {'q.ember': src});
    b.getComponent<PathFollower2DComponent>()!.distance = 60;
    steps(1);
    final q = engine.activeScene.findByName('Q')!;
    script(q).callFunction('onStart', const []);
    expect(script(q).field('near'), ['A']);
    expect(script(q).field('cell'), Vector2(100, 20));
    expect(script(q).field('away'), 30);
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('health bars and glowing lines draw without errors', () {
    final w = walker('W');
    final bolt = EmberEntity(name: 'Bolt')
      ..addComponent(Transform2DComponent())
      ..addComponent(Line2DComponent(points: [Vector2(0, 0), Vector2(50, 50)], glow: true, color: const Color(0xFF67E8F9)));
    start([pathEntity(), w, bolt]);
    w.getComponent<HealthComponent>()!.damage(4);
    final game = EmberFlameGame(engine: engine)..onGameResize(flame.Vector2(400, 300));
    final rec = PictureRecorder();
    game.render(Canvas(rec));
    rec.endRecording();
    expect((Line2DComponent()..fromJson(Line2DComponent(glow: true).toJson())).glow, isTrue);
    expect((HealthComponent()..fromJson(HealthComponent(showBar: true).toJson())).showBar, isTrue);
  });
}

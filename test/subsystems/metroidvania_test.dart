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
import 'package:ember_engine/subsystems/physics/character_controller2d.dart';
import 'package:ember_engine/subsystems/two_d/camera2d.dart';
import 'package:ember_engine/subsystems/two_d/camera_room.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/two_d/flame_game.dart';
import 'package:ember_engine/subsystems/ui/minimap.dart';
import 'package:vector_math/vector_math_64.dart';

EmberEngine get engine => EmberEngine.instance;

/// 40 × 20 cells of 32 px: a floor on row 15 and a wall at column 20 (rows 0-14).
EmberEntity level() {
  final tiles = [
    for (var r = 0; r < 20; r++)
      for (var c = 0; c < 40; c++) (r == 15 || (c == 20 && r < 15)) ? 1 : 0,
  ];
  return EmberEntity(name: 'Map')
    ..addComponent(Transform2DComponent(position: Vector2.zero(), size: Vector2(1280, 640)))
    ..addComponent(FlameTileMapComponent(columns: 40, rows: 20, tileSize: 32, tiles: tiles));
}

EmberEntity hero({String script = ''}) {
  final e = EmberEntity(name: 'Hero')
    ..addComponent(Transform2DComponent(position: Vector2(300, 450), size: Vector2(20, 30)))
    ..addComponent(CharacterController2DComponent(groundY: 100000, airJumps: 1, wallJump: true, dashSpeed: 600));
  if (script.isNotEmpty) e.addComponent(ScriptComponent(scriptName: script));
  return e;
}

CharacterController2DComponent ctl(EmberEntity e) => e.getComponent<CharacterController2DComponent>()!;
Vector2 pos(EmberEntity e) => e.getComponent<Transform2DComponent>()!.position;

/// Runs the controller for [frames] frames with this input.
void drive(EmberEntity e, int frames, {double x = 0, bool hold = false, bool press = false}) {
  for (var i = 0; i < frames; i++) {
    ctl(e).updateMovement(horizontalInput: x, isJumpPressed: hold || press, isJumpJustPressed: press && i == 0, dt: 1 / 60);
  }
}

void start(List<EmberEntity> entities, [Map<String, String> scripts = const {}]) {
  engine.stop();
  EmberScripts.instance.loadAll(scripts);
  final scene = EmberScene(name: 'Spire');
  for (final e in entities) {
    scene.addEntity(e);
  }
  engine.loadScene(scene);
  engine.step();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() => engine.stop());

  test('double jump: one extra jump in the air, recharged on landing', () {
    final h = hero(script: 'h.ember');
    start([level(), h], {'h.ember': 'var air = 0;\nvoid onAirJump() { air++; }\n'});
    drive(h, 60); // land
    expect(ctl(h).isGrounded, isTrue);
    drive(h, 1, press: true);
    drive(h, 20, hold: true);
    final peak = pos(h).y;
    expect(ctl(h).airJumpsLeft, 1);
    drive(h, 1, press: true);
    expect(ctl(h).airJumpsLeft, 0);
    expect(ctl(h).velocity.y, lessThan(0), reason: 'going up again');
    drive(h, 15, hold: true);
    expect(pos(h).y, lessThan(peak));
    final v = ctl(h).velocity.y;
    drive(h, 1, press: true);
    expect(ctl(h).velocity.y, greaterThan(v), reason: 'no third jump');
    drive(h, 120);
    expect(ctl(h).isGrounded, isTrue);
    expect(ctl(h).airJumpsLeft, 1);
    final s = h.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    expect(s.field('air'), 1);
  });

  test('wall slide and wall jump', () {
    final h = hero();
    start([level(), h]);
    pos(h).setValues(560, 200); // in the air, left of the wall at x = 640
    h.getComponent<Transform2DComponent>()!.position = Vector2(560, 200);
    drive(h, 40, x: 1);
    expect(ctl(h).onWall, 1);
    expect(ctl(h).velocity.y, lessThanOrEqualTo(ctl(h).wallSlideSpeed + 0.01), reason: 'sliding, not falling');
    drive(h, 1, x: 1, press: true);
    expect(ctl(h).velocity.x, lessThan(0), reason: 'kicked away from the wall');
    expect(ctl(h).velocity.y, lessThan(0));
    expect(ctl(h).facing, -1);
  });

  test('dash: fast, level, once in the air until landing', () {
    final h = hero();
    start([level(), h]);
    drive(h, 60);
    final x = pos(h).x;
    expect(ctl(h).dash(), isTrue);
    drive(h, 6);
    expect(pos(h).x - x, closeTo(600 * 0.1, 3));
    drive(h, 30);
    drive(h, 1, press: true);
    drive(h, 10, hold: true);
    expect(ctl(h).dash(), isTrue, reason: 'one in the air');
    drive(h, 20);
    expect(ctl(h).dash(), isFalse, reason: 'not two');
    drive(h, 120);
    expect(ctl(h).dash(), isTrue, reason: 'recharged on landing');
    final copy = CharacterController2DComponent()..fromJson(ctl(h).toJson());
    expect((copy.airJumps, copy.wallJump, copy.dashSpeed), (1, true, 600.0));
  });

  test('camera rooms keep the view in the room, glide to the next, and tell the target', () {
    EmberEntity room(String name, double x) => EmberEntity(name: name)
      ..addComponent(Transform2DComponent(position: Vector2(x, 0), size: Vector2(640, 640)))
      ..addComponent(CameraRoom2DComponent());
    final cam = EmberEntity(name: 'Camera')
      ..addComponent(Transform2DComponent(position: Vector2.zero(), size: Vector2.zero()))
      ..addComponent(Camera2DComponent(designWidth: 400, designHeight: 300, followTarget: 'Hero', smoothing: 0.8));
    final h = hero(script: 'h.ember');
    start([level(), room('Left', 0), room('Right', 640), h, cam], {'h.ember': 'var rooms = [];\nvoid onRoomEnter(r) { rooms.add(r.name); }\n'});
    h.getComponent<Transform2DComponent>()!.position = Vector2(620, 300);
    for (var i = 0; i < 120; i++) {
      engine.step();
    }
    final c = cam.getComponent<Camera2DComponent>()!;
    expect(c.position.x, closeTo(640 - 200, 0.5), reason: 'held inside the left room');
    expect(c.room?.entity?.name, 'Left');
    h.getComponent<Transform2DComponent>()!.position = Vector2(660, 300);
    engine.step();
    final afterOne = c.position.x;
    expect(afterOne, lessThan(640 + 200 - 1), reason: 'glides, does not jump');
    for (var i = 0; i < 120; i++) {
      engine.step();
    }
    expect(c.position.x, closeTo(640 + 200, 0.5));
    final s = h.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    expect(s.field('rooms'), ['Left', 'Right']);
  });

  test('the minimap reveals rooms as they are visited, shows markers, and saves what was explored', () {
    final room = EmberEntity(name: 'Start')
      ..addComponent(Transform2DComponent(position: Vector2.zero(), size: Vector2(320, 640)))
      ..addComponent(CameraRoom2DComponent());
    final save = EmberEntity(name: 'Shrine')
      ..tags.add('save')
      ..addComponent(Transform2DComponent(position: Vector2(100, 440), size: Vector2(20, 20)));
    final map = UIMinimapComponent(tilemap: 'Map', target: 'Hero', markers: 'save:#22D3EE');
    final h = hero()..getComponent<Transform2DComponent>()!.position = Vector2(100, 400);
    start([level(), room, save, h, EmberEntity(name: 'Minimap')..addComponent(map)]);
    engine.step();
    expect(map.seenAt(3, 10), isTrue);
    expect(map.seenAt(9, 10), isTrue, reason: 'the whole room');
    expect(map.seenAt(30, 10), isFalse);
    final data = map.explored;
    expect(map.exploredFraction, closeTo(10 * 20 / 800, 0.001));

    final other = UIMinimapComponent(tilemap: 'Map');
    engine.activeScene.addEntity(EmberEntity(name: 'Other')..addComponent(other));
    other.explored = data;
    expect(other.seenAt(9, 10), isTrue);
    expect(other.seenAt(30, 10), isFalse);

    final game = EmberFlameGame(engine: engine)..onGameResize(flame.Vector2(800, 450));
    final rec = PictureRecorder();
    game.render(Canvas(rec));
    rec.endRecording();
    final copy = UIMinimapComponent()..fromJson(map.toJson());
    expect((copy.tilemap, copy.target, copy.markers), ('Map', 'Hero', 'save:#22D3EE'));
  });
}

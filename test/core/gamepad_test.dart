import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/gamepad.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/player_input.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/scripting/script_library.dart';

EmberEngine get engine => EmberEngine.instance;
GamepadInput get pads => GamepadInput.instance;

void frame() => Input.endFrame();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Input.reset();
    pads.clear();
  });
  tearDown(() {
    Input.reset();
    pads.clear();
  });

  test('gamepad 1 drives the usual actions and movement', () {
    expect(Input.isActionPressed('jump'), isFalse);
    pads.press(0, GamepadButton.a);
    expect(Input.isActionJustPressed('jump'), isTrue);
    expect(Input.isActionPressed('jump'), isTrue);
    frame();
    expect(Input.isActionJustPressed('jump'), isFalse, reason: 'only on the first frame');
    pads.release(0, GamepadButton.a);
    expect(Input.isActionJustReleased('jump'), isTrue);

    pads.setAxis(0, GamepadAxis.leftStickX, 0.9);
    pads.setAxis(0, GamepadAxis.leftStickY, 0.1); // inside the dead zone
    expect(Input.getAxis('horizontal'), closeTo(0.9, 1e-9));
    expect(Input.getAxis('vertical'), 0);
    expect(pads.stick(0).x, closeTo(0.9, 1e-9));
    pads.setAxis(0, GamepadAxis.leftStickY, 1);
    expect(pads.stick(0).y, lessThan(0), reason: 'stick up is up on screen (y down)');
  });

  test('two players: each has a half of the keyboard and their own pad', () {
    final p1 = PlayerControls.of(0), p2 = PlayerControls.of(1);
    Input.onKeyDown(LogicalKeyboardKey.keyF);
    expect(p1.pressed('attack'), isTrue);
    expect(p2.pressed('attack'), isFalse);
    Input.onKeyDown(LogicalKeyboardKey.arrowLeft);
    expect(p2.move.x, -1);
    expect(p1.move.x, 0);
    frame();
    pads.press(1, GamepadButton.x);
    expect(p2.pressed('attack'), isTrue);
    expect(p2.usingPad, isTrue);
    pads.setAxis(1, GamepadAxis.leftStickX, 1);
    Input.onKeyUp(LogicalKeyboardKey.arrowLeft);
    expect(p2.move.x, closeTo(1, 1e-9));
    expect(p2.down('right'), isTrue, reason: 'the stick counts as a direction');
  });

  test('motions: a quarter circle forward then attack, mirrored when facing left, within the window', () {
    final p = PlayerControls.of(0);
    void hold(List<LogicalKeyboardKey> keys) {
      for (final k in [LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyD]) {
        Input.onKeyUp(k);
      }
      for (final k in keys) {
        Input.onKeyDown(k);
      }
      frame();
    }

    hold([LogicalKeyboardKey.keyS]);
    hold([LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyD]);
    hold([LogicalKeyboardKey.keyD]);
    Input.onKeyDown(LogicalKeyboardKey.keyF);
    expect(p.motion('236', 'attack'), isTrue);
    expect(p.motion('214', 'attack'), isFalse);
    expect(p.motion('214', 'attack', facingRight: false), isTrue, reason: 'facing left, forward is A');
    frame();
    Input.onKeyUp(LogicalKeyboardKey.keyF);
    for (var i = 0; i < 30; i++) {
      frame();
    }
    Input.onKeyDown(LogicalKeyboardKey.keyF);
    expect(p.motion('236', 'attack'), isFalse, reason: 'too long ago');
    expect(p.buffered('attack'), isTrue);
  });

  test('scripts read players and pads', () {
    registerAllSubsystems();
    EmberScripts.instance.loadAll({
      'p.ember': '''
var jumped = false;
var attack2 = false;
var stick = null;
var connected = false;
void onUpdate(dt) {
  if (Input.player(1).pressed("jump")) jumped = true;
  if (Input.player(2).key("attack")) attack2 = true;
  stick = Input.pad(1).stick;
  connected = Input.pad(1).connected;
}
''',
    });
    final e = EmberEntity(name: 'P')..addComponent(ScriptComponent(scriptName: 'p.ember'));
    engine.stop();
    engine.setMode(EngineMode.twoD);
    engine.loadScene(EmberScene(name: 'Pads')..addEntity(e));
    engine.step(); // Play starts with fresh input
    pads.press(0, GamepadButton.a);
    pads.setAxis(0, GamepadAxis.leftStickX, -1);
    Input.onKeyDown(LogicalKeyboardKey.comma);
    engine.step();
    final s = e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    expect(EmberScripts.instance.problems, isEmpty);
    expect(s.field('jumped'), isTrue);
    expect(s.field('attack2'), isTrue);
    expect(s.field('connected'), isTrue);
    expect((s.field('stick') as dynamic).x, -1);
    engine.stop();
  });
}

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/gamepad.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/templates/clash_game.dart';
import 'package:ember_engine/templates/clash_scripts.dart';

EmberEngine get engine => EmberEngine.instance;
EmberEntity find(String name) => engine.activeScene.findByName(name)!;
EmberScriptBehavior scriptOf(String name) => find(name).getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
EmberScriptBehavior get kai => scriptOf('Kai');
EmberScriptBehavior get ryn => scriptOf('Ryn');
EmberScriptBehavior get match => scriptOf('Match');
double hp(String n) => find(n).getComponent<HealthComponent>()!.health;
String text(String name) => find(name).getComponent<UITextComponent>()!.text;

void startMatch({bool cpu = false, String level = 'normal'}) {
  engine.stop();
  final project = TemplateCatalog.getByType(ProjectTemplateType.clash).createProject(name: 'Clash Test');
  EmberScripts.instance.loadAll(project.scripts);
  final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
  engine.sceneLibrary = () => levels;
  engine.loadScene(project.scenes[Clash.arena]!);
  engine.step();
  EmberScripts.instance.gameData['clashCpu'] = cpu;
  EmberScripts.instance.gameData['clashLevel'] = level;
  engine.restartScene();
  engine.step();
  steps(130); // "ROUND 1", "FIGHT!"
  expect(match.field('state'), 'fight');
}

void steps(int n) {
  for (var i = 0; i < n; i++) {
    engine.step();
  }
}

void tap(LogicalKeyboardKey k, {int hold = 2}) {
  Input.onKeyDown(k);
  steps(hold);
  Input.onKeyUp(k);
}

/// Puts the fighters [gap] pixels apart in the middle of the stage.
void closeIn(double gap) {
  kai.setField('x', 480 - gap / 2);
  ryn.setField('x', 480 + gap / 2);
  steps(2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('clash test');
    for (final l in ['easy', 'normal', 'hard']) {
      SaveData.instance.remove('clash_wins_$l');
    }
    GamepadInput.instance.clear();
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() {
    Input.reset();
    GamepadInput.instance.clear();
    engine.timeScale = 1;
    engine.stop();
  });

  test('the template: title and arena, scripts that compile, art and sound on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.clash).createProject(name: 'Clash');
    expect(project.scenes.keys, containsAll([Clash.title, Clash.arena]));
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in clashScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Clash.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('a jab lands after its startup frames, with hitstop and hitstun; holding back guards it', () {
    startMatch();
    expect(kai.field('facing'), 1);
    expect(ryn.field('facing'), -1);
    closeIn(90);
    Input.onKeyDown(LogicalKeyboardKey.keyF);
    steps(1);
    Input.onKeyUp(LogicalKeyboardKey.keyF);
    expect(hp('Ryn'), 100, reason: 'still starting up');
    steps(6);
    expect(hp('Ryn'), 95);
    expect(ryn.field('state'), 'hit');
    steps(40);

    // Ryn faces left, so back is the right arrow
    Input.onKeyDown(LogicalKeyboardKey.arrowRight);
    closeIn(90);
    tap(LogicalKeyboardKey.keyF);
    steps(8);
    expect(hp('Ryn'), 95, reason: 'guarded');
    expect(ryn.field('state'), 'block');
    Input.onKeyUp(LogicalKeyboardKey.arrowRight);
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('low kicks must be guarded crouching; standing guard does not stop them', () {
    startMatch();
    Input.onKeyDown(LogicalKeyboardKey.arrowRight); // Ryn holds back, standing
    closeIn(100);
    Input.onKeyDown(LogicalKeyboardKey.keyS);
    tap(LogicalKeyboardKey.keyF);
    steps(10);
    Input.onKeyUp(LogicalKeyboardKey.keyS);
    expect(hp('Ryn'), 94, reason: 'the low kick hit');
    steps(40);
    Input.onKeyDown(LogicalKeyboardKey.arrowDown); // now down-back
    steps(2);
    closeIn(100);
    Input.onKeyDown(LogicalKeyboardKey.keyS);
    tap(LogicalKeyboardKey.keyF);
    steps(10);
    Input.onKeyUp(LogicalKeyboardKey.keyS);
    expect(hp('Ryn'), 94, reason: 'guarded low');
    Input.onKeyUp(LogicalKeyboardKey.arrowDown);
    Input.onKeyUp(LogicalKeyboardKey.arrowRight);
  });

  test('down, down-forward, forward + jab throws an orb across the stage; the rising strike cannot be hit at first', () {
    startMatch();
    closeIn(400);
    Input.onKeyDown(LogicalKeyboardKey.keyS);
    steps(2);
    Input.onKeyDown(LogicalKeyboardKey.keyD);
    steps(2);
    Input.onKeyUp(LogicalKeyboardKey.keyS);
    steps(2);
    tap(LogicalKeyboardKey.keyF);
    Input.onKeyUp(LogicalKeyboardKey.keyD);
    expect(kai.field('move'), 'orb');
    steps(14);
    expect(engine.activeScene.allEntities.where((e) => e.enabled && e.name == 'Kai Orb'), hasLength(1));
    steps(70);
    expect(hp('Ryn'), 92, reason: 'the orb hit');
    expect(engine.activeScene.allEntities.where((e) => e.enabled && e.name == 'Kai Orb'), isEmpty);

    steps(40);
    kai.callFunction('start', ['rise']);
    steps(2);
    expect(kai.callFunction('hurtbox', [470.0, 300.0, 60.0, 140.0]), isFalse, reason: 'invulnerable at the start');
    steps(20);
    expect(kai.callFunction('hurtbox', [kai.field('x'), (kai.field('y') as num) - 100, 10.0, 50.0]), isTrue);
  });

  test('a knock-out wins the round; two rounds win the match', () {
    startMatch();
    for (var round = 1; round <= 2; round++) {
      closeIn(90);
      find('Ryn').getComponent<HealthComponent>()!.health = 3;
      tap(LogicalKeyboardKey.keyF);
      steps(10);
      expect(ryn.field('state'), 'ko');
      expect(match.field('state'), 'ko');
      expect(text('Banner'), 'K.O.');
      steps(60 * 6);
    }
    expect(match.field('state'), 'over');
    expect(text('ResultsTitle'), 'KAI WINS');
    expect(find('RetryButton').enabled, isTrue);
  });

  test('the CPU fights back', () {
    startMatch(cpu: true, level: 'hard');
    expect(ryn.field('cpu'), isTrue);
    steps(60 * 20);
    expect(hp('Kai'), lessThan(100), reason: 'the CPU landed hits');
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('player 2 can fight with a gamepad', () {
    startMatch();
    closeIn(90);
    GamepadInput.instance.setAxis(0, GamepadAxis.leftStickX, 0); // pad 1 is player 1's (left alone)
    GamepadInput.instance.press(1, GamepadButton.x);
    steps(1);
    GamepadInput.instance.release(1, GamepadButton.x);
    steps(8);
    expect(hp('Kai'), 95, reason: "pad 2's X is player 2's jab");
  });
}

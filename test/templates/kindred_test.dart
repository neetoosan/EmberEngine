import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/gamepad.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/two_d/camera2d.dart';
import 'package:ember_engine/subsystems/two_d/line2d.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/templates/kindred_game.dart';
import 'package:ember_engine/templates/kindred_scripts.dart';

EmberEngine get engine => EmberEngine.instance;
EmberEntity find(String name) => engine.activeScene.findByName(name)!;
EmberScriptBehavior scriptOf(EmberEntity e) => e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
EmberScriptBehavior get game => scriptOf(find('Grove'));
Camera2DComponent get camera => find('Camera').getComponent<Camera2DComponent>()!;
HealthComponent health(String name) => find(name).getComponent<HealthComponent>()!;
String text(String name) => find(name).getComponent<UITextComponent>()!.text;
EmberEntity live(String name) => engine.activeScene.allEntities.firstWhere((e) => e.enabled && e.name == name);
List<EmberEntity> foes() => [for (final e in engine.activeScene.allEntities) if (e.enabled && e.tags.contains('foe')) e];

void steps(int n) {
  for (var i = 0; i < n; i++) {
    engine.step();
  }
}

void place(String name, double x, double y) => find(name).getComponent<Transform2DComponent>()!.position = vm.Vector2(x, y);

/// Starts the grove and waits out the first banner.
void startGrove() {
  engine.stop();
  final project = TemplateCatalog.getByType(ProjectTemplateType.kindred).createProject(name: 'Kindred Test');
  EmberScripts.instance.loadAll(project.scripts);
  final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
  engine.sceneLibrary = () => levels;
  engine.loadScene(project.scenes[Kindred.grove]!);
  engine.step();
  steps(170);
  expect(game.field('state'), 'play');
}

void join(LogicalKeyboardKey key) {
  Input.onKeyDown(key);
  steps(1);
  Input.onKeyUp(key);
  steps(1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('kindred test');
    SaveData.instance.remove('kindred_best');
    SaveData.instance.remove('kindred_wave');
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

  test('the template: title and grove, scripts that compile, art and sound on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.kindred).createProject(name: 'Kindred');
    expect(project.scenes.keys, containsAll([Kindred.title, Kindred.grove]));
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in kindredScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Kindred.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('player 2 joins with their shoot key; the camera zooms out to keep both in view', () {
    startGrove();
    expect(find('Lume').enabled, isFalse);
    expect(find('Join2').enabled, isTrue);
    join(LogicalKeyboardKey.comma);
    expect(find('Lume').enabled, isTrue);
    expect(find('Bar2').enabled, isTrue);
    expect(find('Join2').enabled, isFalse);
    expect(text('Banner'), 'LUME JOINS');

    // Far apart: the camera zooms out (to its limit) and sits between them
    place('Sol', 150, 500);
    place('Lume', 1450, 500);
    steps(120);
    expect(camera.zoom, closeTo(camera.minZoom, 0.02));
    expect(camera.position.x, closeTo(800, 30));
    // Close together: back in
    place('Sol', 760, 500);
    place('Lume', 840, 500);
    steps(120);
    expect(camera.zoom, closeTo(1, 0.02));
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('nobody can walk off the shared screen', () {
    startGrove();
    join(LogicalKeyboardKey.comma);
    place('Sol', 800, 500);
    place('Lume', 820, 500);
    steps(30);
    Input.onKeyDown(LogicalKeyboardKey.keyA); // Sol runs left
    Input.onKeyDown(LogicalKeyboardKey.arrowRight); // Lume runs right
    steps(60 * 8);
    Input.onKeyUp(LogicalKeyboardKey.keyA);
    Input.onKeyUp(LogicalKeyboardKey.arrowRight);
    final sol = find('Sol').getComponent<Transform2DComponent>()!.position.x;
    final lume = find('Lume').getComponent<Transform2DComponent>()!.position.x;
    final view = 960 / camera.minZoom;
    expect(lume - sol, lessThanOrEqualTo(view - 80 + 2), reason: 'both stay inside the widest view');
    expect(lume - sol, greaterThan(view * 0.6), reason: 'but they did spread out');
  });

  test('the bond between two spirits burns a shadow that crosses it', () {
    startGrove();
    join(LogicalKeyboardKey.comma);
    place('Sol', 700, 500);
    place('Lume', 900, 500);
    steps(2);
    final bond = find('Bond 1').getComponent<Line2DComponent>()!;
    expect(bond.points, hasLength(2));
    final wisp = foes().isNotEmpty ? foes().first : null;
    expect(wisp, isNotNull, reason: 'the first wave is coming in');
    wisp!.getComponent<HealthComponent>()!.maxHealth = 50;
    wisp.getComponent<HealthComponent>()!.health = 50;
    wisp.getComponent<Transform2DComponent>()!.position = vm.Vector2(800 - 23, 500 - 23);
    steps(20);
    expect(wisp.getComponent<HealthComponent>()!.health, lessThan(50));

    // Too far apart, and the bond breaks
    place('Sol', 300, 500);
    place('Lume', 1300, 500);
    steps(2);
    expect(bond.points, isEmpty);
  });

  test('a fallen spirit gets up when a friend stays close; everyone down ends the night', () {
    startGrove();
    join(LogicalKeyboardKey.comma);
    place('Sol', 800, 500);
    place('Lume', 840, 500);
    steps(100); // past the join shield
    health('Lume').damage(99);
    steps(1);
    final lume = scriptOf(find('Lume'));
    expect(lume.field('down'), isTrue);
    expect(find('Lume').tags.contains('alive'), isFalse);
    expect(text('Name2'), contains('DOWN'));
    steps(60);
    expect(lume.field('down'), isTrue, reason: 'still being revived');
    steps(70);
    expect(lume.field('down'), isFalse);
    expect(health('Lume').health, 3);

    steps(100);
    health('Lume').kill();
    health('Sol').kill(); // (damage could miss: a wisp may have just made Sol invulnerable)
    steps(2);
    expect(game.field('state'), 'over');
    expect(text('ResultsTitle'), 'THE LIGHT FADED');
    expect(find('RetryButton').enabled, isTrue);
  });

  test('clearing a wave brings the next; the team grows with a gamepad', () {
    startGrove();
    // Player 3 joins on pad 3
    GamepadInput.instance.press(2, GamepadButton.x);
    steps(1);
    GamepadInput.instance.release(2, GamepadButton.x);
    steps(1);
    expect(find('Iris').enabled, isTrue);
    expect(game.callFunction('teamSize', []), 2);

    // Clear wave 1 by hand
    for (var i = 0; i < 60 * 30 && game.field('wave') == 1; i++) {
      for (final f in foes()) {
        f.getComponent<HealthComponent>()!.damage(99);
      }
      engine.step();
    }
    expect(game.field('wave'), 2);
    steps(1);
    expect(text('WaveText'), 'WAVE 2 / 10');
    expect(game.field('score') as num, greaterThan(100));
  });

  test('two spirits hold off brutes and spitters (no script errors along the way)', () {
    startGrove();
    join(LogicalKeyboardKey.comma);
    game.setField('wave', 4);
    game.setField('queue', []);
    for (final f in foes()) {
      f.getComponent<HealthComponent>()!.damage(99);
    }
    steps(60 * 3 + 170); // wave 5: wisps, brutes and spitters
    expect(game.field('wave'), 5);
    for (final s in ['Sol', 'Lume']) {
      health(s).maxHealth = 999;
      health(s).health = 999;
    }
    Input.onKeyDown(LogicalKeyboardKey.keyF);
    Input.onKeyDown(LogicalKeyboardKey.comma);
    steps(60 * 25);
    Input.onKeyUp(LogicalKeyboardKey.keyF);
    Input.onKeyUp(LogicalKeyboardKey.comma);
    expect(game.field('kills') as num, greaterThan(10));
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('the Hollow on wave ten: defeat it and the grove is safe', () {
    startGrove();
    game.setField('wave', 9);
    game.setField('queue', []);
    for (final f in foes()) {
      f.getComponent<HealthComponent>()!.damage(99);
    }
    steps(4); // wave cleared
    expect(game.field('state'), 'clear');
    steps(60 * 3 + 170);
    expect(game.field('wave'), 10);
    steps(5);
    final hollow = live('Hollow');
    expect(find('BossBar').enabled, isTrue);
    place('Sol', 800, 850);
    steps(60 * 4);
    expect(engine.activeScene.allEntities.any((e) => e.enabled && e.name == 'Wisp'), isTrue);
    hollow.getComponent<HealthComponent>()!.damage(9999);
    steps(60 * 3);
    expect(text('ResultsTitle'), 'THE GROVE IS SAFE');
    expect(EmberScripts.instance.problems, isEmpty);
  });
}

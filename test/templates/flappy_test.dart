import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/project_storage.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/templates/flappy_game.dart';
import 'package:ember_engine/templates/flappy_scripts.dart';

EmberEngine get engine => EmberEngine.instance;

EmberScriptBehavior scriptOf(String entity) =>
    engine.activeScene.findByName(entity)!.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;

/// The Game script's variables.
Object? game(String field) => scriptOf('Game').field(field);
void setGame(String field, Object? v) => scriptOf('Game').instance!.fields[field] = v;

double get birdY => engine.activeScene.findByName('Bird')!.getComponent<Transform2DComponent>()!.position.y;

String text(String entity) => engine.activeScene.findByName(entity)!.getComponent<UITextComponent>()!.text;

int get pipeCount => engine.activeScene.rootEntities.where((e) => e.name == 'PipePair').length;

/// Advances the game by [seconds] at 60 fps.
void run(double seconds, {bool Function()? flapWhen}) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    final flap = flapWhen?.call() ?? false;
    if (flap) Input.onKeyDown(LogicalKeyboardKey.space);
    engine.step();
    if (flap) Input.onKeyUp(LogicalKeyboardKey.space);
  }
}

void tapToFlap() {
  Input.onMouseDown(0);
  engine.step();
  Input.onMouseUp(0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('flappy test');
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    EmberScripts.instance.loadAll(flappyScripts);
    engine.loadScene(buildFlappyScene());
    engine.step(); // start the simulation (paused, stepped manually)
  });

  tearDown(() {
    expect(EmberScripts.instance.problems.map((p) => '$p'), isEmpty, reason: 'scripts ran without errors');
    engine.stop();
  });

  test('template: the scene, its Ember Scripts (editable, error-free) and all art', () async {
    final project = TemplateCatalog.getByType(ProjectTemplateType.flappy).createProject(name: 'Flap');
    final scene = project.activeScene;
    for (final name in ['Camera', 'Bird', 'Ground', 'Hills', 'Game', 'ScoreText', 'MessageText', 'Pipe Template']) {
      expect(scene.findByName(name), isNotNull, reason: name);
    }
    expect(project.scripts.keys, containsAll(flappyScripts.keys));
    for (final e in project.scripts.entries) {
      expect(EmberScripts.check(e.key, e.value), isNull, reason: e.key);
    }
    // Every script component in the scene uses one of the project's scripts
    for (final e in scene.allEntities) {
      for (final c in e.components.whereType<ScriptComponent>()) {
        expect(project.scripts.keys, contains(c.scriptName), reason: '${e.name} uses ${c.scriptName}');
      }
    }
    final art = ProjectStorage.referencedAssetPaths(project);
    expect(art, containsAll(['assets/templates/flappy/bird.png', 'assets/templates/flappy/ground.png']));
    for (final path in art) {
      expect((await rootBundle.load(path)).lengthInBytes, greaterThan(0), reason: path);
    }
  });

  test('waits in Ready until the first flap, then the bird rises and falls', () {
    run(1.0);
    expect(game('state'), 'ready');
    expect(pipeCount, 0);
    expect(text('MessageText'), contains('GET READY'));

    final startY = birdY;
    tapToFlap();
    expect(game('state'), 'playing');
    run(0.15);
    expect(birdY, lessThan(startY - 20), reason: 'flap moves the bird up');
    run(0.6);
    expect(birdY, greaterThan(startY), reason: 'gravity pulls it back down');
    expect(text('MessageText'), isEmpty);
  });

  test('pipes spawn from the template, scroll left and are removed off-screen', () {
    tapToFlap();
    run(1.0, flapWhen: () => birdY > 200);
    expect(pipeCount, 1);
    final pair = engine.activeScene.findByName('PipePair')!;
    expect(pair.enabled, isTrue);
    expect(pair.children.map((c) => c.name), contains('ScoreGate'));
    final firstX = pair.getComponent<Transform2DComponent>()!.position.x;
    run(0.5, flapWhen: () => birdY > 200);
    if (game('state') == 'playing') expect(pair.getComponent<Transform2DComponent>()!.position.x, lessThan(firstX));

    // Pipes never pile up: at most ~3 on screen at a time
    setGame('state', 'playing');
    scriptOf('Bird').instance!.fields['alive'] = false; // ignore crashes; just watch the pipe stream
    run(8.0);
    expect(pipeCount, lessThanOrEqualTo(4));
  });

  test('passing through a gap scores; the score shows on screen', () {
    tapToFlap();
    scriptOf('Game').callFunction('spawnPipes', [240]);
    run(2.4, flapWhen: () => birdY > 250);
    expect(scriptOf('Bird').field('alive'), isTrue);
    expect(game('score'), 1);
    expect(text('ScoreText'), '1');
  });

  test('hitting a pipe ends the game, saves the best score, and a flap restarts', () {
    tapToFlap();
    scriptOf('Game').callFunction('spawnPipes', [420]); // opening near the ground; bird flies into the top pipe
    run(3.0, flapWhen: () => game('state') == 'playing' && birdY > 150);
    expect(game('state'), 'dead');
    expect(text('MessageText'), contains('GAME OVER'));
    expect(SaveData.instance.getInt('best'), greaterThanOrEqualTo(game('score') as int));

    final deadScene = engine.activeScene;
    run(1.0); // bird falls to the ground; wait past the retry delay
    tapToFlap();
    expect(identical(engine.activeScene, deadScene), isFalse, reason: 'scene restarted');
    expect(game('state'), 'ready');
    expect(game('score'), 0);
    expect(pipeCount, 0);
  });

  test('falling to the ground ends the game', () {
    tapToFlap();
    run(2.0);
    expect(game('state'), 'dead');
    expect(birdY, closeTo(Flappy.groundTop - 12, 0.01));
  });

  test('the ground and hills share one scroller script with their own Inspector values', () {
    final ground = scriptOf('Ground'), hills = scriptOf('Hills');
    expect(ground.file, hills.file);
    expect(hills.exposedFields['speedFactor'], 0.25);
    expect(hills.exposedFields['wrapWidth'], 144);
    tapToFlap();
    final g0 = engine.activeScene.findByName('Ground')!.getComponent<Transform2DComponent>()!.position.x;
    final h0 = engine.activeScene.findByName('Hills')!.getComponent<Transform2DComponent>()!.position.x;
    run(0.2, flapWhen: () => birdY > 200);
    final gMoved = g0 - engine.activeScene.findByName('Ground')!.getComponent<Transform2DComponent>()!.position.x;
    final hMoved = h0 - engine.activeScene.findByName('Hills')!.getComponent<Transform2DComponent>()!.position.x;
    expect(hMoved, closeTo(gMoved * 0.25, 1.5));
  });
}

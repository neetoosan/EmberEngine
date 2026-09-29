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
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/templates/flappy_game.dart';

EmberEngine get engine => EmberEngine.instance;

FlappyGame get game => FlappyGame.current!;

FlappyBird get bird =>
    engine.activeScene.findByName('Bird')!.getComponent<ScriptComponent>()!.scriptInstance as FlappyBird;

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
    engine.loadScene(buildFlappyScene());
    engine.step(); // start the simulation (paused, stepped manually)
  });

  tearDown(() => engine.stop());

  test('template creates the Flappy scene; all its art is bundled', () async {
    final project = TemplateCatalog.getByType(ProjectTemplateType.flappy).createProject(name: 'Flap');
    final scene = project.activeScene;
    for (final name in ['Camera', 'Bird', 'Ground', 'Hills', 'Game', 'ScoreText', 'MessageText']) {
      expect(scene.findByName(name), isNotNull, reason: name);
    }
    final art = ProjectStorage.referencedAssetPaths(project);
    expect(art, containsAll(['assets/templates/flappy/bird.png', 'assets/templates/flappy/ground.png']));
    for (final path in art) {
      expect((await rootBundle.load(path)).lengthInBytes, greaterThan(0), reason: path);
    }
  });

  test('waits in Ready until the first flap, then the bird rises and falls', () {
    run(1.0);
    expect(game.state, FlappyState.ready);
    expect(pipeCount, 0);
    expect(text('MessageText'), contains('GET READY'));

    final startY = birdY;
    tapToFlap();
    expect(game.state, FlappyState.playing);
    run(0.15);
    expect(birdY, lessThan(startY - 20), reason: 'flap moves the bird up');
    run(0.6);
    expect(birdY, greaterThan(startY), reason: 'gravity pulls it back down');
    expect(text('MessageText'), isEmpty);
  });

  test('pipes spawn, scroll left and are removed off-screen', () {
    tapToFlap();
    run(1.0, flapWhen: () => birdY > 200);
    expect(pipeCount, 1);
    final firstX = engine.activeScene.findByName('PipePair')!.getComponent<Transform2DComponent>()!.position.x;
    run(0.5, flapWhen: () => birdY > 200);
    final laterX = engine.activeScene.findByName('PipePair')?.getComponent<Transform2DComponent>()?.position.x;
    if (game.state == FlappyState.playing) expect(laterX, lessThan(firstX));

    // Pipes never pile up: at most ~3 on screen at a time
    game.state = FlappyState.playing;
    bird.alive = false; // ignore crashes; just watch the pipe stream
    run(8.0);
    expect(pipeCount, lessThanOrEqualTo(4));
  });

  test('passing through a gap scores; the score shows on screen', () {
    tapToFlap();
    game.spawnPipes(gapCenter: 240);
    run(2.4, flapWhen: () => birdY > 250);
    expect(bird.alive, isTrue);
    expect(game.score, 1);
    expect(text('ScoreText'), '1');
  });

  test('hitting a pipe ends the game, saves the best score, and a flap restarts', () {
    tapToFlap();
    game.spawnPipes(gapCenter: 420); // opening near the ground; bird flies into the top pipe
    run(3.0, flapWhen: () => game.state == FlappyState.playing && birdY > 150);
    expect(game.state, FlappyState.dead);
    expect(text('MessageText'), contains('GAME OVER'));
    expect(SaveData.instance.getInt('best'), greaterThanOrEqualTo(game.score));

    final deadScene = engine.activeScene;
    run(1.0); // bird falls to the ground; wait past the retry delay
    tapToFlap();
    expect(identical(engine.activeScene, deadScene), isFalse, reason: 'scene restarted');
    expect(game.state, FlappyState.ready);
    expect(game.score, 0);
    expect(pipeCount, 0);
  });

  test('falling to the ground ends the game', () {
    tapToFlap();
    run(2.0);
    expect(game.state, FlappyState.dead);
    expect(birdY, closeTo(Flappy.groundTop - FlappyBird.radius, 0.01));
  });
}

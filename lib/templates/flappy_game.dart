import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/engine_loop.dart';
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/input.dart';
import '../core/save_data.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/audio/audio_system.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/ui/ui_text.dart';

/// "Flappy Arcade": a one-button endless flyer (Flappy Bird-style) built
/// entirely from engine components and the scripts in this file.
///
/// World is 288×512 design pixels (the camera scales it to any window).
class Flappy {
  static const double worldW = 288;
  static const double worldH = 512;
  static const double groundTop = 448;
  static const double scrollSpeed = 120; // px/s
  static const double pipeInterval = 1.45; // s between pipe pairs
  static const double gap = 116; // opening between pipes
  static const double pipeWidth = 52;
  static const double capHeight = 24;
  static const String art = 'assets/templates/flappy';

  /// Space, W, Up, a mouse click or a touch.
  static bool get flapPressed =>
      Input.isActionJustPressed(EngineAction.jump) ||
      Input.isMouseButtonJustPressed(0) ||
      Input.isKeyJustPressed(LogicalKeyboardKey.keyW) ||
      Input.isKeyJustPressed(LogicalKeyboardKey.arrowUp);
}

enum FlappyState { ready, playing, dead }

/// Game flow: Ready → Playing → Game Over → restart. Spawns pipes and keeps score.
class FlappyGame extends GameScript {
  static FlappyGame? current;

  FlappyState state = FlappyState.ready;
  int score = 0;
  double _spawnTimer = 0;
  double _deadTime = 0;
  final math.Random _rng = math.Random();

  @override
  void onStart() {
    current = this;
    _setText('ScoreText', '');
    _setText('MessageText', 'GET READY\n\nClick, tap or press Space\nto flap');
  }

  @override
  void onDestroy() {
    if (identical(current, this)) current = null;
  }

  FlappyBird? get _bird =>
      find('Bird')?.getComponent<ScriptComponent>()?.scriptInstance as FlappyBird?;

  @override
  void onUpdate(double dt) {
    switch (state) {
      case FlappyState.ready:
        if (Flappy.flapPressed) {
          state = FlappyState.playing;
          _spawnTimer = 0.9;
          _setText('MessageText', '');
          _setText('ScoreText', '0');
          _bird?.flap();
        }
      case FlappyState.playing:
        _spawnTimer -= dt;
        if (_spawnTimer <= 0) {
          _spawnTimer += Flappy.pipeInterval;
          spawnPipes();
        }
      case FlappyState.dead:
        _deadTime += dt;
        if (_deadTime > 0.8 && Flappy.flapPressed) EmberEngine.instance.restartScene();
    }
  }

  /// Adds a pipe pair just past the right edge with a random gap height.
  EmberEntity spawnPipes({double? gapCenter}) {
    final centerY = gapCenter ?? 150 + _rng.nextDouble() * 180;
    final pair = EmberEntity(name: 'PipePair')
      ..addComponent(Transform2DComponent(position: vm.Vector2(Flappy.worldW + 40, centerY), size: vm.Vector2.zero()))
      ..addComponent(ScriptComponent(scriptName: 'Flappy Pipe'));

    EmberEntity part(String name, double y, double w, double h, EmberAnchor anchor, String image) {
      final e = EmberEntity(name: name, tags: {'deadly'});
      e.addComponent(Transform2DComponent(position: vm.Vector2(0, y), size: vm.Vector2(w, h), anchor: anchor, zIndex: 1));
      e.addComponent(FlameSpriteComponent(assetPath: '${Flappy.art}/$image', flipY: anchor == EmberAnchor.bottomCenter));
      e.addComponent(FlameHitbox2DComponent(size: vm.Vector2(w, h), isSolid: false, debugDraw: false));
      return e;
    }

    const half = Flappy.gap / 2;
    pair.addChild(part('PipeTopBody', -half - Flappy.capHeight, Flappy.pipeWidth, 640, EmberAnchor.bottomCenter, 'pipe_body.png'));
    pair.addChild(part('PipeTopCap', -half, Flappy.pipeWidth + 8, Flappy.capHeight, EmberAnchor.bottomCenter, 'pipe_cap.png'));
    pair.addChild(part('PipeBottomBody', half + Flappy.capHeight, Flappy.pipeWidth, 640, EmberAnchor.topCenter, 'pipe_body.png'));
    pair.addChild(part('PipeBottomCap', half, Flappy.pipeWidth + 8, Flappy.capHeight, EmberAnchor.topCenter, 'pipe_cap.png'));

    // Invisible gate between the pipes: passing it scores a point
    final gate = EmberEntity(name: 'ScoreGate')
      ..addComponent(Transform2DComponent(size: vm.Vector2(6, Flappy.gap), anchor: EmberAnchor.center))
      ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(6, Flappy.gap), isSolid: false, debugDraw: false));
    pair.addChild(gate);
    return spawn(pair);
  }

  void addPoint() {
    if (state != FlappyState.playing) return;
    score++;
    _setText('ScoreText', '$score');
    AudioSystem.instance.playProcedural('coin', volume: 0.6);
  }

  void gameOver() {
    if (state == FlappyState.dead) return;
    state = FlappyState.dead;
    _deadTime = 0;
    final best = math.max(score, SaveData.instance.getInt('best'));
    SaveData.instance.setInt('best', best);
    AudioSystem.instance.playProcedural('hit', volume: 0.9);
    _setText('MessageText', 'GAME OVER\n\nScore $score    Best $best\n\nClick or Space to retry');
  }

  void _setText(String entityName, String text) {
    find(entityName)?.getComponent<UITextComponent>()?.text = text;
  }
}

/// The bird: gravity, flapping, nose tilt, wing animation, crashing.
class FlappyBird extends GameScript {
  static const double gravity = 1500;
  static const double flapVelocity = -430;
  static const double maxFall = 620;
  static const double radius = 12; // half the bird's height, for the ground check

  double velocity = 0;
  bool alive = true;
  double _time = 0;
  double? _baseY;

  Transform2DComponent? get _t => getComponent<Transform2DComponent>();

  void flap() {
    if (!alive) return;
    velocity = flapVelocity;
    AudioSystem.instance.playProcedural('jump', volume: 0.5, pitch: 1.4);
  }

  @override
  void onUpdate(double dt) {
    final t = _t;
    final game = FlappyGame.current;
    if (t == null || game == null) return;
    _time += dt;
    _baseY ??= t.position.y;

    // Wing flap animation (stops when dead)
    final sprite = getComponent<FlameSpriteComponent>();
    if (sprite != null && alive) sprite.frame = (_time / 0.09).floor() % 3;

    if (game.state == FlappyState.ready) {
      t.position = vm.Vector2(t.position.x, _baseY! + math.sin(_time * 6) * 6);
      t.rotation = 0;
      return;
    }

    if (game.state == FlappyState.playing && Flappy.flapPressed) flap();

    velocity = math.min(velocity + gravity * dt, maxFall);
    var y = t.position.y + velocity * dt;
    if (y < -20) {
      y = -20;
      velocity = 0;
    }
    if (y + radius >= Flappy.groundTop) {
      y = Flappy.groundTop - radius;
      velocity = 0;
      if (alive) _die();
    }
    t.position = vm.Vector2(t.position.x, y);

    // Nose up while rising, dive as it falls
    final targetDeg = !alive ? 90.0 : (velocity < 0 ? -25.0 : math.min(90.0, velocity / maxFall * 110.0));
    final current = t.rotationDegrees;
    t.rotationDegrees = current + (targetDeg - current) * math.min(1.0, dt * (velocity < 0 ? 20 : 6));
  }

  @override
  void onTriggerEnter(EmberEntity other) {
    if (!alive) return;
    if (other.name == 'ScoreGate') {
      FlappyGame.current?.addPoint();
    } else if (other.tags.contains('deadly')) {
      _die();
    }
  }

  void _die() {
    alive = false;
    velocity = math.max(velocity, 0);
    FlappyGame.current?.gameOver();
  }
}

/// Moves a pipe pair left; removes it once it is off-screen.
class FlappyPipe extends GameScript {
  @override
  void onUpdate(double dt) {
    final t = getComponent<Transform2DComponent>();
    if (t == null || FlappyGame.current?.state != FlappyState.playing) return;
    t.position = vm.Vector2(t.position.x - Flappy.scrollSpeed * dt, t.position.y);
    if (t.position.x < -60) destroy();
  }
}

/// Scrolls a row of identical tiles (ground, hills) and wraps seamlessly.
class FlappyScroller extends GameScript {
  final double speedFactor;
  final double wrapWidth;
  FlappyScroller(this.speedFactor, this.wrapWidth);

  @override
  void onUpdate(double dt) {
    final t = getComponent<Transform2DComponent>();
    if (t == null || FlappyGame.current?.state == FlappyState.dead) return;
    var x = t.position.x - Flappy.scrollSpeed * speedFactor * dt;
    while (x <= -wrapWidth) {
      x += wrapWidth;
    }
    t.position = vm.Vector2(x, t.position.y);
  }
}

/// Slow cloud drift that wraps around the screen.
class FlappyCloud extends GameScript {
  @override
  void onUpdate(double dt) {
    final t = getComponent<Transform2DComponent>();
    if (t == null) return;
    var x = t.position.x - 14 * dt;
    if (x < -40) x = Flappy.worldW + 40;
    t.position = vm.Vector2(x, t.position.y);
  }
}

void registerFlappyScripts() {
  ScriptRegistry.register('Flappy Game', () => FlappyGame());
  ScriptRegistry.register('Flappy Bird', () => FlappyBird());
  ScriptRegistry.register('Flappy Pipe', () => FlappyPipe());
  ScriptRegistry.register('Flappy Ground Scroll', () => FlappyScroller(1.0, 32));
  ScriptRegistry.register('Flappy Hills Scroll', () => FlappyScroller(0.25, 144));
  ScriptRegistry.register('Flappy Cloud', () => FlappyCloud());
}

/// Builds the complete Flappy Arcade scene.
EmberScene buildFlappyScene() {
  final scene = EmberScene(name: 'MainScene');

  EmberEntity sprite(String name, vm.Vector2 pos, vm.Vector2 size, String image,
      {EmberAnchor anchor = EmberAnchor.topLeft, int z = 0}) {
    return EmberEntity(name: name)
      ..addComponent(Transform2DComponent(position: pos, size: size, anchor: anchor, zIndex: z))
      ..addComponent(FlameSpriteComponent(assetPath: '${Flappy.art}/$image'));
  }

  // Camera: fixed on the 288×512 play area, sky-blue background
  scene.addEntity(EmberEntity(name: 'Camera')
    ..addComponent(Transform2DComponent(position: vm.Vector2(Flappy.worldW / 2, Flappy.worldH / 2), size: vm.Vector2.zero()))
    ..addComponent(Camera2DComponent(
      designWidth: Flappy.worldW,
      designHeight: Flappy.worldH,
      backgroundColor: const Color(0xFF5BB8E6),
    )));

  // Clouds and hills (background)
  for (final (i, p) in [vm.Vector2(40, 90), vm.Vector2(170, 150), vm.Vector2(260, 60)].indexed) {
    scene.addEntity(sprite('Cloud_${i + 1}', p, vm.Vector2(64, 28), 'cloud.png', anchor: EmberAnchor.center, z: -3)
      ..addComponent(ScriptComponent(scriptName: 'Flappy Cloud')));
  }
  final hills = EmberEntity(name: 'Hills')
    ..addComponent(Transform2DComponent(position: vm.Vector2(0, Flappy.groundTop - 48), size: vm.Vector2.zero()))
    ..addComponent(ScriptComponent(scriptName: 'Flappy Hills Scroll'));
  for (var i = 0; i < 4; i++) {
    hills.addChild(sprite('HillTile_$i', vm.Vector2(i * 144.0, 0), vm.Vector2(144, 48), 'hills.png', z: -2));
  }
  scene.addEntity(hills);

  // Scrolling ground (drawn over the pipes)
  final ground = EmberEntity(name: 'Ground')
    ..addComponent(Transform2DComponent(position: vm.Vector2(0, Flappy.groundTop), size: vm.Vector2.zero()))
    ..addComponent(ScriptComponent(scriptName: 'Flappy Ground Scroll'));
  for (var i = 0; i < 11; i++) {
    ground.addChild(sprite('GroundTile_$i', vm.Vector2(i * 32.0, 0), vm.Vector2(32, 64), 'ground.png', z: 5));
  }
  scene.addEntity(ground);

  // The bird
  scene.addEntity(sprite('Bird', vm.Vector2(80, 240), vm.Vector2(34, 24), 'bird.png', anchor: EmberAnchor.center, z: 10)
    ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(24, 16), offset: vm.Vector2(5, 4), isSolid: false))
    ..addComponent(ScriptComponent(scriptName: 'Flappy Bird')));
  final birdSprite = scene.findByName('Bird')!.getComponent<FlameSpriteComponent>()!;
  birdSprite.columns = 3;

  // Game manager and on-screen text
  scene.addEntity(EmberEntity(name: 'Game')..addComponent(ScriptComponent(scriptName: 'Flappy Game')));
  scene.addEntity(EmberEntity(name: 'ScoreText')
    ..addComponent(UITextComponent(text: '0', fontSize: 44, anchor: EmberAnchor.topCenter, offset: vm.Vector2(0, 40))));
  scene.addEntity(EmberEntity(name: 'MessageText')
    ..addComponent(UITextComponent(
      text: 'GET READY\n\nClick, tap or press Space\nto flap',
      fontSize: 18,
      anchor: EmberAnchor.center,
      offset: vm.Vector2(0, -120), // above the bird's start position
    )));
  return scene;
}

import 'dart:ui' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/engine_loop.dart';
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/input.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/audio/audio_system.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/physics/character_controller2d.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/parallax.dart';
import '../subsystems/two_d/sprite_animator.dart';
import '../subsystems/ui/ui_text.dart';
import '../core/gameplay_scripts.dart' show PatrolWalker;

/// "Ember Quest": a Mario-style side-scrolling platformer built from engine
/// components plus the scripts in this file. Original art and music.
class Quest {
  static const String art = 'assets/templates/quest';
  static const String music = '$art/theme.wav';
  static const double tile = 32;
  static const int rows = 12;
  static const double levelHeight = rows * tile;
  static const List<String> levels = ['Level 1', 'Level 2'];

  // Tile IDs (cells of tiles.png)
  static const int grass = 1, dirt = 2, brick = 3, coinBlock = 4, usedBlock = 5, stone = 6;
  static const int plank = 7, spikes = 8, bush = 9, tuft = 10, flower = 11, powerBlock = 12;

  static const Map<int, TileKind> tileKinds = {
    brick: TileKind.breakable,
    coinBlock: TileKind.question,
    powerBlock: TileKind.question,
    usedBlock: TileKind.usedBlock,
    plank: TileKind.oneWay,
    spikes: TileKind.hazard,
    bush: TileKind.decoration,
    tuft: TileKind.decoration,
    flower: TileKind.decoration,
  };

  /// Every file the game loads (some only from scripts), for project export.
  static const List<String> assetFiles = [
    '$art/tiles.png', '$art/hero.png', '$art/hero_big.png', '$art/slime.png', '$art/coin.png',
    '$art/berry.png', '$art/flag.png', '$art/pole.png', '$art/bg_hills.png', '$art/bg_clouds.png', music,
  ];

  static bool get jumpHeld =>
      Input.isActionPressed(EngineAction.jump) || Input.isActionPressed(EngineAction.moveForward);
  static bool get jumpPressed =>
      Input.isActionJustPressed(EngineAction.jump) || Input.isActionJustPressed(EngineAction.moveForward);
}

/// Progress that survives restarts and level changes.
class QuestSession {
  static int lives = 3;
  static int score = 0;
  static int coins = 0;
  static bool big = false;

  static void reset() {
    lives = 3;
    score = 0;
    coins = 0;
    big = false;
  }

  static void addCoin() {
    coins++;
    score += 200;
    if (coins >= 100) {
      coins -= 100;
      lives++;
    }
  }
}

enum HeroState { playing, dead, cleared }

/// The player: run, jump, stomp, grow, get hurt, die, reach the flag.
class QuestHero extends GameScript {
  HeroState state = HeroState.playing;
  bool big = false;
  double invulnerable = 0;
  double _stateTime = 0;
  double _bannerTime = 0;
  double _time = 0;
  double _deadVelocity = 0;
  bool _gameOver = false;
  bool _won = false;
  String? _nextLevel;

  CharacterController2DComponent? get _cc => getComponent<CharacterController2DComponent>();
  Transform2DComponent? get _t => getComponent<Transform2DComponent>();

  String get worldLabel {
    final n = RegExp(r'\d+').firstMatch(scene?.name ?? '')?.group(0) ?? '1';
    return '1-$n';
  }

  @override
  void onStart() {
    _setBig(QuestSession.big, announce: false);
    AudioSystem.instance.playMusic(Quest.music, volume: 0.45);
    _banner('WORLD $worldLabel', seconds: 1.6);
    _updateHud();
  }

  @override
  void onUpdate(double dt) {
    final t = _t, cc = _cc;
    if (t == null || cc == null) return;
    _time += dt;
    _stateTime += dt;
    if (_bannerTime > 0) {
      _bannerTime -= dt;
      if (_bannerTime <= 0 && state == HeroState.playing) _banner('');
    }

    switch (state) {
      case HeroState.playing:
        _play(dt, t, cc);
      case HeroState.dead:
        // Classic death hop: no collisions, just up and off the screen
        _deadVelocity += 1500 * dt;
        t.position = vm.Vector2(t.position.x, t.position.y + _deadVelocity * dt);
        if (_stateTime > 2.4 && !_gameOver) _afterDeath();
        if (_gameOver && _stateTime > 3.0) _restartGame();
      case HeroState.cleared:
        cc.updateMovement(horizontalInput: 0, isJumpPressed: false, isJumpJustPressed: false, dt: dt);
        getComponent<SpriteAnimatorComponent>()?.play('idle');
        if (!_won && _stateTime > 2.5) {
          if (_nextLevel != null && EmberEngine.instance.loadLevel(_nextLevel!)) return;
          _won = true;
          _stateTime = 0;
          _banner('YOU WIN!\n\nScore ${QuestSession.score}\nThanks for playing');
        }
        if (_won && _stateTime > 5) _restartGame();
    }
    _updateHud();
  }

  void _play(double dt, Transform2DComponent t, CharacterController2DComponent cc) {
    final running = Input.isActionPressed(EngineAction.sprint);
    cc.moveSpeed = running ? 290 : 190;
    final wasGrounded = cc.isGrounded;
    cc.updateMovement(
      horizontalInput: Input.getAxis('horizontal'),
      isJumpPressed: Quest.jumpHeld,
      isJumpJustPressed: Quest.jumpPressed,
      dt: dt,
    );
    if (wasGrounded && !cc.isGrounded && cc.velocity.y < -100) {
      AudioSystem.instance.playProcedural('jump', volume: 0.5, pitch: big ? 0.9 : 1.15);
    }

    final sprite = getComponent<FlameSpriteComponent>();
    if (sprite != null) {
      sprite.flipX = cc.facing < 0;
      if (invulnerable > 0) {
        invulnerable -= dt;
        sprite.opacity = (_time * 20).floor().isOdd ? 0.25 : 1.0;
      } else {
        sprite.opacity = 1.0;
      }
    }
    getComponent<SpriteAnimatorComponent>()
        ?.play(!cc.isGrounded ? 'jump' : (cc.velocity.x.abs() > 20 ? 'run' : 'idle'));

    // Fell into a pit
    if (t.position.y > Quest.levelHeight + 64) die();
  }

  // --- Blocks, hazards, pickups, enemies ---

  @override
  void onHeadBump(TileHit tile) {
    if (state != HeroState.playing) return;
    switch (tile.kind) {
      case TileKind.question:
        tile.setTile(Quest.usedBlock);
        if (tile.tileId == Quest.powerBlock) {
          _spawnBerry(tile);
        } else {
          _spawnCoinPop(tile);
          QuestSession.addCoin();
          AudioSystem.instance.playProcedural('coin', volume: 0.7);
        }
      case TileKind.breakable:
        if (big) {
          tile.setTile(0);
          QuestSession.score += 50;
          _spawnDebris(tile);
          AudioSystem.instance.playProcedural('explosion', volume: 0.45, pitch: 1.5);
        } else {
          AudioSystem.instance.playProcedural('click', volume: 0.6, pitch: 0.6);
        }
      default:
        AudioSystem.instance.playProcedural('click', volume: 0.4, pitch: 0.5);
    }
  }

  @override
  void onTileTouch(TileHit tile) {
    if (tile.kind == TileKind.hazard) hurt();
  }

  @override
  void onTriggerEnter(EmberEntity other) {
    if (state != HeroState.playing) return;
    if (other.tags.contains('enemy')) {
      _touchEnemy(other);
    } else if (other.tags.contains('coin')) {
      destroy(other);
      QuestSession.addCoin();
      AudioSystem.instance.playProcedural('coin', volume: 0.6);
    } else if (other.tags.contains('powerup')) {
      destroy(other);
      QuestSession.score += 1000;
      _setBig(true);
    } else if (other.tags.contains('goal')) {
      _reachGoal(other);
    }
  }

  void _touchEnemy(EmberEntity enemy) {
    final walker = enemy.getComponent<ScriptComponent>()?.scriptInstance;
    if (walker is PatrolWalker && walker.squashed) return;
    final cc = _cc!, t = _t!;
    final et = enemy.getComponent<Transform2DComponent>();
    final enemyTop = et == null ? double.infinity : et.worldPosition.y - et.anchorOffset.y + 12;
    // Landing on top of it (falling, feet near its head) squashes it
    if (cc.velocity.y > 0 && t.worldPosition.y <= enemyTop + 14) {
      if (walker is PatrolWalker) walker.squash();
      cc.bounce(Quest.jumpHeld ? 560 : 380);
      QuestSession.score += 100;
    } else {
      hurt();
    }
  }

  void hurt() {
    if (state != HeroState.playing || invulnerable > 0) return;
    if (big) {
      _setBig(false);
      invulnerable = 2.0;
      AudioSystem.instance.playProcedural('hit', volume: 0.8, pitch: 0.8);
    } else {
      die();
    }
  }

  void die() {
    if (state != HeroState.playing) return;
    state = HeroState.dead;
    _stateTime = 0;
    _deadVelocity = -520;
    QuestSession.big = false;
    AudioSystem.instance.stopMusic();
    AudioSystem.instance.playProcedural('hit', volume: 1.0, pitch: 0.6);
    getComponent<FlameHitbox2DComponent>()?.enabled = false;
    getComponent<SpriteAnimatorComponent>()?.play('dead');
    getComponent<FlameSpriteComponent>()?.opacity = 1.0;
  }

  void _afterDeath() {
    QuestSession.lives--;
    if (QuestSession.lives > 0) {
      EmberEngine.instance.restartScene();
    } else {
      _gameOver = true;
      _stateTime = 0;
      _banner('GAME OVER');
    }
  }

  void _restartGame() {
    QuestSession.reset();
    if (!EmberEngine.instance.loadLevel(Quest.levels.first)) EmberEngine.instance.restartScene();
  }

  void _reachGoal(EmberEntity goal) {
    state = HeroState.cleared;
    _stateTime = 0;
    QuestSession.score += 1000;
    _nextLevel = goal.tags.where((t) => t.startsWith('next:')).map((t) => t.substring(5)).firstOrNull;
    AudioSystem.instance.stopMusic();
    AudioSystem.instance.playProcedural('coin', volume: 0.9, pitch: 0.8);
    _banner('LEVEL CLEAR!');
  }

  // --- Size ---

  void _setBig(bool value, {bool announce = true}) {
    big = value;
    QuestSession.big = value;
    final t = _t;
    t?.size = vm.Vector2(32, value ? 48 : 32);
    getComponent<FlameSpriteComponent>()?.assetPath = '${Quest.art}/${value ? 'hero_big.png' : 'hero.png'}';
    final hb = getComponent<FlameHitbox2DComponent>();
    if (hb != null) {
      hb.size = vm.Vector2(22, value ? 42 : 28);
      hb.offset = vm.Vector2(5, value ? 6 : 4);
    }
    if (announce && value) AudioSystem.instance.playProcedural('coin', volume: 0.8, pitch: 1.5);
  }

  // --- Spawned effects ---

  void _spawnCoinPop(TileHit tile) {
    spawn(EmberEntity(name: 'CoinPop')
      ..addComponent(Transform2DComponent(
        position: vm.Vector2(tile.rect.center.dx, tile.rect.top),
        size: vm.Vector2(24, 24),
        anchor: EmberAnchor.bottomCenter,
        zIndex: 4,
      ))
      ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/coin.png', columns: 4))
      ..addComponent(SpriteAnimatorComponent(clips: 'spin=0-3@16', defaultClip: 'spin'))
      ..addComponent(ScriptComponent(scriptName: 'Quest Coin Pop')));
  }

  void _spawnBerry(TileHit tile) {
    AudioSystem.instance.playProcedural('jump', volume: 0.6, pitch: 0.7);
    spawn(EmberEntity(name: 'Power Berry', tags: {'powerup'})
      ..addComponent(Transform2DComponent(
        position: vm.Vector2(tile.rect.center.dx, tile.rect.top - 1),
        size: vm.Vector2(28, 28),
        anchor: EmberAnchor.bottomCenter,
        zIndex: 3,
      ))
      ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/berry.png'))
      ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(24, 24), offset: vm.Vector2(2, 4), isSolid: false, debugDraw: false))
      ..addComponent(CharacterController2DComponent(moveSpeed: 80, gravity: 1500, groundY: 1e6))
      ..addComponent(ScriptComponent(scriptName: 'Quest Berry')));
  }

  void _spawnDebris(TileHit tile) {
    spawn(EmberEntity(name: 'Debris')
      ..addComponent(Transform2DComponent(position: vm.Vector2(tile.rect.center.dx, tile.rect.center.dy), size: vm.Vector2.zero()))
      ..addComponent(ParticleEmitter2DComponent(
        preset: ParticlePreset.sparkBurst,
        spawnRate: 0,
        startColor: const Color(0xFFC2410C),
        endColor: const Color(0xFF431407),
        startSize: 5,
        endSize: 2,
        speed: 140,
        gravity: 900,
      ))
      ..addComponent(ScriptComponent(scriptName: 'Quest Debris')));
  }

  // --- HUD ---

  void _banner(String text, {double seconds = 0}) {
    find('Banner')?.getComponent<UITextComponent>()?.text = text;
    _bannerTime = seconds;
  }

  void _updateHud() {
    final s = QuestSession.score.toString().padLeft(6, '0');
    final c = QuestSession.coins.toString().padLeft(2, '0');
    find('Hud')?.getComponent<UITextComponent>()?.text =
        'SCORE $s     COINS x$c     WORLD $worldLabel     LIVES x${QuestSession.lives}';
  }
}

/// A coin that pops out of a "?" block, rises and vanishes.
class QuestCoinPop extends GameScript {
  double _time = 0;
  @override
  void onUpdate(double dt) {
    _time += dt;
    final t = getComponent<Transform2DComponent>();
    if (t != null) t.position = vm.Vector2(t.position.x, t.position.y - 180 * dt * (1 - _time * 2).clamp(0.0, 1.0));
    if (_time > 0.45) destroy();
  }
}

/// Power-up that slides along the ground; touching it makes the hero big.
class QuestBerry extends GameScript {
  int direction = 1;
  @override
  void onUpdate(double dt) {
    final cc = getComponent<CharacterController2DComponent>();
    final t = getComponent<Transform2DComponent>();
    if (cc == null || t == null) return;
    cc.updateMovement(horizontalInput: direction.toDouble(), isJumpPressed: false, isJumpJustPressed: false, dt: dt);
    if (cc.hitWall) direction = -direction;
    if (t.position.y > Quest.levelHeight + 200) destroy();
  }
}

/// Brick fragments: one burst, then the helper entity removes itself.
class QuestDebris extends GameScript {
  double _time = 0;
  @override
  void onStart() => getComponent<ParticleEmitter2DComponent>()?.burst(14);
  @override
  void onUpdate(double dt) {
    _time += dt;
    if (_time > 1.2) destroy();
  }
}

void registerQuestScripts() {
  ScriptRegistry.register('Quest Hero', () => QuestHero());
  ScriptRegistry.register('Quest Coin Pop', () => QuestCoinPop());
  ScriptRegistry.register('Quest Berry', () => QuestBerry());
  ScriptRegistry.register('Quest Debris', () => QuestDebris());
}

// ---------------------------------------------------------------------------
// Levels

/// Small helper for laying out a level: tiles by column/row plus spawn points.
class QuestLevelBuilder {
  final String name;
  final int columns;
  final List<int> tiles;
  final List<(String, int, int, String?)> spawns = [];

  QuestLevelBuilder(this.name, this.columns) : tiles = List<int>.filled(columns * Quest.rows, 0);

  void set(int c, int r, int id) {
    if (c >= 0 && c < columns && r >= 0 && r < Quest.rows) tiles[r * columns + c] = id;
  }

  /// Grass on row 10, dirt on row 11 (the floor), for columns [from]..[to].
  void ground(int from, int to) {
    for (var c = from; c <= to; c++) {
      set(c, 10, Quest.grass);
      set(c, 11, Quest.dirt);
    }
  }

  /// A row of tiles from a pattern: B brick, ? coin block, P power block,
  /// S stone, = plank, ^ spikes, b bush, t tuft, f flower, space = skip.
  void row(int c0, int r, String pattern) {
    const ids = {
      'B': Quest.brick, '?': Quest.coinBlock, 'P': Quest.powerBlock, 'S': Quest.stone,
      '=': Quest.plank, '^': Quest.spikes, 'b': Quest.bush, 't': Quest.tuft, 'f': Quest.flower,
    };
    for (var i = 0; i < pattern.length; i++) {
      final id = ids[pattern[i]];
      if (id != null) set(c0 + i, r, id);
    }
  }

  /// Stone staircase rising to the right from column [c0], [height] steps.
  void stairs(int c0, int height) {
    for (var i = 0; i < height; i++) {
      for (var h = 0; h <= i; h++) {
        set(c0 + i, 9 - h, Quest.stone);
      }
    }
  }

  void coins(int c0, int c1, int r) {
    for (var c = c0; c <= c1; c++) {
      spawns.add(('coin', c, r, null));
    }
  }

  void enemy(int c, [int r = 9]) => spawns.add(('enemy', c, r, null));
  void hero(int c, [int r = 9]) => spawns.add(('hero', c, r, null));
  void goal(int c, {String? next}) => spawns.add(('goal', c, 9, next));

  EmberScene build() {
    final scene = EmberScene(name: name);
    final worldW = columns * Quest.tile;
    const worldH = Quest.levelHeight;
    vm.Vector2 feet(int c, int r) => vm.Vector2(c * Quest.tile + Quest.tile / 2, (r + 1) * Quest.tile);

    scene.addEntity(EmberEntity(name: 'Camera')
      ..addComponent(Transform2DComponent(position: vm.Vector2(320, worldH / 2), size: vm.Vector2.zero()))
      ..addComponent(Camera2DComponent(
        designWidth: 640,
        designHeight: worldH,
        followTarget: 'Hero',
        smoothing: 0.8,
        deadZone: vm.Vector2(40, 400),
        boundsEnabled: true,
        boundsMin: vm.Vector2.zero(),
        boundsMax: vm.Vector2(worldW, worldH),
        backgroundColor: const Color(0xFF6CB4EE),
      )));

    // Parallax background
    scene.addEntity(EmberEntity(name: 'Clouds')
      ..addComponent(Transform2DComponent(position: vm.Vector2(0, 20), size: vm.Vector2(384, 120), zIndex: -11))
      ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/bg_clouds.png'))
      ..addComponent(ParallaxLayerComponent(factorX: 0.15, factorY: 1.0)));
    scene.addEntity(EmberEntity(name: 'Hills')
      ..addComponent(Transform2DComponent(position: vm.Vector2(0, worldH - 64 - 160), size: vm.Vector2(480, 192), zIndex: -10))
      ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/bg_hills.png'))
      ..addComponent(ParallaxLayerComponent(factorX: 0.35, factorY: 1.0)));

    scene.addEntity(EmberEntity(name: 'Level')
      ..addComponent(Transform2DComponent(size: vm.Vector2.zero()))
      ..addComponent(FlameTileMapComponent(
        columns: columns,
        rows: Quest.rows,
        tileSize: Quest.tile,
        tiles: List<int>.from(tiles),
        tilesetPath: '${Quest.art}/tiles.png',
        tilesetColumns: 8,
        tilesetTileSize: 16,
        tileKinds: Map.of(Quest.tileKinds),
      )));

    var coinIndex = 0, enemyIndex = 0;
    for (final (kind, c, r, extra) in spawns) {
      switch (kind) {
        case 'coin':
          scene.addEntity(EmberEntity(name: 'Coin_${++coinIndex}', tags: {'coin'})
            ..addComponent(Transform2DComponent(position: feet(c, r) - vm.Vector2(0, 4), size: vm.Vector2(24, 24), anchor: EmberAnchor.bottomCenter, zIndex: 2))
            ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/coin.png', columns: 4))
            ..addComponent(SpriteAnimatorComponent(clips: 'spin=0-3@8', defaultClip: 'spin'))
            ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(18, 20), offset: vm.Vector2(3, 2), isSolid: false, debugDraw: false)));
        case 'enemy':
          scene.addEntity(EmberEntity(name: 'Slime_${++enemyIndex}', tags: {'enemy'})
            ..addComponent(Transform2DComponent(position: feet(c, r), size: vm.Vector2(32, 32), anchor: EmberAnchor.bottomCenter, zIndex: 3))
            ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/slime.png', columns: 3))
            ..addComponent(SpriteAnimatorComponent(clips: 'walk=0-1@4; squashed=2', defaultClip: 'walk'))
            ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(26, 18), offset: vm.Vector2(3, 13), isSolid: false))
            ..addComponent(CharacterController2DComponent(moveSpeed: 50, gravity: 1500, groundY: 1e6))
            ..addComponent(ScriptComponent(scriptName: 'Patrol Walker')));
        case 'goal':
          final pole = EmberEntity(name: 'Goal', tags: {'goal', if (extra != null) 'next:$extra'})
            ..addComponent(Transform2DComponent(position: feet(c, r), size: vm.Vector2(8, 256), anchor: EmberAnchor.bottomCenter, zIndex: 1))
            ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/pole.png'))
            ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(20, 256), offset: vm.Vector2(-6, 0), isSolid: false));
          pole.addChild(EmberEntity(name: 'Flag')
            ..addComponent(Transform2DComponent(position: vm.Vector2(4, -252), size: vm.Vector2(40, 40), zIndex: 1))
            ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/flag.png')));
          scene.addEntity(pole);
        case 'hero':
          scene.addEntity(EmberEntity(name: 'Hero', tags: {'player'})
            ..addComponent(Transform2DComponent(position: feet(c, r), size: vm.Vector2(32, 32), anchor: EmberAnchor.bottomCenter, zIndex: 5))
            ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/hero.png', columns: 6))
            ..addComponent(SpriteAnimatorComponent(clips: 'idle=0; run=1-3@12; jump=4; dead=5', defaultClip: 'idle'))
            ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(22, 28), offset: vm.Vector2(5, 4), isSolid: false))
            ..addComponent(CharacterController2DComponent(moveSpeed: 190, jumpVelocity: 560, gravity: 1500, groundY: 1e6))
            ..addComponent(ScriptComponent(scriptName: 'Quest Hero')));
      }
    }

    // HUD
    scene.addEntity(EmberEntity(name: 'Hud')
      ..addComponent(UITextComponent(text: '', fontSize: 15, anchor: EmberAnchor.topLeft, offset: vm.Vector2(14, 10))));
    scene.addEntity(EmberEntity(name: 'Banner')
      ..addComponent(UITextComponent(text: '', fontSize: 30, anchor: EmberAnchor.center, offset: vm.Vector2(0, -40))));
    return scene;
  }
}

/// World 1-1: blocks, a power berry, first slimes, two small pits, a staircase and the flag.
EmberScene buildQuestLevel1() {
  final l = QuestLevelBuilder('Level 1', 110);
  l.ground(0, 44);
  l.ground(47, 76);
  l.ground(79, 109);
  for (final (c, p) in [(5, 'b'), (12, 't'), (17, 'f'), (22, 'bb'), (30, 't'), (50, 'f'), (55, 'b'), (65, 't'), (88, 'bb'), (104, 'f')]) {
    l.row(c, 9, p);
  }

  l.hero(2);
  l.row(10, 6, '?');
  l.row(14, 6, 'BPB?B');
  l.row(16, 3, '?');
  l.enemy(20);

  l.stairs(24, 2);
  l.row(30, 7, '======');
  l.coins(31, 34, 6);
  l.enemy(38);

  l.coins(44, 47, 7); // over the first pit
  l.enemy(52);
  l.enemy(56);
  l.row(58, 6, 'B?B');
  l.row(66, 9, '^^');
  l.enemy(74); // not right where you land after the spikes

  l.coins(76, 79, 7); // over the second pit
  l.enemy(85);
  l.row(90, 6, '?B?');
  l.enemy(92);

  l.stairs(96, 5);
  l.goal(105, next: 'Level 2');
  return l.build();
}

/// World 1-2: wider pits, plank bridges, spike patches, a brick tunnel and more slimes.
EmberScene buildQuestLevel2() {
  final l = QuestLevelBuilder('Level 2', 124);
  l.ground(0, 20);
  l.ground(24, 34);
  l.ground(39, 60);
  l.ground(64, 90);
  l.ground(95, 123);
  for (final (c, p) in [(4, 'b'), (9, 'f'), (26, 't'), (42, 'bb'), (66, 'f'), (82, 't'), (98, 'b'), (118, 'f')]) {
    l.row(c, 9, p);
  }

  l.hero(2);
  l.row(8, 6, '?P?');
  l.enemy(14);
  l.enemy(18);

  l.coins(21, 23, 7); // pit 21-23
  l.row(28, 9, '^^');
  l.enemy(26); // before the spikes, walking towards the player

  l.row(35, 8, '===='); // plank bridge over pit 35-38
  l.coins(35, 38, 7);

  l.row(44, 6, 'B?BB?B');
  l.row(46, 3, '??');
  l.enemy(47);
  l.row(52, 9, '^^^');

  l.row(61, 7, '==='); // pit 61-63 with a plank to hop on
  l.row(68, 7, '======');
  l.row(72, 4, '=====');
  l.coins(73, 76, 3);
  l.enemy(70, 6); // patrols the plank
  l.enemy(78);
  l.row(80, 9, '^^');
  l.enemy(86);

  l.row(92, 8, 'S'); // stepping stones over pit 91-94
  l.row(94, 7, 'S');
  l.enemy(100);
  l.enemy(104);
  l.row(101, 6, 'B?B');

  l.stairs(110, 5);
  l.goal(119); // no next level: this is the finale
  return l.build();
}

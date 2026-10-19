import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/ai/monster_ai.dart';
import '../subsystems/combat/combat.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/two_d/bullet_pool.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/light2d.dart';
import '../subsystems/two_d/top_down_controller.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "Ember Depths": a roguelike dungeon crawler. Every floor is generated from
/// the run's seed (rooms, corridors, auto-tiled walls), lit only by torches
/// and the hero's light. Monsters hunt with Monster AI; chests hold relics
/// that change how the hero fights; death ends the run. Logic: [depthsScripts].
class Depths {
  static const String art = 'assets/templates/depths';
  static const String title = 'Title';
  static const String dungeon = 'Dungeon';
  static const int columns = 56, rows = 36;
  static const double tile = 32;

  static const List<String> assetFiles = [
    '$art/tiles.png', '$art/hero.png', '$art/monsters.png', '$art/props.png', '$art/items.png', '$art/shots.png', '$art/arrow.png',
    '$art/icons.png', '$art/panel.png',
    '$art/depths.wav', '$art/cast.wav', '$art/hit.wav', '$art/hurt.wav', '$art/chest.wav', '$art/coin.wav', '$art/stairs.wav',
    '$art/dash.wav', '$art/die.wav',
  ];

  static const Color ink = Color(0xFFF5F3FF);
  static const Color ember = Color(0xFFF97316);
  static const Color dim = Color(0xFFC4B5FD);
}

EmberEntity _sprite(String name, vm.Vector2 pos, vm.Vector2 size, String image,
    {int z = 0, int columns = 1, int frame = 0, bool additive = false, bool enabled = true}) {
  return EmberEntity(name: name, enabled: enabled)
    ..addComponent(Transform2DComponent(position: pos, size: size, anchor: EmberAnchor.center, zIndex: z))
    ..addComponent(FlameSpriteComponent(assetPath: '${Depths.art}/$image', smooth: true, additive: additive)
      ..columns = columns
      ..frame = frame);
}

/// A hitbox of [w] × [h] at the bottom middle of a [size] box (feet).
FlameHitbox2DComponent _feet(vm.Vector2 size, double w, double h) =>
    FlameHitbox2DComponent(size: vm.Vector2(w, h), offset: vm.Vector2((size.x - w) / 2, size.y - h - 2), isSolid: false);

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset,
        {Color color = Depths.ink, bool glow = false, double spacing = 0, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color, outline: true, glow: glow, letterSpacing: spacing));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size,
        {EmberAnchor anchor = EmberAnchor.center, String hotkey = '', Color color = Depths.ember, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UIButtonComponent(text: text, action: action, hotkey: hotkey, anchor: anchor, offset: offset, size: size, color: color, style: 'outline', fontSize: 14));

EmberEntity _emitter(String name, Color start, Color end, {double size = 4, double speed = 120, double life = 0.6}) => EmberEntity(name: name)
  ..addComponent(Transform2DComponent(position: vm.Vector2(-5000, -5000), size: vm.Vector2.zero(), zIndex: 9))
  ..addComponent(ParticleEmitter2DComponent(
    spawnRate: 0, // bursts only
    maxParticles: 300,
    particleLifetime: life,
    startColor: start,
    endColor: end,
    startSize: size,
    endSize: 0.5,
    speed: speed,
    gravity: 0,
    glow: true,
  ));

/// The tilemap the dungeon is generated into (walls solid, floors walkable).
EmberEntity _dungeonMap({bool withScript = true}) {
  final map = FlameTileMapComponent(
    columns: Depths.columns,
    rows: Depths.rows,
    tileSize: Depths.tile,
    tilesetPath: '${Depths.art}/tiles.png',
    tilesetColumns: 8,
    tilesetTileSize: 64,
    tileKinds: {for (final id in [2, 3, 4, 5]) id: TileKind.decoration},
    smooth: true,
  );
  final e = EmberEntity(name: 'Dungeon')
    ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2(Depths.columns * Depths.tile, Depths.rows * Depths.tile), zIndex: -10))
    ..addComponent(map);
  if (withScript) e.addComponent(ScriptComponent(scriptName: 'depths_game.ember'));
  return e;
}

EmberEntity _camera({String follow = ''}) => EmberEntity(name: 'Camera')
  ..addComponent(Transform2DComponent(position: vm.Vector2(480, 270), size: vm.Vector2.zero()))
  ..addComponent(Camera2DComponent(
    designWidth: 960,
    designHeight: 540,
    followTarget: follow,
    smoothing: 0.85,
    boundsEnabled: true,
    boundsMin: vm.Vector2.zero(),
    boundsMax: vm.Vector2(Depths.columns * Depths.tile, Depths.rows * Depths.tile),
    backgroundColor: const Color(0xFF07050C),
    vignette: 0.35,
    darkness: 0.88,
    darknessColor: const Color(0xFF07050C),
  ));

EmberEntity _torch() => _sprite('Torch', vm.Vector2(-900, -900), vm.Vector2(30, 30), 'props.png', columns: 4, frame: 3, z: 2, enabled: false)
  ..tags.add('torch')
  ..addComponent(Light2DComponent(radius: 150, color: const Color(0xFFFFB061), flicker: 1, intensity: 0.95));

EmberEntity _monster(String kind, int frame, double size, MonsterAIComponent ai, {double hp = 3, double speed = 70}) {
  final dims = vm.Vector2(size, size);
  return _sprite(kind, vm.Vector2(-900, -900), dims, 'monsters.png', columns: 4, frame: frame, z: 4, enabled: false)
    ..tags.add('enemy')
    ..addComponent(_feet(dims, size * 0.55, size * 0.4))
    ..addComponent(TopDownController2DComponent(moveSpeed: speed))
    ..addComponent(HealthComponent(maxHealth: hp, team: 'monster', invulnerableTime: 0.08, hitFlash: 'white', showBar: true))
    ..addComponent(ai)
    ..addComponent(ScriptComponent(scriptName: 'depths_monster.ember', vars: {'kind': kind}));
}

EmberEntity _pickup(String name, String kind, int frame, double size, {bool glow = false}) =>
    _sprite(name, vm.Vector2(-900, -900), vm.Vector2(size, size), 'items.png', columns: 8, frame: frame, z: 3, enabled: false, additive: glow)
      ..addComponent(ScriptComponent(scriptName: 'depths_pickup.ember', vars: {'kind': kind}));

/// A floor of the dungeon (generated when it starts) with everything it needs.
EmberScene buildDepthsDungeon() {
  final scene = EmberScene(name: Depths.dungeon);
  scene.addEntity(_camera(follow: 'Hero'));
  scene.addEntity(_dungeonMap());

  final heroSize = vm.Vector2(40, 40);
  scene.addEntity(_sprite('Hero', vm.Vector2(200, 200), heroSize, 'hero.png', z: 5)
    ..tags.add('player')
    ..addComponent(_feet(heroSize, 18, 14))
    ..addComponent(TopDownController2DComponent(moveSpeed: 150))
    ..addComponent(HealthComponent(maxHealth: 4, team: 'player', invulnerableTime: 1.0, destroyOnDeath: false, hitFlash: 'white'))
    ..addComponent(Light2DComponent(radius: 220, color: const Color(0xFFFFC27A), flicker: 0.25))
    ..addComponent(ScriptComponent(scriptName: 'depths_hero.ember')));
  scene.addEntity(EmberEntity(name: 'Bolts')
    ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero(), zIndex: 7))
    ..addComponent(BulletPool2DComponent(image: '${Depths.art}/shots.png', columns: 3, size: 26, team: 'player', damage: 1, margin: 60, maxBullets: 400)
      ..hitWalls = true));

  const arrow = '${Depths.art}/arrow.png';
  scene
    ..addEntity(_monster('Slime', 0, 36, MonsterAIComponent(sightRange: 190, attackRange: 18, touchDamage: 1, attackDamage: 1, wanderRadius: 60, xpReward: 2),
        hp: 3, speed: 70))
    ..addEntity(_monster('Bat', 2, 34, MonsterAIComponent(sightRange: 230, attackRange: 16, touchDamage: 1, attackDamage: 1, wanderRadius: 90, windup: 0.1),
        hp: 2, speed: 125))
    ..addEntity(_monster('Archer', 1, 40,
        MonsterAIComponent(sightRange: 260, attackRange: 190, touchDamage: 0, attackDamage: 1, ranged: true, projectileSpeed: 210, projectileAsset: arrow, attackCooldown: 1.6, windup: 0.4),
        hp: 3, speed: 55))
    ..addEntity(_monster('Warden', 3, 64,
        MonsterAIComponent(sightRange: 260, attackRange: 26, touchDamage: 1, attackDamage: 2, attackCooldown: 1.2, windup: 0.5, knockbackPower: 320),
        hp: 30, speed: 60));

  scene
    ..addEntity(_sprite('Chest', vm.Vector2(-900, -900), vm.Vector2(40, 40), 'props.png', columns: 4, frame: 0, z: 3, enabled: false)
      ..addComponent(ScriptComponent(scriptName: 'depths_chest.ember')))
    ..addEntity(_sprite('Stairs', vm.Vector2(-900, -900), vm.Vector2(46, 46), 'props.png', columns: 4, frame: 2, z: -5, enabled: false)
      ..addComponent(Light2DComponent(radius: 110, color: Depths.ember, intensity: 0.8, flicker: 0.4))
      ..addComponent(ScriptComponent(scriptName: 'depths_stairs.ember')))
    ..addEntity(_torch())
    ..addEntity(_pickup('Coin', 'coin', 1, 16))
    ..addEntity(_pickup('Heart', 'heart', 0, 18))
    ..addEntity(_pickup('Relic', 'power', 2, 26, glow: true))
    ..addEntity(_emitter('Pop FX', const Color(0xFFFFD08A), const Color(0x00F97316), size: 5, speed: 120))
    ..addEntity(_emitter('Dash FX', const Color(0xFF93C5FD), const Color(0x003B82F6), size: 6, speed: 20, life: 0.35));

  // HUD
  scene
    ..addEntity(EmberEntity(name: 'Hearts')
      ..addComponent(UIImageComponent(assetPath: '${Depths.art}/icons.png', columns: 4, frame: 0, emptyFrame: 2, count: 4, filled: 4, spacing: 2,
          anchor: EmberAnchor.topLeft, offset: vm.Vector2(14, 12), size: vm.Vector2(28, 28))
        ..smooth = true))
    ..addEntity(EmberEntity(name: 'GoldIcon')
      ..addComponent(UIImageComponent(assetPath: '${Depths.art}/icons.png', columns: 4, frame: 1, anchor: EmberAnchor.topLeft, offset: vm.Vector2(14, 46), size: vm.Vector2(22, 22))
        ..smooth = true))
    ..addEntity(_text('GoldText', '0', 18, EmberAnchor.topLeft, vm.Vector2(42, 46), color: const Color(0xFFFDE68A)))
    ..addEntity(EmberEntity(name: 'FloorIcon')
      ..addComponent(UIImageComponent(assetPath: '${Depths.art}/icons.png', columns: 4, frame: 3, anchor: EmberAnchor.topRight, offset: vm.Vector2(-112, 12), size: vm.Vector2(26, 26))
        ..smooth = true))
    ..addEntity(_text('FloorText', 'Floor 1', 20, EmberAnchor.topRight, vm.Vector2(-16, 14)))
    ..addEntity(_text('SeedText', '', 11, EmberAnchor.topRight, vm.Vector2(-16, 42), color: Depths.dim))
    ..addEntity(_text('RelicsText', '', 12, EmberAnchor.bottomLeft, vm.Vector2(14, -12), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('Banner', '', 36, EmberAnchor.topCenter, vm.Vector2(0, 70), color: const Color(0xFFFED7AA), glow: true, spacing: 5))
    ..addEntity(_text('Subtitle', '', 15, EmberAnchor.topCenter, vm.Vector2(0, 116), color: Depths.dim));

  // Results
  scene
    ..addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Depths.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(480, 290))
        ..smooth = true))
    ..addEntity(_text('ResultsTitle', '', 28, EmberAnchor.center, vm.Vector2(0, -90), color: const Color(0xFFFED7AA), glow: true, spacing: 3, enabled: false))
    ..addEntity(_text('ResultsLine', '', 16, EmberAnchor.center, vm.Vector2(0, -38), enabled: false))
    ..addEntity(_text('ResultsStats', '', 13, EmberAnchor.center, vm.Vector2(0, -6), color: Depths.dim, enabled: false))
    ..addEntity(_button('RetryButton', 'NEW RUN', 'retry', vm.Vector2(-150, 76), vm.Vector2(130, 40), hotkey: 'Enter', enabled: false))
    ..addEntity(_button('SameSeedButton', 'SAME SEED', 'same', vm.Vector2(0, 76), vm.Vector2(130, 40), enabled: false, color: Depths.dim))
    ..addEntity(_button('MenuButton', 'MENU', 'menu', vm.Vector2(150, 76), vm.Vector2(130, 40), enabled: false, color: Depths.dim));
  return scene;
}

EmberScene buildDepthsTitle() {
  final scene = EmberScene(name: Depths.title);
  scene.addEntity(_camera()..getComponent<Camera2DComponent>()!.darkness = 0.75);
  scene.addEntity(_dungeonMap(withScript: false));
  scene.addEntity(_torch());
  scene.addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'depths_title.ember')));
  scene
    ..addEntity(_text('Logo', 'EMBER DEPTHS', 64, EmberAnchor.center, vm.Vector2(0, -110), color: const Color(0xFFFED7AA), glow: true, spacing: 10))
    ..addEntity(_text('Tagline', 'Every floor is new. Every death is final. How deep can you go?', 16, EmberAnchor.center, vm.Vector2(0, -50)))
    ..addEntity(_button('StartButton', 'NEW RUN', 'start', vm.Vector2(-100, 20), vm.Vector2(180, 48), hotkey: 'Enter'))
    ..addEntity(_button('DailyButton', 'DAILY DUNGEON', 'daily', vm.Vector2(100, 20), vm.Vector2(180, 48), color: Depths.dim))
    ..addEntity(_text('BestText', '', 15, EmberAnchor.center, vm.Vector2(0, 74), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('Controls', 'WASD move  ·  mouse or arrow keys aim and cast  ·  Shift dash', 13, EmberAnchor.bottomCenter, vm.Vector2(0, -18),
        color: Depths.dim));
  return scene;
}

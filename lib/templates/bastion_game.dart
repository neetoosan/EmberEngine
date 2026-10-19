import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/combat/combat.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/two_d/bullet_pool.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/line2d.dart';
import '../subsystems/two_d/path_follower.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';
import 'bastion_layout.dart';

/// "Ember Bastion": a tower-defense game. Enemies march along a road (Path
/// Follower 2D); build Archer, Cannon, Frost and Tesla towers on a grid,
/// upgrade and sell them, survive 15 waves. The logic is Ember Script
/// ([bastionScripts]).
class Bastion {
  static const String art = 'assets/templates/bastion';
  static const String title = 'Title';
  static const String battle = 'Battle';
  static const List<String> towers = ['Archer', 'Cannon', 'Frost', 'Tesla'];

  static const List<String> assetFiles = [
    '$art/map.png', '$art/decor.png', '$art/keep.png', '$art/bases.png', '$art/tops.png', '$art/enemies.png', '$art/shots.png',
    '$art/icons.png', '$art/range.png', '$art/cell.png', '$art/ring.png', '$art/panel.png',
    '$art/bastion.wav', '$art/arrow.wav', '$art/cannon.wav', '$art/frost.wav', '$art/zap.wav', '$art/build.wav', '$art/coin.wav',
    '$art/leak.wav', '$art/horn.wav', '$art/victory.wav',
  ];

  static const Color gold = Color(0xFFFBBF24);
  static const Color ink = Color(0xFFFFFBEB);
  static const Color dim = Color(0xFFD9F99D);
}

EmberEntity _sprite(String name, vm.Vector2 pos, vm.Vector2 size, String image,
    {int z = 0, int columns = 1, int rows = 1, int frame = 0, bool additive = false, bool enabled = true, Color? tint}) {
  return EmberEntity(name: name, enabled: enabled)
    ..addComponent(Transform2DComponent(position: pos, size: size, anchor: EmberAnchor.center, zIndex: z))
    ..addComponent(FlameSpriteComponent(assetPath: '${Bastion.art}/$image', smooth: true, additive: additive, tint: tint ?? const Color(0xFFFFFFFF))
      ..columns = columns
      ..rows = rows
      ..frame = frame);
}

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset,
        {Color color = Bastion.ink, bool glow = false, double spacing = 0, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color, outline: true, glow: glow, letterSpacing: spacing));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size,
    {EmberAnchor anchor = EmberAnchor.center, String hotkey = '', Color color = Bastion.gold, bool enabled = true, int? iconFrame}) {
  final b = UIButtonComponent(text: text, action: action, hotkey: hotkey, anchor: anchor, offset: offset, size: size, color: color, style: 'outline', fontSize: 14);
  if (iconFrame != null) {
    b
      ..icon = '${Bastion.art}/tops.png'
      ..iconColumns = 3
      ..iconRows = 4
      ..iconFrame = iconFrame;
  }
  return EmberEntity(name: name, enabled: enabled)..addComponent(b);
}

EmberEntity _icon(String name, int frame, EmberAnchor anchor, vm.Vector2 offset, double size) => EmberEntity(name: name)
  ..addComponent(UIImageComponent(assetPath: '${Bastion.art}/icons.png', columns: 5, frame: frame, anchor: anchor, offset: offset, size: vm.Vector2(size, size))
    ..smooth = true);

EmberEntity _emitter(String name, Color start, Color end, {double size = 4, double speed = 120, double gravity = 0, double life = 0.6}) =>
    EmberEntity(name: name)
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
        gravity: gravity,
        glow: true,
      ));

EmberEntity _camera() => EmberEntity(name: 'Camera')
  ..addComponent(Transform2DComponent(position: vm.Vector2(480, 270), size: vm.Vector2.zero()))
  ..addComponent(Camera2DComponent(designWidth: 960, designHeight: 540, backgroundColor: const Color(0xFF3F7F3C), vignette: 0.25));

/// The map: grass and road, the road's path, trees and rocks, the keep.
void _addMap(EmberScene scene) {
  scene.addEntity(_camera());
  scene.addEntity(_sprite('Map', vm.Vector2(480, 270), vm.Vector2(960, 540), 'map.png', z: -20));
  scene.addEntity(EmberEntity(name: 'Path')
    ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero()))
    ..addComponent(Line2DComponent(points: [for (final (x, y) in BastionLayout.path) vm.Vector2(x, y)], width: 0, color: const Color(0x55FFFFFF))));
  for (final (x, y, kind) in BastionLayout.decor) {
    scene.addEntity(_sprite('Decor', vm.Vector2(x, y), vm.Vector2(50, 50), 'decor.png', columns: 4, frame: kind, z: (y / 40).round())
      ..tags.add('blocked'));
  }
  final (kx, ky) = BastionLayout.path.last;
  scene.addEntity(_sprite('Keep', vm.Vector2(kx - 82, ky - 22), vm.Vector2(116, 116), 'keep.png', z: 12));
}

EmberEntity _tower(String type) {
  final t = Bastion.towers.indexOf(type);
  return _sprite('$type Tower', vm.Vector2(-900, -900), vm.Vector2(48, 48), 'bases.png', columns: 3, rows: 4, frame: t * 3, z: 5, enabled: false)
    ..tags.add('tower')
    ..addChild(_sprite('Top', vm.Vector2.zero(), vm.Vector2(48, 48), 'tops.png', columns: 3, rows: 4, frame: t * 3, z: 6))
    ..addComponent(ScriptComponent(scriptName: 'bastion_tower.ember', vars: {'type': type}));
}

EmberEntity _enemy(String kind, int frame, double size, Map<String, Object?> stats) {
  final dims = vm.Vector2(size, size);
  return _sprite(kind, vm.Vector2(-900, -900), dims, 'enemies.png', columns: 5, frame: frame, z: 4, enabled: false)
    ..tags.add('enemy')
    ..addComponent(FlameHitbox2DComponent(size: dims * 0.6, offset: dims * 0.2, isSolid: false))
    ..addComponent(HealthComponent(maxHealth: 30, team: 'monster', invulnerableTime: 0, hitFlash: 'white', showBar: true))
    ..addComponent(PathFollower2DComponent(path: 'Path', speed: 55, rotate: true))
    ..addComponent(ScriptComponent(scriptName: 'bastion_enemy.ember', vars: {'kind': kind, ...stats}));
}

/// The battle: map, towers and enemies (templates), effects, HUD and results.
EmberScene buildBastionBattle() {
  final scene = EmberScene(name: Bastion.battle);
  _addMap(scene);

  // What the player is placing, and a range circle
  final ghost = _sprite('Ghost', vm.Vector2(-900, -900), vm.Vector2(48, 48), 'bases.png', columns: 3, rows: 4, z: 14, enabled: false)
    ..addChild(_sprite('Top', vm.Vector2.zero(), vm.Vector2(48, 48), 'tops.png', columns: 3, rows: 4, z: 15));
  ghost.getComponent<FlameSpriteComponent>()!.opacity = 0.85;
  scene.addEntity(ghost);
  scene.addEntity(_sprite('Range', vm.Vector2(-900, -900), vm.Vector2(128, 128), 'range.png', z: 13, enabled: false));
  scene.addEntity(_sprite('Cell', vm.Vector2(-900, -900), vm.Vector2(40, 40), 'cell.png', z: 13, enabled: false));

  for (final t in Bastion.towers) {
    scene.addEntity(_tower(t));
  }
  scene
    ..addEntity(_enemy('Grunt', 0, 36, {'hp': 30, 'speed': 55, 'reward': 5, 'leak': 1, 'armor': 0}))
    ..addEntity(_enemy('Runner', 1, 42, {'hp': 20, 'speed': 100, 'reward': 6, 'leak': 1, 'armor': 0}))
    ..addEntity(_enemy('Golem', 2, 52, {'hp': 140, 'speed': 34, 'reward': 15, 'leak': 3, 'armor': 4}))
    ..addEntity(_enemy('Wisp', 3, 34, {'hp': 22, 'speed': 80, 'reward': 5, 'leak': 1, 'armor': 0}))
    ..addEntity(_enemy('Knight', 4, 60, {'hp': 700, 'speed': 30, 'reward': 80, 'leak': 10, 'armor': 6}));

  // Shots and effects
  scene.addEntity(EmberEntity(name: 'Shots')
    ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero(), zIndex: 8))
    ..addComponent(BulletPool2DComponent(image: '${Bastion.art}/shots.png', columns: 4, size: 24, team: 'player', additive: false, margin: 30, maxBullets: 500))
    ..addComponent(ScriptComponent(scriptName: 'bastion_shots.ember')));
  scene
    ..addEntity(_sprite('Frost Ring', vm.Vector2(-900, -900), vm.Vector2(128, 128), 'ring.png', z: 7, additive: true, enabled: false, tint: const Color(0xFF7DD3FC)))
    ..addEntity(_sprite('Blast Ring', vm.Vector2(-900, -900), vm.Vector2(128, 128), 'ring.png', z: 9, additive: true, enabled: false, tint: const Color(0xFFFDBA74)))
    ..addEntity(EmberEntity(name: 'Bolt', enabled: false)
      ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero(), zIndex: 10))
      ..addComponent(Line2DComponent(color: const Color(0xFFE9D5FF), width: 2.5, glow: true)))
    ..addEntity(_emitter('Dust FX', const Color(0xFFF5E6C8), const Color(0x00B08A55), size: 6, speed: 70, life: 0.5))
    ..addEntity(_emitter('Coin FX', const Color(0xFFFDE68A), const Color(0x00F59E0B), size: 4, speed: 60, gravity: -60))
    ..addEntity(_emitter('Pop FX', const Color(0xFFFFFFFF), const Color(0x0086EFAC), size: 4, speed: 140))
    ..addEntity(_emitter('Boom FX', const Color(0xFFFFD08A), const Color(0x00EF4444), size: 7, speed: 110))
    ..addEntity(_emitter('Spark FX', const Color(0xFFFFFFFF), const Color(0x00A78BFA), size: 3, speed: 160, life: 0.35));

  scene.addEntity(EmberEntity(name: 'Game')..addComponent(ScriptComponent(scriptName: 'bastion_game.ember')));

  // HUD: gold, lives and wave on the left; speed and menu on the right
  scene
    ..addEntity(_icon('GoldIcon', 0, EmberAnchor.topLeft, vm.Vector2(14, 10), 28))
    ..addEntity(_text('GoldText', '0', 22, EmberAnchor.topLeft, vm.Vector2(48, 11), color: const Color(0xFFFDE68A)))
    ..addEntity(_icon('LivesIcon', 1, EmberAnchor.topLeft, vm.Vector2(118, 10), 28))
    ..addEntity(_text('LivesText', '20', 22, EmberAnchor.topLeft, vm.Vector2(152, 11), color: const Color(0xFFFECDD3)))
    ..addEntity(_icon('WaveIcon', 2, EmberAnchor.topLeft, vm.Vector2(212, 10), 28))
    ..addEntity(_text('WaveText', 'Wave 0 / 15', 20, EmberAnchor.topLeft, vm.Vector2(244, 13)))
    ..addEntity(_button('SpeedButton', 'x1', 'speed', vm.Vector2(-104, 10), vm.Vector2(54, 30), anchor: EmberAnchor.topRight, hotkey: 'F'))
    ..addEntity(_button('MenuHud', 'Menu', 'menu', vm.Vector2(-14, 10), vm.Vector2(80, 30), anchor: EmberAnchor.topRight, color: Bastion.dim))
    ..addEntity(_text('Banner', '', 36, EmberAnchor.topCenter, vm.Vector2(0, 54), color: const Color(0xFFFDE68A), glow: true, spacing: 4))
    ..addEntity(_text('Subtitle', '', 15, EmberAnchor.topCenter, vm.Vector2(0, 100)));

  // Build bar
  for (var i = 0; i < Bastion.towers.length; i++) {
    final t = Bastion.towers[i];
    scene.addEntity(_button('${t}Button', t, 'build:$t', vm.Vector2(14.0 + i * 152, -12), vm.Vector2(144, 46),
        anchor: EmberAnchor.bottomLeft, iconFrame: i * 3));
  }
  scene
    ..addEntity(_button('StartButton', 'START WAVE 1', 'start', vm.Vector2(-14, -12), vm.Vector2(190, 46), anchor: EmberAnchor.bottomRight,
        color: const Color(0xFF4ADE80)))
    ..addEntity(_button('UpgradeButton', 'UPGRADE', 'upgrade', vm.Vector2.zero(), vm.Vector2(140, 30), anchor: EmberAnchor.topLeft,
        color: const Color(0xFF4ADE80), enabled: false))
    ..addEntity(_button('SellButton', 'SELL', 'sell', vm.Vector2.zero(), vm.Vector2(140, 30), anchor: EmberAnchor.topLeft,
        color: const Color(0xFFFCA5A5), enabled: false));

  // Results
  scene
    ..addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Bastion.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(440, 270))
        ..smooth = true))
    ..addEntity(_text('ResultsTitle', '', 30, EmberAnchor.center, vm.Vector2(0, -86), color: const Color(0xFFFDE68A), glow: true, spacing: 3, enabled: false))
    ..addEntity(EmberEntity(name: 'ResultsStars', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Bastion.art}/icons.png', columns: 5, frame: 3, emptyFrame: 4, count: 3, filled: 0, spacing: 10,
          anchor: EmberAnchor.center, offset: vm.Vector2(-64, -30), size: vm.Vector2(44, 44))
        ..smooth = true))
    ..addEntity(_text('ResultsLine', '', 15, EmberAnchor.center, vm.Vector2(0, 30), enabled: false))
    ..addEntity(_button('RetryButton', 'PLAY AGAIN', 'retry', vm.Vector2(-80, 86), vm.Vector2(140, 40), hotkey: 'Enter', enabled: false))
    ..addEntity(_button('MenuButton', 'MENU', 'menu', vm.Vector2(80, 86), vm.Vector2(140, 40), enabled: false, color: Bastion.dim));
  return scene;
}

EmberScene buildBastionTitle() {
  final scene = EmberScene(name: Bastion.title);
  _addMap(scene);
  // A few towers standing guard
  for (final (x, y, t, level) in [(260.0, 230.0, 0, 2), (620.0, 260.0, 1, 1), (300.0, 420.0, 2, 0), (740.0, 470.0, 3, 2)]) {
    scene.addEntity(_sprite('Decor Tower', vm.Vector2(x, y), vm.Vector2(48, 48), 'bases.png', columns: 3, rows: 4, frame: t * 3 + level, z: 5)
      ..addChild(_sprite('Top', vm.Vector2.zero(), vm.Vector2(48, 48), 'tops.png', columns: 3, rows: 4, frame: t * 3 + level, z: 6)));
  }
  scene.addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'bastion_title.ember')));
  EmberEntity stars(String name, vm.Vector2 offset) => EmberEntity(name: name)
    ..addComponent(UIImageComponent(assetPath: '${Bastion.art}/icons.png', columns: 5, frame: 3, emptyFrame: 4, count: 3, filled: 0, spacing: 4,
        anchor: EmberAnchor.center, offset: offset, size: vm.Vector2(24, 24))
      ..smooth = true);
  scene
    ..addEntity(EmberEntity(name: 'TitlePanel')
      ..addComponent(UIImageComponent(assetPath: '${Bastion.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2(0, -10), size: vm.Vector2(520, 320))
        ..smooth = true))
    ..addEntity(_text('Logo', 'EMBER BASTION', 54, EmberAnchor.center, vm.Vector2(0, -112), color: const Color(0xFFFDE68A), glow: true, spacing: 6))
    ..addEntity(_text('Tagline', 'Build towers. Hold the road. Save the keep.', 16, EmberAnchor.center, vm.Vector2(0, -60)))
    ..addEntity(_button('NormalButton', 'NORMAL', 'normal', vm.Vector2(-90, 10), vm.Vector2(150, 46), hotkey: 'Enter', color: const Color(0xFF4ADE80)))
    ..addEntity(_button('HardButton', 'HARD', 'hard', vm.Vector2(90, 10), vm.Vector2(150, 46), color: const Color(0xFFF87171)))
    ..addEntity(stars('NormalStars', vm.Vector2(-130, 52)))
    ..addEntity(stars('HardStars', vm.Vector2(50, 52)))
    ..addEntity(_text('Controls', 'Click a tower below, then the grass  ·  1-4 pick  ·  Space starts a wave  ·  F speed  ·  Shift keeps building', 12,
        EmberAnchor.center, vm.Vector2(0, 100), color: Bastion.dim));
  return scene;
}

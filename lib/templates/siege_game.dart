import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/physics/rigid_body2d.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/line2d.dart';
import '../subsystems/two_d/parallax.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "Ember Siege": an Angry Birds-style physics game. Fling embers from a
/// slingshot to topple frost castles and defeat the imps inside. Built on
/// Rigid Body 2D (forge2d/Box2D); gameplay is Ember Script ([siegeScripts]).
class Siege {
  static const String art = 'assets/templates/siege';
  static const String music = '$art/siege.wav';
  static const double groundTop = 608;
  static const double slingX = 220;

  static const String title = 'Title';
  static const List<String> levels = ['Level 1', 'Level 2', 'Level 3'];

  static const List<String> assetFiles = [
    '$art/wood_post.png', '$art/wood_beam.png', '$art/wood_long.png', '$art/wood_block.png',
    '$art/ice_post.png', '$art/ice_beam.png', '$art/ice_long.png', '$art/ice_block.png',
    '$art/stone_post.png', '$art/stone_beam.png', '$art/stone_long.png', '$art/stone_block.png',
    '$art/imp.png', '$art/ember.png', '$art/coal.png', '$art/spark.png', '$art/keg.png', '$art/slingshot.png',
    '$art/sky.png', '$art/stars.png', '$art/mountains.png', '$art/pines.png', '$art/tiles.png',
    '$art/star.png', '$art/shots.png', '$art/panel.png', music,
  ];

  /// Block shapes (world pixels).
  static const Map<String, (double, double)> shapes = {
    'post': (20, 96),
    'beam': (96, 20),
    'long': (144, 20),
    'block': (40, 40),
  };

  /// Per material: density, friction, health, points.
  static const Map<String, (double, double, double, int)> materials = {
    'wood': (0.7, 0.6, 380, 100),
    'ice': (0.5, 0.15, 140, 80),
    'stone': (2.2, 0.8, 1100, 150),
  };
}

EmberEntity _sprite(String name, vm.Vector2 pos, vm.Vector2 size, String image,
    {EmberAnchor anchor = EmberAnchor.topLeft, int z = 0, int columns = 1}) {
  return EmberEntity(name: name)
    ..addComponent(Transform2DComponent(position: pos, size: size, anchor: anchor, zIndex: z))
    ..addComponent(FlameSpriteComponent(assetPath: '${Siege.art}/$image')..columns = columns);
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

/// Builds castles from the ground up: every piece is given by its centre x
/// and the y of its bottom edge.
class _Castle {
  final EmberScene scene;
  _Castle(this.scene);

  EmberEntity piece(String shape, String material, double x, double bottom) {
    final (w, h) = Siege.shapes[shape]!;
    final (density, friction, health, points) = Siege.materials[material]!;
    final e = _sprite('${_cap(material)} ${_cap(shape)}', vm.Vector2(x, bottom - h / 2), vm.Vector2(w, h), '${material}_$shape.png',
        anchor: EmberAnchor.center, z: 3, columns: 3)
      ..tags.addAll({'block', 'breakable'})
      ..addComponent(RigidBody2DComponent(density: density, friction: friction, restitution: 0.05, startAsleep: true, hitSpeed: 40))
      ..addComponent(ScriptComponent(scriptName: 'siege_block.ember', vars: {'material': material, 'health': health, 'points': points}));
    scene.addEntity(e);
    return e;
  }

  void post(String m, double x, double bottom) => piece('post', m, x, bottom);
  void beam(String m, double x, double bottom) => piece('beam', m, x, bottom);
  void long(String m, double x, double bottom) => piece('long', m, x, bottom);
  void block(String m, double x, double bottom) => piece('block', m, x, bottom);

  /// Imp health for this castle (tougher imps in later levels).
  double impHealth = 220;

  void imp(double x, double bottom) {
    scene.addEntity(_sprite('Imp', vm.Vector2(x, bottom - 18), vm.Vector2(36, 36), 'imp.png', anchor: EmberAnchor.center, z: 4, columns: 3)
      ..tags.addAll({'imp', 'breakable'})
      ..addComponent(RigidBody2DComponent(
          shape: BodyShape2D.circle, density: 0.8, friction: 0.6, restitution: 0.2, angularDamping: 3, startAsleep: true, hitSpeed: 40))
      ..addComponent(ScriptComponent(scriptName: 'siege_imp.ember', vars: {'health': impHealth})));
  }

  void keg(double x, double bottom) {
    scene.addEntity(_sprite('Powder Keg', vm.Vector2(x, bottom - 22), vm.Vector2(36, 44), 'keg.png', anchor: EmberAnchor.center, z: 3)
      ..tags.addAll({'keg', 'breakable'})
      ..addComponent(RigidBody2DComponent(density: 0.6, friction: 0.6, restitution: 0.05, startAsleep: true, hitSpeed: 40))
      ..addComponent(ScriptComponent(scriptName: 'siege_keg.ember')));
  }
}

/// Sky, stars, mountains, pines and the painted ground (a tilemap the
/// rigid bodies collide with).
void _addBackdrop(EmberScene scene) {
  scene.addEntity(_sprite('Sky', vm.Vector2(-600, -760), vm.Vector2(3400, 1440), 'sky.png', z: -10));
  scene.addEntity(_sprite('Stars', vm.Vector2(0, -260), vm.Vector2(640, 240), 'stars.png', z: -9)
    ..addComponent(ParallaxLayerComponent(factorX: 0.1, factorY: 1)));
  scene.addEntity(_sprite('Mountains', vm.Vector2(0, Siege.groundTop - 172), vm.Vector2(640, 180), 'mountains.png', z: -8)
    ..addComponent(ParallaxLayerComponent(factorX: 0.3, factorY: 1)));
  scene.addEntity(_sprite('Pines', vm.Vector2(0, Siege.groundTop - 60), vm.Vector2(256, 64), 'pines.png', z: -7)
    ..addComponent(ParallaxLayerComponent(factorX: 0.6, factorY: 1)));

  const cols = 76, rows = 27, firstRow = 19; // 32 px cells from x = -320; ground surface at row 19 (y = 608)
  final tiles = List<int>.filled(cols * rows, 0);
  for (var c = 0; c < cols; c++) {
    tiles[firstRow * cols + c] = 1;
    for (var r = firstRow + 1; r < rows; r++) {
      tiles[r * cols + c] = r < firstRow + 3 ? 2 : 3;
    }
  }
  scene.addEntity(EmberEntity(name: 'Ground')
    ..addComponent(Transform2DComponent(position: vm.Vector2(-320, 0), size: vm.Vector2.zero(), zIndex: -1))
    ..addComponent(FlameTileMapComponent(
      columns: cols,
      rows: rows,
      tileSize: 32,
      tiles: tiles,
      tilesetPath: '${Siege.art}/tiles.png',
      tilesetColumns: 4,
      tilesetTileSize: 16,
    )));
}

EmberEntity _camera({required double zoom, required double centerX}) {
  final viewH = 540 / zoom;
  return EmberEntity(name: 'Camera')
    ..addComponent(Transform2DComponent(position: vm.Vector2(centerX, Siege.groundTop + 70 - viewH / 2), size: vm.Vector2.zero()))
    ..addComponent(Camera2DComponent(designWidth: 960, designHeight: 540, zoom: zoom, backgroundColor: const Color(0xFF0B1026)));
}

/// A disabled shot "prefab" (spawned by the level script).
EmberEntity _shotTemplate(String kind) {
  final (size, density, bounce) = switch (kind) {
    'coal' => (28.0, 9.0, 0.1),
    'spark' => (22.0, 2.4, 0.35),
    _ => (28.0, 3.0, 0.3),
  };
  final trail = switch (kind) {
    'coal' => ParticleEmitter2DComponent(preset: ParticlePreset.smokeTrail, spawnRate: 18, maxParticles: 30)
      ..applyPreset(ParticlePreset.smokeTrail),
    'spark' => ParticleEmitter2DComponent(
        spawnRate: 30, maxParticles: 30, startColor: const Color(0xFFFEF08A), endColor: const Color(0xFFF97316), speed: 25, startSize: 4, particleLifetime: 0.5),
    _ => ParticleEmitter2DComponent(spawnRate: 30, maxParticles: 40, speed: 25, startSize: 5, particleLifetime: 0.6),
  };
  return _sprite('${_cap(kind)} Template', vm.Vector2(-5000, -5000), vm.Vector2(size, size), '$kind.png',
      anchor: EmberAnchor.center, z: 5, columns: 2)
    ..enabled = false
    ..tags.add('shot')
    ..addComponent(RigidBody2DComponent(
        shape: BodyShape2D.circle, density: density, restitution: bounce, friction: 0.6, angularDamping: 0.6, bullet: true, hitSpeed: 40)
      ..enabled = false) // switched on at launch
    ..addComponent(trail)
    ..addComponent(ScriptComponent(scriptName: 'siege_shot.ember', vars: {'kind': kind}));
}

EmberEntity _emitter(String name, Color start, Color end, {double size = 5, double speed = 120, double gravity = 500}) {
  return EmberEntity(name: name)
    ..addComponent(Transform2DComponent(position: vm.Vector2(-5000, -5000), size: vm.Vector2.zero(), zIndex: 8))
    ..addComponent(ParticleEmitter2DComponent(
      spawnRate: 0,
      maxParticles: 160,
      particleLifetime: 0.9,
      startColor: start,
      endColor: end,
      startSize: size,
      endSize: 1,
      speed: speed,
      gravity: gravity,
    ));
}

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset, {Color color = const Color(0xFFFFFFFF)}) =>
    EmberEntity(name: name)..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size,
        {EmberAnchor anchor = EmberAnchor.center, String hotkey = '', Color color = const Color(0xFFF59E0B), bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UIButtonComponent(
        text: text,
        action: action,
        hotkey: hotkey,
        anchor: anchor,
        offset: offset,
        size: size,
        color: color,
        // Light text on dark buttons, dark text on bright ones
        textColor: color.computeLuminance() < 0.3 ? const Color(0xFFF1F5F9) : const Color(0xFF1B1420),
      ));

/// Everything a level needs besides its castle.
EmberScene _levelScene(String name, {required String ammo, required String levelTitle, required String nextLevel, double zoom = 0.75}) {
  final scene = EmberScene(name: name);
  scene.addEntity(_camera(zoom: zoom, centerX: 480 / zoom));
  scene.addEntity(EmberEntity(name: 'Physics')..addComponent(PhysicsWorld2DComponent(gravity: vm.Vector2(0, 900))));
  _addBackdrop(scene);

  // Slingshot with its two rubber bands (back band behind the shot, front band over it)
  scene.addEntity(_sprite('Slingshot', vm.Vector2(Siege.slingX, Siege.groundTop + 4), vm.Vector2(48, 120), 'slingshot.png',
      anchor: EmberAnchor.bottomCenter, z: 2)
    ..addComponent(ScriptComponent(scriptName: 'siege_slingshot.ember')));
  EmberEntity band(String bandName, int z) => EmberEntity(name: bandName)
    ..addComponent(Transform2DComponent(position: vm.Vector2(Siege.slingX, Siege.groundTop - 104), size: vm.Vector2.zero(), zIndex: z))
    ..addComponent(Line2DComponent(color: const Color(0xFF4A2A14), width: 5));
  scene.addEntity(band('BandBack', 1));
  scene.addEntity(band('BandFront', 6));
  scene.addEntity(EmberEntity(name: 'Trajectory')
    ..addComponent(Transform2DComponent(position: vm.Vector2(Siege.slingX, Siege.groundTop - 104), size: vm.Vector2.zero(), zIndex: 7))
    ..addComponent(Line2DComponent(color: const Color(0xDDFFFFFF), width: 3.5, style: LineStyle2D.dots, taper: true)));

  // Prefabs and effects
  for (final kind in ['ember', 'coal', 'spark']) {
    scene.addEntity(_shotTemplate(kind));
  }
  scene.addEntity(_emitter('Wood Debris', const Color(0xFFA0662F), const Color(0xFF5B3A1E)));
  scene.addEntity(_emitter('Ice Debris', const Color(0xFFE8FAFF), const Color(0xFF7DD3FC), size: 4));
  scene.addEntity(_emitter('Stone Debris', const Color(0xFFB4B9C1), const Color(0xFF52565E), size: 6));
  scene.addEntity(_emitter('Puff', const Color(0xFFF8FAFC), const Color(0xFF93C5FD), size: 7, speed: 90, gravity: -60));
  scene.addEntity(_emitter('Blast', const Color(0xFFFDE68A), const Color(0xFFDC2626), size: 9, speed: 220, gravity: 100));

  // Level flow
  scene.addEntity(EmberEntity(name: 'Siege')
    ..addComponent(ScriptComponent(
        scriptName: 'siege_level.ember', vars: {'ammo': ammo, 'levelTitle': levelTitle, 'nextLevel': nextLevel})));

  // HUD
  scene.addEntity(_button('RetryHud', 'Retry', 'restart', vm.Vector2(16, 14), vm.Vector2(84, 32), anchor: EmberAnchor.topLeft, color: const Color(0xFF334155)));
  scene.addEntity(_button('MenuHud', 'Menu', 'level:${Siege.title}', vm.Vector2(108, 14), vm.Vector2(84, 32),
      anchor: EmberAnchor.topLeft, color: const Color(0xFF334155)));
  scene.addEntity(EmberEntity(name: 'ShotsHud')
    ..addComponent(UIImageComponent(
        assetPath: '${Siege.art}/shots.png', columns: 2, frame: 0, emptyFrame: 1, count: 3, spacing: 6,
        anchor: EmberAnchor.topLeft, offset: vm.Vector2(20, 58), size: vm.Vector2(24, 24))));
  scene.addEntity(_text('LevelText', name, 18, EmberAnchor.topCenter, vm.Vector2(0, 18)));
  scene.addEntity(_text('ScoreText', 'Score 0', 22, EmberAnchor.topRight, vm.Vector2(-20, 14)));
  scene.addEntity(_text('BestText', 'Best 0', 14, EmberAnchor.topRight, vm.Vector2(-20, 44), color: const Color(0xFFCBD5E1)));
  scene.addEntity(_text('HintText', 'Drag the shot back and let go  ·  tap again in flight for its power', 14, EmberAnchor.bottomCenter,
      vm.Vector2(0, -16), color: const Color(0xFFE2E8F0)));

  // Results (shown by the level script)
  scene.addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
    ..addComponent(UIImageComponent(assetPath: '${Siege.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(400, 260))));
  scene.addEntity(_text('ResultsTitle', '', 30, EmberAnchor.center, vm.Vector2(0, -88), color: const Color(0xFFFDE68A))..enabled = false);
  scene.addEntity(EmberEntity(name: 'ResultsStars', enabled: false)
    ..addComponent(UIImageComponent(
        assetPath: '${Siege.art}/star.png', columns: 2, frame: 0, emptyFrame: 1, count: 3, filled: 0, spacing: 12,
        anchor: EmberAnchor.center, offset: vm.Vector2(-60, -24), size: vm.Vector2(48, 48))));
  scene.addEntity(_text('ResultsScore', '', 16, EmberAnchor.center, vm.Vector2(0, 30))..enabled = false);
  scene.addEntity(_button('RetryButton', 'Retry', 'restart', vm.Vector2(-128, 86), vm.Vector2(112, 40), enabled: false, color: const Color(0xFF94A3B8)));
  scene.addEntity(_button('MenuButton', 'Menu', 'level:${Siege.title}', vm.Vector2(0, 86), vm.Vector2(112, 40), enabled: false, color: const Color(0xFF94A3B8)));
  scene.addEntity(_button('NextButton', 'Next', 'level:$nextLevel', vm.Vector2(128, 86), vm.Vector2(112, 40), hotkey: 'Enter', enabled: false));
  return scene;
}

/// Level 1 "Frostgate": two wooden towers and an imp hiding behind ice.
EmberScene buildSiegeLevel1() {
  final scene = _levelScene('Level 1', ammo: 'ember,ember,ember', levelTitle: 'Frostgate', nextLevel: 'Level 2');
  final c = _Castle(scene);
  const g = Siege.groundTop;
  // Tower A
  c.post('wood', 862, g);
  c.post('wood', 938, g);
  c.beam('wood', 900, g - 96);
  c.imp(900, g - 116);
  // Imp behind an ice block
  c.block('ice', 990, g);
  c.imp(1032, g);
  // Tower B, two floors
  c.post('wood', 1092, g);
  c.post('wood', 1168, g);
  c.beam('wood', 1130, g - 96);
  c.post('ice', 1092, g - 116);
  c.post('ice', 1168, g - 116);
  c.beam('ice', 1130, g - 212);
  c.imp(1130, g - 232);
  return scene;
}

/// Level 2 "Ice Keep": two ice-and-wood halls on a stone footing, a tower on top.
EmberScene buildSiegeLevel2() {
  final scene = _levelScene('Level 2', ammo: 'ember,coal,ember', levelTitle: 'Ice Keep', nextLevel: 'Level 3');
  final c = _Castle(scene);
  const g = Siege.groundTop;
  for (var i = 0; i < 8; i++) {
    c.block('stone', 900 + i * 40.0, g);
  }
  const f = g - 40; // top of the stone footing
  // Hall A (ice)
  c.post('ice', 898, f);
  c.post('ice', 1022, f);
  c.long('ice', 960, f - 96);
  c.imp(960, f);
  // Hall B (wood)
  c.post('wood', 1058, f);
  c.post('wood', 1182, f);
  c.long('wood', 1120, f - 96);
  c.imp(1120, f);
  // Tower across both halls
  c.post('ice', 1002, f - 116);
  c.post('ice', 1078, f - 116);
  c.beam('ice', 1040, f - 212);
  c.imp(1040, f - 232);
  return scene;
}

/// Level 3 "Stone Citadel": a stone keep with powder kegs, a side tower.
EmberScene buildSiegeLevel3() {
  final scene = _levelScene('Level 3', ammo: 'spark,coal,ember,ember', levelTitle: 'Stone Citadel', nextLevel: '', zoom: 0.68);
  final c = _Castle(scene)..impHealth = 380; // helmeted citadel guards
  const g = Siege.groundTop;
  // Outer wall
  c.post('stone', 842, g);
  c.post('stone', 918, g);
  c.beam('stone', 880, g - 96);
  c.block('wood', 880, g - 116);
  // Keep: stone ground floor with a keg and an imp
  c.post('stone', 1018, g);
  c.post('stone', 1142, g);
  c.keg(1060, g);
  c.imp(1106, g);
  c.long('stone', 1080, g - 96);
  // Wooden upper floor with an imp, ice cap with an imp on top
  c.post('wood', 1018, g - 116);
  c.post('wood', 1142, g - 116);
  c.imp(1080, g - 116);
  c.long('wood', 1080, g - 212);
  c.block('ice', 1080, g - 232);
  c.imp(1080, g - 272);
  // Keg between the keep and the side tower
  c.keg(1197, g);
  // Side tower
  c.post('wood', 1252, g);
  c.post('wood', 1328, g);
  c.beam('ice', 1290, g - 96);
  c.imp(1290, g - 116);
  return scene;
}

/// Title screen with level select and saved stars.
EmberScene buildSiegeTitle() {
  final scene = EmberScene(name: Siege.title);
  scene.addEntity(_camera(zoom: 0.75, centerX: 640));
  _addBackdrop(scene);
  // A little castle and the slingshot for decoration (no physics)
  scene.addEntity(_sprite('Slingshot', vm.Vector2(Siege.slingX, Siege.groundTop + 4), vm.Vector2(48, 120), 'slingshot.png',
      anchor: EmberAnchor.bottomCenter, z: 2));
  scene.addEntity(_sprite('Ember', vm.Vector2(Siege.slingX, Siege.groundTop - 104), vm.Vector2(28, 28), 'ember.png',
      anchor: EmberAnchor.center, z: 5, columns: 2));
  for (final (x, image, w, h) in [(1030.0, 'stone_post.png', 20.0, 96.0), (1110.0, 'stone_post.png', 20.0, 96.0)]) {
    scene.addEntity(_sprite('Deco Post', vm.Vector2(x, Siege.groundTop - h / 2), vm.Vector2(w, h), image, anchor: EmberAnchor.center, z: 3, columns: 3));
  }
  scene.addEntity(_sprite('Deco Beam', vm.Vector2(1070, Siege.groundTop - 106), vm.Vector2(96, 20), 'ice_beam.png', anchor: EmberAnchor.center, z: 3, columns: 3));
  scene.addEntity(_sprite('Deco Imp', vm.Vector2(1070, Siege.groundTop - 134), vm.Vector2(36, 36), 'imp.png', anchor: EmberAnchor.center, z: 4, columns: 3));

  scene.addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'siege_title.ember')));
  scene.addEntity(_text('Logo', 'EMBER SIEGE', 58, EmberAnchor.topCenter, vm.Vector2(0, 54), color: const Color(0xFFFDBA4A)));
  scene.addEntity(_text('Tagline', 'Fling embers. Topple frost castles. Melt every imp.', 16, EmberAnchor.topCenter, vm.Vector2(0, 128),
      color: const Color(0xFFE2E8F0)));
  for (var i = 1; i <= Siege.levels.length; i++) {
    final x = (i - 2) * 120.0;
    scene.addEntity(_button('Level$i Button', '$i', 'level:Level $i', vm.Vector2(x, 10), vm.Vector2(96, 64), hotkey: i == 1 ? 'Enter' : ''));
    scene.addEntity(EmberEntity(name: 'Level$i Stars')
      ..addComponent(UIImageComponent(
          assetPath: '${Siege.art}/star.png', columns: 2, frame: 0, emptyFrame: 1, count: 3, filled: 0, spacing: 4,
          anchor: EmberAnchor.center, offset: vm.Vector2(x - 26, 64), size: vm.Vector2(24, 24))));
  }
  scene.addEntity(_button('ResetButton', 'Reset progress', 'reset', vm.Vector2(0, -16), vm.Vector2(150, 30),
      anchor: EmberAnchor.bottomCenter, color: const Color(0xFF334155)));
  return scene;
}

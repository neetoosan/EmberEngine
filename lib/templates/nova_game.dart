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
import '../subsystems/two_d/parallax.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "Ember Nova": a neon side-scrolling shooter. Waves of drones, darts,
/// turrets, spinners and cruisers, then a three-phase boss; power-ups,
/// bombs, shields, grazing and a score multiplier; loops get harder.
/// Thousands of bullets come from two Bullet Pool 2D entities; the game
/// logic is Ember Script ([novaScripts]).
class Nova {
  static const String art = 'assets/templates/nova';
  static const String title = 'Title';
  static const String stage = 'Stage';

  static const List<String> assetFiles = [
    '$art/ship.png', '$art/thruster.png', '$art/enemies.png', '$art/cruiser.png', '$art/boss.png', '$art/boss_core.png',
    '$art/bullets.png', '$art/pickups.png', '$art/icons.png', '$art/ring.png', '$art/flare.png', '$art/panel.png',
    '$art/bg_space.png', '$art/bg_nebula.png', '$art/bg_stars_far.png', '$art/bg_stars_near.png', '$art/bg_planet.png',
    '$art/nova.wav', '$art/nova_boss.wav', '$art/shot.wav', '$art/boom.wav', '$art/bigboom.wav', '$art/power.wav',
    '$art/hurt.wav', '$art/bomb.wav',
  ];

  static const Color cyan = Color(0xFF22D3EE);
  static const Color ink = Color(0xFFE0F2FE);
  static const Color dim = Color(0xFF93C5FD);
}

EmberEntity _sprite(String name, vm.Vector2 pos, vm.Vector2 size, String image,
    {EmberAnchor anchor = EmberAnchor.center, int z = 0, int columns = 1, int frame = 0, bool additive = false, bool enabled = true}) {
  return EmberEntity(name: name, enabled: enabled)
    ..addComponent(Transform2DComponent(position: pos, size: size, anchor: anchor, zIndex: z))
    ..addComponent(FlameSpriteComponent(assetPath: '${Nova.art}/$image', smooth: true, additive: additive)
      ..columns = columns
      ..frame = frame);
}

/// A hitbox of [w] × [h] centred on an entity of [size].
FlameHitbox2DComponent _hitbox(vm.Vector2 size, double w, double h) =>
    FlameHitbox2DComponent(size: vm.Vector2(w, h), offset: vm.Vector2((size.x - w) / 2, (size.y - h) / 2), isSolid: false);

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset,
        {Color color = Nova.ink, bool glow = false, double spacing = 0, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color, outline: false, glow: glow, letterSpacing: spacing));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size,
        {EmberAnchor anchor = EmberAnchor.center, String hotkey = '', Color color = Nova.cyan, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UIButtonComponent(
          text: text, action: action, hotkey: hotkey, anchor: anchor, offset: offset, size: size, color: color, style: 'outline', fontSize: 15));

EmberEntity _emitter(String name, Color start, Color end, {double size = 5, double speed = 160, double life = 0.7, int max = 400}) =>
    EmberEntity(name: name)
      ..addComponent(Transform2DComponent(position: vm.Vector2(-5000, -5000), size: vm.Vector2.zero(), zIndex: 9))
      ..addComponent(ParticleEmitter2DComponent(
        spawnRate: 0, // bursts only (scripts call particles.burst(count, where))
        maxParticles: max,
        particleLifetime: life,
        startColor: start,
        endColor: end,
        startSize: size,
        endSize: 0.5,
        speed: speed,
        gravity: 0,
        glow: true,
      ));

EmberEntity _camera() => EmberEntity(name: 'Camera')
  ..addComponent(Transform2DComponent(position: vm.Vector2(480, 270), size: vm.Vector2.zero()))
  ..addComponent(Camera2DComponent(designWidth: 960, designHeight: 540, backgroundColor: const Color(0xFF060816), vignette: 0.45));

/// Space, a planet and three layers of stars and cloud scrolling at different speeds.
void _addSpace(EmberScene scene) {
  scene.addEntity(_camera());
  EmberEntity layer(String name, String image, vm.Vector2 pos, vm.Vector2 size, int z, double scroll, {bool repeat = true}) =>
      _sprite(name, pos, size, image, anchor: EmberAnchor.topLeft, z: z)
        ..addComponent(ParallaxLayerComponent(factorX: 1, factorY: 1, repeatX: repeat, scrollX: scroll));
  scene
    ..addEntity(_sprite('Space', vm.Vector2.zero(), vm.Vector2(960, 540), 'bg_space.png', anchor: EmberAnchor.topLeft, z: -30))
    ..addEntity(layer('Planet', 'bg_planet.png', vm.Vector2(560, -40), vm.Vector2(340, 340), -26, -5, repeat: false))
    ..addEntity(layer('Far Stars', 'bg_stars_far.png', vm.Vector2.zero(), vm.Vector2(960, 540), -24, -30))
    ..addEntity(layer('Nebula', 'bg_nebula.png', vm.Vector2.zero(), vm.Vector2(1280, 540), -22, -55))
    ..addEntity(layer('Near Stars', 'bg_stars_near.png', vm.Vector2.zero(), vm.Vector2(960, 540), -20, -150));
}

EmberEntity _ship(String name, vm.Vector2 pos) {
  final size = vm.Vector2(72, 48);
  final ship = _sprite(name, pos, size, 'ship.png', z: 5);
  ship.addChild(_sprite('Thruster', vm.Vector2(-30, 0), vm.Vector2(52, 26), 'thruster.png', anchor: EmberAnchor.centerRight, z: 4, columns: 2, additive: true));
  return ship;
}

EmberEntity _enemy(String kind, int frame, double size, double hp, int points, int crystals, double speed, {String image = 'enemies.png', vm.Vector2? box}) {
  final dims = box ?? vm.Vector2(size, size);
  return _sprite(kind, vm.Vector2(-900, -900), dims, image, z: 3, columns: image == 'enemies.png' ? 4 : 1, frame: frame, enabled: false)
    ..tags.add('enemy')
    ..addComponent(_hitbox(dims, dims.x * 0.7, dims.y * 0.62))
    ..addComponent(HealthComponent(maxHealth: hp, team: 'monster', invulnerableTime: 0, hitFlash: 'white'))
    ..addComponent(ScriptComponent(scriptName: 'nova_enemy.ember', vars: {'kind': kind, 'points': points, 'crystals': crystals, 'speed': speed}));
}

EmberEntity _pickup(String name, String kind, int frame, double size) =>
    _sprite(name, vm.Vector2(-900, -900), vm.Vector2(size, size), 'pickups.png', z: 6, columns: 4, frame: frame, enabled: false)
      ..addComponent(ScriptComponent(scriptName: 'nova_pickup.ember', vars: {'kind': kind}));

/// The stage: ship, bullet pools, enemy and pickup templates, effects, HUD.
EmberScene buildNovaStage() {
  final scene = EmberScene(name: Nova.stage);
  _addSpace(scene);

  // The ship: only the small core in the middle can be hit
  final ship = _ship('Ship', vm.Vector2(150, 270))
    ..tags.add('player')
    ..addComponent(_hitbox(vm.Vector2(72, 48), 8, 8))
    ..addComponent(HealthComponent(maxHealth: 100000, team: 'player', invulnerableTime: 0, destroyOnDeath: false, hitFlash: 'none'))
    ..addComponent(ScriptComponent(scriptName: 'nova_player.ember'));
  ship.addChild(_sprite('Core', vm.Vector2.zero(), vm.Vector2(22, 22), 'flare.png', z: 7, additive: true, enabled: false));
  ship.addChild(_sprite('Shield', vm.Vector2.zero(), vm.Vector2(96, 96), 'ring.png', z: 6, additive: true));
  scene.addEntity(ship);

  // Bullets: one pool for the ship, one for every enemy
  scene.addEntity(EmberEntity(name: 'Player Shots')
    ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero(), zIndex: 4))
    ..addComponent(BulletPool2DComponent(image: '${Nova.art}/bullets.png', columns: 8, size: 44, team: 'player', damage: 1, maxBullets: 600)));
  scene.addEntity(EmberEntity(name: 'Enemy Shots')
    ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero(), zIndex: 8))
    ..addComponent(BulletPool2DComponent(image: '${Nova.art}/bullets.png', columns: 8, size: 30, team: 'monster', damage: 1, grazeRadius: 16, maxBullets: 3000)));

  // Enemy templates (copied by the stage script)
  scene
    ..addEntity(_enemy('Drone', 0, 56, 3, 100, 1, 175))
    ..addEntity(_enemy('Dart', 1, 58, 2, 150, 1, 260))
    ..addEntity(_enemy('Turret', 2, 66, 16, 400, 3, 120))
    ..addEntity(_enemy('Spinner', 3, 72, 12, 350, 3, 120))
    ..addEntity(_enemy('Cruiser', 0, 0, 70, 1500, 8, 90, image: 'cruiser.png', box: vm.Vector2(200, 125)));
  final boss = _sprite('Boss', vm.Vector2(-900, -900), vm.Vector2(390, 300), 'boss.png', z: 3, enabled: false)
    ..tags.add('enemy')
    ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(330, 150), offset: vm.Vector2(30, 75), isSolid: false))
    ..addComponent(HealthComponent(maxHealth: 900, team: 'monster', invulnerableTime: 0, hitFlash: 'white'))
    ..addComponent(ScriptComponent(scriptName: 'nova_boss.ember'));
  boss.addChild(_sprite('Core', vm.Vector2(-68, 0), vm.Vector2(120, 120), 'boss_core.png', z: 4, additive: true));
  scene.addEntity(boss);

  scene
    ..addEntity(_pickup('Power', 'power', 0, 40))
    ..addEntity(_pickup('Bomb Pickup', 'bomb', 1, 40))
    ..addEntity(_pickup('Shield Pickup', 'shield', 2, 40))
    ..addEntity(_pickup('Crystal', 'crystal', 3, 22));

  // Effects
  scene
    ..addEntity(_sprite('Shockwave', vm.Vector2(-900, -900), vm.Vector2(128, 128), 'ring.png', z: 9, additive: true, enabled: false))
    ..addEntity(_emitter('Boom FX', const Color(0xFFFFB86B), const Color(0x00FF2D75), size: 9, speed: 150, life: 0.75))
    ..addEntity(_emitter('Spark FX', const Color(0xFFFFFFFF), const Color(0x0022D3EE), size: 3.5, speed: 320, life: 0.45));

  scene.addEntity(EmberEntity(name: 'Stage')..addComponent(ScriptComponent(scriptName: 'nova_stage.ember')));

  // HUD
  scene
    ..addEntity(_text('ScoreLabel', 'SCORE', 12, EmberAnchor.topLeft, vm.Vector2(22, 14), color: Nova.dim, spacing: 3))
    ..addEntity(_text('ScoreText', '0', 30, EmberAnchor.topLeft, vm.Vector2(20, 30), glow: true))
    ..addEntity(_text('MultText', 'x1.0', 16, EmberAnchor.topLeft, vm.Vector2(22, 70), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('HiText', 'HI 0', 14, EmberAnchor.topRight, vm.Vector2(-22, 16), color: Nova.dim, spacing: 2))
    ..addEntity(EmberEntity(name: 'Lives')
      ..addComponent(UIImageComponent(assetPath: '${Nova.art}/icons.png', columns: 2, frame: 0, count: 3, spacing: 2,
          anchor: EmberAnchor.bottomLeft, offset: vm.Vector2(16, -14), size: vm.Vector2(34, 34))
        ..smooth = true))
    ..addEntity(EmberEntity(name: 'Bombs')
      ..addComponent(UIImageComponent(assetPath: '${Nova.art}/icons.png', columns: 2, frame: 1, count: 2, spacing: 0,
          anchor: EmberAnchor.bottomLeft, offset: vm.Vector2(16, -50), size: vm.Vector2(28, 28))
        ..smooth = true))
    ..addEntity(_text('PowerLabel', 'POWER', 11, EmberAnchor.bottomRight, vm.Vector2(-150, -58), color: Nova.dim, spacing: 2))
    ..addEntity(EmberEntity(name: 'PowerBar')
      ..addComponent(UIBarComponent(value: 1, max: 4, fillColor: const Color(0xFF3B82F6), backColor: const Color(0x99101830),
          anchor: EmberAnchor.bottomRight, offset: vm.Vector2(-150, -44), size: vm.Vector2(120, 8))))
    ..addEntity(_button('BombButton', 'BOMB', 'bomb', vm.Vector2(-16, -14), vm.Vector2(86, 34), anchor: EmberAnchor.bottomRight,
        color: const Color(0xFFF97316)))
    ..addEntity(_text('BossName', 'EMBER DREADNOUGHT', 12, EmberAnchor.topCenter, vm.Vector2(0, 14), color: const Color(0xFFF9A8D4), spacing: 3, enabled: false))
    ..addEntity(EmberEntity(name: 'BossBar', enabled: false)
      ..addComponent(UIBarComponent(value: 1, max: 1, fillColor: const Color(0xFFEC4899), backColor: const Color(0x99101830),
          anchor: EmberAnchor.topCenter, offset: vm.Vector2(0, 34), size: vm.Vector2(420, 8))))
    ..addEntity(_text('Banner', '', 44, EmberAnchor.center, vm.Vector2(0, -40), glow: true, spacing: 6))
    ..addEntity(_text('Subtitle', '', 16, EmberAnchor.center, vm.Vector2(0, 8), color: Nova.dim, spacing: 1));

  // Pause
  scene
    ..addEntity(_text('PausedText', 'PAUSED', 40, EmberAnchor.center, vm.Vector2(0, -60), glow: true, spacing: 8, enabled: false))
    ..addEntity(_button('ResumeButton', 'RESUME', 'resume', vm.Vector2(0, 10), vm.Vector2(180, 42), enabled: false))
    ..addEntity(_button('QuitButton', 'MENU', 'menu', vm.Vector2(0, 62), vm.Vector2(180, 42), enabled: false, color: Nova.dim));

  // Results (shown by the stage script)
  scene
    ..addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Nova.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(460, 285))
        ..smooth = true))
    ..addEntity(_text('ResultsTitle', '', 32, EmberAnchor.center, vm.Vector2(0, -92), glow: true, spacing: 6, enabled: false))
    ..addEntity(_text('ResultsScore', '', 40, EmberAnchor.center, vm.Vector2(0, -36), color: const Color(0xFFFDE68A), glow: true, enabled: false))
    ..addEntity(_text('ResultsLine', '', 14, EmberAnchor.center, vm.Vector2(0, 10), color: Nova.dim, enabled: false))
    ..addEntity(_text('ResultsStats', '', 13, EmberAnchor.center, vm.Vector2(0, 34), color: Nova.dim, enabled: false))
    ..addEntity(_button('RetryButton', 'RETRY', 'retry', vm.Vector2(-80, 92), vm.Vector2(140, 40), hotkey: 'Enter', enabled: false))
    ..addEntity(_button('NextButton', 'NEXT LOOP', 'next', vm.Vector2(-80, 92), vm.Vector2(140, 40), hotkey: 'Enter', enabled: false))
    ..addEntity(_button('MenuButton', 'MENU', 'menu', vm.Vector2(80, 92), vm.Vector2(140, 40), enabled: false, color: Nova.dim));
  return scene;
}

EmberScene buildNovaTitle() {
  final scene = EmberScene(name: Nova.title);
  _addSpace(scene);
  scene.addEntity(_ship('Title Ship', vm.Vector2(250, 330))..getComponent<Transform2DComponent>()!.scale = vm.Vector2(1.6, 1.6));
  scene.addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'nova_title.ember')));
  scene
    ..addEntity(_text('Logo', 'EMBER NOVA', 72, EmberAnchor.topCenter, vm.Vector2(0, 70), glow: true, spacing: 14))
    ..addEntity(_text('Tagline', 'A neon shooter. Weave through the bullets, break the armada.', 16, EmberAnchor.topCenter, vm.Vector2(0, 160),
        color: Nova.dim, spacing: 1))
    ..addEntity(_button('StartButton', 'START', 'start', vm.Vector2(140, 40), vm.Vector2(200, 48), hotkey: 'Enter'))
    ..addEntity(_text('BestText', '', 14, EmberAnchor.center, vm.Vector2(140, 96), color: const Color(0xFFFDE68A), spacing: 2))
    ..addEntity(_text('Controls', 'Arrows / WASD fly   ·   Shift precise   ·   X bomb   ·   P pause   ·   or drag with mouse or finger', 13,
        EmberAnchor.bottomCenter, vm.Vector2(0, -18), color: Nova.dim));
  return scene;
}

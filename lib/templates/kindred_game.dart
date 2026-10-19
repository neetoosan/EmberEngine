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
import '../subsystems/two_d/top_down_controller.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "Ember Kindred": a co-op arena for 1 to 4 players on one screen. Four
/// lantern spirits hold a moonlit grove against ten waves of shadow things
/// and the Hollow. Friends join at any time (keyboard halves or gamepads);
/// the camera zooms out to keep everyone in view; a light bond between
/// spirits burns whatever crosses it; a fallen spirit gets back up when a
/// friend stays close. Logic: [kindredScripts].
class Kindred {
  static const String art = 'assets/templates/kindred';
  static const String title = 'Title';
  static const String grove = 'Grove';
  static const double width = 1600, height = 1000;

  /// The four spirits, in player order.
  static const List<String> spirits = ['Sol', 'Lume', 'Iris', 'Wren'];

  static const List<String> assetFiles = [
    '$art/spirits.png', '$art/faces.png', '$art/foes.png', '$art/hollow.png', '$art/grove.png', '$art/shots.png', '$art/motes.png',
    '$art/ring.png', '$art/panel.png',
    '$art/kindred.wav', '$art/shoot.wav', '$art/hit.wav', '$art/hurt.wav', '$art/down.wav', '$art/revive.wav', '$art/join.wav',
    '$art/wave.wav', '$art/dash.wav', '$art/roar.wav', '$art/win.wav', '$art/lose.wav',
  ];

  static const Color ink = Color(0xFFF0FDFA);
  static const Color mint = Color(0xFF5EEAD4);
  static const Color dim = Color(0xFF99F6E4);

  /// Each spirit's colour (HUD bars, bonds).
  static const List<Color> colors = [Color(0xFFF97316), Color(0xFF38BDF8), Color(0xFFC084FC), Color(0xFFFACC15)];
}

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset,
        {Color color = Kindred.ink, bool glow = false, double spacing = 0, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color, outline: true, glow: glow, letterSpacing: spacing));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size, {String hotkey = '', Color color = Kindred.mint, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UIButtonComponent(text: text, action: action, hotkey: hotkey, anchor: EmberAnchor.center, offset: offset, size: size, color: color, style: 'outline', fontSize: 15));

EmberEntity _sprite(String name, vm.Vector2 pos, double size, String image, {int z = 0, int columns = 1, int rows = 1, int frame = 0, bool additive = false, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(Transform2DComponent(position: pos, size: vm.Vector2(size, size), anchor: EmberAnchor.center, zIndex: z))
      ..addComponent(FlameSpriteComponent(assetPath: '${Kindred.art}/$image', smooth: true, additive: additive)
        ..columns = columns
        ..rows = rows
        ..frame = frame);

EmberEntity _backdrop() => EmberEntity(name: 'Grove Art')
  ..addComponent(Transform2DComponent(position: vm.Vector2(Kindred.width / 2, Kindred.height / 2), size: vm.Vector2(Kindred.width, Kindred.height), anchor: EmberAnchor.center, zIndex: -20))
  ..addComponent(FlameSpriteComponent(assetPath: '${Kindred.art}/grove.png', smooth: true));

/// A shared screen: frames every spirit in play, zooming out as they spread.
EmberEntity _camera({bool follow = true}) => EmberEntity(name: 'Camera')
  ..addComponent(Transform2DComponent(position: vm.Vector2(Kindred.width / 2, Kindred.height / 2), size: vm.Vector2.zero()))
  ..addComponent(Camera2DComponent(
    designWidth: 960,
    designHeight: 540,
    followTarget: follow ? Kindred.spirits.join(', ') : '',
    smoothing: 0.88,
    boundsEnabled: true,
    boundsMin: vm.Vector2.zero(),
    boundsMax: vm.Vector2(Kindred.width, Kindred.height),
    backgroundColor: const Color(0xFF061412),
    zoom: follow ? 1 : 0.62,
    vignette: 0.3,
    fitTargets: follow,
    minZoom: 0.62,
    maxZoom: 1,
    fitPadding: 170,
  ));

EmberEntity _spirit(int slot) {
  final name = Kindred.spirits[slot];
  return _sprite(name, vm.Vector2(760 + slot * 30.0, 500 + (slot.isOdd ? 30 : -30)), 60, 'spirits.png', z: 5, columns: 3, rows: 4, frame: slot * 3,
      enabled: slot == 0)
    ..tags.addAll(['spirit', 'alive'])
    ..addComponent(TopDownController2DComponent(moveSpeed: 200))
    ..addComponent(HealthComponent(maxHealth: 6, team: 'player', invulnerableTime: 0.9, destroyOnDeath: false, hitFlash: 'white'))
    ..addComponent(ScriptComponent(scriptName: 'kindred_spirit.ember', vars: {'slot': slot + 1}))
    ..addChild(_sprite('Ring', vm.Vector2(0, 4), 96, 'ring.png', z: 4, additive: true, enabled: false));
}

EmberEntity _foe(String kind, int frame, double size, {double hp = 2, double speed = 100}) => _sprite(kind, vm.Vector2(-900, -900), size, 'foes.png', z: 4, columns: 3, frame: frame, enabled: false)
  ..tags.add('foe')
  ..addComponent(TopDownController2DComponent(moveSpeed: speed))
  ..addComponent(HealthComponent(maxHealth: hp, team: 'monster', invulnerableTime: 0.04, hitFlash: 'white', showBar: hp > 2))
  ..addComponent(ScriptComponent(scriptName: 'kindred_foe.ember', vars: {'kind': kind}));

EmberEntity _emitter(String name, Color start, Color end, {double size = 4, double speed = 160, double life = 0.5}) => EmberEntity(name: name)
  ..addComponent(Transform2DComponent(position: vm.Vector2(-5000, -5000), size: vm.Vector2.zero(), zIndex: 9))
  ..addComponent(ParticleEmitter2DComponent(
      spawnRate: 0, maxParticles: 400, particleLifetime: life, startColor: start, endColor: end, startSize: size, endSize: 0.5, speed: speed, gravity: 0, glow: true));

/// One player's corner of the HUD: face, name, health bar and a join hint.
void _card(EmberScene scene, int slot) {
  final right = slot.isOdd;
  final bottom = slot >= 2;
  final anchor = bottom ? (right ? EmberAnchor.bottomRight : EmberAnchor.bottomLeft) : (right ? EmberAnchor.topRight : EmberAnchor.topLeft);
  final sx = right ? -1.0 : 1.0, sy = bottom ? -1.0 : 1.0;
  final n = slot + 1;
  final joined = slot == 0;
  final hint = ['', 'P2  ·  press  ,  or pad 2  X  to join', 'P3  ·  press  X  on pad 3 to join', 'P4  ·  press  X  on pad 4 to join'][slot];
  scene
    ..addEntity(EmberEntity(name: 'Face$n', enabled: joined)
      ..addComponent(UIImageComponent(assetPath: '${Kindred.art}/faces.png', columns: 4, frame: slot, anchor: anchor, offset: vm.Vector2(14 * sx, 10 * sy), size: vm.Vector2(44, 44))
        ..smooth = true))
    ..addEntity(_text('Name$n', Kindred.spirits[slot].toUpperCase(), 13, anchor, vm.Vector2(64 * sx, (bottom ? 36 : 12) * sy),
        color: Color.lerp(Kindred.colors[slot], const Color(0xFFFFFFFF), 0.45)!, spacing: 2, enabled: joined))
    ..addEntity(EmberEntity(name: 'Bar$n', enabled: joined)
      ..addComponent(UIBarComponent(value: 6, max: 6, fillColor: Kindred.colors[slot], backColor: const Color(0x99041210), anchor: anchor,
          offset: vm.Vector2(64 * sx, (bottom ? 16 : 32) * sy), size: vm.Vector2(150, 12))
        ..fromRight = right))
    ..addEntity(_text('Join$n', hint, 12, anchor, vm.Vector2(16 * sx, 18 * sy), color: Kindred.dim, enabled: !joined));
}

EmberScene buildKindredGrove() {
  final scene = EmberScene(name: Kindred.grove);
  scene
    ..addEntity(_camera())
    ..addEntity(_backdrop())
    ..addEntity(EmberEntity(name: 'Grove')..addComponent(ScriptComponent(scriptName: 'kindred_game.ember')));
  // The light bonds between neighbouring spirits (drawn under them)
  for (var k = 1; k <= 3; k++) {
    scene.addEntity(EmberEntity(name: 'Bond $k')
      ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero(), zIndex: 3))
      ..addComponent(Line2DComponent(color: const Color(0xCCFEF3C7), width: 4, glow: true)));
  }
  for (var slot = 0; slot < 4; slot++) {
    scene.addEntity(_spirit(slot));
  }
  scene
    ..addEntity(EmberEntity(name: 'Bolts')
      ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero(), zIndex: 7))
      ..addComponent(BulletPool2DComponent(image: '${Kindred.art}/shots.png', columns: 5, size: 26, team: 'player', damage: 1, margin: 80, maxBullets: 600)))
    ..addEntity(EmberEntity(name: 'Shadow Shots')
      ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero(), zIndex: 8))
      ..addComponent(BulletPool2DComponent(image: '${Kindred.art}/shots.png', columns: 5, size: 30, team: 'monster', damage: 1, margin: 120, maxBullets: 800)))
    ..addEntity(_foe('Wisp', 0, 46, hp: 2, speed: 115))
    ..addEntity(_foe('Brute', 1, 76, hp: 12, speed: 62))
    ..addEntity(_foe('Spitter', 2, 56, hp: 5, speed: 70))
    ..addEntity(_sprite('Hollow', vm.Vector2(-900, -900), 190, 'hollow.png', z: 6, enabled: false)
      ..tags.add('foe')
      ..addComponent(TopDownController2DComponent(moveSpeed: 55))
      ..addComponent(HealthComponent(maxHealth: 220, team: 'monster', invulnerableTime: 0.04, hitFlash: 'white', destroyOnDeath: false))
      ..addComponent(ScriptComponent(scriptName: 'kindred_hollow.ember')))
    ..addEntity(_sprite('Mote', vm.Vector2(-900, -900), 26, 'motes.png', z: 3, columns: 2, frame: 0, additive: true, enabled: false)
      ..addComponent(ScriptComponent(scriptName: 'kindred_mote.ember', vars: {'kind': 'mote'})))
    ..addEntity(_sprite('Bloom', vm.Vector2(-900, -900), 30, 'motes.png', z: 3, columns: 2, frame: 1, enabled: false)
      ..addComponent(ScriptComponent(scriptName: 'kindred_mote.ember', vars: {'kind': 'bloom'})))
    ..addEntity(_emitter('Spark FX', const Color(0xFFFFF7ED), const Color(0x00FDBA74)))
    ..addEntity(_emitter('Shadow FX', const Color(0xFFE9D5FF), const Color(0x007C3AED), size: 5, speed: 140, life: 0.6))
    ..addEntity(_emitter('Revive FX', const Color(0xFFFEF3C7), const Color(0x005EEAD4), size: 6, speed: 220, life: 0.8));

  // HUD
  for (var slot = 0; slot < 4; slot++) {
    _card(scene, slot);
  }
  scene
    ..addEntity(_text('WaveText', 'WAVE 1', 18, EmberAnchor.topCenter, vm.Vector2(0, 10), spacing: 4))
    ..addEntity(_text('ScoreText', '0', 15, EmberAnchor.topCenter, vm.Vector2(0, 34), color: const Color(0xFFFDE68A)))
    ..addEntity(EmberEntity(name: 'BossBar', enabled: false)
      ..addComponent(UIBarComponent(value: 1, max: 1, fillColor: const Color(0xFFD946EF), backColor: const Color(0x99140818), anchor: EmberAnchor.topCenter,
          offset: vm.Vector2(0, 58), size: vm.Vector2(360, 10))))
    ..addEntity(_text('Banner', '', 46, EmberAnchor.center, vm.Vector2(0, -90), color: const Color(0xFFFEF3C7), glow: true, spacing: 8))
    ..addEntity(_text('Subtitle', '', 16, EmberAnchor.center, vm.Vector2(0, -44), color: Kindred.dim))
    ..addEntity(_text('PausedText', 'PAUSED', 40, EmberAnchor.center, vm.Vector2(0, -60), glow: true, spacing: 8, enabled: false))
    ..addEntity(_button('ResumeButton', 'RESUME', 'resume', vm.Vector2(0, 10), vm.Vector2(180, 42), enabled: false))
    ..addEntity(_button('QuitButton', 'MENU', 'menu', vm.Vector2(0, 62), vm.Vector2(180, 42), enabled: false, color: Kindred.dim))
    ..addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Kindred.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(460, 270))
        ..smooth = true))
    ..addEntity(_text('ResultsTitle', '', 30, EmberAnchor.center, vm.Vector2(0, -80), color: const Color(0xFFFEF3C7), glow: true, spacing: 4, enabled: false))
    ..addEntity(_text('ResultsLine', '', 16, EmberAnchor.center, vm.Vector2(0, -28), enabled: false))
    ..addEntity(_text('ResultsStats', '', 13, EmberAnchor.center, vm.Vector2(0, 2), color: Kindred.dim, enabled: false))
    ..addEntity(_button('RetryButton', 'AGAIN', 'retry', vm.Vector2(-80, 72), vm.Vector2(140, 40), hotkey: 'Enter', enabled: false))
    ..addEntity(_button('MenuButton', 'MENU', 'menu', vm.Vector2(80, 72), vm.Vector2(140, 40), enabled: false, color: Kindred.dim));
  return scene;
}

EmberScene buildKindredTitle() {
  final scene = EmberScene(name: Kindred.title);
  scene
    ..addEntity(_camera(follow: false))
    ..addEntity(_backdrop())
    ..addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'kindred_title.ember')));
  for (var slot = 0; slot < 4; slot++) {
    scene.addEntity(_sprite('${Kindred.spirits[slot]} Pose', vm.Vector2(500 + slot * 200.0, 750), 110, 'spirits.png', z: 5, columns: 3, rows: 4, frame: slot * 3));
  }
  scene
    ..addEntity(_text('Logo', 'EMBER KINDRED', 66, EmberAnchor.topCenter, vm.Vector2(0, 44), color: const Color(0xFFFEF3C7), glow: true, spacing: 12))
    ..addEntity(_text('Tagline', 'Four lantern spirits. One grove. Hold the light together.', 16, EmberAnchor.topCenter, vm.Vector2(0, 124), color: Kindred.dim))
    ..addEntity(_button('PlayButton', 'PLAY', 'play', vm.Vector2(0, 36), vm.Vector2(200, 46), hotkey: 'Enter'))
    ..addEntity(_text('BestText', '', 14, EmberAnchor.center, vm.Vector2(0, 84), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('PlayersText', '1 to 4 players on one screen. Friends join at any time.', 13, EmberAnchor.bottomCenter, vm.Vector2(0, -60)))
    ..addEntity(_text('Controls',
        'P1: WASD · F shoot · G dash      P2: arrows · , shoot · . dash      pads: stick · X shoot · Y dash      stay close to a fallen friend to bring them back',
        11, EmberAnchor.bottomCenter, vm.Vector2(0, -24), color: Kindred.dim));
  return scene;
}

import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/combat/combat.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "Ember Clash": a 1v1 fighting game, against the CPU or a second player
/// (two halves of a keyboard, or gamepads). Frame-data moves at a fixed 60
/// steps a second, guarding high and low, specials from motion inputs,
/// hitstop and combos. Logic: [clashScripts].
class Clash {
  static const String art = 'assets/templates/clash';
  static const String title = 'Title';
  static const String arena = 'Arena';

  static const List<String> assetFiles = [
    '$art/kai.png', '$art/ryn.png', '$art/stage.png', '$art/orbs.png', '$art/spark.png', '$art/panel.png',
    '$art/clash.wav', '$art/punch.wav', '$art/kick.wav', '$art/block.wav', '$art/swoosh.wav', '$art/fireball.wav', '$art/ko.wav', '$art/gong.wav',
  ];

  static const Color ink = Color(0xFFFFF7ED);
  static const Color ember = Color(0xFFF97316);
  static const Color frost = Color(0xFF38BDF8);
}

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset,
        {Color color = Clash.ink, bool glow = false, double spacing = 0, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color, outline: true, glow: glow, letterSpacing: spacing));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size, {String hotkey = '', Color color = Clash.ember, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UIButtonComponent(text: text, action: action, hotkey: hotkey, anchor: EmberAnchor.center, offset: offset, size: size, color: color, style: 'outline', fontSize: 15));

EmberEntity _backdrop() => EmberEntity(name: 'Stage Art')
  ..addComponent(Transform2DComponent(position: vm.Vector2(480, 270), size: vm.Vector2(960, 540), anchor: EmberAnchor.center, zIndex: -20))
  ..addComponent(FlameSpriteComponent(assetPath: '${Clash.art}/stage.png', smooth: true));

EmberEntity _camera() => EmberEntity(name: 'Camera')
  ..addComponent(Transform2DComponent(position: vm.Vector2(480, 270), size: vm.Vector2.zero()))
  ..addComponent(Camera2DComponent(designWidth: 960, designHeight: 540, backgroundColor: const Color(0xFF1C0A05), vignette: 0.3));

EmberEntity _fighter(String name, String image, int player, double x, String orb) => EmberEntity(name: name)
  ..addComponent(Transform2DComponent(position: vm.Vector2(x, 450), size: vm.Vector2(168, 168), anchor: EmberAnchor.bottomCenter, zIndex: 5))
  ..addComponent(FlameSpriteComponent(assetPath: '${Clash.art}/$image', smooth: true)
    ..columns = 5
    ..rows = 3)
  ..addComponent(HealthComponent(maxHealth: 100, team: 'p$player', invulnerableTime: 0, destroyOnDeath: false, hitFlash: 'white'))
  ..addComponent(ScriptComponent(scriptName: 'clash_fighter.ember', vars: {'player': player, 'orbName': orb}));

EmberEntity _orb(String name, int frame) => EmberEntity(name: name, enabled: false)
  ..tags.add(name)
  ..addComponent(Transform2DComponent(position: vm.Vector2(-900, -900), size: vm.Vector2(64, 64), anchor: EmberAnchor.center, zIndex: 6))
  ..addComponent(FlameSpriteComponent(assetPath: '${Clash.art}/orbs.png', smooth: true, additive: true)
    ..columns = 2
    ..frame = frame)
  ..addComponent(ScriptComponent(scriptName: 'clash_orb.ember'));

EmberScene buildClashArena() {
  final scene = EmberScene(name: Clash.arena);
  scene
    ..addEntity(_camera())
    ..addEntity(_backdrop())
    ..addEntity(_fighter('Kai', 'kai.png', 1, 330, 'Kai Orb'))
    ..addEntity(_fighter('Ryn', 'ryn.png', 2, 630, 'Ryn Orb'))
    ..addEntity(_orb('Kai Orb', 0))
    ..addEntity(_orb('Ryn Orb', 1))
    ..addEntity(EmberEntity(name: 'Spark', enabled: false)
      ..addComponent(Transform2DComponent(position: vm.Vector2(-900, -900), size: vm.Vector2(90, 90), anchor: EmberAnchor.center, zIndex: 8))
      ..addComponent(FlameSpriteComponent(assetPath: '${Clash.art}/spark.png', smooth: true, additive: true)))
    ..addEntity(EmberEntity(name: 'Hit FX')
      ..addComponent(Transform2DComponent(position: vm.Vector2(-5000, -5000), size: vm.Vector2.zero(), zIndex: 9))
      ..addComponent(ParticleEmitter2DComponent(
          spawnRate: 0, maxParticles: 300, particleLifetime: 0.35, startColor: const Color(0xFFFFF7ED), endColor: const Color(0x00F97316),
          startSize: 4, endSize: 0.5, speed: 260, gravity: 300, glow: true)))
    ..addEntity(EmberEntity(name: 'Match')..addComponent(ScriptComponent(scriptName: 'clash_match.ember')));

  // HUD: health bars, names, round wins, the timer
  scene
    ..addEntity(EmberEntity(name: 'P1Bar')
      ..addComponent(UIBarComponent(value: 100, max: 100, fillColor: Clash.ember, backColor: const Color(0x99140804), anchor: EmberAnchor.topLeft,
          offset: vm.Vector2(24, 22), size: vm.Vector2(360, 18))))
    ..addEntity(EmberEntity(name: 'P2Bar')
      ..addComponent(UIBarComponent(value: 100, max: 100, fillColor: Clash.frost, backColor: const Color(0x99140804), anchor: EmberAnchor.topRight,
          offset: vm.Vector2(-24, 22), size: vm.Vector2(360, 18))
        ..fromRight = true))
    ..addEntity(_text('P1Name', 'KAI', 15, EmberAnchor.topLeft, vm.Vector2(26, 46), color: const Color(0xFFFED7AA), spacing: 3))
    ..addEntity(_text('P2Name', 'RYN', 15, EmberAnchor.topRight, vm.Vector2(-26, 46), color: const Color(0xFFBAE6FD), spacing: 3))
    ..addEntity(_text('P1Wins', '', 16, EmberAnchor.topLeft, vm.Vector2(340, 46), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('P2Wins', '', 16, EmberAnchor.topRight, vm.Vector2(-340, 46), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('TimerText', '60', 34, EmberAnchor.topCenter, vm.Vector2(0, 12), glow: true))
    ..addEntity(_text('P1Combo', '', 22, EmberAnchor.centerLeft, vm.Vector2(30, -80), color: const Color(0xFFFED7AA), glow: true))
    ..addEntity(_text('P2Combo', '', 22, EmberAnchor.centerRight, vm.Vector2(-30, -80), color: const Color(0xFFBAE6FD), glow: true))
    ..addEntity(_text('Banner', '', 64, EmberAnchor.center, vm.Vector2(0, -60), color: const Color(0xFFFDE68A), glow: true, spacing: 8))
    ..addEntity(_text('Subtitle', '', 18, EmberAnchor.center, vm.Vector2(0, 4)))
    ..addEntity(_text('PausedText', 'PAUSED', 40, EmberAnchor.center, vm.Vector2(0, -60), glow: true, spacing: 8, enabled: false))
    ..addEntity(_button('ResumeButton', 'RESUME', 'resume', vm.Vector2(0, 10), vm.Vector2(180, 42), enabled: false))
    ..addEntity(_button('QuitButton', 'MENU', 'menu', vm.Vector2(0, 62), vm.Vector2(180, 42), enabled: false, color: const Color(0xFFFED7AA)))
    ..addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Clash.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(440, 240))
        ..smooth = true))
    ..addEntity(_text('ResultsTitle', '', 40, EmberAnchor.center, vm.Vector2(0, -56), color: const Color(0xFFFDE68A), glow: true, spacing: 6, enabled: false))
    ..addEntity(_text('ResultsLine', '', 16, EmberAnchor.center, vm.Vector2(0, -4), enabled: false))
    ..addEntity(_button('RetryButton', 'REMATCH', 'retry', vm.Vector2(-80, 64), vm.Vector2(140, 40), hotkey: 'Enter', enabled: false))
    ..addEntity(_button('MenuButton', 'MENU', 'menu', vm.Vector2(80, 64), vm.Vector2(140, 40), enabled: false, color: const Color(0xFFFED7AA)));
  return scene;
}

EmberScene buildClashTitle() {
  final scene = EmberScene(name: Clash.title);
  scene
    ..addEntity(_camera())
    ..addEntity(_backdrop())
    ..addEntity(EmberEntity(name: 'Kai Pose')
      ..addComponent(Transform2DComponent(position: vm.Vector2(250, 450), size: vm.Vector2(200, 200), anchor: EmberAnchor.bottomCenter))
      ..addComponent(FlameSpriteComponent(assetPath: '${Clash.art}/kai.png', smooth: true)
        ..columns = 5
        ..rows = 3
        ..frame = 9))
    ..addEntity(EmberEntity(name: 'Ryn Pose')
      ..addComponent(Transform2DComponent(position: vm.Vector2(710, 450), size: vm.Vector2(200, 200), anchor: EmberAnchor.bottomCenter))
      ..addComponent(FlameSpriteComponent(assetPath: '${Clash.art}/ryn.png', smooth: true, flipX: true)
        ..columns = 5
        ..rows = 3
        ..frame = 11))
    ..addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'clash_title.ember')))
    ..addEntity(_text('Logo', 'EMBER CLASH', 70, EmberAnchor.topCenter, vm.Vector2(0, 40), color: const Color(0xFFFDE68A), glow: true, spacing: 12))
    ..addEntity(_text('Tagline', 'Kai of the ember temple against Ryn of the frost clan', 16, EmberAnchor.topCenter, vm.Vector2(0, 124)))
    ..addEntity(_button('EasyButton', 'VS CPU · EASY', 'easy', vm.Vector2(0, -50), vm.Vector2(220, 42)))
    ..addEntity(_button('NormalButton', 'VS CPU · NORMAL', 'normal', vm.Vector2(0, 0), vm.Vector2(220, 42), hotkey: 'Enter'))
    ..addEntity(_button('HardButton', 'VS CPU · HARD', 'hard', vm.Vector2(0, 50), vm.Vector2(220, 42)))
    ..addEntity(_button('VersusButton', '2 PLAYERS', 'versus', vm.Vector2(0, 110), vm.Vector2(220, 42), color: Clash.frost))
    ..addEntity(_text('WinsText', '', 13, EmberAnchor.bottomCenter, vm.Vector2(0, -44), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('Controls',
        'P1: WASD · F jab · G kick · H block    P2: arrows · , jab · . kick · / block    pads: X jab · Y kick · B block    ↓↘→ + jab: orb    →↓↘ + jab: rising strike',
        11, EmberAnchor.bottomCenter, vm.Vector2(0, -18), color: const Color(0xFFFED7AA)));
  return scene;
}

import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "Ember Pulse": a four-lane rhythm game. Notes fall in time with "Neon
/// Drift" (the song and its charts come from [PulseSong]); timing uses the
/// Music clock, so it stays in step with what you hear. Logic: [pulseScripts].
class Pulse {
  static const String art = 'assets/templates/pulse';
  static const String title = 'Title';
  static const String stage = 'Stage';
  static const List<double> laneX = [345, 435, 525, 615];
  static const double hitY = 450;

  static const List<String> assetFiles = [
    '$art/bg.png', '$art/lane.png', '$art/notes.png', '$art/receptors.png', '$art/hold.png', '$art/flash.png', '$art/panel.png',
    '$art/song.wav', '$art/tick.wav', '$art/miss.wav', '$art/cheer.wav',
  ];

  static const List<Color> lanes = [Color(0xFF22D3EE), Color(0xFFA855F7), Color(0xFFF472B6), Color(0xFFFB923C)];
  static const Color ink = Color(0xFFFDF4FF);
}

EmberEntity _sprite(String name, vm.Vector2 pos, vm.Vector2 size, String image,
    {int z = 0, int columns = 1, int frame = 0, bool additive = false, bool enabled = true, Color tint = const Color(0xFFFFFFFF)}) {
  return EmberEntity(name: name, enabled: enabled)
    ..addComponent(Transform2DComponent(position: pos, size: size, anchor: EmberAnchor.center, zIndex: z))
    ..addComponent(FlameSpriteComponent(assetPath: '${Pulse.art}/$image', smooth: true, additive: additive, tint: tint)
      ..columns = columns
      ..frame = frame);
}

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset,
        {Color color = Pulse.ink, bool glow = false, double spacing = 0, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color, outline: false, glow: glow, letterSpacing: spacing));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size,
        {String hotkey = '', Color color = const Color(0xFFF472B6), bool enabled = true, EmberAnchor anchor = EmberAnchor.center}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UIButtonComponent(text: text, action: action, hotkey: hotkey, anchor: anchor, offset: offset, size: size, color: color, style: 'outline', fontSize: 15));

void _addBackdrop(EmberScene scene) {
  scene.addEntity(EmberEntity(name: 'Camera')
    ..addComponent(Transform2DComponent(position: vm.Vector2(480, 270), size: vm.Vector2.zero()))
    ..addComponent(Camera2DComponent(designWidth: 960, designHeight: 540, backgroundColor: const Color(0xFF0A0418), vignette: 0.35)));
  scene.addEntity(_sprite('Background', vm.Vector2(480, 270), vm.Vector2(960, 540), 'bg.png', z: -20));
}

/// The stage: lanes, receptors on the hit line, note templates, HUD, results.
EmberScene buildPulseStage() {
  final scene = EmberScene(name: Pulse.stage);
  _addBackdrop(scene);
  for (var i = 0; i < 4; i++) {
    final x = Pulse.laneX[i];
    scene
      ..addEntity(_sprite('Lane $i', vm.Vector2(x, 245), vm.Vector2(88, 520), 'lane.png', z: -10, tint: Color.lerp(Pulse.lanes[i], const Color(0xFFFFFFFF), 0.5)!))
      ..addEntity(_sprite('Receptor $i', vm.Vector2(x, Pulse.hitY), vm.Vector2(84, 42), 'receptors.png', columns: 4, frame: i, z: 2));
  }
  scene
    ..addEntity(_sprite('Note', vm.Vector2(-900, -900), vm.Vector2(84, 42), 'notes.png', columns: 4, z: 5, additive: true, enabled: false))
    ..addEntity(_sprite('Trail', vm.Vector2(-900, -900), vm.Vector2(40, 256), 'hold.png', z: 4, additive: true, enabled: false))
    ..addEntity(_sprite('Flash', vm.Vector2(-900, -900), vm.Vector2(110, 55), 'flash.png', z: 6, additive: true, enabled: false))
    ..addEntity(EmberEntity(name: 'Sparks')
      ..addComponent(Transform2DComponent(position: vm.Vector2(-5000, -5000), size: vm.Vector2.zero(), zIndex: 7))
      ..addComponent(ParticleEmitter2DComponent(
          spawnRate: 0, maxParticles: 300, particleLifetime: 0.4, startColor: const Color(0xFFFFFFFF), endColor: const Color(0x00F472B6),
          startSize: 3, endSize: 0.5, speed: 180, gravity: 200, glow: true)));
  scene.addEntity(EmberEntity(name: 'Stage')..addComponent(ScriptComponent(scriptName: 'pulse_stage.ember')));

  // Key hints under the receptors
  for (var i = 0; i < 4; i++) {
    scene.addEntity(_text('Key $i', ['D', 'F', 'J', 'K'][i], 14, EmberAnchor.topLeft, vm.Vector2(Pulse.laneX[i] - 5, Pulse.hitY + 30), color: Color.lerp(Pulse.lanes[i], const Color(0xFFFFFFFF), 0.4)!));
  }
  scene
    ..addEntity(_text('SongText', '', 14, EmberAnchor.topLeft, vm.Vector2(18, 16), color: const Color(0xFFF9A8D4), spacing: 3))
    ..addEntity(EmberEntity(name: 'Progress')
      ..addComponent(UIBarComponent(value: 0, max: 1, fillColor: const Color(0xFFF472B6), backColor: const Color(0x66120424),
          anchor: EmberAnchor.topLeft, offset: vm.Vector2(18, 38), size: vm.Vector2(200, 5))))
    ..addEntity(_text('ScoreText', '0', 32, EmberAnchor.topRight, vm.Vector2(-20, 12), glow: true))
    ..addEntity(_text('AccuracyText', '100.0%', 15, EmberAnchor.topRight, vm.Vector2(-22, 52), color: const Color(0xFFF9A8D4)))
    ..addEntity(_text('ComboText', '', 54, EmberAnchor.center, vm.Vector2(0, -110), color: const Color(0x99FDF4FF), glow: true))
    ..addEntity(_text('Judgement', '', 28, EmberAnchor.center, vm.Vector2(0, 90), glow: true, spacing: 4))
    ..addEntity(_text('PausedText', 'PAUSED', 40, EmberAnchor.center, vm.Vector2(0, -60), glow: true, spacing: 8, enabled: false))
    ..addEntity(_button('ResumeButton', 'RESUME', 'resume', vm.Vector2(0, 10), vm.Vector2(180, 42), enabled: false))
    ..addEntity(_button('QuitButton', 'MENU', 'menu', vm.Vector2(0, 62), vm.Vector2(180, 42), enabled: false, color: const Color(0xFFC4B5FD)));

  // Results
  scene
    ..addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Pulse.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(520, 300))
        ..smooth = true))
    ..addEntity(_text('ResultsTitle', '', 26, EmberAnchor.center, vm.Vector2(0, -105), color: const Color(0xFFF9A8D4), glow: true, spacing: 5, enabled: false))
    ..addEntity(_text('ResultsGrade', '', 80, EmberAnchor.center, vm.Vector2(0, -40), color: const Color(0xFFFDE68A), glow: true, enabled: false))
    ..addEntity(_text('ResultsLine', '', 14, EmberAnchor.center, vm.Vector2(0, 26), enabled: false))
    ..addEntity(_text('ResultsStats', '', 13, EmberAnchor.center, vm.Vector2(0, 50), color: const Color(0xFFC4B5FD), enabled: false))
    ..addEntity(_button('RetryButton', 'AGAIN', 'retry', vm.Vector2(-80, 104), vm.Vector2(140, 40), hotkey: 'Enter', enabled: false))
    ..addEntity(_button('MenuButton', 'MENU', 'menu', vm.Vector2(80, 104), vm.Vector2(140, 40), enabled: false, color: const Color(0xFFC4B5FD)));
  return scene;
}

EmberScene buildPulseTitle() {
  final scene = EmberScene(name: Pulse.title);
  _addBackdrop(scene);
  scene.addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'pulse_title.ember')));
  scene
    ..addEntity(_text('Logo', 'EMBER PULSE', 66, EmberAnchor.topCenter, vm.Vector2(0, 40), glow: true, spacing: 12))
    ..addEntity(_text('Tagline', 'Neon Drift  ·  hit the notes with the beat', 16, EmberAnchor.topCenter, vm.Vector2(0, 122), color: const Color(0xFFF9A8D4), spacing: 2));
  for (final (i, d, label, color) in [(0, 'easy', 'EASY', Pulse.lanes[0]), (1, 'normal', 'NORMAL', Pulse.lanes[2]), (2, 'hard', 'HARD', Pulse.lanes[3])]) {
    final x = (i - 1) * 190.0;
    scene
      ..addEntity(_button('${label}Button', label, d, vm.Vector2(x, 10), vm.Vector2(170, 50), color: color, hotkey: i == 1 ? 'Enter' : ''))
      ..addEntity(_text('${label}Best', '', 13, EmberAnchor.center, vm.Vector2(x, 52), color: const Color(0xFFFDE68A)));
  }
  scene
    ..addEntity(_button('SoonerButton', '−', 'sooner', vm.Vector2(-130, -60), vm.Vector2(40, 32), anchor: EmberAnchor.bottomCenter, color: const Color(0xFFC4B5FD)))
    ..addEntity(_text('OffsetText', 'Audio offset 0 ms', 14, EmberAnchor.bottomCenter, vm.Vector2(0, -66)))
    ..addEntity(_button('LaterButton', '+', 'later', vm.Vector2(130, -60), vm.Vector2(40, 32), anchor: EmberAnchor.bottomCenter, color: const Color(0xFFC4B5FD)))
    ..addEntity(_text('Controls', 'D F J K or the arrow keys (or tap the lanes)  ·  hold the long notes  ·  P pauses', 13, EmberAnchor.bottomCenter,
        vm.Vector2(0, -20), color: const Color(0xFFC4B5FD)));
  return scene;
}

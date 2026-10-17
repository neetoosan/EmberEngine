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

/// "Ember Gems": a match-3 puzzle. Swap gems to make lines; lines of four,
/// L/T shapes and lines of five make special gems. Three levels with
/// different goals (score, collect a colour, break the ice), stars and
/// unlocks. The board logic is Ember Script ([gemsScripts]).
class Gems {
  static const String art = 'assets/templates/gems';
  static const String music = '$art/gems.wav';
  static const String title = 'Title';
  static const List<String> levels = ['Level 1', 'Level 2', 'Level 3'];

  static const List<String> assetFiles = [
    '$art/gems.png', '$art/overlays.png', '$art/cells.png', '$art/background.png', '$art/star.png', '$art/panel.png', music,
  ];

  /// Board placement (matches gems_board.ember).
  static const double cell = 56, left = 256, top = 64;
  static const int size = 8;
}

EmberEntity _sprite(String name, vm.Vector2 pos, vm.Vector2 size, String image,
    {EmberAnchor anchor = EmberAnchor.center, int z = 0, int columns = 1, int frame = 0, bool enabled = true}) {
  return EmberEntity(name: name, enabled: enabled)
    ..addComponent(Transform2DComponent(position: pos, size: size, anchor: anchor, zIndex: z))
    ..addComponent(FlameSpriteComponent(assetPath: '${Gems.art}/$image')
      ..columns = columns
      ..frame = frame);
}

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset, {Color color = const Color(0xFFFFFFFF)}) =>
    EmberEntity(name: name)..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size,
        {EmberAnchor anchor = EmberAnchor.center, String hotkey = '', Color color = const Color(0xFFC084FC), bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UIButtonComponent(text: text, action: action, hotkey: hotkey, anchor: anchor, offset: offset, size: size, color: color));

EmberEntity _stars(String name, vm.Vector2 offset, double size, {bool enabled = true}) => EmberEntity(name: name, enabled: enabled)
  ..addComponent(UIImageComponent(
      assetPath: '${Gems.art}/star.png', columns: 2, frame: 0, emptyFrame: 1, count: 3, filled: 0, spacing: size / 4,
      anchor: EmberAnchor.center, offset: offset, size: vm.Vector2(size, size)));

EmberEntity _emitter(String name, Color start, Color end, {double size = 5, double speed = 120, double gravity = 200}) =>
    EmberEntity(name: name)
      ..addComponent(Transform2DComponent(position: vm.Vector2(-5000, -5000), size: vm.Vector2.zero(), zIndex: 8))
      ..addComponent(ParticleEmitter2DComponent(
        spawnRate: 0, // bursts only (scripts call particles.burst(count, where))
        maxParticles: 220,
        particleLifetime: 0.6,
        startColor: start,
        endColor: end,
        startSize: size,
        endSize: 1,
        speed: speed,
        gravity: gravity,
      ));

EmberEntity _camera() => EmberEntity(name: 'Camera')
  ..addComponent(Transform2DComponent(position: vm.Vector2(480, 270), size: vm.Vector2.zero()))
  ..addComponent(Camera2DComponent(designWidth: 960, designHeight: 540, backgroundColor: const Color(0xFF1E1B4B)));

void _addBackdrop(EmberScene scene) {
  scene.addEntity(_camera());
  scene.addEntity(_sprite('Background', vm.Vector2(0, 0), vm.Vector2(960, 540), 'background.png', anchor: EmberAnchor.topLeft, z: -10));
}

/// A level: the board, gem and ice templates, effects, HUD and results.
/// [vars] set the board script's goal, moves, stars and layout.
EmberScene _levelScene(String name, Map<String, Object?> vars) {
  final scene = EmberScene(name: name);
  _addBackdrop(scene);

  // Board backing and cells
  const boardW = Gems.cell * Gems.size;
  scene.addEntity(EmberEntity(name: 'Board Frame')
    ..addComponent(Transform2DComponent(
        position: vm.Vector2(Gems.left + boardW / 2, Gems.top + boardW / 2), size: vm.Vector2(boardW + 20, boardW + 20), anchor: EmberAnchor.center, zIndex: -2))
    ..addComponent(FlameSpriteComponent(assetPath: '${Gems.art}/panel.png')));
  for (var r = 0; r < Gems.size; r++) {
    for (var c = 0; c < Gems.size; c++) {
      scene.addEntity(_sprite('Cell', vm.Vector2(Gems.left + c * Gems.cell + Gems.cell / 2, Gems.top + r * Gems.cell + Gems.cell / 2),
          vm.Vector2(Gems.cell, Gems.cell), 'cells.png', columns: 4, frame: (r + c) % 2, z: -1));
    }
  }

  // Templates copied by the board script
  final gem = _sprite('Gem', vm.Vector2(-500, -500), vm.Vector2(50, 50), 'gems.png', columns: 7, z: 3, enabled: false)..tags.add('gem');
  gem.addChild(_sprite('Mark', vm.Vector2.zero(), vm.Vector2(50, 50), 'overlays.png', columns: 5, z: 4, enabled: false));
  scene.addEntity(gem);
  scene.addEntity(_sprite('Ice', vm.Vector2(-500, -500), vm.Vector2(Gems.cell, Gems.cell), 'cells.png', columns: 4, frame: 2, z: 1, enabled: false)
    ..tags.add('ice'));
  scene.addEntity(_sprite('Selector', vm.Vector2(-500, -500), vm.Vector2(Gems.cell, Gems.cell), 'overlays.png', columns: 5, frame: 3, z: 5, enabled: false));
  for (final n in [1, 2]) {
    scene.addEntity(_sprite('Hint $n', vm.Vector2(-500, -500), vm.Vector2(44, 44), 'overlays.png', columns: 5, frame: 4, z: 5, enabled: false));
  }
  scene.addEntity(_emitter('Pop FX', const Color(0xFFFFF7B0), const Color(0x00C084FC), size: 5, speed: 110, gravity: 120));
  scene.addEntity(_emitter('Ice FX', const Color(0xFFFFFFFF), const Color(0x00BAE6FD), size: 4, speed: 140, gravity: 260));

  scene.addEntity(EmberEntity(name: 'Board')..addComponent(ScriptComponent(scriptName: 'gems_board.ember', vars: vars)));

  // HUD: moves on the left, score and goal on the right
  const dim = Color(0xFFC4B5FD);
  scene
    ..addEntity(_button('RetryHud', 'Retry', 'restart', vm.Vector2(16, 14), vm.Vector2(84, 32), anchor: EmberAnchor.topLeft, color: const Color(0xFF4C1D95)))
    ..addEntity(_button('MenuHud', 'Menu', 'level:${Gems.title}', vm.Vector2(108, 14), vm.Vector2(84, 32), anchor: EmberAnchor.topLeft,
        color: const Color(0xFF4C1D95)))
    ..addEntity(_text('LevelText', name, 18, EmberAnchor.topCenter, vm.Vector2(0, 22)))
    ..addEntity(_text('MovesLabel', 'MOVES', 16, EmberAnchor.centerLeft, vm.Vector2(78, -70), color: dim))
    ..addEntity(_text('MovesText', '0', 56, EmberAnchor.centerLeft, vm.Vector2(78, -20)))
    ..addEntity(_text('BestText', 'Best 0', 14, EmberAnchor.centerLeft, vm.Vector2(70, 50), color: dim))
    ..addEntity(_text('ScoreLabel', 'SCORE', 16, EmberAnchor.centerRight, vm.Vector2(-86, -110), color: dim))
    ..addEntity(_text('ScoreText', '0', 36, EmberAnchor.centerRight, vm.Vector2(-70, -72)))
    ..addEntity(EmberEntity(name: 'StarBar')
      ..addComponent(UIBarComponent(value: 0, max: 1, fillColor: const Color(0xFFFACC15), anchor: EmberAnchor.centerRight,
          offset: vm.Vector2(-30, -26), size: vm.Vector2(190, 14))))
    ..addEntity(_text('GoalLabel', 'GOAL', 16, EmberAnchor.centerRight, vm.Vector2(-104, 22), color: dim))
    ..addEntity(_text('GoalText', '', 13, EmberAnchor.centerRight, vm.Vector2(-28, 52)))
    ..addEntity(_text('Banner', '', 34, EmberAnchor.center, vm.Vector2(0, -6), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('HintText', 'Swap neighbouring gems: click one then another, or drag it', 13, EmberAnchor.bottomCenter, vm.Vector2(0, -8),
        color: dim));

  // Results (shown by the board script)
  scene
    ..addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Gems.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(420, 270))))
    ..addEntity(_text('ResultsTitle', '', 30, EmberAnchor.center, vm.Vector2(0, -92), color: const Color(0xFFFDE68A))..enabled = false)
    ..addEntity(_stars('ResultsStars', vm.Vector2(-64, -30), 48, enabled: false))
    ..addEntity(_text('ResultsScore', '', 15, EmberAnchor.center, vm.Vector2(0, 30))..enabled = false)
    ..addEntity(_button('RetryButton', 'Retry', 'restart', vm.Vector2(-130, 90), vm.Vector2(112, 40), enabled: false, color: const Color(0xFF94A3B8)))
    ..addEntity(_button('MenuButton', 'Menu', 'level:${Gems.title}', vm.Vector2(0, 90), vm.Vector2(112, 40), enabled: false, color: const Color(0xFF94A3B8)))
    ..addEntity(_button('NextButton', 'Next', '', vm.Vector2(130, 90), vm.Vector2(112, 40), hotkey: 'Enter', enabled: false));
  return scene;
}

/// Level 1 "Ember Mine": reach the score with five colours (learn the specials).
EmberScene buildGemsLevel1() => _levelScene('Level 1', {
      'levelTitle': 'Ember Mine',
      'moves': 18,
      'goal': 'score',
      'goalTarget': 2500,
      'colors': 5,
      'twoStars': 4500,
      'threeStars': 6500,
      'nextLevel': 'Level 2',
    });

/// Level 2 "Ruby Vault": collect 20 rubies with all six colours.
EmberScene buildGemsLevel2() => _levelScene('Level 2', {
      'levelTitle': 'Ruby Vault',
      'moves': 22,
      'goal': 'collect',
      'goalTarget': 20,
      'goalColor': 0,
      'colors': 6,
      'twoStars': 5000,
      'threeStars': 8000,
      'nextLevel': 'Level 3',
    });

/// Level 3 "Frozen Grotto": break every block of ice.
EmberScene buildGemsLevel3() => _levelScene('Level 3', {
      'levelTitle': 'Frozen Grotto',
      'moves': 25,
      'goal': 'ice',
      'colors': 5,
      'twoStars': 6000,
      'threeStars': 9000,
      'ice': '......../.##..##./.##..##./......../......../.##..##./.##..##./........',
      'nextLevel': '',
    });

EmberScene buildGemsTitle() {
  final scene = EmberScene(name: Gems.title);
  _addBackdrop(scene);
  // A few gems around the logo (swayed by the title script)
  for (final (x, y, k) in [(150.0, 110.0, 0), (250.0, 70.0, 2), (710.0, 70.0, 4), (810.0, 110.0, 5), (120.0, 330.0, 3), (840.0, 330.0, 1)]) {
    scene.addEntity(_sprite('Decor Gem', vm.Vector2(x, y), vm.Vector2(64, 64), 'gems.png', columns: 7, frame: k, z: 2)..tags.add('decor'));
  }
  scene.addEntity(_sprite('Decor Star', vm.Vector2(480, 200), vm.Vector2(48, 48), 'gems.png', columns: 7, frame: 6, z: 2)..tags.add('decor'));
  scene.addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'gems_title.ember')));
  scene.addEntity(_text('Logo', 'EMBER GEMS', 62, EmberAnchor.topCenter, vm.Vector2(0, 54), color: const Color(0xFFFDE68A)));
  scene.addEntity(_text('Tagline', 'Swap. Match three. Set off blasts, bombs and stars.', 16, EmberAnchor.topCenter, vm.Vector2(0, 132),
      color: const Color(0xFFE9D5FF)));
  for (var i = 1; i <= Gems.levels.length; i++) {
    final x = (i - 2) * 120.0;
    scene.addEntity(_button('Level$i Button', '$i', 'level:Level $i', vm.Vector2(x, 10), vm.Vector2(96, 64), hotkey: i == 1 ? 'Enter' : ''));
    scene.addEntity(_stars('Level$i Stars', vm.Vector2(x - 26, 64), 24));
  }
  scene.addEntity(_button('ResetButton', 'Reset progress', 'reset', vm.Vector2(0, -16), vm.Vector2(150, 30),
      anchor: EmberAnchor.bottomCenter, color: const Color(0xFF4C1D95)));
  return scene;
}

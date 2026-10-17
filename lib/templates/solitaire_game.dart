import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "Ember Solitaire": Klondike with drag-and-drop, one-click moves, undo,
/// hints, auto-finish and the bouncing-cards win. Draw 1 and Draw 3 tables;
/// the rules are Ember Script ([solitaireScripts]).
class Solitaire {
  static const String art = 'assets/templates/solitaire';
  static const String music = '$art/solitaire.wav';
  static const String title = 'Title';
  static const List<String> modes = ['Draw 1', 'Draw 3'];

  static const List<String> assetFiles = ['$art/cards.png', '$art/table.png', '$art/panel.png', music];

  /// Table layout (matches solitaire_table.ember).
  static const double col0 = 152, colStep = 108, topY = 84, tableY = 204;
  static const double cardW = 64, cardH = 88;

  /// Frames in cards.png.
  static const int back = 52, emptySlot = 53, recycleSlot = 54;
}

EmberEntity _card(String name, vm.Vector2 pos, int frame, {int z = 0, double rotation = 0, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(Transform2DComponent(
          position: pos, size: vm.Vector2(Solitaire.cardW, Solitaire.cardH), anchor: EmberAnchor.center, zIndex: z, rotation: rotation))
      ..addComponent(FlameSpriteComponent(assetPath: '${Solitaire.art}/cards.png')
        ..columns = 13
        ..rows = 5
        ..frame = frame);

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset, {Color color = const Color(0xFFFFFFFF)}) =>
    EmberEntity(name: name)..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size,
        {EmberAnchor anchor = EmberAnchor.center, String hotkey = '', Color color = const Color(0xFFFBBF24), bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UIButtonComponent(text: text, action: action, hotkey: hotkey, anchor: anchor, offset: offset, size: size, color: color));

void _addTable(EmberScene scene) {
  scene.addEntity(EmberEntity(name: 'Camera')
    ..addComponent(Transform2DComponent(position: vm.Vector2(480, 270), size: vm.Vector2.zero()))
    ..addComponent(Camera2DComponent(designWidth: 960, designHeight: 540, backgroundColor: const Color(0xFF0E3B24))));
  scene.addEntity(EmberEntity(name: 'Felt')
    ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2(960, 540), zIndex: -10))
    ..addComponent(FlameSpriteComponent(assetPath: '${Solitaire.art}/table.png')));
}

/// A table: empty-pile frames, the card template, the rules script, HUD and results.
EmberScene buildSolitaireTable(String mode) {
  final draw = mode == 'Draw 3' ? 3 : 1;
  final scene = EmberScene(name: mode);
  _addTable(scene);
  double colX(int c) => Solitaire.col0 + c * Solitaire.colStep;

  scene.addEntity(_card('Stock Slot', vm.Vector2(colX(0), Solitaire.topY), Solitaire.recycleSlot, z: -5));
  for (var f = 0; f < 4; f++) {
    scene.addEntity(_card('Foundation Slot', vm.Vector2(colX(3 + f), Solitaire.topY), Solitaire.emptySlot, z: -5));
  }
  for (var c = 0; c < 7; c++) {
    scene.addEntity(_card('Column Slot', vm.Vector2(colX(c), Solitaire.tableY), Solitaire.emptySlot, z: -5));
  }
  scene.addEntity(_card('Card', vm.Vector2(-500, -500), Solitaire.back, enabled: false)..tags.add('card'));
  scene.addEntity(EmberEntity(name: 'Table')..addComponent(ScriptComponent(scriptName: 'solitaire_table.ember', vars: {'draw': draw, 'mode': mode})));

  // Buttons on the left, numbers on the right
  const panel = Color(0xFF14532D);
  final buttons = [('UndoButton', 'Undo', 'undo'), ('HintButton', 'Hint', 'hint'), ('NewButton', 'New deal', 'restart'), ('MenuHud', 'Menu', 'level:${Solitaire.title}')];
  for (var i = 0; i < buttons.length; i++) {
    final (name, label, action) = buttons[i];
    scene.addEntity(_button(name, label, action, vm.Vector2(12, 170 + i * 46.0), vm.Vector2(100, 38), anchor: EmberAnchor.topLeft, color: panel));
  }
  scene.addEntity(_button('AutoButton', 'Finish', 'auto', vm.Vector2(12, 360), vm.Vector2(100, 38), anchor: EmberAnchor.topLeft, enabled: false));
  const dim = Color(0xFFBBF7D0);
  scene
    ..addEntity(_text('ModeText', mode, 16, EmberAnchor.topRight, vm.Vector2(-18, 150), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('ScoreLabel', 'SCORE', 12, EmberAnchor.topRight, vm.Vector2(-18, 186), color: dim))
    ..addEntity(_text('ScoreText', '0', 24, EmberAnchor.topRight, vm.Vector2(-18, 202)))
    ..addEntity(_text('MovesLabel', 'MOVES', 12, EmberAnchor.topRight, vm.Vector2(-18, 244), color: dim))
    ..addEntity(_text('MovesText', '0', 24, EmberAnchor.topRight, vm.Vector2(-18, 260)))
    ..addEntity(_text('TimeLabel', 'TIME', 12, EmberAnchor.topRight, vm.Vector2(-18, 302), color: dim))
    ..addEntity(_text('TimeText', '0:00', 24, EmberAnchor.topRight, vm.Vector2(-18, 318)))
    ..addEntity(_text('BestText', '', 11, EmberAnchor.bottomCenter, vm.Vector2(0, -8), color: dim));

  // Results (shown by the table script)
  scene
    ..addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Solitaire.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(480, 240))))
    ..addEntity(_text('ResultsTitle', '', 36, EmberAnchor.center, vm.Vector2(0, -74), color: const Color(0xFFFDE68A))..enabled = false)
    ..addEntity(_text('ResultsLine', '', 14, EmberAnchor.center, vm.Vector2(0, -16))..enabled = false)
    ..addEntity(_text('ResultsBest', '', 13, EmberAnchor.center, vm.Vector2(0, 14), color: dim)..enabled = false)
    ..addEntity(_button('AgainButton', 'Deal again', 'restart', vm.Vector2(-70, 72), vm.Vector2(124, 40), hotkey: 'Enter', enabled: false))
    ..addEntity(_button('MenuButton', 'Menu', 'level:${Solitaire.title}', vm.Vector2(70, 72), vm.Vector2(124, 40), enabled: false,
        color: const Color(0xFF94A3B8)));
  return scene;
}

EmberScene buildSolitaireTitle() {
  final scene = EmberScene(name: Solitaire.title);
  _addTable(scene);
  // A fanned hand of cards (Ace, King, Queen, Jack, Ten of different suits)
  final fan = [(39, -0.42), (12, -0.21), (24, 0.0), (49, 0.21), (9, 0.42)];
  for (var i = 0; i < fan.length; i++) {
    final (frame, angle) = fan[i];
    scene.addEntity(_card('Fan Card', vm.Vector2(480 + (i - 2) * 34.0, 250 + (i - 2).abs() * 8.0), frame, z: i, rotation: angle));
  }
  scene.addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'solitaire_title.ember')));
  scene
    ..addEntity(_text('Logo', 'EMBER SOLITAIRE', 54, EmberAnchor.topCenter, vm.Vector2(0, 44), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('Tagline', 'Klondike. Build each suit from Ace to King.', 16, EmberAnchor.topCenter, vm.Vector2(0, 114),
        color: const Color(0xFFDCFCE7)));
  for (var i = 0; i < Solitaire.modes.length; i++) {
    final mode = Solitaire.modes[i];
    final x = (i == 0 ? -1 : 1) * 120.0;
    scene.addEntity(_button('$mode Button', mode, 'level:$mode', vm.Vector2(x, 130), vm.Vector2(160, 52), hotkey: i == 0 ? 'Enter' : ''));
    scene.addEntity(_text('$mode Record', '', 13, EmberAnchor.center, vm.Vector2(x, 176), color: const Color(0xFFBBF7D0)));
  }
  scene.addEntity(_button('ResetButton', 'Reset records', 'reset', vm.Vector2(0, -14), vm.Vector2(150, 30),
      anchor: EmberAnchor.bottomCenter, color: const Color(0xFF14532D)));
  return scene;
}

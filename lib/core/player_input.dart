import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'gamepad.dart';
import 'input.dart';

/// Controls for one player: their half of the keyboard and their gamepad.
///
/// Player 1: WASD to move, W or Space jump, F attack, G special, H block,
/// Escape start. Player 2: arrows, Up jump, `,` (or Numpad 1) attack, `.`
/// (Numpad 2) special, `/` (Numpad 3) block, Enter start. Players 3 and 4
/// use gamepads only. On a pad: stick or D-pad to move, A jump, X / RB
/// attack, Y special, B / LB block, Start.
///
/// Recent directions and buttons are remembered for fighting-game motions:
/// `motion("236", "attack")` is a quarter circle forward + attack.
class PlayerControls {
  static final List<PlayerControls> players = List.generate(4, PlayerControls._);
  static PlayerControls of(int index) => players[index.clamp(0, players.length - 1)];

  final int index;
  PlayerControls._(this.index);

  static const actions = ['left', 'right', 'up', 'down', 'jump', 'attack', 'special', 'block', 'start'];

  static final _keys = <int, Map<String, List<LogicalKeyboardKey>>>{
    0: {
      'left': [LogicalKeyboardKey.keyA],
      'right': [LogicalKeyboardKey.keyD],
      'up': [LogicalKeyboardKey.keyW],
      'down': [LogicalKeyboardKey.keyS],
      'jump': [LogicalKeyboardKey.keyW, LogicalKeyboardKey.space],
      'attack': [LogicalKeyboardKey.keyF],
      'special': [LogicalKeyboardKey.keyG],
      'block': [LogicalKeyboardKey.keyH],
      'start': [LogicalKeyboardKey.escape],
    },
    1: {
      'left': [LogicalKeyboardKey.arrowLeft],
      'right': [LogicalKeyboardKey.arrowRight],
      'up': [LogicalKeyboardKey.arrowUp],
      'down': [LogicalKeyboardKey.arrowDown],
      'jump': [LogicalKeyboardKey.arrowUp],
      'attack': [LogicalKeyboardKey.comma, LogicalKeyboardKey.numpad1],
      'special': [LogicalKeyboardKey.period, LogicalKeyboardKey.numpad2],
      'block': [LogicalKeyboardKey.slash, LogicalKeyboardKey.numpad3],
      'start': [LogicalKeyboardKey.enter],
    },
  };

  static const _pad = <String, List<GamepadButton>>{
    'left': [GamepadButton.dpadLeft],
    'right': [GamepadButton.dpadRight],
    'up': [GamepadButton.dpadUp],
    'down': [GamepadButton.dpadDown],
    'jump': [GamepadButton.a],
    'attack': [GamepadButton.x, GamepadButton.rightBumper],
    'special': [GamepadButton.y],
    'block': [GamepadButton.b, GamepadButton.leftBumper],
    'start': [GamepadButton.start],
  };

  InputManager get _in => InputManager.instance;
  GamepadInput get _gp => GamepadInput.instance;

  bool get usingPad => _gp.connected(index);

  /// Directions also come from the stick (past half way).
  bool _stickDir(String action) {
    if (!_gp.connected(index)) return false;
    final s = _gp.stick(index);
    return switch (action) {
      'left' => s.x < -0.5,
      'right' => s.x > 0.5,
      'up' => s.y < -0.5,
      'down' => s.y > 0.5,
      _ => false,
    };
  }

  final Set<String> _stickWasDown = {};

  bool down(String action) {
    for (final k in _keys[index]?[action] ?? const <LogicalKeyboardKey>[]) {
      if (_in.isKeyPressed(k)) return true;
    }
    for (final b in _pad[action] ?? const <GamepadButton>[]) {
      if (_gp.isDown(index, b)) return true;
    }
    return _stickDir(action);
  }

  bool pressed(String action) {
    for (final k in _keys[index]?[action] ?? const <LogicalKeyboardKey>[]) {
      if (_in.isKeyJustPressed(k)) return true;
    }
    for (final b in _pad[action] ?? const <GamepadButton>[]) {
      if (_gp.justPressed(index, b)) return true;
    }
    return _stickDir(action) && !_stickWasDown.contains(action);
  }

  bool released(String action) {
    for (final k in _keys[index]?[action] ?? const <LogicalKeyboardKey>[]) {
      if (_in.isKeyJustReleased(k)) return true;
    }
    for (final b in _pad[action] ?? const <GamepadButton>[]) {
      if (_gp.justReleased(index, b)) return true;
    }
    return !_stickDir(action) && _stickWasDown.contains(action);
  }

  /// Movement as a Vec2: x right, y down (keys, D-pad or stick).
  vm.Vector2 get move {
    final keys = vm.Vector2((down('right') ? 1.0 : 0.0) - (down('left') ? 1.0 : 0.0), (down('down') ? 1.0 : 0.0) - (down('up') ? 1.0 : 0.0));
    if (keys.length2 > 0) return keys.length2 > 1 ? keys.normalized() : keys;
    return _gp.connected(index) ? _gp.stick(index) : vm.Vector2.zero();
  }

  // --- History for motions --------------------------------------------------

  int _frame = 0;
  final List<(int, int)> _dirs = []; // (numpad direction, frame), when it changed
  final List<(String, int)> _buttons = []; // (action, frame) presses

  static int _numpad(vm.Vector2 m) {
    final x = m.x > 0.4 ? 1 : (m.x < -0.4 ? -1 : 0);
    final y = m.y > 0.4 ? -1 : (m.y < -0.4 ? 1 : 0); // up is positive in numpad notation
    return 5 + x + y * 3;
  }

  /// Called once per frame (before presses are cleared).
  void record() {
    _frame++;
    final d = _numpad(move);
    if (_dirs.isEmpty || _dirs.last.$1 != d) _dirs.add((d, _frame));
    for (final a in const ['attack', 'special', 'block', 'jump']) {
      if (pressed(a)) _buttons.add((a, _frame));
    }
    while (_dirs.length > 32) {
      _dirs.removeAt(0);
    }
    while (_buttons.length > 32) {
      _buttons.removeAt(0);
    }
    for (final a in const ['left', 'right', 'up', 'down']) {
      if (_stickDir(a)) {
        _stickWasDown.add(a);
      } else {
        _stickWasDown.remove(a);
      }
    }
  }

  /// [action] was pressed in the last [frames] frames (a buffered press).
  bool buffered(String action, {int frames = 6}) => pressed(action) || _buttons.any((b) => b.$1 == action && _frame - b.$2 < frames);

  /// True when the directions [sequence] (numpad notation, 6 = toward
  /// the way the player faces) were entered in order within [window] frames,
  /// ending with [button] being pressed (now, or in the last few frames).
  bool motion(String sequence, String button, {bool facingRight = true, int window = 20}) {
    if (!buffered(button, frames: 4)) return false;
    int mirror(int d) => facingRight ? d : (d % 3 == 1 ? d + 2 : (d % 3 == 0 ? d - 2 : d));
    final wanted = [for (final ch in sequence.split('')) int.parse(ch)];
    final now = _numpad(move);
    final history = [..._dirs.where((d) => _frame - d.$2 <= window).map((d) => mirror(d.$1)), mirror(now)];
    var i = wanted.length - 1;
    for (var k = history.length - 1; k >= 0 && i >= 0; k--) {
      if (history[k] == wanted[i]) i--;
    }
    return i < 0;
  }

  void clearHistory() {
    _dirs.clear();
    _buttons.clear();
    _stickWasDown.clear();
  }

  static void recordAll() {
    for (final p in players) {
      p.record();
    }
  }

  static void resetAll() {
    for (final p in players) {
      p.clearHistory();
    }
  }
}

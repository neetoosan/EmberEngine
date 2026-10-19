import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gamepads/gamepads.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

export 'package:gamepads/gamepads.dart' show GamepadButton, GamepadAxis;

/// One gamepad's state this frame.
class PadState {
  final String id;
  final Set<GamepadButton> down = {};
  final Set<GamepadButton> pressed = {};
  final Set<GamepadButton> released = {};
  final Map<GamepadAxis, double> axes = {};
  PadState(this.id);
}

/// Xbox / PlayStation / generic gamepads (Windows, Android, web, macOS,
/// Linux) through the `gamepads` package's normalized buttons and axes.
/// Pads become players 1, 2, … in the order they are first used.
class GamepadInput {
  static final GamepadInput instance = GamepadInput._();
  GamepadInput._();

  /// Stick values closer to the centre than this count as 0.
  static const double deadZone = 0.22;

  final List<PadState> pads = [];
  StreamSubscription<NormalizedGamepadEvent>? _sub;

  /// Starts listening to real gamepads (does nothing where there are none).
  void start() {
    if (_sub != null) return;
    try {
      _sub = Gamepads.normalizedEvents.listen(_onEvent, onError: (Object e) => debugPrint('Ember: gamepads unavailable: $e'));
    } catch (e) {
      debugPrint('Ember: gamepads unavailable: $e');
    }
  }

  PadState _padById(String id) {
    for (final p in pads) {
      if (p.id == id) return p;
    }
    final p = PadState(id);
    pads.add(p);
    return p;
  }

  PadState _padFor(int player) {
    while (pads.length <= player) {
      pads.add(PadState('virtual ${pads.length + 1}'));
    }
    return pads[player];
  }

  void _onEvent(NormalizedGamepadEvent e) {
    final p = _padById(e.gamepadId);
    final b = e.button;
    if (b != null) {
      _set(p, b, e.value > 0.5);
    } else if (e.axis != null) {
      p.axes[e.axis!] = e.value;
    }
  }

  void _set(PadState p, GamepadButton b, bool on) {
    if (on && p.down.add(b)) p.pressed.add(b);
    if (!on && p.down.remove(b)) p.released.add(b);
  }

  /// For tests and on-screen pads: press or release a button of [player] (0 = player 1).
  void press(int player, GamepadButton b) => _set(_padFor(player), b, true);
  void release(int player, GamepadButton b) => _set(_padFor(player), b, false);
  void setAxis(int player, GamepadAxis a, double value) => _padFor(player).axes[a] = value;

  bool connected(int player) => player < pads.length;
  bool isDown(int player, GamepadButton b) => player < pads.length && pads[player].down.contains(b);
  bool justPressed(int player, GamepadButton b) => player < pads.length && pads[player].pressed.contains(b);
  bool justReleased(int player, GamepadButton b) => player < pads.length && pads[player].released.contains(b);

  double axis(int player, GamepadAxis a) {
    if (player >= pads.length) return 0;
    final v = pads[player].axes[a] ?? 0;
    return v.abs() < deadZone ? 0 : v;
  }

  /// A stick as a Vec2 with x right and y down (the D-pad counts too for the left stick).
  vm.Vector2 stick(int player, {bool right = false}) {
    var x = axis(player, right ? GamepadAxis.rightStickX : GamepadAxis.leftStickX);
    var y = -axis(player, right ? GamepadAxis.rightStickY : GamepadAxis.leftStickY);
    if (!right) {
      if (isDown(player, GamepadButton.dpadLeft)) x = -1;
      if (isDown(player, GamepadButton.dpadRight)) x = 1;
      if (isDown(player, GamepadButton.dpadUp)) y = -1;
      if (isDown(player, GamepadButton.dpadDown)) y = 1;
    }
    final v = vm.Vector2(x, y);
    if (v.length2 > 1) v.normalize();
    return v;
  }

  void endFrame() {
    for (final p in pads) {
      p.pressed.clear();
      p.released.clear();
    }
  }

  void reset() {
    for (final p in pads) {
      p.down.clear();
      p.pressed.clear();
      p.released.clear();
      p.axes.clear();
    }
  }

  /// Forgets every pad (tests).
  @visibleForTesting
  void clear() => pads.clear();
}

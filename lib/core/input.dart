import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

/// High-level action enumeration for Engine actions.
enum EngineAction {
  moveForward,
  moveBackward,
  moveLeft,
  moveRight,
  jump,
  fire,
  sprint,
  crouch,
  interact,
}

/// High-level action-based Input Abstraction for Ember Engine.
class Input {
  Input._();
  static final InputManager instance = InputManager._singleton;

  static void onKeyDown(LogicalKeyboardKey key) => InputManager._singleton.onKeyDown(key);
  static void onKeyUp(LogicalKeyboardKey key) => InputManager._singleton.onKeyUp(key);
  static void onMouseMove(vm.Vector2 pos, vm.Vector2 delta) => InputManager._singleton.onMouseMove(pos, delta);
  static void onMouseDown(int button) => InputManager._singleton.onMouseDown(button);
  static void onMouseUp(int button) => InputManager._singleton.onMouseUp(button);

  static void bindHardwareKeyboard() => InputManager._singleton.bindHardwareKeyboard();

  static bool get isPointerLocked => InputManager._singleton.isPointerLocked;
  static set isPointerLocked(bool locked) => InputManager._singleton.isPointerLocked = locked;

  static void setVirtualJoystick(vm.Vector2 axis) => InputManager._singleton.setVirtualJoystick(axis);
  static void setVirtualAction(dynamic action, bool pressed) => InputManager._singleton.setVirtualAction(action, pressed);

  static bool isKeyPressed(LogicalKeyboardKey key) => InputManager._singleton.isKeyPressed(key);
  static bool isKeyJustPressed(LogicalKeyboardKey key) => InputManager._singleton.isKeyJustPressed(key);
  static bool isKeyJustReleased(LogicalKeyboardKey key) => InputManager._singleton.isKeyJustReleased(key);

  static bool isActionPressed(dynamic action) => InputManager._singleton.isActionPressed(action);
  static bool isActionJustPressed(dynamic action) => InputManager._singleton.isActionJustPressed(action);
  static bool isActionJustReleased(dynamic action) => InputManager._singleton.isActionJustReleased(action);

  static double getAxis(String axisName) => InputManager._singleton.getAxis(axisName);
  static vm.Vector2 getMovementVector() => InputManager._singleton.getMovementVector();

  static vm.Vector2 get mousePosition => InputManager._singleton.mousePosition;
  static vm.Vector2 get mouseDelta => InputManager._singleton.mouseDelta;

  static bool isMouseButtonPressed(int button) => InputManager._singleton.isMouseButtonPressed(button);
  static bool isMouseButtonJustPressed(int button) => InputManager._singleton.isMouseButtonJustPressed(button);

  static void endFrame() => InputManager._singleton.endFrame();
  static void reset() => InputManager._singleton.reset();
}

/// Central Input Manager Instance providing query and action mappings.
class InputManager {
  static final InputManager _singleton = InputManager._();
  static InputManager get instance => _singleton;
  InputManager._();
  factory InputManager() => _singleton;

  // Raw key states
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  final Set<LogicalKeyboardKey> _justPressedKeys = {};
  final Set<LogicalKeyboardKey> _justReleasedKeys = {};

  // Mouse states
  vm.Vector2 _mousePosition = vm.Vector2.zero();
  vm.Vector2 _mouseDelta = vm.Vector2.zero();
  final Set<int> _mouseButtons = {};
  final Set<int> _justPressedMouseButtons = {};
  bool isPointerLocked = false;

  /// Pointer position in 2D world coordinates (set by the 2D viewport while playing).
  vm.Vector2 mouseWorldPosition = vm.Vector2.zero();

  // Virtual mobile touch inputs
  vm.Vector2 _virtualJoystickAxis = vm.Vector2.zero();
  final Set<String> _virtualActions = {};
  final Set<String> _virtualJustPressedActions = {};
  final Set<String> _virtualJustReleasedActions = {};

  // Action bindings
  final Map<EngineAction, List<LogicalKeyboardKey>> _actionKeyMap = {
    EngineAction.jump: [LogicalKeyboardKey.space],
    EngineAction.fire: [LogicalKeyboardKey.keyF, LogicalKeyboardKey.enter],
    EngineAction.interact: [LogicalKeyboardKey.keyE],
    EngineAction.sprint: [LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight],
    EngineAction.crouch: [LogicalKeyboardKey.keyC, LogicalKeyboardKey.controlLeft],
    EngineAction.moveLeft: [LogicalKeyboardKey.keyA, LogicalKeyboardKey.arrowLeft],
    EngineAction.moveRight: [LogicalKeyboardKey.keyD, LogicalKeyboardKey.arrowRight],
    EngineAction.moveForward: [LogicalKeyboardKey.keyW, LogicalKeyboardKey.arrowUp],
    EngineAction.moveBackward: [LogicalKeyboardKey.keyS, LogicalKeyboardKey.arrowDown],
  };

  static String _actionName(dynamic action) {
    if (action is EngineAction) return action.name;
    if (action is String) return action;
    return action.toString();
  }

  static EngineAction? _parseEngineAction(dynamic action) {
    if (action is EngineAction) return action;
    if (action is String) {
      for (final a in EngineAction.values) {
        if (a.name.toLowerCase() == action.toLowerCase() ||
            a.name.toLowerCase() == action.replaceAll('_', '').toLowerCase()) {
          return a;
        }
      }
    }
    return null;
  }

  /// Registered action bindings map.
  Map<EngineAction, List<LogicalKeyboardKey>> get actions => Map.unmodifiable(_actionKeyMap);

  // --- Keyboard Event Dispatchers ---

  void onKeyDown(LogicalKeyboardKey key) {
    if (!_pressedKeys.contains(key)) {
      _justPressedKeys.add(key);
    }
    _pressedKeys.add(key);
  }

  void onKeyUp(LogicalKeyboardKey key) {
    _pressedKeys.remove(key);
    _justReleasedKeys.add(key);
  }

  void handleRawKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      onKeyDown(event.logicalKey);
    } else if (event is KeyUpEvent) {
      onKeyUp(event.logicalKey);
    }
  }

  bool _hardwareBound = false;

  /// Routes every physical keyboard event into this manager, regardless of
  /// which widget has focus. Events are observed, never consumed, so editor
  /// shortcuts and text fields keep working. Safe to call more than once.
  void bindHardwareKeyboard() {
    if (_hardwareBound) return;
    _hardwareBound = true;
    HardwareKeyboard.instance.addHandler((event) {
      handleRawKeyEvent(event);
      return false;
    });
  }

  // --- Mouse Event Dispatchers ---

  void onMouseMove(vm.Vector2 pos, vm.Vector2 delta) {
    _mousePosition = pos;
    _mouseDelta += delta;
  }

  void injectMouseDelta(vm.Vector2 delta) {
    onMouseMove(_mousePosition, delta);
  }

  void onMouseDown(int button) {
    if (!_mouseButtons.contains(button)) {
      _justPressedMouseButtons.add(button);
    }
    _mouseButtons.add(button);
  }

  void onMouseUp(int button) {
    _mouseButtons.remove(button);
  }

  // --- Virtual Mobile Touch Dispatchers ---

  void setVirtualJoystick(vm.Vector2 axis) {
    _virtualJoystickAxis = axis;
  }

  void setVirtualAxis(vm.Vector2 axis) => setVirtualJoystick(axis);

  void setVirtualAction(dynamic action, bool pressed) {
    final actName = _actionName(action);
    if (pressed) {
      if (!_virtualActions.contains(actName)) {
        _virtualJustPressedActions.add(actName);
      }
      _virtualActions.add(actName);
    } else {
      if (_virtualActions.contains(actName)) {
        _virtualJustReleasedActions.add(actName);
      }
      _virtualActions.remove(actName);
    }
  }

  void setVirtualButton(dynamic action, bool pressed) => setVirtualAction(action, pressed);

  // --- Query API ---

  /// Checks if a key is currently held down.
  bool isKeyPressed(LogicalKeyboardKey key) => _pressedKeys.contains(key);

  /// Checks if a key was pressed in this exact frame.
  bool isKeyJustPressed(LogicalKeyboardKey key) => _justPressedKeys.contains(key);

  /// Checks if a key was released in this exact frame.
  bool isKeyJustReleased(LogicalKeyboardKey key) => _justReleasedKeys.contains(key);

  /// Checks if a high-level action is held down (Keyboard + Virtual Touch).
  bool isActionPressed(dynamic action) {
    final actName = _actionName(action);
    if (_virtualActions.contains(actName)) return true;

    final engineAction = _parseEngineAction(action);
    if (engineAction != null) {
      final keys = _actionKeyMap[engineAction];
      if (keys != null) {
        for (final k in keys) {
          if (_pressedKeys.contains(k)) return true;
        }
      }
    }
    return false;
  }

  /// Checks if a high-level action was initiated this frame.
  bool isActionJustPressed(dynamic action) {
    final actName = _actionName(action);
    if (_virtualJustPressedActions.contains(actName)) return true;

    final engineAction = _parseEngineAction(action);
    if (engineAction != null) {
      final keys = _actionKeyMap[engineAction];
      if (keys != null) {
        for (final k in keys) {
          if (_justPressedKeys.contains(k)) return true;
        }
      }
    }
    return false;
  }

  /// Checks if a high-level action was released this frame.
  bool isActionJustReleased(dynamic action) {
    final actName = _actionName(action);
    if (_virtualJustReleasedActions.contains(actName)) return true;

    final engineAction = _parseEngineAction(action);
    if (engineAction != null) {
      final keys = _actionKeyMap[engineAction];
      if (keys != null) {
        for (final k in keys) {
          if (_justReleasedKeys.contains(k)) return true;
        }
      }
    }
    return false;
  }

  /// Gets 2D composite axis vector from 4 actions + virtual joystick.
  vm.Vector2 getAxis2D(dynamic rightAction, dynamic leftAction, dynamic upAction, dynamic downAction) {
    double x = 0.0;
    double y = 0.0;
    if (isActionPressed(rightAction)) x += 1.0;
    if (isActionPressed(leftAction)) x -= 1.0;
    if (isActionPressed(upAction)) y += 1.0;
    if (isActionPressed(downAction)) y -= 1.0;

    x += _virtualJoystickAxis.x;
    y += _virtualJoystickAxis.y;

    return vm.Vector2(x.clamp(-1.0, 1.0), y.clamp(-1.0, 1.0));
  }

  /// Gets normalized axis value between -1.0 and 1.0 (combines WASD/Arrows and Virtual Joystick).
  double getAxis(String axisName) {
    double val = 0.0;
    if (axisName == 'horizontal') {
      if (isActionPressed(EngineAction.moveLeft)) val -= 1.0;
      if (isActionPressed(EngineAction.moveRight)) val += 1.0;
      val += _virtualJoystickAxis.x;
    } else if (axisName == 'vertical') {
      if (isActionPressed(EngineAction.moveBackward)) val -= 1.0;
      if (isActionPressed(EngineAction.moveForward)) val += 1.0;
      val -= _virtualJoystickAxis.y; // Standard invert
    }
    return val.clamp(-1.0, 1.0);
  }

  /// Gets the 2D movement vector (normalized if length > 1).
  vm.Vector2 getMovementVector() {
    final x = getAxis('horizontal');
    final y = getAxis('vertical');
    final vec = vm.Vector2(x, y);
    if (vec.length2 > 1.0) {
      vec.normalize();
    }
    return vec;
  }

  /// Mouse position in screen pixels.
  vm.Vector2 get mousePosition => _mousePosition;

  /// Accumulated mouse delta since last frame tick.
  vm.Vector2 get mouseDelta => _mouseDelta;

  /// Checks if a mouse button is pressed (0: Primary/Left, 1: Middle, 2: Secondary/Right).
  bool isMouseButtonPressed(int button) => _mouseButtons.contains(button);

  /// Checks if a mouse button was just pressed this frame.
  bool isMouseButtonJustPressed(int button) => _justPressedMouseButtons.contains(button);

  /// Flushes frame-specific triggers at end of tick.
  void endFrame() {
    _justPressedKeys.clear();
    _justReleasedKeys.clear();
    _justPressedMouseButtons.clear();
    _virtualJustPressedActions.clear();
    _virtualJustReleasedActions.clear();
    _mouseDelta = vm.Vector2.zero();
  }

  /// Clears all input states (used on scene transition or unfocus).
  void reset() {
    _pressedKeys.clear();
    _justPressedKeys.clear();
    _justReleasedKeys.clear();
    _mouseButtons.clear();
    _justPressedMouseButtons.clear();
    _virtualActions.clear();
    _virtualJustPressedActions.clear();
    _virtualJustReleasedActions.clear();
    _virtualJoystickAxis = vm.Vector2.zero();
    _mouseDelta = vm.Vector2.zero();
  }
}

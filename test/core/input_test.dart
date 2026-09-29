import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/input.dart';

void main() {
  group('InputManager Action & Virtual Input Tests', () {
    setUp(() {
      InputManager.instance.reset();
    });

    test('Default actions have correct default key and button bindings', () {
      final input = InputManager.instance;
      expect(input.actions.containsKey(EngineAction.moveForward), isTrue);
      expect(input.actions.containsKey(EngineAction.jump), isTrue);
      expect(input.actions.containsKey(EngineAction.fire), isTrue);
      expect(input.actions.containsKey(EngineAction.sprint), isTrue);
    });

    test('Keyboard key down triggers action press', () {
      final input = InputManager.instance;

      // Simulate 'Key W' down
      input.handleRawKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyW,
          logicalKey: LogicalKeyboardKey.keyW,
          timeStamp: Duration.zero,
        ),
      );

      expect(input.isActionPressed(EngineAction.moveForward), isTrue);
      expect(input.isActionJustPressed(EngineAction.moveForward), isTrue);

      // Next frame after endFrame()
      input.endFrame();
      expect(input.isActionPressed(EngineAction.moveForward), isTrue);
      expect(input.isActionJustPressed(EngineAction.moveForward), isFalse);

      // Key Up
      input.handleRawKeyEvent(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.keyW,
          logicalKey: LogicalKeyboardKey.keyW,
          timeStamp: Duration.zero,
        ),
      );

      expect(input.isActionPressed(EngineAction.moveForward), isFalse);
      expect(input.isActionJustReleased(EngineAction.moveForward), isTrue);
    });

    test('Virtual touch joystick sets axis vector and button states', () {
      final input = InputManager.instance;

      input.setVirtualAxis(Vector2(0.8, -0.6));
      expect(input.getAxis2D(EngineAction.moveRight, EngineAction.moveLeft, EngineAction.moveForward, EngineAction.moveBackward).x, closeTo(0.8, 0.001));
      expect(input.getAxis2D(EngineAction.moveRight, EngineAction.moveLeft, EngineAction.moveForward, EngineAction.moveBackward).y, closeTo(-0.6, 0.001));

      input.setVirtualButton(EngineAction.jump, true);
      expect(input.isActionPressed(EngineAction.jump), isTrue);
      expect(input.isActionJustPressed(EngineAction.jump), isTrue);

      input.endFrame();
      input.setVirtualButton(EngineAction.jump, false);
      expect(input.isActionPressed(EngineAction.jump), isFalse);
      expect(input.isActionJustReleased(EngineAction.jump), isTrue);
    });

    test('Mouse delta and look axes accumulate correctly', () {
      final input = InputManager.instance;

      input.injectMouseDelta(Vector2(12.0, -8.0));
      expect(input.mouseDelta.x, closeTo(12.0, 0.001));
      expect(input.mouseDelta.y, closeTo(-8.0, 0.001));

      input.endFrame();
      expect(input.mouseDelta.x, 0.0);
      expect(input.mouseDelta.y, 0.0);
    });
  });
}

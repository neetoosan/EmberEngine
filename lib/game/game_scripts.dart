import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/game_script.dart';
import '../core/transform2d.dart';
import '../core/transform3d.dart';

/// Your game's own scripts.
///
/// Dart is compiled ahead of time, so gameplay code is written here (not in
/// the in-editor script tab, which is a scratchpad) and registered by name.
/// Registered scripts show up in the Inspector's "Script" dropdown on any
/// Script Component, run when you press Play in the editor, and are compiled
/// into exported games.
///
/// To add one: subclass [GameScript], then register it in [registerGameScripts].
void registerGameScripts() {
  ScriptRegistry.register('Hover Bob', () => HoverBob());
}

/// Example: floats an object up and down (works in 2D and 3D).
class HoverBob extends GameScript {
  double height = 0.25; // metres in 3D; multiplied by 40 for pixels in 2D
  double speed = 2.0;
  double _time = 0.0;
  double? _baseY;

  @override
  void onUpdate(double dt) {
    _time += dt;
    final offset = math.sin(_time * speed);

    final t3d = getComponent<Transform3DComponent>();
    if (t3d != null) {
      _baseY ??= t3d.position.y;
      t3d.position = vm.Vector3(t3d.position.x, _baseY! + offset * height, t3d.position.z);
      return;
    }

    final t2d = getComponent<Transform2DComponent>();
    if (t2d != null) {
      _baseY ??= t2d.position.y;
      t2d.position = vm.Vector2(t2d.position.x, _baseY! + offset * height * 40);
    }
  }
}

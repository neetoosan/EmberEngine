import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deleting the selected entity (any way) clears the selection, so the Inspector never shows a ghost', () {
    registerAllSubsystems();
    final engine = EmberEngine.instance;
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    final parent = EmberEntity(name: 'Parent')..addComponent(Transform2DComponent(position: Vector2.zero()));
    final child = EmberEntity(name: 'Child')..addComponent(Transform2DComponent(position: Vector2.zero()));
    parent.addChild(child);
    final other = EmberEntity(name: 'Other')..addComponent(Transform2DComponent(position: Vector2.zero()));
    engine.loadScene(EmberScene()
      ..addEntity(parent)
      ..addEntity(other));

    engine.selectEntity(other);
    engine.activeScene.removeEntity(other); // e.g. the ✕ in the Hierarchy
    expect(engine.selectedEntity, isNull);

    engine.selectEntity(child);
    engine.activeScene.removeEntity(parent); // removing a parent removes its children
    expect(engine.selectedEntity, isNull);
  });
}

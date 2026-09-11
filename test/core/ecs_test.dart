import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/component.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/inspectable.dart';

class MockLifecycleComponent extends EmberComponent {
  bool awoke = false;
  bool started = false;
  int updateCount = 0;
  int fixedUpdateCount = 0;
  bool destroyed = false;
  bool enabledState = true;

  @override
  void onAwake() => awoke = true;

  @override
  void onStart() => started = true;

  @override
  void onUpdate(double dt) => updateCount++;

  @override
  void onFixedUpdate(double fixedDt) => fixedUpdateCount++;

  @override
  void onEnable() => enabledState = true;

  @override
  void onDisable() => enabledState = false;

  @override
  void onDestroy() {
    destroyed = true;
    super.onDestroy();
  }

  @override
  Map<String, dynamic> toJson() => {'updateCount': updateCount};

  @override
  void fromJson(Map<String, dynamic> json) {
    updateCount = json['updateCount'] as int? ?? 0;
  }

  @override
  MockLifecycleComponent clone() => MockLifecycleComponent();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Ember Engine Core & ECS Tests', () {
    test('Entity creation and component management', () {
      final entity = EmberEntity(name: 'Hero');
      expect(entity.name, 'Hero');
      expect(entity.enabled, isTrue);

      final comp = MockLifecycleComponent();
      entity.addComponent(comp);

      expect(entity.hasComponent<MockLifecycleComponent>(), isTrue);
      expect(entity.getComponent<MockLifecycleComponent>(), same(comp));
      expect(comp.entity, same(entity));

      entity.awake();
      expect(comp.awoke, isTrue);

      entity.start();
      expect(comp.started, isTrue);

      entity.update(0.016);
      expect(comp.updateCount, 1);

      entity.fixedUpdate(0.016);
      expect(comp.fixedUpdateCount, 1);

      // Disable test
      comp.enabled = false;
      expect(comp.enabledState, isFalse);
      entity.update(0.016);
      expect(comp.updateCount, 1); // Not updated while disabled

      // Removal test
      entity.removeComponent(comp);
      expect(entity.hasComponent<MockLifecycleComponent>(), isFalse);
      expect(comp.destroyed, isTrue);
    });

    test('Hierarchy and Parent-Child Relations', () {
      final parent = EmberEntity(name: 'Parent');
      final child = EmberEntity(name: 'Child');
      final grandchild = EmberEntity(name: 'Grandchild');

      parent.addChild(child);
      child.addChild(grandchild);

      expect(child.parent, same(parent));
      expect(parent.children, contains(child));
      expect(grandchild.parent, same(child));

      final descendants = parent.getAllDescendants();
      expect(descendants.length, 2);
      expect(descendants, contains(child));
      expect(descendants, contains(grandchild));

      // Hierarchy destruction
      parent.destroy();
      expect(parent.children, isEmpty);
      expect(child.parent, isNull);
    });

    test('Transform 3D Local and World Matrix propagation', () {
      final parent = EmberEntity(name: 'Parent');
      final pTransform = parent.addComponent(Transform3DComponent(
        position: Vector3(10.0, 0.0, 0.0),
      ));

      final child = EmberEntity(name: 'Child');
      final cTransform = child.addComponent(Transform3DComponent(
        position: Vector3(0.0, 5.0, 0.0),
      ));

      parent.addChild(child);

      expect(pTransform.worldPosition, Vector3(10.0, 0.0, 0.0));
      // Child world position should combine parent position + child local position
      expect(cTransform.worldPosition, Vector3(10.0, 5.0, 0.0));

      // Move parent
      pTransform.position = Vector3(20.0, 0.0, 0.0);
      expect(cTransform.worldPosition, Vector3(20.0, 5.0, 0.0));

      // Forward, Right, Up vectors
      expect(pTransform.forward.z, closeTo(-1.0, 0.001));
      expect(pTransform.right.x, closeTo(1.0, 0.001));
      expect(pTransform.up.y, closeTo(1.0, 0.001));
    });

    test('Transform 2D and Anchor Offset', () {
      final t2d = Transform2DComponent(
        position: Vector2(100.0, 200.0),
        size: Vector2(64.0, 64.0),
        anchor: EmberAnchor.center,
      );

      expect(t2d.anchorOffset.x, 32.0);
      expect(t2d.anchorOffset.y, 32.0);

      t2d.anchor = EmberAnchor.topLeft;
      expect(t2d.anchorOffset.x, 0.0);
      expect(t2d.anchorOffset.y, 0.0);

      t2d.anchor = EmberAnchor.bottomRight;
      expect(t2d.anchorOffset.x, 64.0);
      expect(t2d.anchorOffset.y, 64.0);
    });

    test('Scene JSON Serialization and Deserialization', () {
      final scene = EmberScene(name: 'Test Scene');
      final entity = EmberEntity(name: 'TestEntity');
      entity.addComponent(Transform3DComponent(
        position: Vector3(1.0, 2.0, 3.0),
        scale: Vector3(2.0, 2.0, 2.0),
      ));
      scene.addEntity(entity);

      final json = scene.toJson();
      expect(json['name'], 'Test Scene');
      expect((json['entities'] as List).length, 1);

      final restoredScene = EmberScene.fromJson(json);
      expect(restoredScene.name, 'Test Scene');
      expect(restoredScene.rootEntities.length, 1);

      final restoredEntity = restoredScene.rootEntities.first;
      expect(restoredEntity.name, 'TestEntity');
      final restoredTransform = restoredEntity.getComponent<Transform3DComponent>();
      expect(restoredTransform, isNotNull);
      expect(restoredTransform!.position.x, 1.0);
      expect(restoredTransform.position.y, 2.0);
      expect(restoredTransform.position.z, 3.0);
      expect(restoredTransform.scale.x, 2.0);
    });

    test('Inspectable metadata reflection', () {
      final t3d = Transform3DComponent(
        position: Vector3(1.0, 2.0, 3.0),
      );

      final props = t3d.inspectableProperties;
      expect(props.isNotEmpty, isTrue);

      final posProp = props.firstWhere((p) => p.name == 'position');
      expect(posProp.type, InspectableType.vector3);
      expect((posProp.value as Vector3).x, 1.0);

      // Mutate via setter
      posProp.setValue(Vector3(5.0, 6.0, 7.0));
      expect(t3d.position.x, 5.0);
    });

    test('Engine master loop play/pause/step/stop state restoration', () {
      final engine = EmberEngine.instance;
      engine.setMode(EngineMode.threeD);

      expect(engine.playState, PlayState.stopped);
      final initialCount = engine.entityCount;

      engine.play();
      expect(engine.playState, PlayState.playing);

      // Add dynamic object during play
      final dynamicObj = EmberEntity(name: 'Dynamic');
      engine.activeScene.addEntity(dynamicObj);
      expect(engine.entityCount, initialCount + 1);

      engine.pause();
      expect(engine.playState, PlayState.paused);

      engine.step();

      // Stop should restore pre-play snapshot!
      engine.stop();
      expect(engine.playState, PlayState.stopped);
      expect(engine.entityCount, initialCount);
    });
  });
}

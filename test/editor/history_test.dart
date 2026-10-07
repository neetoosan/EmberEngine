import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/ember_editor_app.dart';
import 'package:ember_engine/editor/history.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';

EmberEngine get engine => EmberEngine.instance;
EditorHistory get history => EditorHistory.instance;

EmberEntity box(String name, double x) =>
    EmberEntity(name: name)..addComponent(Transform2DComponent(position: Vector2(x, 0)));

double xOf(String name) => engine.activeScene.findByName(name)!.getComponent<Transform2DComponent>()!.position.x;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    engine.loadScene(EmberScene(name: 'History Test')..addEntity(box('A', 0))..addEntity(box('B', 50)));
    history.attach(engine);
    history.clear();
  });

  test('undo and redo property edits, adding and deleting entities', () {
    engine.activeScene.findByName('A')!.getComponent<Transform2DComponent>()!.position = Vector2(100, 0);
    history.flush();
    engine.activeScene.removeEntity(engine.activeScene.findByName('B')!);
    history.flush();
    engine.activeScene.addEntity(box('C', 7));
    history.flush();
    expect(history.undoCount, 3);

    expect(history.undo(), isTrue);
    expect(engine.activeScene.findByName('C'), isNull);
    expect(history.undo(), isTrue);
    expect(engine.activeScene.findByName('B'), isNotNull, reason: 'deleted entity comes back');
    expect(history.undo(), isTrue);
    expect(xOf('A'), 0);
    expect(history.undo(), isFalse);

    expect(history.redo(), isTrue);
    expect(xOf('A'), 100);
    expect(history.redo(), isTrue);
    expect(engine.activeScene.findByName('B'), isNull);
    // A new edit after undo drops the redo steps
    history.undo();
    engine.activeScene.findByName('A')!.getComponent<Transform2DComponent>()!.position = Vector2(5, 0);
    history.flush();
    expect(history.canRedo, isFalse);
  });

  test('rapid changes (dragging, scrubbing a number) become one step', () {
    final t = engine.activeScene.findByName('A')!.getComponent<Transform2DComponent>()!;
    for (var i = 1; i <= 30; i++) {
      t.position = Vector2(i * 2.0, 0); // no settle in between
    }
    history.flush();
    expect(history.undoCount, 1);
    history.undo();
    expect(xOf('A'), 0);
  });

  test('keeps the selection and ignores changes made while playing', () {
    engine.selectEntity(engine.activeScene.findByName('A'));
    engine.activeScene.findByName('A')!.addComponent(HealthComponent());
    history.flush();
    history.undo();
    expect(engine.selectedEntity?.name, 'A', reason: 'selection follows the restored entity');
    expect(engine.activeScene.findByName('A')!.getComponent<HealthComponent>(), isNull);

    history.redo();
    engine.play();
    engine.activeScene.findByName('A')!.getComponent<Transform2DComponent>()!.position = Vector2(999, 0);
    history.flush();
    engine.stop();
    history.flush();
    expect(history.undoCount, 1, reason: 'play-mode changes are not edits');
    expect(history.undo(), isTrue);
    expect(engine.activeScene.findByName('A')!.getComponent<HealthComponent>(), isNull, reason: 'history survives Play/Stop');
  });

  test('switching to another scene starts a fresh history', () {
    engine.activeScene.findByName('A')!.getComponent<Transform2DComponent>()!.position = Vector2(3, 0);
    history.flush();
    engine.loadScene(EmberScene(name: 'Other')..addEntity(box('Z', 0)));
    expect(history.canUndo, isFalse);
  });

  testWidgets('editor: Delete then Ctrl+Z restores; Ctrl+Z in a text field stays in the field', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    EditorHistory.settleTime = const Duration(milliseconds: 50);
    addTearDown(() => EditorHistory.settleTime = const Duration(milliseconds: 400));
    final project = TemplateCatalog.getByType(ProjectTemplateType.platformer2d).createProject(name: 'Undo Test');
    await tester.pumpWidget(EmberEditorApp(initialProject: project, startInLauncher: false));
    await tester.pump(const Duration(milliseconds: 100));
    history.clear();

    final name = engine.activeScene.allEntities.first.name;
    engine.selectEntity(engine.activeScene.allEntities.first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.activeScene.findByName(name), isNull);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('undo-button'))).onPressed, isNotNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.activeScene.findByName(name), isNotNull);

    // Redo with the top-bar button
    await tester.tap(find.byKey(const ValueKey('redo-button')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.activeScene.findByName(name), isNull);

    // In a text field, Ctrl+Z is the field's own undo
    history.undo();
    await tester.pump(const Duration(milliseconds: 100));
    final steps = history.undoCount;
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(history.undoCount, steps);
    expect(engine.activeScene.findByName(name), isNotNull);
  });
}

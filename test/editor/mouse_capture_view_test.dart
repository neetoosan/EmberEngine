import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/mouse_lock.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/editor/panels/viewport_container.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/physics/character_controller3d.dart';
import 'package:ember_engine/subsystems/three_d/camera3d.dart';

class FakeLock implements MouseLockBackend {
  bool on = false;
  @override
  bool get supported => true;
  @override
  bool get locked => on;
  @override
  void lock() => on = true;
  @override
  void unlock() => on = false;
  @override
  (double, double) takeDelta() => (0, 0);
}

void main() {
  testWidgets('a first-person game waits behind "Click to play"; a click captures the mouse, Escape frees it', (tester) async {
    registerAllSubsystems();
    final fake = FakeLock();
    MouseLock.backendOverride = fake;
    Input.bindHardwareKeyboard();
    final engine = EmberEngine.instance;
    engine.setMode(EngineMode.threeD);
    final player = EmberEntity(name: 'Player')
      ..addComponent(Transform3DComponent(position: Vector3(0, 0.9, 0)))
      ..addComponent(CameraComponent())
      ..addComponent(CharacterController3DComponent())
      ..addComponent(ScriptComponent(scriptName: 'FPS Player Controller'));
    engine.loadScene(EmberScene(name: 'S')..addEntity(player));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ViewportContainer(engine: engine))));
    engine.play();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(MouseLock.wanted, isTrue);
    expect(engine.waitingForMouse, isTrue);
    await tester.pump(const Duration(milliseconds: 50)); // the overlay shows on the next frame
    expect(find.text('Click to play'), findsOneWidget);

    final time = engine.levelTime;
    await tester.pump(const Duration(milliseconds: 200));
    expect(engine.levelTime, time, reason: 'the game waits');

    await tester.tapAt(tester.getCenter(find.byType(ViewportContainer)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.on, isTrue);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Click to play'), findsNothing);
    expect(engine.levelTime, greaterThan(time), reason: 'running again');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.on, isFalse, reason: 'Escape released the mouse');
    expect(find.text('Click to play'), findsOneWidget);

    engine.stop();
    MouseLock.backendOverride = null;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('UI buttons can be clicked in a 3D game (Ember Arena: Play on the title screen)', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    registerAllSubsystems();
    MouseLock.backendOverride = FakeLock();
    final engine = EmberEngine.instance;
    final project = TemplateCatalog.getByType(ProjectTemplateType.arena).createProject(name: 'Arena');
    EmberScripts.instance.loadAll(project.scripts);
    final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
    engine.sceneLibrary = () => levels;
    engine.setMode(EngineMode.threeD);
    engine.loadScene(project.activeScene);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ViewportContainer(engine: engine))));
    engine.play();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.activeScene.name, 'Title');
    // The Play button sits 40 px below the middle of the view
    await tester.tapAt(tester.getCenter(find.byType(ViewportContainer)) + const Offset(0, 40));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(engine.activeScene.name, 'Arena');
    engine.stop();
    MouseLock.backendOverride = null;
    await tester.pumpWidget(const SizedBox());
  });
}

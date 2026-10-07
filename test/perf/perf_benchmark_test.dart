// ignore_for_file: avoid_print
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/subsystems/three_d/components3d.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/subsystems/three_d/renderer3d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/templates/quest_game.dart';

/// Rough performance numbers (printed) with generous limits so regressions show.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerAllSubsystems);

  test('2D: engine tick on a crowded platformer level', () {
    final engine = EmberEngine.instance;
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    final scene = buildQuestLevel1();
    // 300 extra coins to make scene scans visible
    for (var i = 0; i < 300; i++) {
      scene.addEntity(EmberEntity(name: 'ExtraCoin_$i', tags: {'coin'})
        ..addComponent(Transform2DComponent(position: Vector2(200.0 + i * 11, 100), size: Vector2(24, 24)))
        ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/coin.png', columns: 4))
        ..addComponent(FlameHitbox2DComponent(size: Vector2(18, 20), isSolid: false)));
    }
    engine.loadScene(scene);
    engine.step();
    var notifications = 0;
    void count() => notifications++;
    engine.addListener(count);

    final sw = Stopwatch()..start();
    for (var i = 0; i < 600; i++) {
      engine.step();
    }
    sw.stop();
    engine.removeListener(count);
    final perTick = sw.elapsedMicroseconds / 600 / 1000;
    print('2D tick: ${perTick.toStringAsFixed(3)} ms/frame over 600 frames, '
        '${scene.allEntities.length} entities, engine notifications: $notifications');
    engine.stop();
    expect(perTick, lessThan(16));
  });

  test('3D: software renderer frame cost (FPS arena)', () {
    final engine = EmberEngine.instance;
    engine.stop();
    engine.setMode(EngineMode.threeD);
    engine.loadScene(TemplateCatalog.getByType(ProjectTemplateType.fps3d).createProject(name: 'Bench').activeScene);
    final sw = Stopwatch()..start();
    for (var i = 0; i < 60; i++) {
      final recorder = ui.PictureRecorder();
      Renderer3D.renderScene(
        canvas: Canvas(recorder),
        size: const Size(1280, 720),
        engine: engine,
        cameraPosition: Vector3(6, 5, 14),
        cameraRotation: Quaternion.axisAngle(Vector3(0, 1, 0), 0.4),
      );
      recorder.endRecording().dispose();
    }
    sw.stop();
    final perFrame = sw.elapsedMicroseconds / 60 / 1000;
    print('3D render: ${perFrame.toStringAsFixed(3)} ms/frame');
    expect(perFrame, lessThan(50));
  });

  test('3D: 400 objects (spheres, cubes, floor) stay interactive', () {
    final engine = EmberEngine.instance;
    engine.stop();
    engine.setMode(EngineMode.threeD);
    final scene = EmberScene(name: 'Stress');
    var i = 0;
    for (var x = -10; x < 10; x++) {
      for (var z = -10; z < 10; z++) {
        scene.addEntity(EmberEntity(name: 'M${i++}')
          ..addComponent(Transform3DComponent(position: Vector3(x * 1.6, 0.5, z * 1.6)))
          ..addComponent(MeshRenderer3DComponent(primitiveType: i % 3 == 0 ? MeshPrimitiveType.cube : MeshPrimitiveType.sphere)));
      }
    }
    engine.loadScene(scene);
    final sw = Stopwatch();
    for (var f = 0; f < 35; f++) {
      if (f == 5) sw.start(); // the first frames include compiling the renderer; time the steady state
      final recorder = ui.PictureRecorder();
      Renderer3D.renderScene(
        canvas: Canvas(recorder),
        size: const Size(1280, 720),
        engine: engine,
        cameraPosition: Vector3(6, 5, 14),
        cameraRotation: Quaternion.axisAngle(Vector3(0, 1, 0), 0.4),
      );
      recorder.endRecording().dispose();
    }
    final perFrame = sw.elapsedMicroseconds / 30 / 1000;
    print('3D stress render (after warm-up): ${perFrame.toStringAsFixed(3)} ms/frame, ${Renderer3D.stats.triangles} triangles, '
        '${Renderer3D.stats.culledObjects}/${Renderer3D.stats.objects} objects culled');
    // ~25-35 ms alone in the test VM, more when the suite runs in parallel (the old
    // renderer took ~190 ms); release builds are faster
    expect(perFrame, lessThan(100), reason: 'regression guard for a 400-object scene');
  });
}

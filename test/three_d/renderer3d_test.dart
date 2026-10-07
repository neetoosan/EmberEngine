import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/subsystems/three_d/components3d.dart';
import 'package:ember_engine/subsystems/three_d/material.dart';
import 'package:ember_engine/subsystems/three_d/renderer3d.dart';

EmberEngine get engine => EmberEngine.instance;
const size = Size(200, 150);

EmberEntity mesh(MeshPrimitiveType type, Vector3 at, Color color, {Vector3? scale}) => EmberEntity(name: type.name)
  ..addComponent(Transform3DComponent(position: at, scale: scale))
  ..addComponent(MeshRenderer3DComponent(primitiveType: type, material: Material3D(color: color)));

/// Renders the active scene from [camera] (looking down -Z) and returns RGBA pixels.
Future<(ByteData, int)> render(WidgetTester tester, {Vector3? camera}) async {
  final recorder = ui.PictureRecorder();
  Renderer3D.renderScene(
    canvas: Canvas(recorder),
    size: size,
    engine: engine,
    cameraPosition: camera ?? Vector3(0, 0, 5),
    cameraRotation: Quaternion.identity(),
    showGrid: false,
    showSelection: false,
  );
  final picture = recorder.endRecording();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    return image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  return (bytes!, size.width.toInt());
}

Color pixel((ByteData, int) img, int x, int y) {
  final (data, w) = img;
  final i = (y * w + x) * 4;
  return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

bool reddish(Color c) => c.r > 0.35 && c.r > c.g * 2 && c.r > c.b * 2;
bool bluish(Color c) => c.b > 0.35 && c.b > c.r * 2 && c.b > c.g * 1.5;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.threeD);
  });

  testWidgets('a lit cube in front of the camera shows its colour; only front faces are drawn', (tester) async {
    engine.loadScene(EmberScene()..addEntity(mesh(MeshPrimitiveType.cube, Vector3.zero(), const Color(0xFFFF2020))));
    final img = await render(tester);
    expect(reddish(pixel(img, 100, 75)), isTrue, reason: '${pixel(img, 100, 75)}');
    expect(pixel(img, 2, 2).a, 0, reason: 'nothing drawn in the corner');
    expect(Renderer3D.stats.triangles, lessThanOrEqualTo(6), reason: 'back faces culled (a cube shows at most 3 faces)');
  });

  testWidgets('nearer objects cover farther ones', (tester) async {
    engine.loadScene(EmberScene()
      ..addEntity(mesh(MeshPrimitiveType.cube, Vector3(0, 0, 2), const Color(0xFF2040FF)))
      ..addEntity(mesh(MeshPrimitiveType.cube, Vector3(0, 0, -2), const Color(0xFFFF2020), scale: Vector3.all(3))));
    final img = await render(tester, camera: Vector3(0, 0, 8));
    expect(bluish(pixel(img, 100, 75)), isTrue, reason: 'blue cube is in front: ${pixel(img, 100, 75)}');
    expect(reddish(pixel(img, 82, 75)), isTrue, reason: 'the big red cube shows around it: ${pixel(img, 82, 75)}');
  });

  testWidgets('objects outside the view are skipped entirely', (tester) async {
    engine.loadScene(EmberScene()
      ..addEntity(mesh(MeshPrimitiveType.sphere, Vector3(0, 0, 0), Colors.white))
      ..addEntity(mesh(MeshPrimitiveType.sphere, Vector3(200, 0, 0), Colors.white))
      ..addEntity(mesh(MeshPrimitiveType.sphere, Vector3(0, 0, 50), Colors.white))); // behind the camera
    await render(tester);
    expect(Renderer3D.stats.objects, 3);
    expect(Renderer3D.stats.culledObjects, 2);
  });

  testWidgets('a floor the camera stands on is clipped at the near plane but still drawn', (tester) async {
    engine.loadScene(EmberScene()
      ..addEntity(mesh(MeshPrimitiveType.plane, Vector3(0, -1, 0), const Color(0xFF20C040), scale: Vector3(80, 1, 80))));
    final img = await render(tester);
    final bottom = pixel(img, 100, 145);
    expect(bottom.g, greaterThan(bottom.r * 1.5), reason: 'floor visible under the camera: $bottom');
  });

  testWidgets('a floor is one even colour and nothing is drawn outside the viewport', (tester) async {
    engine.loadScene(EmberScene()
      ..addEntity(mesh(MeshPrimitiveType.plane, Vector3(0, -1, 0), const Color(0xFF20C040), scale: Vector3(80, 1, 80))));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Viewport inset in a larger window, like the editor's centre panel
    canvas.translate(50, 50);
    Renderer3D.renderScene(
      canvas: canvas,
      size: size,
      engine: engine,
      cameraPosition: Vector3(0, 0, 5),
      cameraRotation: Quaternion.axisAngle(Vector3(0, 1, 0), 0.5),
      showGrid: false,
      showSelection: false,
    );
    final picture = recorder.endRecording();
    final data = (await tester.runAsync(() async {
      final image = await picture.toImage(300, 250);
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    }))!;
    final img = (data, 300);
    expect(pixel(img, 20, 230).a, 0, reason: 'left of the viewport stays empty');
    expect(pixel(img, 150, 240).a, 0, reason: 'below the viewport stays empty');
    final floor = {for (var x = 55; x < 250; x += 15) pixel(img, x, 190).toARGB32()};
    expect(floor, hasLength(1), reason: 'no seam between the floor triangles');
  });

  testWidgets('spheres are smooth-shaded (colour blends across the surface), pyramids stay flat', (tester) async {
    engine.loadScene(EmberScene()..addEntity(mesh(MeshPrimitiveType.sphere, Vector3.zero(), Colors.white, scale: Vector3.all(3))));
    final img = await render(tester);
    final samples = {for (var x = 70; x <= 130; x += 6) pixel(img, x, 60).toARGB32()};
    expect(samples.length, greaterThan(5), reason: 'many distinct shades across the sphere');

    expect(MeshRenderer3DComponent(primitiveType: MeshPrimitiveType.sphere).mesh.smoothShading, isTrue);
    expect(MeshRenderer3DComponent(primitiveType: MeshPrimitiveType.cylinder).mesh.smoothShading, isTrue);
    expect(MeshRenderer3DComponent(primitiveType: MeshPrimitiveType.pyramid).mesh.smoothShading, isFalse);
  });
}

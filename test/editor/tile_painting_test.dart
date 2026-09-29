import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/editor/tile_brush.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/two_d/flame_viewport.dart';
import 'package:ember_engine/subsystems/two_d/tilemap_editor.dart';

void main() {
  setUpAll(registerAllSubsystems);

  testWidgets('pick a tile in the palette, then paint and erase in the viewport', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final engine = EmberEngine.instance;
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    final scene = EmberScene.starterFor('Paint', is2D: true);
    engine.loadScene(scene);
    final map = scene.findByName('Level')!.getComponent<FlameTileMapComponent>()!;
    TileBrush.instance.enabled = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SizedBox(height: 600, child: FlameViewportWidget(engine: engine)),
          SizedBox(height: 250, child: TilemapPaletteWidget(engine: engine)),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Painting into "Level"'), findsOneWidget);

    // Choose tile 3 and make it a "?" block
    await tester.tap(find.byTooltip('Tile 3 · solid'));
    await tester.pump();
    expect(TileBrush.instance.tileId, 3);
    expect(TileBrush.instance.enabled, isTrue);
    await tester.tap(find.byType(DropdownButton<TileKind>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('"?" block').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(map.kindOf(3), TileKind.question);

    // Paint: drag across the viewport above the floor
    final game = tester.state<State>(find.byType(FlameViewportWidget));
    expect(game, isNotNull);
    final viewportCenter = tester.getCenter(find.byType(FlameViewportWidget));
    final before = map.tiles.where((t) => t == 3).length;
    final gesture = await tester.startGesture(viewportCenter + const Offset(-60, -60), kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(120, 0));
    await gesture.up();
    await tester.pump();
    final painted = map.tiles.where((t) => t == 3).length;
    expect(painted, greaterThan(before), reason: 'left-drag painted tiles');

    // Erase with the right button over the same row
    final eraser = await tester.startGesture(
      viewportCenter + const Offset(-60, -60),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await eraser.moveBy(const Offset(120, 0));
    await eraser.up();
    await tester.pump();
    expect(map.tiles.where((t) => t == 3).length, lessThan(painted), reason: 'right-drag erased');

    TileBrush.instance.enabled = false;
  });
}

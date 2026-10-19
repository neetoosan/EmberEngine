import 'dart:ui';
import 'package:flame/game.dart' as flame;
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/two_d/flame_game.dart';
import 'package:vector_math/vector_math_64.dart';

EmberEngine get engine => EmberEngine.instance;

FlameTileMapComponent grid(String layout, {int cols = 8, int rows = 6}) =>
    FlameTileMapComponent(columns: cols, rows: rows, tileSize: 32, layout: layout, tiles: List.filled(cols * rows, 2), tileKinds: {2: TileKind.decoration});

EmberEntity mapEntity(FlameTileMapComponent m) => EmberEntity(name: 'Map')
  ..addComponent(Transform2DComponent(position: Vector2.zero(), size: Vector2(m.extent.width, m.extent.height)))
  ..addComponent(m);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() {
    Input.reset();
    engine.stop();
  });

  test('isometric and hex cells: centres and picking agree, and every cell is found from its centre', () {
    for (final layout in ['isometric', 'hex', 'square']) {
      final m = grid(layout);
      engine.loadScene(EmberScene(name: 'Grid')..addEntity(mapEntity(m)));
      for (var r = 0; r < m.rows; r++) {
        for (var c = 0; c < m.columns; c++) {
          final centre = m.cellRect(c, r).center;
          expect(m.cellAt(centre.dx, centre.dy), (c, r), reason: '$layout ($c, $r)');
          // A little off centre still finds it
          expect(m.cellAt(centre.dx + 5, centre.dy - 3), (c, r), reason: '$layout near ($c, $r)');
        }
      }
    }
    final iso = grid('isometric');
    expect(iso.cellRect(0, 0).size, const Size(64, 32), reason: 'diamonds twice as wide as tall');
    expect(iso.cellRect(1, 0).center - iso.cellRect(0, 0).center, const Offset(32, 16));
    expect(iso.cellRect(0, 1).center - iso.cellRect(0, 0).center, const Offset(-32, 16));
    final hex = grid('hex');
    expect(hex.neighbours(3, 2), hasLength(6));
    expect(hex.neighbours(3, 3), hasLength(6));
    expect((FlameTileMapComponent()..fromJson(iso.toJson())).layout, 'isometric');
  });

  test('paths go around blocked cells and missing tiles, on square, isometric and hex maps', () {
    for (final layout in ['square', 'isometric', 'hex']) {
      final m = grid(layout);
      // A wall down column 4 with one gap at row 5
      for (var r = 0; r < 5; r++) {
        m.blockedCells.add(r * m.columns + 4);
      }
      final path = m.findPath(1, 1, 6, 1)!;
      expect(path.last, (6, 1), reason: layout);
      expect(path.any((p) => p.$1 == 4 && p.$2 < 5), isFalse, reason: '$layout: not through the wall');
      expect(path.any((p) => p == (4, 5)), isTrue, reason: '$layout: through the gap');
      m.blockedCells.add(5 * m.columns + 4);
      expect(m.findPath(1, 1, 6, 1), isNull, reason: '$layout: no way round');
    }
    final holes = grid('square')..setTile(2, 0, 0);
    expect(holes.isWalkable(2, 0), isFalse, reason: 'no tile, no ground');
  });

  test('Y-sort: within a layer, lower on the screen draws in front', () {
    EmberEntity thing(String name, double y, {bool ySort = true}) => EmberEntity(name: name)
      ..addComponent(Transform2DComponent(position: Vector2(0, y), size: Vector2(10, 10))..ySort = ySort)
      ..addComponent(FlameSpriteComponent());
    final a = thing('Front', 100), b = thing('Back', 20), c = thing('Plain', 200, ySort: false);
    engine.loadScene(EmberScene(name: 'Sort')
      ..addEntity(a)
      ..addEntity(b)
      ..addEntity(c));
    engine.step();
    final game = EmberFlameGame(engine: engine)..onGameResize(flame.Vector2(200, 200));
    final rec = PictureRecorder();
    game.render(Canvas(rec));
    rec.endRecording();
    expect(game.debugDrawOrder().map((e) => e.name).toList(), ['Back', 'Front', 'Plain']);
    b.getComponent<Transform2DComponent>()!.position = Vector2(0, 150);
    expect(game.debugDrawOrder().map((e) => e.name).toList(), ['Front', 'Back', 'Plain'], reason: 'moving re-sorts');
    expect((Transform2DComponent()..fromJson(a.getComponent<Transform2DComponent>()!.toJson())).ySort, isTrue);
  });

  test('scripts: findPath, block, cellAt on an isometric map, findInBox, right click and drag start', () {
    const src = '''
var path = null;
var blocked = null;
var cell = null;
var boxed = [];
var right = false;
void onStart() {
  var map = find("Map").tilemap;
  path = map.findPath(0, 0, 3, 0);
  map.block(1, 0, true);
  blocked = map.findPath(0, 0, 3, 0);
  cell = map.cellAt(map.cellCenter(2, 3));
}
void onUpdate(dt) {
  if (Input.rightClick) right = true;
  if (Input.mouseReleased) boxed = findInBox("unit", Input.dragStart, Input.mouse).map((e) => e.name);
}
''';
    EmberScripts.instance.loadAll({'s.ember': src});
    EmberEntity unit(String n, double x, double y) => EmberEntity(name: n)
      ..tags.add('unit')
      ..addComponent(Transform2DComponent(position: Vector2(x, y), size: Vector2(10, 10)));
    final m = grid('isometric');
    final scripted = EmberEntity(name: 'Brain')..addComponent(ScriptComponent(scriptName: 's.ember'));
    engine.loadScene(EmberScene(name: 'S')
      ..addEntity(mapEntity(m))
      ..addEntity(unit('A', 100, 100))
      ..addEntity(unit('B', 150, 120))
      ..addEntity(unit('C', 400, 300))
      ..addEntity(scripted));
    engine.step();
    final s = scripted.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    expect(EmberScripts.instance.problems, isEmpty);
    expect(s.field('path'), [[1, 0], [2, 0], [3, 0]]);
    expect((s.field('blocked') as List).length, greaterThan(3), reason: 'goes round the blocked cell');
    expect(s.field('cell'), [2, 3]);

    Input.instance.mouseWorldPosition = Vector2(80, 80);
    Input.onMouseDown(0);
    engine.step();
    Input.instance.mouseWorldPosition = Vector2(200, 200);
    engine.step();
    Input.onMouseUp(0);
    engine.step();
    expect(s.field('boxed'), ['A', 'B']);
    Input.onMouseDown(2);
    engine.step();
    Input.onMouseUp(2);
    expect(s.field('right'), isTrue);
  });

  test('isometric and hex maps draw without errors', () {
    for (final layout in ['isometric', 'hex']) {
      engine.loadScene(EmberScene(name: 'Draw')..addEntity(mapEntity(grid(layout))));
      engine.step();
      final game = EmberFlameGame(engine: engine)..onGameResize(flame.Vector2(400, 300));
      final rec = PictureRecorder();
      game.render(Canvas(rec));
      rec.endRecording();
    }
  });
}

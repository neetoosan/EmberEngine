import 'dart:ui';
import 'package:flame/game.dart' as flame;
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/two_d/camera2d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/two_d/flame_game.dart';
import 'package:ember_engine/subsystems/two_d/light2d.dart';
import 'package:ember_engine/subsystems/two_d/procgen.dart';
import 'package:vector_math/vector_math_64.dart';

EmberEngine get engine => EmberEngine.instance;

/// Cells of [id] reachable from the first one (4-way).
int reachable(FlameTileMapComponent m, int id) {
  final cells = <(int, int)>[];
  for (var r = 0; r < m.rows; r++) {
    for (var c = 0; c < m.columns; c++) {
      if (m.getTile(c, r) == id) cells.add((c, r));
    }
  }
  if (cells.isEmpty) return 0;
  final seen = {cells.first};
  final todo = [cells.first];
  while (todo.isNotEmpty) {
    final (c, r) = todo.removeLast();
    for (final (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final n = (c + dc, r + dr);
      if (!seen.contains(n) && m.getTile(n.$1, n.$2) == id) {
        seen.add(n);
        todo.add(n);
      }
    }
  }
  return seen.length;
}

int count(FlameTileMapComponent m, int id) => m.tiles.where((t) => t == id).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() => engine.stop());

  test('seeded random repeats; noise is smooth and in range', () {
    final a = SeededRandom(42), b = SeededRandom(42), c = SeededRandom(7);
    final sa = [for (var i = 0; i < 5; i++) a.integer(1000)];
    expect([for (var i = 0; i < 5; i++) b.integer(1000)], sa);
    expect([for (var i = 0; i < 5; i++) c.integer(1000)], isNot(sa));

    for (var i = 0; i < 200; i++) {
      final v = Noise2D.at(i * 0.37, i * 0.11, 3);
      expect(v, inInclusiveRange(0, 1));
    }
    expect((Noise2D.at(1.30, 2.0) - Noise2D.at(1.31, 2.0)).abs(), lessThan(0.05), reason: 'smooth');
    expect(Noise2D.at(4.2, 1.7, 1), Noise2D.at(4.2, 1.7, 1));
    expect(Noise2D.fractal(0.5, 0.5, seed: 2), inInclusiveRange(0, 1));
  });

  test('dungeons: rooms that do not overlap, all joined, the same for the same seed', () {
    final m = FlameTileMapComponent(columns: 60, rows: 40);
    final rooms = TileGen.dungeon(m, seed: 5, rooms: 9);
    expect(rooms.length, greaterThanOrEqualTo(6));
    for (var i = 0; i < rooms.length; i++) {
      for (var j = i + 1; j < rooms.length; j++) {
        expect(rooms[i].overlaps(rooms[j], 1), isFalse);
      }
    }
    expect(reachable(m, 2), count(m, 2), reason: 'every floor cell can be walked to');
    for (var c = 0; c < 60; c++) {
      expect(m.getTile(c, 0), 1, reason: 'walls all round');
    }
    final again = FlameTileMapComponent(columns: 60, rows: 40);
    TileGen.dungeon(again, seed: 5, rooms: 9);
    expect(again.tiles, m.tiles);
  });

  test('caves, autotiling into 16 wall pieces, and floor variation', () {
    final m = FlameTileMapComponent(columns: 40, rows: 30);
    TileGen.cave(m, seed: 3);
    expect(count(m, 2), greaterThan(200));
    expect(m.getTile(0, 10), 1);

    final w = FlameTileMapComponent(columns: 5, rows: 5, tiles: [
      for (var r = 0; r < 5; r++)
        for (var c = 0; c < 5; c++) (r == 0 || c == 0 || r == 4 || c == 4 || (r == 2 && c == 2)) ? 1 : 2,
    ]);
    TileGen.autotile(w, 1, 10);
    expect(w.getTile(2, 2), 10, reason: 'a lone pillar has no wall neighbours');
    expect(w.getTile(2, 0), 10 + 2 + 8 + 1, reason: 'top edge: wall left, right and (off the map) above');
    expect(w.getTile(0, 0), 10 + 15);
    expect(w.getTile(1, 1), 2, reason: 'floors are left alone');
    TileGen.autotile(w, 1, 10);
    expect(w.getTile(2, 0), 10 + 11, reason: 'running it again gives the same pieces');

    TileGen.vary(w, 2, [3, 4], 1.0, seed: 1);
    expect(count(w, 2), 0);
  });

  test('scripts: Random, noise, dungeon, autotile, cells, and the tilemap shortcut', () {
    const src = '''
var rooms = [];
var first = 0;
var same = false;
var n = 0;
var floorCells = 0;
var cell = null;
void onStart() {
  var map = self.tilemap;
  rooms = map.dungeon(11, rooms: 6, wall: 1, floor: 2);
  map.autotile(1, 20);
  floorCells = map.cellsWith(2).length;
  cell = map.cellAt(rooms[0]["center"]);
  var a = Random(9);
  var b = Random(9);
  first = a.integer(100);
  same = first == b.integer(100) && a.pick([1, 2, 3]) == b.pick([1, 2, 3]);
  n = noise(0.3, 0.7, 1);
}
''';
    EmberScripts.instance.loadAll({'gen.ember': src});
    final map = FlameTileMapComponent(columns: 50, rows: 30, tileSize: 32);
    final e = EmberEntity(name: 'Map')
      ..addComponent(Transform2DComponent(position: Vector2.zero(), size: Vector2(1600, 960)))
      ..addComponent(map)
      ..addComponent(ScriptComponent(scriptName: 'gen.ember'));
    engine.loadScene(EmberScene(name: 'Gen')..addEntity(e));
    engine.step();
    final s = e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    expect(EmberScripts.instance.problems, isEmpty);
    expect((s.field('rooms') as List).length, greaterThanOrEqualTo(4));
    expect(s.field('same'), isTrue);
    expect(s.field('n'), inInclusiveRange(0, 1));
    expect(s.field('floorCells'), greaterThan(50));
    expect(map.tiles.contains(1), isFalse, reason: 'every wall became a piece');
    final room = (s.field('rooms') as List).first as Map;
    final cell = s.field('cell') as List;
    expect(map.getTile(cell[0] as int, cell[1] as int), 2, reason: 'room centres are floor');
    expect(room['center'], isA<Vector2>());
  });

  test('lights cut through darkness; glowing things are drawn above it; saving', () {
    final cam = EmberEntity(name: 'Camera')
      ..addComponent(Transform2DComponent(position: Vector2(200, 150), size: Vector2.zero()))
      ..addComponent(Camera2DComponent(designWidth: 400, designHeight: 300, darkness: 0.9));
    final torch = EmberEntity(name: 'Torch')
      ..addComponent(Transform2DComponent(position: Vector2(100, 100), size: Vector2(10, 10)))
      ..addComponent(Light2DComponent(radius: 80, flicker: 1));
    engine.loadScene(EmberScene(name: 'Dark')
      ..addEntity(cam)
      ..addEntity(torch));
    engine.step();
    final light = torch.getComponent<Light2DComponent>()!;
    final radii = <double>{};
    for (var i = 0; i < 20; i++) {
      engine.step();
      radii.add(light.currentRadius);
    }
    expect(radii.length, greaterThan(5), reason: 'it flickers');
    expect(light.center, const Offset(105, 105));
    final game = EmberFlameGame(engine: engine)..onGameResize(flame.Vector2(400, 300));
    final rec = PictureRecorder();
    game.render(Canvas(rec));
    rec.endRecording();

    final copy = Light2DComponent()..fromJson(Light2DComponent(radius: 50, flicker: 0.5, tint: false).toJson());
    expect((copy.radius, copy.flicker, copy.tint), (50.0, 0.5, false));
    final c2 = Camera2DComponent()..fromJson(Camera2DComponent(darkness: 0.7, darknessColor: const Color(0xFF101020)).toJson());
    expect((c2.darkness, c2.darknessColor), (0.7, const Color(0xFF101020)));
  });
}

import 'dart:math' as math;
import 'flame_components.dart';

/// Random numbers that come out the same every time for the same [seed]:
/// replayable levels, daily challenges, shareable runs.
class SeededRandom {
  final int seed;
  final math.Random _r;

  SeededRandom(this.seed) : _r = math.Random(seed);

  /// 0 .. 1.
  double next() => _r.nextDouble();
  double range(double min, double max) => min + _r.nextDouble() * (max - min);

  /// A whole number from 0 to [max] - 1.
  int integer(int max) => max <= 0 ? 0 : _r.nextInt(max);
  bool chance(double p) => _r.nextDouble() < p;
  T? pick<T>(List<T> list) => list.isEmpty ? null : list[_r.nextInt(list.length)];
  void shuffle(List<Object?> list) => list.shuffle(_r);
}

/// Smooth 2D noise (gradient noise), for terrain, caves, clouds and wobble.
class Noise2D {
  static double _fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);

  static int _hash(int x, int y, int seed) {
    var h = x * 374761393 + y * 668265263 + seed * 2246822519;
    h = (h ^ (h >> 13)) * 1274126177;
    return h ^ (h >> 16);
  }

  static double _grad(int x, int y, int seed, double dx, double dy) {
    final a = (_hash(x, y, seed) & 0xFFFF) / 0xFFFF * math.pi * 2;
    return math.cos(a) * dx + math.sin(a) * dy;
  }

  /// Noise at ([x], [y]), from 0 to 1 (0.5 on average). One unit is one "blob".
  static double at(double x, double y, [int seed = 0]) {
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    final u = _fade(fx), v = _fade(fy);
    final n00 = _grad(x0, y0, seed, fx, fy);
    final n10 = _grad(x0 + 1, y0, seed, fx - 1, fy);
    final n01 = _grad(x0, y0 + 1, seed, fx, fy - 1);
    final n11 = _grad(x0 + 1, y0 + 1, seed, fx - 1, fy - 1);
    final nx0 = n00 + (n10 - n00) * u;
    final nx1 = n01 + (n11 - n01) * u;
    return ((nx0 + (nx1 - nx0) * v) * 0.7071 + 0.5).clamp(0.0, 1.0);
  }

  /// Several layers of [at] (finer and fainter each time): more natural shapes.
  static double fractal(double x, double y, {int seed = 0, int octaves = 4}) {
    var sum = 0.0, amp = 1.0, freq = 1.0, total = 0.0;
    for (var i = 0; i < octaves; i++) {
      sum += at(x * freq, y * freq, seed + i * 31) * amp;
      total += amp;
      amp *= 0.5;
      freq *= 2;
    }
    return sum / total;
  }
}

/// A rectangular room in tile cells.
class DungeonRoom {
  final int col, row, width, height;
  const DungeonRoom(this.col, this.row, this.width, this.height);
  int get centerCol => col + width ~/ 2;
  int get centerRow => row + height ~/ 2;
  bool overlaps(DungeonRoom o, int margin) =>
      col - margin < o.col + o.width && o.col - margin < col + width && row - margin < o.row + o.height && o.row - margin < row + height;
}

/// Level generators that write into a tilemap.
class TileGen {
  /// Rooms joined by corridors: the map is filled with [wall], then up to
  /// [rooms] non-overlapping rooms of [minSize]..[maxSize] cells are carved
  /// with [floor], each joined to the nearest earlier room by an L-shaped
  /// corridor [corridor] cells wide. Returns the rooms (the first is a good start).
  static List<DungeonRoom> dungeon(FlameTileMapComponent map,
      {int seed = 0, int rooms = 10, int minSize = 5, int maxSize = 10, int wall = 1, int floor = 2, int corridor = 2}) {
    final rng = math.Random(seed);
    final cols = map.columns, rows = map.rows;
    final tiles = List<int>.filled(cols * rows, wall);
    final placed = <DungeonRoom>[];
    for (var attempt = 0; attempt < rooms * 30 && placed.length < rooms; attempt++) {
      final w = minSize + rng.nextInt(math.max(1, maxSize - minSize + 1));
      final h = minSize + rng.nextInt(math.max(1, maxSize - minSize + 1));
      if (w + 2 >= cols || h + 2 >= rows) continue;
      final room = DungeonRoom(1 + rng.nextInt(cols - w - 1), 1 + rng.nextInt(rows - h - 1), w, h);
      if (placed.any((o) => room.overlaps(o, 2))) continue;
      placed.add(room);
    }
    void carve(int c, int r) {
      if (c > 0 && r > 0 && c < cols - 1 && r < rows - 1) tiles[r * cols + c] = floor;
    }

    for (final room in placed) {
      for (var r = room.row; r < room.row + room.height; r++) {
        for (var c = room.col; c < room.col + room.width; c++) {
          carve(c, r);
        }
      }
    }
    for (var i = 1; i < placed.length; i++) {
      final a = placed[i];
      var best = placed[0];
      for (final o in placed.take(i)) {
        final d = (o.centerCol - a.centerCol).abs() + (o.centerRow - a.centerRow).abs();
        if (d < (best.centerCol - a.centerCol).abs() + (best.centerRow - a.centerRow).abs()) best = o;
      }
      final horizontalFirst = rng.nextBool();
      void hLine(int r, int c0, int c1) {
        for (var c = math.min(c0, c1); c <= math.max(c0, c1); c++) {
          for (var k = 0; k < corridor; k++) {
            carve(c, r + k);
          }
        }
      }

      void vLine(int c, int r0, int r1) {
        for (var r = math.min(r0, r1); r <= math.max(r0, r1); r++) {
          for (var k = 0; k < corridor; k++) {
            carve(c + k, r);
          }
        }
      }

      if (horizontalFirst) {
        hLine(a.centerRow, a.centerCol, best.centerCol);
        vLine(best.centerCol, a.centerRow, best.centerRow);
      } else {
        vLine(a.centerCol, a.centerRow, best.centerRow);
        hLine(best.centerRow, a.centerCol, best.centerCol);
      }
    }
    map.setTiles(tiles);
    return placed;
  }

  /// Natural caves (cellular automaton): random [fill] of walls, smoothed
  /// [steps] times; the border is always wall.
  static void cave(FlameTileMapComponent map, {int seed = 0, double fill = 0.45, int steps = 4, int wall = 1, int floor = 2}) {
    final rng = math.Random(seed);
    final cols = map.columns, rows = map.rows;
    var solid = List<bool>.generate(cols * rows, (i) {
      final c = i % cols, r = i ~/ cols;
      return c == 0 || r == 0 || c == cols - 1 || r == rows - 1 || rng.nextDouble() < fill;
    });
    for (var s = 0; s < steps; s++) {
      final next = List<bool>.filled(cols * rows, true);
      for (var r = 1; r < rows - 1; r++) {
        for (var c = 1; c < cols - 1; c++) {
          var n = 0;
          for (var dr = -1; dr <= 1; dr++) {
            for (var dc = -1; dc <= 1; dc++) {
              if ((dr != 0 || dc != 0) && solid[(r + dr) * cols + c + dc]) n++;
            }
          }
          next[r * cols + c] = n >= 5 || (n >= 4 && solid[r * cols + c]);
        }
      }
      solid = next;
    }
    map.setTiles([for (final w in solid) w ? wall : floor]);
  }

  /// Picks wall pieces by their neighbours: every tile that is [baseId] (or
  /// already one of the 16 pieces) becomes firstId + mask, where the mask adds
  /// 1 / 2 / 4 / 8 when the tile above / right / below / left is wall too.
  /// Off the map counts as wall.
  static void autotile(FlameTileMapComponent map, int baseId, int firstId) {
    final cols = map.columns, rows = map.rows;
    final src = map.tiles;
    bool isWall(int c, int r) {
      if (c < 0 || r < 0 || c >= cols || r >= rows) return true;
      final id = src[r * cols + c];
      return id == baseId || (id >= firstId && id < firstId + 16);
    }

    final out = List<int>.of(src);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (!isWall(c, r)) continue;
        final mask = (isWall(c, r - 1) ? 1 : 0) | (isWall(c + 1, r) ? 2 : 0) | (isWall(c, r + 1) ? 4 : 0) | (isWall(c - 1, r) ? 8 : 0);
        out[r * cols + c] = firstId + mask;
      }
    }
    map.setTiles(out);
  }

  /// Replaces some tiles of [id] with one of [variants] (worn floors, cracks, moss).
  static void vary(FlameTileMapComponent map, int id, List<int> variants, double chance, {int seed = 0}) {
    if (variants.isEmpty) return;
    final rng = math.Random(seed);
    final out = [for (final t in map.tiles) t == id && rng.nextDouble() < chance ? variants[rng.nextInt(variants.length)] : t];
    map.setTiles(out);
  }
}

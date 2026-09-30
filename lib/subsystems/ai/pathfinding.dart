import 'dart:math' as math;
import 'dart:ui' show Rect;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/entity.dart';
import '../../core/scene.dart';
import '../physics/tile_collision.dart';
import '../two_d/flame_components.dart';

/// A* pathfinding over the tile grid of a scene's collision tilemaps.
///
/// The grid comes from the largest collision tilemap; a cell is walkable
/// when no collision layer has a solid tile there. Paths use 8 directions
/// without cutting corners. The walkability grid is cached until tiles or
/// the scene structure change.
class Pathfinder {
  static final Expando<_Grid> _cache = Expando<_Grid>();

  /// World points (cell centres, ending exactly at [to]) from [from] to [to],
  /// or null if unreachable within [maxExpanded] explored cells.
  static List<vm.Vector2>? findPath(EmberScene scene, vm.Vector2 from, vm.Vector2 to, {int maxExpanded = 6000}) {
    final grid = _gridFor(scene);
    if (grid == null) return [to.clone()];
    final start = grid.cellOf(from.x, from.y);
    final goal = grid.cellOf(to.x, to.y);
    if (start == null || goal == null || grid.blocked[goal]) return null;
    if (start == goal) return [to.clone()];

    final cols = grid.cols;
    final g = <int, double>{start: 0};
    final cameFrom = <int, int>{};
    final open = _Heap()..push(start, _h(start, goal, cols));
    final closed = <int>{};
    var expanded = 0;

    while (open.isNotEmpty) {
      final cur = open.pop();
      if (cur == goal) break;
      if (!closed.add(cur)) continue;
      if (++expanded > maxExpanded) return null;
      final cx = cur % cols, cy = cur ~/ cols;
      for (final (dx, dy) in _dirs) {
        final nx = cx + dx, ny = cy + dy;
        if (nx < 0 || ny < 0 || nx >= cols || ny >= grid.rows) continue;
        final n = ny * cols + nx;
        if (grid.blocked[n]) continue;
        // No corner cutting: both orthogonal neighbours must be free
        if (dx != 0 && dy != 0 && (grid.blocked[cy * cols + nx] || grid.blocked[ny * cols + cx])) continue;
        final cost = g[cur]! + (dx != 0 && dy != 0 ? math.sqrt2 : 1);
        if (cost < (g[n] ?? double.infinity)) {
          g[n] = cost;
          cameFrom[n] = cur;
          open.push(n, cost + _h(n, goal, cols));
        }
      }
    }
    if (!cameFrom.containsKey(goal)) return null;

    final cells = <int>[goal];
    var c = goal;
    while (cameFrom.containsKey(c) && cameFrom[c] != start) {
      c = cameFrom[c]!;
      cells.add(c);
    }
    final path = [for (final cell in cells.reversed) grid.centerOf(cell)];
    path[path.length - 1] = to.clone();
    return path;
  }

  /// True if the cell under the world point is walkable.
  static bool isWalkable(EmberScene scene, double x, double y) {
    final grid = _gridFor(scene);
    if (grid == null) return true;
    final c = grid.cellOf(x, y);
    return c != null && !grid.blocked[c];
  }

  static const _dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];

  static double _h(int a, int b, int cols) {
    final dx = (a % cols - b % cols).abs(), dy = (a ~/ cols - b ~/ cols).abs();
    return (dx + dy) + (math.sqrt2 - 2) * math.min(dx, dy);
  }

  static _Grid? _gridFor(EmberScene scene) {
    final maps = scene.componentsOf<FlameTileMapComponent>().where((m) => m.collision && m.enabled && m.entity != null).toList();
    if (maps.isEmpty) return null;
    final key = Object.hash(EmberEntity.structureVersion, Object.hashAll(maps.map((m) => m.revision)));
    final cached = _cache[scene];
    if (cached != null && cached.key == key) return cached;

    maps.sort((a, b) => (b.columns * b.rows).compareTo(a.columns * a.rows));
    final base = maps.first;
    final origin = base.cellRect(0, 0);
    final grid = _Grid(key, base.columns, base.rows, origin.left, origin.top, origin.width);
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = Rect.fromLTWH(grid.ox + c * grid.size, grid.oy + r * grid.size, grid.size, grid.size).deflate(2);
        grid.blocked[r * grid.cols + c] = TileCollision.blocked(scene, cell);
      }
    }
    _cache[scene] = grid;
    return grid;
  }
}

class _Grid {
  final int key, cols, rows;
  final double ox, oy, size;
  final List<bool> blocked;
  _Grid(this.key, this.cols, this.rows, this.ox, this.oy, this.size) : blocked = List<bool>.filled(cols * rows, false);

  int? cellOf(double x, double y) {
    final c = ((x - ox) / size).floor(), r = ((y - oy) / size).floor();
    if (c < 0 || r < 0 || c >= cols || r >= rows) return null;
    return r * cols + c;
  }

  vm.Vector2 centerOf(int cell) => vm.Vector2(ox + (cell % cols + 0.5) * size, oy + (cell ~/ cols + 0.5) * size);
}

/// Minimal binary min-heap of (cell, priority).
class _Heap {
  final List<int> _cells = [];
  final List<double> _prio = [];

  bool get isNotEmpty => _cells.isNotEmpty;

  void push(int cell, double p) {
    _cells.add(cell);
    _prio.add(p);
    var i = _cells.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_prio[parent] <= _prio[i]) break;
      _swap(i, parent);
      i = parent;
    }
  }

  int pop() {
    final top = _cells.first;
    final lastCell = _cells.removeLast();
    final lastPrio = _prio.removeLast();
    if (_cells.isNotEmpty) {
      _cells[0] = lastCell;
      _prio[0] = lastPrio;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _cells.length && _prio[l] < _prio[m]) m = l;
        if (r < _cells.length && _prio[r] < _prio[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final c = _cells[a];
    _cells[a] = _cells[b];
    _cells[b] = c;
    final p = _prio[a];
    _prio[a] = _prio[b];
    _prio[b] = p;
  }
}

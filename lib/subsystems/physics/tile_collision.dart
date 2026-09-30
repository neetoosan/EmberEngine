import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;
import '../../core/scene.dart';
import '../two_d/flame_components.dart';

/// Tile queries shared by movement, projectiles and AI.
class TileCollision {
  /// Non-empty tiles of every enabled collision tilemap that overlap [area].
  static List<TileHit> tilesIn(EmberScene scene, Rect area) {
    final hits = <TileHit>[];
    for (final map in scene.componentsOf<FlameTileMapComponent>()) {
      final e = map.entity;
      if (e == null || !e.enabled || !map.enabled || !map.collision) continue;
      hits.addAll(map.tilesIn(area));
    }
    return hits;
  }

  /// True if any solid (blocking) tile overlaps [area].
  static bool blocked(EmberScene scene, Rect area) {
    final probe = area.deflate(0.01);
    return tilesIn(scene, probe).any((t) => t.kind.blocks && t.rect.overlaps(probe));
  }

  /// True if the straight line from [a] to [b] crosses no blocking tile
  /// (sampled every [step] pixels) — used for line-of-sight checks.
  static bool lineClear(EmberScene scene, Offset a, Offset b, {double step = 8}) {
    final d = b - a;
    final n = (d.distance / step).ceil();
    for (var i = 1; i < n; i++) {
      final p = a + d * (i / n);
      if (blocked(scene, Rect.fromCenter(center: p, width: 2, height: 2))) return false;
    }
    return true;
  }

  /// Distance helper used by AI.
  static double distance(Offset a, Offset b) => math.sqrt((a - b).distanceSquared);
}

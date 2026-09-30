import 'dart:ui' show Rect;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/entity.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import '../two_d/flame_components.dart';

/// 2D Physics and Collision World for Ember Engine (Flame integration).
///
/// Each step it (1) pushes overlapping *solid* hitboxes apart and (2) reports
/// contact changes to scripts: `onCollisionEnter/Exit` when both hitboxes are
/// solid, `onTriggerEnter/Exit` when either is a trigger (non-solid).
class PhysicsWorld2D {
  static vm.Vector2 gravity = vm.Vector2(0.0, 980.0); // pixels/s² (downward positive in 2D)

  /// Pairs touching at the end of the previous step, per scene.
  static final Expando<Set<String>> _contacts = Expando<Set<String>>();

  /// World-space rectangle of an entity's hitbox.
  static Rect hitboxRect(Transform2DComponent t, FlameHitbox2DComponent h) {
    final min = t.worldPosition + h.offset - t.anchorOffset;
    return Rect.fromLTWH(min.x, min.y, h.size.x, h.size.y);
  }

  /// Steps 2D physics: resolves solid overlaps, then dispatches contact events.
  static void step(EmberScene scene, double fixedDt) {
    final bodies = <(EmberEntity, Transform2DComponent, FlameHitbox2DComponent)>[];
    for (final h in scene.componentsOf<FlameHitbox2DComponent>()) {
      final e = h.entity;
      if (e == null || !e.enabled || !h.enabled) continue;
      final t = e.getComponent<Transform2DComponent>();
      if (t != null) bodies.add((e, t, h));
    }

    // 1. Contact events (detected before solids are pushed apart, so solid
    //    hits are seen; solids resting side by side count as touching).
    final previous = _contacts[scene] ?? <String>{};
    final current = <String>{};
    // Sort-and-sweep broadphase: each rectangle is computed once, bodies are
    // sorted by left edge, and only pairs whose x-ranges overlap are tested.
    final rects = [for (final (_, t, h) in bodies) hitboxRect(t, h)];
    final order = List<int>.generate(bodies.length, (i) => i)..sort((a, b) => rects[a].left.compareTo(rects[b].left));
    for (int oi = 0; oi < order.length; oi++) {
      final i = order[oi];
      final (eA, _, hitA) = bodies[i];
      final rA = rects[i];
      final reach = rA.right + _restingTolerance;
      for (int oj = oi + 1; oj < order.length; oj++) {
        final j = order[oj];
        final rB = rects[j];
        if (rB.left > reach) break; // everything further right starts beyond A
        final (eB, _, hitB) = bodies[j];
        final bothSolid = hitA.isSolid && hitB.isSolid;
        if (!(bothSolid ? rA.inflate(_restingTolerance).overlaps(rB) : rA.overlaps(rB))) continue;
        final key = _pairKey(eA, eB);
        current.add(key);
        if (!previous.contains(key)) {
          _dispatch(eA, eB, solid: hitA.isSolid && hitB.isSolid, enter: true);
        }
      }
    }
    for (final key in previous.difference(current)) {
      final ids = key.split('|');
      final a = scene.findEntityById(ids[0]);
      final b = scene.findEntityById(ids[1]);
      if (a == null || b == null) continue; // destroyed; nothing to notify
      final ha = a.getComponent<FlameHitbox2DComponent>();
      final hb = b.getComponent<FlameHitbox2DComponent>();
      _dispatch(a, b, solid: (ha?.isSolid ?? false) && (hb?.isSolid ?? false), enter: false);
    }
    _contacts[scene] = current;

    // 2. Resolve solid-vs-solid overlaps
    for (int i = 0; i < bodies.length; i++) {
      final (eA, tA, hitA) = bodies[i];
      if (!hitA.isSolid) continue;
      for (int j = i + 1; j < bodies.length; j++) {
        final (eB, tB, hitB) = bodies[j];
        if (!hitB.isSolid) continue;
        _resolveAABBCollision(eA, tA, hitA, eB, tB, hitB);
      }
    }
  }

  /// Gap (world pixels) within which two solid hitboxes still count as touching.
  static const double _restingTolerance = 0.5;

  /// Forgets contact state (call when a scene is restarted).
  static void resetContacts(EmberScene scene) => _contacts[scene] = null;

  static String _pairKey(EmberEntity a, EmberEntity b) =>
      a.id.compareTo(b.id) < 0 ? '${a.id}|${b.id}' : '${b.id}|${a.id}';

  static void _dispatch(EmberEntity a, EmberEntity b, {required bool solid, required bool enter}) {
    if (solid) {
      a.notifyScripts((s) => enter ? s.onCollisionEnter(b) : s.onCollisionExit(b));
      b.notifyScripts((s) => enter ? s.onCollisionEnter(a) : s.onCollisionExit(a));
    } else {
      a.notifyScripts((s) => enter ? s.onTriggerEnter(b) : s.onTriggerExit(b));
      b.notifyScripts((s) => enter ? s.onTriggerEnter(a) : s.onTriggerExit(a));
    }
  }

  static void _resolveAABBCollision(
    EmberEntity eA,
    Transform2DComponent tA,
    FlameHitbox2DComponent hitA,
    EmberEntity eB,
    Transform2DComponent tB,
    FlameHitbox2DComponent hitB,
  ) {
    final posA = tA.worldPosition + hitA.offset - tA.anchorOffset;
    final posB = tB.worldPosition + hitB.offset - tB.anchorOffset;
    final sizeA = hitA.size;
    final sizeB = hitB.size;

    // AABB intersection check
    final dx = (posA.x + sizeA.x * 0.5) - (posB.x + sizeB.x * 0.5);
    final px = (sizeA.x * 0.5 + sizeB.x * 0.5) - dx.abs();
    if (px <= 0) return;

    final dy = (posA.y + sizeA.y * 0.5) - (posB.y + sizeB.y * 0.5);
    final py = (sizeA.y * 0.5 + sizeB.y * 0.5) - dy.abs();
    if (py <= 0) return;

    // Minimum penetration separation on Entity A
    if (px < py) {
      final sign = dx > 0 ? 1.0 : -1.0;
      tA.position = vm.Vector2(tA.position.x + px * sign, tA.position.y);
    } else {
      final sign = dy > 0 ? 1.0 : -1.0;
      tA.position = vm.Vector2(tA.position.x, tA.position.y + py * sign);
    }
  }
}

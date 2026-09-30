import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import '../physics/tile_collision.dart';
import 'flame_components.dart';

/// 4-way facing used for top-down animations (walk_down, attack_left, ...).
enum Facing { down, up, left, right }

/// Top-down (Zelda-style) character movement: 8 directions, smooth
/// acceleration, sliding along solid tiles, and decaying knockback.
///
/// Collision uses the entity's Hitbox 2D if present (usually just the feet),
/// otherwise its Transform 2D box. Call [move] every frame from a script.
class TopDownController2DComponent extends EmberComponent {
  double moveSpeed;

  /// How quickly velocity reaches the target speed (higher = snappier).
  double acceleration;

  final vm.Vector2 velocity = vm.Vector2.zero();
  final vm.Vector2 _knockback = vm.Vector2.zero();
  Facing facing = Facing.down;
  bool _hitWall = false;

  TopDownController2DComponent({this.moveSpeed = 140, this.acceleration = 14});

  bool get isMoving => velocity.length2 > 25;
  bool get hitWall => _hitWall;

  /// Unit vector for [facing] (world space; +y is down).
  vm.Vector2 get facingVector => switch (facing) {
        Facing.down => vm.Vector2(0, 1),
        Facing.up => vm.Vector2(0, -1),
        Facing.left => vm.Vector2(-1, 0),
        Facing.right => vm.Vector2(1, 0),
      };

  /// Adds an impulse (pixels/second) that fades out quickly.
  void knockback(vm.Vector2 impulse) => _knockback.add(impulse);

  /// Moves toward [direction] (x right, y down; length ≤ 1 = analog speed).
  void move(vm.Vector2 direction, double dt) {
    final self = entity;
    final t = self?.getComponent<Transform2DComponent>();
    if (self == null || t == null) return;

    var dir = direction.clone();
    if (dir.length2 > 1) dir.normalize();
    if (dir.length2 > 0.01) {
      facing = dir.x.abs() > dir.y.abs()
          ? (dir.x > 0 ? Facing.right : Facing.left)
          : (dir.y > 0 ? Facing.down : Facing.up);
    }
    final target = dir * moveSpeed;
    velocity.add((target - velocity) * math.min(1.0, dt * acceleration));
    final motion = (velocity + _knockback) * dt;
    _knockback.scale(math.exp(-dt * 9));
    if (_knockback.length2 < 1) _knockback.setZero();

    _hitWall = false;
    final scene = self.scene;
    if (scene == null) {
      t.position = t.position + motion;
      return;
    }
    // Axis-separated: slide along walls instead of stopping dead
    final body = _body(self, t);
    final dx = _sweep(scene, body, motion.x, horizontal: true);
    final movedX = body.shift(Offset(dx, 0));
    final dy = _sweep(scene, movedX, motion.y, horizontal: false);
    if (dx != motion.x) velocity.x = 0;
    if (dy != motion.y) velocity.y = 0;
    t.position = vm.Vector2(t.position.x + dx, t.position.y + dy);
  }

  /// How far [body] can move by [amount] along one axis before a solid tile.
  double _sweep(EmberScene scene, Rect body, double amount, {required bool horizontal}) {
    if (amount == 0) return 0;
    final moved = body.shift(horizontal ? Offset(amount, 0) : Offset(0, amount));
    var allowed = amount;
    for (final tile in TileCollision.tilesIn(scene, moved.inflate(1))) {
      if (!tile.kind.blocks || !tile.rect.overlaps(moved.deflate(0.01))) continue;
      final r = tile.rect;
      final limit = horizontal
          ? (amount > 0 ? r.left - body.right : r.right - body.left)
          : (amount > 0 ? r.top - body.bottom : r.bottom - body.top);
      if (amount > 0 ? limit < allowed : limit > allowed) allowed = limit;
      _hitWall = true;
    }
    // Never move backwards because of a tile we already overlap
    return amount > 0 ? math.max(0, allowed) : math.min(0, allowed);
  }

  static Rect _body(EmberEntity e, Transform2DComponent t) {
    final min = t.worldPosition - t.anchorOffset;
    final h = e.getComponent<FlameHitbox2DComponent>();
    if (h != null) return Rect.fromLTWH(min.x + h.offset.x, min.y + h.offset.y, h.size.x, h.size.y);
    return Rect.fromLTWH(min.x, min.y, t.size.x * t.scale.x, t.size.y * t.scale.y);
  }


  @override
  String get displayName => 'Top-Down Controller 2D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<double>(
          name: 'moveSpeed',
          label: 'Move Speed (px/s)',
          type: InspectableType.number,
          getter: () => moveSpeed,
          setter: (v) {
            moveSpeed = v;
            notifyListeners();
          },
          min: 0,
          step: 5,
        ),
        InspectableProperty<double>(
          name: 'acceleration',
          label: 'Acceleration',
          type: InspectableType.number,
          getter: () => acceleration,
          setter: (v) {
            acceleration = v;
            notifyListeners();
          },
          min: 1,
          step: 1,
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {'moveSpeed': moveSpeed, 'acceleration': acceleration};

  @override
  void fromJson(Map<String, dynamic> json) {
    moveSpeed = (json['moveSpeed'] as num?)?.toDouble() ?? 140;
    acceleration = (json['acceleration'] as num?)?.toDouble() ?? 14;
    notifyListeners();
  }

  @override
  TopDownController2DComponent clone() => TopDownController2DComponent(moveSpeed: moveSpeed, acceleration: acceleration);
}

void registerTopDownController() {
  ComponentRegistry.register('Top-Down Controller 2D', (json) => TopDownController2DComponent()..fromJson(json));
}

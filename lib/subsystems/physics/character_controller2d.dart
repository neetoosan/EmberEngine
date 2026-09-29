import 'dart:math' as math;
import 'dart:ui' show Rect;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/transform2d.dart';
import '../two_d/flame_components.dart';

/// 2D Kinematic Platformer Character Controller.
///
/// Implements key 2D game development principles:
/// - Coyote Time (120ms leniency after leaving ground)
/// - Jump Buffering (100ms window before landing)
/// - Variable Jump Height (releasing jump early truncates ascent)
/// - Snappy horizontal acceleration and friction
class CharacterController2DComponent extends EmberComponent {
  double moveSpeed;
  double jumpVelocity;
  double gravity;
  double coyoteTimeDuration;
  double jumpBufferDuration;
  double groundY;

  final vm.Vector2 _velocity = vm.Vector2.zero();
  bool _isGrounded = false;
  double _coyoteTimer = 0.0;
  double _jumpBufferTimer = 0.0;

  CharacterController2DComponent({
    this.moveSpeed = 220.0,
    this.jumpVelocity = 420.0,
    this.gravity = 980.0,
    this.coyoteTimeDuration = 0.12,
    this.jumpBufferDuration = 0.10,
    this.groundY = 500.0,
  });

  bool get isGrounded => _isGrounded;
  bool get canJump => _coyoteTimer > 0.0 || _isGrounded;
  bool get isJumpBuffered => _jumpBufferTimer > 0.0;
  vm.Vector2 get velocity => _velocity;

  void jump() {
    _velocity.y = -jumpVelocity;
    _isGrounded = false;
    _coyoteTimer = 0.0;
    notifyListeners();
  }

  void bufferJump() {
    _jumpBufferTimer = jumpBufferDuration;
  }

  void update(EmberEntity ent, double dt) {
    attach(ent);
    final t2d = ent.getComponent<Transform2DComponent>();
    if (t2d != null) {
      if (t2d.position.y >= groundY) {
        t2d.position.y = groundY;
        _velocity.y = 0.0;
        _isGrounded = true;
      } else {
        _isGrounded = false;
      }
    }
    updateMovement(
      horizontalInput: 0.0,
      isJumpPressed: false,
      isJumpJustPressed: false,
      dt: dt,
    );
  }

  /// Updates horizontal input (-1.0 to 1.0) and integrates kinematics.
  void updateMovement({
    required double horizontalInput,
    required bool isJumpPressed,
    required bool isJumpJustPressed,
    required double dt,
  }) {
    final t2d = entity?.getComponent<Transform2DComponent>();
    if (t2d == null) return;

    // 1. Horizontal acceleration
    final targetVx = horizontalInput * moveSpeed;
    _velocity.x += (targetVx - _velocity.x) * math.min(1.0, dt * 16.0);

    // 2. Timers
    if (_isGrounded) {
      _coyoteTimer = coyoteTimeDuration;
    } else {
      _coyoteTimer = math.max(0.0, _coyoteTimer - dt);
    }

    if (isJumpJustPressed) {
      _jumpBufferTimer = jumpBufferDuration;
    } else {
      _jumpBufferTimer = math.max(0.0, _jumpBufferTimer - dt);
    }

    // 3. Jump Execution (Coyote time + Jump Buffer)
    if (_jumpBufferTimer > 0.0 && _coyoteTimer > 0.0) {
      _velocity.y = -jumpVelocity; // Upward is negative Y in 2D
      _coyoteTimer = 0.0;
      _jumpBufferTimer = 0.0;
      _isGrounded = false;
    }

    // 4. Variable Jump Height: If player releases jump while moving up, cut velocity
    if (!isJumpPressed && _velocity.y < -50.0) {
      _velocity.y *= 0.5;
    }

    // 5. Apply Gravity (always; ground contact is re-detected every frame)
    _velocity.y += gravity * dt;

    // 6. Integrate Position one axis at a time, colliding with solid tiles
    final w = t2d.size.x * t2d.scale.x;
    final h = t2d.size.y * t2d.scale.y;
    final anchor = t2d.anchorOffset;
    final solids = _solidTileRects();
    _isGrounded = false;

    var x = t2d.position.x + _velocity.x * dt;
    var y = t2d.position.y;
    for (final r in solids) {
      if (!_overlaps(r, x - anchor.x, y - anchor.y, w, h)) continue;
      if (_velocity.x > 0) {
        x = r.left - w + anchor.x;
      } else if (_velocity.x < 0) {
        x = r.right + anchor.x;
      }
      _velocity.x = 0.0;
    }

    y += _velocity.y * dt;
    for (final r in solids) {
      if (!_overlaps(r, x - anchor.x, y - anchor.y, w, h)) continue;
      if (_velocity.y > 0) {
        y = r.top - h + anchor.y;
        _isGrounded = true;
      } else if (_velocity.y < 0) {
        y = r.bottom + anchor.y;
      }
      _velocity.y = 0.0;
    }

    // 7. Fallback world floor at [groundY]
    final footY = y + (h - anchor.y);
    if (footY >= groundY) {
      y = groundY - (h - anchor.y);
      _velocity.y = 0.0;
      _isGrounded = true;
    }

    t2d.position = vm.Vector2(x, y);
  }

  static bool _overlaps(Rect r, double left, double top, double w, double h) {
    const eps = 0.01;
    return left + w > r.left + eps &&
        left < r.right - eps &&
        top + h > r.top + eps &&
        top < r.bottom - eps;
  }

  /// World-space rectangles of every non-empty tile in the scene's tilemaps.
  List<Rect> _solidTileRects() {
    final scene = entity?.scene;
    if (scene == null) return const [];
    final rects = <Rect>[];
    for (final e in scene.allEntities) {
      if (!e.enabled) continue;
      final map = e.getComponent<FlameTileMapComponent>();
      final t = e.getComponent<Transform2DComponent>();
      if (map == null || t == null || !map.enabled) continue;
      final origin = t.worldPosition - t.anchorOffset;
      final ts = map.tileSize * t.worldScale.x;
      for (int r = 0; r < map.rows; r++) {
        for (int c = 0; c < map.columns; c++) {
          if (map.getTile(c, r) > 0) {
            rects.add(Rect.fromLTWH(origin.x + c * ts, origin.y + r * ts, ts, ts));
          }
        }
      }
    }
    return rects;
  }

  @override
  String get displayName => 'Character Controller 2D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<double>(
          name: 'moveSpeed',
          label: 'Move Speed (px/s)',
          type: InspectableType.number,
          getter: () => moveSpeed,
          setter: (val) {
            moveSpeed = val;
            notifyListeners();
          },
          min: 50.0,
          max: 800.0,
          step: 10.0,
        ),
        InspectableProperty<double>(
          name: 'jumpVelocity',
          label: 'Jump Force',
          type: InspectableType.number,
          getter: () => jumpVelocity,
          setter: (val) {
            jumpVelocity = val;
            notifyListeners();
          },
          min: 100.0,
          max: 1200.0,
          step: 20.0,
        ),
        InspectableProperty<double>(
          name: 'gravity',
          label: 'Gravity',
          type: InspectableType.number,
          getter: () => gravity,
          setter: (val) {
            gravity = val;
            notifyListeners();
          },
          min: 100.0,
          max: 3000.0,
          step: 50.0,
        ),
        InspectableProperty<double>(
          name: 'groundY',
          label: 'Ground Y (px)',
          type: InspectableType.number,
          getter: () => groundY,
          setter: (val) {
            groundY = val;
            notifyListeners();
          },
          step: 10.0,
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'moveSpeed': moveSpeed,
      'jumpVelocity': jumpVelocity,
      'gravity': gravity,
      'coyoteTimeDuration': coyoteTimeDuration,
      'jumpBufferDuration': jumpBufferDuration,
      'groundY': groundY,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    moveSpeed = (json['moveSpeed'] as num?)?.toDouble() ?? 220.0;
    jumpVelocity = (json['jumpVelocity'] as num?)?.toDouble() ?? 420.0;
    gravity = (json['gravity'] as num?)?.toDouble() ?? 980.0;
    coyoteTimeDuration = (json['coyoteTimeDuration'] as num?)?.toDouble() ?? 0.12;
    jumpBufferDuration = (json['jumpBufferDuration'] as num?)?.toDouble() ?? 0.10;
    groundY = (json['groundY'] as num?)?.toDouble() ?? 500.0;
    notifyListeners();
  }

  @override
  CharacterController2DComponent clone() {
    return CharacterController2DComponent(
      moveSpeed: moveSpeed,
      jumpVelocity: jumpVelocity,
      gravity: gravity,
      coyoteTimeDuration: coyoteTimeDuration,
      jumpBufferDuration: jumpBufferDuration,
      groundY: groundY,
    );
  }
}

/// Registers 2D Character Controller in ComponentRegistry.
void registerCharacterController2D() {
  ComponentRegistry.register('Character Controller 2D', (json) {
    final comp = CharacterController2DComponent();
    comp.fromJson(json);
    return comp;
  });
}

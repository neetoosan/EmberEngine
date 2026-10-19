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
/// - Optional abilities (metroidvanias): [airJumps] (double jump), [wallJump]
///   (slide down walls and jump off them) and a dash ([dashSpeed], `dash()`).
class CharacterController2DComponent extends EmberComponent {
  double moveSpeed;
  double jumpVelocity;
  double gravity;
  double coyoteTimeDuration;
  double jumpBufferDuration;
  double groundY;

  /// Extra jumps in mid-air (1 = double jump).
  int airJumps;

  /// Slide down walls and jump off them.
  bool wallJump;
  double wallSlideSpeed;

  /// Speed of `dash()` (0 = no dash) and how long it lasts.
  double dashSpeed;
  double dashTime;

  int _airJumpsLeft = 0;
  int _wallDir = 0;
  double _wallLock = 0;
  double _dashTimer = 0;
  double _dashCooldown = 0;
  int _dashDir = 1;
  bool _canDash = true;

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
    this.airJumps = 0,
    this.wallJump = false,
    this.wallSlideSpeed = 110,
    this.dashSpeed = 0,
    this.dashTime = 0.18,
  });

  /// -1 touching a wall on the left, 1 on the right, 0 none (while in the air).
  int get onWall => _wallDir;
  int get airJumpsLeft => _airJumpsLeft;
  bool get dashing => _dashTimer > 0;

  /// Dashes the way it faces. One dash in the air until landing; returns false if it can't.
  bool dash() {
    if (dashSpeed <= 0 || _dashTimer > 0 || _dashCooldown > 0 || !_canDash) return false;
    _dashTimer = dashTime;
    _dashCooldown = dashTime + 0.25;
    _dashDir = _facing;
    if (!_isGrounded) _canDash = false;
    _velocity.y = 0;
    entity?.notifyScripts((s) => s.onMessage('onDash', const []));
    return true;
  }

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

    // 1. Horizontal acceleration (briefly ignored after a wall jump; a dash overrides it)
    if (_dashCooldown > 0) _dashCooldown -= dt;
    final dashingNow = _dashTimer > 0;
    if (dashingNow) {
      _dashTimer -= dt;
      _velocity.x = _dashDir * dashSpeed;
      _velocity.y = 0;
    } else if (_wallLock > 0) {
      _wallLock -= dt;
    } else {
      final targetVx = horizontalInput * moveSpeed;
      _velocity.x += (targetVx - _velocity.x) * math.min(1.0, dt * 16.0);
    }

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
    } else if (isJumpJustPressed && !dashingNow) {
      if (wallJump && _wallDir != 0) {
        // Off the wall, away from it
        _velocity.x = -_wallDir * moveSpeed * 1.15;
        _velocity.y = -jumpVelocity * 0.95;
        _facing = -_wallDir;
        _wallLock = 0.16;
        _jumpBufferTimer = 0.0;
        entity?.notifyScripts((s) => s.onMessage('onWallJump', const []));
      } else if (_airJumpsLeft > 0) {
        _velocity.y = -jumpVelocity * 0.92;
        _airJumpsLeft--;
        _jumpBufferTimer = 0.0;
        entity?.notifyScripts((s) => s.onMessage('onAirJump', const []));
      }
    }

    // 4. Variable Jump Height: If player releases jump while moving up, cut velocity
    if (!isJumpPressed && _velocity.y < -50.0) {
      _velocity.y *= 0.5;
    }

    // 5. Apply Gravity (not mid-dash; ground contact is re-detected every frame)
    if (!dashingNow) _velocity.y += gravity * dt;
    // Sliding down a wall while pushing against it
    if (wallJump && _wallDir != 0 && !_isGrounded && _velocity.y > wallSlideSpeed && horizontalInput * _wallDir > 0.1) {
      _velocity.y = wallSlideSpeed;
    }

    if (_wallLock <= 0 && !dashingNow) {
      if (horizontalInput > 0.1) _facing = 1;
      if (horizontalInput < -0.1) _facing = -1;
    }

    // 6. Integrate Position one axis at a time against the tiles near the character
    final w = t2d.size.x * t2d.scale.x;
    final h = t2d.size.y * t2d.scale.y;
    final anchor = t2d.anchorOffset;
    final prevBottom = t2d.position.y - anchor.y + h;
    _isGrounded = false;
    _hitWall = false;

    var x = t2d.position.x + _velocity.x * dt;
    var y = t2d.position.y;
    final reach = (_velocity.x.abs() + _velocity.y.abs()) * dt + 2;
    final nearby = _tilesNear(Rect.fromLTWH(t2d.position.x - anchor.x, t2d.position.y - anchor.y, w, h).inflate(reach));

    for (final tile in nearby) {
      if (!tile.kind.blocks || !_overlaps(tile.rect, x - anchor.x, y - anchor.y, w, h)) continue;
      if (_velocity.x > 0) {
        x = tile.rect.left - w + anchor.x;
      } else if (_velocity.x < 0) {
        x = tile.rect.right + anchor.x;
      }
      _velocity.x = 0.0;
      _hitWall = true;
    }

    y += _velocity.y * dt;
    final bumped = <TileHit>[];
    final movingUp = _velocity.y < 0;
    for (final tile in nearby) {
      if (!_overlaps(tile.rect, x - anchor.x, y - anchor.y, w, h)) continue;
      final r = tile.rect;
      if (tile.kind.blocks) {
        if (_velocity.y > 0) {
          y = r.top - h + anchor.y;
          _isGrounded = true;
        } else if (_velocity.y < 0) {
          y = r.bottom + anchor.y;
          bumped.add(tile);
        }
        _velocity.y = 0.0;
      } else if (tile.kind == TileKind.oneWay && _velocity.y > 0 && prevBottom <= r.top + 0.5) {
        // Platforms you can jump up through but stand on
        y = r.top - h + anchor.y;
        _isGrounded = true;
        _velocity.y = 0.0;
      }
    }

    // 7. Fallback world floor at [groundY]
    final footY = y + (h - anchor.y);
    if (footY >= groundY) {
      y = groundY - (h - anchor.y);
      _velocity.y = 0.0;
      _isGrounded = true;
    }

    t2d.position = vm.Vector2(x, y);

    // Abilities recharge on the ground; walls are felt just beside the body
    if (_isGrounded) {
      _airJumpsLeft = airJumps;
      _canDash = true;
    }
    _wallDir = 0;
    if (!_isGrounded && wallJump) {
      final top = y - anchor.y + 4, height = h - 8;
      bool solid(double left) => _tilesNear(Rect.fromLTWH(left, top, 2, height)).any((tile) => tile.kind.blocks && tile.rect.overlaps(Rect.fromLTWH(left, top, 2, height)));
      if (solid(x - anchor.x - 2)) _wallDir = -1;
      if (solid(x - anchor.x + w)) _wallDir = 1;
    }

    // 8. Events: the block most directly overhead was bumped; hazards touched
    final self = entity;
    if (self != null) {
      if (movingUp && bumped.isNotEmpty) {
        final cx = x - anchor.x + w / 2;
        bumped.sort((a, b) => (a.rect.center.dx - cx).abs().compareTo((b.rect.center.dx - cx).abs()));
        final hit = bumped.first;
        self.notifyScripts((s) => s.onHeadBump(hit));
      }
      // Hazards use a slightly smaller body: grazing the edge of a spike tile
      // (whose art rarely fills the whole cell) should not count as a hit.
      final body = Rect.fromLTWH(x - anchor.x, y - anchor.y, w, h).deflate(hazardForgiveness);
      for (final tile in nearby.followedBy(_tilesNear(body.inflate(1)))) {
        if (tile.kind == TileKind.hazard && tile.rect.overlaps(body)) {
          self.notifyScripts((s) => s.onTileTouch(tile));
        }
      }
    }
  }

  /// Pixels trimmed from each side of the character when checking hazard tiles.
  double hazardForgiveness = 4.0;

  int _facing = 1;
  bool _hitWall = false;

  /// 1 when last moving right, -1 when last moving left.
  int get facing => _facing;
  set facing(int value) => _facing = value < 0 ? -1 : 1;

  /// True if horizontal movement was blocked by a wall this frame.
  bool get hitWall => _hitWall;

  /// True if a tile a character can stand on (solid or one-way) covers the
  /// world point ([x], [y]) — e.g. to check for a ledge ahead.
  bool hasGroundAt(double x, double y) =>
      _tilesNear(Rect.fromLTWH(x - 0.5, y - 0.5, 1, 1)).any((t) => t.kind.blocks || t.kind == TileKind.oneWay);

  /// True if a hazard tile (spikes, lava) covers the world point ([x], [y]).
  bool hasHazardAt(double x, double y) =>
      _tilesNear(Rect.fromLTWH(x - 0.5, y - 0.5, 1, 1)).any((t) => t.kind == TileKind.hazard);

  /// Launches the character upward (e.g. after stomping an enemy or a spring).
  void bounce(double strength) {
    _velocity.y = -strength;
    _isGrounded = false;
    _coyoteTimer = 0.0;
  }

  static bool _overlaps(Rect r, double left, double top, double w, double h) {
    const eps = 0.01;
    return left + w > r.left + eps &&
        left < r.right - eps &&
        top + h > r.top + eps &&
        top < r.bottom - eps;
  }

  /// Non-empty tiles of every tilemap in the scene that overlap [area].
  List<TileHit> _tilesNear(Rect area) {
    final scene = entity?.scene;
    if (scene == null) return const [];
    final hits = <TileHit>[];
    for (final map in scene.componentsOf<FlameTileMapComponent>()) {
      final e = map.entity;
      if (e == null || !e.enabled || !map.enabled || !map.collision) continue;
      hits.addAll(map.tilesIn(area));
    }
    return hits;
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
        InspectableProperty<int>(
          name: 'airJumps',
          label: 'Air Jumps',
          type: InspectableType.integer,
          getter: () => airJumps,
          setter: (val) {
            airJumps = val.clamp(0, 5);
            notifyListeners();
          },
          min: 0,
          max: 5,
          step: 1,
          tooltip: '1 = double jump',
        ),
        InspectableProperty<bool>(
          name: 'wallJump',
          label: 'Wall Jump',
          type: InspectableType.boolean,
          getter: () => wallJump,
          setter: (val) {
            wallJump = val;
            notifyListeners();
          },
          tooltip: 'Slide down walls and jump off them',
        ),
        InspectableProperty<double>(
          name: 'dashSpeed',
          label: 'Dash Speed',
          type: InspectableType.number,
          getter: () => dashSpeed,
          setter: (val) {
            dashSpeed = val < 0 ? 0 : val;
            notifyListeners();
          },
          min: 0,
          step: 20,
          tooltip: '0 = no dash; scripts call controller.dash()',
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
      if (airJumps != 0) 'airJumps': airJumps,
      if (wallJump) 'wallJump': true,
      if (wallSlideSpeed != 110) 'wallSlideSpeed': wallSlideSpeed,
      if (dashSpeed != 0) 'dashSpeed': dashSpeed,
      if (dashTime != 0.18) 'dashTime': dashTime,
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
    airJumps = (json['airJumps'] as num?)?.toInt() ?? 0;
    wallJump = json['wallJump'] as bool? ?? false;
    wallSlideSpeed = (json['wallSlideSpeed'] as num?)?.toDouble() ?? 110;
    dashSpeed = (json['dashSpeed'] as num?)?.toDouble() ?? 0;
    dashTime = (json['dashTime'] as num?)?.toDouble() ?? 0.18;
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
      airJumps: airJumps,
      wallJump: wallJump,
      wallSlideSpeed: wallSlideSpeed,
      dashSpeed: dashSpeed,
      dashTime: dashTime,
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

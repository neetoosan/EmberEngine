import 'dart:math' as math;
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/assets.dart';
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../combat/combat.dart';
import 'camera2d.dart';
import 'flame_components.dart';

/// One bullet. Angles are in degrees: 0 points right, 90 points down.
class Bullet2D {
  double x, y, angle, speed;
  double accel, curve, maxSpeed;
  double radius, scale, damage, life, age = 0;
  int frame;
  bool grazed = false;

  /// Homing: turns toward this entity at [turn] degrees per second while it lives.
  EmberEntity? target;
  double turn;

  /// Damages everything of another team within this radius of the hit.
  double splash;

  /// Removed (by clear or clearAround) while the pool was updating.
  bool removed = false;

  Bullet2D(this.x, this.y, this.angle, this.speed,
      {this.accel = 0, this.curve = 0, this.maxSpeed = 0, this.radius = 6, this.scale = 1, this.damage = 1, this.life = 10, this.frame = 0,
      this.target, this.turn = 540, this.splash = 0});

  double get vx => math.cos(angle * math.pi / 180) * speed;
  double get vy => math.sin(angle * math.pi / 180) * speed;
}

/// Many cheap bullets (shoot-'em-ups, bullet hell, turrets) without one
/// entity per bullet. Bullets fly, curve and speed up; leave when they are
/// off camera or too old; and damage the first entity with Health of another
/// [team] they touch. All of them are drawn in one batch from a sprite sheet,
/// glowing ([additive]) if wanted. A bullet can home in on a target and
/// explode with splash damage (towers, missiles); each hit sends
/// `onBulletHit(position, victim, frame)` to the pool's scripts (for effects).
///
/// Scripts: `self.bullets.fire(pos, angle, speed)`, `ring`, `spread`,
/// `clear()`, `clearAround(pos, radius)` (a bomb), `count`.
class BulletPool2DComponent extends EmberComponent {
  String image;
  int columns;
  int rows;
  int maxBullets;
  String team;
  double damage;
  bool additive;
  bool rotate;
  double size;
  double grazeRadius;
  double margin;
  Color color;

  /// Bullets stop at solid tiles of tilemaps with collision (walls).
  bool hitWalls = false;

  final List<Bullet2D> _bullets = [];

  /// True while [onUpdate] walks the list: removals are then deferred, since
  /// a hit can run scripts that clear bullets (a bomb, the player's death).
  bool _updating = false;

  BulletPool2DComponent({
    this.image = '',
    this.columns = 1,
    this.rows = 1,
    this.maxBullets = 2000,
    this.team = 'monster',
    this.damage = 1,
    this.additive = true,
    this.rotate = true,
    this.size = 24,
    this.grazeRadius = 0,
    this.margin = 48,
    this.color = const Color(0xFFFF5CA8),
  });

  List<Bullet2D> get bullets => _bullets;
  int get count => _updating ? _bullets.where((b) => !b.removed).length : _bullets.length;

  /// Fires one bullet from ([x], [y]) at [angle] degrees and [speed] px/s.
  /// [curve] turns it (degrees/s), [accel] changes its speed (px/s²) up to
  /// [maxSpeed] (0 = no limit). Returns false when the pool is full.
  bool fire(double x, double y, double angle, double speed,
      {int frame = 0,
      double? radius,
      double accel = 0,
      double curve = 0,
      double maxSpeed = 0,
      double scale = 1,
      double? damage,
      double life = 10,
      EmberEntity? target,
      double turn = 540,
      double splash = 0}) {
    if (_bullets.length >= maxBullets) return false;
    _bullets.add(Bullet2D(x, y, angle, speed,
        frame: frame,
        radius: radius ?? size * 0.25 * scale,
        accel: accel,
        curve: curve,
        maxSpeed: maxSpeed,
        scale: scale,
        damage: damage ?? this.damage,
        life: life,
        target: target,
        turn: turn,
        splash: splash));
    return true;
  }

  /// [count] bullets evenly around a circle, the first at [offset] degrees.
  void ring(double x, double y, int count, double speed, {double offset = 0, int frame = 0, double? radius, double accel = 0, double curve = 0, double maxSpeed = 0, double scale = 1, double? damage}) {
    for (var i = 0; i < count; i++) {
      fire(x, y, offset + 360 * i / count, speed, frame: frame, radius: radius, accel: accel, curve: curve, maxSpeed: maxSpeed, scale: scale, damage: damage);
    }
  }

  /// [count] bullets fanned over [arc] degrees, centred on [angle].
  void spread(double x, double y, double angle, int count, double arc, double speed,
      {int frame = 0, double? radius, double accel = 0, double curve = 0, double maxSpeed = 0, double scale = 1, double? damage}) {
    for (var i = 0; i < count; i++) {
      final a = count == 1 ? angle : angle - arc / 2 + arc * i / (count - 1);
      fire(x, y, a, speed, frame: frame, radius: radius, accel: accel, curve: curve, maxSpeed: maxSpeed, scale: scale, damage: damage);
    }
  }

  /// Removes every bullet. Returns how many there were.
  int clear() => _removeWhere((_) => true);

  /// Removes the bullets within [radius] of ([x], [y]). Returns how many.
  int clearAround(double x, double y, double radius) {
    final r2 = radius * radius;
    return _removeWhere((b) => (b.x - x) * (b.x - x) + (b.y - y) * (b.y - y) <= r2);
  }

  int _removeWhere(bool Function(Bullet2D b) test) {
    var n = 0;
    for (final b in _bullets) {
      if (!b.removed && test(b)) {
        b.removed = true;
        n++;
      }
    }
    if (!_updating) _bullets.removeWhere((b) => b.removed);
    return n;
  }

  @override
  void onUpdate(double dt) {
    final self = entity;
    final scene = self?.scene;
    if (self == null || scene == null || _bullets.isEmpty) return;

    Rect? keep;
    final camera = Camera2DComponent.findIn(scene);
    if (camera != null) {
      final c = camera.position;
      keep = Rect.fromCenter(center: Offset(c.x, c.y), width: camera.viewWidth + 2 * margin, height: camera.viewHeight + 2 * margin);
    }

    _walls = hitWalls ? [for (final m in scene.componentsOf<FlameTileMapComponent>()) if (m.collision && m.enabled && (m.entity?.enabled ?? false)) m] : const [];

    final targets = <(HealthComponent, Rect)>[];
    for (final h in scene.componentsOf<HealthComponent>()) {
      final e = h.entity;
      if (e == null || !e.enabled || !h.enabled || h.isDead || h.team == team) continue;
      targets.add((h, Combat.bodyOf(e)));
    }

    _updating = true;
    try {
      for (final b in List<Bullet2D>.of(_bullets)) {
        if (!b.removed && !_step(b, dt, keep, targets)) b.removed = true;
      }
    } finally {
      _updating = false;
      _bullets.removeWhere((b) => b.removed);
    }
  }

  /// Moves [b]; false when it is gone.
  bool _step(Bullet2D b, double dt, Rect? keep, List<(HealthComponent, Rect)> targets) {
    b.age += dt;
    if (b.age >= b.life) return false;
    final target = b.target;
    if (target != null) {
      if (!target.enabled || target.scene == null || (target.getComponent<HealthComponent>()?.isDead ?? false)) {
        b.target = null; // flies on straight
      } else {
        final c = Combat.bodyOf(target).center;
        final want = math.atan2(c.dy - b.y, c.dx - b.x) * 180 / math.pi;
        final diff = ((want - b.angle + 540) % 360) - 180;
        final step = b.turn * dt;
        b.angle += diff.clamp(-step, step);
      }
    }
    if (b.curve != 0) b.angle += b.curve * dt;
    if (b.accel != 0) {
      b.speed = math.max(0, b.speed + b.accel * dt);
      if (b.maxSpeed > 0 && b.speed > b.maxSpeed) b.speed = b.maxSpeed;
    }
    final rad = b.angle * math.pi / 180;
    b.x += math.cos(rad) * b.speed * dt;
    b.y += math.sin(rad) * b.speed * dt;
    if (keep != null && !keep.contains(Offset(b.x, b.y))) return false;
    if (_walls.isNotEmpty && _wallAt(b.x, b.y)) {
      final at = vm.Vector2(b.x, b.y);
      entity?.notifyScripts((s) => s.onMessage('onBulletHit', [at, null, b.frame]));
      return false;
    }

    for (final (health, body) in targets) {
      if (health.isDead) continue;
      final d2 = _distanceSquared(body, b.x, b.y);
      if (d2 <= b.radius * b.radius) {
        if (health.isInvulnerable) continue; // passes through a flashing player
        _hit(b, health, targets);
        return false;
      }
      if (grazeRadius > 0 && !b.grazed && d2 <= (b.radius + grazeRadius) * (b.radius + grazeRadius)) {
        b.grazed = true;
        health.entity?.notifyScripts((s) => s.onMessage('onGraze', const []));
      }
    }
    return true;
  }

  void _hit(Bullet2D b, HealthComponent first, List<(HealthComponent, Rect)> targets) {
    final victim = first.entity;
    if (b.splash > 0) {
      final r2 = b.splash * b.splash;
      for (final (health, body) in targets) {
        if (!health.isDead && _distanceSquared(body, b.x, b.y) <= r2) health.damage(b.damage, source: entity);
      }
    } else {
      first.damage(b.damage, source: entity);
    }
    final at = vm.Vector2(b.x, b.y);
    entity?.notifyScripts((s) => s.onMessage('onBulletHit', [at, victim, b.frame]));
  }

  List<FlameTileMapComponent> _walls = const [];

  bool _wallAt(double x, double y) {
    for (final m in _walls) {
      final r = m.cellRect(0, 0);
      if (r.width <= 0) continue;
      final id = m.getTile(((x - r.left) / r.width).floor(), ((y - r.top) / r.height).floor());
      if (id > 0 && m.kindOf(id).blocks) return true;
    }
    return false;
  }

  static double _distanceSquared(Rect r, double x, double y) {
    final dx = x < r.left ? r.left - x : (x > r.right ? x - r.right : 0.0);
    final dy = y < r.top ? r.top - y : (y > r.bottom ? y - r.bottom : 0.0);
    return dx * dx + dy * dy;
  }

  /// Draws every bullet in world space (one batch).
  void paint(Canvas canvas) {
    if (_bullets.isEmpty) return;
    final img = image.isEmpty ? null : EmberAssets.instance.image(image);
    if (img == null) {
      final glow = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..blendMode = additive ? BlendMode.plus : BlendMode.srcOver;
      final core = Paint()..color = const Color(0xFFFFFFFF);
      for (final b in _bullets) {
        canvas.drawCircle(Offset(b.x, b.y), size * 0.5 * b.scale, glow);
        canvas.drawCircle(Offset(b.x, b.y), size * 0.22 * b.scale, core);
      }
      return;
    }
    final cols = columns < 1 ? 1 : columns, rws = rows < 1 ? 1 : rows;
    final cw = img.width / cols, ch = img.height / rws;
    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    for (final b in _bullets) {
      if (b.removed) continue;
      final f = b.frame % (cols * rws);
      final s = size * b.scale / math.max(cw, ch);
      final rad = rotate ? b.angle * math.pi / 180 : 0.0;
      transforms.add(RSTransform.fromComponents(
          rotation: rad, scale: s, anchorX: cw / 2, anchorY: ch / 2, translateX: b.x, translateY: b.y));
      rects.add(Rect.fromLTWH((f % cols) * cw, (f ~/ cols) * ch, cw, ch));
    }
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..blendMode = additive ? BlendMode.plus : BlendMode.srcOver;
    canvas.drawAtlas(img, transforms, rects, null, null, null, paint);
  }

  @override
  String get displayName => 'Bullet Pool 2D';

  InspectableProperty<T> _prop<T>(String name, String label, InspectableType type, T Function() get, void Function(T) set,
          {String? tooltip, double? min, double? max, double? step}) =>
      InspectableProperty<T>(
          name: name,
          label: label,
          type: type,
          getter: get,
          setter: (v) {
            set(v);
            notifyListeners();
          },
          tooltip: tooltip,
          min: min,
          max: max,
          step: step ?? 0.1);

  @override
  List<InspectableProperty> get inspectableProperties => [
        _prop<String>('image', 'Bullet Image', InspectableType.string, () => image, (v) => image = v, tooltip: 'Sprite sheet; empty draws glowing dots'),
        _prop<int>('columns', 'Sheet Columns', InspectableType.integer, () => columns, (v) => columns = v.clamp(1, 64), min: 1, max: 64, step: 1),
        _prop<int>('rows', 'Sheet Rows', InspectableType.integer, () => rows, (v) => rows = v.clamp(1, 64), min: 1, max: 64, step: 1),
        _prop<double>('size', 'Size', InspectableType.number, () => size, (v) => size = v, min: 1, step: 1, tooltip: 'Drawn size of a bullet in pixels'),
        _prop<String>('team', 'Team', InspectableType.string, () => team, (v) => team = v, tooltip: 'Bullets never hurt entities of this team'),
        _prop<double>('damage', 'Damage', InspectableType.number, () => damage, (v) => damage = v, min: 0, step: 0.5),
        _prop<bool>('additive', 'Glow (additive)', InspectableType.boolean, () => additive, (v) => additive = v, tooltip: 'Bright colours add up like light'),
        _prop<bool>('rotate', 'Face Direction', InspectableType.boolean, () => rotate, (v) => rotate = v),
        _prop<int>('maxBullets', 'Max Bullets', InspectableType.integer, () => maxBullets, (v) => maxBullets = v.clamp(1, 20000), min: 1, step: 100),
        _prop<double>('grazeRadius', 'Graze Radius', InspectableType.number, () => grazeRadius, (v) => grazeRadius = v,
            min: 0, step: 1, tooltip: 'Bullets passing this close send onGraze() to the target (0 = off)'),
        _prop<double>('margin', 'Off-screen Margin', InspectableType.number, () => margin, (v) => margin = v,
            min: 0, step: 8, tooltip: 'Bullets this far outside the camera are removed'),
        _prop<Color>('color', 'Dot Color', InspectableType.color, () => color, (v) => color = v, tooltip: 'Used when there is no image'),
        _prop<bool>('hitWalls', 'Stop at Walls', InspectableType.boolean, () => hitWalls, (v) => hitWalls = v,
            tooltip: 'Bullets end on solid tiles (onBulletHit with no victim)'),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'image': image,
        'columns': columns,
        'rows': rows,
        'maxBullets': maxBullets,
        'team': team,
        'damage': damage,
        'additive': additive,
        'rotate': rotate,
        'size': size,
        'grazeRadius': grazeRadius,
        'margin': margin,
        'color': color.toARGB32(),
        if (hitWalls) 'hitWalls': true,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    image = json['image'] as String? ?? '';
    columns = (json['columns'] as num?)?.toInt() ?? 1;
    rows = (json['rows'] as num?)?.toInt() ?? 1;
    maxBullets = (json['maxBullets'] as num?)?.toInt() ?? 2000;
    team = json['team'] as String? ?? 'monster';
    damage = (json['damage'] as num?)?.toDouble() ?? 1;
    additive = json['additive'] as bool? ?? true;
    rotate = json['rotate'] as bool? ?? true;
    size = (json['size'] as num?)?.toDouble() ?? 24;
    grazeRadius = (json['grazeRadius'] as num?)?.toDouble() ?? 0;
    margin = (json['margin'] as num?)?.toDouble() ?? 48;
    color = Color(json['color'] as int? ?? 0xFFFF5CA8);
    hitWalls = json['hitWalls'] as bool? ?? false;
    notifyListeners();
  }

  @override
  BulletPool2DComponent clone() => BulletPool2DComponent()..fromJson(toJson());
}

void registerBulletPool() {
  ComponentRegistry.register('Bullet Pool 2D', (json) => BulletPool2DComponent()..fromJson(json));
}


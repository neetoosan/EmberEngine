import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import '../physics/character_controller3d.dart';
import '../physics/tile_collision.dart';
import '../three_d/components3d.dart';
import '../two_d/flame_components.dart';
import '../two_d/top_down_controller.dart';

/// Hit points for players, monsters and breakables.
///
/// Damage respects [team] (no friendly fire), grants [invulnerableTime]
/// seconds of immunity, flashes the sprite (2D) or every mesh (3D) red,
/// applies knockback through a Top-Down Controller (2D) or Character
/// Controller 3D, and sends `onDamaged` / `onDeath` to the entity's scripts.
/// With [destroyOnDeath] the entity is removed when it dies.
class HealthComponent extends EmberComponent {
  double maxHealth;
  double health;
  String team;
  double invulnerableTime;
  bool destroyOnDeath;

  /// How a 2D sprite shows a hit: "red" (tinted), "white" (a bright flash,
  /// good for fast games where things are hit many times a second) or "none".
  String hitFlash;

  /// Shows a small health bar above it (2D) once it has been hurt.
  bool showBar;

  double _invulnerable = 0;
  double _flash = 0;
  Color? _tintBeforeFlash;

  HealthComponent({
    this.maxHealth = 3,
    double? health,
    this.team = 'monster',
    this.invulnerableTime = 0.3,
    this.destroyOnDeath = true,
    this.hitFlash = 'red',
    this.showBar = false,
  }) : health = health ?? maxHealth;

  bool get isDead => health <= 0;
  bool get isInvulnerable => _invulnerable > 0;

  /// Applies [amount] damage unless dead, invulnerable, or on the same team as
  /// [source]. [knockback] (world pixels/second) pushes a 2D target away;
  /// [push] (metres/second) pushes a 3D one. Returns true if damage was dealt.
  bool damage(double amount, {EmberEntity? source, vm.Vector2? knockback, vm.Vector3? push}) {
    final self = entity;
    if (self == null || isDead || _invulnerable > 0 || amount <= 0) return false;
    final sourceTeam = source?.getComponent<HealthComponent>()?.team ?? _teamTag(source);
    if (sourceTeam != null && sourceTeam == team) return false;

    health = math.max(0, health - amount);
    _invulnerable = invulnerableTime;
    _startFlash();
    if (knockback != null) self.getComponent<TopDownController2DComponent>()?.knockback(knockback);
    if (push != null) self.getComponent<CharacterController3DComponent>()?.knockback(push);
    self.notifyScripts((s) => s.onDamaged(amount, source));
    if (isDead) {
      self.notifyScripts((s) => s.onDeath(source));
      source?.notifyScripts((s) => s.onKill(self));
      if (destroyOnDeath) self.scene?.destroyLater(self);
    }
    notifyListeners();
    return true;
  }

  /// Dies right away (ignores team and invulnerability), e.g. a robot that self-destructs.
  void kill({EmberEntity? source}) {
    final self = entity;
    if (self == null || isDead) return;
    health = 0;
    self.notifyScripts((s) => s.onDeath(source));
    if (source != null && !identical(source, self)) source.notifyScripts((s) => s.onKill(self));
    if (destroyOnDeath) self.scene?.destroyLater(self);
    notifyListeners();
  }

  void heal(double amount) {
    if (isDead) return;
    health = math.min(maxHealth, health + amount);
    notifyListeners();
  }

  /// Projectiles carry their shooter's team as a `team:<name>` tag.
  static String? _teamTag(EmberEntity? e) {
    if (e == null) return null;
    for (final t in e.tags) {
      if (t.startsWith('team:')) return t.substring(5);
    }
    return null;
  }

  /// Colour of the hit flash on 3D meshes.
  static const Color meshFlashColor = Color(0xFFFF4D4D);

  void _startFlash() {
    final self = entity;
    if (self != null) _flashMeshes(self);
    final sprite = entity?.getComponent<FlameSpriteComponent>();
    if (sprite == null || hitFlash == 'none') return;
    if (hitFlash == 'white') {
      // A flash plays out before the next starts, so steady fire flickers
      if (sprite.flash <= 0) sprite.flash = 1;
      return;
    }
    _tintBeforeFlash ??= sprite.tint;
    sprite.tint = const Color(0xFFFF5A5A);
    _flash = 0.12;
  }

  static void _flashMeshes(EmberEntity e) {
    e.getComponent<MeshRenderer3DComponent>()?.flash(meshFlashColor, 0.14);
    for (final c in e.children) {
      _flashMeshes(c);
    }
  }

  @override
  void onUpdate(double dt) {
    if (_invulnerable > 0) _invulnerable -= dt;
    final sprite = entity?.getComponent<FlameSpriteComponent>();
    if (sprite != null && sprite.flash > 0) sprite.flash = math.max(0, sprite.flash - dt * 9);
    if (_flash > 0) {
      _flash -= dt;
      if (_flash <= 0) {
        final sprite = entity?.getComponent<FlameSpriteComponent>();
        if (sprite != null && _tintBeforeFlash != null) sprite.tint = _tintBeforeFlash!;
        _tintBeforeFlash = null;
      }
    }
  }

  @override
  String get displayName => 'Health';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<double>(
          name: 'maxHealth',
          label: 'Max Health',
          type: InspectableType.number,
          getter: () => maxHealth,
          setter: (v) {
            maxHealth = v;
            health = math.min(health, v);
            notifyListeners();
          },
          min: 1,
          step: 1,
        ),
        InspectableProperty<String>(
          name: 'team',
          label: 'Team',
          type: InspectableType.string,
          getter: () => team,
          setter: (v) {
            team = v;
            notifyListeners();
          },
          tooltip: 'Same team never damages itself (e.g. player / monster)',
        ),
        InspectableProperty<double>(
          name: 'invulnerableTime',
          label: 'Invulnerable After Hit (s)',
          type: InspectableType.number,
          getter: () => invulnerableTime,
          setter: (v) {
            invulnerableTime = v;
            notifyListeners();
          },
          min: 0,
          step: 0.05,
        ),
        InspectableProperty<bool>(
          name: 'destroyOnDeath',
          label: 'Remove On Death',
          type: InspectableType.boolean,
          getter: () => destroyOnDeath,
          setter: (v) {
            destroyOnDeath = v;
            notifyListeners();
          },
        ),
        InspectableProperty<String>(
          name: 'hitFlash',
          label: 'Hit Flash',
          type: InspectableType.options,
          options: const ['red', 'white', 'none'],
          getter: () => hitFlash,
          setter: (v) {
            hitFlash = v;
            notifyListeners();
          },
          tooltip: 'red: tinted; white: a bright flash (fast games); none',
        ),
        InspectableProperty<bool>(
          name: 'showBar',
          label: 'Health Bar',
          type: InspectableType.boolean,
          getter: () => showBar,
          setter: (v) {
            showBar = v;
            notifyListeners();
          },
          tooltip: 'A small bar above it once it has been hurt (2D)',
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'maxHealth': maxHealth,
        'health': health,
        'team': team,
        'invulnerableTime': invulnerableTime,
        'destroyOnDeath': destroyOnDeath,
        if (hitFlash != 'red') 'hitFlash': hitFlash,
        if (showBar) 'showBar': true,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    maxHealth = (json['maxHealth'] as num?)?.toDouble() ?? 3;
    health = (json['health'] as num?)?.toDouble() ?? maxHealth;
    team = json['team'] as String? ?? 'monster';
    invulnerableTime = (json['invulnerableTime'] as num?)?.toDouble() ?? 0.3;
    destroyOnDeath = json['destroyOnDeath'] as bool? ?? true;
    hitFlash = json['hitFlash'] as String? ?? 'red';
    showBar = json['showBar'] as bool? ?? false;
    notifyListeners();
  }

  @override
  HealthComponent clone() => HealthComponent()..fromJson(toJson());
}

/// Melee and area damage helpers.
class Combat {
  /// World rectangle an entity occupies for combat: its Hitbox 2D if it has
  /// one, otherwise its Transform 2D box.
  static Rect bodyOf(EmberEntity e) {
    final t = e.getComponent<Transform2DComponent>();
    if (t == null) return Rect.zero;
    final h = e.getComponent<FlameHitbox2DComponent>();
    final min = t.worldPosition - t.anchorOffset;
    if (h != null) return Rect.fromLTWH(min.x + h.offset.x, min.y + h.offset.y, h.size.x, h.size.y);
    return Rect.fromLTWH(min.x, min.y, t.size.x * t.scale.x, t.size.y * t.scale.y);
  }

  /// Damages every living entity with a Health component that overlaps
  /// [area] and is not on [team]. Knockback pushes targets away from the
  /// centre of [area]. Returns the entities that were hit.
  static List<EmberEntity> strike(
    EmberScene scene,
    Rect area, {
    required String team,
    required double damage,
    EmberEntity? source,
    double knockback = 0,
  }) {
    final hit = <EmberEntity>[];
    for (final health in scene.componentsOf<HealthComponent>()) {
      final e = health.entity;
      if (e == null || !e.enabled || health.isDead || health.team == team || identical(e, source)) continue;
      final body = bodyOf(e);
      if (!body.overlaps(area)) continue;
      vm.Vector2? push;
      if (knockback > 0) {
        final d = body.center - area.center;
        final len = d.distance;
        final dir = len < 0.001 ? const Offset(0, 1) : d / len;
        push = vm.Vector2(dir.dx * knockback, dir.dy * knockback);
      }
      if (health.damage(damage, source: source, knockback: push)) hit.add(e);
    }
    return hit;
  }
}

/// A moving shot (arrow, fireball). Damages the first enemy of [team] it
/// touches, then disappears; also disappears on walls or after [lifetime].
class ProjectileComponent extends EmberComponent {
  vm.Vector2 velocity;
  double damage;
  String team;
  double lifetime;
  double knockback;
  bool pierce;

  /// Who fired it: damage and kills are credited to them.
  EmberEntity? owner;

  double _age = 0;

  ProjectileComponent({
    vm.Vector2? velocity,
    this.damage = 1,
    this.team = 'monster',
    this.lifetime = 3,
    this.knockback = 120,
    this.pierce = false,
  }) : velocity = velocity ?? vm.Vector2(200, 0);

  @override
  void onUpdate(double dt) {
    final self = entity;
    final scene = self?.scene;
    final t = self?.getComponent<Transform2DComponent>();
    if (self == null || scene == null || t == null) return;
    _age += dt;
    t.position = t.position + velocity * dt;
    // Point the sprite along its flight path
    t.rotation = math.atan2(velocity.y, velocity.x);
    final body = Combat.bodyOf(self);
    final hits = Combat.strike(scene, body, team: team, damage: damage, source: owner ?? self, knockback: knockback);
    if ((hits.isNotEmpty && !pierce) || _age >= lifetime || TileCollision.blocked(scene, body)) {
      scene.destroyLater(self);
    }
  }

  @override
  String get displayName => 'Projectile';

  @override
  Map<String, dynamic> toJson() => {
        'velocity': [velocity.x, velocity.y],
        'damage': damage,
        'team': team,
        'lifetime': lifetime,
        'knockback': knockback,
        'pierce': pierce,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    final v = json['velocity'] as List<dynamic>?;
    velocity = v == null ? vm.Vector2(200, 0) : vm.Vector2((v[0] as num).toDouble(), (v[1] as num).toDouble());
    damage = (json['damage'] as num?)?.toDouble() ?? 1;
    team = json['team'] as String? ?? 'monster';
    lifetime = (json['lifetime'] as num?)?.toDouble() ?? 3;
    knockback = (json['knockback'] as num?)?.toDouble() ?? 120;
    pierce = json['pierce'] as bool? ?? false;
  }

  @override
  ProjectileComponent clone() => ProjectileComponent()..fromJson(toJson());
}

void registerCombatComponents() {
  ComponentRegistry.register('Health', (json) => HealthComponent()..fromJson(json));
  ComponentRegistry.register('Projectile', (json) => ProjectileComponent()..fromJson(json));
}

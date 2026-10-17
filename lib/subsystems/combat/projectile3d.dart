import 'dart:math' as math;
import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart';
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform3d.dart';
import '../particles/particle_system.dart';
import '../physics/character_controller3d.dart';
import '../three_d/components3d.dart';
import '../three_d/material.dart';
import '../three_d/primitives.dart';
import 'combat.dart';

/// A moving 3D shot (plasma orb, rocket). Damages the first entity with a
/// Health on another [team] that it touches, then disappears; also
/// disappears on solid colliders, the floor, or after [lifetime].
///
/// With [splashRadius] > 0 it explodes: everything within the radius takes
/// damage (less further out). [impact] names a scene entity with a Particle
/// Emitter 3D that bursts where the shot lands.
class Projectile3DComponent extends EmberComponent {
  Vector3 velocity;
  double damage;
  String team;
  double lifetime;

  /// Size of the shot for hits (metres).
  double radius;

  /// Downward pull (m/s²); 0 flies straight.
  double gravity;

  /// Push on hit (m/s along the flight direction).
  double knockback;

  double splashRadius;

  /// Name of an entity whose Particle Emitter 3D bursts at the impact point.
  String impact;

  /// Who fired it: damage and kills are credited to them, and it never hits them.
  EmberEntity? owner;

  double _age = 0;

  Projectile3DComponent({
    Vector3? velocity,
    this.damage = 1,
    this.team = 'monster',
    this.lifetime = 4,
    this.radius = 0.25,
    this.gravity = 0,
    this.knockback = 4,
    this.splashRadius = 0,
    this.impact = '',
  }) : velocity = velocity ?? Vector3(0, 0, -20);

  /// A ready-made glowing orb: an entity with a small sphere and this component.
  static EmberEntity orb({
    required Vector3 position,
    required Vector3 velocity,
    required String team,
    double damage = 1,
    double size = 0.35,
    Color color = const Color(0xFFFF7A1A),
    EmberEntity? owner,
    String impact = '',
    double splashRadius = 0,
    String name = 'Shot',
  }) {
    return EmberEntity(name: name)
      ..tags.add('projectile')
      ..addComponent(Transform3DComponent(position: position, scale: Vector3.all(size)))
      ..addComponent(MeshRenderer3DComponent(
        customMesh: _orbMesh,
        material: Material3D(color: color, emission: 1, roughness: 1, metallic: 0),
        castShadows: false,
      ))
      ..addComponent(Projectile3DComponent(
        velocity: velocity,
        damage: damage,
        team: team,
        radius: size * 0.6,
        impact: impact,
        splashRadius: splashRadius,
      )..owner = owner);
  }

  /// Low-poly sphere shared by every orb (they are many and small).
  static final _orbMesh = MeshPrimitives.createSphere(latSegments: 5, lonSegments: 8);

  @override
  void onUpdate(double dt) {
    final self = entity;
    final scene = self?.scene;
    final t = self?.getComponent<Transform3DComponent>();
    if (self == null || scene == null || t == null || !self.enabled) return;
    _age += dt;
    if (gravity != 0) velocity.y -= gravity * dt;
    final from = t.position.clone();
    final step = velocity * dt;
    // Sweep in short hops so fast shots don't pass through thin walls
    final hops = math.max(1, (step.length / math.max(0.05, radius)).ceil());
    for (var i = 1; i <= hops; i++) {
      final p = from + step * (i / hops);
      final hit = _touching(scene, self, p);
      if (hit != null || p.y <= radius * 0.5) {
        t.position = p;
        _land(scene, self, p, hit);
        return;
      }
    }
    t.position = from + step;
    if (_age >= lifetime) scene.destroyLater(self);
  }

  /// The entity this shot touches at [p]: an enemy's Health box or a solid collider.
  EmberEntity? _touching(EmberScene scene, EmberEntity self, Vector3 p) {
    for (final col in scene.componentsOf<Collider3DComponent>()) {
      final e = col.entity;
      if (e == null || identical(e, self) || identical(e, owner) || !e.enabled || !col.enabled || col.isTrigger) continue;
      if (e.tags.contains('projectile')) continue;
      final health = e.getComponent<HealthComponent>();
      if (health != null && (health.team == team || health.isDead)) continue;
      final et = e.getComponent<Transform3DComponent>();
      if (et == null) continue;
      if (_sphereTouchesBox(p, radius, et.worldPosition + col.center, col.size, et.worldScale)) return e;
    }
    // Characters without a collider (e.g. the player): their controller's capsule, as a box
    for (final health in scene.componentsOf<HealthComponent>()) {
      final e = health.entity;
      if (e == null || identical(e, owner) || !e.enabled || health.isDead || health.team == team) continue;
      if (e.hasComponent<Collider3DComponent>()) continue;
      final et = e.getComponent<Transform3DComponent>();
      if (et == null) continue;
      final cc = e.getComponent<CharacterController3DComponent>();
      final size = cc == null ? Vector3(0.8, 1.8, 0.8) : Vector3(cc.radius * 2, cc.height, cc.radius * 2);
      if (_sphereTouchesBox(p, radius, et.worldPosition, size, Vector3.all(1))) return e;
    }
    return null;
  }

  static bool _sphereTouchesBox(Vector3 p, double r, Vector3 center, Vector3 size, Vector3 scale) {
    final hx = size.x * scale.x * 0.5, hy = size.y * scale.y * 0.5, hz = size.z * scale.z * 0.5;
    final dx = math.max(0.0, (p.x - center.x).abs() - hx);
    final dy = math.max(0.0, (p.y - center.y).abs() - hy);
    final dz = math.max(0.0, (p.z - center.z).abs() - hz);
    return dx * dx + dy * dy + dz * dz <= r * r;
  }

  void _land(EmberScene scene, EmberEntity self, Vector3 at, EmberEntity? hit) {
    final credit = owner ?? self;
    final dir = velocity.length2 == 0 ? Vector3(0, 0, -1) : velocity.normalized();
    if (splashRadius > 0) {
      for (final h in scene.componentsOf<HealthComponent>().toList()) {
        final e = h.entity;
        if (e == null || !e.enabled || h.isDead || h.team == team) continue;
        final pos = e.getComponent<Transform3DComponent>()?.worldPosition;
        if (pos == null) continue;
        final d = pos.distanceTo(at);
        if (d > splashRadius) continue;
        final away = d < 0.01 ? dir : (pos - at).normalized();
        final falloff = 1 - 0.5 * d / splashRadius;
        h.damage(damage * falloff, source: credit, push: away * knockback * falloff + Vector3(0, 3 * falloff, 0));
      }
    } else if (hit != null) {
      hit.getComponent<HealthComponent>()?.damage(damage, source: credit, push: dir * knockback);
      self.notifyScripts((s) => s.onMessage('onHit', [hit]));
    }
    if (impact.isNotEmpty) scene.findByName(impact)?.getComponent<ParticleEmitter3DComponent>()?.burst(splashRadius > 0 ? 30 : 10, at);
    scene.destroyLater(self);
  }

  @override
  String get displayName => 'Projectile 3D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<Vector3>(
          name: 'velocity',
          label: 'Velocity (m/s)',
          type: InspectableType.vector3,
          getter: () => velocity,
          setter: (v) => velocity = v,
        ),
        _n('damage', 'Damage', () => damage, (v) => damage = v),
        InspectableProperty<String>(
          name: 'team',
          label: 'Team',
          type: InspectableType.string,
          getter: () => team,
          setter: (v) => team = v,
          tooltip: 'Never hurts Health on the same team',
        ),
        _n('lifetime', 'Lifetime (s)', () => lifetime, (v) => lifetime = v),
        _n('radius', 'Radius (m)', () => radius, (v) => radius = v, step: 0.05),
        _n('gravity', 'Gravity (m/s²)', () => gravity, (v) => gravity = v),
        _n('knockback', 'Knockback (m/s)', () => knockback, (v) => knockback = v),
        _n('splashRadius', 'Splash Radius (m)', () => splashRadius, (v) => splashRadius = v, step: 0.5),
        InspectableProperty<String>(
          name: 'impact',
          label: 'Impact Effect',
          type: InspectableType.string,
          getter: () => impact,
          setter: (v) => impact = v,
          tooltip: 'Name of an entity with a Particle Emitter 3D to burst where it lands',
        ),
      ];

  InspectableProperty<double> _n(String name, String label, double Function() get, void Function(double) set, {double step = 1}) =>
      InspectableProperty<double>(name: name, label: label, type: InspectableType.number, getter: get, setter: set, min: 0, step: step);

  @override
  Map<String, dynamic> toJson() => {
        'velocity': [velocity.x, velocity.y, velocity.z],
        'damage': damage,
        'team': team,
        'lifetime': lifetime,
        'radius': radius,
        'gravity': gravity,
        'knockback': knockback,
        'splashRadius': splashRadius,
        'impact': impact,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    final v = json['velocity'] as List<dynamic>?;
    velocity = v == null ? Vector3(0, 0, -20) : Vector3((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble());
    damage = (json['damage'] as num?)?.toDouble() ?? 1;
    team = json['team'] as String? ?? 'monster';
    lifetime = (json['lifetime'] as num?)?.toDouble() ?? 4;
    radius = (json['radius'] as num?)?.toDouble() ?? 0.25;
    gravity = (json['gravity'] as num?)?.toDouble() ?? 0;
    knockback = (json['knockback'] as num?)?.toDouble() ?? 4;
    splashRadius = (json['splashRadius'] as num?)?.toDouble() ?? 0;
    impact = json['impact'] as String? ?? '';
  }

  @override
  Projectile3DComponent clone() => Projectile3DComponent()..fromJson(toJson());
}

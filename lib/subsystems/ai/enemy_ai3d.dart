import 'dart:math' as math;
import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart';
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform3d.dart';
import '../combat/combat.dart';
import '../combat/projectile3d.dart';
import '../particles/particle_system.dart';
import '../physics/character_controller3d.dart';
import '../physics/physics_world3d.dart';

/// How an [EnemyAI3DComponent] fights.
enum EnemyBehavior3D {
  /// Runs at the target and hits it up close (with self-destruct: explodes).
  chaser,

  /// Keeps its distance, strafes, and fires glowing shots when it can see the target.
  shooter,

  /// Walks closer, winds up, then charges in a straight line; dizzy after a charge.
  charger,
}

/// Ready-made 3D enemy brain: finds the entity tagged [targetTag], walks
/// around obstacles and other enemies (through a Character Controller 3D),
/// and attacks according to [behavior].
///
/// Scripts on the enemy receive `onAttack(target)`, `onFire(shot)` and
/// `onCharge()`; its [state] is readable ("chase", "strafe", "windup",
/// "charge", "dizzy", "idle").
class EnemyAI3DComponent extends EmberComponent {
  EnemyBehavior3D behavior;
  String targetTag;
  double moveSpeed;
  double turnSpeed;
  double sightRange;

  // Melee (chaser, charger)
  double attackRange;
  double attackDamage;
  double attackCooldown;
  bool selfDestruct;
  double explosionRadius;

  // Shooter
  double preferredDistance;
  double fireRange;
  double fireCooldown;
  double shotSpeed;
  double shotDamage;
  Color shotColor;
  double aimHeight;

  // Charger
  double chargeSpeed;
  double chargeRange;
  double windup;
  double dizzyTime;

  /// Flying enemies hover at this height (metres above the floor); 0 walks.
  double hoverHeight;

  /// Name of an entity with a Particle Emitter 3D for hits and explosions.
  String impact;

  String state = 'idle';

  EmberEntity? _target;
  double _cooldown = 0, _fireTimer = 0, _stateTime = 0, _strafeSign = 1, _strafeSwitch = 2;
  double _stuckTime = 0, _sidestep = 0, _sidestepSign = 1;
  Vector3 _chargeDir = Vector3.zero();
  bool _chargeHit = false;
  final math.Random _rng = math.Random();

  EnemyAI3DComponent({
    this.behavior = EnemyBehavior3D.chaser,
    this.targetTag = 'player',
    this.moveSpeed = 4,
    this.turnSpeed = 300,
    this.sightRange = 60,
    this.attackRange = 1.6,
    this.attackDamage = 10,
    this.attackCooldown = 1.0,
    this.selfDestruct = false,
    this.explosionRadius = 2.5,
    this.preferredDistance = 10,
    this.fireRange = 30,
    this.fireCooldown = 1.6,
    this.shotSpeed = 14,
    this.shotDamage = 8,
    this.shotColor = const Color(0xFFFF7A1A),
    this.aimHeight = 1.2,
    this.chargeSpeed = 14,
    this.chargeRange = 12,
    this.windup = 0.7,
    this.dizzyTime = 1.2,
    this.hoverHeight = 0,
    this.impact = '',
  });

  EmberEntity? get target => _target;

  @override
  void onStart() {
    final e = entity;
    if (e != null && e.getComponent<CharacterController3DComponent>() == null) {
      e.addComponent(CharacterController3DComponent(walkSpeed: moveSpeed));
    }
    _fireTimer = fireCooldown * (0.4 + _rng.nextDouble() * 0.6); // don't all fire at once
    _strafeSign = _rng.nextBool() ? 1 : -1;
  }

  EmberEntity? _findTarget(EmberScene scene) {
    final t = _target;
    if (t != null && t.scene != null && t.enabled) return t;
    for (final e in scene.allEntities) {
      if (e.enabled && e.tags.contains(targetTag)) return _target = e;
    }
    return _target = null;
  }

  void _setState(String s) {
    if (state == s) return;
    state = s;
    _stateTime = 0;
  }

  @override
  void onUpdate(double dt) {
    final self = entity;
    final scene = self?.scene;
    final t = self?.getComponent<Transform3DComponent>();
    final cc = self?.getComponent<CharacterController3DComponent>();
    if (self == null || scene == null || t == null || cc == null || !self.enabled) return;
    if (self.getComponent<HealthComponent>()?.isDead ?? false) return;
    if (hoverHeight > 0) cc.gravity = 0;
    _cooldown = math.max(0, _cooldown - dt);
    _fireTimer = math.max(0, _fireTimer - dt);
    _stateTime += dt;

    final target = _findTarget(scene);
    final targetDead = target?.getComponent<HealthComponent>()?.isDead ?? false;
    final pos = t.worldPosition;
    if (target == null || targetDead) {
      _setState('idle');
      _drive(cc, t, Vector3.zero(), dt, pos);
      return;
    }
    final tp = target.getComponent<Transform3DComponent>()?.worldPosition ?? pos;
    final to = Vector3(tp.x - pos.x, 0, tp.z - pos.z);
    final dist = to.length;
    final toward = dist < 1e-6 ? Vector3(0, 0, -1) : to / dist;
    if (dist > sightRange) {
      _setState('idle');
      _drive(cc, t, Vector3.zero(), dt, pos);
      return;
    }

    var move = Vector3.zero();
    var face = toward;
    var speed = moveSpeed;
    switch (behavior) {
      case EnemyBehavior3D.chaser:
        _setState('chase');
        move = dist > attackRange * 0.8 ? toward : Vector3.zero(); // stop at arm's length
        if (dist <= attackRange && _cooldown <= 0) _melee(scene, self, target, toward);
      case EnemyBehavior3D.shooter:
        _strafeSwitch -= dt;
        if (_strafeSwitch <= 0) {
          _strafeSign = -_strafeSign;
          _strafeSwitch = 1.5 + _rng.nextDouble() * 2.5;
        }
        final side = Vector3(-toward.z, 0, toward.x) * _strafeSign;
        if (dist > preferredDistance + 2) {
          _setState('chase');
          move = toward + side * 0.3;
        } else if (dist < preferredDistance - 2) {
          _setState('retreat');
          move = -toward + side * 0.5;
        } else {
          _setState('strafe');
          move = side;
          speed = moveSpeed * 0.7;
        }
        final facingErr = _yawError(t, toward);
        if (dist <= fireRange && _fireTimer <= 0 && facingErr < 25) {
          final muzzle = pos + Vector3(0, aimHeight, 0) + toward * 0.7;
          final aim = tp + Vector3(0, 0.25, 0);
          if (_canSee(scene, self, target, muzzle, aim)) _fire(scene, self, muzzle, aim);
        }
      case EnemyBehavior3D.charger:
        switch (state) {
          case 'windup':
            move = Vector3.zero();
            if (_stateTime >= windup) {
              _chargeDir = toward.clone();
              _chargeHit = false;
              _setState('charge');
              self.notifyScripts((s) => s.onMessage('onCharge', const []));
            }
          case 'charge':
            move = _chargeDir;
            face = _chargeDir;
            speed = chargeSpeed;
            if (!_chargeHit && dist <= attackRange + 0.4) {
              _chargeHit = true;
              _hit(target, _chargeDir, attackDamage, push: 12);
              self.notifyScripts((s) => s.onMessage('onAttack', [target]));
            }
            final blocked = _stateTime > 0.2 && Vector3(cc.velocity.x, 0, cc.velocity.z).length < chargeSpeed * 0.25;
            if (_stateTime > 1.1 || blocked || _chargeHit && _stateTime > 0.35) {
              _setState('dizzy');
              _cooldown = attackCooldown;
            }
          case 'dizzy':
            move = Vector3.zero();
            face = t.forward;
            if (_stateTime >= dizzyTime) _setState('chase');
          default:
            _setState('chase');
            move = dist > attackRange * 0.8 ? toward : Vector3.zero();
            if (dist <= chargeRange && dist > attackRange && _cooldown <= 0 &&
                _canSee(scene, self, target, pos + Vector3(0, 0.8, 0), tp)) {
              _setState('windup');
            } else if (dist <= attackRange && _cooldown <= 0) {
              _melee(scene, self, target, toward);
            }
        }
    }

    if (state != 'charge' && state != 'windup' && state != 'dizzy' && move.length2 > 0) {
      move = _avoid(scene, self, pos, move.normalized(), dt);
    }
    _turn(t, face, dt);
    _drive(cc, t, move, dt, pos, speed: speed);
    if (hoverHeight > 0) {
      final bob = math.sin((_stateTime + pos.x) * 3) * 0.12;
      final y = t.position.y + (hoverHeight + bob - t.position.y) * math.min(1, dt * 4);
      t.position = Vector3(t.position.x, y, t.position.z);
    }
  }

  void _drive(CharacterController3DComponent cc, Transform3DComponent t, Vector3 dir, double dt, Vector3 before, {double? speed}) {
    cc.walkSpeed = speed ?? moveSpeed;
    cc.move(dir, false, dt);
    // Stuck against something: sidestep for a moment
    if (dir.length2 > 0 && state != 'charge') {
      final moved = Vector3(t.worldPosition.x - before.x, 0, t.worldPosition.z - before.z).length;
      if (moved < cc.walkSpeed * dt * 0.25) {
        _stuckTime += dt;
        if (_stuckTime > 0.35 && _sidestep <= 0) {
          _sidestep = 0.7;
          _sidestepSign = _rng.nextBool() ? 1 : -1;
        }
      } else {
        _stuckTime = 0;
      }
    }
  }

  /// Steers [dir] away from other enemies and around whatever blocked it lately.
  Vector3 _avoid(EmberScene scene, EmberEntity self, Vector3 pos, Vector3 dir, double dt) {
    var out = dir.clone();
    for (final other in scene.componentsOf<EnemyAI3DComponent>()) {
      final e = other.entity;
      if (e == null || identical(e, self) || !e.enabled) continue;
      final op = e.getComponent<Transform3DComponent>()?.worldPosition;
      if (op == null) continue;
      final away = Vector3(pos.x - op.x, 0, pos.z - op.z);
      final d = away.length;
      if (d > 0.01 && d < 1.8) out += away / d * ((1.8 - d) / 1.8) * 1.5;
    }
    if (_sidestep > 0) {
      _sidestep -= dt;
      out += Vector3(-dir.z, 0, dir.x) * (_sidestepSign * 1.6);
    }
    return out.length2 == 0 ? out : out.normalized();
  }

  double _yawError(Transform3DComponent t, Vector3 dir) {
    final want = math.atan2(-dir.x, -dir.z) * 180 / math.pi;
    var d = (want - t.euler.y) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d.abs();
  }

  void _turn(Transform3DComponent t, Vector3 dir, double dt) {
    if (dir.x * dir.x + dir.z * dir.z < 1e-6) return;
    final want = math.atan2(-dir.x, -dir.z) * 180 / math.pi;
    var d = (want - t.euler.y) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    final step = turnSpeed * dt;
    t.euler = Vector3(t.euler.x, t.euler.y + d.clamp(-step, step), t.euler.z);
  }

  bool _canSee(EmberScene scene, EmberEntity self, EmberEntity target, Vector3 from, Vector3 to) {
    final d = to - from;
    if (d.length2 < 1e-6) return true;
    final hit = PhysicsWorld3D.raycast(scene: scene, origin: from, direction: d, maxDistance: d.length, ignoreEntity: self);
    return hit == null || identical(hit.entity, target) || hit.entity.getComponent<EnemyAI3DComponent>() != null;
  }

  void _hit(EmberEntity target, Vector3 dir, double amount, {double push = 6}) {
    target.getComponent<HealthComponent>()?.damage(amount, source: entity, push: dir * push + Vector3(0, push * 0.3, 0));
  }

  void _melee(EmberScene scene, EmberEntity self, EmberEntity target, Vector3 toward) {
    _cooldown = attackCooldown;
    self.notifyScripts((s) => s.onMessage('onAttack', [target]));
    if (!selfDestruct) {
      _hit(target, toward, attackDamage);
      return;
    }
    // Explode: hurt everything nearby that is not on our team, then die
    final pos = self.getComponent<Transform3DComponent>()!.worldPosition;
    final team = self.getComponent<HealthComponent>()?.team ?? 'monster';
    for (final h in scene.componentsOf<HealthComponent>().toList()) {
      final e = h.entity;
      if (e == null || identical(e, self) || h.team == team || h.isDead) continue;
      final p = e.getComponent<Transform3DComponent>()?.worldPosition;
      if (p == null || p.distanceTo(pos) > explosionRadius) continue;
      final away = Vector3(p.x - pos.x, 0, p.z - pos.z);
      _hit(e, away.length2 == 0 ? toward : away.normalized(), attackDamage, push: 9);
    }
    if (impact.isNotEmpty) scene.findByName(impact)?.getComponent<ParticleEmitter3DComponent>()?.burst(30, pos);
    final own = self.getComponent<HealthComponent>();
    if (own != null) {
      own.kill(source: self);
    } else {
      scene.destroyLater(self);
    }
  }

  void _fire(EmberScene scene, EmberEntity self, Vector3 muzzle, Vector3 aim) {
    _fireTimer = fireCooldown * (0.85 + _rng.nextDouble() * 0.3);
    final team = self.getComponent<HealthComponent>()?.team ?? 'monster';
    final shot = Projectile3DComponent.orb(
      position: muzzle,
      velocity: (aim - muzzle).normalized() * shotSpeed,
      team: team,
      damage: shotDamage,
      color: shotColor,
      owner: self,
      impact: impact,
      name: '${self.name} Shot',
    );
    scene.addEntity(shot);
    self.notifyScripts((s) => s.onMessage('onFire', [shot]));
  }

  @override
  String get displayName => 'Enemy AI 3D';

  InspectableProperty<double> _n(String name, String label, double Function() get, void Function(double) set, {double step = 0.5, double max = 200}) =>
      InspectableProperty<double>(
        name: name,
        label: label,
        type: InspectableType.number,
        getter: get,
        setter: (v) {
          set(v);
          notifyListeners();
        },
        min: 0,
        max: max,
        step: step,
      );

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<EnemyBehavior3D>(
          name: 'behavior',
          label: 'Behavior',
          type: InspectableType.options,
          getter: () => behavior,
          setter: (v) {
            behavior = v;
            notifyListeners();
          },
          options: EnemyBehavior3D.values.map((b) => b.name).toList(),
        ),
        InspectableProperty<String>(
          name: 'targetTag',
          label: 'Target Tag',
          type: InspectableType.string,
          getter: () => targetTag,
          setter: (v) => targetTag = v,
        ),
        _n('moveSpeed', 'Move Speed (m/s)', () => moveSpeed, (v) => moveSpeed = v),
        _n('turnSpeed', 'Turn Speed (°/s)', () => turnSpeed, (v) => turnSpeed = v, step: 10, max: 1000),
        _n('sightRange', 'Sight Range (m)', () => sightRange, (v) => sightRange = v),
        _n('attackRange', 'Attack Range (m)', () => attackRange, (v) => attackRange = v, step: 0.1),
        _n('attackDamage', 'Attack Damage', () => attackDamage, (v) => attackDamage = v, step: 1),
        _n('attackCooldown', 'Attack Cooldown (s)', () => attackCooldown, (v) => attackCooldown = v, step: 0.1),
        InspectableProperty<bool>(
          name: 'selfDestruct',
          label: 'Explodes On Attack',
          type: InspectableType.boolean,
          getter: () => selfDestruct,
          setter: (v) => selfDestruct = v,
        ),
        _n('explosionRadius', 'Explosion Radius (m)', () => explosionRadius, (v) => explosionRadius = v),
        _n('preferredDistance', 'Keep Distance (m)', () => preferredDistance, (v) => preferredDistance = v),
        _n('fireRange', 'Fire Range (m)', () => fireRange, (v) => fireRange = v),
        _n('fireCooldown', 'Fire Cooldown (s)', () => fireCooldown, (v) => fireCooldown = v, step: 0.1),
        _n('shotSpeed', 'Shot Speed (m/s)', () => shotSpeed, (v) => shotSpeed = v),
        _n('shotDamage', 'Shot Damage', () => shotDamage, (v) => shotDamage = v, step: 1),
        InspectableProperty<Color>(
          name: 'shotColor',
          label: 'Shot Color',
          type: InspectableType.color,
          getter: () => shotColor,
          setter: (v) => shotColor = v,
        ),
        _n('aimHeight', 'Muzzle Height (m)', () => aimHeight, (v) => aimHeight = v, step: 0.1),
        _n('chargeSpeed', 'Charge Speed (m/s)', () => chargeSpeed, (v) => chargeSpeed = v),
        _n('chargeRange', 'Charge Range (m)', () => chargeRange, (v) => chargeRange = v),
        _n('windup', 'Charge Wind-up (s)', () => windup, (v) => windup = v, step: 0.1),
        _n('dizzyTime', 'Dizzy After Charge (s)', () => dizzyTime, (v) => dizzyTime = v, step: 0.1),
        _n('hoverHeight', 'Hover Height (m, 0 = walks)', () => hoverHeight, (v) => hoverHeight = v, step: 0.1),
        InspectableProperty<String>(
          name: 'impact',
          label: 'Impact Effect',
          type: InspectableType.string,
          getter: () => impact,
          setter: (v) => impact = v,
          tooltip: 'Name of an entity with a Particle Emitter 3D for hits and explosions',
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'behavior': behavior.name,
        'targetTag': targetTag,
        'moveSpeed': moveSpeed,
        'turnSpeed': turnSpeed,
        'sightRange': sightRange,
        'attackRange': attackRange,
        'attackDamage': attackDamage,
        'attackCooldown': attackCooldown,
        'selfDestruct': selfDestruct,
        'explosionRadius': explosionRadius,
        'preferredDistance': preferredDistance,
        'fireRange': fireRange,
        'fireCooldown': fireCooldown,
        'shotSpeed': shotSpeed,
        'shotDamage': shotDamage,
        'shotColor': shotColor.toARGB32(),
        'aimHeight': aimHeight,
        'chargeSpeed': chargeSpeed,
        'chargeRange': chargeRange,
        'windup': windup,
        'dizzyTime': dizzyTime,
        'hoverHeight': hoverHeight,
        'impact': impact,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    final d = EnemyAI3DComponent();
    double n(String k, double def) => (json[k] as num?)?.toDouble() ?? def;
    behavior = EnemyBehavior3D.values.firstWhere((b) => b.name == json['behavior'], orElse: () => EnemyBehavior3D.chaser);
    targetTag = json['targetTag'] as String? ?? d.targetTag;
    moveSpeed = n('moveSpeed', d.moveSpeed);
    turnSpeed = n('turnSpeed', d.turnSpeed);
    sightRange = n('sightRange', d.sightRange);
    attackRange = n('attackRange', d.attackRange);
    attackDamage = n('attackDamage', d.attackDamage);
    attackCooldown = n('attackCooldown', d.attackCooldown);
    selfDestruct = json['selfDestruct'] as bool? ?? false;
    explosionRadius = n('explosionRadius', d.explosionRadius);
    preferredDistance = n('preferredDistance', d.preferredDistance);
    fireRange = n('fireRange', d.fireRange);
    fireCooldown = n('fireCooldown', d.fireCooldown);
    shotSpeed = n('shotSpeed', d.shotSpeed);
    shotDamage = n('shotDamage', d.shotDamage);
    shotColor = Color(json['shotColor'] as int? ?? d.shotColor.toARGB32());
    aimHeight = n('aimHeight', d.aimHeight);
    chargeSpeed = n('chargeSpeed', d.chargeSpeed);
    chargeRange = n('chargeRange', d.chargeRange);
    windup = n('windup', d.windup);
    dizzyTime = n('dizzyTime', d.dizzyTime);
    hoverHeight = n('hoverHeight', d.hoverHeight);
    impact = json['impact'] as String? ?? '';
    notifyListeners();
  }

  @override
  EnemyAI3DComponent clone() => EnemyAI3DComponent()..fromJson(toJson());
}

void registerEnemyAI3D() {
  ComponentRegistry.register('Enemy AI 3D', (json) => EnemyAI3DComponent()..fromJson(json));
  ComponentRegistry.register('Projectile 3D', (json) => Projectile3DComponent()..fromJson(json));
}

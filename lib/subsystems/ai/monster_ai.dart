import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import '../combat/combat.dart';
import '../physics/tile_collision.dart';
import '../two_d/flame_components.dart';
import '../two_d/sprite_animator.dart';
import '../two_d/top_down_controller.dart';
import 'pathfinding.dart';

enum MonsterState { wander, chase, attack, returning }

/// Configurable monster brain for top-down games.
///
/// Wanders near its spawn point, notices the target (tag [targetTag]) within
/// [sightRange] when it has line of sight, chases it (pathing around walls),
/// attacks in melee or with projectiles, and gives up beyond [loseRange].
/// Needs a Top-Down Controller 2D for movement; uses Health for its team,
/// a Sprite Animator (`idle`, `walk`, `attack` clips) and flips its sprite.
class MonsterAIComponent extends EmberComponent {
  String targetTag;
  double sightRange;
  double attackRange;
  double loseRange;
  double attackDamage;
  double attackCooldown;

  /// Seconds the monster pauses (telegraphs) before an attack lands.
  double windup;

  /// Damage dealt just by touching the target (0 = harmless to touch).
  double touchDamage;
  bool ranged;
  double projectileSpeed;
  String projectileAsset;
  bool wander;
  double wanderRadius;

  /// Experience awarded to whoever kills this monster (read by game scripts).
  double xpReward;
  double knockbackPower;

  MonsterState _state = MonsterState.wander;
  final vm.Vector2 _home = vm.Vector2.zero();
  bool _homeSet = false;
  vm.Vector2? _wanderGoal;
  double _wanderPause = 0;
  double _cooldown = 0;
  double _windupLeft = 0;
  List<vm.Vector2>? _path;
  double _repath = 0;
  EmberEntity? _target;
  int _targetVersion = -1;
  final math.Random _rng = math.Random();

  MonsterAIComponent({
    this.targetTag = 'player',
    this.sightRange = 150,
    this.attackRange = 26,
    this.loseRange = 260,
    this.attackDamage = 1,
    this.attackCooldown = 1.0,
    this.windup = 0.3,
    this.touchDamage = 1,
    this.ranged = false,
    this.projectileSpeed = 170,
    this.projectileAsset = '',
    this.wander = true,
    this.wanderRadius = 64,
    this.xpReward = 5,
    this.knockbackPower = 180,
  });

  MonsterState get state => _state;
  bool get isWindingUp => _windupLeft > 0;

  @override
  void onUpdate(double dt) {
    final self = entity;
    final scene = self?.scene;
    final mover = self?.getComponent<TopDownController2DComponent>();
    final health = self?.getComponent<HealthComponent>();
    if (self == null || scene == null || mover == null) return;
    if (health != null && health.isDead) return;

    final me = _center(self);
    if (!_homeSet) {
      _home.setFrom(me);
      _homeSet = true;
    }
    _cooldown = math.max(0, _cooldown - dt);
    _repath -= dt;

    final target = _findTarget(scene);
    final targetHealth = target?.getComponent<HealthComponent>();
    final alive = target != null && target.enabled && !(targetHealth?.isDead ?? false);
    final targetPos = alive ? _center(target) : null;
    final dist = targetPos == null ? double.infinity : me.distanceTo(targetPos);
    final team = health?.team ?? 'monster';

    if (alive && touchDamage > 0 && Combat.bodyOf(self).overlaps(Combat.bodyOf(target))) {
      targetHealth?.damage(touchDamage, source: self, knockback: _push(me, targetPos!));
    }

    // --- State transitions
    switch (_state) {
      case MonsterState.wander:
      case MonsterState.returning:
        if (alive && dist <= sightRange && _sees(scene, me, targetPos!)) _state = MonsterState.chase;
      case MonsterState.chase:
      case MonsterState.attack:
        if (!alive || dist > loseRange) {
          _state = MonsterState.returning;
          _windupLeft = 0;
          _path = null;
        }
    }
    if (_state == MonsterState.returning && me.distanceTo(_home) < 8) _state = MonsterState.wander;

    // --- Behaviour
    var move = vm.Vector2.zero();
    switch (_state) {
      case MonsterState.wander:
        move = _wanderStep(scene, me, dt);
      case MonsterState.returning:
        move = _steer(scene, me, _home) * 0.7;
      case MonsterState.chase:
      case MonsterState.attack:
        final tp = targetPos!;
        final sees = _sees(scene, me, tp);
        final inRange = dist <= attackRange + (ranged ? 0 : _reach(self, target!));
        if (_windupLeft > 0) {
          _windupLeft -= dt;
          if (_windupLeft <= 0) _attack(scene, self, me, tp, team);
        } else if (inRange && sees && _cooldown <= 0) {
          _state = MonsterState.attack;
          _windupLeft = windup;
          if (windup <= 0) _attack(scene, self, me, tp, team);
        } else if (ranged && sees && dist < attackRange * 0.5) {
          move = (me - tp)..normalize(); // keep distance
        } else if (!inRange || !sees) {
          _state = MonsterState.chase;
          move = _steer(scene, me, tp);
        }
        if (_windupLeft > 0 && tp.x != me.x) _face(self, tp.x - me.x);
    }

    mover.move(move, dt);
    if (move.x.abs() > 0.05) _face(self, move.x);
    final anim = self.getComponent<SpriteAnimatorComponent>();
    if (anim != null) {
      if (_windupLeft > 0 && anim.hasClip('attack')) {
        anim.play('attack');
      } else {
        anim.play(mover.isMoving && anim.hasClip('walk') ? 'walk' : 'idle');
      }
    }
  }

  void _attack(EmberScene scene, EmberEntity self, vm.Vector2 me, vm.Vector2 tp, String team) {
    _cooldown = attackCooldown;
    _windupLeft = 0;
    _state = MonsterState.chase;
    final dir = tp - me;
    if (dir.length2 < 0.001) dir.setValues(0, 1);
    dir.normalize();
    if (ranged) {
      spawnProjectile(scene, self, me, dir, team);
      return;
    }
    final size = math.max(attackRange, 16.0);
    final hitCenter = me + dir * (size * 0.6);
    final area = Rect.fromCenter(center: Offset(hitCenter.x, hitCenter.y), width: size * 1.4, height: size * 1.4);
    Combat.strike(scene, area, team: team, damage: attackDamage, source: self, knockback: knockbackPower);
  }

  /// Fires a projectile from [from] along [dir] (credited to [owner]).
  EmberEntity spawnProjectile(EmberScene scene, EmberEntity owner, vm.Vector2 from, vm.Vector2 dir, String team) {
    const s = 12.0;
    final shot = EmberEntity(name: '${owner.name} Shot', tags: {'projectile', 'team:$team'})
      ..addComponent(Transform2DComponent(
        position: from + dir * 10,
        size: vm.Vector2(s, s),
        anchor: EmberAnchor.center,
        zIndex: 5,
      ))
      ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(8, 8), offset: vm.Vector2(2, 2), isSolid: false, debugDraw: false))
      ..addComponent(ProjectileComponent(velocity: dir * projectileSpeed, damage: attackDamage, team: team, knockback: knockbackPower * 0.6)
        ..owner = owner);
    if (projectileAsset.isNotEmpty) shot.addComponent(FlameSpriteComponent(assetPath: projectileAsset));
    scene.addEntity(shot);
    return shot;
  }

  vm.Vector2 _wanderStep(EmberScene scene, vm.Vector2 me, double dt) {
    if (!wander) return vm.Vector2.zero();
    if (_wanderPause > 0) {
      _wanderPause -= dt;
      return vm.Vector2.zero();
    }
    final goal = _wanderGoal;
    if (goal == null || me.distanceTo(goal) < 6 || (entity?.getComponent<TopDownController2DComponent>()?.hitWall ?? false)) {
      _wanderGoal = null;
      _wanderPause = 0.6 + _rng.nextDouble() * 1.4;
      for (var i = 0; i < 6; i++) {
        final a = _rng.nextDouble() * math.pi * 2;
        final r = wanderRadius * (0.3 + _rng.nextDouble() * 0.7);
        final p = _home + vm.Vector2(math.cos(a), math.sin(a)) * r;
        if (Pathfinder.isWalkable(scene, p.x, p.y) && TileCollision.lineClear(scene, Offset(me.x, me.y), Offset(p.x, p.y))) {
          _wanderGoal = p;
          break;
        }
      }
      return vm.Vector2.zero();
    }
    return (goal - me).normalized() * 0.45;
  }

  /// Direction toward [goal]: straight if nothing is in the way, else along an A* path.
  vm.Vector2 _steer(EmberScene scene, vm.Vector2 me, vm.Vector2 goal) {
    if (TileCollision.lineClear(scene, Offset(me.x, me.y), Offset(goal.x, goal.y))) {
      _path = null;
      final d = goal - me;
      return d.length2 < 1 ? vm.Vector2.zero() : d.normalized();
    }
    if (_path == null || _path!.isEmpty || _repath <= 0) {
      _path = Pathfinder.findPath(scene, me, goal);
      _repath = 0.5;
    }
    final path = _path;
    if (path == null || path.isEmpty) return vm.Vector2.zero();
    while (path.length > 1 && me.distanceTo(path.first) < 6) {
      path.removeAt(0);
    }
    final d = path.first - me;
    return d.length2 < 1 ? vm.Vector2.zero() : d.normalized();
  }

  bool _sees(EmberScene scene, vm.Vector2 a, vm.Vector2 b) => TileCollision.lineClear(scene, Offset(a.x, a.y), Offset(b.x, b.y));

  EmberEntity? _findTarget(EmberScene scene) {
    if (_targetVersion != EmberEntity.structureVersion) {
      _targetVersion = EmberEntity.structureVersion;
      _target = null;
      for (final e in scene.allEntities) {
        if (e.tags.contains(targetTag)) {
          _target = e;
          break;
        }
      }
    }
    return _target;
  }

  vm.Vector2 _push(vm.Vector2 from, vm.Vector2 to) {
    final d = to - from;
    if (d.length2 < 0.001) return vm.Vector2(0, knockbackPower);
    return d.normalized() * knockbackPower;
  }

  /// Half-size of both bodies, so melee range is measured edge to edge.
  static double _reach(EmberEntity a, EmberEntity b) {
    final ra = Combat.bodyOf(a), rb = Combat.bodyOf(b);
    return (math.max(ra.width, ra.height) + math.max(rb.width, rb.height)) / 2;
  }

  static vm.Vector2 _center(EmberEntity e) {
    final c = Combat.bodyOf(e).center;
    return vm.Vector2(c.dx, c.dy);
  }

  static void _face(EmberEntity e, double dx) {
    final sprite = e.getComponent<FlameSpriteComponent>();
    if (sprite == null) return;
    final left = dx < 0;
    if (sprite.flipX != left) sprite.flipX = left;
  }

  InspectableProperty<double> _num(String name, String label, double Function() get, void Function(double) set, {double step = 1}) =>
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
        step: step,
      );

  InspectableProperty<bool> _bool(String name, String label, bool Function() get, void Function(bool) set) => InspectableProperty<bool>(
        name: name,
        label: label,
        type: InspectableType.boolean,
        getter: get,
        setter: (v) {
          set(v);
          notifyListeners();
        },
      );

  @override
  String get displayName => 'Monster AI';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'targetTag',
          label: 'Target Tag',
          type: InspectableType.string,
          getter: () => targetTag,
          setter: (v) {
            targetTag = v;
            _targetVersion = -1;
            notifyListeners();
          },
        ),
        _num('sightRange', 'Sight Range (px)', () => sightRange, (v) => sightRange = v, step: 8),
        _num('attackRange', 'Attack Range (px)', () => attackRange, (v) => attackRange = v, step: 2),
        _num('loseRange', 'Give Up Range (px)', () => loseRange, (v) => loseRange = v, step: 8),
        _num('attackDamage', 'Attack Damage', () => attackDamage, (v) => attackDamage = v, step: 0.5),
        _num('attackCooldown', 'Attack Cooldown (s)', () => attackCooldown, (v) => attackCooldown = v, step: 0.1),
        _num('windup', 'Attack Windup (s)', () => windup, (v) => windup = v, step: 0.05),
        _num('touchDamage', 'Touch Damage', () => touchDamage, (v) => touchDamage = v, step: 0.5),
        _bool('ranged', 'Ranged (shoots)', () => ranged, (v) => ranged = v),
        _num('projectileSpeed', 'Projectile Speed', () => projectileSpeed, (v) => projectileSpeed = v, step: 10),
        InspectableProperty<String>(
          name: 'projectileAsset',
          label: 'Projectile Sprite',
          type: InspectableType.string,
          getter: () => projectileAsset,
          setter: (v) {
            projectileAsset = v;
            notifyListeners();
          },
        ),
        _bool('wander', 'Wander When Idle', () => wander, (v) => wander = v),
        _num('wanderRadius', 'Wander Radius (px)', () => wanderRadius, (v) => wanderRadius = v, step: 8),
        _num('xpReward', 'XP Reward', () => xpReward, (v) => xpReward = v),
        _num('knockbackPower', 'Knockback', () => knockbackPower, (v) => knockbackPower = v, step: 10),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'targetTag': targetTag,
        'sightRange': sightRange,
        'attackRange': attackRange,
        'loseRange': loseRange,
        'attackDamage': attackDamage,
        'attackCooldown': attackCooldown,
        'windup': windup,
        'touchDamage': touchDamage,
        'ranged': ranged,
        'projectileSpeed': projectileSpeed,
        'projectileAsset': projectileAsset,
        'wander': wander,
        'wanderRadius': wanderRadius,
        'xpReward': xpReward,
        'knockbackPower': knockbackPower,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    double n(String k, double d) => (json[k] as num?)?.toDouble() ?? d;
    targetTag = json['targetTag'] as String? ?? 'player';
    sightRange = n('sightRange', 150);
    attackRange = n('attackRange', 26);
    loseRange = n('loseRange', 260);
    attackDamage = n('attackDamage', 1);
    attackCooldown = n('attackCooldown', 1);
    windup = n('windup', 0.3);
    touchDamage = n('touchDamage', 1);
    ranged = json['ranged'] as bool? ?? false;
    projectileSpeed = n('projectileSpeed', 170);
    projectileAsset = json['projectileAsset'] as String? ?? '';
    wander = json['wander'] as bool? ?? true;
    wanderRadius = n('wanderRadius', 64);
    xpReward = n('xpReward', 5);
    knockbackPower = n('knockbackPower', 180);
    notifyListeners();
  }

  @override
  MonsterAIComponent clone() => MonsterAIComponent()..fromJson(toJson());
}

void registerMonsterAI() {
  ComponentRegistry.register('Monster AI', (json) => MonsterAIComponent()..fromJson(json));
}

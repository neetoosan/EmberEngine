import 'dart:math' as math;
import 'package:forge2d/forge2d.dart' as f2;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import '../two_d/flame_components.dart';

// forge2d uses 32-bit vector_math vectors; the engine uses 64-bit ones.

/// Engine pixels -> Box2D metres.
f2.Vector2 _m(vm.Vector2 v, double ppm) => f2.Vector2(v.x / ppm, v.y / ppm);

/// Box2D metres -> engine pixels.
vm.Vector2 _px(f2.Vector2 v, double ppm) => vm.Vector2(v.x * ppm, v.y * ppm);

/// How a rigid body moves.
enum RigidBodyType2D {
  /// Moved by gravity, collisions and impulses (crates, projectiles).
  dynamic,

  /// Never moves (ground, walls). Other bodies collide with it.
  static,

  /// Moved only by its velocity (moving platforms); pushes dynamic bodies.
  kinematic,
}

enum BodyShape2D { box, circle }

enum JointType2D {
  /// Pinned at the anchor; free to rotate (wheels, swinging doors).
  hinge,

  /// Glued together at the anchor.
  weld,

  /// Kept no further apart than [PhysicsJoint2DComponent.length] (chains, ropes).
  rope,

  /// Pulled back towards [PhysicsJoint2DComponent.length] (springs, bungees).
  spring,
}

/// Real 2D physics for an entity: gravity, stacking, tipping, bouncing,
/// friction and rotation (Box2D, via forge2d).
///
/// The collider fits the entity's box (Transform 2D size × scale), or
/// [colliderSize] when set. Units are pixels: velocities in px/s, impulses
/// in kg·px/s (a 32×32 box of density 1 weighs 1 kg).
class RigidBody2DComponent extends EmberComponent {
  RigidBodyType2D bodyType;
  BodyShape2D shape;

  /// Collider width and height in world pixels; (0, 0) uses the entity's box.
  vm.Vector2 colliderSize;

  double density;
  double friction;
  double restitution;
  double linearDamping;
  double angularDamping;
  double gravityScale;
  bool fixedRotation;

  /// Continuous collision for fast, small bodies (projectiles), so they never
  /// pass through thin walls between two steps.
  bool bullet;

  /// Reports touches (onTriggerEnter/Exit) without colliding.
  bool sensor;

  /// Starts asleep: a stacked tower stays perfectly still until something hits it.
  bool startAsleep;

  /// Approach speed (px/s) at which a contact counts as a hit and is
  /// reported to scripts as `onHit(other, impulse, speed)`. Resting contacts
  /// never count.
  double hitSpeed;

  RigidBody2DComponent({
    this.bodyType = RigidBodyType2D.dynamic,
    this.shape = BodyShape2D.box,
    vm.Vector2? colliderSize,
    this.density = 1,
    this.friction = 0.5,
    this.restitution = 0.1,
    this.linearDamping = 0.05,
    this.angularDamping = 0.1,
    this.gravityScale = 1,
    this.fixedRotation = false,
    this.bullet = false,
    this.sensor = false,
    this.startAsleep = false,
    this.hitSpeed = 60,
  }) : colliderSize = colliderSize ?? vm.Vector2.zero();

  // --- Runtime (owned by RigidWorld2D) ---

  f2.Body? _body;
  double _ppm = RigidWorld2D.defaultPixelsPerMeter;

  /// Bumped by every property change; the world rebuilds the body when it differs.
  int _revision = 0;
  int _builtRevision = -1;
  double _builtW = 0, _builtH = 0;

  /// The transform pose the world wrote last (so script/editor moves are noticed).
  double _syncX = double.nan, _syncY = double.nan, _syncRot = double.nan;

  vm.Vector2? _pendingVelocity;
  double? _pendingAngular;
  final List<(vm.Vector2, vm.Vector2?)> _pendingImpulses = [];

  /// The live Box2D body while the game runs (null in the editor).
  f2.Body? get body => _body;

  /// Velocity in px/s. Can be set before the body exists (e.g. right after spawning).
  vm.Vector2 get velocity {
    final b = _body;
    if (b != null) return _px(b.linearVelocity, _ppm);
    return _pendingVelocity?.clone() ?? vm.Vector2.zero();
  }

  set velocity(vm.Vector2 v) {
    final b = _body;
    if (b != null) {
      b.linearVelocity = _m(v, _ppm);
      b.setAwake(true);
    } else {
      _pendingVelocity = v.clone();
    }
  }

  /// Spin in radians per second (positive = clockwise on screen).
  double get angularVelocity => _body?.angularVelocity ?? _pendingAngular ?? 0;

  set angularVelocity(double w) {
    final b = _body;
    if (b != null) {
      b.angularVelocity = w;
      b.setAwake(true);
    } else {
      _pendingAngular = w;
    }
  }

  /// Instant push in kg·px/s, at the centre of mass or at a world point (adds spin).
  void applyImpulse(vm.Vector2 impulse, [vm.Vector2? worldPoint]) {
    final b = _body;
    if (b == null) {
      _pendingImpulses.add((impulse.clone(), worldPoint?.clone()));
      return;
    }
    b.applyLinearImpulse(_m(impulse, _ppm), point: worldPoint == null ? null : _m(worldPoint, _ppm));
  }

  /// Continuous push for this physics step (call every fixed update), kg·px/s².
  void applyForce(vm.Vector2 force, [vm.Vector2? worldPoint]) {
    final b = _body;
    if (b == null) return;
    b.applyForce(_m(force, _ppm), point: worldPoint == null ? null : _m(worldPoint, _ppm));
  }

  void applyTorque(double torque) => _body?.applyTorque(torque / (_ppm * _ppm));

  /// Mass in kg (estimated from size and density before the game runs).
  double get mass {
    final b = _body;
    if (b != null) return b.mass;
    final t = entity?.getComponent<Transform2DComponent>();
    if (t == null || bodyType != RigidBodyType2D.dynamic) return 0;
    final d = colliderDims(t);
    final area = shape == BodyShape2D.circle ? math.pi * math.pow(math.min(d.x, d.y) / 2, 2) : d.x * d.y;
    return density * area / (_ppm * _ppm);
  }

  bool get sleeping => _body == null ? startAsleep : !_body!.isAwake;

  void wake() => _body?.setAwake(true);

  /// Collider width and height in world pixels.
  vm.Vector2 colliderDims(Transform2DComponent t) {
    if (colliderSize.x > 0 && colliderSize.y > 0) return colliderSize.clone();
    final s = t.worldScale;
    return vm.Vector2((t.size.x * s.x).abs(), (t.size.y * s.y).abs());
  }

  void _changed() {
    _revision++;
    notifyListeners();
  }

  // --- Inspector ---

  @override
  String get displayName => 'Rigid Body 2D';

  InspectableProperty<double> _num(String name, String label, double Function() get, void Function(double) set,
          {double step = 0.1, double? min, double? max, String? tooltip}) =>
      InspectableProperty<double>(
        name: name,
        label: label,
        type: InspectableType.number,
        getter: get,
        setter: (v) {
          set(v);
          _changed();
        },
        step: step,
        min: min,
        max: max,
        tooltip: tooltip,
      );

  InspectableProperty<bool> _flag(String name, String label, bool Function() get, void Function(bool) set, String tooltip) =>
      InspectableProperty<bool>(
        name: name,
        label: label,
        type: InspectableType.boolean,
        getter: get,
        setter: (v) {
          set(v);
          _changed();
        },
        tooltip: tooltip,
      );

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'bodyType',
          label: 'Body Type',
          type: InspectableType.options,
          getter: () => bodyType.name,
          setter: (v) {
            bodyType = RigidBodyType2D.values.firstWhere((t) => t.name == v, orElse: () => RigidBodyType2D.dynamic);
            _changed();
          },
          options: RigidBodyType2D.values.map((t) => t.name).toList(),
          tooltip: 'dynamic: falls and tumbles · static: never moves · kinematic: moved by its velocity',
        ),
        InspectableProperty<String>(
          name: 'shape',
          label: 'Shape',
          type: InspectableType.options,
          getter: () => shape.name,
          setter: (v) {
            shape = BodyShape2D.values.firstWhere((s) => s.name == v, orElse: () => BodyShape2D.box);
            _changed();
          },
          options: BodyShape2D.values.map((s) => s.name).toList(),
        ),
        InspectableProperty<vm.Vector2>(
          name: 'colliderSize',
          label: 'Collider Size',
          type: InspectableType.vector2,
          getter: () => colliderSize,
          setter: (v) {
            colliderSize = v;
            _changed();
          },
          step: 1,
          tooltip: 'Width and height in pixels; 0, 0 fits the entity box',
        ),
        _num('density', 'Density', () => density, (v) => density = math.max(0, v), min: 0, tooltip: 'Weight per area (1 = wood)'),
        _num('friction', 'Friction', () => friction, (v) => friction = v.clamp(0, 2).toDouble(), min: 0, max: 2),
        _num('restitution', 'Bounciness', () => restitution, (v) => restitution = v.clamp(0, 1).toDouble(), min: 0, max: 1),
        _num('linearDamping', 'Linear Damping', () => linearDamping, (v) => linearDamping = math.max(0, v), min: 0, tooltip: 'Air drag'),
        _num('angularDamping', 'Angular Damping', () => angularDamping, (v) => angularDamping = math.max(0, v), min: 0),
        _num('gravityScale', 'Gravity Scale', () => gravityScale, (v) => gravityScale = v, tooltip: '0 floats, 1 normal, 2 heavy'),
        _flag('fixedRotation', 'Fixed Rotation', () => fixedRotation, (v) => fixedRotation = v, 'Never tips over (characters)'),
        _flag('bullet', 'Fast Moving', () => bullet, (v) => bullet = v, 'Continuous collision for projectiles'),
        _flag('sensor', 'Sensor', () => sensor, (v) => sensor = v, 'Detects touches (onTriggerEnter) without colliding'),
        _flag('startAsleep', 'Start Asleep', () => startAsleep, (v) => startAsleep = v, 'Rest perfectly still until hit (stacked towers)'),
        _num('hitSpeed', 'Hit Speed', () => hitSpeed, (v) => hitSpeed = math.max(0, v), step: 5, min: 0,
            tooltip: 'Impact speed (px/s) reported to scripts as onHit(other, impulse, speed)'),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'bodyType': bodyType.name,
        'shape': shape.name,
        'colliderSize': [colliderSize.x, colliderSize.y],
        'density': density,
        'friction': friction,
        'restitution': restitution,
        'linearDamping': linearDamping,
        'angularDamping': angularDamping,
        'gravityScale': gravityScale,
        'fixedRotation': fixedRotation,
        'bullet': bullet,
        'sensor': sensor,
        'startAsleep': startAsleep,
        'hitSpeed': hitSpeed,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    double n(String k, double d) => (json[k] as num?)?.toDouble() ?? d;
    bodyType = RigidBodyType2D.values.firstWhere((t) => t.name == json['bodyType'], orElse: () => RigidBodyType2D.dynamic);
    shape = BodyShape2D.values.firstWhere((s) => s.name == json['shape'], orElse: () => BodyShape2D.box);
    final cs = json['colliderSize'];
    colliderSize = cs is List && cs.length == 2 ? vm.Vector2((cs[0] as num).toDouble(), (cs[1] as num).toDouble()) : vm.Vector2.zero();
    density = n('density', 1);
    friction = n('friction', 0.5);
    restitution = n('restitution', 0.1);
    linearDamping = n('linearDamping', 0.05);
    angularDamping = n('angularDamping', 0.1);
    gravityScale = n('gravityScale', 1);
    fixedRotation = json['fixedRotation'] as bool? ?? false;
    bullet = json['bullet'] as bool? ?? false;
    sensor = json['sensor'] as bool? ?? false;
    startAsleep = json['startAsleep'] as bool? ?? false;
    hitSpeed = n('hitSpeed', 60);
    _changed();
  }

  @override
  RigidBody2DComponent clone() => RigidBody2DComponent()..fromJson(toJson());
}

/// Connects this entity's rigid body to another one (or to a fixed point in
/// the world): hinges, welds, ropes and springs. Can snap under load.
class PhysicsJoint2DComponent extends EmberComponent {
  JointType2D jointType;

  /// Name of the other entity (with a Rigid Body 2D); empty pins to the world.
  String connectedTo;

  /// Attachment point on this body, in pixels from its centre.
  vm.Vector2 anchor;

  /// Attachment point on the other body, in pixels from its centre — or,
  /// when pinned to the world, from this body's starting centre.
  vm.Vector2 connectedAnchor;

  /// Rope: longest length. Spring: rest length. 0 = the distance at start.
  double length;

  /// Spring / weld stiffness in oscillations per second (0 = rigid weld).
  double stiffness;
  double damping;

  /// Hinge motor speed in radians per second (0 = no motor).
  double motorSpeed;
  double motorTorque;

  /// Pulling force that snaps the joint (0 = unbreakable). 1 kg weighs about 980.
  double breakForce;

  bool collideConnected;

  PhysicsJoint2DComponent({
    this.jointType = JointType2D.hinge,
    this.connectedTo = '',
    vm.Vector2? anchor,
    vm.Vector2? connectedAnchor,
    this.length = 0,
    this.stiffness = 4,
    this.damping = 0.5,
    this.motorSpeed = 0,
    this.motorTorque = 1000,
    this.breakForce = 0,
    this.collideConnected = false,
  })  : anchor = anchor ?? vm.Vector2.zero(),
        connectedAnchor = connectedAnchor ?? vm.Vector2.zero();

  f2.Joint? _joint;
  int _revision = 0;
  int _builtRevision = -1;

  /// True once the joint snapped (it stays broken until the level restarts).
  bool broken = false;

  f2.Joint? get joint => _joint;

  /// Current pulling force on the joint (kg·px/s²), 0 when not active.
  double force = 0;

  void _changed() {
    _revision++;
    notifyListeners();
  }

  @override
  String get displayName => 'Joint 2D';

  InspectableProperty<double> _num(String name, String label, double Function() get, void Function(double) set,
          {double step = 1, double? min, String? tooltip}) =>
      InspectableProperty<double>(
        name: name,
        label: label,
        type: InspectableType.number,
        getter: get,
        setter: (v) {
          set(v);
          _changed();
        },
        step: step,
        min: min,
        tooltip: tooltip,
      );

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'jointType',
          label: 'Joint Type',
          type: InspectableType.options,
          getter: () => jointType.name,
          setter: (v) {
            jointType = JointType2D.values.firstWhere((t) => t.name == v, orElse: () => JointType2D.hinge);
            _changed();
          },
          options: JointType2D.values.map((t) => t.name).toList(),
          tooltip: 'hinge: rotates around the anchor · weld: glued · rope: max length · spring: springy length',
        ),
        InspectableProperty<String>(
          name: 'connectedTo',
          label: 'Connected To',
          type: InspectableType.string,
          getter: () => connectedTo,
          setter: (v) {
            connectedTo = v;
            _changed();
          },
          tooltip: 'Entity name with a Rigid Body 2D; empty pins it to the world',
        ),
        InspectableProperty<vm.Vector2>(
          name: 'anchor',
          label: 'Anchor',
          type: InspectableType.vector2,
          getter: () => anchor,
          setter: (v) {
            anchor = v;
            _changed();
          },
          step: 1,
          tooltip: 'Point on this body, pixels from its centre',
        ),
        InspectableProperty<vm.Vector2>(
          name: 'connectedAnchor',
          label: 'Connected Anchor',
          type: InspectableType.vector2,
          getter: () => connectedAnchor,
          setter: (v) {
            connectedAnchor = v;
            _changed();
          },
          step: 1,
          tooltip: 'Point on the other body (pixels from its centre), or in the world relative to this body\'s start',
        ),
        _num('length', 'Length', () => length, (v) => length = math.max(0, v), min: 0, tooltip: 'Rope max / spring rest length; 0 = as placed'),
        _num('stiffness', 'Stiffness', () => stiffness, (v) => stiffness = math.max(0, v), step: 0.5, min: 0, tooltip: 'Spring oscillations per second'),
        _num('damping', 'Damping', () => damping, (v) => damping = v.clamp(0, 1).toDouble(), step: 0.05, min: 0),
        _num('motorSpeed', 'Motor Speed', () => motorSpeed, (v) => motorSpeed = v, step: 0.1, tooltip: 'Hinge: radians per second (windmills, wheels)'),
        _num('motorTorque', 'Motor Torque', () => motorTorque, (v) => motorTorque = math.max(0, v), step: 50, min: 0),
        _num('breakForce', 'Break Force', () => breakForce, (v) => breakForce = math.max(0, v), step: 50, min: 0,
            tooltip: 'Snaps above this pull (0 = unbreakable). 1 kg weighs about 980'),
        InspectableProperty<bool>(
          name: 'collideConnected',
          label: 'Bodies Collide',
          type: InspectableType.boolean,
          getter: () => collideConnected,
          setter: (v) {
            collideConnected = v;
            _changed();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'jointType': jointType.name,
        'connectedTo': connectedTo,
        'anchor': [anchor.x, anchor.y],
        'connectedAnchor': [connectedAnchor.x, connectedAnchor.y],
        'length': length,
        'stiffness': stiffness,
        'damping': damping,
        'motorSpeed': motorSpeed,
        'motorTorque': motorTorque,
        'breakForce': breakForce,
        'collideConnected': collideConnected,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    double n(String k, double d) => (json[k] as num?)?.toDouble() ?? d;
    vm.Vector2 v2(Object? raw) => raw is List && raw.length == 2 ? vm.Vector2((raw[0] as num).toDouble(), (raw[1] as num).toDouble()) : vm.Vector2.zero();
    jointType = JointType2D.values.firstWhere((t) => t.name == json['jointType'], orElse: () => JointType2D.hinge);
    connectedTo = json['connectedTo'] as String? ?? '';
    anchor = v2(json['anchor']);
    connectedAnchor = v2(json['connectedAnchor']);
    length = n('length', 0);
    stiffness = n('stiffness', 4);
    damping = n('damping', 0.5);
    motorSpeed = n('motorSpeed', 0);
    motorTorque = n('motorTorque', 1000);
    breakForce = n('breakForce', 0);
    collideConnected = json['collideConnected'] as bool? ?? false;
    _changed();
  }

  @override
  PhysicsJoint2DComponent clone() => PhysicsJoint2DComponent()..fromJson(toJson());
}

/// Scene-wide physics settings (optional; put it on any one entity).
class PhysicsWorld2DComponent extends EmberComponent {
  /// Pixels per second² (down is positive).
  vm.Vector2 gravity;

  /// World scale: how many pixels make one metre. Box2D works best with
  /// objects between 0.1 and 10 metres, so pick it for your sprite sizes.
  double pixelsPerMeter;

  /// Lets resting bodies sleep (cheaper, and settled towers stay still).
  bool allowSleep;

  PhysicsWorld2DComponent({vm.Vector2? gravity, this.pixelsPerMeter = RigidWorld2D.defaultPixelsPerMeter, this.allowSleep = true})
      : gravity = gravity ?? vm.Vector2(0, RigidWorld2D.defaultGravity);

  @override
  String get displayName => 'Physics World 2D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<vm.Vector2>(
          name: 'gravity',
          label: 'Gravity',
          type: InspectableType.vector2,
          getter: () => gravity,
          setter: (v) {
            gravity = v;
            notifyListeners();
          },
          step: 10,
          tooltip: 'Pixels per second² (down is positive)',
        ),
        InspectableProperty<double>(
          name: 'pixelsPerMeter',
          label: 'Pixels / Metre',
          type: InspectableType.number,
          getter: () => pixelsPerMeter,
          setter: (v) {
            pixelsPerMeter = v.clamp(4, 512).toDouble();
            notifyListeners();
          },
          step: 1,
          min: 4,
          tooltip: 'World scale (applies when the game starts)',
        ),
        InspectableProperty<bool>(
          name: 'allowSleep',
          label: 'Allow Sleep',
          type: InspectableType.boolean,
          getter: () => allowSleep,
          setter: (v) {
            allowSleep = v;
            notifyListeners();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'gravity': [gravity.x, gravity.y],
        'pixelsPerMeter': pixelsPerMeter,
        'allowSleep': allowSleep,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    final g = json['gravity'];
    gravity = g is List && g.length == 2 ? vm.Vector2((g[0] as num).toDouble(), (g[1] as num).toDouble()) : vm.Vector2(0, RigidWorld2D.defaultGravity);
    pixelsPerMeter = (json['pixelsPerMeter'] as num?)?.toDouble() ?? RigidWorld2D.defaultPixelsPerMeter;
    allowSleep = json['allowSleep'] as bool? ?? true;
    notifyListeners();
  }

  @override
  PhysicsWorld2DComponent clone() => PhysicsWorld2DComponent()..fromJson(toJson());
}

/// A rigid body (or tilemap) hit by [RigidWorld2D.raycast].
class RayHit2D {
  final EmberEntity entity;
  final vm.Vector2 point;
  final vm.Vector2 normal;
  final double fraction;
  const RayHit2D(this.entity, this.point, this.normal, this.fraction);
}

/// One scene's Box2D world: creates bodies for [RigidBody2DComponent]s (and
/// static colliders for solid tilemap tiles), steps them, writes the result
/// back to the entities' transforms and reports collisions to scripts.
class RigidWorld2D {
  static const double defaultPixelsPerMeter = 32;
  static const double defaultGravity = 980;

  static final Expando<RigidWorld2D> _worlds = Expando<RigidWorld2D>();

  /// The physics world of [scene], if it has one yet.
  static RigidWorld2D? of(EmberScene scene) => _worlds[scene];

  /// The physics world of [scene], created if needed (queries from scripts).
  static RigidWorld2D obtain(EmberScene scene) => _worlds[scene] ??= RigidWorld2D._(scene);

  /// Steps [scene]'s rigid bodies (no-op for scenes without any).
  static void step(EmberScene scene, double dt) {
    var w = _worlds[scene];
    if (w == null) {
      if (scene.componentsOf<RigidBody2DComponent>().isEmpty) return;
      w = _worlds[scene] = RigidWorld2D._(scene);
    }
    w._step(dt);
  }

  final EmberScene scene;
  final f2.World world;
  final double ppm;
  late final f2.Body _ground;
  late final _Listener _listener;

  final Set<RigidBody2DComponent> _bodies = {};
  final Set<PhysicsJoint2DComponent> _joints = {};
  final Map<FlameTileMapComponent, (f2.Body, int, double, double, double)> _tileBodies = {};

  // Collision events gathered during a step, dispatched after it
  final Map<f2.Contact, double> _approach = {};
  final Map<(Object, Object), (double, double)> _impacts = {};
  final List<(Object, Object, bool)> _begins = [];
  final List<(Object, Object, bool)> _ends = [];
  final Map<(Object, Object), int> _touching = {};
  final List<PhysicsJoint2DComponent> _brokenJoints = [];

  RigidWorld2D._(this.scene)
      : ppm = _settings(scene)?.pixelsPerMeter ?? defaultPixelsPerMeter,
        world = f2.World() {
    final s = _settings(scene);
    world.gravity = _m(s?.gravity ?? vm.Vector2(0, defaultGravity), ppm);
    world.setAllowSleep(s?.allowSleep ?? true);
    _ground = world.createBody(f2.BodyDef());
    _listener = _Listener(this);
    world.setContactListener(_listener);
  }

  static PhysicsWorld2DComponent? _settings(EmberScene scene) {
    for (final s in scene.componentsOf<PhysicsWorld2DComponent>()) {
      if (s.enabled && (s.entity?.enabled ?? false)) return s;
    }
    return null;
  }

  /// Gravity in px/s².
  vm.Vector2 get gravity => _px(world.gravity, ppm);
  set gravity(vm.Vector2 g) {
    world.gravity = _m(g, ppm);
    for (final rb in _bodies) {
      rb._body?.setAwake(true);
    }
  }

  int get bodyCount => _bodies.length;

  /// Moving (awake, dynamic) bodies right now.
  int get awakeCount {
    var n = 0;
    for (final rb in _bodies) {
      final b = rb._body;
      if (b != null && b.bodyType == f2.BodyType.dynamic && b.isAwake && _moving(b)) n++;
    }
    return n;
  }

  /// True when nothing is moving any more (every dynamic body asleep or still).
  bool get settled => awakeCount == 0;

  bool _moving(f2.Body b) => b.linearVelocity.length2 * ppm * ppm > 9 || b.angularVelocity.abs() > 0.05;

  // ---------------------------------------------------------------------------
  // Stepping

  void _step(double dt) {
    final s = _settings(scene);
    if (s != null) world.gravity = _m(s.gravity, ppm);
    _syncBodies();
    _syncTilemaps();
    _syncJoints();
    world.stepDt(dt);
    _settleSleepers();
    _checkJoints(dt);
    _writeBack();
    _dispatch();
  }

  static bool _activeInHierarchy(EmberEntity e) {
    EmberEntity? cur = e;
    while (cur != null) {
      if (!cur.enabled) return false;
      cur = cur.parent;
    }
    return e.scene != null;
  }

  void _syncBodies() {
    final seen = <RigidBody2DComponent>{};
    for (final rb in scene.componentsOf<RigidBody2DComponent>()) {
      final e = rb.entity;
      if (e == null || !rb.enabled || !_activeInHierarchy(e)) continue;
      final t = e.getComponent<Transform2DComponent>();
      if (t == null) continue;
      seen.add(rb);
      final dims = rb.colliderDims(t);
      if (rb._body != null && (rb._builtRevision != rb._revision || dims.x != rb._builtW || dims.y != rb._builtH)) {
        _destroyBody(rb, keepMotion: true);
      }
      if (rb._body == null) {
        _createBody(rb, t, dims);
        continue;
      }
      // Moved by a script or the editor since the last step: teleport the body
      if (t.position.x != rb._syncX || t.position.y != rb._syncY || t.rotation != rb._syncRot) {
        final (c, rot) = centerOf(t);
        rb._body!
          ..setTransform(_m(c, ppm), rot)
          ..setAwake(true);
        _remember(rb, t);
      }
    }
    for (final rb in _bodies.toList()) {
      if (!seen.contains(rb)) _destroyBody(rb);
    }
  }

  void _remember(RigidBody2DComponent rb, Transform2DComponent t) {
    rb._syncX = t.position.x;
    rb._syncY = t.position.y;
    rb._syncRot = t.rotation;
  }

  void _createBody(RigidBody2DComponent rb, Transform2DComponent t, vm.Vector2 dims) {
    final (c, rot) = centerOf(t);
    final pending = rb._pendingVelocity != null || rb._pendingAngular != null || rb._pendingImpulses.isNotEmpty;
    final body = world.createBody(f2.BodyDef(
      type: switch (rb.bodyType) {
        RigidBodyType2D.dynamic => f2.BodyType.dynamic,
        RigidBodyType2D.static => f2.BodyType.static,
        RigidBodyType2D.kinematic => f2.BodyType.kinematic,
      },
      position: _m(c, ppm),
      angle: rot,
      linearDamping: rb.linearDamping,
      angularDamping: rb.angularDamping,
      fixedRotation: rb.fixedRotation,
      bullet: rb.bullet,
      isAwake: !rb.startAsleep || pending,
      gravityScale: rb.gravityScale == 1 ? null : f2.Vector2.all(rb.gravityScale),
      userData: rb,
    ));
    final f2.Shape shape;
    if (rb.shape == BodyShape2D.circle) {
      shape = f2.CircleShape()..radius = math.max(0.01, math.min(dims.x, dims.y) / 2 / ppm);
    } else {
      shape = f2.PolygonShape()..setAsBoxXY(math.max(0.01, dims.x / 2 / ppm), math.max(0.01, dims.y / 2 / ppm));
    }
    body.createFixture(f2.FixtureDef(
      shape,
      density: rb.density,
      friction: rb.friction,
      restitution: rb.restitution,
      isSensor: rb.sensor,
      userData: rb,
    ));
    rb
      .._body = body
      .._ppm = ppm
      .._builtRevision = rb._revision
      .._builtW = dims.x
      .._builtH = dims.y;
    final v = rb._pendingVelocity;
    if (v != null) body.linearVelocity = _m(v, ppm);
    final w = rb._pendingAngular;
    if (w != null) body.angularVelocity = w;
    for (final (impulse, point) in rb._pendingImpulses) {
      body.applyLinearImpulse(_m(impulse, ppm), point: point == null ? null : _m(point, ppm));
    }
    rb._pendingVelocity = null;
    rb._pendingAngular = null;
    rb._pendingImpulses.clear();
    _bodies.add(rb);
    _remember(rb, t);
    if (rb.startAsleep && !pending) _sleepers.add((rb, body.position.clone(), body.angle));
  }

  /// "Start Asleep" bodies created this step, with the pose they were placed at.
  final List<(RigidBody2DComponent, f2.Vector2, double)> _sleepers = [];

  /// Box2D wakes bodies when their first contacts form, which would make a
  /// sleeping tower settle by a fraction of a pixel. After that first step the
  /// contacts exist, so the bodies go back exactly where they were placed and
  /// sleep until something actually hits them.
  void _settleSleepers() {
    for (final (rb, pos, angle) in _sleepers) {
      final body = rb._body;
      if (body == null) continue;
      body
        ..setTransform(pos, angle)
        ..linearVelocity = f2.Vector2.zero()
        ..angularVelocity = 0
        ..setAwake(false);
    }
    _sleepers.clear();
  }

  void _destroyBody(RigidBody2DComponent rb, {bool keepMotion = false}) {
    final body = rb._body;
    if (body != null) {
      if (keepMotion) {
        rb._pendingVelocity = _px(body.linearVelocity, ppm);
        rb._pendingAngular = body.angularVelocity;
      }
      // Joints on this body go with it (Box2D destroys them)
      for (final j in _joints.toList()) {
        final joint = j._joint;
        if (joint != null && (identical(joint.bodyA, body) || identical(joint.bodyB, body))) {
          j._joint = null;
          _joints.remove(j);
        }
      }
      world.destroyBody(body);
    }
    rb._body = null;
    _bodies.remove(rb);
  }

  void _syncTilemaps() {
    final seen = <FlameTileMapComponent>{};
    for (final tm in scene.componentsOf<FlameTileMapComponent>()) {
      final e = tm.entity;
      if (e == null || !tm.enabled || !tm.collision || !_activeInHierarchy(e)) continue;
      final t = e.getComponent<Transform2DComponent>();
      if (t == null) continue;
      seen.add(tm);
      final o = t.worldPosition - t.anchorOffset;
      final ts = tm.tileSize * t.worldScale.x;
      final existing = _tileBodies[tm];
      if (existing != null && existing.$2 == tm.revision && existing.$3 == o.x && existing.$4 == o.y && existing.$5 == ts) continue;
      if (existing != null) world.destroyBody(existing.$1);
      _tileBodies[tm] = (_buildTileBody(tm, o.x, o.y, ts), tm.revision, o.x, o.y, ts);
    }
    for (final tm in _tileBodies.keys.toList()) {
      if (!seen.contains(tm)) world.destroyBody(_tileBodies.remove(tm)!.$1);
    }
  }

  /// One static body for a tilemap: solid tiles merged into as few boxes as possible.
  f2.Body _buildTileBody(FlameTileMapComponent tm, double ox, double oy, double ts) {
    final body = world.createBody(f2.BodyDef(userData: tm));
    bool solid(int c, int r) {
      final id = tm.getTile(c, r);
      return id > 0 && tm.kindOf(id).blocks;
    }

    // Horizontal runs per row, extended downward while the row below has the same run
    final open = <(int, int), (int, int)>{}; // (c0, c1) -> (firstRow, lastRow)
    final boxes = <(int, int, int, int)>[];
    for (var r = 0; r <= tm.rows; r++) {
      final runs = <(int, int)>{};
      if (r < tm.rows) {
        var c = 0;
        while (c < tm.columns) {
          if (!solid(c, r)) {
            c++;
            continue;
          }
          final start = c;
          while (c < tm.columns && solid(c, r)) {
            c++;
          }
          runs.add((start, c - 1));
        }
      }
      for (final key in open.keys.toList()) {
        if (runs.contains(key)) {
          open[key] = (open[key]!.$1, r);
        } else {
          final (r0, r1) = open.remove(key)!;
          boxes.add((key.$1, r0, key.$2, r1));
        }
      }
      for (final run in runs) {
        open.putIfAbsent(run, () => (r, r));
      }
    }
    for (final (c0, r0, c1, r1) in boxes) {
      final hw = (c1 - c0 + 1) * ts / 2, hh = (r1 - r0 + 1) * ts / 2;
      final center = f2.Vector2((ox + c0 * ts + hw) / ppm, (oy + r0 * ts + hh) / ppm);
      body.createFixture(f2.FixtureDef(f2.PolygonShape()..setAsBox(hw / ppm, hh / ppm, center, 0), friction: 0.7, userData: tm));
    }
    return body;
  }

  void _syncJoints() {
    for (final j in scene.componentsOf<PhysicsJoint2DComponent>()) {
      final e = j.entity;
      final active = e != null && j.enabled && !j.broken && _activeInHierarchy(e);
      final bodyA = active ? e.getComponent<RigidBody2DComponent>()?._body : null;
      f2.Body? bodyB;
      if (bodyA != null) {
        if (j.connectedTo.isEmpty) {
          bodyB = _ground;
        } else {
          final other = scene.findEntityByName(j.connectedTo);
          bodyB = other == null || !_activeInHierarchy(other) ? null : other.getComponent<RigidBody2DComponent>()?._body;
        }
      }
      final existing = j._joint;
      if (existing != null &&
          (bodyA == null || bodyB == null || !identical(existing.bodyA, bodyA) || !identical(existing.bodyB, bodyB) || j._builtRevision != j._revision)) {
        world.destroyJoint(existing);
        j._joint = null;
        _joints.remove(j);
      }
      if (j._joint == null && bodyA != null && bodyB != null && !identical(bodyA, bodyB)) _createJoint(j, bodyA, bodyB);
    }
    for (final j in _joints.toList()) {
      if (j.entity?.scene != scene) {
        final joint = j._joint;
        if (joint != null) world.destroyJoint(joint);
        j._joint = null;
        _joints.remove(j);
      }
    }
  }

  void _createJoint(PhysicsJoint2DComponent j, f2.Body a, f2.Body b) {
    final anchorA = a.worldPoint(_m(j.anchor, ppm));
    final anchorB = identical(b, _ground) ? a.worldCenter + _m(j.connectedAnchor, ppm) : b.worldPoint(_m(j.connectedAnchor, ppm));
    final f2.Joint joint;
    switch (j.jointType) {
      case JointType2D.hinge:
        final def = f2.RevoluteJointDef()..initialize(a, b, anchorA);
        if (j.motorSpeed != 0) {
          def
            ..enableMotor = true
            ..motorSpeed = j.motorSpeed
            ..maxMotorTorque = j.motorTorque / (ppm * ppm);
        }
        def.collideConnected = j.collideConnected;
        joint = f2.RevoluteJoint(def);
      case JointType2D.weld:
        final def = f2.WeldJointDef()
          ..initialize(a, b, anchorA)
          ..frequencyHz = j.stiffness > 0 && j.length > 0 ? j.stiffness : 0
          ..dampingRatio = j.damping;
        def.collideConnected = j.collideConnected;
        joint = f2.WeldJoint(def);
      case JointType2D.rope:
        final def = f2.RopeJointDef()
          ..bodyA = a
          ..bodyB = b
          ..maxLength = j.length > 0 ? j.length / ppm : anchorA.distanceTo(anchorB);
        def.localAnchorA.setFrom(a.localPoint(anchorA));
        def.localAnchorB.setFrom(b.localPoint(anchorB));
        def.collideConnected = true;
        joint = f2.RopeJoint(def);
      case JointType2D.spring:
        final def = f2.DistanceJointDef()..initialize(a, b, anchorA, anchorB);
        def
          ..length = j.length > 0 ? j.length / ppm : math.max(0.01, anchorA.distanceTo(anchorB))
          ..frequencyHz = j.stiffness
          ..dampingRatio = j.damping
          ..collideConnected = j.collideConnected;
        joint = f2.DistanceJoint(def);
    }
    world.createJoint(joint);
    j
      .._joint = joint
      .._builtRevision = j._revision;
    _joints.add(j);
  }

  void _checkJoints(double dt) {
    if (dt <= 0) return;
    for (final j in _joints.toList()) {
      final joint = j._joint;
      if (joint == null) continue;
      j.force = joint.reactionForce(1 / dt).length * ppm;
      if (j.breakForce > 0 && j.force > j.breakForce) {
        world.destroyJoint(joint);
        j
          .._joint = null
          ..broken = true
          ..force = 0;
        _joints.remove(j);
        _brokenJoints.add(j);
      }
    }
  }

  void _writeBack() {
    for (final rb in _bodies) {
      final body = rb._body;
      if (body == null || body.bodyType == f2.BodyType.static || !body.isAwake) continue;
      final t = rb.entity?.getComponent<Transform2DComponent>();
      if (t == null) continue;
      final (pos, rot) = poseFor(t, _px(body.position, ppm), body.angle);
      t.setPose(pos, rot);
      _remember(rb, t);
    }
  }

  // ---------------------------------------------------------------------------
  // Events

  static EmberEntity? _entityOf(Object? data) => data is EmberComponent ? data.entity : null;

  static (Object, Object) _pair(Object a, Object b) => identityHashCode(a) <= identityHashCode(b) ? (a, b) : (b, a);

  void _dispatch() {
    for (final (a, b, sensor) in _begins) {
      final key = _pair(a, b);
      final n = (_touching[key] ?? 0) + 1;
      _touching[key] = n;
      if (n == 1) _notifyPair(a, b, (x, other) => sensor ? x.notifyScripts((s) => s.onTriggerEnter(other)) : x.notifyScripts((s) => s.onCollisionEnter(other)));
    }
    for (final (a, b, sensor) in _ends) {
      final key = _pair(a, b);
      final n = (_touching[key] ?? 1) - 1;
      if (n <= 0) {
        _touching.remove(key);
        _notifyPair(a, b, (x, other) => sensor ? x.notifyScripts((s) => s.onTriggerExit(other)) : x.notifyScripts((s) => s.onCollisionExit(other)));
      } else {
        _touching[key] = n;
      }
    }
    for (final MapEntry(key: (a, b), value: (impulse, speed)) in _impacts.entries) {
      _notifyPair(a, b, (x, other) => x.notifyScripts((s) => s.onHit(other, impulse, speed)));
    }
    for (final j in _brokenJoints) {
      j.entity?.notifyScripts((s) => s.onJointBreak(j));
    }
    _begins.clear();
    _ends.clear();
    _impacts.clear();
    _approach.clear();
    _brokenJoints.clear();
  }

  void _notifyPair(Object a, Object b, void Function(EmberEntity self, EmberEntity other) send) {
    final ea = _entityOf(a), eb = _entityOf(b);
    if (ea == null || eb == null || identical(ea, eb)) return;
    if (ea.scene != null) send(ea, eb);
    if (eb.scene != null) send(eb, ea);
  }

  // ---------------------------------------------------------------------------
  // Queries

  /// The first solid body (or tilemap) on the segment [from]–[to] (pixels).
  RayHit2D? raycast(vm.Vector2 from, vm.Vector2 to) {
    if (from.distanceTo(to) < 1e-6) return null;
    final cb = _ClosestRay();
    world.raycast(cb, _m(from, ppm), _m(to, ppm));
    final f = cb.fixture;
    final e = f == null ? null : _entityOf(f.userData);
    if (e == null) return null;
    return RayHit2D(e, _px(cb.point, ppm), vm.Vector2(cb.normal.x, cb.normal.y), cb.fraction);
  }

  /// Entities whose rigid body (or solid tile) covers [point].
  List<EmberEntity> entitiesAt(vm.Vector2 point) {
    final p = _m(point, ppm);
    final cb = _PointQuery(p);
    world.queryAABB(cb, f2.AABB.withVec2(p - f2.Vector2.all(0.001), p + f2.Vector2.all(0.001)));
    return [for (final f in cb.found) ?_entityOf(f.userData)];
  }

  /// Pushes every dynamic body within [radius] px of [center] away from it,
  /// strongest at the centre ([strength] in kg·px/s). Returns them with how
  /// close they were (1 = at the centre, 0 = at the edge).
  List<(EmberEntity, double)> explode(vm.Vector2 center, double radius, double strength) {
    final out = <(EmberEntity, double)>[];
    if (radius <= 0) return out;
    for (final rb in _bodies) {
      final body = rb._body;
      final e = rb.entity;
      if (body == null || e == null || body.bodyType != f2.BodyType.dynamic) continue;
      final c = _px(body.worldCenter, ppm);
      final d = c - center;
      final dist = d.length;
      if (dist > radius) continue;
      final falloff = 1 - dist / radius;
      final dir = dist < 1e-3 ? vm.Vector2(0, -1) : d / dist;
      body.applyLinearImpulse(_m(dir * (strength * falloff), ppm), wake: true);
      out.add((e, falloff));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Pose conversion (matches how the 2D renderer places an entity's box)

  /// World-space centre of the entity's box and its world rotation.
  static (vm.Vector2, double) centerOf(Transform2DComponent t) {
    final rot = t.worldRotation;
    final s = t.worldScale;
    final lx = (t.size.x / 2 - t.anchorOffset.x) * s.x, ly = (t.size.y / 2 - t.anchorOffset.y) * s.y;
    final c = math.cos(rot), sn = math.sin(rot);
    final p = t.worldPosition;
    return (vm.Vector2(p.x + lx * c - ly * sn, p.y + lx * sn + ly * c), rot);
  }

  /// Local position and rotation that put the box centre at [center] with [angle].
  static (vm.Vector2, double) poseFor(Transform2DComponent t, vm.Vector2 center, double angle) {
    final s = t.worldScale;
    final lx = (t.size.x / 2 - t.anchorOffset.x) * s.x, ly = (t.size.y / 2 - t.anchorOffset.y) * s.y;
    final c = math.cos(angle), sn = math.sin(angle);
    final world = vm.Vector2(center.x - (lx * c - ly * sn), center.y - (lx * sn + ly * c));
    final parent = t.entity?.parent?.getComponent<Transform2DComponent>();
    if (parent == null) return (world, angle);
    final pr = parent.worldRotation, ps = parent.worldScale, pp = parent.worldPosition;
    final d = world - pp;
    final pc = math.cos(-pr), psn = math.sin(-pr);
    final local = vm.Vector2((d.x * pc - d.y * psn) / (ps.x == 0 ? 1 : ps.x), (d.x * psn + d.y * pc) / (ps.y == 0 ? 1 : ps.y));
    return (local, angle - pr);
  }
}

class _Listener extends f2.ContactListener {
  final RigidWorld2D w;
  _Listener(this.w);
  final f2.WorldManifold _manifold = f2.WorldManifold();

  @override
  void beginContact(f2.Contact contact) {
    final a = contact.fixtureA.userData, b = contact.fixtureB.userData;
    if (a == null || b == null) return;
    w._begins.add((a, b, contact.fixtureA.isSensor || contact.fixtureB.isSensor));
  }

  @override
  void endContact(f2.Contact contact) {
    final a = contact.fixtureA.userData, b = contact.fixtureB.userData;
    if (a == null || b == null) return;
    w._ends.add((a, b, contact.fixtureA.isSensor || contact.fixtureB.isSensor));
  }

  static double _hitSpeedOf(Object? data) => data is RigidBody2DComponent ? data.hitSpeed : double.infinity;

  @override
  void preSolve(f2.Contact contact, f2.Manifold oldManifold) {
    final threshold = math.min(_hitSpeedOf(contact.fixtureA.userData), _hitSpeedOf(contact.fixtureB.userData));
    if (threshold == double.infinity || contact.manifold.pointCount == 0) return;
    contact.getWorldManifold(_manifold);
    final bodyA = contact.fixtureA.body, bodyB = contact.fixtureB.body;
    var best = 0.0;
    for (var i = 0; i < contact.manifold.pointCount; i++) {
      final p = _manifold.points[i];
      final rel = bodyB.linearVelocityFromWorldPoint(p) - bodyA.linearVelocityFromWorldPoint(p);
      final approach = -rel.dot(_manifold.normal) * w.ppm; // px/s, positive when closing in
      if (approach > best) best = approach;
    }
    if (best >= threshold) w._approach[contact] = best;
  }

  @override
  void postSolve(f2.Contact contact, f2.ContactImpulse impulse) {
    final speed = w._approach.remove(contact);
    if (speed == null) return;
    final a = contact.fixtureA.userData, b = contact.fixtureB.userData;
    if (a == null || b == null) return;
    var total = 0.0;
    for (var i = 0; i < impulse.count; i++) {
      total += impulse.normalImpulses[i];
    }
    total *= w.ppm;
    final key = RigidWorld2D._pair(a, b);
    final prev = w._impacts[key];
    if (prev == null || prev.$1 < total) w._impacts[key] = (total, math.max(speed, prev?.$2 ?? 0));
  }
}

class _ClosestRay implements f2.RayCastCallback {
  f2.Fixture? fixture;
  f2.Vector2 point = f2.Vector2.zero();
  f2.Vector2 normal = f2.Vector2.zero();
  double fraction = 1;

  @override
  double reportFixture(f2.Fixture fixture, f2.Vector2 point, f2.Vector2 normal, double fraction) {
    if (fixture.isSensor) return -1;
    this.fixture = fixture;
    this.point = point.clone();
    this.normal = normal.clone();
    this.fraction = fraction;
    return fraction;
  }
}

class _PointQuery implements f2.QueryCallback {
  final f2.Vector2 point;
  final List<f2.Fixture> found = [];
  _PointQuery(this.point);

  @override
  bool reportFixture(f2.Fixture fixture) {
    if (fixture.testPoint(point)) found.add(fixture);
    return true;
  }
}

void registerRigidBodyComponents() {
  ComponentRegistry.register('Rigid Body 2D', (json) => RigidBody2DComponent()..fromJson(json));
  ComponentRegistry.register('Joint 2D', (json) => PhysicsJoint2DComponent()..fromJson(json));
  ComponentRegistry.register('Physics World 2D', (json) => PhysicsWorld2DComponent()..fromJson(json));
}

/// The engine as seen from Ember Script: global functions, `self`, entities,
/// components, vectors, input and game state — with documentation for the
/// editor's API reference and autocomplete.
library;

import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;
import '../core/component.dart';
import '../core/engine_loop.dart';
import '../core/entity.dart';
import '../core/event_bus.dart' show LogSeverity;
import '../core/game_script.dart';
import '../core/gamepad.dart';
import '../core/input.dart';
import '../core/player_input.dart';
import '../core/mouse_lock.dart';
import '../core/save_data.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../core/transform3d.dart';
import '../core/tween.dart';
import '../subsystems/ai/enemy_ai3d.dart';
import '../subsystems/ai/monster_ai.dart';
import '../subsystems/audio/audio_component.dart';
import '../subsystems/audio/audio_system.dart';
import '../subsystems/combat/combat.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/physics/character_controller2d.dart';
import '../subsystems/physics/character_controller3d.dart';
import '../subsystems/physics/physics_world3d.dart';
import '../subsystems/physics/rigid_body2d.dart';
import '../subsystems/physics/tile_collision.dart';
import '../subsystems/story/story_player.dart';
import '../subsystems/three_d/components3d.dart';
import '../subsystems/two_d/bullet_pool.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/door.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/line2d.dart';
import '../subsystems/two_d/path_follower.dart';
import '../subsystems/two_d/procgen.dart';
import '../subsystems/two_d/sprite_animator.dart';
import '../subsystems/two_d/top_down_controller.dart';
import '../subsystems/ui/dialogue.dart';
import '../subsystems/ui/minimap.dart';
import '../subsystems/ui/ui_widgets.dart';
import 'interpreter.dart';
import 'script_library.dart';

// ---------------------------------------------------------------------------
// Documentation (API reference + autocomplete)

class ApiEntry {
  /// Where it lives: '' for globals, else a type such as 'Entity', 'Vec2', 'Input'.
  final String owner;
  final String category;
  final String signature;
  final String doc;
  final bool isCallback;
  const ApiEntry(this.owner, this.category, this.signature, this.doc, {this.isCallback = false});

  String get name => RegExp(r'^[A-Za-z_]\w*').firstMatch(signature)?.group(0) ?? signature;
  bool get isMethod => signature.contains('(');

  /// Text to insert when chosen in autocomplete.
  String get insertText => isMethod ? '$name(' : name;
}

class ScriptApi {
  static final List<ApiEntry> entries = [];

  static void _add(String owner, String category, List<(String, String)> items, {bool callbacks = false}) {
    for (final (sig, doc) in items) {
      entries.add(ApiEntry(owner, category, sig, doc, isCallback: callbacks));
    }
  }

  static List<ApiEntry> members(String owner) => entries.where((e) => e.owner == owner).toList();
  static List<ApiEntry> get globals => entries.where((e) => e.owner == '' && !e.isCallback).toList();
  static List<ApiEntry> get callbacks => entries.where((e) => e.isCallback).toList();

  /// Owners with members, in reference order.
  static List<String> get owners => {for (final e in entries) if (e.owner.isNotEmpty) e.owner}.toList();
}

// ---------------------------------------------------------------------------
// Helpers

EmberScripts get _lib => EmberScripts.instance;
EmberEntity? get _self => _lib.current?.entity;
EmberScene get _scene => _self?.scene ?? EmberEngine.instance.activeScene;

NativeFunction _fn(String name, Object? Function(List<Object?> a) f) => NativeFunction(name, (a, _) => f(a));
NativeFunction _fnN(String name, Object? Function(List<Object?> a, Map<String, Object?> n) f) => NativeFunction(name, f);

double _num(List<Object?> a, int i, String what) => arg<num>(a, i, what).toDouble();

Vector2 _vec(Object? v, String what) {
  if (v is Vector2) return v.clone();
  if (v is List && v.length == 2 && v[0] is num && v[1] is num) {
    return Vector2((v[0] as num).toDouble(), (v[1] as num).toDouble());
  }
  if (v is EmberEntity) return _center(v);
  throw ScriptArgumentError('$what should be a Vec2 (vec(x, y)) or an entity, not ${Interpreter.describe(v)}');
}

/// A point from `(entityOrVec)` or `(x, y)` arguments starting at [i].
Vector2 _point(List<Object?> a, int i, String what) {
  if (i < a.length && a[i] is num) return Vector2(_num(a, i, 'x'), _num(a, i + 1, 'y'));
  return _vec(i < a.length ? a[i] : null, what);
}

Vector2 _center(EmberEntity e) {
  if (e.hasComponent<Transform2DComponent>()) {
    final c = Combat.bodyOf(e).center;
    return Vector2(c.dx, c.dy);
  }
  final t3 = e.getComponent<Transform3DComponent>();
  return t3 == null ? Vector2.zero() : Vector2(t3.position.x, t3.position.y);
}

/// The 3D position of an entity with a Transform 3D (world space), or null.
Vector3? _pos3(EmberEntity e) => e.getComponent<Transform3DComponent>()?.worldPosition;

/// A Vec3 from a Vec3, a 3D entity, or a Vec2 (z = 0).
Vector3 _vec3(Object? v, String what) {
  if (v is Vector3) return v.clone();
  if (v is EmberEntity) {
    final p = _pos3(v);
    if (p != null) return p;
    final c = _center(v);
    return Vector3(c.x, c.y, 0);
  }
  if (v is Vector2) return Vector3(v.x, v.y, 0);
  throw ScriptArgumentError('$what should be a Vec3 (vec3(x, y, z)) or a 3D entity, not ${Interpreter.describe(v)}');
}

/// A 3D point from `(entityOrVec)` or `(x, y, z)` arguments starting at [i].
Vector3 _point3(List<Object?> a, int i, String what) {
  if (i < a.length && a[i] is num) return Vector3(_num(a, i, 'x'), _num(a, i + 1, 'y'), _num(a, i + 2, 'z'));
  return _vec3(i < a.length ? a[i] : null, what);
}

/// True when [v] names a point in 3D (a Vec3 or an entity with a Transform 3D).
bool _is3DPoint(Object? v) => v is Vector3 || (v is EmberEntity && v.hasComponent<Transform3DComponent>());

/// Yaw (degrees) that makes a Transform 3D face along [d] (forward is -Z at yaw 0).
double _yawToward(Vector3 d) => math.atan2(-d.x, -d.z) * 180 / math.pi;

/// Smallest signed difference between two angles in degrees (-180..180).
double _angleDelta(double from, double to) {
  var d = (to - from) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// Where to put a spawned copy: a Vec3 / 3D entity in 3D, else a 2D point.
Object? _spawnAt(List<Object?> a, int i) {
  if (i >= a.length) return null;
  if (_is3DPoint(a[i])) return _vec3(a[i], 'position');
  if (a[i] is num && i + 2 < a.length && a[i + 2] is num) return _point3(a, i, 'position');
  return _point(a, i, 'position');
}

EmberEntity _entity(Object? v, String what) {
  if (v is EmberEntity) return v;
  if (v is String) {
    final found = _scene.findByName(v);
    if (found != null) return found;
    throw ScriptArgumentError('no entity named "$v"');
  }
  throw ScriptArgumentError('$what should be an entity, not ${Interpreter.describe(v)}');
}

/// Normalises names for loose matching: "Flame Sprite" == "flameSprite" == "sprite".
String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');

String _colorToScript(Color c) {
  final argb = c.toARGB32();
  final hex = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  return (argb >> 24) == 0xFF ? '#$hex' : '#${(argb >> 24).toRadixString(16).padLeft(2, '0').toUpperCase()}$hex';
}

Color _colorFromScript(Object? v) {
  if (v is Color) return v;
  if (v is int) return Color(v <= 0xFFFFFF ? 0xFF000000 | v : v);
  if (v is String) {
    var s = v.trim().replaceFirst('#', '');
    const named = {
      'white': 'FFFFFF', 'black': '000000', 'red': 'EF4444', 'green': '22C55E', 'blue': '3B82F6', 'yellow': 'FACC15',
      'orange': 'F97316', 'purple': 'A855F7', 'gray': '9CA3AF', 'grey': '9CA3AF', 'pink': 'F472B6', 'cyan': '22D3EE',
    };
    s = named[s.toLowerCase()] ?? s;
    final n = int.tryParse(s, radix: 16);
    if (n != null && (s.length == 6 || s.length == 8)) return Color(s.length == 6 ? 0xFF000000 | n : n);
  }
  throw ScriptArgumentError('a color should look like "#FF8800" or "red", not ${Interpreter.describe(v)}');
}

/// Engine value -> script value.
Object? toScript(Object? v) => switch (v) {
      Color() => _colorToScript(v),
      EmberAnchor() => v.name,
      Vector2() => v.clone(),
      Vector3() => [v.x, v.y, v.z],
      Enum() => v.name,
      _ => v,
    };

/// Script value -> engine value shaped like [like].
Object? fromScript(Object? v, Object? like) {
  if (like is double) return v is num ? v.toDouble() : throw ScriptArgumentError('expected a number');
  if (like is int) return v is num ? v.round() : throw ScriptArgumentError('expected a whole number');
  if (like is bool) return v is bool ? v : throw ScriptArgumentError('expected true or false');
  if (like is String) return v?.toString() ?? '';
  if (like is Color) return _colorFromScript(v);
  if (like is Vector2) return _vec(v, 'value');
  if (like is Vector3) {
    if (v is List && v.length == 3) return Vector3((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble());
    throw ScriptArgumentError('expected [x, y, z]');
  }
  if (like is EmberAnchor) {
    return EmberAnchor.values.firstWhere((a) => _norm(a.name) == _norm('$v'),
        orElse: () => throw ScriptArgumentError('unknown anchor "$v"'));
  }
  return v;
}

/// Finds a component on [e] by type name ("Health", "Flame Sprite", "sprite", ...).
EmberComponent? findComponent(EmberEntity e, String name) {
  final want = _norm(name);
  final aliases = _componentAliases[want];
  for (final c in e.components) {
    final n = _norm(c.displayName);
    if (n == want || (aliases != null && aliases.contains(n))) return c;
  }
  if (aliases != null) return null;
  for (final c in e.components) {
    if (_norm(c.displayName).contains(want)) return c;
  }
  return null;
}

/// Shortcut names for components. Several targets: the first one the entity has (2D or 3D).
const Map<String, List<String>> _componentAliases = {
  'controller': ['charactercontroller2d', 'charactercontroller3d'],
  'platformer': ['charactercontroller2d'],
  'particles': ['particleemitter2d', 'particleemitter3d'],
  'camera': ['camera2d', 'camera'],
  'transform': ['transform2d', 'transform3d'],
  'rigidbody': ['rigidbody2d', 'rigidbody3d'],
  'rb': ['rigidbody2d', 'rigidbody3d'],
  'physics': ['rigidbody2d', 'rigidbody3d'],
  'mesh': ['meshrenderer3d'],
  'enemy': ['enemyai3d'],
  'story': ['storyplayer'],
  'projectile': ['projectile', 'projectile3d'],
  'sprite': ['flamesprite'],
  'hitbox': ['flamehitbox2d'],
  'body': ['flamehitbox2d'],
  'tilemap': ['flametilemap', 'flametilemap2d'],
  'light': ['light2d'],
  'mover': ['topdowncontroller2d'],
  'topdown': ['topdowncontroller2d'],
  'ai': ['monsterai'],
  'text': ['uitext'],
  'bar': ['uibar'],
  'button': ['uibutton'],
  'image': ['uiimage'],
  'audio': ['audiosource'],
  'animator': ['spriteanimator'],
  'joint': ['joint2d'],
  'line': ['line2d'],
  'bullets': ['bulletpool2d'],
  'follower': ['pathfollower2d'],
  'minimap': ['uiminimap'],
};

/// Optional settings shared by bullets.fire / ring / spread.
({
  int frame,
  double? radius,
  double accel,
  double curve,
  double maxSpeed,
  double scale,
  double? damage,
  double life,
  EmberEntity? target,
  double turn,
  double splash
}) _bulletOptions(Map<String, Object?> o) {
  double? d(String k) => (o[k] as num?)?.toDouble();
  final target = o['target'];
  if (target != null && target is! EmberEntity) throw ScriptArgumentError('target should be an entity, not ${Interpreter.describe(target)}');
  return (
    target: target as EmberEntity?,
    turn: d('turn') ?? 540,
    splash: d('splash') ?? 0,
    frame: (o['frame'] as num?)?.round() ?? 0,
    radius: d('radius'),
    accel: d('accel') ?? 0,
    curve: d('curve') ?? 0,
    maxSpeed: d('maxSpeed') ?? 0,
    scale: d('scale') ?? 1,
    damage: d('damage'),
    life: d('life') ?? 10,
  );
}

// Keyboard names: 'A', 'Space', 'Left', 'Enter', 'Shift', 'Escape', ...
final Map<String, LogicalKeyboardKey> _keyCache = {};
const _keyAliases = {
  'space': LogicalKeyboardKey.space, 'left': LogicalKeyboardKey.arrowLeft, 'right': LogicalKeyboardKey.arrowRight,
  'up': LogicalKeyboardKey.arrowUp, 'down': LogicalKeyboardKey.arrowDown, 'enter': LogicalKeyboardKey.enter,
  'return': LogicalKeyboardKey.enter, 'esc': LogicalKeyboardKey.escape, 'escape': LogicalKeyboardKey.escape,
  'shift': LogicalKeyboardKey.shiftLeft, 'ctrl': LogicalKeyboardKey.controlLeft, 'control': LogicalKeyboardKey.controlLeft,
  'alt': LogicalKeyboardKey.altLeft, 'tab': LogicalKeyboardKey.tab, 'backspace': LogicalKeyboardKey.backspace,
};

LogicalKeyboardKey _key(Object? name) {
  final s = arg<String>([name], 0, 'key name');
  final k = s.toLowerCase();
  final cached = _keyCache[k];
  if (cached != null) return cached;
  var key = _keyAliases[k];
  if (key == null) {
    for (final candidate in LogicalKeyboardKey.knownLogicalKeys) {
      if (candidate.keyLabel.toLowerCase() == k || (candidate.debugName?.toLowerCase() ?? '') == k) {
        key = candidate;
        break;
      }
    }
  }
  if (key == null) throw ScriptArgumentError('unknown key "$s" (try "A", "Space", "Left", "Enter", "Shift")');
  return _keyCache[k] = key;
}

EngineAction _action(Object? name) {
  final s = _norm(arg<String>([name], 0, 'action'));
  const aliases = {'attack': 'fire', 'shoot': 'fire', 'use': 'interact', 'run': 'sprint', 'up': 'moveforward', 'down': 'movebackward', 'left': 'moveleft', 'right': 'moveright'};
  final want = aliases[s] ?? s;
  return EngineAction.values.firstWhere((a) => _norm(a.name) == want,
      orElse: () => throw ScriptArgumentError('unknown action "$name" (jump, fire, interact, sprint, crouch)'));
}

// ---------------------------------------------------------------------------
// Types

class _Vec2Host extends HostType {
  @override
  String get typeName => 'Vec2';
  @override
  bool matches(Object v) => v is Vector2;
  @override
  String describe(Object obj) => Interpreter.stringify(obj);
  @override
  List<String> memberNames(Object obj) => [for (final e in ScriptApi.members('Vec2')) e.name];

  @override
  Object? getMember(Object obj, String name) {
    final v = obj as Vector2;
    return switch (name) {
      'x' => v.x,
      'y' => v.y,
      'length' => v.length,
      'angle' => math.atan2(v.y, v.x),
      'normalized' => _fn(name, (_) => v.length2 == 0 ? Vector2.zero() : v.normalized()),
      'distanceTo' => _fn(name, (a) => v.distanceTo(_point(a, 0, 'other'))),
      'dot' => _fn(name, (a) => v.dot(_vec(a[0], 'other'))),
      'rotated' => _fn(name, (a) {
          final r = _num(a, 0, 'radians'), c = math.cos(r), s = math.sin(r);
          return Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
        }),
      'lerp' => _fn(name, (a) {
          final o = _vec(a[0], 'other'), t = _num(a, 1, 't');
          return v + (o - v) * t;
        }),
      'withX' => _fn(name, (a) => Vector2(_num(a, 0, 'x'), v.y)),
      'withY' => _fn(name, (a) => Vector2(v.x, _num(a, 0, 'y'))),
      _ => missing,
    };
  }

  @override
  bool setMember(Object obj, String name, Object? value) =>
      throw ScriptArgumentError('vectors can\'t be changed in place — use v = vec(newX, v.y) or v.withX(newX)');
}

class _Vec3Host extends HostType {
  @override
  String get typeName => 'Vec3';
  @override
  bool matches(Object v) => v is Vector3;
  @override
  String describe(Object obj) => Interpreter.stringify(obj);
  @override
  List<String> memberNames(Object obj) => [for (final e in ScriptApi.members('Vec3')) e.name];

  @override
  Object? getMember(Object obj, String name) {
    final v = obj as Vector3;
    return switch (name) {
      'x' => v.x,
      'y' => v.y,
      'z' => v.z,
      'length' => v.length,
      'flat' => Vector3(v.x, 0, v.z),
      'normalized' => _fn(name, (_) => v.length2 == 0 ? Vector3.zero() : v.normalized()),
      'distanceTo' => _fn(name, (a) => v.distanceTo(_point3(a, 0, 'other'))),
      'dot' => _fn(name, (a) => v.dot(_vec3(a[0], 'other'))),
      'cross' => _fn(name, (a) => v.cross(_vec3(a[0], 'other'))),
      'lerp' => _fn(name, (a) {
          final o = _vec3(a[0], 'other'), t = _num(a, 1, 't');
          return v + (o - v) * t;
        }),
      'withX' => _fn(name, (a) => Vector3(_num(a, 0, 'x'), v.y, v.z)),
      'withY' => _fn(name, (a) => Vector3(v.x, _num(a, 0, 'y'), v.z)),
      'withZ' => _fn(name, (a) => Vector3(v.x, v.y, _num(a, 0, 'z'))),
      _ => missing,
    };
  }

  @override
  bool setMember(Object obj, String name, Object? value) =>
      throw ScriptArgumentError('vectors can\'t be changed in place — use v = vec3(newX, v.y, v.z) or v.withX(newX)');
}

class _EntityHost extends HostType {
  @override
  String get typeName => 'Entity';
  @override
  bool matches(Object v) => v is EmberEntity;
  @override
  String describe(Object obj) => 'Entity(${(obj as EmberEntity).name})';
  @override
  List<String> memberNames(Object obj) => [for (final e in ScriptApi.members('Entity')) e.name];

  @override
  Object? getMember(Object obj, String name) {
    final e = obj as EmberEntity;
    final t2 = e.getComponent<Transform2DComponent>();
    final t3 = t2 == null ? e.getComponent<Transform3DComponent>() : null;
    switch (name) {
      case 'name':
        return e.name;
      case 'id':
        return e.id;
      case 'enabled':
        return e.enabled;
      case 'alive':
        return e.scene != null;
      case 'tags':
        return e.tags.toList();
      case 'x':
        return t2?.position.x ?? t3?.position.x ?? 0.0;
      case 'y':
        return t2?.position.y ?? t3?.position.y ?? 0.0;
      case 'z':
        return t3?.position.z ?? 0.0;
      case 'position':
        if (t3 != null) return t3.position.clone();
        return t2 != null ? t2.position.clone() : Vector2.zero();
      case 'worldPosition':
        return t3?.worldPosition ?? (t2 != null ? t2.worldPosition.clone() : Vector2.zero());
      case 'yaw':
        return t3?.euler.y ?? 0.0;
      case 'pitch':
        return t3?.euler.x ?? 0.0;
      case 'roll':
        return t3?.euler.z ?? 0.0;
      case 'forward':
        return t3?.forward ?? Vector3(0, 0, -1);
      case 'right':
        return t3?.right ?? Vector3(1, 0, 0);
      case 'up':
        return t3?.up ?? Vector3(0, 1, 0);
      case 'lookAt':
        return _fn(name, (a) {
          if (t3 == null) return null;
          final d = _point3(a, 0, 'target') - t3.worldPosition;
          if (d.length2 == 0) return null;
          final level = optArg<bool>(a, a.isNotEmpty && a[0] is num ? 3 : 1, 'level', true);
          final pitch = level ? t3.euler.x : math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z)) * 180 / math.pi;
          t3.euler = Vector3(pitch, _yawToward(d), t3.euler.z);
          return null;
        });
      case 'turnToward':
        return _fn(name, (a) {
          if (t3 == null) return 0.0;
          final d = _point3(a, 0, 'target') - t3.worldPosition;
          final maxStep = _num(a, a.isNotEmpty && a[0] is num ? 3 : 1, 'maxDegrees');
          if (d.x * d.x + d.z * d.z < 1e-9) return 0.0;
          final delta = _angleDelta(t3.euler.y, _yawToward(d));
          final step = delta.clamp(-maxStep, maxStep);
          t3.euler = Vector3(t3.euler.x, t3.euler.y + step, t3.euler.z);
          return (delta - step).abs();
        });
      case 'center':
        return _center(e);
      case 'rotation':
        return t2?.rotation ?? 0.0;
      case 'layer':
        return t2?.zIndex ?? 0;
      case 'scale':
        return t2?.scale.clone() ?? Vector2(1, 1);
      case 'width':
        return t2?.size.x ?? 0.0;
      case 'height':
        return t2?.size.y ?? 0.0;
      case 'parent':
        return e.parent;
      case 'children':
        return e.children.toList();
      case 'script':
        return _scriptOf(e);
      case 'hasTag':
        return _fn(name, (a) => e.tags.contains(arg<String>(a, 0, 'tag')));
      case 'addTag':
        return _fn(name, (a) => e.tags.add(arg<String>(a, 0, 'tag')));
      case 'removeTag':
        return _fn(name, (a) => e.tags.remove(arg<String>(a, 0, 'tag')));
      case 'get':
        return _fn(name, (a) => findComponent(e, arg<String>(a, 0, 'component name')));
      case 'has':
        return _fn(name, (a) => findComponent(e, arg<String>(a, 0, 'component name')) != null);
      case 'add':
        return _fn(name, (a) {
          final type = arg<String>(a, 0, 'component type');
          final c = ComponentRegistry.create(type, {});
          if (c == null) throw ScriptArgumentError('no component type "$type"');
          e.addComponent(c);
          // Scripts only run while playing, so the new component starts right away
          c.internalAwake();
          c.internalStart();
          return c;
        });
      case 'remove':
        return _fn(name, (a) {
          final c = findComponent(e, arg<String>(a, 0, 'component name'));
          if (c != null) e.removeComponent(c);
          return c != null;
        });
      case 'child':
        return _fn(name, (a) {
          final n = arg<String>(a, 0, 'name');
          for (final c in e.children) {
            if (c.name == n) return c;
          }
          return null;
        });
      case 'destroy':
        return _fn(name, (a) {
          final s = e.scene;
          final delay = optArg<num>(a, 0, 'seconds', 0).toDouble();
          if (s == null) return null;
          if (delay > 0) {
            EmberTween.delay(delay, () => s.destroyLater(e));
          } else {
            s.destroyLater(e);
          }
          return null;
        });
      case 'distanceTo':
        return _fn(name, (a) {
          if (t3 != null && (a.isEmpty || _is3DPoint(a[0]) || (a.length > 2 && a[2] is num))) {
            return t3.worldPosition.distanceTo(_point3(a, 0, 'target'));
          }
          return _center(e).distanceTo(_point(a, 0, 'target'));
        });
      case 'directionTo':
        return _fn(name, (a) {
          if (t3 != null && (a.isEmpty || _is3DPoint(a[0]) || (a.length > 2 && a[2] is num))) {
            final d = _point3(a, 0, 'target') - t3.worldPosition;
            return d.length2 == 0 ? Vector3.zero() : d.normalized();
          }
          final d = _point(a, 0, 'target') - _center(e);
          return d.length2 == 0 ? Vector2.zero() : d.normalized();
        });
      case 'moveToward':
        return _fn(name, (a) {
          if (t3 != null && (a.isEmpty || _is3DPoint(a[0]) || (a.length > 3 && a[2] is num))) {
            final target = _point3(a, 0, 'target');
            final step = _num(a, a.isNotEmpty && a[0] is num ? 3 : 1, 'maxDistance');
            final d = target - t3.worldPosition;
            t3.position = t3.position + (d.length <= step ? d : d.normalized() * step);
            return d.length <= step;
          }
          final target = _point(a, 0, 'target');
          final step = _num(a, a.isNotEmpty && a[0] is num ? 2 : 1, 'maxDistance');
          final d = target - _center(e);
          final move = d.length <= step ? d : d.normalized() * step;
          if (t2 != null) t2.position = t2.position + move;
          return d.length <= step;
        });
      case 'overlaps':
        return _fn(name, (a) => Combat.bodyOf(e).overlaps(Combat.bodyOf(_entity(a[0], 'other'))));
      case 'call':
        return _fn(name, (a) {
          final fn = arg<String>(a, 0, 'function name');
          Object? result;
          var found = false;
          e.notifyScripts((s) {
            if (s is EmberScriptBehavior && s.hasFunction(fn)) {
              found = true;
              result = s.callFunction(fn, a.sublist(1));
            }
          });
          if (!found) throw ScriptArgumentError('${e.name} has no script function "$fn"');
          return result;
        });
      case 'clone':
        return _fn(name, (a) => spawnCopy(e, _spawnAt(a, 0)));
      case 'interact':
        return _fn(name, (a) {
          final s = e.scene;
          return s == null ? null : Interaction.interact(s, e, range: optArg<num>(a, 0, 'range', 24).toDouble());
        });
      default:
        // Shortcut to a component: self.health, self.sprite, self.mover, ...
        final c = findComponent(e, name);
        if (c != null) return c;
        return missing;
    }
  }

  static Object? _scriptOf(EmberEntity e) {
    for (final c in e.components) {
      if (c is ScriptComponent && c.scriptInstance is EmberScriptBehavior) return c.scriptInstance;
    }
    return null;
  }

  @override
  bool setMember(Object obj, String name, Object? value) {
    final e = obj as EmberEntity;
    final t2 = e.getComponent<Transform2DComponent>();
    final t3 = t2 == null ? e.getComponent<Transform3DComponent>() : null;
    double n() => value is num ? value.toDouble() : throw ScriptArgumentError('$name should be a number');
    switch (name) {
      case 'name':
        e.name = '$value';
      case 'enabled':
        e.enabled = value == true;
      case 'x':
        if (t2 != null) t2.position = Vector2(n(), t2.position.y);
        if (t3 != null) t3.position = Vector3(n(), t3.position.y, t3.position.z);
      case 'y':
        if (t2 != null) t2.position = Vector2(t2.position.x, n());
        if (t3 != null) t3.position = Vector3(t3.position.x, n(), t3.position.z);
      case 'z':
        if (t3 != null) t3.position = Vector3(t3.position.x, t3.position.y, n());
      case 'position':
        if (t3 != null) {
          t3.position = value is Vector3 ? value.clone() : Vector3(_vec(value, 'position').x, _vec(value, 'position').y, t3.position.z);
        } else if (t2 != null) {
          t2.position = _vec(value, 'position');
        }
      case 'yaw':
        if (t3 != null) t3.euler = Vector3(t3.euler.x, n(), t3.euler.z);
      case 'pitch':
        if (t3 != null) t3.euler = Vector3(n(), t3.euler.y, t3.euler.z);
      case 'roll':
        if (t3 != null) t3.euler = Vector3(t3.euler.x, t3.euler.y, n());
      case 'center':
        final v = _vec(value, 'center');
        if (t2 != null) t2.position = t2.position + (v - _center(e));
      case 'rotation':
        t2?.rotation = n();
      case 'layer':
        t2?.zIndex = n().round();
      case 'scale':
        if (t2 != null) t2.scale = value is num ? Vector2.all(value.toDouble()) : _vec(value, 'scale');
      case 'width':
        if (t2 != null) t2.size = Vector2(n(), t2.size.y);
      case 'height':
        if (t2 != null) t2.size = Vector2(t2.size.x, n());
      default:
        return false;
    }
    return true;
  }
}

/// The Ember Script on another entity: read and write its variables.
class _ScriptVarsHost extends HostType {
  @override
  String get typeName => 'Script';
  @override
  bool matches(Object v) => v is EmberScriptBehavior;
  @override
  String describe(Object obj) => 'Script(${(obj as EmberScriptBehavior).file})';
  @override
  List<String> memberNames(Object obj) => (obj as EmberScriptBehavior).program?.fields.map((f) => f.name).toList() ?? const [];

  @override
  Object? getMember(Object obj, String name) {
    final s = obj as EmberScriptBehavior;
    if (s.program?.fields.any((f) => f.name == name) ?? false) return s.field(name);
    if (s.hasFunction(name)) return _fn(name, (a) => s.callFunction(name, a));
    return missing;
  }

  @override
  bool setMember(Object obj, String name, Object? value) {
    final s = obj as EmberScriptBehavior;
    final inst = s.instance;
    if (inst == null || !inst.fields.containsKey(name)) return false;
    if (inst.root.isFinal(name)) throw ScriptArgumentError('"$name" is final');
    inst.fields[name] = value;
    return true;
  }
}

class _ComponentHost extends HostType {
  @override
  String get typeName => 'Component';
  @override
  bool matches(Object v) => v is EmberComponent;
  @override
  String describe(Object obj) => (obj as EmberComponent).displayName;

  @override
  List<String> memberNames(Object obj) {
    final c = obj as EmberComponent;
    return [
      'enabled', 'type', 'entity',
      ...c.inspectableProperties.map((p) => p.name),
      ..._special.keys.where((k) => _special[k]!.$1(c)),
    ];
  }

  // Extra members per component type: (applies?, getter, setter)
  static final Map<String, (bool Function(EmberComponent), Object? Function(EmberComponent, String), void Function(EmberComponent, Object?)?)> _special = {
    // Sprite
    'frame': ((c) => c is FlameSpriteComponent || c is UIImageComponent, (c, _) => c is FlameSpriteComponent ? c.frame : (c as UIImageComponent).frame,
        (c, v) => c is FlameSpriteComponent ? c.frame = (v as num).round() : (c as UIImageComponent).frame = (v as num).round()),
    'asset': ((c) => c is FlameSpriteComponent, (c, _) => (c as FlameSpriteComponent).assetPath, (c, v) => (c as FlameSpriteComponent).assetPath = '$v'),
    'visible': ((c) => true, (c, _) => c.enabled, (c, v) => c.enabled = v == true),
    // Animator
    'play': ((c) => c is SpriteAnimatorComponent, (c, n) => _fn(n, (a) {
          (c as SpriteAnimatorComponent).play(arg<String>(a, 0, 'clip'), restart: optArg<bool>(a, 1, 'restart', false));
          return null;
        }), null),
    'current': ((c) => c is SpriteAnimatorComponent, (c, _) => (c as SpriteAnimatorComponent).currentClip, null),
    'finished': ((c) => c is SpriteAnimatorComponent, (c, _) => (c as SpriteAnimatorComponent).isFinished, null),
    'hasClip': ((c) => c is SpriteAnimatorComponent, (c, n) => _fn(n, (a) => (c as SpriteAnimatorComponent).hasClip(arg<String>(a, 0, 'clip'))), null),
    // Health
    'health': ((c) => c is HealthComponent, (c, _) => (c as HealthComponent).health, (c, v) {
          final h = c as HealthComponent;
          h.health = (v as num).toDouble().clamp(0, h.maxHealth).toDouble();
        }),
    'dead': ((c) => c is HealthComponent, (c, _) => (c as HealthComponent).isDead, null),
    'invulnerable': ((c) => c is HealthComponent, (c, _) => (c as HealthComponent).isInvulnerable, null),
    'damage': ((c) => c is HealthComponent, (c, n) => _fn(n, (a) => (c as HealthComponent).damage(
          _num(a, 0, 'amount'),
          // A script hurting its own entity (spikes, falling) is not friendly fire
          source: a.length > 1 && a[1] != null ? _entity(a[1], 'source') : (identical(_self, c.entity) ? null : _self),
          knockback: a.length > 2 && a[2] != null && a[2] is! Vector3 ? _vec(a[2], 'knockback') : null,
          push: a.length > 2 && a[2] is Vector3 ? a[2] as Vector3 : null,
        )), null),
    'heal': ((c) => c is HealthComponent, (c, n) => _fn(n, (a) {
          (c as HealthComponent).heal(_num(a, 0, 'amount'));
          return null;
        }), null),
    // Top-down movement
    'move': ((c) => c is TopDownController2DComponent || c is CharacterController2DComponent || c is CharacterController3DComponent, (c, n) => _fn(n, (a) {
          if (c is CharacterController3DComponent) {
            c.move(a.isEmpty ? Vector3.zero() : _vec3(a[0], 'direction'), optArg<bool>(a, 1, 'sprint', false), _lib.dt);
          } else if (c is TopDownController2DComponent) {
            c.move(a.isEmpty ? Vector2.zero() : _point(a, 0, 'direction'), _lib.dt);
          } else {
            final cc = c as CharacterController2DComponent;
            final jumpHeld = optArg<bool>(a, 1, 'jumpHeld', false);
            cc.updateMovement(
              horizontalInput: optArg<num>(a, 0, 'horizontal', 0).toDouble(),
              isJumpPressed: jumpHeld,
              isJumpJustPressed: optArg<bool>(a, 2, 'jumpPressed', false),
              dt: _lib.dt,
            );
          }
          return null;
        }), null),
    'velocity': ((c) => c is TopDownController2DComponent || c is CharacterController2DComponent || c is RigidBody2DComponent || c is CharacterController3DComponent,
        (c, _) => switch (c) {
              CharacterController3DComponent() => c.velocity.clone(),
              TopDownController2DComponent() => c.velocity.clone(),
              RigidBody2DComponent() => c.velocity,
              _ => (c as CharacterController2DComponent).velocity.clone(),
            },
        (c, v) {
          if (c is CharacterController3DComponent) {
            c.velocity.setFrom(_vec3(v, 'velocity'));
            return;
          }
          final vv = _vec(v, 'velocity');
          if (c is TopDownController2DComponent) c.velocity.setFrom(vv);
          if (c is CharacterController2DComponent) c.velocity.setFrom(vv);
          if (c is RigidBody2DComponent) c.velocity = vv;
        }),
    // Rigid Body 2D
    'angularVelocity': ((c) => c is RigidBody2DComponent, (c, _) => (c as RigidBody2DComponent).angularVelocity,
        (c, v) => (c as RigidBody2DComponent).angularVelocity = (v as num).toDouble()),
    'speed': ((c) => c is RigidBody2DComponent, (c, _) => (c as RigidBody2DComponent).velocity.length, null),
    'mass': ((c) => c is RigidBody2DComponent, (c, _) => (c as RigidBody2DComponent).mass, null),
    'sleeping': ((c) => c is RigidBody2DComponent, (c, _) => (c as RigidBody2DComponent).sleeping, null),
    'applyImpulse': ((c) => c is RigidBody2DComponent, (c, n) => _fn(n, (a) {
          (c as RigidBody2DComponent).applyImpulse(_vec(a.isEmpty ? null : a[0], 'impulse'), a.length > 1 ? _vec(a[1], 'point') : null);
          return null;
        }), null),
    'applyForce': ((c) => c is RigidBody2DComponent, (c, n) => _fn(n, (a) {
          (c as RigidBody2DComponent).applyForce(_vec(a.isEmpty ? null : a[0], 'force'), a.length > 1 ? _vec(a[1], 'point') : null);
          return null;
        }), null),
    'applyTorque': ((c) => c is RigidBody2DComponent, (c, n) => _fn(n, (a) {
          (c as RigidBody2DComponent).applyTorque(_num(a, 0, 'torque'));
          return null;
        }), null),
    'wake': ((c) => c is RigidBody2DComponent, (c, n) => _fn(n, (_) {
          (c as RigidBody2DComponent).wake();
          return null;
        }), null),
    // Joint 2D
    'broken': ((c) => c is PhysicsJoint2DComponent, (c, _) => (c as PhysicsJoint2DComponent).broken, null),
    'force': ((c) => c is PhysicsJoint2DComponent, (c, _) => (c as PhysicsJoint2DComponent).force, null),
    'snap': ((c) => c is PhysicsJoint2DComponent, (c, n) => _fn(n, (_) {
          (c as PhysicsJoint2DComponent).broken = true;
          return null;
        }), null),
    // Line 2D
    'points': ((c) => c is Line2DComponent, (c, _) => [for (final p in (c as Line2DComponent).points) p.clone()], (c, v) {
          if (v is! List) throw ScriptArgumentError('points should be a list of vec(x, y)');
          (c as Line2DComponent).points = [for (final p in v) _vec(p, 'point')];
        }),
    'clear': ((c) => c is Line2DComponent || c is BulletPool2DComponent, (c, n) => _fn(n, (_) {
          if (c is BulletPool2DComponent) return c.clear();
          (c as Line2DComponent).points = [];
          return null;
        }), null),
    // Bullet Pool 2D
    'fire': ((c) => c is BulletPool2DComponent, (c, n) => _fnN(n, (a, o) {
          final p = _point(a, 0, 'position');
          final i = a.isNotEmpty && a[0] is num ? 2 : 1;
          final b = _bulletOptions(o);
          return (c as BulletPool2DComponent).fire(p.x, p.y, _num(a, i, 'angle'), _num(a, i + 1, 'speed'),
              frame: b.frame,
              radius: b.radius,
              accel: b.accel,
              curve: b.curve,
              maxSpeed: b.maxSpeed,
              scale: b.scale,
              damage: b.damage,
              life: b.life,
              target: b.target,
              turn: b.turn,
              splash: b.splash);
        }), null),
    'ring': ((c) => c is BulletPool2DComponent, (c, n) => _fnN(n, (a, o) {
          final p = _point(a, 0, 'position');
          final i = a.isNotEmpty && a[0] is num ? 2 : 1;
          final b = _bulletOptions(o);
          (c as BulletPool2DComponent).ring(p.x, p.y, arg<num>(a, i, 'count').round(), _num(a, i + 1, 'speed'),
              offset: (o['offset'] as num?)?.toDouble() ?? 0,
              frame: b.frame, radius: b.radius, accel: b.accel, curve: b.curve, maxSpeed: b.maxSpeed, scale: b.scale, damage: b.damage);
          return null;
        }), null),
    'spread': ((c) => c is BulletPool2DComponent, (c, n) => _fnN(n, (a, o) {
          final p = _point(a, 0, 'position');
          final i = a.isNotEmpty && a[0] is num ? 2 : 1;
          final b = _bulletOptions(o);
          (c as BulletPool2DComponent).spread(p.x, p.y, _num(a, i, 'angle'), arg<num>(a, i + 1, 'count').round(), _num(a, i + 2, 'arc'), _num(a, i + 3, 'speed'),
              frame: b.frame, radius: b.radius, accel: b.accel, curve: b.curve, maxSpeed: b.maxSpeed, scale: b.scale, damage: b.damage);
          return null;
        }), null),
    // Flame TileMap: reading, writing and generating levels
    'getTile': ((c) => c is FlameTileMapComponent, (c, n) => _fn(n, (a) => (c as FlameTileMapComponent).getTile(arg<num>(a, 0, 'column').round(), arg<num>(a, 1, 'row').round())), null),
    'setTile': ((c) => c is FlameTileMapComponent, (c, n) => _fn(n, (a) {
          (c as FlameTileMapComponent).setTile(arg<num>(a, 0, 'column').round(), arg<num>(a, 1, 'row').round(), arg<num>(a, 2, 'tile').round());
          return null;
        }), null),
    'fill': ((c) => c is FlameTileMapComponent, (c, n) => _fn(n, (a) {
          final m = c as FlameTileMapComponent;
          m.setTiles(List.filled(m.columns * m.rows, arg<num>(a, 0, 'tile').round()));
          return null;
        }), null),
    'cellAt': ((c) => c is FlameTileMapComponent, (c, n) => _fn(n, (a) {
          final p = _point(a, 0, 'point');
          final cell = (c as FlameTileMapComponent).cellAt(p.x, p.y);
          return cell == null ? null : [cell.$1, cell.$2];
        }), null),
    'findPath': ((c) => c is FlameTileMapComponent, (c, n) => _fn(n, (a) {
          int i(int k, String what) => arg<num>(a, k, what).round();
          final path = (c as FlameTileMapComponent).findPath(i(0, 'from column'), i(1, 'from row'), i(2, 'to column'), i(3, 'to row'));
          return path == null ? null : [for (final (pc, pr) in path) [pc, pr]];
        }), null),
    'block': ((c) => c is FlameTileMapComponent, (c, n) => _fn(n, (a) {
          final m = c as FlameTileMapComponent;
          final k = arg<num>(a, 1, 'row').round() * m.columns + arg<num>(a, 0, 'column').round();
          if (a.length < 3 || a[2] == true) {
            m.blockedCells.add(k);
          } else {
            m.blockedCells.remove(k);
          }
          return null;
        }), null),
    'walkable': ((c) => c is FlameTileMapComponent, (c, n) => _fn(n, (a) => (c as FlameTileMapComponent).isWalkable(arg<num>(a, 0, 'column').round(), arg<num>(a, 1, 'row').round())), null),
    'cellCenter': ((c) => c is FlameTileMapComponent, (c, n) => _fn(n, (a) {
          final r = (c as FlameTileMapComponent).cellRect(arg<num>(a, 0, 'column').round(), arg<num>(a, 1, 'row').round());
          return Vector2(r.center.dx, r.center.dy);
        }), null),
    'cellsWith': ((c) => c is FlameTileMapComponent, (c, n) => _fn(n, (a) {
          final m = c as FlameTileMapComponent;
          final id = arg<num>(a, 0, 'tile').round();
          final out = <Object?>[];
          for (var r = 0; r < m.rows; r++) {
            for (var col = 0; col < m.columns; col++) {
              if (m.getTile(col, r) == id) out.add([col, r]);
            }
          }
          return out;
        }), null),
    'dungeon': ((c) => c is FlameTileMapComponent, (c, n) => _fnN(n, (a, o) {
          final m = c as FlameTileMapComponent;
          int i(String k, int d) => (o[k] as num?)?.round() ?? d;
          final rooms = TileGen.dungeon(m,
              seed: arg<num>(a, 0, 'seed').round(),
              rooms: i('rooms', 10),
              minSize: i('minSize', 5),
              maxSize: i('maxSize', 10),
              wall: i('wall', 1),
              floor: i('floor', 2),
              corridor: i('corridor', 2));
          return [
            for (final r in rooms)
              {
                'col': r.col,
                'row': r.row,
                'width': r.width,
                'height': r.height,
                'center': () {
                  final rect = m.cellRect(r.centerCol, r.centerRow);
                  return Vector2(rect.center.dx, rect.center.dy);
                }(),
              },
          ];
        }), null),
    'cave': ((c) => c is FlameTileMapComponent, (c, n) => _fnN(n, (a, o) {
          TileGen.cave(c as FlameTileMapComponent,
              seed: arg<num>(a, 0, 'seed').round(),
              fill: (o['fill'] as num?)?.toDouble() ?? 0.45,
              steps: (o['steps'] as num?)?.round() ?? 4,
              wall: (o['wall'] as num?)?.round() ?? 1,
              floor: (o['floor'] as num?)?.round() ?? 2);
          return null;
        }), null),
    'autotile': ((c) => c is FlameTileMapComponent, (c, n) => _fn(n, (a) {
          TileGen.autotile(c as FlameTileMapComponent, arg<num>(a, 0, 'wall tile').round(), arg<num>(a, 1, 'first piece').round());
          return null;
        }), null),
    'vary': ((c) => c is FlameTileMapComponent, (c, n) => _fnN(n, (a, o) {
          final ids = a.length > 1 && a[1] is List ? [for (final v in a[1] as List) (v as num).round()] : <int>[];
          TileGen.vary(c as FlameTileMapComponent, arg<num>(a, 0, 'tile').round(), ids, optArg<num>(a, 2, 'chance', 0.2).toDouble(),
              seed: (o['seed'] as num?)?.round() ?? 0);
          return null;
        }), null),
    // Path Follower 2D
    'slow': ((c) => c is PathFollower2DComponent, (c, n) => _fn(n, (a) {
          (c as PathFollower2DComponent).slow(_num(a, 0, 'factor'), optArg<num>(a, 1, 'seconds', 1).toDouble());
          return null;
        }), null),
    'progress': ((c) => c is PathFollower2DComponent, (c, _) => (c as PathFollower2DComponent).progress, null),
    'distance': ((c) => c is PathFollower2DComponent, (c, _) => (c as PathFollower2DComponent).distance,
        (c, v) => (c as PathFollower2DComponent).distance = (v as num).toDouble()),
    'remaining': ((c) => c is PathFollower2DComponent, (c, _) => (c as PathFollower2DComponent).remaining, null),
    'done': ((c) => c is PathFollower2DComponent, (c, _) => (c as PathFollower2DComponent).done, null),
    'slowed': ((c) => c is PathFollower2DComponent, (c, _) => (c as PathFollower2DComponent).slowed, null),
    'distanceTo': ((c) => c is Line2DComponent, (c, n) => _fn(n, (a) {
          final p = _point(a, 0, 'point');
          return (c as Line2DComponent).distanceTo(p.x, p.y);
        }), null),
    'clearAround': ((c) => c is BulletPool2DComponent, (c, n) => _fn(n, (a) {
          final p = _point(a, 0, 'position');
          final i = a.isNotEmpty && a[0] is num ? 2 : 1;
          return (c as BulletPool2DComponent).clearAround(p.x, p.y, _num(a, i, 'radius'));
        }), null),
    // Camera 2D
    'shake': ((c) => c is Camera2DComponent, (c, n) => _fn(n, (a) {
          (c as Camera2DComponent).shake(optArg<num>(a, 0, 'amount', 8).toDouble(), optArg<num>(a, 1, 'seconds', 0.3).toDouble());
          return null;
        }), null),
    'facing': ((c) => c is TopDownController2DComponent || c is CharacterController2DComponent,
        (c, _) => c is TopDownController2DComponent ? c.facing.name : ((c as CharacterController2DComponent).facing < 0 ? 'left' : 'right'),
        (c, v) {
          if (c is! TopDownController2DComponent) throw ScriptArgumentError('facing can only be set on a Top-Down Controller');
          c.facing = Facing.values.firstWhere((f) => f.name == '$v',
              orElse: () => throw ScriptArgumentError('facing is "up", "down", "left" or "right", not ${Interpreter.describe(v)}'));
        }),
    'moving': ((c) => c is TopDownController2DComponent, (c, _) => (c as TopDownController2DComponent).isMoving, null),
    'hitWall': ((c) => c is TopDownController2DComponent || c is CharacterController2DComponent,
        (c, _) => c is TopDownController2DComponent ? c.hitWall : (c as CharacterController2DComponent).hitWall, null),
    'knockback': ((c) => c is TopDownController2DComponent, (c, n) => _fn(n, (a) {
          (c as TopDownController2DComponent).knockback(_point(a, 0, 'impulse'));
          return null;
        }), null),
    // Platformer
    'grounded': ((c) => c is CharacterController2DComponent || c is CharacterController3DComponent,
        (c, _) => c is CharacterController3DComponent ? c.isGrounded : (c as CharacterController2DComponent).isGrounded, null),
    'canJump': ((c) => c is CharacterController2DComponent, (c, _) => (c as CharacterController2DComponent).canJump, null),
    'dash': ((c) => c is CharacterController2DComponent, (c, n) => _fn(n, (_) => (c as CharacterController2DComponent).dash()), null),
    'dashing': ((c) => c is CharacterController2DComponent, (c, _) => (c as CharacterController2DComponent).dashing, null),
    'onWall': ((c) => c is CharacterController2DComponent, (c, _) => (c as CharacterController2DComponent).onWall, null),
    'airJumpsLeft': ((c) => c is CharacterController2DComponent, (c, _) => (c as CharacterController2DComponent).airJumpsLeft, null),
    // UI Minimap
    'explored': ((c) => c is UIMinimapComponent, (c, _) => (c as UIMinimapComponent).explored, (c, v) => (c as UIMinimapComponent).explored = '${v ?? ''}'),
    'exploredFraction': ((c) => c is UIMinimapComponent, (c, _) => (c as UIMinimapComponent).exploredFraction, null),
    'revealAll': ((c) => c is UIMinimapComponent, (c, n) => _fn(n, (_) {
          (c as UIMinimapComponent).revealAll();
          return null;
        }), null),
    // Camera rooms
    'room': ((c) => c is Camera2DComponent, (c, _) => (c as Camera2DComponent).room?.entity, null),
    'snapToTarget': ((c) => c is Camera2DComponent, (c, n) => _fn(n, (_) {
          (c as Camera2DComponent).snapToTarget();
          return null;
        }), null),
    'keepInView': ((c) => c is Camera2DComponent, (c, n) => _fn(n, (a) {
          final t = arg<EmberEntity>(a, 0, 'entity').getComponent<Transform2DComponent>();
          if (t != null) t.position = (c as Camera2DComponent).keepInReach(t.position, margin: optArg<num>(a, 1, 'margin', 24).toDouble());
          return null;
        }), null),
    'bounce': ((c) => c is CharacterController2DComponent, (c, n) => _fn(n, (a) {
          final cc = c as CharacterController2DComponent;
          cc.bounce(optArg<num>(a, 0, 'strength', cc.jumpVelocity).toDouble());
          return null;
        }), null),
    // Story Player
    'variable': ((c) => c is StoryPlayerComponent, (c, n) => _fn(n, (a) => (c as StoryPlayerComponent).vars[arg<String>(a, 0, 'name')]), null),
    'setVariable': ((c) => c is StoryPlayerComponent, (c, n) => _fn(n, (a) {
          (c as StoryPlayerComponent).vars[arg<String>(a, 0, 'name')] = a.length > 1 ? a[1] : null;
          return null;
        }), null),
    'jump': ((c) => c is StoryPlayerComponent || c is CharacterController3DComponent, (c, n) => _fn(n, (a) {
          if (c is CharacterController3DComponent) return c.jump();
          (c as StoryPlayerComponent).jump(arg<String>(a, 0, 'label'));
          return null;
        }), null),
    'label': ((c) => c is StoryPlayerComponent, (c, _) => (c as StoryPlayerComponent).label, null),
    'ended': ((c) => c is StoryPlayerComponent, (c, _) => (c as StoryPlayerComponent).ended, null),
    'speaker': ((c) => c is StoryPlayerComponent, (c, _) => (c as StoryPlayerComponent).speaker, null),
    // 3D meshes
    'flash': ((c) => c is MeshRenderer3DComponent || c is Camera2DComponent, (c, n) => _fn(n, (a) {
          if (c is Camera2DComponent) {
            c.flash(a.isNotEmpty && a[0] != null ? _colorFromScript(a[0]) : const Color(0xB0FFFFFF), optArg<num>(a, 1, 'seconds', 0.25).toDouble());
            return null;
          }
          (c as MeshRenderer3DComponent).flash(
              a.isNotEmpty && a[0] != null ? _colorFromScript(a[0]) : const Color(0xFFFFFFFF), optArg<num>(a, 1, 'seconds', 0.12).toDouble());
          return null;
        }), null),
    // Effects & sound
    'burst': ((c) => c is ParticleEmitter2DComponent || c is ParticleEmitter3DComponent, (c, n) => _fn(n, (a) {
          final count = optArg<num>(a, 0, 'count', 20).round();
          if (c is ParticleEmitter3DComponent) {
            c.burst(count, a.length > 1 ? _vec3(a[1], 'position') : null);
          } else {
            (c as ParticleEmitter2DComponent).burst(count, a.length > 1 ? _vec(a[1], 'position') : null);
          }
          return null;
        }), null),
    'playSound': ((c) => c is AudioSourceComponent, (c, n) => _fn(n, (_) {
          (c as AudioSourceComponent).play();
          return null;
        }), null),
    'stopSound': ((c) => c is AudioSourceComponent, (c, n) => _fn(n, (_) {
          (c as AudioSourceComponent).stop();
          return null;
        }), null),
    'talk': ((c) => c is DialogueComponent, (c, n) => _fn(n, (_) {
          (c as DialogueComponent).talk();
          return null;
        }), null),
    // UI images (hearts)
    'count': ((c) => c is UIImageComponent || c is BulletPool2DComponent,
        (c, _) => c is BulletPool2DComponent ? c.count : (c as UIImageComponent).count,
        (c, v) {
          if (c is BulletPool2DComponent) throw ScriptArgumentError('count of a Bullet Pool can only be read');
          (c as UIImageComponent).count = (v as num).round();
        }),
    'filled': ((c) => c is UIImageComponent, (c, _) => (c as UIImageComponent).filled, (c, v) => (c as UIImageComponent).filled = (v as num).round()),
    // Monster AI
    'state': ((c) => c is MonsterAIComponent || c is EnemyAI3DComponent,
        (c, _) => c is EnemyAI3DComponent ? c.state : (c as MonsterAIComponent).state.name, null),
    'target': ((c) => c is EnemyAI3DComponent, (c, _) => (c as EnemyAI3DComponent).target, null),
    'shoot': ((c) => c is MonsterAIComponent, (c, n) => _fn(n, (a) {
          final ai = c as MonsterAIComponent;
          final e = ai.entity;
          final s = e?.scene;
          if (e == null || s == null) return null;
          final dir = _point(a, 0, 'direction');
          if (dir.length2 == 0) throw ScriptArgumentError('direction must not be vec(0, 0)');
          final team = e.getComponent<HealthComponent>()?.team ?? 'monster';
          return ai.spawnProjectile(s, e, _center(e), dir.normalized(), team);
        }), null),
    // Platformer probes (e.g. turn around at ledges)
    'groundAt': ((c) => c is CharacterController2DComponent,
        (c, n) => _fn(n, (a) => (c as CharacterController2DComponent).hasGroundAt(_num(a, 0, 'x'), _num(a, 1, 'y'))), null),
    'hazardAt': ((c) => c is CharacterController2DComponent,
        (c, n) => _fn(n, (a) => (c as CharacterController2DComponent).hasHazardAt(_num(a, 0, 'x'), _num(a, 1, 'y'))), null),
    // Transform
    'position': ((c) => c is Transform2DComponent, (c, _) => (c as Transform2DComponent).position.clone(),
        (c, v) => (c as Transform2DComponent).position = _vec(v, 'position')),
  };

  @override
  Object? getMember(Object obj, String name) {
    final c = obj as EmberComponent;
    if (name == 'enabled') return c.enabled;
    if (name == 'type') return c.displayName;
    if (name == 'entity') return c.entity;
    final s = _special[name];
    if (s != null && s.$1(c)) return s.$2(c, name);
    final p = _property(c, name);
    if (p != null) return toScript(p.getValue());
    return missing;
  }

  @override
  bool setMember(Object obj, String name, Object? value) {
    final c = obj as EmberComponent;
    if (name == 'enabled') {
      c.enabled = value == true;
      return true;
    }
    final s = _special[name];
    if (s != null && s.$1(c) && s.$3 != null) {
      try {
        s.$3!(c, value);
      } on TypeError {
        throw ScriptArgumentError('wrong kind of value ${Interpreter.describe(value)}');
      }
      return true;
    }
    final p = _property(c, name);
    if (p == null) return false;
    p.setValue(fromScript(value, p.getValue()));
    return true;
  }

  static dynamic _property(EmberComponent c, String name) {
    final props = c.inspectableProperties;
    for (final p in props) {
      if (p.name == name) return p;
    }
    final want = _norm(name);
    for (final p in props) {
      if (_norm(p.name) == want || _norm(p.label) == want) return p;
    }
    return null;
  }
}

class _TileHitHost extends HostType {
  @override
  String get typeName => 'Tile';
  @override
  bool matches(Object v) => v is TileHit;
  @override
  Object? getMember(Object obj, String name) {
    final t = obj as TileHit;
    return switch (name) {
      'column' => t.col,
      'row' => t.row,
      'id' => t.tileId,
      'kind' => t.kind.name,
      'x' => t.rect.center.dx,
      'y' => t.rect.center.dy,
      'left' => t.rect.left,
      'top' => t.rect.top,
      'right' => t.rect.right,
      'bottom' => t.rect.bottom,
      'set' => _fn(name, (a) {
          t.setTile(arg<int>(a, 0, 'tile id'));
          return null;
        }),
      _ => missing,
    };
  }
}

/// `Input.key('A')`, `Input.move`, ...
class InputApi {
  const InputApi();
}

class _InputHost extends HostType {
  @override
  String get typeName => 'Input';
  @override
  bool matches(Object v) => v is InputApi;
  @override
  Object? getMember(Object obj, String name) => switch (name) {
        'key' => _fn(name, (a) => Input.isKeyPressed(_key(a.isEmpty ? null : a[0]))),
        'pressed' => _fn(name, (a) => Input.isKeyJustPressed(_key(a.isEmpty ? null : a[0]))),
        'released' => _fn(name, (a) => Input.isKeyJustReleased(_key(a.isEmpty ? null : a[0]))),
        'action' => _fn(name, (a) => Input.isActionPressed(_action(a.isEmpty ? null : a[0]))),
        'actionPressed' => _fn(name, (a) => Input.isActionJustPressed(_action(a.isEmpty ? null : a[0]))),
        'axis' => _fn(name, (a) => Input.getAxis(arg<String>(a, 0, 'axis').toLowerCase())),
        'move' => Vector2(Input.getAxis('horizontal'), -Input.getAxis('vertical')),
        'mouse' => InputManager.instance.mouseWorldPosition.clone(),
        'click' => Input.isMouseButtonJustPressed(0),
        'rightClick' => Input.isMouseButtonJustPressed(2),
        'player' => _fn(name, (a) => PlayerControls.of(arg<num>(a, 0, 'player number').round() - 1)),
        'pad' => _fn(name, (a) => _Pad(arg<num>(a, 0, 'pad number').round() - 1)),
        'pads' => GamepadInput.instance.pads.length,
        'rightDown' => Input.isMouseButtonPressed(2),
        'dragStart' => InputManager.instance.dragStart.clone(),
        'mouseDown' => Input.isMouseButtonPressed(0),
        'mouseReleased' => Input.isMouseButtonJustReleased(0),
        'mouseDelta' => Input.mouseDelta.clone(),
        'mouseLocked' => MouseLock.locked,
        'lockMouse' => _fn(name, (a) {
            final on = optArg<bool>(a, 0, 'on', true);
            MouseLock.wanted = on;
            if (!on) MouseLock.unlock();
            return null;
          }),
        _ => missing,
      };
}

/// `Physics.gravity`, `Physics.raycast(a, b)`, `Physics.explode(...)`.
class PhysicsApi {
  const PhysicsApi();
}

class _PhysicsHost extends HostType {
  @override
  String get typeName => 'Physics';
  @override
  bool matches(Object v) => v is PhysicsApi;

  RigidWorld2D get _world => RigidWorld2D.obtain(_scene);

  @override
  Object? getMember(Object obj, String name) => switch (name) {
        'gravity' => _world.gravity,
        'settled' => _world.settled,
        'moving' => _world.awakeCount,
        'raycast' => _fn(name, (a) {
            if (a.isNotEmpty && _is3DPoint(a[0])) {
              final from = _vec3(a[0], 'from'), to = _vec3(a.length > 1 ? a[1] : null, 'to');
              final ignore = a.length > 2 && a[2] is EmberEntity ? a[2] as EmberEntity : (a[0] is EmberEntity ? a[0] as EmberEntity : null);
              final d = to - from;
              if (d.length2 == 0) return null;
              return PhysicsWorld3D.raycast(scene: _scene, origin: from, direction: d, maxDistance: d.length, ignoreEntity: ignore);
            }
            return _world.raycast(_vec(a.isEmpty ? null : a[0], 'from'), _vec(a.length > 1 ? a[1] : null, 'to'));
          }),
        'lineOfSight' => _fn(name, (a) {
            final from = _vec3(a.isEmpty ? null : a[0], 'from'), to = _vec3(a.length > 1 ? a[1] : null, 'to');
            final d = to - from;
            if (d.length2 == 0) return true;
            final ignore = a.length > 2 && a[2] is EmberEntity ? a[2] as EmberEntity : (a[0] is EmberEntity ? a[0] as EmberEntity : null);
            final hit = PhysicsWorld3D.raycast(scene: _scene, origin: from, direction: d, maxDistance: d.length, ignoreEntity: ignore);
            return hit == null || (a.length > 1 && identical(hit.entity, a[1]));
          }),
        'entitiesAt' => _fn(name, (a) => _world.entitiesAt(_point(a, 0, 'point'))),
        'explode' => _fn(name, (a) {
            final at = _point(a, 0, 'center');
            final i = a.isNotEmpty && a[0] is num ? 2 : 1;
            final pushed = _world.explode(at, optArg<num>(a, i, 'radius', 120).toDouble(), optArg<num>(a, i + 1, 'strength', 800).toDouble());
            return [for (final (e, _) in pushed) e];
          }),
        _ => missing,
      };

  @override
  bool setMember(Object obj, String name, Object? value) {
    if (name != 'gravity') return false;
    _world.gravity = _vec(value, 'gravity');
    return true;
  }
}

class _RayHitHost extends HostType {
  @override
  String get typeName => 'RayHit';
  @override
  bool matches(Object v) => v is RayHit2D;
  @override
  String describe(Object obj) => 'RayHit(${(obj as RayHit2D).entity.name})';
  @override
  Object? getMember(Object obj, String name) {
    final h = obj as RayHit2D;
    return switch (name) {
      'entity' => h.entity,
      'point' => h.point.clone(),
      'normal' => h.normal.clone(),
      'fraction' => h.fraction,
      _ => missing,
    };
  }
}

class _RayHit3DHost extends HostType {
  @override
  String get typeName => 'RayHit3D';
  @override
  bool matches(Object v) => v is RaycastHit3D;
  @override
  String describe(Object obj) => 'RayHit3D(${(obj as RaycastHit3D).entity.name})';
  @override
  Object? getMember(Object obj, String name) {
    final h = obj as RaycastHit3D;
    return switch (name) {
      'entity' => h.entity,
      'point' => h.point.clone(),
      'normal' => h.normal.clone(),
      'distance' => h.distance,
      _ => missing,
    };
  }
}

/// `Game.timeScale`, `Game.level`, ...
class GameApi {
  const GameApi();
}

GamepadButton _padButton(Object? name) {
  final want = '$name'.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
  const aliases = {'lb': 'leftbumper', 'rb': 'rightbumper', 'lt': 'lefttrigger', 'rt': 'righttrigger', 'up': 'dpadup', 'down': 'dpaddown',
    'left': 'dpadleft', 'right': 'dpadright', 'select': 'back', 'l3': 'leftstick', 'r3': 'rightstick'};
  final n = aliases[want] ?? want;
  for (final b in GamepadButton.values) {
    if (b.name.toLowerCase() == n) return b;
  }
  throw ScriptArgumentError('unknown gamepad button "$name" (try "a", "b", "x", "y", "lb", "rb", "start", "up")');
}

class _Pad {
  final int index;
  const _Pad(this.index);
}

class _PadHost extends HostType {
  @override
  String get typeName => 'Pad';
  @override
  bool matches(Object v) => v is _Pad;
  @override
  List<String> memberNames(Object obj) => const ['connected', 'button', 'pressed', 'released', 'stick', 'rightStick', 'trigger'];
  @override
  Object? getMember(Object obj, String name) {
    final i = (obj as _Pad).index;
    final g = GamepadInput.instance;
    return switch (name) {
      'connected' => g.connected(i),
      'button' => _fn(name, (a) => g.isDown(i, _padButton(a.isEmpty ? null : a[0]))),
      'pressed' => _fn(name, (a) => g.justPressed(i, _padButton(a.isEmpty ? null : a[0]))),
      'released' => _fn(name, (a) => g.justReleased(i, _padButton(a.isEmpty ? null : a[0]))),
      'stick' => g.stick(i),
      'rightStick' => g.stick(i, right: true),
      'trigger' => _fn(name, (a) => g.axis(i, '${a.isEmpty ? 'right' : a[0]}' == 'left' ? GamepadAxis.leftTrigger : GamepadAxis.rightTrigger)),
      _ => missing,
    };
  }
}

/// Input.player(n): a player's half of the keyboard plus their gamepad.
class _PlayerHost extends HostType {
  @override
  String get typeName => 'Player';
  @override
  bool matches(Object v) => v is PlayerControls;
  @override
  List<String> memberNames(Object obj) => const ['move', 'key', 'pressed', 'released', 'buffered', 'motion', 'usingPad', 'number'];
  @override
  Object? getMember(Object obj, String name) {
    final p = obj as PlayerControls;
    String action(List<Object?> a) {
      final s = arg<String>(a, 0, 'action');
      if (!PlayerControls.actions.contains(s)) throw ScriptArgumentError('unknown action "$s" (${PlayerControls.actions.join(', ')})');
      return s;
    }

    return switch (name) {
      'move' => p.move,
      'number' => p.index + 1,
      'usingPad' => p.usingPad,
      'key' => _fn(name, (a) => p.down(action(a))),
      'pressed' => _fn(name, (a) => p.pressed(action(a))),
      'released' => _fn(name, (a) => p.released(action(a))),
      'buffered' => _fn(name, (a) => p.buffered(action(a), frames: optArg<num>(a, 1, 'frames', 6).round())),
      'motion' => _fnN(name, (a, n) => p.motion(arg<String>(a, 0, 'directions'), action([a.length > 1 ? a[1] : null]),
          facingRight: n['facingRight'] as bool? ?? true, window: (n['window'] as num?)?.round() ?? 20)),
      _ => missing,
    };
  }
}

/// `Music.time`, `Music.pause()`: the music clock for rhythm games.
class MusicApi {
  const MusicApi();
}

class _MusicHost extends HostType {
  @override
  String get typeName => 'Music';
  @override
  bool matches(Object v) => v is MusicApi;
  @override
  List<String> memberNames(Object obj) => const ['time', 'playing', 'paused', 'ended', 'offset', 'pause', 'resume', 'stop'];
  @override
  Object? getMember(Object obj, String name) {
    final a = AudioSystem.instance;
    return switch (name) {
      'time' => a.musicTime,
      'playing' => a.musicPlaying,
      'paused' => a.musicPaused,
      'ended' => a.musicEnded,
      'offset' => a.musicOffset,
      'pause' => _fn(name, (_) {
          a.pauseMusic();
          return null;
        }),
      'resume' => _fn(name, (_) {
          a.resumeMusic();
          return null;
        }),
      'stop' => _fn(name, (_) {
          a.stopMusic();
          return null;
        }),
      _ => missing,
    };
  }

  @override
  bool setMember(Object obj, String name, Object? value) {
    if (name != 'offset') return false;
    AudioSystem.instance.musicOffset = value is num ? value.toDouble() : throw ScriptArgumentError('offset should be a number of seconds');
    return true;
  }
}

/// Random(seed): numbers that repeat for the same seed.
class _RandomHost extends HostType {
  @override
  String get typeName => 'Random';
  @override
  bool matches(Object v) => v is SeededRandom;
  @override
  List<String> memberNames(Object obj) => const ['seed', 'next', 'range', 'integer', 'chance', 'pick', 'shuffle'];
  @override
  Object? getMember(Object obj, String name) {
    final r = obj as SeededRandom;
    return switch (name) {
      'seed' => r.seed,
      'next' => _fn(name, (_) => r.next()),
      'range' => _fn(name, (a) => r.range(_num(a, 0, 'min'), _num(a, 1, 'max'))),
      'integer' => _fn(name, (a) => r.integer(arg<num>(a, 0, 'max').round())),
      'chance' => _fn(name, (a) => r.chance(_num(a, 0, 'probability'))),
      'pick' => _fn(name, (a) => r.pick<Object?>(arg<List>(a, 0, 'list'))),
      'shuffle' => _fn(name, (a) {
          r.shuffle(arg<List>(a, 0, 'list'));
          return null;
        }),
      _ => missing,
    };
  }
}

class _GameHost extends HostType {
  @override
  String get typeName => 'Game';
  @override
  bool matches(Object v) => v is GameApi;
  @override
  Object? getMember(Object obj, String name) {
    final engine = EmberEngine.instance;
    return switch (name) {
      'time' => engine.levelTime,
      'dt' => _lib.dt,
      'timeScale' => engine.timeScale,
      'level' => engine.activeScene.name,
      'levels' => engine.levelNames,
      'paused' => engine.timeScale == 0,
      'data' => _lib.gameData,
      'dialogueOpen' => DialogueSystem.instance.isOpen,
      'today' => () {
          final d = DateTime.now();
          return d.year * 10000 + d.month * 100 + d.day;
        }(),
      _ => missing,
    };
  }

  @override
  bool setMember(Object obj, String name, Object? value) {
    final engine = EmberEngine.instance;
    switch (name) {
      case 'timeScale':
        engine.timeScale = value is num ? value.toDouble().clamp(0, 10).toDouble() : throw ScriptArgumentError('timeScale should be a number');
      case 'paused':
        engine.timeScale = value == true ? 0 : 1;
      default:
        return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Spawning

/// 2D entities whose box (hitbox, else Transform 2D box) contains a point,
/// top-most first (highest layer, then the one added last). Args: (point, tag?).
List<EmberEntity> _pickAll(List<Object?> a) {
  final p = _point(a, 0, 'point');
  final tagIndex = a.isNotEmpty && a[0] is num ? 2 : 1;
  final tag = tagIndex < a.length && a[tagIndex] is String ? a[tagIndex] as String : null;
  final hits = <(EmberEntity, int, int)>[];
  var order = 0;
  for (final e in _scene.allEntities) {
    order++;
    if (!e.activeInHierarchy || (tag != null && !e.tags.contains(tag))) continue;
    final t = e.getComponent<Transform2DComponent>();
    if (t == null) continue;
    if (Combat.bodyOf(e).contains(Offset(p.x, p.y))) hits.add((e, t.zIndex, order));
  }
  hits.sort((x, y) => x.$2 != y.$2 ? y.$2.compareTo(x.$2) : y.$3.compareTo(x.$3));
  return [for (final h in hits) h.$1];
}

/// Copies [template] (e.g. a disabled "Bullet" entity used as a prefab) into the scene.
EmberEntity spawnCopy(EmberEntity template, Object? at) {
  final copy = template.clone();
  // Spawned copies keep the template's names (scripts compare other.name), unlike Ctrl+D copies
  void rename(EmberEntity from, EmberEntity to) {
    to.name = from.name;
    for (var i = 0; i < from.children.length && i < to.children.length; i++) {
      rename(from.children[i], to.children[i]);
    }
  }

  rename(template, copy);
  copy.enabled = true;
  final t = copy.getComponent<Transform2DComponent>();
  if (at is Vector2 && t != null) t.position = at;
  final t3 = copy.getComponent<Transform3DComponent>();
  if (at is Vector3 && t3 != null) t3.position = at.clone();
  if (at is Vector2 && t3 != null) t3.position = Vector3(at.x, at.y, t3.position.z);
  _scene.addEntity(copy);
  return copy;
}

// ---------------------------------------------------------------------------
// Registration

bool _registered = false;

void registerScriptApi() {
  if (_registered) return;
  _registered = true;
  Interpreter.hostTypes.addAll([
    _Vec2Host(), _Vec3Host(), _RandomHost(), _MusicHost(), _PadHost(), _PlayerHost(), _RayHit3DHost(), _EntityHost(), _ScriptVarsHost(), _TileHitHost(), _RayHitHost(), _InputHost(), _GameHost(), _PhysicsHost(), _ComponentHost(),
  ]);

  final g = Interpreter.globals;
  final rng = math.Random();

  // --- Basics
  g['print'] = _fn('print', (a) {
    _lib.print(a.map(Interpreter.stringify).join(' '));
    return null;
  });
  g['warn'] = _fn('warn', (a) {
    EmberEngine.instance.log(a.map(Interpreter.stringify).join(' '), severity: LogSeverity.warning, source: _lib.current?.file ?? 'Script');
    return null;
  });
  g['vec3'] = _fn('vec3', (a) => Vector3(optArg<num>(a, 0, 'x', 0).toDouble(), optArg<num>(a, 1, 'y', 0).toDouble(), optArg<num>(a, 2, 'z', 0).toDouble()));
  g['vec'] = _fn('vec', (a) => Vector2(optArg<num>(a, 0, 'x', 0).toDouble(), optArg<num>(a, 1, 'y', 0).toDouble()));
  g['Input'] = const InputApi();
  g['Game'] = const GameApi();
  g['Music'] = const MusicApi();
  g['readText'] = _fn('readText', (a) => _lib.text(arg<String>(a, 0, 'file name')));
  g['Physics'] = const PhysicsApi();

  // --- Math
  g['pi'] = math.pi;
  g['random'] = _fn('random', (_) => rng.nextDouble());
  g['randomRange'] = _fn('randomRange', (a) {
    final lo = _num(a, 0, 'min'), hi = _num(a, 1, 'max');
    return lo + rng.nextDouble() * (hi - lo);
  });
  g['randomInt'] = _fn('randomInt', (a) {
    final n = arg<int>(a, 0, 'max');
    if (n <= 0) throw ScriptArgumentError('max must be at least 1');
    return rng.nextInt(n);
  });
  g['chance'] = _fn('chance', (a) => rng.nextDouble() < _num(a, 0, 'probability'));
  g['abs'] = _fn('abs', (a) => arg<num>(a, 0, 'x').abs());
  g['min'] = _fn('min', (a) => math.min(arg<num>(a, 0, 'a'), arg<num>(a, 1, 'b')));
  g['max'] = _fn('max', (a) => math.max(arg<num>(a, 0, 'a'), arg<num>(a, 1, 'b')));
  g['clamp'] = _fn('clamp', (a) => arg<num>(a, 0, 'x').clamp(arg<num>(a, 1, 'min'), arg<num>(a, 2, 'max')));
  g['lerp'] = _fn('lerp', (a) {
    final t = _num(a, 2, 't');
    if (a[0] is Vector2) return _vec(a[0], 'a') + (_vec(a[1], 'b') - _vec(a[0], 'a')) * t;
    return _num(a, 0, 'a') + (_num(a, 1, 'b') - _num(a, 0, 'a')) * t;
  });
  g['sqrt'] = _fn('sqrt', (a) => math.sqrt(_num(a, 0, 'x')));
  g['pow'] = _fn('pow', (a) => math.pow(arg<num>(a, 0, 'x'), arg<num>(a, 1, 'exponent')));
  g['sin'] = _fn('sin', (a) => math.sin(_num(a, 0, 'radians')));
  g['cos'] = _fn('cos', (a) => math.cos(_num(a, 0, 'radians')));
  g['atan2'] = _fn('atan2', (a) => math.atan2(_num(a, 0, 'y'), _num(a, 1, 'x')));
  g['Random'] = _fn('Random', (a) => SeededRandom(optArg<num>(a, 0, 'seed', DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF).round()));
  g['noise'] = _fn('noise', (a) => Noise2D.at(_num(a, 0, 'x'), _num(a, 1, 'y'), optArg<num>(a, 2, 'seed', 0).round()));
  g['smoothNoise'] = _fn('smoothNoise', (a) => Noise2D.fractal(_num(a, 0, 'x'), _num(a, 1, 'y'), seed: optArg<num>(a, 2, 'seed', 0).round()));
  g['snap'] = _fn('snap', (a) {
    final p = _vec(a.isEmpty ? null : a[0], 'point');
    final cell = optArg<num>(a, 1, 'cell size', 32).toDouble();
    if (cell <= 0) throw ScriptArgumentError('cell size should be more than 0');
    return Vector2((p.x / cell).floor() * cell + cell / 2, (p.y / cell).floor() * cell + cell / 2);
  });
  g['angleTo'] = _fn('angleTo', (a) {
    final from = _vec(a.isEmpty ? null : a[0], 'from');
    final to = _vec(a.length > 1 ? a[1] : null, 'to');
    return math.atan2(to.y - from.y, to.x - from.x) * 180 / math.pi;
  });
  g['floor'] = _fn('floor', (a) => arg<num>(a, 0, 'x').floor());
  g['round'] = _fn('round', (a) => arg<num>(a, 0, 'x').round());
  g['sign'] = _fn('sign', (a) => arg<num>(a, 0, 'x').sign);
  g['degrees'] = _fn('degrees', (a) => _num(a, 0, 'radians') * 180 / math.pi);
  g['radians'] = _fn('radians', (a) => _num(a, 0, 'degrees') * math.pi / 180);

  // --- Scene
  g['find'] = _fn('find', (a) {
    // A live entity first: a hidden template of the same name comes last
    final name = arg<String>(a, 0, 'name');
    EmberEntity? hidden;
    for (final e in _scene.allEntities) {
      if (e.name != name) continue;
      if (e.enabled) return e;
      hidden ??= e;
    }
    return hidden;
  });
  g['findAll'] = _fn('findAll', (a) {
    final tag = arg<String>(a, 0, 'tag');
    return [for (final e in _scene.allEntities) if (e.enabled && e.tags.contains(tag)) e];
  });
  g['pick'] = _fn('pick', (a) {
    final hits = _pickAll(a);
    return hits.isEmpty ? null : hits.first;
  });
  g['pickAll'] = _fn('pickAll', _pickAll);
  g['findInBox'] = _fn('findInBox', (a) {
    final tag = arg<String>(a, 0, 'tag');
    final p = _vec(a.length > 1 ? a[1] : null, 'corner');
    final q = _vec(a.length > 2 ? a[2] : null, 'corner');
    final box = Rect.fromPoints(Offset(p.x, p.y), Offset(q.x, q.y));
    return [
      for (final e in _scene.allEntities)
        if (e.enabled && e.tags.contains(tag) && box.contains(Combat.bodyOf(e).center)) e,
    ];
  });
  g['findInRange'] = _fn('findInRange', (a) {
    final tag = arg<String>(a, 0, 'tag');
    final from = _vec(a.length > 1 ? a[1] : null, 'point');
    final radius = _num(a, 2, 'radius');
    final found = <(EmberEntity, double)>[];
    for (final e in _scene.allEntities) {
      if (!e.enabled || !e.tags.contains(tag)) continue;
      final d = _center(e).distanceTo(from);
      if (d <= radius) found.add((e, d));
    }
    found.sort((x, y) => x.$2.compareTo(y.$2));
    return [for (final (e, _) in found) e];
  });
  g['findNearest'] = _fn('findNearest', (a) {
    final tag = arg<String>(a, 0, 'tag');
    final from = a.length > 1 ? _point(a, 1, 'from') : (_self == null ? Vector2.zero() : _center(_self!));
    EmberEntity? best;
    var bestD = double.infinity;
    for (final e in _scene.allEntities) {
      if (!e.enabled || !e.tags.contains(tag) || identical(e, _self)) continue;
      final d = _center(e).distanceTo(from);
      if (d < bestD) {
        bestD = d;
        best = e;
      }
    }
    return best;
  });
  g['spawn'] = _fn('spawn', (a) {
    final template = _entity(a.isEmpty ? null : a[0], 'template');
    return spawnCopy(template, _spawnAt(a, 1));
  });
  g['destroy'] = _fn('destroy', (a) {
    final e = a.isEmpty || a[0] == null ? _self : _entity(a[0], 'entity');
    if (e != null) e.scene?.destroyLater(e);
    return null;
  });
  g['solidAt'] = _fn('solidAt', (a) {
    final p = _point(a, 0, 'point');
    final size = optArg<num>(a, a.isNotEmpty && a[0] is num ? 2 : 1, 'size', 4).toDouble();
    return TileCollision.blocked(_scene, Rect.fromCenter(center: Offset(p.x, p.y), width: size, height: size));
  });
  g['strike'] = _fnN('strike', (a, n) {
    final at = _point(a, 0, 'center');
    final w = a.isNotEmpty && a[0] is num ? 2 : 1;
    final width = optArg<num>(a, w, 'width', 32).toDouble(), height = optArg<num>(a, w + 1, 'height', width).toDouble();
    final self = _self;
    final team = n['team'] as String? ?? self?.getComponent<HealthComponent>()?.team ?? 'player';
    final hits = Combat.strike(
      _scene,
      Rect.fromCenter(center: Offset(at.x, at.y), width: width, height: height),
      team: team,
      damage: (n['damage'] as num?)?.toDouble() ?? 1,
      source: self,
      knockback: (n['knockback'] as num?)?.toDouble() ?? 150,
    );
    return hits;
  });

  // --- Levels, time, UI
  g['loadLevel'] = _fn('loadLevel', (a) {
    final name = arg<String>(a, 0, 'scene name');
    final spawnAt = a.length > 1 ? arg<String>(a, 1, 'spawn point') : null;
    if (!EmberEngine.instance.levelNames.contains(name)) throw ScriptArgumentError('no scene called "$name" (scenes: ${EmberEngine.instance.levelNames.join(', ')})');
    Doors.travel(name, spawnAt: spawnAt);
    return null;
  });
  g['restart'] = _fn('restart', (_) {
    EmberEngine.instance.restartScene();
    return null;
  });
  g['after'] = _fn('after', (a) {
    final behavior = _lib.current;
    final fn = a.length > 1 ? a[1] : null;
    EmberTween.delay(_num(a, 0, 'seconds'), () => _lib.callLater(behavior, fn, const []));
    return null;
  });
  g['every'] = _fn('every', (a) {
    final behavior = _lib.current;
    final seconds = _num(a, 0, 'seconds');
    if (seconds <= 0) throw ScriptArgumentError('seconds must be more than 0');
    final fn = a.length > 1 ? a[1] : null;
    final handle = _Timer();
    void schedule() {
      EmberTween.delay(seconds, () {
        if (handle.stopped || (behavior != null && !behavior.alive)) return;
        if (_lib.callLater(behavior, fn, const []) == false) return; // return false to stop
        schedule();
      });
    }

    schedule();
    return _fn('stop', (_) {
      handle.stopped = true;
      return null;
    });
  });
  g['tween'] = _fnN('tween', (a, n) {
    final behavior = _lib.current;
    final fn = a.length > 1 ? a[1] : null;
    final ease = switch ('${n['ease'] ?? 'inOut'}') {
      'linear' => Ease.linear,
      'in' => Ease.inQuad,
      'out' => Ease.outQuad,
      'back' => Ease.outBack,
      _ => Ease.inOutQuad,
    };
    final done = n['then'];
    EmberTween.run(_num(a, 0, 'seconds'), (t) => _lib.callLater(behavior, fn, [t]), ease: ease,
        onComplete: done == null ? null : () => _lib.callLater(behavior, done, const []));
    return null;
  });
  g['say'] = _fn('say', (a) {
    final behavior = _lib.current;
    final done = a.length > 1 ? a[1] : null;
    DialogueSystem.instance.start(DialogueSystem.parse(arg<String>(a, 0, 'text')),
        onFinished: done == null ? null : () => _lib.callLater(behavior, done, const []));
    return null;
  });
  g['setText'] = _fn('setText', (a) {
    final e = _entity(a.isEmpty ? null : a[0], 'entity');
    final c = findComponent(e, 'UI Text') ?? findComponent(e, 'UI Button');
    if (c == null) throw ScriptArgumentError('${e.name} has no UI Text');
    _ComponentHost._property(c, 'text')?.setValue(a.length > 1 ? Interpreter.stringify(a[1]) : '');
    return null;
  });

  // --- Sound
  g['playSound'] = _fnN('playSound', (a, n) {
    final clip = arg<String>(a, 0, 'sound');
    final volume = (n['volume'] as num?)?.toDouble() ?? optArg<num>(a, 1, 'volume', 1).toDouble();
    final pitch = (n['pitch'] as num?)?.toDouble() ?? 1.0;
    if (clip.contains('.')) {
      AudioSystem.instance.play(clip: clip, volume: volume, pitch: pitch);
    } else {
      AudioSystem.instance.playProcedural(clip, volume: volume, pitch: pitch);
    }
    return null;
  });
  g['playMusic'] = _fnN('playMusic', (a, n) {
    AudioSystem.instance.playMusic(arg<String>(a, 0, 'music file'),
        volume: (n['volume'] as num?)?.toDouble() ?? optArg<num>(a, 1, 'volume', 0.6).toDouble(), loop: n['loop'] as bool? ?? true);
    return null;
  });
  g['stopMusic'] = _fn('stopMusic', (_) {
    AudioSystem.instance.stopMusic();
    return null;
  });

  // --- Saving
  g['saveValue'] = _fn('saveValue', (a) {
    final key = arg<String>(a, 0, 'key');
    final v = a.length > 1 ? a[1] : null;
    switch (v) {
      case int():
        SaveData.instance.setInt(key, v);
      case double():
        SaveData.instance.setDouble(key, v);
      case bool():
        SaveData.instance.setBool(key, v);
      case String():
        SaveData.instance.setString(key, v);
      case Map():
        SaveData.instance.setMap(key, v.map((k, x) => MapEntry('$k', x)));
      default:
        throw ScriptArgumentError('only numbers, text, true/false and maps can be saved');
    }
    return null;
  });
  g['deleteValue'] = _fn('deleteValue', (a) {
    SaveData.instance.remove(arg<String>(a, 0, 'key'));
    return null;
  });
  g['loadValue'] = _fn('loadValue', (a) {
    final key = arg<String>(a, 0, 'key');
    final fallback = a.length > 1 ? a[1] : null;
    if (!SaveData.instance.has(key)) return fallback;
    return switch (fallback) {
      // double first: on the web a whole-number fallback is also a double
      double() when Interpreter.webNumbers => SaveData.instance.getDouble(key, defaultValue: fallback),
      int() => SaveData.instance.getInt(key, defaultValue: fallback),
      double() => SaveData.instance.getDouble(key, defaultValue: fallback),
      bool() => SaveData.instance.getBool(key, defaultValue: fallback),
      String() => SaveData.instance.getString(key, defaultValue: fallback),
      _ => SaveData.instance.getMap(key) ?? SaveData.instance.getString(key),
    };
  });

  _registerDocs();
}

class _Timer {
  bool stopped = false;
}

// ---------------------------------------------------------------------------
// Reference docs

void _registerDocs() {
  ScriptApi._add('', 'Events', [
    ('onStart()', 'Runs once when the game starts (or when the entity is spawned).'),
    ('onUpdate(dt)', 'Runs every frame. dt = seconds since the last frame (about 0.016).'),
    ('onFixedUpdate(dt)', 'Runs at a fixed 60 steps per second — steady physics.'),
    ('onDestroy()', 'Runs when the entity is removed.'),
    ('onTriggerEnter(other)', 'This entity\'s hitbox started touching [other] (a non-solid hitbox).'),
    ('onTriggerExit(other)', 'Stopped touching [other].'),
    ('onCollisionEnter(other)', 'Two solid hitboxes (or rigid bodies) started touching.'),
    ('onHit(other, impulse, speed)', 'This Rigid Body 2D struck something (or was struck) at its Hit Speed or faster. impulse ≈ mass × speed: use it for damage.'),
    ('onJointBreak(joint)', 'A Joint 2D on this entity snapped (its Break Force was exceeded).'),
    ('onDamaged(amount, source)', 'This entity\'s Health lost [amount] (source may be null).'),
    ('onDeath(killer)', 'This entity\'s Health reached 0.'),
    ('onKill(victim)', 'This entity (or its projectile) killed [victim] — award XP here.'),
    ('onInteract(by)', 'The player pressed E next to this entity.'),
    ('onUIAction(action)', 'A UI Button with this action was clicked (every script receives it).'),
    ('onHeadBump(tile)', 'Platformer hero hit a tile with its head (tile.set(0) breaks it).'),
    ('onTileTouch(tile)', 'Touching a hazard tile (spikes, lava).'),
    ('onBulletHit(position, victim, frame)', "A bullet from this entity's Bullet Pool hit something (play effects here)."),
    ('onGraze()', 'An enemy bullet just missed this entity (its pool has a Graze Radius).'),
    ('onRoomEnter(room)', 'The camera follows this entity into another Camera Room 2D.'),
    ('onAirJump() / onWallJump() / onDash()', 'Platformer: an ability was just used (effects and sounds).'),
    ('onPathEnd()', "This entity's Path Follower reached the end of its path."),
  ], callbacks: true);

  ScriptApi._add('', 'Basics', [
    ('self', 'The entity this script is on.'),
    ('print(value, ...)', 'Writes to the Console.'),
    ('warn(value, ...)', 'Writes a warning to the Console.'),
    ('vec(x, y)', 'A 2D vector / point, e.g. vec(100, 50). Add, subtract, multiply by numbers.'),
    ('vec3(x, y, z)', 'A 3D vector / point, e.g. vec3(0, 1, -5). Add, subtract, multiply by numbers.'),
    ('Input', 'Keyboard, mouse and actions — see Input.'),
    ('Game', 'Time, time scale and the current level — see Game.'),
    ('Music', 'The music clock for rhythm games: Music.time (seconds heard), playing, ended, offset (calibration), pause(), resume(), stop().'),
    ('readText(file)', 'The text of a file in the Script workspace (charts, level lists, dialogue).'),
    ('Physics', 'Gravity, raycasts and explosions (2D), raycasts and line of sight (3D) — see Physics.'),
  ]);
  ScriptApi._add('', 'Math', [
    ('random()', 'A random number from 0 to 1.'),
    ('randomRange(min, max)', 'A random number between min and max.'),
    ('randomInt(max)', 'A random whole number from 0 to max - 1.'),
    ('chance(probability)', 'true with this probability, e.g. chance(0.25) is true 1 time in 4.'),
    ('abs(x)', 'Distance from zero.'),
    ('min(a, b)', 'The smaller number.'),
    ('max(a, b)', 'The larger number.'),
    ('clamp(x, min, max)', 'x kept between min and max.'),
    ('lerp(a, b, t)', 'Blend from a to b (t = 0..1). Works on numbers and vectors.'),
    ('sqrt(x)', 'Square root.'),
    ('pow(x, exponent)', 'x to a power.'),
    ('sin(radians)', 'Sine.'),
    ('cos(radians)', 'Cosine.'),
    ('atan2(y, x)', 'Angle of a direction, in radians.'),
    ('angleTo(from, to)', 'Angle in degrees from one point (or entity) to another: aim bullets with it.'),
    ('Random(seed)', 'Random numbers that repeat for the same seed: r.next(), r.range(a, b), r.integer(n), r.chance(p), r.pick(list), r.shuffle(list).'),
    ('noise(x, y, seed)', 'Smooth noise from 0 to 1 (terrain, caves, wobble); smoothNoise adds finer detail.'),
    ('snap(point, cell)', 'The centre of the grid cell a point is in, e.g. snap(Input.mouse, 40): build grids.'),
    ('floor(x)', 'Round down.'),
    ('round(x)', 'Round to the nearest whole number.'),
    ('sign(x)', '-1, 0 or 1.'),
    ('degrees(radians)', 'Radians to degrees.'),
    ('radians(degrees)', 'Degrees to radians.'),
    ('pi', '3.14159…'),
  ]);
  ScriptApi._add('', 'Scene', [
    ('find(name)', 'The entity with this name, or null (a visible one first, so spawned copies win over their hidden template).'),
    ('findAll(tag)', 'All enabled entities with this tag.'),
    ('findNearest(tag)', 'The closest entity with this tag (optionally findNearest(tag, from)).'),
    ('findInBox(tag, corner, corner)', 'Entities with this tag whose centre is inside the box (drag-selecting units).'),
    ('findInRange(tag, point, radius)', 'Entities with this tag within radius of a point, nearest first (tower targets, area spells).'),
    ('pick(point, tag)', '2D: the top-most entity under a point (e.g. pick(Input.mouse, "card")), or null.'),
    ('pickAll(point, tag)', '2D: every entity under a point, top-most first.'),
    ('solidAt(point)', 'true if a solid tile covers this point (walls, water, trees). solidAt(x, y, size) checks a square.'),
    ('spawn(template, position)', 'Copies an entity (e.g. a disabled "Bullet" prefab) to a position and returns the copy.'),
    ('destroy(entity)', 'Removes an entity at the end of the frame. destroy() removes self.'),
    ('strike(center, width, height, damage: 1)', 'Damages every enemy with Health in the box (named: damage, team, knockback). Returns who was hit.'),
  ]);
  ScriptApi._add('', 'Game flow', [
    ('loadLevel(name)', 'Fades out and loads another scene (optionally loadLevel(name, "Spawn Point")).'),
    ('restart()', 'Restarts the current scene.'),
    ('after(seconds, () { ... })', 'Runs code once after a delay.'),
    ('every(seconds, () { ... })', 'Runs code repeatedly; returns a stop() function (or return false to stop).'),
    ('tween(seconds, (t) { ... }, ease: "inOut", then: () {...})', 'Animates: calls you with t from 0 to 1. Eases: linear, in, out, inOut, back.'),
    ('say("Name: text")', 'Shows dialogue (one line per \\n); the game pauses until it is read.'),
    ('setText(entity, text)', 'Changes a UI Text (by entity or name).'),
  ]);
  ScriptApi._add('', 'Sound', [
    ('playSound(name, volume)', 'A built-in sound (coin, jump, hit, laser, explosion, click) or an audio file path.'),
    ('playMusic(path, volume)', 'Loops background music.'),
    ('stopMusic()', 'Stops the music.'),
  ]);
  ScriptApi._add('', 'Saving', [
    ('saveValue(key, value)', 'Stores a number, text, bool or map between runs (e.g. best score).'),
    ('loadValue(key, default)', 'Reads a saved value, or default if never saved.'),
    ('deleteValue(key)', 'Forgets a saved value.'),
  ]);

  ScriptApi._add('Entity', 'Entity', [
    ('name', 'The entity\'s name (can be changed).'),
    ('x', 'Horizontal position.'),
    ('y', 'Vertical position (down is positive in 2D).'),
    ('z', 'Depth position (3D).'),
    ('position', 'Position: a Vec2 in 2D, a Vec3 in 3D (relative to its parent).'),
    ('worldPosition', 'Position in the world (after parents).'),
    ('yaw', '3D: turn left/right in degrees (0 faces -Z, 90 faces -X).'),
    ('pitch', '3D: tilt up/down in degrees.'),
    ('roll', '3D: lean sideways in degrees.'),
    ('forward', '3D: unit Vec3 it faces.'),
    ('right', '3D: unit Vec3 to its right.'),
    ('up', '3D: unit Vec3 above it.'),
    ('lookAt(target, level)', '3D: face a point or entity (level = true keeps it upright, the default).'),
    ('turnToward(target, maxDegrees)', '3D: turn at most maxDegrees toward a target; returns the angle still left.'),
    ('center', 'Middle of its hitbox (or box) as a Vec2; can be set.'),
    ('rotation', 'Rotation in radians (2D).'),
    ('layer', '2D draw order: higher layers are drawn on top (and picked first).'),
    ('scale', '2D size multiplier: a number or a Vec2 (1 = normal).'),
    ('width', 'Box width.'),
    ('height', 'Box height.'),
    ('enabled', 'false hides it and stops its scripts.'),
    ('alive', 'false once destroyed.'),
    ('tags', 'Its tags as a list.'),
    ('hasTag(tag)', 'true if it has this tag.'),
    ('addTag(tag)', 'Adds a tag.'),
    ('removeTag(tag)', 'Removes a tag.'),
    ('get(component)', 'A component by type, e.g. self.get("Health"). Shortcut: self.health, self.sprite …'),
    ('has(component)', 'true if it has this component.'),
    ('add(component)', 'Adds a new component by type, e.g. self.add("Health").'),
    ('remove(component)', 'Removes a component.'),
    ('destroy(delay)', 'Removes the entity (optionally after a delay in seconds).'),
    ('distanceTo(other)', 'Distance to another entity or point (Vec2, or Vec3 in 3D).'),
    ('directionTo(other)', 'Unit vector pointing at another entity or point (Vec3 in 3D).'),
    ('moveToward(target, maxDistance)', 'Steps toward a point; returns true when arrived.'),
    ('overlaps(other)', 'true if the hitboxes touch.'),
    ('interact(range)', 'Talks to / uses the nearest entity within range (opens its Dialogue, sends it onInteract). Returns it or null.'),
    ('call(function, args...)', 'Calls a function in this entity\'s Ember Script, e.g. enemy.call("stun", 2).'),
    ('script', 'This entity\'s Ember Script: read or set its variables (enemy.script.speed = 0).'),
    ('clone(position)', 'Copies this entity into the scene.'),
    ('child(name)', 'A child entity by name.'),
    ('children', 'Child entities.'),
    ('parent', 'Parent entity, or null.'),
    ('sprite', 'Its Flame Sprite (frame, flipX, opacity, tint, asset).'),
    ('animator', 'Its Sprite Animator (play("run"), current, finished).'),
    ('health', 'Its Health (health, maxHealth, damage(n), heal(n), dead).'),
    ('mover', 'Its Top-Down Controller (move(dir), velocity, facing, knockback(v)).'),
    ('controller', 'Its Platformer Controller (move(x, jumpHeld, jumpPressed), grounded, bounce()), or in 3D its Character Controller 3D (move(dir), jump(), grounded).'),
    ('mesh', 'Its Mesh Renderer 3D (color, emission, opacity, flash()).'),
    ('enemy', 'Its Enemy AI 3D (target, state, speed, …).'),
    ('story', 'Its Story Player (variable(name), setVariable(name, value), jump(label), label, ended, speaker).'),
    ('hitbox', 'Its Hitbox 2D.'),
    ('particles', 'Its Particle Emitter (burst(20), burst(20, position)).'),
    ('rigidbody', 'Its Rigid Body 2D (velocity, angularVelocity, applyImpulse(v), mass, sleeping).'),
    ('joint', 'Its Joint 2D (broken, force, snap()).'),
    ('line', 'Its Line 2D (points, color, width, clear()).'),
    ('camera', 'Its Camera 2D (zoom, followTarget, shake(amount, seconds)).'),
    ('text', 'Its UI Text (text).'),
    ('ai', 'Its Monster AI (state, sightRange, …).'),
  ]);
  ScriptApi._add('Component', 'Component', [
    ('enabled', 'Turns the component on or off.'),
    ('type', 'Component type name.'),
    ('entity', 'The entity it belongs to.'),
    ('(any Inspector field)', 'Every field shown in the Inspector can be read and set by name, e.g. sprite.flipX, health.maxHealth, text.text.'),
    ('play(clip)', 'Animator: switch clip.'),
    ('damage(amount, source, knockback)', 'Health: take damage. Returns true if it hurt.'),
    ('heal(amount)', 'Health: restore health.'),
    ('move(direction)', 'Top-down: walk toward a Vec2 (length ≤ 1). Platformer: move(horizontal, jumpHeld, jumpPressed).'),
    ('burst(count, position)', 'Particles: emit a burst (optionally at a world position).'),
    ('velocity', 'Rigid body / movers: current velocity in px/s (can be set, even right after spawn()).'),
    ('angularVelocity', 'Rigid body: spin in radians per second.'),
    ('speed', 'Rigid body: how fast it moves (px/s).'),
    ('mass', 'Rigid body: weight in kg (a 32×32 box of density 1 is 1 kg).'),
    ('sleeping', 'Rigid body: true while resting (not simulated until touched).'),
    ('applyImpulse(impulse, point)', 'Rigid body: instant push in kg·px/s (at a world point adds spin).'),
    ('applyForce(force, point)', 'Rigid body: steady push for this physics step (call in onFixedUpdate).'),
    ('wake()', 'Rigid body: wake it up so it simulates again.'),
    ('snap()', 'Joint: break it now.'),
    ('points', 'Line 2D: list of world points to draw through, e.g. [vec(0, 0), vec(100, 40)].'),
    ('shake(amount, seconds)', 'Camera 2D: screen shake (e.g. find("Camera").camera.shake(10, 0.4)).'),
    ('flash(color, seconds)', 'Camera 2D: fill the screen with a colour that fades out (hits, bombs).'),
    ('fire(position, angle, speed)', 'Bullet Pool: one bullet. Angle in degrees (0 right, 90 down). Named: frame, scale, curve (degrees/s), accel, maxSpeed, damage, radius, life, target (homes in), turn (degrees/s), splash (radius).'),
    ('ring(position, count, speed)', 'Bullet Pool: bullets all around (named: offset in degrees, plus those of fire).'),
    ('spread(position, angle, count, arc, speed)', 'Bullet Pool: a fan of bullets over arc degrees around angle.'),
    ('dungeon(seed)', 'TileMap: rooms and corridors (named: rooms, minSize, maxSize, wall, floor, corridor). Returns the rooms, each with col, row, width, height, center.'),
    ('cave(seed)', 'TileMap: natural caves (named: fill, steps, wall, floor).'),
    ('autotile(wall, first)', 'TileMap: turns wall tiles into one of 16 pieces (first + 1 up, 2 right, 4 down, 8 left when the neighbour is wall too).'),
    ('findPath(c0, r0, c1, r1)', 'TileMap: the shortest walk between two cells as a list of [col, row] (null if blocked). block(col, row, true) marks cells (buildings); walkable(col, row). Works on square, isometric and hex maps.'),
    ('getTile(col, row)', 'TileMap: the tile id there (setTile(col, row, id), fill(id), vary(id, [ids], chance), cellAt(point), cellCenter(col, row), cellsWith(id)).'),
    ('slow(factor, seconds)', 'Path Follower: move at factor of its speed for a while (frost towers). Also progress (0..1), distance, remaining, done.'),
    ('distanceTo(point)', 'Line 2D: how far a point is from the line (keep towers off the path).'),
    ('clearAround(position, radius)', 'Bullet Pool: remove bullets near a point (a bomb). Returns how many; clear() removes all.'),
    ('talk()', 'Dialogue: open this character\'s lines.'),
    ('shoot(direction)', 'Monster AI: fire its projectile along a Vec2 (e.g. rings of fireballs).'),
    ('dash()', 'Platformer: dash the way it faces (needs Dash Speed). Also dashing, onWall (-1, 0, 1), airJumpsLeft; Air Jumps and Wall Jump are Inspector fields.'),
    ('explored', 'Minimap: what was explored, as text to save; set it to load. exploredFraction (0..1), revealAll().'),
    ('room', 'Camera 2D: the Camera Room entity the followed entity is in (or null). snapToTarget() jumps straight to the followed entity.'),
    ('groundAt(x, y)', 'Platformer: is there floor at this point? (turn around at ledges)'),
    ('hazardAt(x, y)', 'Platformer: is there a hazard tile at this point?'),
  ]);
  ScriptApi._add('Vec2', 'Vec2', [
    ('x', 'Horizontal part.'),
    ('y', 'Vertical part.'),
    ('length', 'Length of the vector.'),
    ('angle', 'Direction in radians.'),
    ('normalized()', 'Same direction, length 1.'),
    ('distanceTo(other)', 'Distance to another point.'),
    ('dot(other)', 'Dot product.'),
    ('rotated(radians)', 'Turned by an angle.'),
    ('lerp(other, t)', 'Blend toward another vector.'),
    ('withX(x)', 'Copy with a new x.'),
    ('withY(y)', 'Copy with a new y.'),
  ]);
  ScriptApi._add('Input', 'Input', [
    ('key(name)', 'true while a key is held: Input.key("A"), Input.key("Space"), Input.key("Left").'),
    ('pressed(name)', 'true on the frame a key goes down.'),
    ('released(name)', 'true on the frame a key goes up.'),
    ('action(name)', 'Held action: jump, fire (attack), interact, sprint, crouch, left, right, up, down.'),
    ('actionPressed(name)', 'Action went down this frame.'),
    ('axis(name)', '"horizontal" or "vertical": -1 .. 1.'),
    ('move', 'WASD / arrows as a Vec2 (x right, y down).'),
    ('mouse', 'Mouse position in the world.'),
    ('click', 'true on the frame the mouse (or touch) goes down.'),
    ('mouseDown', 'true while the mouse button is held.'),
    ('mouseReleased', 'true on the frame the mouse (or touch) is let go — end of a drag.'),
    ('rightClick', 'true on the frame the right mouse button goes down (rightDown while held).'),
    ('player(n)', 'Player n (1-4): their half of the keyboard and their gamepad. .move (Vec2), .key("attack"), .pressed / .released, .buffered("attack"), .motion("236", "attack", facingRight: true) for fighting moves. Actions: left right up down jump attack special block start.'),
    ('pad(n)', 'Gamepad n (1-4): .connected, .button("a"), .pressed("start"), .released, .stick, .rightStick, .trigger("left"). Pad 1 also works with Input.move and Input.action.'),
    ('dragStart', 'Where the left button went down, in the world (box selection: findInBox(tag, Input.dragStart, Input.mouse)).'),
  ]);
  ScriptApi._add('Physics', 'Physics', [
    ('gravity', 'World gravity as a Vec2 in px/s² (can be set, e.g. vec(0, 300) for the moon).'),
    ('settled', 'true when no rigid body is moving any more.'),
    ('moving', 'How many rigid bodies are still moving.'),
    ('raycast(from, to)', 'The first body on the line: a RayHit (entity, point, normal) or null.'),
    ('entitiesAt(point)', 'Entities whose rigid body covers this point.'),
    ('explode(center, radius, strength)', 'Pushes every body within radius away (strongest at the centre); returns them.'),
    ('raycast(from, to, ignore)', '3D (Vec3 points): the first collider on the line, a RayHit3D (entity, point, normal, distance), or null.'),
    ('lineOfSight(from, to, ignore)', '3D: true if nothing solid is between two points (or the first thing hit is the target entity).'),
  ]);
  ScriptApi._add('Vec3', 'Vec3', [
    ('x', 'Left/right part.'),
    ('y', 'Up/down part.'),
    ('z', 'Forward/back part (-Z is forward).'),
    ('length', 'Length of the vector.'),
    ('flat', 'Copy with y = 0 (along the ground).'),
    ('normalized()', 'Same direction, length 1.'),
    ('distanceTo(other)', 'Distance to another point.'),
    ('dot(other)', 'Dot product.'),
    ('cross(other)', 'Cross product.'),
    ('lerp(other, t)', 'Blend toward another vector.'),
    ('withX(x)', 'Copy with a new x.'),
    ('withY(y)', 'Copy with a new y.'),
    ('withZ(z)', 'Copy with a new z.'),
  ]);
  ScriptApi._add('RayHit3D', 'RayHit3D', [
    ('entity', 'The entity hit.'),
    ('point', 'Where the ray hit (Vec3).'),
    ('normal', 'Surface direction at the hit (Vec3).'),
    ('distance', 'How far from the start.'),
  ]);
  ScriptApi._add('RayHit', 'RayHit', [
    ('entity', 'The entity that was hit.'),
    ('point', 'Where the ray hit (Vec2).'),
    ('normal', 'Direction the hit surface faces.'),
    ('fraction', '0 at the ray start, 1 at its end.'),
  ]);
  ScriptApi._add('Game', 'Game', [
    ('time', 'Seconds since the level started.'),
    ('dt', 'Seconds in the current frame.'),
    ('timeScale', '1 normal speed, 0.5 slow motion, 0 frozen (can be set).'),
    ('paused', 'Set true to freeze game time (menus).'),
    ('level', 'Name of the current scene.'),
    ('levels', 'Names of all scenes.'),
    ('data', 'A map shared by all scripts that survives level changes and restarts: Game.data["lives"] = 3.'),
    ('dialogueOpen', 'true while a dialogue box is showing.'),
    ('today', "Today's date as a number, e.g. 20261018: a seed for daily challenges."),
  ]);
  ScriptApi._add('Tile', 'Tile', [
    ('column', 'Tile column.'),
    ('row', 'Tile row.'),
    ('id', 'Tile id.'),
    ('kind', 'solid, breakable, question, hazard, …'),
    ('x', 'Centre x of the tile (also y, left, top, right, bottom).'),
    ('set(id)', 'Replaces the tile (0 removes it).'),
  ]);
  ScriptApi._add('Text', 'Text & numbers', [
    ('length', 'Number of characters / items.'),
    ('toUpperCase()', 'TEXT.'),
    ('contains(text)', 'true if it contains text.'),
    ('split(separator)', 'Splits into a list.'),
    ('padLeft(width, "0")', '"7".padLeft(3, "0") → "007".'),
    ('toStringAsFixed(digits)', '3.14159.toStringAsFixed(2) → "3.14".'),
    ('round()', 'Nearest whole number.'),
    ('toNumber()', '"42".toNumber() → 42.'),
  ]);
  ScriptApi._add('List', 'Lists & maps', [
    ('add(item)', 'Appends to a list.'),
    ('remove(item)', 'Removes an item.'),
    ('contains(item)', 'true if present.'),
    ('map((x) => ...)', 'A new list with each item transformed.'),
    ('where((x) => ...)', 'Items that match.'),
    ('forEach((x) { ... })', 'Runs code for each item.'),
    ('random()', 'A random item.'),
    ('sort()', 'Sorts in place.'),
    ('keys', 'Map keys.'),
    ('values', 'Map values.'),
  ]);
}

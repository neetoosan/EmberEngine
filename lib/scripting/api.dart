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
import '../core/input.dart';
import '../core/save_data.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../core/transform3d.dart';
import '../core/tween.dart';
import '../subsystems/ai/monster_ai.dart';
import '../subsystems/audio/audio_component.dart';
import '../subsystems/audio/audio_system.dart';
import '../subsystems/combat/combat.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/physics/character_controller2d.dart';
import '../subsystems/two_d/door.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/sprite_animator.dart';
import '../subsystems/two_d/top_down_controller.dart';
import '../subsystems/ui/dialogue.dart';
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
  final alias = _componentAliases[want];
  for (final c in e.components) {
    final n = _norm(c.displayName);
    if (n == want || n == alias || (alias == null && n.contains(want))) return c;
  }
  return null;
}

const _componentAliases = {
  'sprite': 'flamesprite',
  'hitbox': 'flamehitbox2d',
  'body': 'flamehitbox2d',
  'tilemap': 'flametilemap2d',
  'controller': 'charactercontroller2d',
  'platformer': 'charactercontroller2d',
  'mover': 'topdowncontroller2d',
  'topdown': 'topdowncontroller2d',
  'ai': 'monsterai',
  'text': 'uitext',
  'bar': 'uibar',
  'button': 'uibutton',
  'image': 'uiimage',
  'audio': 'audiosource',
  'particles': 'particleemitter2d',
  'camera': 'camera2d',
  'animator': 'spriteanimator',
  'transform': 'transform2d',
};

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
        return t2 != null ? t2.position.clone() : Vector2(t3?.position.x ?? 0, t3?.position.y ?? 0);
      case 'center':
        return _center(e);
      case 'rotation':
        return t2?.rotation ?? 0.0;
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
        return _fn(name, (a) => _center(e).distanceTo(_point(a, 0, 'target')));
      case 'directionTo':
        return _fn(name, (a) {
          final d = _point(a, 0, 'target') - _center(e);
          return d.length2 == 0 ? Vector2.zero() : d.normalized();
        });
      case 'moveToward':
        return _fn(name, (a) {
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
        return _fn(name, (a) => spawnCopy(e, a.isEmpty ? null : _point(a, 0, 'position')));
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
        final v = _vec(value, 'position');
        if (t2 != null) t2.position = v;
        if (t3 != null) t3.position = Vector3(v.x, v.y, t3.position.z);
      case 'center':
        final v = _vec(value, 'center');
        if (t2 != null) t2.position = t2.position + (v - _center(e));
      case 'rotation':
        t2?.rotation = n();
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
          source: a.length > 1 && a[1] != null ? _entity(a[1], 'source') : _self,
          knockback: a.length > 2 && a[2] != null ? _vec(a[2], 'knockback') : null,
        )), null),
    'heal': ((c) => c is HealthComponent, (c, n) => _fn(n, (a) {
          (c as HealthComponent).heal(_num(a, 0, 'amount'));
          return null;
        }), null),
    // Top-down movement
    'move': ((c) => c is TopDownController2DComponent || c is CharacterController2DComponent, (c, n) => _fn(n, (a) {
          if (c is TopDownController2DComponent) {
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
    'velocity': ((c) => c is TopDownController2DComponent || c is CharacterController2DComponent,
        (c, _) => c is TopDownController2DComponent ? c.velocity.clone() : (c as CharacterController2DComponent).velocity.clone(),
        (c, v) {
          final vv = _vec(v, 'velocity');
          if (c is TopDownController2DComponent) c.velocity.setFrom(vv);
          if (c is CharacterController2DComponent) c.velocity.setFrom(vv);
        }),
    'facing': ((c) => c is TopDownController2DComponent || c is CharacterController2DComponent,
        (c, _) => c is TopDownController2DComponent ? c.facing.name : ((c as CharacterController2DComponent).facing < 0 ? 'left' : 'right'), null),
    'moving': ((c) => c is TopDownController2DComponent, (c, _) => (c as TopDownController2DComponent).isMoving, null),
    'hitWall': ((c) => c is TopDownController2DComponent || c is CharacterController2DComponent,
        (c, _) => c is TopDownController2DComponent ? c.hitWall : (c as CharacterController2DComponent).hitWall, null),
    'knockback': ((c) => c is TopDownController2DComponent, (c, n) => _fn(n, (a) {
          (c as TopDownController2DComponent).knockback(_point(a, 0, 'impulse'));
          return null;
        }), null),
    // Platformer
    'grounded': ((c) => c is CharacterController2DComponent, (c, _) => (c as CharacterController2DComponent).isGrounded, null),
    'canJump': ((c) => c is CharacterController2DComponent, (c, _) => (c as CharacterController2DComponent).canJump, null),
    'bounce': ((c) => c is CharacterController2DComponent, (c, n) => _fn(n, (a) {
          final cc = c as CharacterController2DComponent;
          cc.bounce(optArg<num>(a, 0, 'strength', cc.jumpVelocity).toDouble());
          return null;
        }), null),
    // Effects & sound
    'burst': ((c) => c is ParticleEmitter2DComponent, (c, n) => _fn(n, (a) {
          (c as ParticleEmitter2DComponent).burst(optArg<num>(a, 0, 'count', 20).round());
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
    'count': ((c) => c is UIImageComponent, (c, _) => (c as UIImageComponent).count, (c, v) => (c as UIImageComponent).count = (v as num).round()),
    'filled': ((c) => c is UIImageComponent, (c, _) => (c as UIImageComponent).filled, (c, v) => (c as UIImageComponent).filled = (v as num).round()),
    // Monster AI
    'state': ((c) => c is MonsterAIComponent, (c, _) => (c as MonsterAIComponent).state.name, null),
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
        'mouseDown' => Input.isMouseButtonPressed(0),
        _ => missing,
      };
}

/// `Game.timeScale`, `Game.level`, ...
class GameApi {
  const GameApi();
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

/// Copies [template] (e.g. a disabled "Bullet" entity used as a prefab) into the scene.
EmberEntity spawnCopy(EmberEntity template, Vector2? at) {
  final copy = template.clone();
  copy.enabled = true;
  final t = copy.getComponent<Transform2DComponent>();
  if (at != null && t != null) t.position = at;
  final t3 = copy.getComponent<Transform3DComponent>();
  if (at != null && t3 != null) t3.position = Vector3(at.x, at.y, t3.position.z);
  _scene.addEntity(copy);
  return copy;
}

// ---------------------------------------------------------------------------
// Registration

bool _registered = false;

void registerScriptApi() {
  if (_registered) return;
  _registered = true;
  Interpreter.hostTypes.addAll([_Vec2Host(), _EntityHost(), _ScriptVarsHost(), _TileHitHost(), _InputHost(), _GameHost(), _ComponentHost()]);

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
  g['vec'] = _fn('vec', (a) => Vector2(optArg<num>(a, 0, 'x', 0).toDouble(), optArg<num>(a, 1, 'y', 0).toDouble()));
  g['Input'] = const InputApi();
  g['Game'] = const GameApi();

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
  g['floor'] = _fn('floor', (a) => arg<num>(a, 0, 'x').floor());
  g['round'] = _fn('round', (a) => arg<num>(a, 0, 'x').round());
  g['sign'] = _fn('sign', (a) => arg<num>(a, 0, 'x').sign);
  g['degrees'] = _fn('degrees', (a) => _num(a, 0, 'radians') * 180 / math.pi);
  g['radians'] = _fn('radians', (a) => _num(a, 0, 'degrees') * math.pi / 180);

  // --- Scene
  g['find'] = _fn('find', (a) => _scene.findByName(arg<String>(a, 0, 'name')));
  g['findAll'] = _fn('findAll', (a) {
    final tag = arg<String>(a, 0, 'tag');
    return [for (final e in _scene.allEntities) if (e.enabled && e.tags.contains(tag)) e];
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
    return spawnCopy(template, a.length > 1 ? _point(a, 1, 'position') : null);
  });
  g['destroy'] = _fn('destroy', (a) {
    final e = a.isEmpty || a[0] == null ? _self : _entity(a[0], 'entity');
    if (e != null) e.scene?.destroyLater(e);
    return null;
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
  g['playMusic'] = _fn('playMusic', (a) {
    AudioSystem.instance.playMusic(arg<String>(a, 0, 'music file'), volume: optArg<num>(a, 1, 'volume', 0.6).toDouble());
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
  g['loadValue'] = _fn('loadValue', (a) {
    final key = arg<String>(a, 0, 'key');
    final fallback = a.length > 1 ? a[1] : null;
    if (!SaveData.instance.has(key)) return fallback;
    return switch (fallback) {
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
    ('onCollisionEnter(other)', 'Two solid hitboxes bumped.'),
    ('onDamaged(amount, source)', 'This entity\'s Health lost [amount] (source may be null).'),
    ('onDeath(killer)', 'This entity\'s Health reached 0.'),
    ('onKill(victim)', 'This entity (or its projectile) killed [victim] — award XP here.'),
    ('onInteract(by)', 'The player pressed E next to this entity.'),
    ('onUIAction(action)', 'A UI Button with this action was clicked (every script receives it).'),
    ('onHeadBump(tile)', 'Platformer hero hit a tile with its head (tile.set(0) breaks it).'),
    ('onTileTouch(tile)', 'Touching a hazard tile (spikes, lava).'),
  ], callbacks: true);

  ScriptApi._add('', 'Basics', [
    ('self', 'The entity this script is on.'),
    ('print(value, ...)', 'Writes to the Console.'),
    ('warn(value, ...)', 'Writes a warning to the Console.'),
    ('vec(x, y)', 'A 2D vector / point, e.g. vec(100, 50). Add, subtract, multiply by numbers.'),
    ('Input', 'Keyboard, mouse and actions — see Input.'),
    ('Game', 'Time, time scale and the current level — see Game.'),
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
    ('floor(x)', 'Round down.'),
    ('round(x)', 'Round to the nearest whole number.'),
    ('sign(x)', '-1, 0 or 1.'),
    ('degrees(radians)', 'Radians to degrees.'),
    ('radians(degrees)', 'Degrees to radians.'),
    ('pi', '3.14159…'),
  ]);
  ScriptApi._add('', 'Scene', [
    ('find(name)', 'The entity with this name, or null.'),
    ('findAll(tag)', 'All enabled entities with this tag.'),
    ('findNearest(tag)', 'The closest entity with this tag (optionally findNearest(tag, from)).'),
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
  ]);

  ScriptApi._add('Entity', 'Entity', [
    ('name', 'The entity\'s name (can be changed).'),
    ('x', 'Horizontal position.'),
    ('y', 'Vertical position (down is positive in 2D).'),
    ('position', 'Position as a Vec2.'),
    ('center', 'Middle of its hitbox (or box) as a Vec2; can be set.'),
    ('rotation', 'Rotation in radians (2D).'),
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
    ('distanceTo(other)', 'Distance to another entity or Vec2.'),
    ('directionTo(other)', 'Unit Vec2 pointing at another entity or Vec2.'),
    ('moveToward(target, maxDistance)', 'Steps toward a point; returns true when arrived.'),
    ('overlaps(other)', 'true if the hitboxes touch.'),
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
    ('controller', 'Its Platformer Controller (move(x, jumpHeld, jumpPressed), grounded, bounce()).'),
    ('hitbox', 'Its Hitbox 2D.'),
    ('particles', 'Its Particle Emitter (burst(20)).'),
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
    ('burst(count)', 'Particles: emit a burst.'),
    ('talk()', 'Dialogue: open this character\'s lines.'),
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
  ]);
  ScriptApi._add('Game', 'Game', [
    ('time', 'Seconds since the level started.'),
    ('dt', 'Seconds in the current frame.'),
    ('timeScale', '1 normal speed, 0.5 slow motion, 0 frozen (can be set).'),
    ('paused', 'Set true to freeze game time (menus).'),
    ('level', 'Name of the current scene.'),
    ('levels', 'Names of all scenes.'),
  ]);
  ScriptApi._add('Tile', 'Tile', [
    ('column', 'Tile column.'),
    ('row', 'Tile row.'),
    ('id', 'Tile id.'),
    ('kind', 'solid, breakable, question, hazard, …'),
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

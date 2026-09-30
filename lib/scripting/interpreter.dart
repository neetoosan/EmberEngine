/// Ember Script tree-walking interpreter.
library;

import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' show Vector2;
import 'ast.dart';
import 'lexer.dart';
import 'parser.dart' show isMultiVar;

/// A function written in Ember Script (top-level, local, or a lambda).
class ScriptFunction {
  final FunctionDecl decl;
  final Scope closure;
  const ScriptFunction(this.decl, this.closure);

  @override
  String toString() => decl.name.isEmpty ? 'Function' : 'Function ${decl.name}';
}

/// A function provided by the engine. Receives positional and named arguments.
class NativeFunction {
  final String name;
  final Object? Function(List<Object?> args, Map<String, Object?> named) fn;
  const NativeFunction(this.name, this.fn);

  @override
  String toString() => 'Function $name';
}

/// Exposes a Dart type to scripts (entities, components, Vec2, Input, ...).
abstract class HostType {
  String get typeName;
  bool matches(Object value);

  /// The value of `obj.name`, or [missing] if there is no such member.
  Object? getMember(Object obj, String name);

  /// Sets `obj.name = value`; returns false if the member can't be set.
  bool setMember(Object obj, String name, Object? value) => false;

  /// Member names, for error hints and autocomplete.
  List<String> memberNames(Object obj) => const [];

  String describe(Object obj) => typeName;
}

/// Returned by [HostType.getMember] when a member doesn't exist.
const Object missing = _Missing();

class _Missing {
  const _Missing();
}

class Scope {
  final Map<String, Object?> vars;
  Set<String>? _finals;
  final Scope? parent;

  /// Set on an instance's root scope.
  final ScriptInstance? instance;

  Scope(this.parent, {Map<String, Object?>? vars, this.instance}) : vars = vars ?? {};

  ScriptInstance? get owner {
    Scope? s = this;
    while (s != null) {
      if (s.instance != null) return s.instance;
      s = s.parent;
    }
    return null;
  }

  void define(String name, Object? value, {bool isFinal = false}) {
    vars[name] = value;
    if (isFinal) (_finals ??= {}).add(name);
  }

  Scope? find(String name) {
    Scope? s = this;
    while (s != null) {
      if (s.vars.containsKey(name)) return s;
      s = s.parent;
    }
    return null;
  }

  bool isFinal(String name) => _finals?.contains(name) ?? false;
}

/// One running copy of a script (e.g. the script on one enemy).
class ScriptInstance {
  Program program;
  late final Scope root;

  /// Script-level values available by name (e.g. `self`).
  final Map<String, Object?> specials;

  ScriptInstance(this.program, {Map<String, Object?>? specials}) : specials = specials ?? {} {
    root = Scope(null, instance: this);
  }

  Map<String, Object?> get fields => root.vars;

  bool hasFunction(String name) => program.functions.containsKey(name);

  ScriptFunction? function(String name) {
    final f = program.functions[name];
    return f == null ? null : ScriptFunction(f, root);
  }
}

enum _Flow { normal, breakLoop, continueLoop, returned }

/// Raised on a script mistake while running.
class ScriptRuntimeError extends ScriptError {
  final String function;
  ScriptRuntimeError(super.message, super.line, super.column, {super.file, this.function = ''});
}

class Interpreter {
  /// Engine functions and objects visible to every script (print, Input, vec, ...).
  static final Map<String, Object?> globals = {};

  /// Bindings for engine types.
  static final List<HostType> hostTypes = [];

  /// Operations one callback may run before it is stopped (infinite-loop guard).
  static int budgetPerCall = 3000000;

  static const int maxDepth = 200;

  int _budget = 0;
  int _depth = 0;
  Object? _returnValue;
  String _file = '';
  String _function = '';

  /// Receives `print(...)` output.
  void Function(String message)? onPrint;

  // --- Entry points ---

  /// Initialises [instance]'s top-level variables (in order).
  void initialize(ScriptInstance instance, {Map<String, Object?> overrides = const {}}) {
    _startCall(instance.program.file, '<variables>');
    for (final f in instance.program.fields) {
      Object? value;
      if (overrides.containsKey(f.name)) {
        value = coerceLike(overrides[f.name], f.literalDefault);
      } else if (f.init != null) {
        value = eval(f.init!, instance.root);
      }
      instance.root.define(f.name, value, isFinal: f.isFinal);
    }
  }

  /// Calls [name] on [instance] if it exists, passing only as many
  /// arguments as the function declares. Returns the result.
  Object? callIfDefined(ScriptInstance instance, String name, [List<Object?> args = const []]) {
    final decl = instance.program.functions[name];
    if (decl == null) return null;
    _startCall(instance.program.file, name);
    final n = math.min(args.length, decl.positionalCount);
    return _callScript(ScriptFunction(decl, instance.root), args.sublist(0, n), const {}, null);
  }

  /// Calls any callable value from engine code (e.g. a tween callback).
  Object? callValue(Object? callee, List<Object?> args, {String file = '', String function = ''}) {
    final outer = _depth == 0;
    if (outer) _startCall(file, function.isEmpty ? 'callback' : function);
    return call(callee, args, const {}, null);
  }

  void _startCall(String file, String function) {
    if (_depth > 0) return; // nested call from a native: keep the budget of the outer call
    _budget = budgetPerCall;
    _file = file;
    _function = function;
  }

  ScriptRuntimeError error(String message, [Node? at]) =>
      ScriptRuntimeError(message, at?.line ?? 0, at?.column ?? 0, file: _file, function: _function);

  void _tick(Node at) {
    if (--_budget < 0) {
      throw error('This script ran too long without finishing (an endless loop?). It was stopped.', at);
    }
  }

  // --- Statements ---

  _Flow _exec(Stmt s, Scope scope) {
    _tick(s);
    switch (s) {
      case ExprStmt():
        eval(s.expr, scope);
        return _Flow.normal;
      case VarStmt():
        if (scope.vars.containsKey(s.name) && scope.instance == null) {
          throw error('"${s.name}" is already declared in this block', s);
        }
        scope.define(s.name, s.init == null ? null : eval(s.init!, scope), isFinal: s.isFinal);
        return _Flow.normal;
      case BlockStmt():
        return _execBlock(s.body, isMultiVar(s) ? scope : Scope(scope));
      case IfStmt():
        if (_truthy(eval(s.condition, scope), s.condition)) return _exec(s.then, Scope(scope));
        if (s.otherwise != null) return _exec(s.otherwise!, Scope(scope));
        return _Flow.normal;
      case WhileStmt():
        if (s.doWhile) {
          do {
            final f = _exec(s.body, Scope(scope));
            if (f == _Flow.breakLoop) break;
            if (f == _Flow.returned) return f;
          } while (_truthy(eval(s.condition, scope), s.condition));
        } else {
          while (_truthy(eval(s.condition, scope), s.condition)) {
            final f = _exec(s.body, Scope(scope));
            if (f == _Flow.breakLoop) break;
            if (f == _Flow.returned) return f;
          }
        }
        return _Flow.normal;
      case ForStmt():
        final loop = Scope(scope);
        if (s.init != null) _exec(s.init!, loop);
        while (s.condition == null || _truthy(eval(s.condition!, loop), s.condition!)) {
          final iteration = Scope(loop);
          final f = _exec(s.body, iteration);
          if (f == _Flow.breakLoop) break;
          if (f == _Flow.returned) return f;
          for (final u in s.updates) {
            eval(u, loop);
          }
          _tick(s);
        }
        return _Flow.normal;
      case ForInStmt():
        final it = eval(s.iterable, scope);
        final Iterable<Object?> items = switch (it) {
          List() => List<Object?>.of(it),
          Map() => List<Object?>.of(it.keys),
          String() => it.split(''),
          Iterable() => List<Object?>.of(it),
          _ => throw error('for-in needs a list, map or string, not ${typeOf(it)}', s.iterable),
        };
        for (final item in items) {
          final iteration = Scope(scope)..define(s.name, item);
          final f = _exec(s.body, iteration);
          if (f == _Flow.breakLoop) break;
          if (f == _Flow.returned) return f;
          _tick(s);
        }
        return _Flow.normal;
      case BreakStmt():
        return _Flow.breakLoop;
      case ContinueStmt():
        return _Flow.continueLoop;
      case ReturnStmt():
        _returnValue = s.value == null ? null : eval(s.value!, scope);
        return _Flow.returned;
      case FunctionStmt():
        scope.define(s.function.name, ScriptFunction(s.function, scope));
        return _Flow.normal;
      default:
        throw error('Unknown statement', s);
    }
  }

  _Flow _execBlock(List<Stmt> body, Scope scope) {
    for (final st in body) {
      final f = _exec(st, scope);
      if (f != _Flow.normal) return f;
    }
    return _Flow.normal;
  }

  bool _truthy(Object? v, Node at) {
    if (v is bool) return v;
    if (v == null) return false;
    throw error('A condition must be true or false, but this is ${describe(v)}', at);
  }

  // --- Expressions ---

  Object? eval(Expr e, Scope scope) {
    switch (e) {
      case LiteralExpr():
        return e.value;
      case NameExpr():
        return _lookup(e.name, scope, e);
      case InterpolationExpr():
        final b = StringBuffer();
        for (final p in e.parts) {
          b.write(p is String ? p : stringify(eval(p as Expr, scope)));
        }
        return b.toString();
      case ListExpr():
        return [for (final i in e.items) eval(i, scope)];
      case MapExpr():
        return {for (final (k, v) in e.entries) eval(k, scope): eval(v, scope)};
      case MemberExpr():
        final obj = eval(e.object, scope);
        if (obj == null && e.nullSafe) return null;
        return getMember(obj, e.name, e);
      case IndexExpr():
        return _index(eval(e.object, scope), eval(e.index, scope), e);
      case CallExpr():
        return _evalCall(e, scope);
      case UnaryExpr():
        final v = eval(e.operand, scope);
        if (e.op == '!') return !_truthy(v, e.operand);
        if (v is num) return -v;
        if (v is Vector2) return -v;
        throw error("Can't negate ${describe(v)}", e);
      case BinaryExpr():
        return binary(e.op, eval(e.left, scope), eval(e.right, scope), e);
      case LogicalExpr():
        final l = eval(e.left, scope);
        switch (e.op) {
          case '&&':
            return _truthy(l, e.left) && _truthy(eval(e.right, scope), e.right);
          case '||':
            return _truthy(l, e.left) || _truthy(eval(e.right, scope), e.right);
          default: // ??
            return l ?? eval(e.right, scope);
        }
      case ConditionalExpr():
        return _truthy(eval(e.condition, scope), e.condition) ? eval(e.then, scope) : eval(e.otherwise, scope);
      case AssignExpr():
        return _assign(e, scope);
      case UpdateExpr():
        final old = eval(e.target, scope);
        if (old is! num) throw error('++ and -- need a number, but this is ${describe(old)}', e);
        final updated = old + e.delta;
        _store(e.target, updated, scope, e);
        return e.prefix ? updated : old;
      case FunctionExpr():
        return ScriptFunction(e.function, scope);
      default:
        throw error('Unknown expression', e);
    }
  }

  Object? _lookup(String name, Scope scope, Node at) {
    final s = scope.find(name);
    if (s != null) return s.vars[name];
    final owner = scope.owner;
    if (owner != null) {
      final f = owner.function(name);
      if (f != null) return f;
      if (owner.specials.containsKey(name)) return owner.specials[name];
    }
    if (globals.containsKey(name)) return globals[name];
    throw error('Unknown name "$name"${_suggest(name, [
          ...?owner?.fields.keys,
          ...?owner?.program.functions.keys,
          ...?owner?.specials.keys,
          ...globals.keys,
        ])}', at);
  }

  static String _suggest(String name, Iterable<String> candidates) {
    String? best;
    var bestD = 3;
    for (final c in candidates) {
      final d = _distance(name.toLowerCase(), c.toLowerCase());
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best == null ? '' : ' — did you mean "$best"?';
  }

  static int _distance(String a, String b) {
    if ((a.length - b.length).abs() > 3) return 99;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = [i, ...List<int>.filled(b.length, 0)];
      for (var j = 1; j <= b.length; j++) {
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce(math.min);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  Object? _assign(AssignExpr e, Scope scope) {
    Object? value;
    if (e.op.isEmpty) {
      value = eval(e.value, scope);
    } else if (e.op == '??') {
      final current = eval(e.target, scope);
      if (current != null) return current;
      value = eval(e.value, scope);
    } else {
      value = binary(e.op, eval(e.target, scope), eval(e.value, scope), e);
    }
    _store(e.target, value, scope, e);
    return value;
  }

  void _store(Expr target, Object? value, Scope scope, Node at) {
    switch (target) {
      case NameExpr():
        final s = scope.find(target.name);
        if (s == null) {
          final owner = scope.owner;
          if (owner != null && owner.hasFunction(target.name)) throw error('"${target.name}" is a function', at);
          if (owner != null && owner.specials.containsKey(target.name)) throw error('"${target.name}" can\'t be changed', at);
          throw error('Unknown variable "${target.name}" — declare it first with var ${target.name} = ...;', at);
        }
        if (s.isFinal(target.name)) throw error('"${target.name}" is final and can\'t be changed', at);
        s.vars[target.name] = value;
      case MemberExpr():
        final obj = eval(target.object, scope);
        if (obj == null && target.nullSafe) return;
        setMember(obj, target.name, value, at);
      case IndexExpr():
        final obj = eval(target.object, scope);
        final idx = eval(target.index, scope);
        if (obj is List) {
          if (idx is! int) throw error('A list index must be a whole number', target.index);
          if (idx < 0 || idx >= obj.length) throw error('Index $idx is outside the list (length ${obj.length})', target.index);
          obj[idx] = value;
        } else if (obj is Map) {
          obj[idx] = value;
        } else {
          throw error("Can't set [..] on ${describe(obj)}", at);
        }
      default:
        throw error("Can't assign to this", at);
    }
  }

  Object? _index(Object? obj, Object? idx, Node at) {
    if (obj is List) {
      if (idx is! int) throw error('A list index must be a whole number', at);
      if (idx < 0 || idx >= obj.length) throw error('Index $idx is outside the list (length ${obj.length})', at);
      return obj[idx];
    }
    if (obj is Map) return obj[idx];
    if (obj is String) {
      if (idx is! int || idx < 0 || idx >= obj.length) throw error('Index $idx is outside the string', at);
      return obj[idx];
    }
    throw error("Can't use [..] on ${describe(obj)}", at);
  }

  Object? _evalCall(CallExpr e, Scope scope) {
    final Object? callee;
    if (e.callee is MemberExpr) {
      final m = e.callee as MemberExpr;
      final obj = eval(m.object, scope);
      if (obj == null && m.nullSafe) return null;
      callee = getMember(obj, m.name, m);
    } else {
      callee = eval(e.callee, scope);
    }
    final args = [for (final a in e.args) eval(a, scope)];
    final named = e.named.isEmpty ? const <String, Object?>{} : {for (final n in e.named.entries) n.key: eval(n.value, scope)};
    return call(callee, args, named, e);
  }

  /// Calls a script or native function.
  Object? call(Object? callee, List<Object?> args, Map<String, Object?> named, Node? at) {
    if (callee is ScriptFunction) return _callScript(callee, args, named, at);
    if (callee is NativeFunction) {
      try {
        return callee.fn(args, named);
      } on ScriptRuntimeError {
        rethrow;
      } on ScriptArgumentError catch (x) {
        throw error('${callee.name}: ${x.message}', at);
      } catch (x) {
        throw error('${callee.name} failed: $x', at);
      }
    }
    throw error('${describe(callee)} is not a function', at);
  }

  Object? _callScript(ScriptFunction f, List<Object?> args, Map<String, Object?> named, Node? at) {
    final d = f.decl;
    if (args.length < d.requiredCount || args.length > d.positionalCount) {
      final n = d.requiredCount == d.positionalCount ? '${d.requiredCount}' : '${d.requiredCount}-${d.positionalCount}';
      throw error('${d.name.isEmpty ? 'This function' : d.name} expects $n argument${n == '1' ? '' : 's'}, got ${args.length}', at);
    }
    for (final k in named.keys) {
      if (!d.params.any((p) => p.named && p.name == k)) {
        throw error('${d.name.isEmpty ? 'This function' : d.name} has no named argument "$k"', at);
      }
    }
    if (++_depth > maxDepth) {
      _depth = 0;
      throw error('Too many nested calls (a function calling itself forever?)', at);
    }
    try {
      final scope = Scope(f.closure);
      var i = 0;
      for (final p in d.params) {
        Object? v;
        if (p.named) {
          v = named.containsKey(p.name) ? named[p.name] : (p.defaultValue == null ? null : eval(p.defaultValue!, scope));
        } else {
          v = i < args.length ? args[i] : (p.defaultValue == null ? null : eval(p.defaultValue!, scope));
          i++;
        }
        scope.define(p.name, v);
      }
      _returnValue = null;
      final flow = _execBlock(d.body, scope);
      final result = flow == _Flow.returned ? _returnValue : null;
      _returnValue = null;
      return result;
    } finally {
      _depth--;
    }
  }

  // --- Operators ---

  Object? binary(String op, Object? l, Object? r, Node at) {
    if (op == '==') return _equals(l, r);
    if (op == '!=') return !_equals(l, r);
    if (l is num && r is num) {
      switch (op) {
        case '+':
          return l + r;
        case '-':
          return l - r;
        case '*':
          return l * r;
        case '/':
          if (r == 0) throw error('Division by zero', at);
          return l / r;
        case '~/':
          if (r == 0) throw error('Division by zero', at);
          return l ~/ r;
        case '%':
          if (r == 0) throw error('Division by zero', at);
          return l % r;
        case '<':
          return l < r;
        case '<=':
          return l <= r;
        case '>':
          return l > r;
        case '>=':
          return l >= r;
      }
    }
    if (op == '+' && (l is String || r is String)) return stringify(l) + stringify(r);
    if (l is String && r is String) {
      final c = l.compareTo(r);
      switch (op) {
        case '<':
          return c < 0;
        case '<=':
          return c <= 0;
        case '>':
          return c > 0;
        case '>=':
          return c >= 0;
      }
    }
    if (op == '*' && l is String && r is int) return l * r;
    if (op == '+' && l is List && r is List) return [...l, ...r];
    if (l is Vector2 && r is Vector2) {
      if (op == '+') return l + r;
      if (op == '-') return l - r;
    }
    if (l is Vector2 && r is num) {
      if (op == '*') return l * r.toDouble();
      if (op == '/') return l / r.toDouble();
    }
    if (l is num && r is Vector2 && op == '*') return r * l.toDouble();
    throw error("Can't use $op on ${describe(l)} and ${describe(r)}", at);
  }

  static bool _equals(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    return a == b;
  }

  // --- Members ---

  Object? getMember(Object? obj, String name, Node at) {
    if (obj == null) throw error('Can\'t read ".$name" of null (the value is missing)', at);
    if (name == 'toString') return NativeFunction('toString', (_, _) => stringify(obj));
    final v = switch (obj) {
      String() => _stringMember(obj, name),
      num() => _numMember(obj, name),
      List() => _listMember(obj, name, at),
      Map() => _mapMember(obj, name, at),
      _ => _hostMember(obj, name),
    };
    if (identical(v, missing)) {
      final names = _memberNames(obj);
      throw error('${describe(obj)} has no "$name"${_suggest(name, names)}', at);
    }
    return v;
  }

  void setMember(Object? obj, String name, Object? value, Node at) {
    if (obj == null) throw error('Can\'t set ".$name" of null (the value is missing)', at);
    for (final h in hostTypes) {
      if (h.matches(obj)) {
        try {
          if (h.setMember(obj, name, value)) return;
        } on ScriptArgumentError catch (x) {
          throw error('.$name: ${x.message}', at);
        }
        break;
      }
    }
    throw error('Can\'t set "$name" on ${describe(obj)}', at);
  }

  Object? _hostMember(Object obj, String name) {
    for (final h in hostTypes) {
      if (h.matches(obj)) return h.getMember(obj, name);
    }
    return missing;
  }

  List<String> _memberNames(Object obj) {
    for (final h in hostTypes) {
      if (h.matches(obj)) return h.memberNames(obj);
    }
    return switch (obj) {
      String() => _stringMembers,
      num() => _numMembers,
      List() => _listMembers,
      Map() => _mapMembers,
      _ => const [],
    };
  }

  static NativeFunction _fn(String name, Object? Function(List<Object?> a) f) => NativeFunction(name, (a, _) => f(a));

  static const _stringMembers = [
    'length', 'isEmpty', 'isNotEmpty', 'toUpperCase', 'toLowerCase', 'trim', 'contains', 'startsWith', 'endsWith',
    'substring', 'split', 'replaceAll', 'indexOf', 'padLeft', 'padRight', 'toNumber',
  ];

  Object? _stringMember(String s, String name) => switch (name) {
        'length' => s.length,
        'isEmpty' => s.isEmpty,
        'isNotEmpty' => s.isNotEmpty,
        'toUpperCase' => _fn(name, (_) => s.toUpperCase()),
        'toLowerCase' => _fn(name, (_) => s.toLowerCase()),
        'trim' => _fn(name, (_) => s.trim()),
        'contains' => _fn(name, (a) => s.contains(arg<String>(a, 0, 'text'))),
        'startsWith' => _fn(name, (a) => s.startsWith(arg<String>(a, 0, 'text'))),
        'endsWith' => _fn(name, (a) => s.endsWith(arg<String>(a, 0, 'text'))),
        'substring' => _fn(name, (a) => s.substring(arg<int>(a, 0, 'start'), a.length > 1 ? arg<int>(a, 1, 'end') : null)),
        'split' => _fn(name, (a) => s.split(arg<String>(a, 0, 'separator'))),
        'replaceAll' => _fn(name, (a) => s.replaceAll(arg<String>(a, 0, 'from'), arg<String>(a, 1, 'to'))),
        'indexOf' => _fn(name, (a) => s.indexOf(arg<String>(a, 0, 'text'))),
        'padLeft' => _fn(name, (a) => s.padLeft(arg<int>(a, 0, 'width'), a.length > 1 ? arg<String>(a, 1, 'pad') : ' ')),
        'padRight' => _fn(name, (a) => s.padRight(arg<int>(a, 0, 'width'), a.length > 1 ? arg<String>(a, 1, 'pad') : ' ')),
        'toNumber' => _fn(name, (_) => num.tryParse(s.trim())),
        _ => missing,
      };

  static const _numMembers = [
    'round', 'floor', 'ceil', 'abs', 'toInt', 'toDouble', 'clamp', 'toStringAsFixed', 'isEven', 'isOdd', 'sign', 'isNaN',
  ];

  Object? _numMember(num n, String name) => switch (name) {
        'round' => _fn(name, (_) => n.round()),
        'floor' => _fn(name, (_) => n.floor()),
        'ceil' => _fn(name, (_) => n.ceil()),
        'abs' => _fn(name, (_) => n.abs()),
        'toInt' => _fn(name, (_) => n.toInt()),
        'toDouble' => _fn(name, (_) => n.toDouble()),
        'clamp' => _fn(name, (a) => n.clamp(arg<num>(a, 0, 'min'), arg<num>(a, 1, 'max'))),
        'toStringAsFixed' => _fn(name, (a) => n.toStringAsFixed(arg<int>(a, 0, 'digits'))),
        'isEven' => n is int ? n.isEven : n.toInt().isEven,
        'isOdd' => n is int ? n.isOdd : n.toInt().isOdd,
        'sign' => n.sign,
        'isNaN' => n.isNaN,
        _ => missing,
      };

  static const _listMembers = [
    'length', 'isEmpty', 'isNotEmpty', 'first', 'last', 'add', 'addAll', 'insert', 'remove', 'removeAt', 'removeLast',
    'removeWhere', 'contains', 'indexOf', 'clear', 'join', 'map', 'where', 'forEach', 'any', 'every', 'firstWhere',
    'reduce', 'fold', 'sort', 'reversed', 'shuffle', 'sublist', 'toList', 'take', 'skip', 'random',
  ];

  Object? _listMember(List<Object?> l, String name, Node at) {
    Object? f(Object? fn, List<Object?> args) => call(fn, args, const {}, at);
    return switch (name) {
      'length' => l.length,
      'isEmpty' => l.isEmpty,
      'isNotEmpty' => l.isNotEmpty,
      'first' => l.isEmpty ? throw error('The list is empty', at) : l.first,
      'last' => l.isEmpty ? throw error('The list is empty', at) : l.last,
      'add' => _fn(name, (a) => l.add(a.isEmpty ? null : a[0])),
      'addAll' => _fn(name, (a) => l.addAll(arg<List<Object?>>(a, 0, 'list'))),
      'insert' => _fn(name, (a) => l.insert(arg<int>(a, 0, 'index'), a.length > 1 ? a[1] : null)),
      'remove' => _fn(name, (a) => l.remove(a.isEmpty ? null : a[0])),
      'removeAt' => _fn(name, (a) => l.removeAt(arg<int>(a, 0, 'index'))),
      'removeLast' => _fn(name, (_) => l.removeLast()),
      'removeWhere' => _fn(name, (a) => l.removeWhere((x) => f(a[0], [x]) == true)),
      'contains' => _fn(name, (a) => l.contains(a.isEmpty ? null : a[0])),
      'indexOf' => _fn(name, (a) => l.indexOf(a.isEmpty ? null : a[0])),
      'clear' => _fn(name, (_) => l.clear()),
      'join' => _fn(name, (a) => l.map(stringify).join(a.isEmpty ? '' : arg<String>(a, 0, 'separator'))),
      'map' => _fn(name, (a) => [for (final x in l) f(a[0], [x])]),
      'where' => _fn(name, (a) => [for (final x in l) if (f(a[0], [x]) == true) x]),
      'forEach' => _fn(name, (a) {
          for (final x in List<Object?>.of(l)) {
            f(a[0], [x]);
          }
          return null;
        }),
      'any' => _fn(name, (a) => l.any((x) => f(a[0], [x]) == true)),
      'every' => _fn(name, (a) => l.every((x) => f(a[0], [x]) == true)),
      'firstWhere' => NativeFunction(name, (a, named) {
          for (final x in l) {
            if (f(a[0], [x]) == true) return x;
          }
          final orElse = named['orElse'];
          return orElse == null ? null : f(orElse, []);
        }),
      'reduce' => _fn(name, (a) => l.isEmpty ? null : l.reduce((x, y) => f(a[0], [x, y]))),
      'fold' => _fn(name, (a) => l.fold<Object?>(a[0], (x, y) => f(a[1], [x, y]))),
      'sort' => _fn(name, (a) {
          if (a.isEmpty) {
            l.sort((x, y) => x is Comparable && y is Comparable ? x.compareTo(y) : 0);
          } else {
            l.sort((x, y) => (f(a[0], [x, y]) as num).sign.toInt());
          }
          return null;
        }),
      'reversed' => l.reversed.toList(),
      'shuffle' => _fn(name, (_) => l.shuffle(random)),
      'sublist' => _fn(name, (a) => l.sublist(arg<int>(a, 0, 'start'), a.length > 1 ? arg<int>(a, 1, 'end') : null)),
      'toList' => _fn(name, (_) => List<Object?>.of(l)),
      'take' => _fn(name, (a) => l.take(arg<int>(a, 0, 'count')).toList()),
      'skip' => _fn(name, (a) => l.skip(arg<int>(a, 0, 'count')).toList()),
      'random' => _fn(name, (_) => l.isEmpty ? null : l[random.nextInt(l.length)]),
      _ => missing,
    };
  }

  static const _mapMembers = [
    'length', 'isEmpty', 'isNotEmpty', 'keys', 'values', 'containsKey', 'containsValue', 'remove', 'forEach', 'clear',
    'putIfAbsent',
  ];

  Object? _mapMember(Map<Object?, Object?> m, String name, Node at) => switch (name) {
        'length' => m.length,
        'isEmpty' => m.isEmpty,
        'isNotEmpty' => m.isNotEmpty,
        'keys' => m.keys.toList(),
        'values' => m.values.toList(),
        'containsKey' => _fn(name, (a) => m.containsKey(a.isEmpty ? null : a[0])),
        'containsValue' => _fn(name, (a) => m.containsValue(a.isEmpty ? null : a[0])),
        'remove' => _fn(name, (a) => m.remove(a.isEmpty ? null : a[0])),
        'forEach' => _fn(name, (a) {
            for (final e in Map<Object?, Object?>.of(m).entries) {
              call(a[0], [e.key, e.value], const {}, at);
            }
            return null;
          }),
        'clear' => _fn(name, (_) => m.clear()),
        'putIfAbsent' => _fn(name, (a) => m.putIfAbsent(a[0], () => call(a[1], [], const {}, at))),
        _ => missing,
      };

  // --- Helpers ---

  static final math.Random random = math.Random();

  static String typeOf(Object? v) => switch (v) {
        null => 'null',
        bool() => 'a bool',
        int() => 'a whole number',
        double() => 'a number',
        String() => 'a string',
        List() => 'a list',
        Map() => 'a map',
        ScriptFunction() || NativeFunction() => 'a function',
        _ => _hostName(v),
      };

  static String _hostName(Object v) {
    for (final h in hostTypes) {
      if (h.matches(v)) return 'a ${h.typeName}';
    }
    return 'a ${v.runtimeType}';
  }

  /// A short description for error messages: `the number 3`, `a list`, ...
  static String describe(Object? v) => switch (v) {
        null => 'null',
        num() || bool() => '$v',
        String() => '"${v.length > 30 ? '${v.substring(0, 30)}…' : v}"',
        _ => typeOf(v),
      };

  static String stringify(Object? v) {
    if (v is String) return v;
    if (v is double && v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(1);
    if (v is List) return '[${v.map(stringify).join(', ')}]';
    if (v is Map) return '{${v.entries.map((e) => '${stringify(e.key)}: ${stringify(e.value)}').join(', ')}}';
    if (v is Vector2) return 'Vec2(${_n(v.x)}, ${_n(v.y)})';
    if (v != null) {
      for (final h in hostTypes) {
        if (h.matches(v)) return h.describe(v);
      }
    }
    return '$v';
  }

  static String _n(double d) => d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);

  /// Converts an Inspector override to the type of the field's default.
  static Object? coerceLike(Object? value, Object? like) {
    if (like is int && value is num) return value.round();
    if (like is double && value is num) return value.toDouble();
    if (like is num && value is String) return num.tryParse(value) ?? like;
    if (like is bool && value is! bool) return value == 'true' || value == 1;
    if (like is String && value is! String) return value?.toString() ?? '';
    return value;
  }
}

/// Wrong arguments to an engine function; reported with the script line.
class ScriptArgumentError implements Exception {
  final String message;
  ScriptArgumentError(this.message);
}

/// Reads argument [i] as a [T] (numbers convert between int and double).
T arg<T>(List<Object?> args, int i, String what) {
  if (i >= args.length) throw ScriptArgumentError('missing argument "$what"');
  final v = args[i];
  if (v is T) return v;
  if (T == double && v is num) return v.toDouble() as T;
  if (T == int && v is double && v == v.roundToDouble()) return v.toInt() as T;
  throw ScriptArgumentError('"$what" should be ${_typeWord<T>()}, not ${Interpreter.describe(v)}');
}

/// Optional argument [i], or [fallback].
T optArg<T>(List<Object?> args, int i, String what, T fallback) =>
    i < args.length && args[i] != null ? arg<T>(args, i, what) : fallback;

String _typeWord<T>() {
  if (T == int) return 'a whole number';
  if (T == double || T == num) return 'a number';
  if (T == String) return 'text';
  if (T == bool) return 'true or false';
  if (T == List || T.toString().startsWith('List')) return 'a list';
  return T.toString();
}

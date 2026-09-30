/// Ember Script runtime: the project's `.ember` scripts, compiled and
/// attached to entities through Script Components.
library;

import 'package:flutter/foundation.dart';
import '../core/engine_loop.dart';
import '../core/entity.dart';
import '../core/event_bus.dart' show LogSeverity;
import '../core/game_script.dart';
import 'api.dart';
import 'ast.dart';
import 'interpreter.dart';
import 'lexer.dart';
import 'parser.dart';

/// A script problem found while compiling or running, for the Problems list.
class ScriptProblem {
  final String file;
  final int line, column;
  final String message;
  final bool runtime;
  int count;
  ScriptProblem(this.file, this.line, this.column, this.message, {this.runtime = false, this.count = 1});

  String get location => '$file:$line${column > 0 ? ':$column' : ''}';

  @override
  String toString() => '$location  $message';
}

class EmberScripts extends ChangeNotifier {
  static final EmberScripts instance = EmberScripts._();
  EmberScripts._() {
    registerScriptApi();
    ScriptRegistry.extraScripts = () => names;
    ScriptRegistry.fallback = create;
  }

  static const String extension = '.ember';
  static bool isScriptFile(String name) => name.endsWith(extension);

  final Map<String, String> _sources = {};
  final Map<String, Program> _programs = {};
  final Map<String, ScriptProblem> _compileErrors = {};
  final Map<String, ScriptProblem> _runtimeErrors = {};
  final Set<EmberScriptBehavior> _live = {};
  final Interpreter interpreter = Interpreter();

  /// Lines written with print() since Play started (also sent to the console).
  final List<String> output = [];

  /// The script whose code is running right now (for `self`-free globals like destroy()).
  EmberScriptBehavior? current;

  /// Seconds in the last onUpdate / onFixedUpdate.
  double dt = 1 / 60;

  List<String> get names => _sources.keys.toList()..sort();
  String? source(String file) => _sources[file];
  Program? program(String file) => _programs[file];
  ScriptProblem? compileError(String file) => _compileErrors[file];
  List<ScriptProblem> get problems => [..._compileErrors.values, ..._runtimeErrors.values];
  int get liveCount => _live.length;

  /// Replaces all scripts with the `.ember` entries of [scripts] (e.g. a project's).
  void loadAll(Map<String, String> scripts) {
    _sources.clear();
    _programs.clear();
    _compileErrors.clear();
    for (final e in scripts.entries) {
      if (isScriptFile(e.key)) _compile(e.key, e.value);
    }
    notifyListeners();
  }

  /// Adds or edits a script. Running copies pick up the new code at once
  /// (their variables keep their values). Returns the compile error, if any.
  ScriptProblem? update(String file, String source) {
    if (_sources[file] == source && (_programs.containsKey(file) || _compileErrors.containsKey(file))) {
      return _compileErrors[file];
    }
    _compile(file, source);
    final program = _programs[file];
    if (program != null && _compileErrors[file] == null) {
      for (final b in _live.where((b) => b.file == file).toList()) {
        b._reload(program);
      }
    }
    notifyListeners();
    return _compileErrors[file];
  }

  void remove(String file) {
    _sources.remove(file);
    _programs.remove(file);
    _compileErrors.remove(file);
    notifyListeners();
  }

  void _compile(String file, String source) {
    _sources[file] = source;
    try {
      _programs[file] = Parser.parseProgram(source, file: file);
      _compileErrors.remove(file);
    } on ScriptError catch (e) {
      _compileErrors[file] = ScriptProblem(file, e.line, e.column, e.message);
    }
  }

  /// Checks [source] without installing it (for live error markers while typing).
  static ScriptProblem? check(String file, String source) {
    try {
      Parser.parseProgram(source, file: file);
      return null;
    } on ScriptError catch (e) {
      return ScriptProblem(file, e.line, e.column, e.message);
    }
  }

  /// A Script Component asked for [name]: an Ember Script behaviour, if it's one of ours.
  GameScript? create(String name) => _sources.containsKey(name) ? EmberScriptBehavior(name) : null;

  /// Called when Play starts: fresh output and runtime errors.
  void beginPlay() {
    _live.clear();
    _runtimeErrors.clear();
    output.clear();
    current = null;
    notifyListeners();
  }

  void clearRuntimeErrors() {
    _runtimeErrors.clear();
    notifyListeners();
  }

  void print(String message) {
    output.add(message);
    if (output.length > 500) output.removeRange(0, output.length - 500);
    final src = current == null ? 'Script' : current!.file;
    EmberEngine.instance.log(message, source: src);
  }

  /// Records a runtime error once (repeats are counted, not re-logged).
  void report(ScriptError e) {
    final file = e.file.isEmpty ? (current?.file ?? 'script') : e.file;
    final key = '$file:${e.line}:${e.message}';
    final existing = _runtimeErrors[key];
    if (existing != null) {
      existing.count++;
      return;
    }
    final fn = e is ScriptRuntimeError && e.function.isNotEmpty ? ' (in ${e.function})' : '';
    _runtimeErrors[key] = ScriptProblem(file, e.line, e.column, e.message + fn, runtime: true);
    EmberEngine.instance.log('${e.message}$fn', severity: LogSeverity.error, source: '$file:${e.line}');
    notifyListeners();
  }

  /// Runs [action] as [behavior] (so errors are reported, not thrown).
  Object? run(EmberScriptBehavior? behavior, Object? Function() action) {
    final previous = current;
    current = behavior ?? current;
    try {
      return action();
    } on ScriptError catch (e) {
      report(e);
      return null;
    } finally {
      current = previous;
    }
  }

  /// Calls a script function value later (timers, tweens, UI callbacks).
  Object? callLater(EmberScriptBehavior? behavior, Object? fn, List<Object?> args) {
    if (behavior != null && !behavior.alive) return null;
    return run(behavior, () => interpreter.callValue(fn, args, file: behavior?.file ?? ''));
  }

  void _track(EmberScriptBehavior b) => _live.add(b);
  void _untrack(EmberScriptBehavior b) => _live.remove(b);
}

/// Runs one `.ember` script on one entity.
class EmberScriptBehavior extends GameScript implements ConfigurableScript {
  final String file;
  ScriptInstance? _instance;
  bool alive = false;
  bool _reportedCompileError = false;

  @override
  Map<String, Object?> overrides = {};

  EmberScriptBehavior(this.file);

  EmberScripts get _lib => EmberScripts.instance;
  Program? get program => _lib.program(file);
  ScriptInstance? get instance => _instance;

  /// Current value of a script variable (running), else its Inspector/default value.
  Object? field(String name) {
    final inst = _instance;
    if (inst != null && inst.fields.containsKey(name)) return inst.fields[name];
    if (overrides.containsKey(name)) return overrides[name];
    for (final f in program?.fields ?? const <FieldDecl>[]) {
      if (f.name == name) return f.literalDefault;
    }
    return null;
  }

  @override
  Map<String, Object?> get exposedFields => {
        for (final f in program?.fields ?? const <FieldDecl>[])
          if (f.exposed) f.name: Interpreter.coerceLike(overrides[f.name] ?? field(f.name), f.literalDefault),
      };

  @override
  void setField(String name, Object? value) {
    final decl = program?.fields.where((f) => f.name == name).firstOrNull;
    final v = Interpreter.coerceLike(value, decl?.literalDefault);
    overrides[name] = v;
    _instance?.fields[name] = v;
  }

  bool _ensureInstance() {
    if (_instance != null) return true;
    final p = program;
    if (p == null) {
      if (!_reportedCompileError) {
        _reportedCompileError = true;
        final err = _lib.compileError(file);
        EmberEngine.instance.log(
          err == null ? 'Script $file not found' : 'Script $file has an error and did not run: ${err.message}',
          severity: LogSeverity.error,
          source: err == null ? file : err.location,
        );
      }
      return false;
    }
    final inst = ScriptInstance(p, specials: {'self': entity});
    _instance = inst;
    _lib.run(this, () {
      _lib.interpreter.initialize(inst, overrides: overrides);
      return null;
    });
    return true;
  }

  void _reload(Program p) {
    final inst = _instance;
    if (inst == null) return;
    inst.program = p;
    // New variables get their initial value; existing ones keep theirs
    _lib.run(this, () {
      for (final f in p.fields) {
        if (!inst.fields.containsKey(f.name)) {
          inst.root.define(f.name, f.init == null ? null : _lib.interpreter.eval(f.init!, inst.root), isFinal: f.isFinal);
        }
      }
      return null;
    });
  }

  Object? _call(String name, [List<Object?> args = const []]) {
    final inst = _instance;
    if (inst == null || !inst.hasFunction(name)) return null;
    return _lib.run(this, () => _lib.interpreter.callIfDefined(inst, name, args));
  }

  /// Calls a function defined in this script (used by entity.call(...)).
  Object? callFunction(String name, List<Object?> args) {
    if (!_ensureInstance()) return null;
    return _call(name, args);
  }

  bool hasFunction(String name) => program?.functions.containsKey(name) ?? false;

  @override
  void onAwake() {
    if (!_ensureInstance()) return;
    alive = true;
    _lib._track(this);
    _call('onAwake');
  }

  @override
  void onStart() => _call('onStart');

  @override
  void onUpdate(double dt) {
    _lib.dt = dt;
    _call('onUpdate', [dt]);
  }

  @override
  void onFixedUpdate(double fixedDt) {
    if (_instance?.hasFunction('onFixedUpdate') ?? false) {
      _lib.dt = fixedDt;
      _call('onFixedUpdate', [fixedDt]);
    }
  }

  @override
  void onDestroy() {
    _call('onDestroy');
    alive = false;
    _lib._untrack(this);
  }

  @override
  void onTriggerEnter(EmberEntity other) => _call('onTriggerEnter', [other]);
  @override
  void onTriggerExit(EmberEntity other) => _call('onTriggerExit', [other]);
  @override
  void onCollisionEnter(EmberEntity other) => _call('onCollisionEnter', [other]);
  @override
  void onCollisionExit(EmberEntity other) => _call('onCollisionExit', [other]);
  @override
  void onHeadBump(TileHit tile) => _call('onHeadBump', [tile]);
  @override
  void onTileTouch(TileHit tile) => _call('onTileTouch', [tile]);
  @override
  void onDamaged(double amount, EmberEntity? source) => _call('onDamaged', [amount, source]);
  @override
  void onDeath(EmberEntity? killer) => _call('onDeath', [killer]);
  @override
  void onKill(EmberEntity victim) => _call('onKill', [victim]);
  @override
  void onUIAction(String action) => _call('onUIAction', [action]);
  @override
  void onInteract(EmberEntity by) => _call('onInteract', [by]);
}

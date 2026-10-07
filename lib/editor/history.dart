import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/engine_loop.dart';
import '../core/event_bus.dart' show PlayState;
import '../core/scene.dart';

/// Undo / redo for everything edited in the scene.
///
/// Rather than every panel recording its own commands, the history watches
/// the scene: once edits settle (a drag ends, a field stops changing, a
/// paint stroke finishes) it stores a snapshot. Undo restores the previous
/// snapshot. So any edit — Inspector fields, gizmo drags, tile painting,
/// adding / deleting / duplicating entities, attaching scripts — is undoable,
/// including edits made by panels added later.
class EditorHistory extends ChangeNotifier {
  static final EditorHistory instance = EditorHistory._();
  EditorHistory._();

  /// How long the scene must stay unchanged before a step is recorded.
  static Duration settleTime = const Duration(milliseconds: 400);
  static const int maxSteps = 100;

  EmberEngine? _engine;
  EmberScene? _scene;
  String? _sceneName;
  String? _baseline;
  final List<_Step> _undo = [];
  final List<_Step> _redo = [];
  Timer? _timer;
  bool _restoring = false;

  bool get canUndo => _undo.isNotEmpty || _pendingChange;
  bool get canRedo => _redo.isNotEmpty;
  int get undoCount => _undo.length;
  int get redoCount => _redo.length;

  bool _pendingChange = false;

  /// Starts watching [engine]'s scene.
  void attach(EmberEngine engine) {
    if (identical(_engine, engine)) return;
    _engine?.removeListener(_onEngine);
    _engine = engine;
    engine.addListener(_onEngine);
    _watch(engine.activeScene, clear: true);
  }

  void detach() {
    _engine?.removeListener(_onEngine);
    _scene?.removeListener(_onSceneChanged);
    _engine = null;
    _scene = null;
    _timer?.cancel();
  }

  /// Forgets all steps (e.g. another project was opened).
  void clear() {
    _undo.clear();
    _redo.clear();
    _pendingChange = false;
    _timer?.cancel();
    final s = _scene;
    _baseline = s == null ? null : _snapshot(s);
    notifyListeners();
  }

  bool get _editing => _engine?.playState == PlayState.stopped;

  void _onEngine() {
    final e = _engine;
    if (e == null || _restoring) return;
    if (!identical(e.activeScene, _scene)) {
      // A different scene object: Stop restored the edited scene (same name,
      // keep the steps), or another scene/project was opened (start over).
      _watch(e.activeScene, clear: e.activeScene.name != _sceneName);
    }
  }

  void _watch(EmberScene scene, {required bool clear}) {
    _scene?.removeListener(_onSceneChanged);
    _scene = scene;
    _sceneName = scene.name;
    scene.addListener(_onSceneChanged);
    _timer?.cancel();
    _pendingChange = false;
    if (clear) {
      _undo.clear();
      _redo.clear();
    }
    _baseline = _editing ? _snapshot(scene) : _baseline;
    notifyListeners();
  }

  void _onSceneChanged() {
    if (_restoring || !_editing) return;
    _pendingChange = true;
    _timer?.cancel();
    _timer = Timer(settleTime, flush);
  }

  /// Records the current state now (if it changed) instead of waiting.
  void flush() {
    _timer?.cancel();
    _pendingChange = false;
    final s = _scene;
    if (s == null || !_editing) return;
    final now = _snapshot(s);
    if (_baseline == null) {
      _baseline = now;
      return;
    }
    if (now == _baseline) return;
    _undo.add(_Step(_baseline!, _engine?.selectedEntity?.id));
    if (_undo.length > maxSteps) _undo.removeAt(0);
    _redo.clear();
    _baseline = now;
    notifyListeners();
  }

  /// Returns false when there is nothing to undo.
  bool undo() {
    if (!_editing) return false;
    flush();
    if (_undo.isEmpty) return false;
    final step = _undo.removeLast();
    _redo.add(_Step(_baseline!, _engine?.selectedEntity?.id));
    _restore(step);
    return true;
  }

  bool redo() {
    if (!_editing) return false;
    flush();
    if (_redo.isEmpty) return false;
    final step = _redo.removeLast();
    _undo.add(_Step(_baseline!, _engine?.selectedEntity?.id));
    _restore(step);
    return true;
  }

  void _restore(_Step step) {
    final engine = _engine;
    if (engine == null) return;
    _restoring = true;
    try {
      final scene = EmberScene.fromJson(jsonDecode(step.json) as Map<String, dynamic>);
      _scene?.removeListener(_onSceneChanged);
      engine.loadScene(scene);
      _scene = scene;
      _sceneName = scene.name;
      scene.addListener(_onSceneChanged);
      _baseline = step.json;
      final selected = step.selectedId == null ? null : scene.findById(step.selectedId!);
      if (selected != null) engine.selectEntity(selected);
    } finally {
      _restoring = false;
    }
    notifyListeners();
  }

  static String _snapshot(EmberScene scene) => jsonEncode(scene.toJson());
}

class _Step {
  final String json;
  final String? selectedId;
  const _Step(this.json, this.selectedId);
}

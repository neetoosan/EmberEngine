import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/scene.dart';
import 'hub/project_manifest.dart';
import 'hub/project_storage.dart';

/// A recovery copy found for a project (written while editing, kept after a crash).
class RecoveryCopy {
  final File file;
  final DateTime savedAt;
  final Map<String, dynamic> content;
  const RecoveryCopy(this.file, this.savedAt, this.content);
}

/// Knows whether the open project has changes that are not saved to disk,
/// and keeps a recovery copy in `<project>/.recovery/` so a crash or power
/// cut loses at most [autosaveInterval] of work. The copy is deleted when
/// the project is saved or the user chooses not to keep the changes.
class ProjectSession extends ChangeNotifier {
  static final ProjectSession instance = ProjectSession._();
  ProjectSession._();

  static const String recoveryDirName = '.recovery';
  static const String recoveryFileName = 'recovery.json';

  /// How often the unsaved-changes marker is refreshed.
  Duration checkInterval = const Duration(seconds: 2);

  /// How often a recovery copy is written while there are unsaved changes.
  Duration autosaveInterval = const Duration(seconds: 60);

  EmberProject? _project;
  Map<String, dynamic> Function()? _content;
  bool Function()? _canSnapshot;
  int? _savedDigest;
  bool _dirty = false;
  Timer? _checkTimer;
  Timer? _autosaveTimer;

  EmberProject? get project => _project;

  /// True when the project differs from what was last saved.
  bool get isDirty => _dirty;

  /// When the last recovery copy was written (this session).
  DateTime? lastRecoveryWrite;

  /// Starts tracking [project]. [content] returns everything a save writes
  /// (see [contentOf]); [canSnapshot] returns false while the content cannot
  /// change (e.g. while the game is playing), to skip needless work.
  void begin(EmberProject project, {required Map<String, dynamic> Function() content, bool Function()? canSnapshot}) {
    end();
    _project = project;
    _content = content;
    _canSnapshot = canSnapshot;
    _savedDigest = _digest(content());
    _dirty = false;
    _checkTimer = Timer.periodic(checkInterval, (_) => refresh());
    _autosaveTimer = Timer.periodic(autosaveInterval, (_) => writeRecovery());
    notifyListeners();
  }

  void end() {
    _checkTimer?.cancel();
    _autosaveTimer?.cancel();
    _checkTimer = null;
    _autosaveTimer = null;
    _project = null;
    _content = null;
    if (_dirty) {
      _dirty = false;
      notifyListeners();
    }
  }

  /// Re-checks for unsaved changes (also runs every [checkInterval]).
  void refresh() {
    final content = _content;
    if (content == null || !(_canSnapshot?.call() ?? true)) return;
    final dirty = _digest(content()) != _savedDigest;
    if (dirty != _dirty) {
      _dirty = dirty;
      notifyListeners();
    }
  }

  /// Call after the project was written to disk: it is clean again and the
  /// recovery copy is no longer needed.
  Future<void> markSaved() async {
    final content = _content;
    if (content != null) _savedDigest = _digest(content());
    if (_dirty) {
      _dirty = false;
      notifyListeners();
    }
    final p = _project;
    if (p != null) await discardRecovery(p);
  }

  /// Marks the current content as differing from disk (after restoring a recovery copy).
  void markRecovered() {
    _dirty = true;
    notifyListeners();
  }

  /// Writes a recovery copy if there are unsaved changes. Returns the file written, if any.
  Future<File?> writeRecovery() async {
    final p = _project, content = _content;
    if (p == null || content == null || !ProjectStorage.hasDiskLocation(p)) return null;
    if (!(_canSnapshot?.call() ?? true)) return null;
    final now = content();
    final digest = _digest(now);
    if (digest == _savedDigest) return null;
    try {
      final file = recoveryFile(p);
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({'savedAt': DateTime.now().toIso8601String(), 'content': now}), flush: true);
      await tmp.rename(file.path);
      lastRecoveryWrite = DateTime.now();
      return file;
    } catch (_) {
      return null; // never let a background safety copy interrupt editing
    }
  }

  // ---------------------------------------------------------------------------

  /// What a save writes: every scene, every script and the start scene.
  /// [editingScene]/[editingJson] replace the stored copy of the scene open in the editor.
  static Map<String, dynamic> contentOf(EmberProject project, {String? editingScene, Map<String, dynamic>? editingJson}) => {
        'name': project.name,
        'start': project.defaultSceneName,
        'scenes': {
          for (final e in project.scenes.entries) e.key: e.key == editingScene && editingJson != null ? editingJson : e.value.toJson(),
        },
        'scripts': Map<String, String>.of(project.scripts),
      };

  /// Puts recovered [content] into [project] (scenes, scripts, start scene).
  static void applyContent(EmberProject project, Map<String, dynamic> content) {
    final scenes = (content['scenes'] as Map?)?.cast<String, dynamic>() ?? const {};
    project.scenes
      ..clear()
      ..addAll({for (final e in scenes.entries) e.key: EmberScene.fromJson((e.value as Map).cast<String, dynamic>())});
    project.scripts
      ..clear()
      ..addAll(((content['scripts'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')));
    final start = content['start'] as String?;
    if (start != null && project.scenes.containsKey(start)) project.defaultSceneName = start;
  }

  static File recoveryFile(EmberProject project) =>
      File('${project.path}${Platform.pathSeparator}$recoveryDirName${Platform.pathSeparator}$recoveryFileName');

  /// The recovery copy left by an earlier session (e.g. after a crash), if any.
  static Future<RecoveryCopy?> findRecovery(EmberProject project) async {
    if (!ProjectStorage.hasDiskLocation(project)) return null;
    final file = recoveryFile(project);
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final content = (json['content'] as Map).cast<String, dynamic>();
      final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '') ?? await file.lastModified();
      return RecoveryCopy(file, savedAt, content);
    } catch (_) {
      return null; // unreadable (e.g. half-written by a power cut): nothing to offer
    }
  }

  static Future<void> discardRecovery(EmberProject project) async {
    if (!ProjectStorage.hasDiskLocation(project)) return;
    try {
      final file = recoveryFile(project);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static int _digest(Map<String, dynamic> content) {
    final s = jsonEncode(content);
    return Object.hash(s.length, s.hashCode);
  }
}

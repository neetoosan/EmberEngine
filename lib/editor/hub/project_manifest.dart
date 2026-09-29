import 'dart:convert';
import 'dart:io';
import '../../core/scene.dart';
import '../../core/scene_serializer.dart';

/// Render pipeline modes supported by Ember Engine.
enum RenderPipelineMode {
  twoD('2D Flat & Pixel Pipeline (Flame)', '2D'),
  threeD('3D Viewport & Spatial Mesh Pipeline', '3D'),
  hybrid('Hybrid 2D + 3D Viewport Pipeline', 'Hybrid');

  final String label;
  final String shortCode;
  const RenderPipelineMode(this.label, this.shortCode);
}

/// Metadata model representing an Ember Project.
class EmberProject {
  final String id;
  String name;
  String version;
  String author;
  String description;
  RenderPipelineMode renderPipeline;
  DateTime createdAt;
  DateTime lastModified;
  String defaultSceneName;
  String path;

  /// In-memory or bundled scenes keyed by scene name.
  final Map<String, EmberScene> scenes = {};

  /// Custom user scripts stored in the project (filename -> source code).
  final Map<String, String> scripts = {};

  /// Custom project asset metadata or paths.
  final List<String> assets = [];

  EmberProject({
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.author = 'Ember Developer',
    this.description = 'Created with Ember Engine',
    this.renderPipeline = RenderPipelineMode.hybrid,
    DateTime? createdAt,
    DateTime? lastModified,
    this.defaultSceneName = 'MainScene',
    String? path,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastModified = lastModified ?? DateTime.now(),
        path = path ?? 'projects/${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_')}';

  /// Returns the default active scene for this project.
  EmberScene get activeScene {
    if (scenes.containsKey(defaultSceneName)) {
      return scenes[defaultSceneName]!;
    }
    if (scenes.isNotEmpty) {
      return scenes.values.first;
    }
    final fallback = renderPipeline == RenderPipelineMode.twoD
        ? EmberScene.createDefault2DScene()
        : EmberScene.createDefault3DScene();
    scenes[defaultSceneName] = fallback;
    return fallback;
  }

  /// Serializes project manifest to JSON.
  Map<String, dynamic> toJson() {
    final serializedScenes = <String, dynamic>{};
    for (final entry in scenes.entries) {
      serializedScenes[entry.key] = SceneSerializer.serializeScene(entry.value);
    }

    return {
      'id': id,
      'name': name,
      'path': path,
      'version': version,
      'author': author,
      'description': description,
      'renderPipeline': renderPipeline.name,
      'createdAt': createdAt.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
      'defaultSceneName': defaultSceneName,
      'scenes': serializedScenes,
      'scripts': scripts,
      'assets': assets,
    };
  }

  /// Deserializes project manifest from JSON.
  factory EmberProject.fromJson(Map<String, dynamic> json) {
    final pipelineName = json['renderPipeline'] as String? ?? 'hybrid';
    final pipeline = RenderPipelineMode.values.firstWhere(
      (p) => p.name == pipelineName,
      orElse: () => RenderPipelineMode.hybrid,
    );

    final project = EmberProject(
      id: json['id'] as String? ?? 'proj_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Untitled Ember Project',
      path: json['path'] as String?,
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? 'Ember Developer',
      description: json['description'] as String? ?? '',
      renderPipeline: pipeline,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      lastModified: json['lastModified'] != null ? DateTime.tryParse(json['lastModified'] as String) : null,
      defaultSceneName: json['defaultSceneName'] as String? ?? 'MainScene',
    );

    // Restore scenes
    if (json['scenes'] is Map) {
      final sceneMap = json['scenes'] as Map<String, dynamic>;
      for (final entry in sceneMap.entries) {
        if (entry.value is String) {
          project.scenes[entry.key] = SceneSerializer.deserializeScene(
            entry.value as String,
          );
        } else if (entry.value is Map) {
          project.scenes[entry.key] = SceneSerializer.deserializeSceneFromMap(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    // Restore scripts
    if (json['scripts'] is Map) {
      final scriptMap = json['scripts'] as Map<String, dynamic>;
      for (final entry in scriptMap.entries) {
        project.scripts[entry.key] = entry.value.toString();
      }
    }

    // Restore assets
    if (json['assets'] is List) {
      project.assets.addAll((json['assets'] as List).map((e) => e.toString()));
    }

    return project;
  }
}

/// Metadata item for recent projects in the Startup Hub.
class RecentProjectInfo {
  final String id;
  final String name;
  final String path;
  final String templateName;
  final RenderPipelineMode renderPipeline;
  final DateTime lastOpened;
  final bool isPinned;
  final String? previewSnippet;

  const RecentProjectInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.templateName,
    required this.renderPipeline,
    required this.lastOpened,
    this.isPinned = false,
    this.previewSnippet,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'templateName': templateName,
        'renderPipeline': renderPipeline.name,
        'lastOpened': lastOpened.toIso8601String(),
        'isPinned': isPinned,
        'previewSnippet': previewSnippet,
      };

  factory RecentProjectInfo.fromJson(Map<String, dynamic> json) {
    final pipelineName = json['renderPipeline'] as String? ?? 'hybrid';
    final pipeline = RenderPipelineMode.values.firstWhere(
      (p) => p.name == pipelineName,
      orElse: () => RenderPipelineMode.hybrid,
    );

    return RecentProjectInfo(
      id: json['id'] as String? ?? 'recent_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Untitled Project',
      path: json['path'] as String? ?? 'projects/untitled',
      templateName: json['templateName'] as String? ?? 'Blank Canvas',
      renderPipeline: pipeline,
      lastOpened: json['lastOpened'] != null
          ? DateTime.tryParse(json['lastOpened'] as String) ?? DateTime.now()
          : DateTime.now(),
      isPinned: json['isPinned'] as bool? ?? false,
      previewSnippet: json['previewSnippet'] as String?,
    );
  }
}

/// Manages recent projects persistence and list querying.
class RecentProjectsManager {
  static final RecentProjectsManager _instance = RecentProjectsManager._();
  static RecentProjectsManager get instance => _instance;
  RecentProjectsManager._();

  final List<RecentProjectInfo> _recentProjects = [];

  /// Where the list is persisted; null keeps it in memory only (e.g. in tests).
  File? _storageFile;

  List<RecentProjectInfo> get recentProjects => List.unmodifiable(_recentProjects);

  /// Loads the saved list from [file] and persists every later change to it.
  Future<void> attachStorage(File file) async {
    _storageFile = file;
    if (await file.exists()) {
      deserialize(await file.readAsString());
    }
  }

  Future<void> _pendingWrite = Future.value();

  /// Queues a write of the current list; writes never overlap on the same file.
  void _persist() {
    final file = _storageFile;
    if (file == null) return;
    final snapshot = serialize();
    _pendingWrite = _pendingWrite
        .then((_) => file.writeAsString(snapshot, flush: true))
        .then((_) {}, onError: (Object _) {});
  }

  /// Completes once every queued write has reached disk.
  Future<void> flush() => _pendingWrite;

  void addOrUpdateRecent(RecentProjectInfo info) {
    _recentProjects.removeWhere((p) => p.id == info.id || p.path == info.path);
    _recentProjects.insert(0, info);
    if (_recentProjects.length > 25) {
      _recentProjects.removeLast();
    }
    _persist();
  }

  void removeRecent(String id) {
    _recentProjects.removeWhere((p) => p.id == id);
    _persist();
  }

  void togglePin(String id) {
    final index = _recentProjects.indexWhere((p) => p.id == id);
    if (index != -1) {
      final item = _recentProjects[index];
      _recentProjects[index] = RecentProjectInfo(
        id: item.id,
        name: item.name,
        path: item.path,
        templateName: item.templateName,
        renderPipeline: item.renderPipeline,
        lastOpened: item.lastOpened,
        isPinned: !item.isPinned,
        previewSnippet: item.previewSnippet,
      );
      _persist();
    }
  }

  List<RecentProjectInfo> search(String query) {
    if (query.trim().isEmpty) return recentProjects;
    final q = query.toLowerCase();
    return _recentProjects
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.templateName.toLowerCase().contains(q) ||
            p.path.toLowerCase().contains(q))
        .toList();
  }

  String serialize() {
    return jsonEncode(_recentProjects.map((p) => p.toJson()).toList());
  }

  void deserialize(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr);
      if (list is List) {
        _recentProjects.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _recentProjects.add(RecentProjectInfo.fromJson(item));
          }
        }
      }
    } catch (_) {
      // Corrupt file: start with an empty list rather than failing to launch.
    }
  }
}

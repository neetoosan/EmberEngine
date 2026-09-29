import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../../core/scene_serializer.dart';
import 'project_manifest.dart';

/// Reads and writes Ember projects as folders on disk:
///
/// ```text
/// MyGame/
///   project.ember.json      manifest (name, pipeline, scene + script index)
///   scenes/MainScene.scene  one JSON file per scene
///   scripts/*.dart          script sources written in the in-engine editor
/// ```
class ProjectStorage {
  static const String manifestFileName = 'project.ember.json';
  static const String scenesDirName = 'scenes';
  static const String scriptsDirName = 'scripts';
  static const String sceneExtension = '.scene';

  /// Filesystem projects need dart:io, which the web build does not have.
  static bool get isSupported => !kIsWeb;

  /// Whether [project] already lives in a real folder (vs. a fresh in-memory template).
  static bool hasDiskLocation(EmberProject project) =>
      isSupported && File(project.path).isAbsolute && Directory(project.path).existsSync();

  /// `<Documents>/EmberProjects`, created on first use.
  static Future<Directory> defaultProjectsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(_join(docs.path, 'EmberProjects'));
    await dir.create(recursive: true);
    return dir;
  }

  /// A folder name derived from [name] that does not exist yet under [root].
  static Future<String> allocateProjectPath(String name, {Directory? root}) async {
    final parent = root ?? await defaultProjectsRoot();
    final base = slug(name);
    var candidate = _join(parent.path, base);
    for (var i = 2; await Directory(candidate).exists(); i++) {
      candidate = _join(parent.path, '${base}_$i');
    }
    return candidate;
  }

  static String slug(String name) {
    final s = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '').replaceAll(RegExp(r'\s+'), '_');
    return s.isEmpty ? 'EmberProject' : s;
  }

  /// Writes the whole project into [EmberProject.path] (created if needed).
  static Future<void> save(EmberProject project) async {
    final dir = Directory(project.path);
    await Directory(_join(dir.path, scenesDirName)).create(recursive: true);
    project.lastModified = DateTime.now();

    final sceneFiles = <String, String>{};
    for (final entry in project.scenes.entries) {
      final fileName = '${slug(entry.key)}$sceneExtension';
      sceneFiles[entry.key] = '$scenesDirName/$fileName';
      await _writeAtomic(
        _join(dir.path, scenesDirName, fileName),
        SceneSerializer.serializeScene(entry.value),
      );
    }

    final scriptFiles = <String>[];
    if (project.scripts.isNotEmpty) {
      await Directory(_join(dir.path, scriptsDirName)).create(recursive: true);
      for (final entry in project.scripts.entries) {
        final fileName = entry.key.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        scriptFiles.add('$scriptsDirName/$fileName');
        await _writeAtomic(_join(dir.path, scriptsDirName, fileName), entry.value);
      }
    }

    await _copyBundledAssets(project, dir.path);

    final manifest = {
      'format': 'EmberProject',
      'formatVersion': 1,
      'id': project.id,
      'name': project.name,
      'version': project.version,
      'author': project.author,
      'description': project.description,
      'renderPipeline': project.renderPipeline.name,
      'createdAt': project.createdAt.toIso8601String(),
      'lastModified': project.lastModified.toIso8601String(),
      'defaultSceneName': project.defaultSceneName,
      'scenes': sceneFiles,
      'scripts': scriptFiles,
      'assets': project.assets,
    };
    await _writeAtomic(
      _join(dir.path, manifestFileName),
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
  }

  /// Loads a project from its folder, or from the path of its manifest file.
  static Future<EmberProject> load(String folderOrManifest) async {
    final dirPath = folderOrManifest.endsWith(manifestFileName)
        ? File(folderOrManifest).parent.path
        : folderOrManifest;
    final manifestFile = File(_join(dirPath, manifestFileName));
    if (!await manifestFile.exists()) {
      throw FileSystemException('No $manifestFileName in this folder', dirPath);
    }

    final json = jsonDecode(await manifestFile.readAsString());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Project manifest is not a JSON object');
    }

    final pipelineName = json['renderPipeline'] as String? ?? 'hybrid';
    final project = EmberProject(
      id: json['id'] as String? ?? 'proj_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Untitled Ember Project',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? 'Ember Developer',
      description: json['description'] as String? ?? '',
      renderPipeline: RenderPipelineMode.values.firstWhere(
        (p) => p.name == pipelineName,
        orElse: () => RenderPipelineMode.hybrid,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      lastModified: DateTime.tryParse(json['lastModified'] as String? ?? ''),
      defaultSceneName: json['defaultSceneName'] as String? ?? 'MainScene',
      path: dirPath,
    );

    final scenes = json['scenes'];
    if (scenes is Map) {
      for (final entry in scenes.entries) {
        final file = File(_join(dirPath, entry.value.toString()));
        if (await file.exists()) {
          project.scenes[entry.key.toString()] = SceneSerializer.deserializeScene(await file.readAsString());
        }
      }
    }

    final scripts = json['scripts'];
    if (scripts is List) {
      for (final rel in scripts) {
        final file = File(_join(dirPath, rel.toString()));
        if (await file.exists()) {
          project.scripts[file.uri.pathSegments.last] = await file.readAsString();
        }
      }
    }

    final assets = json['assets'];
    if (assets is List) {
      project.assets.addAll(assets.map((e) => e.toString()));
    }
    return project;
  }

  /// Every `assets/...` path referenced anywhere in the project's scenes.
  static Set<String> referencedAssetPaths(EmberProject project) {
    final found = <String>{};
    void scan(Object? node) {
      if (node is String) {
        if (node.startsWith('assets/')) found.add(node);
      } else if (node is Map) {
        node.values.forEach(scan);
      } else if (node is List) {
        node.forEach(scan);
      }
    }

    for (final scene in project.scenes.values) {
      scan(scene.toJson());
    }
    return found;
  }

  /// Copies engine-bundled files (built-in template art) that the project uses
  /// but does not have yet, so the project folder is self-contained.
  static Future<void> _copyBundledAssets(EmberProject project, String dirPath) async {
    // Scene references plus files only scripts use (listed in project.assets)
    final paths = {...referencedAssetPaths(project), ...project.assets.where((a) => a.startsWith('assets/'))};
    for (final rel in paths) {
      final target = File(_join(dirPath, rel.replaceAll('/', Platform.pathSeparator)));
      if (await target.exists()) continue;
      try {
        final data = await rootBundle.load(rel);
        await target.parent.create(recursive: true);
        await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
      } catch (_) {
        // Not a bundled asset (e.g. a user file that was moved); leave it to the user.
      }
    }
  }

  /// Writes to a temp file first so a crash mid-save never leaves a half-written file.
  static Future<void> _writeAtomic(String path, String contents) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(path);
  }

  static String _join(String a, [String? b, String? c]) {
    final sep = Platform.pathSeparator;
    var out = a;
    for (final part in [b, c]) {
      if (part == null) continue;
      out = out.endsWith(sep) || out.endsWith('/') ? '$out$part' : '$out$sep$part';
    }
    return out;
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'project_manifest.dart';

/// Single-file archive manager for portable `.emberpkg` bundles.
///
/// Encapsulates project manifest, serialized scenes, custom scripts,
/// and asset manifests into a versioned, portable JSON package.
class ProjectPackageManager {
  static const String packageVersion = '1.0.0';
  static const String packageSignature = 'EMBER_ENGINE_PROJECT_PACKAGE';

  /// Serializes an [EmberProject] into a `.emberpkg` package JSON string.
  ///
  /// [files] (project-relative path -> bytes: the project's images and
  /// sounds) are embedded so the package is a complete, self-contained game —
  /// used for web and Android, where there is no folder next to the game.
  static String exportToPackageString(EmberProject project, {Map<String, Uint8List>? files}) {
    final manifestData = project.toJson();
    final packagePayload = {
      'signature': packageSignature,
      'pkgVersion': packageVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'project': manifestData,
      'checksum': _computeChecksum(manifestData.toString()),
      if (files != null && files.isNotEmpty) 'files': {for (final e in files.entries) e.key: base64Encode(e.value)},
    };

    return files == null || files.isEmpty
        ? const JsonEncoder.withIndent('  ').convert(packagePayload)
        : jsonEncode(packagePayload); // compact: embedded files make it large
  }

  /// A package's project plus its embedded files (empty if none).
  static (EmberProject, Map<String, Uint8List>) importWithFiles(String packageJsonStr) {
    final project = importFromPackageString(packageJsonStr);
    final decoded = jsonDecode(packageJsonStr) as Map<String, dynamic>;
    final raw = decoded['files'];
    final files = <String, Uint8List>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        files['${e.key}'] = base64Decode('${e.value}');
      }
    }
    return (project, files);
  }

  /// Deserializes a `.emberpkg` package JSON string into an [EmberProject].
  static EmberProject importFromPackageString(String packageJsonStr) {
    final decoded = jsonDecode(packageJsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid .emberpkg format: root must be a JSON object');
    }

    final sig = decoded['signature'] as String?;
    if (sig != packageSignature) {
      throw const FormatException('Invalid package signature: not an Ember Engine package');
    }

    final projectMap = decoded['project'];
    if (projectMap is! Map) {
      throw const FormatException('Invalid .emberpkg: missing project payload');
    }

    return EmberProject.fromJson(Map<String, dynamic>.from(projectMap));
  }

  /// Alias for exportToPackageString.
  static String exportProjectToPackage(EmberProject project) => exportToPackageString(project);

  /// Alias for importFromPackageString.
  static EmberProject importProjectFromPackage(String packageJsonStr) => importFromPackageString(packageJsonStr);

  /// Computes a lightweight deterministic hash checksum for package verification.
  static int _computeChecksum(String data) {
    var hash = 5381;
    for (var i = 0; i < data.length; i++) {
      hash = ((hash << 5) + hash) + data.codeUnitAt(i);
      hash = hash & 0x7FFFFFFF;
    }
    return hash;
  }
}

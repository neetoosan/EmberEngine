import 'dart:io';
import '../../core/assets.dart';

/// Lists and imports the files in the open project's `assets/` folder.
class ProjectAssets {
  static const Set<String> imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'};
  static const Set<String> audioExtensions = {'wav', 'mp3', 'ogg'};

  static String extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }

  static bool isImage(String path) => imageExtensions.contains(extensionOf(path));
  static bool isAudio(String path) => audioExtensions.contains(extensionOf(path));

  /// Project-relative paths (`assets/...`, forward slashes) of every file in
  /// the project's assets folder, optionally limited to [extensions].
  static List<String> list({Set<String>? extensions}) {
    final root = EmberAssets.instance.root;
    if (root == null) return const [];
    final dir = Directory('$root${Platform.pathSeparator}assets');
    if (!dir.existsSync()) return const [];
    final out = <String>[];
    for (final f in dir.listSync(recursive: true)) {
      if (f is! File) continue;
      final rel = f.path.substring(root.length + 1).replaceAll('\\', '/');
      if (extensions == null || extensions.contains(extensionOf(rel))) out.add(rel);
    }
    out.sort();
    return out;
  }

  /// Copies [sourcePath] into `assets/<subfolder>/` of the open project and
  /// returns its project-relative path. Null when no project folder is open.
  static Future<String?> importFile(String sourcePath, {String? subfolder}) async {
    final root = EmberAssets.instance.root;
    if (root == null) return null;
    final sep = Platform.pathSeparator;
    final name = File(sourcePath).uri.pathSegments.last;
    final folder = subfolder ?? (isImage(name) ? 'sprites' : isAudio(name) ? 'audio' : 'misc');
    final dest = File('$root${sep}assets$sep$folder$sep$name');
    await dest.parent.create(recursive: true);
    await File(sourcePath).copy(dest.path);
    final rel = 'assets/$folder/$name';
    EmberAssets.instance.invalidate(rel);
    return rel;
  }
}

import 'dart:io';
import 'project_manifest.dart';
import 'project_package.dart';

/// Packages a project as a standalone game.
///
/// A standalone game is the *player runtime* (this repo built with
/// `lib/main_player.dart` as the entry point, no editor UI) plus a
/// `game.emberpkg.json` file next to its executable. The runtime loads that
/// file on start-up, so one runtime build can ship any number of games.
class GameExporter {
  /// The game file the player runtime looks for beside its executable.
  static const String gameFileName = 'game.emberpkg.json';

  /// Where [buildPlayerRuntime] leaves the runtime inside the engine repo.
  static const String runtimeDirName = 'build/player_runtime';

  /// Executable name produced by `flutter build` (CMake BINARY_NAME).
  static const String runtimeExeBase = 'ember_engine';

  /// The engine source checkout, when the editor was started from it
  /// (e.g. with `flutter run`). Needed to build the runtime from the editor.
  static Directory? findEngineRepo() {
    Directory dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
      if (pubspec.existsSync() && pubspec.readAsStringSync().contains('name: ember_engine')) {
        return dir;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  /// A previously built player runtime, if one exists.
  static Directory? findPlayerRuntime() {
    final fromEnv = Platform.environment['EMBER_PLAYER_RUNTIME'];
    if (fromEnv != null && _isRuntime(Directory(fromEnv))) return Directory(fromEnv);
    final repo = findEngineRepo();
    if (repo == null) return null;
    final dir = Directory('${repo.path}${Platform.pathSeparator}${runtimeDirName.replaceAll('/', Platform.pathSeparator)}');
    return _isRuntime(dir) ? dir : null;
  }

  static bool _isRuntime(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}$_exeName').existsSync();

  static String get _exeName => Platform.isWindows ? '$runtimeExeBase.exe' : runtimeExeBase;

  static String get _platformTarget {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'linux';
  }

  static String _buildOutputPath(Directory repo) {
    final sep = Platform.pathSeparator;
    if (Platform.isWindows) return '${repo.path}${sep}build${sep}windows${sep}x64${sep}runner${sep}Release';
    if (Platform.isLinux) return '${repo.path}${sep}build${sep}linux${sep}x64${sep}release${sep}bundle';
    return '${repo.path}${sep}build${sep}macos${sep}Build${sep}Products${sep}Release';
  }

  /// The shell command that builds the runtime, for showing to the user.
  static String get buildCommand =>
      'flutter build $_platformTarget --release -t lib/main_player.dart';

  /// Builds the player runtime with Flutter and copies it to [runtimeDirName].
  /// Streams build output through [onLog]. Returns the runtime folder.
  static Future<Directory> buildPlayerRuntime({void Function(String line)? onLog}) async {
    final repo = findEngineRepo();
    if (repo == null) {
      throw StateError('Engine source folder not found. Start the editor from the repo, '
          'or build the runtime manually with: $buildCommand');
    }
    onLog?.call('> $buildCommand');
    final process = await Process.start(
      'flutter',
      ['build', _platformTarget, '--release', '-t', 'lib/main_player.dart'],
      workingDirectory: repo.path,
      runInShell: true,
    );
    process.stdout.transform(const SystemEncoding().decoder).listen((s) => onLog?.call(s.trimRight()));
    process.stderr.transform(const SystemEncoding().decoder).listen((s) => onLog?.call(s.trimRight()));
    final code = await process.exitCode;
    if (code != 0) throw ProcessException('flutter', ['build'], 'Build failed (exit code $code)', code);

    final target = Directory('${repo.path}${Platform.pathSeparator}${runtimeDirName.replaceAll('/', Platform.pathSeparator)}');
    if (await target.exists()) await target.delete(recursive: true);
    await _copyDirectory(Directory(_buildOutputPath(repo)), target);
    onLog?.call('Player runtime ready: ${target.path}');
    return target;
  }

  /// Writes a standalone copy of [project] into `<outputParent>/<GameName>/`
  /// and returns the path of the game executable.
  static Future<String> export({
    required EmberProject project,
    required Directory runtime,
    required String outputParent,
  }) async {
    final sep = Platform.pathSeparator;
    final gameName = project.name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    final safeName = gameName.isEmpty ? 'EmberGame' : gameName;
    final outDir = Directory('$outputParent$sep$safeName');
    if (await outDir.exists()) await outDir.delete(recursive: true);
    await _copyDirectory(runtime, outDir);

    // Rename the runtime executable after the game (also sets the window title on Windows).
    var exePath = '${outDir.path}$sep$_exeName';
    final ext = Platform.isWindows ? '.exe' : '';
    final renamed = '${outDir.path}$sep$safeName$ext';
    if (await File(exePath).exists()) {
      await File(exePath).rename(renamed);
      exePath = renamed;
    }

    await File('${outDir.path}$sep$gameFileName')
        .writeAsString(ProjectPackageManager.exportToPackageString(project), flush: true);

    // Images, audio and other project files the game loads at runtime
    final assets = Directory('${project.path}${sep}assets');
    if (await assets.exists()) {
      await _copyDirectory(assets, Directory('${outDir.path}${sep}assets'));
    }
    return exePath;
  }

  static Future<void> _copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(recursive: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final dest = '${to.path}${Platform.pathSeparator}$name';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(dest));
      } else if (entity is File) {
        await entity.copy(dest);
      }
    }
  }
}

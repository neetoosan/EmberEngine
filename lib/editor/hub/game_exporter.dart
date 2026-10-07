import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

  // ---------------------------------------------------------------------------
  // Web

  /// Where [buildWebRuntime] leaves the web player inside the engine repo.
  static const String webRuntimeDirName = 'build/player_runtime_web';

  /// Where the game package goes inside the web player (the Flutter asset key
  /// `assets/game/game.emberpkg.json` is served from `assets/assets/game/`).
  static const String webGamePath = 'assets/assets/game/$gameFileName';

  static String get webBuildCommand => 'flutter build web --release -t lib/main_player.dart';

  /// A previously built web player, if one exists.
  static Directory? findWebRuntime() {
    final fromEnv = Platform.environment['EMBER_WEB_RUNTIME'];
    if (fromEnv != null && File(_join(fromEnv, 'index.html')).existsSync()) return Directory(fromEnv);
    final repo = findEngineRepo();
    if (repo == null) return null;
    final dir = Directory(_join(repo.path, webRuntimeDirName));
    return File(_join(dir.path, 'index.html')).existsSync() ? dir : null;
  }

  /// Builds the web player once and keeps it in [webRuntimeDirName].
  static Future<Directory> buildWebRuntime({void Function(String line)? onLog}) async {
    final repo = findEngineRepo();
    if (repo == null) {
      throw StateError('Engine source folder not found. Build the web player manually with: $webBuildCommand');
    }
    await _runFlutter(repo, ['build', 'web', '--release', '-t', 'lib/main_player.dart'], onLog: onLog);
    final target = Directory(_join(repo.path, webRuntimeDirName));
    if (await target.exists()) await target.delete(recursive: true);
    await _copyDirectory(Directory(_join(repo.path, 'build', 'web')), target);
    onLog?.call('Web player ready: ${target.path}');
    return target;
  }

  /// Writes a web version of [project] into `<outputParent>/<GameName>-web/`:
  /// the web player plus the game package (with its images and sounds inside).
  /// Upload the folder to any static web host. Returns the folder path.
  static Future<String> exportWeb({
    required EmberProject project,
    required Directory runtime,
    required String outputParent,
  }) async {
    final outDir = Directory(_join(outputParent, '${safeName(project.name)}-web'));
    if (await outDir.exists()) await outDir.delete(recursive: true);
    await _copyDirectory(runtime, outDir);

    // Relative base, so the game works in any sub-folder (itch.io, GitHub Pages)
    final index = File(_join(outDir.path, 'index.html'));
    await index.writeAsString((await index.readAsString())
        .replaceFirst(RegExp(r'<base href="[^"]*">'), '<base href="./">')
        .replaceFirst(RegExp(r'<title>[^<]*</title>'), '<title>${_htmlEscape(project.name)}</title>')
        .replaceFirst(RegExp(r'<meta name="apple-mobile-web-app-title" content="[^"]*">'),
            '<meta name="apple-mobile-web-app-title" content="${_htmlEscape(project.name)}">'));

    // "Install app" in the browser uses the game's name, not the engine's
    final manifest = File(_join(outDir.path, 'manifest.json'));
    if (await manifest.exists()) {
      try {
        final m = (jsonDecode(await manifest.readAsString()) as Map).cast<String, dynamic>();
        m['name'] = project.name;
        m['short_name'] = project.name.length > 12 ? project.name.substring(0, 12).trim() : project.name;
        m['description'] = '${project.name} (made with Ember Engine)';
        await manifest.writeAsString(const JsonEncoder.withIndent('  ').convert(m));
      } catch (_) {} // a hand-edited manifest is left as it is
    }

    final game = File(_join(outDir.path, webGamePath));
    await game.parent.create(recursive: true);
    await game.writeAsString(ProjectPackageManager.exportToPackageString(project, files: await collectProjectFiles(project)));

    await File(_join(outDir.path, 'play-locally.ps1')).writeAsString(_localServerScript);
    await File(_join(outDir.path, 'README.txt')).writeAsString(
      '${project.name} - web version (Ember Engine)\r\n\r\n'
      'Upload this whole folder to a web host (itch.io "HTML" game, GitHub Pages, Netlify...)\r\n'
      'and open index.html there. Browsers do not run it straight from the disk.\r\n\r\n'
      'To try it on this computer: right-click play-locally.ps1 > Run with PowerShell,\r\n'
      'then it opens http://localhost:8123/ in your browser.\r\n',
    );
    return outDir.path;
  }

  // ---------------------------------------------------------------------------
  // Android

  /// Builds an Android APK of [project] (with its own name and app id, so
  /// several games install side by side) into `<outputParent>/<GameName>.apk`.
  /// Needs the engine source folder and the Android SDK; takes a few minutes.
  static Future<String> exportAndroid({
    required EmberProject project,
    required String outputParent,
    void Function(String line)? onLog,
  }) async {
    final repo = findEngineRepo();
    if (repo == null) {
      throw StateError('Android export needs the engine source folder (start the editor from it) and the Android SDK.');
    }
    final staged = File(_join(repo.path, 'assets', 'game', gameFileName));
    await staged.parent.create(recursive: true);
    await staged.writeAsString(ProjectPackageManager.exportToPackageString(project, files: await collectProjectFiles(project)));
    try {
      final appId = androidAppId(project.name);
      onLog?.call('App id: $appId');
      await _runFlutter(
        repo,
        ['build', 'apk', '--release', '-t', 'lib/main_player.dart'],
        environment: {'EMBER_APP_ID': appId, 'EMBER_APP_NAME': project.name},
        onLog: onLog,
      );
      final apk = File(_join(repo.path, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'));
      if (!await apk.exists()) throw StateError('The build finished but no APK was found at ${apk.path}');
      await Directory(outputParent).create(recursive: true);
      final out = _join(outputParent, '${safeName(project.name)}.apk');
      await apk.copy(out);
      return out;
    } finally {
      // The engine's own builds must not ship this game: remove the staged file and
      // the copies Gradle / Flutter keep in their incremental build folders.
      if (await staged.exists()) await staged.delete();
      await removeStagedGameCopies(repo);
    }
  }

  /// Deletes copies of a staged Android game left in the repo's build folders.
  static Future<void> removeStagedGameCopies(Directory repo) async {
    final build = Directory(_join(repo.path, 'build'));
    if (!await build.exists()) return;
    final sep = Platform.pathSeparator;
    await for (final e in build.list(recursive: true, followLinks: false)) {
      if (e is File &&
          e.path.endsWith('${sep}assets${sep}game$sep$gameFileName') &&
          !e.path.contains('${sep}player_runtime')) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }

  /// A valid, stable Android application id for a game name.
  static String androidAppId(String name) {
    var s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    if (s.isEmpty) s = 'game';
    if (!RegExp(r'^[a-z]').hasMatch(s)) s = 'g_$s';
    return 'com.embergames.$s';
  }

  // ---------------------------------------------------------------------------
  // Shared

  static String safeName(String name) {
    final s = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    return s.isEmpty ? 'EmberGame' : s;
  }

  /// The project's own files (images, sounds) by project-relative path, for
  /// embedding in the game package. Built-in template art is in the player already.
  static Future<Map<String, Uint8List>> collectProjectFiles(EmberProject project) async {
    final files = <String, Uint8List>{};
    final root = project.path;
    if (root.isEmpty) return files;
    final assets = Directory(_join(root, 'assets'));
    if (!await assets.exists()) return files;
    await for (final entity in assets.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = entity.path.substring(root.length + 1).replaceAll(Platform.pathSeparator, '/');
      files[rel] = await entity.readAsBytes();
    }
    return files;
  }

  static Future<void> _runFlutter(
    Directory repo,
    List<String> args, {
    Map<String, String>? environment,
    void Function(String line)? onLog,
  }) async {
    onLog?.call('> flutter ${args.join(' ')}');
    final process = await Process.start('flutter', args, workingDirectory: repo.path, runInShell: true, environment: environment);
    process.stdout.transform(const SystemEncoding().decoder).listen((s) => onLog?.call(s.trimRight()));
    process.stderr.transform(const SystemEncoding().decoder).listen((s) => onLog?.call(s.trimRight()));
    final code = await process.exitCode;
    if (code != 0) throw ProcessException('flutter', args, 'Build failed (exit code $code)', code);
  }

  static String _join(String a, [String? b, String? c, String? d, String? e, String? f]) {
    final sep = Platform.pathSeparator;
    return [a, ?b, ?c, ?d, ?e, ?f].map((p) => p.replaceAll('/', sep)).join(sep);
  }

  static String _htmlEscape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// Serves the exported web game on http://localhost:8123/ (no installs needed).
  static const String _localServerScript = r'''
# Serves this folder on http://localhost:8123/ and opens the browser. Close the window to stop.
$root = $PSScriptRoot
$port = 8123
$types = @{ '.html'='text/html'; '.js'='text/javascript'; '.mjs'='text/javascript'; '.wasm'='application/wasm';
  '.json'='application/json'; '.png'='image/png'; '.jpg'='image/jpeg'; '.wav'='audio/wav'; '.mp3'='audio/mpeg';
  '.ogg'='audio/ogg'; '.css'='text/css'; '.ttf'='font/ttf'; '.otf'='font/otf'; '.ico'='image/x-icon'; '.bin'='application/octet-stream' }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "Playing at http://localhost:$port/  (close this window to stop)"
Start-Process "http://localhost:$port/"
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
  if ($path -eq '') { $path = 'index.html' }
  $file = Join-Path $root $path
  if ((Test-Path $file -PathType Leaf) -and ((Resolve-Path $file).Path.StartsWith($root))) {
    $bytes = [System.IO.File]::ReadAllBytes($file)
    $ext = [System.IO.Path]::GetExtension($file).ToLower()
    $ctx.Response.ContentType = $(if ($types[$ext]) { $types[$ext] } else { 'application/octet-stream' })
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  } else {
    $ctx.Response.StatusCode = 404
  }
  $ctx.Response.Close()
}
''';

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

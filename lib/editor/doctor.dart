import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/assets.dart';
import '../core/crash_reporter.dart';
import '../core/game_script.dart';
import '../core/version.dart';
import '../scripting/script_library.dart';
import 'hub/game_exporter.dart';

/// Result of one Doctor check.
enum HealthStatus {
  passed('Passed', Colors.greenAccent, Icons.check_circle_rounded),
  warning('Warning', Colors.amberAccent, Icons.warning_amber_rounded),
  failed('Problem', Colors.redAccent, Icons.error_outline_rounded),
  info('Info', Color(0xFF93C5FD), Icons.info_outline_rounded);

  final String label;
  final Color color;
  final IconData icon;
  const HealthStatus(this.label, this.color, this.icon);
}

/// One line of the Doctor's report, optionally with a button that fixes or opens the problem.
class DiagnosticReportItem {
  final String title;
  final String category;
  final HealthStatus status;
  final String details;
  final String? recommendation;
  final String? actionLabel;
  final VoidCallback? action;

  const DiagnosticReportItem({
    required this.title,
    required this.category,
    required this.status,
    required this.details,
    this.recommendation,
    this.actionLabel,
    this.action,
  });
}

/// What the Doctor looks at: the project as it would be saved right now.
class DoctorInput {
  final String projectName;
  final String projectPath;
  final String startScene;
  final Map<String, Map<String, dynamic>> scenes;
  final Map<String, String> scripts;
  final bool hasUnsavedChanges;

  const DoctorInput({
    required this.projectName,
    this.projectPath = '',
    required this.startScene,
    required this.scenes,
    required this.scripts,
    this.hasUnsavedChanges = false,
  });

  /// From the map produced by `ProjectSession.contentOf`.
  factory DoctorInput.fromContent(Map<String, dynamic> content, {String projectPath = '', bool hasUnsavedChanges = false}) => DoctorInput(
        projectName: content['name'] as String? ?? 'Project',
        projectPath: projectPath,
        startScene: content['start'] as String? ?? '',
        scenes: {for (final e in (content['scenes'] as Map).entries) '${e.key}': (e.value as Map).cast<String, dynamic>()},
        scripts: (content['scripts'] as Map).map((k, v) => MapEntry('$k', '$v')),
        hasUnsavedChanges: hasUnsavedChanges,
      );
}

/// Real checks of a project and of this machine's export setup. Every line
/// it reports comes from something it actually looked at.
class ProjectDoctor {
  ProjectDoctor._();

  /// Sprite path used when no image was picked (drawn as a placeholder box on purpose).
  static const String placeholderSprite = 'assets/sprites/default_character.png';

  /// Runs every check. [onOpenScript] and [onSave] become "fix" buttons.
  /// [assetExists] and [checkExports] are replaceable for tests.
  static Future<List<DiagnosticReportItem>> run(
    DoctorInput input, {
    void Function(String file)? onOpenScript,
    VoidCallback? onSave,
    Future<bool> Function(String path)? assetExists,
    bool checkExports = !kIsWeb,
  }) async {
    final items = <DiagnosticReportItem>[
      DiagnosticReportItem(
        title: 'Engine',
        category: 'About',
        status: HealthStatus.info,
        details: '${EmberVersion.displayName} · ${CrashReporter.systemSummary()}',
      ),
      _startScene(input),
      ..._scriptCompile(input, onOpenScript),
      ?_runtimeErrors(onOpenScript),
      _scriptReferences(input),
      _sceneLinks(input),
      await _assets(input, assetExists ?? _defaultAssetExists(input.projectPath)),
      _saved(input, onSave),
      if (checkExports) ..._exports(),
    ];
    return items;
  }

  /// Share of real checks that passed (info lines don't count).
  static double score(List<DiagnosticReportItem> items) {
    final judged = items.where((i) => i.status != HealthStatus.info).toList();
    if (judged.isEmpty) return 1;
    return judged.where((i) => i.status == HealthStatus.passed).length / judged.length;
  }

  // ---------------------------------------------------------------------------

  static DiagnosticReportItem _startScene(DoctorInput input) => input.scenes.containsKey(input.startScene)
      ? DiagnosticReportItem(
          title: 'Start scene',
          category: 'Scenes',
          status: HealthStatus.passed,
          details: '"${input.startScene}" opens first (${input.scenes.length} scene${input.scenes.length == 1 ? '' : 's'} in the project).',
        )
      : DiagnosticReportItem(
          title: 'Start scene',
          category: 'Scenes',
          status: HealthStatus.failed,
          details: 'The start scene "${input.startScene}" does not exist, so an exported game would not know where to begin.',
          recommendation: 'Open a scene and choose "Set as start scene" in the scene menu.',
        );

  static List<DiagnosticReportItem> _scriptCompile(DoctorInput input, void Function(String file)? onOpenScript) {
    final ember = input.scripts.entries.where((e) => EmberScripts.isScriptFile(e.key)).toList();
    final errors = <ScriptProblem>[];
    for (final e in ember) {
      final p = EmberScripts.check(e.key, e.value);
      if (p != null) errors.add(p);
    }
    final notes = input.scripts.keys.where((f) => f.endsWith('.dart')).toList();
    return [
      if (errors.isEmpty)
        DiagnosticReportItem(
          title: 'Scripts compile',
          category: 'Scripts',
          status: HealthStatus.passed,
          details: ember.isEmpty ? 'No Ember Scripts in this project.' : 'All ${ember.length} Ember Script file${ember.length == 1 ? '' : 's'} compile.',
        )
      else
        DiagnosticReportItem(
          title: 'Scripts compile',
          category: 'Scripts',
          status: HealthStatus.failed,
          details: errors.take(3).map((p) => '${p.location}  ${p.message}').join('\n') +
              (errors.length > 3 ? '\n…and ${errors.length - 3} more' : ''),
          recommendation: 'A script with an error does not run. Fix the line shown (it is also marked in the Script workspace).',
          actionLabel: onOpenScript == null ? null : 'Open ${errors.first.file}',
          action: onOpenScript == null ? null : () => onOpenScript(errors.first.file),
        ),
      if (notes.isNotEmpty)
        DiagnosticReportItem(
          title: 'Dart note files',
          category: 'Scripts',
          status: HealthStatus.warning,
          details: '${notes.join(', ')} ${notes.length == 1 ? 'is' : 'are'} kept as notes only: .dart files do not run in Ember games.',
          recommendation: 'Move the logic into an Ember Script (.ember) and attach it with a Script Component.',
        ),
    ];
  }

  static DiagnosticReportItem? _runtimeErrors(void Function(String file)? onOpenScript) {
    final runtime = EmberScripts.instance.problems.where((p) => p.runtime).toList();
    if (runtime.isEmpty) return null;
    return DiagnosticReportItem(
      title: 'Errors during the last Play',
      category: 'Scripts',
      status: HealthStatus.warning,
      details: runtime.take(3).map((p) => '${p.location}  ${p.message}${p.count > 1 ? '  (×${p.count})' : ''}').join('\n'),
      recommendation: 'The game kept running, but these lines did not work. See Problems in the Script workspace.',
      actionLabel: onOpenScript == null ? null : 'Open ${runtime.first.file}',
      action: onOpenScript == null ? null : () => onOpenScript(runtime.first.file),
    );
  }

  /// Every Script Component names a script that exists.
  static DiagnosticReportItem _scriptReferences(DoctorInput input) {
    final missing = <String>{};
    _visitComponents(input, (scene, entity, type, data) {
      if (type != 'Script Component') return;
      final name = data['scriptName'] as String? ?? '';
      if (name.isEmpty || input.scripts.containsKey(name) || ScriptRegistry.isBuiltIn(name)) return;
      missing.add('$entity uses "$name" ($scene)');
    });
    return missing.isEmpty
        ? const DiagnosticReportItem(
            title: 'Script Components',
            category: 'Scripts',
            status: HealthStatus.passed,
            details: 'Every Script Component points to a script that exists.',
          )
        : DiagnosticReportItem(
            title: 'Script Components',
            category: 'Scripts',
            status: HealthStatus.failed,
            details: _list(missing),
            recommendation: 'Pick an existing script on these entities, or create the script in the Script workspace.',
          );
  }

  /// Buttons, doors and scripts only lead to scenes that exist.
  static DiagnosticReportItem _sceneLinks(DoctorInput input) {
    final broken = <String>{};
    void check(String target, String from) {
      if (target.isNotEmpty && !input.scenes.containsKey(target)) broken.add('$from → "$target"');
    }

    _visitComponents(input, (scene, entity, type, data) {
      if (type == 'UI Button') {
        final action = data['action'] as String? ?? '';
        if (action.startsWith('level:')) check(action.substring(6), '$entity button ($scene)');
      } else if (type == 'Door') {
        check(data['targetLevel'] as String? ?? '', '$entity door ($scene)');
      }
    });
    final call = RegExp(r'''loadLevel\(\s*["']([^"'$]+)["']''');
    for (final e in input.scripts.entries) {
      for (final m in call.allMatches(e.value)) {
        check(m.group(1)!, e.key);
      }
    }
    return broken.isEmpty
        ? const DiagnosticReportItem(
            title: 'Scene links',
            category: 'Scenes',
            status: HealthStatus.passed,
            details: 'Every button, door and loadLevel() leads to a scene that exists.',
          )
        : DiagnosticReportItem(
            title: 'Scene links',
            category: 'Scenes',
            status: HealthStatus.failed,
            details: _list(broken),
            recommendation: 'Rename the target to an existing scene, or create the missing scene.',
          );
  }

  static Future<DiagnosticReportItem> _assets(DoctorInput input, Future<bool> Function(String path) exists) async {
    final paths = <String>{};
    void scan(Object? node) {
      if (node is String) {
        if (node.startsWith('assets/') && node != placeholderSprite) paths.add(node);
      } else if (node is Map) {
        node.values.forEach(scan);
      } else if (node is List) {
        node.forEach(scan);
      }
    }

    input.scenes.values.forEach(scan);
    final missing = <String>[];
    for (final p in paths) {
      if (!await exists(p)) missing.add(p);
    }
    missing.sort();
    return missing.isEmpty
        ? DiagnosticReportItem(
            title: 'Images and sounds',
            category: 'Assets',
            status: HealthStatus.passed,
            details: paths.isEmpty ? 'The scenes use no files.' : 'All ${paths.length} files used by the scenes were found.',
          )
        : DiagnosticReportItem(
            title: 'Images and sounds',
            category: 'Assets',
            status: HealthStatus.failed,
            details: 'Not found: ${_list(missing)}',
            recommendation: 'Import the files (Asset Browser → Import) or pick another file on the sprite / audio component.',
          );
  }

  static DiagnosticReportItem _saved(DoctorInput input, VoidCallback? onSave) => input.hasUnsavedChanges
      ? DiagnosticReportItem(
          title: 'Saved',
          category: 'Project',
          status: HealthStatus.warning,
          details: '"${input.projectName}" has changes that are not saved yet (a recovery copy is kept every minute).',
          actionLabel: onSave == null ? null : 'Save now',
          action: onSave,
        )
      : DiagnosticReportItem(
          title: 'Saved',
          category: 'Project',
          status: HealthStatus.passed,
          details: input.projectPath.isEmpty ? 'All changes saved.' : 'All changes saved in ${input.projectPath}.',
        );

  static List<DiagnosticReportItem> _exports() {
    final repo = GameExporter.findEngineRepo();
    final flutter = _onPath('flutter');
    final items = <DiagnosticReportItem>[];
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final runtime = GameExporter.findPlayerRuntime();
      final os = Platform.isWindows ? 'Windows' : (Platform.isMacOS ? 'macOS' : 'Linux');
      items.add(runtime != null
          ? DiagnosticReportItem(title: '$os export', category: 'Export', status: HealthStatus.passed, details: 'Game player ready: ${runtime.path}')
          : DiagnosticReportItem(
              title: '$os export',
              category: 'Export',
              status: HealthStatus.warning,
              details: 'The $os game player has not been built yet.',
              recommendation: repo != null && flutter
                  ? 'Open Export and choose $os: the player is built once (a few minutes).'
                  : 'Building it needs the Ember Engine source folder and Flutter on this computer.',
            ));
    }
    final web = GameExporter.findWebRuntime();
    items.add(web != null
        ? DiagnosticReportItem(title: 'Web export', category: 'Export', status: HealthStatus.passed, details: 'Web player ready: ${web.path}')
        : DiagnosticReportItem(
            title: 'Web export',
            category: 'Export',
            status: HealthStatus.warning,
            details: 'The web player has not been built yet.',
            recommendation: repo != null && flutter
                ? 'Open Export and choose Web: the player is built once.'
                : 'Building it needs the Ember Engine source folder and Flutter on this computer.',
          ));
    final sdk = _androidSdk();
    final androidReady = repo != null && flutter && sdk != null;
    items.add(DiagnosticReportItem(
      title: 'Android export',
      category: 'Export',
      status: androidReady ? HealthStatus.passed : HealthStatus.warning,
      details: [
        repo != null ? 'Engine source: found' : 'Engine source: not found',
        flutter ? 'Flutter: found' : 'Flutter: not on PATH',
        sdk != null ? 'Android SDK: $sdk' : 'Android SDK: not found (set ANDROID_HOME)',
      ].join(' · '),
      recommendation: androidReady ? null : 'Android export builds the game with Flutter and the Android SDK; install what is missing.',
    ));
    items.add(const DiagnosticReportItem(
      title: 'Other platforms',
      category: 'Export',
      status: HealthStatus.info,
      details: 'macOS, Linux and iOS games cannot be exported yet.',
    ));
    return items;
  }

  // ---------------------------------------------------------------------------

  static void _visitComponents(DoctorInput input, void Function(String scene, String entity, String type, Map<String, dynamic> data) visit) {
    void walk(String scene, Object? raw) {
      if (raw is! Map) return;
      final name = raw['name'] as String? ?? 'Entity';
      for (final c in (raw['components'] as List?) ?? const []) {
        if (c is Map) visit(scene, name, c['type'] as String? ?? '', (c['data'] as Map?)?.cast<String, dynamic>() ?? const {});
      }
      for (final child in (raw['children'] as List?) ?? const []) {
        walk(scene, child);
      }
    }

    for (final e in input.scenes.entries) {
      for (final raw in (e.value['entities'] as List?) ?? const []) {
        walk(e.key, raw);
      }
    }
  }

  static String _list(Iterable<String> things) {
    final l = things.toList();
    return l.take(5).join('\n') + (l.length > 5 ? '\n…and ${l.length - 5} more' : '');
  }

  static Future<bool> Function(String path) _defaultAssetExists(String projectPath) => (path) async {
        if (projectPath.isNotEmpty && !kIsWeb && File('$projectPath${Platform.pathSeparator}$path').existsSync()) return true;
        return await EmberAssets.instance.readBytes(path) != null;
      };

  static bool _onPath(String exe) {
    if (kIsWeb) return false;
    final names = Platform.isWindows ? ['$exe.bat', '$exe.exe', '$exe.cmd'] : [exe];
    final sep = Platform.isWindows ? ';' : ':';
    for (final dir in (Platform.environment['PATH'] ?? '').split(sep)) {
      for (final n in names) {
        if (dir.isNotEmpty && File('$dir${Platform.pathSeparator}$n').existsSync()) return true;
      }
    }
    return false;
  }

  static String? _androidSdk() {
    if (kIsWeb) return null;
    final env = Platform.environment;
    final candidates = [
      env['ANDROID_HOME'],
      env['ANDROID_SDK_ROOT'],
      if (Platform.isWindows && env['LOCALAPPDATA'] != null) '${env['LOCALAPPDATA']}\\Android\\Sdk',
      if (env['HOME'] != null) '${env['HOME']}/Library/Android/sdk',
      if (env['HOME'] != null) '${env['HOME']}/Android/Sdk',
    ];
    for (final c in candidates) {
      if (c != null && c.isNotEmpty && Directory(c).existsSync()) return c;
    }
    return null;
  }
}

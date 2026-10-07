import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../hub/game_exporter.dart';
import '../hub/project_manifest.dart';
import '../hub/project_storage.dart';
import '../theme/ember_theme.dart';

enum ExportTarget { windows, web, android }

/// "Export Game" dialog: Windows (.exe folder), Web (folder to upload) or
/// Android (.apk). Builds the needed player once, then writes the game.
class ExportGameDialog extends StatefulWidget {
  /// Saves the project and returns it with the latest edited scene.
  final Future<EmberProject?> Function() prepareProject;

  const ExportGameDialog({super.key, required this.prepareProject});

  static Future<void> show(BuildContext context, {required Future<EmberProject?> Function() prepareProject}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportGameDialog(prepareProject: prepareProject),
    );
  }

  @override
  State<ExportGameDialog> createState() => _ExportGameDialogState();
}

class _ExportGameDialogState extends State<ExportGameDialog> {
  ExportTarget _target = ExportTarget.windows;
  Directory? _runtime;
  Directory? _webRuntime;
  String? _outputParent;
  bool _busy = false;
  String? _result;
  String? _error;
  final List<String> _log = [];
  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _runtime = GameExporter.findPlayerRuntime();
    _webRuntime = GameExporter.findWebRuntime();
    _initOutputFolder();
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _initOutputFolder() async {
    try {
      final root = await ProjectStorage.defaultProjectsRoot();
      if (mounted) setState(() => _outputParent ??= '${root.path}${Platform.pathSeparator}Exports');
    } catch (_) {}
  }

  void _appendLog(String line) {
    if (!mounted || line.isEmpty) return;
    setState(() => _log.addAll(line.split('\n').where((l) => l.trim().isNotEmpty)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buildRuntime() => _run(() async {
        if (_target == ExportTarget.web) {
          final dir = await GameExporter.buildWebRuntime(onLog: _appendLog);
          setState(() => _webRuntime = dir);
        } else {
          final dir = await GameExporter.buildPlayerRuntime(onLog: _appendLog);
          setState(() => _runtime = dir);
        }
      });

  Future<void> _chooseFolder() async {
    final picked = await FilePicker.getDirectoryPath(dialogTitle: 'Choose where to export the game');
    if (picked != null) setState(() => _outputParent = picked);
  }

  bool get _ready => switch (_target) {
        ExportTarget.windows => _runtime != null,
        ExportTarget.web => _webRuntime != null,
        ExportTarget.android => GameExporter.findEngineRepo() != null,
      };

  Future<void> _export() => _run(() async {
        final out = _outputParent;
        if (out == null) return;
        setState(() => _result = null);
        final project = await widget.prepareProject();
        if (project == null) throw StateError('Open or create a project first.');
        await Directory(out).create(recursive: true);
        final result = switch (_target) {
          ExportTarget.windows => await GameExporter.export(project: project, runtime: _runtime!, outputParent: out),
          ExportTarget.web => await GameExporter.exportWeb(project: project, runtime: _webRuntime!, outputParent: out),
          ExportTarget.android => await GameExporter.exportAndroid(project: project, outputParent: out, onLog: _appendLog),
        };
        _appendLog('Exported "${project.name}" → $result');
        setState(() => _result = result);
      });

  void _revealResult() {
    final r = _result;
    if (r == null) return;
    final folder = FileSystemEntity.isDirectorySync(r) ? r : File(r).parent.path;
    if (Platform.isWindows) {
      Process.run('explorer', [folder]);
    } else if (Platform.isMacOS) {
      Process.run('open', [folder]);
    } else {
      Process.run('xdg-open', [folder]);
    }
  }

  static const _label = TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold);
  static const _body = TextStyle(color: Colors.white, fontSize: 12);

  Widget _targetButton(ExportTarget t, IconData icon, String title, String subtitle) {
    final selected = _target == t;
    return Expanded(
      child: InkWell(
        key: ValueKey('export-${t.name}'),
        onTap: _busy ? null : () => setState(() {
              _target = t;
              _result = null;
              _error = null;
            }),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? EmberTheme.emberOrange.withValues(alpha: 0.15) : EmberTheme.canvasBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? EmberTheme.emberOrange : EmberTheme.borderMuted),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: selected ? EmberTheme.emberOrange : Colors.white70),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _runtimeStep() {
    final canBuild = GameExporter.findEngineRepo() != null;
    switch (_target) {
      case ExportTarget.windows:
        if (_runtime != null) return Text('Ready: ${_runtime!.path}', style: _body);
        return _buildPrompt(
          'The Windows game player (engine without the editor) has not been built yet. One-time step, a few minutes.',
          canBuild,
          GameExporter.buildCommand,
        );
      case ExportTarget.web:
        if (_webRuntime != null) return Text('Ready: ${_webRuntime!.path}', style: _body);
        return _buildPrompt(
          'The web player has not been built yet. One-time step, a few minutes.',
          canBuild,
          GameExporter.webBuildCommand,
        );
      case ExportTarget.android:
        return Text(
          canBuild
              ? 'Each Android export is a full build (a few minutes). Needs the Android SDK '
                  '(check with "flutter doctor"). The APK is signed with the debug key: fine for '
                  'phones and testers; the Play Store needs your own signing key.'
              : 'Android export needs the engine source folder: start the editor from it with "flutter run".',
          style: _body,
        );
    }
  }

  Widget _buildPrompt(String text, bool canBuild, String command) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: _body),
          const SizedBox(height: 6),
          if (canBuild)
            OutlinedButton.icon(
              onPressed: _busy ? null : _buildRuntime,
              icon: const Icon(Icons.build, size: 14),
              label: Text(_target == ExportTarget.web ? 'Build web player' : 'Build player runtime'),
            )
          else
            SelectableText('Run in the engine folder:  $command', style: _body),
        ],
      );

  String get _doneText => switch (_target) {
        ExportTarget.windows => 'Done! Double-click the game to play it:',
        ExportTarget.web => 'Done! Upload this folder to a web host (see README.txt; play-locally.ps1 tries it here):',
        ExportTarget.android => 'Done! Copy the APK to an Android phone and open it to install:',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: EmberTheme.panelBg,
      title: const Row(
        children: [
          Icon(Icons.ios_share, color: EmberTheme.emberOrange, size: 20),
          SizedBox(width: 8),
          Text('Export Game', style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. Platform', style: _label),
              const SizedBox(height: 6),
              Row(
                children: [
                  _targetButton(ExportTarget.windows, Icons.desktop_windows_outlined, 'Windows', 'A folder with the .exe'),
                  const SizedBox(width: 8),
                  _targetButton(ExportTarget.web, Icons.public, 'Web', 'Play in any browser'),
                  const SizedBox(width: 8),
                  _targetButton(ExportTarget.android, Icons.phone_android, 'Android', 'An .apk for phones'),
                ],
              ),
              const SizedBox(height: 16),
              const Text('2. Player', style: _label),
              const SizedBox(height: 4),
              _runtimeStep(),
              const SizedBox(height: 16),
              const Text('3. Output folder', style: _label),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: Text(_outputParent ?? 'Choose a folder…', style: _body)),
                  TextButton(onPressed: _busy ? null : _chooseFolder, child: const Text('Change…')),
                ],
              ),
              if (_log.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  height: 140,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: EmberTheme.canvasBg, borderRadius: BorderRadius.circular(4)),
                  child: ListView.builder(
                    controller: _logScroll,
                    itemCount: _log.length,
                    itemBuilder: (_, i) => Text(
                      _log[i],
                      style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: EmberTheme.emberOrange),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                SelectableText(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
              if (_result != null) ...[
                const SizedBox(height: 12),
                Text(_doneText, style: _label),
                SelectableText(_result!, style: _body),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_result != null) TextButton(onPressed: _revealResult, child: const Text('Show in folder')),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton.icon(
          key: const ValueKey('export-go'),
          style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.emberOrange, foregroundColor: Colors.white),
          onPressed: _busy || !_ready || _outputParent == null ? null : _export,
          icon: const Icon(Icons.rocket_launch_rounded, size: 16),
          label: Text(switch (_target) {
            ExportTarget.windows => 'Export',
            ExportTarget.web => 'Export for Web',
            ExportTarget.android => 'Build APK',
          }),
        ),
      ],
    );
  }
}

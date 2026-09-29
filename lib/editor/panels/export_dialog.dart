import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../hub/game_exporter.dart';
import '../hub/project_manifest.dart';
import '../hub/project_storage.dart';
import '../theme/ember_theme.dart';

/// "Export Game" dialog: builds (once) the standalone player runtime and
/// writes the current project next to it as a double-clickable game.
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
  Directory? _runtime;
  String? _outputParent;
  bool _busy = false;
  String? _resultExe;
  String? _error;
  final List<String> _log = [];
  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _runtime = GameExporter.findPlayerRuntime();
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
    setState(() => _log.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  Future<void> _buildRuntime() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dir = await GameExporter.buildPlayerRuntime(onLog: _appendLog);
      setState(() => _runtime = dir);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFolder() async {
    final picked = await FilePicker.getDirectoryPath(dialogTitle: 'Choose where to export the game');
    if (picked != null) setState(() => _outputParent = picked);
  }

  Future<void> _export() async {
    final runtime = _runtime;
    final out = _outputParent;
    if (runtime == null || out == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _resultExe = null;
    });
    try {
      final project = await widget.prepareProject();
      if (project == null) throw StateError('Open or create a project first.');
      await Directory(out).create(recursive: true);
      final exe = await GameExporter.export(project: project, runtime: runtime, outputParent: out);
      _appendLog('Exported "${project.name}" → $exe');
      setState(() => _resultExe = exe);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _revealResult() {
    final exe = _resultExe;
    if (exe == null) return;
    final folder = File(exe).parent.path;
    if (Platform.isWindows) {
      Process.run('explorer', [folder]);
    } else if (Platform.isMacOS) {
      Process.run('open', [folder]);
    } else {
      Process.run('xdg-open', [folder]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canBuild = GameExporter.findEngineRepo() != null;
    const label = TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold);
    const body = TextStyle(color: Colors.white, fontSize: 12);

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
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Player runtime', style: label),
            const SizedBox(height: 4),
            if (_runtime != null)
              Text('Ready: ${_runtime!.path}', style: body)
            else ...[
              const Text(
                'The game player (engine without the editor) has not been built yet. '
                'This is a one-time step and takes a few minutes.',
                style: body,
              ),
              const SizedBox(height: 6),
              if (canBuild)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _buildRuntime,
                  icon: const Icon(Icons.build, size: 14),
                  label: const Text('Build player runtime'),
                )
              else
                SelectableText('Run in the engine folder:  ${GameExporter.buildCommand}', style: body),
            ],
            const SizedBox(height: 16),
            const Text('2. Output folder', style: label),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: Text(_outputParent ?? 'Choose a folder…', style: body)),
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
            if (_resultExe != null) ...[
              const SizedBox(height: 12),
              const Text('Done! Double-click the game to play it:', style: label),
              SelectableText(_resultExe!, style: body),
            ],
          ],
        ),
      ),
      actions: [
        if (_resultExe != null)
          TextButton(onPressed: _revealResult, child: const Text('Show in folder')),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.emberOrange),
          onPressed: _busy || _runtime == null || _outputParent == null ? null : _export,
          icon: const Icon(Icons.rocket_launch_rounded, size: 16),
          label: const Text('Export'),
        ),
      ],
    );
  }
}

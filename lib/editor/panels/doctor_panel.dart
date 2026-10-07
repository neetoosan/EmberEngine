import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../doctor.dart';
import '../hub/project_manifest.dart';
import '../hub/project_package.dart';
import '../hub/project_storage.dart';
import '../project_session.dart';
import '../theme/ember_theme.dart';

export '../doctor.dart' show DiagnosticReportItem, HealthStatus;

/// Ember Doctor: real checks of the open project and of this machine's
/// export setup (see [ProjectDoctor]), with buttons that open or fix problems.
class EmberDoctorDialog extends StatefulWidget {
  final EmberProject? project;

  /// The project as it would be saved now (`ProjectSession.contentOf`); defaults to [project] as stored.
  final Map<String, dynamic> Function()? content;
  final bool Function()? hasUnsavedChanges;
  final void Function(String file)? onOpenScript;
  final Future<void> Function()? onSave;

  /// Off in tests (they don't look at this machine's Flutter / Android setup).
  final bool checkExports;

  const EmberDoctorDialog({
    super.key,
    this.project,
    this.content,
    this.hasUnsavedChanges,
    this.onOpenScript,
    this.onSave,
    this.checkExports = !kIsWeb,
  });

  static void show(
    BuildContext context, {
    EmberProject? project,
    Map<String, dynamic> Function()? content,
    bool Function()? hasUnsavedChanges,
    void Function(String file)? onOpenScript,
    Future<void> Function()? onSave,
    bool checkExports = !kIsWeb,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => EmberDoctorDialog(
        project: project,
        content: content,
        hasUnsavedChanges: hasUnsavedChanges,
        onOpenScript: onOpenScript,
        onSave: onSave,
        checkExports: checkExports,
      ),
    );
  }

  @override
  State<EmberDoctorDialog> createState() => _EmberDoctorDialogState();
}

class _EmberDoctorDialogState extends State<EmberDoctorDialog> {
  final List<DiagnosticReportItem> _reports = [];
  bool _isRunningDiagnostics = false;
  double _healthScore = 1.0;

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    final project = widget.project;
    setState(() {
      _isRunningDiagnostics = true;
      _reports.clear();
    });
    if (project == null) {
      setState(() {
        _reports.add(const DiagnosticReportItem(
            title: 'No project open', category: 'Project', status: HealthStatus.info, details: 'Open a project from the Project Hub to check it.'));
        _isRunningDiagnostics = false;
      });
      return;
    }
    final content = widget.content?.call() ?? ProjectSession.contentOf(project);
    final input = DoctorInput.fromContent(content,
        projectPath: ProjectStorage.hasDiskLocation(project) ? project.path : '', hasUnsavedChanges: widget.hasUnsavedChanges?.call() ?? false);
    final items = await ProjectDoctor.run(
      input,
      checkExports: widget.checkExports,
      onOpenScript: widget.onOpenScript == null
          ? null
          : (file) {
              Navigator.of(context).pop();
              widget.onOpenScript!(file);
            },
      onSave: widget.onSave == null
          ? null
          : () async {
              await widget.onSave!();
              if (mounted) _runDiagnostics();
            },
    );
    if (!mounted) return;
    // Problems first, then warnings, passes and information (stable within each)
    const order = [HealthStatus.failed, HealthStatus.warning, HealthStatus.passed, HealthStatus.info];
    final sorted = [for (final st in order) ...items.where((i) => i.status == st)];
    setState(() {
      _reports.addAll(sorted);
      _healthScore = ProjectDoctor.score(items);
      _isRunningDiagnostics = false;
    });
  }

  void _exportProjectPackage() {
    if (widget.project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active project to export.')),
      );
      return;
    }

    final pkgStr = ProjectPackageManager.exportToPackageString(widget.project!);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EmberTheme.panelBg,
        title: const Row(
          children: [
            Icon(Icons.inventory_2_rounded, color: EmberTheme.emberOrange, size: 20),
            SizedBox(width: 8),
            Text('Exported .emberpkg Bundle', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Single-file package bundle for project "${widget.project!.name}" (${widget.project!.scenes.length} scenes, ${widget.project!.scripts.length} scripts):',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: TextEditingController(text: pkgStr),
                readOnly: true,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: EmberTheme.canvasBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.emberOrange),
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Package ready for sharing or archive storage.')),
              );
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final healthPercent = (_healthScore * 100).round();
    final judged = _reports.where((r) => r.status != HealthStatus.info).length;
    final passed = _reports.where((r) => r.status == HealthStatus.passed).length;

    return AlertDialog(
      backgroundColor: EmberTheme.panelBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: EmberTheme.emberOrange.withAlpha(40),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.health_and_safety_rounded, color: EmberTheme.emberOrange, size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ember Doctor', style: TextStyle(color: Colors.white, fontSize: 16)),
              Text('Checks your project and the export setup on this computer', style: TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: healthPercent == 100 ? Colors.green.withAlpha(40) : Colors.amber.withAlpha(40),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: healthPercent == 100 ? Colors.greenAccent : Colors.amberAccent),
            ),
            child: Text(
              _isRunningDiagnostics ? 'Checking…' : '$passed of $judged checks passed',
              style: TextStyle(
                color: healthPercent == 100 ? Colors.greenAccent : Colors.amberAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 650,
        height: 400,
        child: _isRunningDiagnostics
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: EmberTheme.emberOrange),
                    SizedBox(height: 16),
                    Text('Checking the project…', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              )
            : ListView.separated(
                itemCount: _reports.length,
                separatorBuilder: (ctx, i) => const Divider(color: EmberTheme.borderMuted, height: 1),
                itemBuilder: (ctx, idx) {
                  final r = _reports[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(r.status.icon, color: r.status.color, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(r.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: EmberTheme.canvasBg,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(r.category, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(r.details, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              if (r.recommendation != null) ...[
                                const SizedBox(height: 2),
                                Text(r.recommendation!, style: TextStyle(color: r.status.color.withAlpha(200), fontSize: 10)),
                              ],
                              if (r.action != null && r.actionLabel != null) ...[
                                const SizedBox(height: 6),
                                OutlinedButton(
                                  onPressed: r.action,
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    side: BorderSide(color: r.status.color.withAlpha(160)),
                                  ),
                                  child: Text(r.actionLabel!, style: TextStyle(color: r.status.color, fontSize: 11)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _isRunningDiagnostics ? null : _runDiagnostics,
          icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white70),
          label: const Text('Check again', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.surfaceBg, side: const BorderSide(color: EmberTheme.borderMuted)),
          onPressed: _exportProjectPackage,
          icon: const Icon(Icons.archive_outlined, size: 16, color: Colors.white),
          label: const Text('Export .emberpkg', style: TextStyle(color: Colors.white, fontSize: 12)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.emberOrange),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ],
    );
  }
}

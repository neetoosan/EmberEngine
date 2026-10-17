import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../hub/game_exporter.dart';
import '../hub/game_icons.dart';
import '../hub/project_manifest.dart';
import '../hub/project_storage.dart';
import '../hub/windows_msix.dart';
import '../theme/ember_theme.dart';

/// Project Settings: how the exported game presents itself (name, version,
/// build number, publisher, Android app id, MSIX identity, icon). Returns true when saved.
class ProjectSettingsDialog extends StatefulWidget {
  final EmberProject project;
  const ProjectSettingsDialog({super.key, required this.project});

  static Future<bool> show(BuildContext context, EmberProject project) async =>
      await showDialog<bool>(context: context, builder: (_) => ProjectSettingsDialog(project: project)) ?? false;

  @override
  State<ProjectSettingsDialog> createState() => _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState extends State<ProjectSettingsDialog> {
  late final TextEditingController _name, _version, _build, _publisher, _appId, _msixName, _msixPublisher;
  late String _iconPath;
  Uint8List? _iconPreview;
  String? _iconWarning;

  EmberProject get p => widget.project;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: p.game.displayName);
    _version = TextEditingController(text: p.version);
    _build = TextEditingController(text: '${p.game.buildNumber}');
    _publisher = TextEditingController(text: p.game.publisher);
    _appId = TextEditingController(text: p.game.appId);
    _msixName = TextEditingController(text: p.game.msixName);
    _msixPublisher = TextEditingController(text: p.game.msixPublisher);
    _iconPath = p.game.iconPath;
    for (final c in [_name, _version, _build, _publisher, _appId, _msixName, _msixPublisher]) {
      c.addListener(() => setState(() {}));
    }
    _loadPreview();
  }

  @override
  void dispose() {
    for (final c in [_name, _version, _build, _publisher, _appId, _msixName, _msixPublisher]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPreview() async {
    try {
      final bytes = await GameIcons.sourceFor(p, iconPath: _iconPath);
      final check = await GameIcons.inspect(bytes);
      if (mounted) {
        setState(() {
          _iconPreview = bytes;
          _iconWarning = check.warning;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _iconPreview = null;
          _iconWarning = 'The icon could not be read: $e';
        });
      }
    }
  }

  bool get _canPickIcon => ProjectStorage.hasDiskLocation(p);

  Future<void> _pickIcon() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Choose a square game icon (512x512 PNG is best)', type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg']);
    final path = picked?.path;
    if (path == null) return;
    final ext = path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    const rel = 'assets/icon';
    final target = File('${p.path}${Platform.pathSeparator}assets${Platform.pathSeparator}icon${Platform.pathSeparator}icon.$ext');
    await target.parent.create(recursive: true);
    await File(path).copy(target.path);
    setState(() => _iconPath = '$rel/icon.$ext');
    await _loadPreview();
  }

  String? get _versionError => GameSettings.isValidVersion(_version.text.trim()) ? null : 'Use numbers like 1.0.0';
  String? get _buildError {
    final n = int.tryParse(_build.text.trim());
    return n == null || n < 1 ? 'A whole number, 1 or more' : null;
  }

  String? get _appIdError {
    final id = _appId.text.trim();
    if (id.isEmpty) return null;
    return GameSettings.isValidAppId(id) ? null : 'Like com.yourstudio.yourgame (letters, digits, _ and dots)';
  }

  String? get _msixNameError {
    final n = _msixName.text.trim();
    return n.isEmpty || GameSettings.isValidMsixName(n) ? null : '3 to 50 letters, digits, dots and dashes';
  }

  String? get _msixPublisherError {
    final v = _msixPublisher.text.trim();
    return v.isEmpty || GameSettings.isValidMsixPublisher(v) ? null : 'Starts with CN=, e.g. CN=My Studio';
  }

  bool get _valid => _versionError == null && _buildError == null && _appIdError == null && _msixNameError == null && _msixPublisherError == null;

  void _save() {
    p.game
      ..displayName = _name.text.trim()
      ..publisher = _publisher.text.trim()
      ..buildNumber = int.parse(_build.text.trim())
      ..appId = _appId.text.trim()
      ..msixName = _msixName.text.trim()
      ..msixPublisher = _msixPublisher.text.trim()
      ..iconPath = _iconPath;
    p.version = _version.text.trim();
    Navigator.of(context).pop(true);
  }

  Widget _field(String label, TextEditingController c, {String? hint, String? help, String? error, Key? key}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: key,
          controller: c,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(labelText: label, hintText: hint, helperText: help, helperMaxLines: 3, errorText: error, errorMaxLines: 3, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final title = _name.text.trim().isEmpty ? p.name : _name.text.trim();
    final autoId = GameExporter.androidAppId(title);
    final autoMsixName = WindowsMsix.defaultIdentityName(_appId.text.trim().isEmpty ? autoId : _appId.text.trim());
    final autoMsixPublisher = WindowsMsix.defaultPublisher(_publisher.text.trim().isEmpty ? p.author : _publisher.text.trim(), title);
    return AlertDialog(
      backgroundColor: EmberTheme.panelBg,
      title: const Text('Project Settings', style: TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('How your exported game presents itself to players and stores.', style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(color: EmberTheme.canvasBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: EmberTheme.borderMuted)),
                    clipBehavior: Clip.antiAlias,
                    child: _iconPreview == null ? const Icon(Icons.image_not_supported_outlined, color: Colors.white38) : Image.memory(_iconPreview!, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_iconPath.isEmpty ? 'Icon: the Ember Engine icon' : 'Icon: $_iconPath', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          OutlinedButton.icon(
                            key: const ValueKey('settings-pick-icon'),
                            onPressed: _canPickIcon ? _pickIcon : null,
                            icon: const Icon(Icons.image_outlined, size: 15),
                            label: const Text('Choose image…', style: TextStyle(fontSize: 12)),
                          ),
                          if (_iconPath.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setState(() => _iconPath = '');
                                _loadPreview();
                              },
                              child: const Text('Use the Ember icon', style: TextStyle(fontSize: 12)),
                            ),
                        ]),
                        if (!_canPickIcon) const Text('Save the project first so the icon has a folder to go in.', style: TextStyle(color: Colors.amberAccent, fontSize: 11)),
                        if (_iconWarning != null) Text(_iconWarning!, style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _field('Game name', _name, key: const ValueKey('settings-name'), hint: p.name, help: 'Window title, app name and browser tab. Empty: "${p.name}".'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _field('Version', _version, key: const ValueKey('settings-version'), help: 'Shown to players, e.g. 1.0.0', error: _versionError)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field('Build number', _build,
                          key: const ValueKey('settings-build'), help: 'Must go up for every store upload (Ember does this after release builds)', error: _buildError)),
                ],
              ),
              _field('Publisher', _publisher, key: const ValueKey('settings-publisher'), hint: p.author, help: 'You or your studio: file properties, installer, copyright. Empty: "${p.author}".'),
              _field('Android app id', _appId,
                  key: const ValueKey('settings-appid'),
                  hint: autoId,
                  help: 'Unique on Google Play and cannot change after publishing. Empty: $autoId',
                  error: _appIdError),
              const SizedBox(height: 6),
              const Text('Microsoft Store (MSIX)', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              const Text('Copy both from Partner Center → your game → Product identity. Only needed for Store uploads.',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: _field('Package name', _msixName,
                          key: const ValueKey('settings-msix-name'), hint: autoMsixName, help: 'Package/Identity/Name. Empty: $autoMsixName', error: _msixNameError)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field('Package publisher', _msixPublisher,
                          key: const ValueKey('settings-msix-publisher'),
                          hint: autoMsixPublisher,
                          help: 'Package/Identity/Publisher. Empty: $autoMsixPublisher',
                          error: _msixPublisherError)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(key: const ValueKey('settings-save'), onPressed: _valid ? _save : null, child: const Text('Save')),
      ],
    );
  }
}

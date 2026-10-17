import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../hub/android_signing.dart';
import '../hub/game_exporter.dart';
import '../hub/game_icons.dart';
import '../hub/project_manifest.dart';
import '../hub/project_storage.dart';
import '../hub/windows_msix.dart';
import '../theme/ember_theme.dart';
import 'android_key_dialog.dart';
import 'project_settings_dialog.dart';

enum ExportTarget { windows, web, android }

/// "Export Game": Windows (folder, ZIP, installer, or an MSIX package), Web (folder and an itch.io
/// ZIP) or Android (APK and/or a signed app bundle for Google Play), each
/// carrying the game's own name, icon and version from Project Settings.
class ExportGameDialog extends StatefulWidget {
  /// Saves the project and returns it with the latest edited scene.
  final Future<EmberProject?> Function() prepareProject;

  /// The open project (for the name, icon and signing key shown before exporting).
  final EmberProject? project;

  const ExportGameDialog({super.key, required this.prepareProject, this.project});

  static Future<void> show(BuildContext context, {required Future<EmberProject?> Function() prepareProject, EmberProject? project}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportGameDialog(prepareProject: prepareProject, project: project),
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
  List<String> _results = [];
  String? _note;
  String? _error;
  final List<String> _log = [];
  final ScrollController _logScroll = ScrollController();
  Uint8List? _iconPreview;

  // Windows
  bool _windowsZip = true;
  bool _windowsInstaller = true;
  bool _msix = false; // Windows format: MSIX package instead of the game folder
  bool _msixSigned = false;
  String? _pfx;
  final _pfxPassword = TextEditingController();
  bool _rememberPfxPassword = true;
  // Web
  bool _webZip = true;
  // Android
  bool _apk = true;
  bool _aab = false;
  bool _release = false;
  AndroidSigningKey? _key;
  final _password = TextEditingController();
  bool _rememberPassword = true;

  @override
  void initState() {
    super.initState();
    _runtime = GameExporter.findPlayerRuntime();
    _webRuntime = GameExporter.findWebRuntime();
    _initOutputFolder();
    _loadIdentity();
  }

  @override
  void dispose() {
    _logScroll.dispose();
    _password.dispose();
    _pfxPassword.dispose();
    super.dispose();
  }

  Future<void> _initOutputFolder() async {
    try {
      final root = await ProjectStorage.defaultProjectsRoot();
      if (mounted) setState(() => _outputParent ??= '${root.path}${Platform.pathSeparator}Exports');
    } catch (_) {}
  }

  Future<void> _loadIdentity() async {
    final p = widget.project;
    if (p == null) return;
    try {
      final icon = await GameIcons.sourceFor(p);
      if (mounted) setState(() => _iconPreview = icon);
    } catch (_) {
      if (mounted) setState(() => _iconPreview = null);
    }
    final pfx = await WindowsMsix.certificateForProject(p.id);
    if (pfx != null && File(pfx).existsSync()) {
      final remembered = await WindowsMsix.rememberedPassword(pfx);
      if (!mounted) return;
      setState(() {
        _pfx = pfx;
        if (remembered != null) _pfxPassword.text = remembered;
      });
    }
    final key = await AndroidSigning.keyForProject(p.id);
    if (key != null && File(key.keystorePath).existsSync()) {
      final remembered = await AndroidSigning.rememberedPassword(key);
      if (!mounted) return;
      setState(() {
        _key = key;
        if (remembered != null) _password.text = remembered;
      });
    }
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

  Future<void> _editSettings() async {
    final p = widget.project;
    if (p == null) return;
    if (await ProjectSettingsDialog.show(context, p)) {
      await widget.prepareProject(); // save the new settings
      await _loadIdentity();
      if (mounted) setState(() {});
    }
  }

  Future<void> _createKey() async {
    final p = widget.project;
    if (p == null) return;
    final created = await CreateAndroidKeyDialog.show(context, p);
    if (created == null) return;
    final (key, password) = created;
    await AndroidSigning.setKeyForProject(p.id, key);
    setState(() {
      _key = key;
      _password.text = password;
      _release = true;
    });
    _appendLog('Created upload key ${key.keystorePath}: back it up together with its password.');
  }

  Future<void> _chooseKey() async {
    final p = widget.project;
    if (p == null) return;
    final picked = await FilePicker.pickFile(dialogTitle: 'Choose your keystore (.jks, .keystore or .p12)', type: FileType.custom, allowedExtensions: ['jks', 'keystore', 'p12', 'pfx']);
    final path = picked?.path;
    if (path == null || !mounted) return;
    final alias = await _askAlias();
    if (alias == null) return;
    final key = AndroidSigningKey(path, alias);
    await AndroidSigning.setKeyForProject(p.id, key);
    final remembered = await AndroidSigning.rememberedPassword(key);
    setState(() {
      _key = key;
      _password.text = remembered ?? '';
      _release = true;
    });
  }

  Future<void> _chooseCertificate() async {
    final p = widget.project;
    if (p == null) return;
    final picked = await FilePicker.pickFile(dialogTitle: 'Choose your code-signing certificate (.pfx)', type: FileType.custom, allowedExtensions: ['pfx', 'p12']);
    final path = picked?.path;
    if (path == null || !mounted) return;
    await WindowsMsix.setCertificateForProject(p.id, path);
    final remembered = await WindowsMsix.rememberedPassword(path);
    setState(() {
      _pfx = path;
      _pfxPassword.text = remembered ?? '';
      _msixSigned = true;
    });
  }

  Future<void> _createCertificate() async {
    final p = widget.project;
    if (p == null) return;
    final created = await showDialog<(MsixCertificate, String)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TestCertificateDialog(project: p),
    );
    if (created == null || !mounted) return;
    final (cert, cer) = created;
    await WindowsMsix.setCertificateForProject(p.id, cert.pfxPath);
    setState(() {
      _pfx = cert.pfxPath;
      _pfxPassword.text = cert.password;
      _msixSigned = true;
    });
    _appendLog('Created test certificate ${cert.pfxPath} (public part: $cer).');
  }

  Future<String?> _askAlias() {
    final c = TextEditingController(text: 'upload');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EmberTheme.panelBg,
        title: const Text('Key alias', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'The name of the key inside the keystore')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: const Text('Use this key')),
        ],
      ),
    );
  }

  bool get _ready => switch (_target) {
        ExportTarget.windows => _runtime != null &&
            (!_msix || (WindowsMsix.findMakeAppx() != null && (!_msixSigned || (_pfx != null && _pfxPassword.text.isNotEmpty)))),
        ExportTarget.web => _webRuntime != null,
        ExportTarget.android => GameExporter.findEngineRepo() != null && (_apk || _aab) && (!_release || (_key != null && _password.text.isNotEmpty)),
      };

  Future<void> _export() => _run(() async {
        final out = _outputParent;
        if (out == null) return;
        setState(() {
          _results = [];
          _log.clear();
          _note = null;
        });
        final project = await widget.prepareProject();
        if (project == null) throw StateError('Open or create a project first.');
        await Directory(out).create(recursive: true);
        _appendLog('Preparing the icon…');
        final icons = await GameIcons.render(await GameIcons.sourceFor(project));
        final results = <String>[];
        switch (_target) {
          case ExportTarget.windows when _msix:
            MsixCertificate? cert;
            if (_msixSigned) {
              cert = MsixCertificate(_pfx!, _pfxPassword.text);
              await WindowsMsix.certificateSubject(cert); // a wrong password fails here, before the build
              await WindowsMsix.rememberPassword(cert.pfxPath, _rememberPfxPassword ? cert.password : null);
            }
            // The game folder is only a step towards the package
            final temp = await Directory.systemTemp.createTemp('ember_msix_game');
            try {
              final exe = await GameExporter.export(project: project, runtime: _runtime!, outputParent: temp.path, icons: icons, onLog: _appendLog);
              results.add(await WindowsMsix.build(
                  project: project, gameFolder: File(exe).parent.path, outputParent: out, icons: icons, certificate: cert, onLog: _appendLog));
            } finally {
              await temp.delete(recursive: true);
            }
            _note = cert == null
                ? 'Unsigned MSIX: upload it in Partner Center (Package name and publisher must match Project Settings). Windows will not install it until it is signed.'
                : 'Signed MSIX. With a test certificate, each PC must first trust its .cer: double-click it, Install Certificate, Local Machine, '
                    '"Trusted People". For public downloads use a code-signing certificate from a certificate authority, or the Microsoft Store.';
          case ExportTarget.windows:
            final exe = await GameExporter.export(project: project, runtime: _runtime!, outputParent: out, icons: icons, onLog: _appendLog);
            results.add(exe);
            final folder = File(exe).parent.path;
            if (_windowsZip) results.add(await GameExporter.zipGameFolder(folder));
            if (_windowsInstaller) {
              final (iss, setup) = await GameExporter.buildInstaller(project, folder, icons: icons, onLog: _appendLog);
              results.add(setup ?? iss);
              if (setup == null) _note = 'Installer: Inno Setup is not installed, so only the installer script was written. Install Inno Setup (free, jrsoftware.org) and export again to get a Setup.exe.';
            }
          case ExportTarget.web:
            final folder = await GameExporter.exportWeb(project: project, runtime: _webRuntime!, outputParent: out, icons: icons);
            results.add(folder);
            if (_webZip) results.add(await GameExporter.zipWebForItch(folder));
          case ExportTarget.android:
            String? password;
            final key = _release ? _key : null;
            if (key != null) {
              password = _password.text;
              if (!await AndroidSigning.verify(key, password)) throw StateError('That password does not open ${key.keystorePath} (or the alias "${key.alias}" is wrong).');
              await AndroidSigning.rememberPassword(key, _rememberPassword ? password : null);
            }
            results.addAll(await GameExporter.exportAndroid(
                project: project, outputParent: out, onLog: _appendLog, icons: icons, key: key, password: password, apk: _apk, appBundle: _aab));
            if (key != null) {
              // Stores refuse a second upload with the same build number
              project.game.buildNumber++;
              await widget.prepareProject();
              _note = 'Build ${project.game.buildNumber - 1} done. The next export will be build ${project.game.buildNumber}.';
            }
        }
        for (final r in results) {
          _appendLog('→ $r');
        }
        setState(() => _results = results);
      });

  void _revealResult() {
    if (_results.isEmpty) return;
    final r = _results.first;
    final folder = FileSystemEntity.isDirectorySync(r) ? Directory(r).parent.path : File(r).parent.path;
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
  static const _muted = TextStyle(color: Colors.white54, fontSize: 11);

  Widget _targetButton(ExportTarget t, IconData icon, String title, String subtitle) {
    final selected = _target == t;
    return Expanded(
      child: InkWell(
        key: ValueKey('export-${t.name}'),
        onTap: _busy
            ? null
            : () => setState(() {
                  _target = t;
                  _results = [];
                  _log.clear();
                  _note = null;
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

  Widget _identity() {
    final p = widget.project;
    if (p == null) return const SizedBox.shrink();
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: EmberTheme.canvasBg),
          clipBehavior: Clip.antiAlias,
          child: _iconPreview == null ? const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent) : Image.memory(_iconPreview!, fit: BoxFit.cover),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.gameTitle, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              Text('Version ${p.version} · build ${p.game.buildNumber} · by ${p.publisherName}', style: _muted),
            ],
          ),
        ),
        TextButton.icon(
          key: const ValueKey('export-edit-settings'),
          onPressed: _busy ? null : _editSettings,
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Name, icon, version…', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged, {String? help, Key? key}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 28,
            child: Checkbox(key: key, value: value, onChanged: _busy ? null : (v) => setState(() => onChanged(v ?? false))),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: label, style: _body),
                if (help != null) TextSpan(text: '  $help', style: _muted),
              ])),
            ),
          ),
        ],
      );

  Widget _options() {
    switch (_target) {
      case ExportTarget.windows:
        final inno = GameExporter.findInnoCompiler() != null;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            ChoiceChip(
              key: const ValueKey('export-win-exe'),
              label: const Text('Game folder (.exe)', style: TextStyle(fontSize: 12)),
              selected: !_msix,
              onSelected: _busy ? null : (_) => setState(() => _msix = false),
            ),
            ChoiceChip(
              key: const ValueKey('export-win-msix'),
              label: const Text('MSIX package', style: TextStyle(fontSize: 12)),
              selected: _msix,
              onSelected: _busy ? null : (_) => setState(() => _msix = true),
            ),
          ]),
          const SizedBox(height: 6),
          if (_msix) ..._msixOptions() else ...[
            _check('ZIP to share', _windowsZip, (v) => _windowsZip = v, help: 'One file for itch.io, Steam uploads or friends.', key: const ValueKey('export-win-zip')),
            _check('Installer (Setup.exe)', _windowsInstaller, (v) => _windowsInstaller = v,
                help: inno ? 'Start-menu shortcut and uninstaller; no admin rights needed.' : 'Needs Inno Setup (free); without it the installer script is written for later.',
                key: const ValueKey('export-win-installer')),
          ],
        ]);
      case ExportTarget.web:
        return _check('ZIP for itch.io', _webZip, (v) => _webZip = v,
            help: 'Upload it as an HTML game ("This file will be played in the browser").', key: const ValueKey('export-web-zip'));
      case ExportTarget.android:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _check('APK', _apk, (v) => _apk = v, help: 'Install directly on phones and tablets.', key: const ValueKey('export-apk')),
          _check('App bundle (.aab)', _aab, (v) {
            _aab = v;
            if (v) _release = true;
          }, help: 'What Google Play asks you to upload.', key: const ValueKey('export-aab')),
          const SizedBox(height: 6),
          _check('Sign with my upload key (for Google Play)', _release, (v) => _release = v,
              help: _release ? null : 'Off: signed with a debug key, fine for testing on your own devices.', key: const ValueKey('export-release')),
          if (_release) ...[
            const SizedBox(height: 4),
            if (_key == null)
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(key: const ValueKey('export-create-key'), onPressed: _busy ? null : _createKey, icon: const Icon(Icons.vpn_key_outlined, size: 14), label: const Text('Create a key…')),
                TextButton(onPressed: _busy ? null : _chooseKey, child: const Text('I already have one…')),
              ])
            else ...[
              Row(children: [
                const Icon(Icons.vpn_key_outlined, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Expanded(child: Text('${_key!.keystorePath}  (alias ${_key!.alias})', style: _muted)),
                TextButton(onPressed: _busy ? null : _chooseKey, child: const Text('Change…')),
              ]),
              TextField(
                key: const ValueKey('export-key-password'),
                controller: _password,
                obscureText: true,
                onChanged: (_) => setState(() {}),
                style: _body,
                decoration: const InputDecoration(labelText: 'Key password', isDense: true),
              ),
              _check('Remember the password on this computer', _rememberPassword, (v) => _rememberPassword = v, help: 'Kept in Windows Credential Manager, never in the project.'),
            ],
          ],
        ]);
    }
  }

  List<Widget> _msixOptions() {
    final p = widget.project;
    if (WindowsMsix.findMakeAppx() == null) {
      return const [
        Text('MSIX needs the Windows SDK (MakeAppx). Install it with Visual Studio ("Windows SDK" component) or from '
            'developer.microsoft.com/windows/downloads/windows-sdk, then reopen this dialog.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
      ];
    }
    return [
      Text('One file for the Microsoft Store, with clean install and uninstall from Windows Settings.', style: _muted),
      if (p != null) Text('Package ${WindowsMsix.identityName(p)} · ${WindowsMsix.publisher(p)} · version ${WindowsMsix.version(p)}', style: _muted),
      const SizedBox(height: 4),
      _check('Sign with my certificate', _msixSigned, (v) => _msixSigned = v,
          help: _msixSigned
              ? 'To install from your website or on your own PCs; the publisher comes from the certificate.'
              : 'Off: unsigned, for uploading to the Microsoft Store (the Store signs it).',
          key: const ValueKey('export-msix-signed')),
      if (_msixSigned) ...[
        const SizedBox(height: 4),
        if (_pfx == null)
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
                key: const ValueKey('export-create-cert'),
                onPressed: _busy ? null : _createCertificate,
                icon: const Icon(Icons.verified_user_outlined, size: 14),
                label: const Text('Create a test certificate…')),
            TextButton(onPressed: _busy ? null : _chooseCertificate, child: const Text('I have a .pfx…')),
          ])
        else ...[
          Row(children: [
            const Icon(Icons.verified_user_outlined, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            Expanded(child: Text(_pfx!, style: _muted)),
            TextButton(onPressed: _busy ? null : _chooseCertificate, child: const Text('Change…')),
          ]),
          TextField(
            key: const ValueKey('export-pfx-password'),
            controller: _pfxPassword,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            style: _body,
            decoration: const InputDecoration(labelText: 'Certificate password', isDense: true),
          ),
          _check('Remember the password on this computer', _rememberPfxPassword, (v) => _rememberPfxPassword = v,
              help: 'Kept in Windows Credential Manager, never in the project.'),
        ],
      ],
    ];
  }

  Widget _runtimeStep() {
    final canBuild = GameExporter.findEngineRepo() != null;
    switch (_target) {
      case ExportTarget.windows:
        if (_runtime != null) return Text('Ready: ${_runtime!.path}', style: _muted);
        return _buildPrompt('The Windows game player (engine without the editor) has not been built yet. One-time step, a few minutes.', canBuild,
            GameExporter.buildCommand);
      case ExportTarget.web:
        if (_webRuntime != null) return Text('Ready: ${_webRuntime!.path}', style: _muted);
        return _buildPrompt('The web player has not been built yet. One-time step, a few minutes.', canBuild, GameExporter.webBuildCommand);
      case ExportTarget.android:
        return Text(
          canBuild
              ? 'Each Android export is a full build (a few minutes per package). Needs the Android SDK (check with "flutter doctor").'
              : 'Android export needs the engine source folder: start the editor from it with "flutter run".',
          style: _muted,
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
        ExportTarget.windows => _msix ? 'Done! Your MSIX package:' : 'Done! Double-click the game to play it, or share the ZIP / installer:',
        ExportTarget.web => 'Done! Upload the ZIP to itch.io, or the folder to any web host:',
        ExportTarget.android => 'Done! Install the APK on a phone; upload the .aab to Google Play:',
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
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _identity(),
              const SizedBox(height: 14),
              const Text('1. Platform', style: _label),
              const SizedBox(height: 6),
              Row(
                children: [
                  _targetButton(ExportTarget.windows, Icons.desktop_windows_outlined, 'Windows', '.exe, installer or MSIX'),
                  const SizedBox(width: 8),
                  _targetButton(ExportTarget.web, Icons.public, 'Web', 'Browser, itch.io'),
                  const SizedBox(width: 8),
                  _targetButton(ExportTarget.android, Icons.phone_android, 'Android', 'APK, Google Play'),
                ],
              ),
              const SizedBox(height: 12),
              const Text('2. Options', style: _label),
              const SizedBox(height: 2),
              _options(),
              const SizedBox(height: 12),
              const Text('3. Player', style: _label),
              const SizedBox(height: 4),
              _runtimeStep(),
              const SizedBox(height: 12),
              const Text('4. Output folder', style: _label),
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
                  height: 130,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: EmberTheme.canvasBg, borderRadius: BorderRadius.circular(4)),
                  child: ListView.builder(
                    controller: _logScroll,
                    itemCount: _log.length,
                    itemBuilder: (_, i) => Text(_log[i], style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace')),
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
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_doneText, style: _label),
                for (final r in _results) SelectableText(r, style: _body),
              ],
              if (_note != null) ...[
                const SizedBox(height: 8),
                Text(_note!, style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_results.isNotEmpty) TextButton(onPressed: _revealResult, child: const Text('Show in folder')),
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
            ExportTarget.windows => _msix ? 'Build MSIX' : 'Export for Windows',
            ExportTarget.web => 'Export for Web',
            ExportTarget.android => _aab && !_apk ? 'Build app bundle' : 'Build for Android',
          }),
        ),
      ],
    );
  }
}

/// Creates a self-signed certificate for testing MSIX packages on your own PCs.
class _TestCertificateDialog extends StatefulWidget {
  final EmberProject project;
  const _TestCertificateDialog({required this.project});

  @override
  State<_TestCertificateDialog> createState() => _TestCertificateDialogState();
}

class _TestCertificateDialogState extends State<_TestCertificateDialog> {
  late final TextEditingController _subject;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subject = TextEditingController(text: WindowsMsix.publisher(widget.project));
    for (final c in [_subject, _password, _confirm]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_subject, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _problem {
    if (!GameSettings.isValidMsixPublisher(_subject.text)) return 'The publisher starts with CN=, e.g. CN=My Studio.';
    if (_password.text.length < 6) return 'The password needs at least 6 characters.';
    if (_password.text != _confirm.text) return 'The two passwords are different.';
    return null;
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final docs = await getApplicationDocumentsDirectory();
      final sep = Platform.pathSeparator;
      final folder = '${docs.path}${sep}Ember Keys';
      final base = '${GameExporter.safeName(widget.project.gameTitle)} test certificate';
      var path = '$folder$sep$base.pfx';
      for (var i = 2; File(path).existsSync(); i++) {
        path = '$folder$sep$base $i.pfx';
      }
      final created = await WindowsMsix.createTestCertificate(pfxPath: path, password: _password.text, subject: _subject.text.trim());
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: EmberTheme.panelBg,
      title: const Text('Create a test certificate', style: TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Signs MSIX packages for testing on your own PCs. Each PC has to trust the certificate once (Ember writes a .cer '
              'file for that). Players downloading from the internet need a certificate from a certificate authority, or the Microsoft Store.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('cert-subject'), controller: _subject, decoration: const InputDecoration(labelText: 'Publisher (certificate subject)', isDense: true)),
            const SizedBox(height: 8),
            TextField(key: const ValueKey('cert-password'), controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (6+ characters)', isDense: true)),
            const SizedBox(height: 8),
            TextField(key: const ValueKey('cert-confirm'), controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Password again', isDense: true)),
            const SizedBox(height: 8),
            const Text('Saved in Documents/Ember Keys.', style: TextStyle(color: Colors.white54, fontSize: 11)),
            if (_problem != null && (_password.text.isNotEmpty || _confirm.text.isNotEmpty))
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(_problem!, style: const TextStyle(color: Colors.amberAccent, fontSize: 11))),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(color: EmberTheme.emberOrange)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(key: const ValueKey('cert-create'), onPressed: _busy || _problem != null ? null : _create, child: const Text('Create certificate')),
      ],
    );
  }
}

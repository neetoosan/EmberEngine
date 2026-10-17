import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../hub/android_signing.dart';
import '../hub/game_exporter.dart';
import '../hub/project_manifest.dart';
import '../theme/ember_theme.dart';

/// Creates a new Android upload key for a game. Returns the key and its password.
class CreateAndroidKeyDialog extends StatefulWidget {
  final EmberProject project;
  const CreateAndroidKeyDialog({super.key, required this.project});

  static Future<(AndroidSigningKey, String)?> show(BuildContext context, EmberProject project) =>
      showDialog<(AndroidSigningKey, String)>(context: context, barrierDismissible: false, builder: (_) => CreateAndroidKeyDialog(project: project));

  @override
  State<CreateAndroidKeyDialog> createState() => _CreateAndroidKeyDialogState();
}

class _CreateAndroidKeyDialogState extends State<CreateAndroidKeyDialog> {
  final _name = TextEditingController();
  final _country = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _folder;
  bool _busy = false;
  String? _error;

  String get _fileName => '${GameExporter.safeName(widget.project.gameTitle)} upload key.p12';

  @override
  void initState() {
    super.initState();
    _name.text = widget.project.publisherName;
    for (final c in [_name, _country, _password, _confirm]) {
      c.addListener(() => setState(() {}));
    }
    _defaultFolder();
  }

  Future<void> _defaultFolder() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      if (mounted) setState(() => _folder ??= '${docs.path}${Platform.pathSeparator}Ember Keys');
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_name, _country, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _problem {
    if (_password.text.length < 6) return 'The password needs at least 6 characters.';
    if (_password.text != _confirm.text) return 'The two passwords are different.';
    if (_country.text.isNotEmpty && !RegExp(r'^[A-Za-z]{2}$').hasMatch(_country.text)) return 'Country: two letters (e.g. NG, US) or leave empty.';
    if (_folder == null) return 'Choose a folder for the key.';
    return null;
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await AndroidSigning.createKey(
        keystorePath: '$_folder${Platform.pathSeparator}$_fileName',
        alias: 'upload',
        password: _password.text,
        name: _name.text,
        countryCode: _country.text,
      );
      if (mounted) Navigator.of(context).pop((key, _password.text));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noKeytool = AndroidSigning.findKeytool() == null;
    return AlertDialog(
      backgroundColor: EmberTheme.panelBg,
      title: const Text('Create an upload key', style: TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Google Play needs every build of a game to be signed with the same key. Ember creates the key file here; '
                'only you have it.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.amber.withAlpha(30), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amberAccent.withAlpha(120))),
                child: const Text(
                  'Back up the key file and its password (e.g. a password manager and a USB stick). If you lose them you cannot '
                  'update your game, unless you use Play App Signing and ask Google to reset your upload key.',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your name or studio', isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: _country, decoration: const InputDecoration(labelText: 'Country code (optional, e.g. NG)', isDense: true)),
              const SizedBox(height: 8),
              TextField(key: const ValueKey('key-password'), controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (6+ characters)', isDense: true)),
              const SizedBox(height: 8),
              TextField(key: const ValueKey('key-confirm'), controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Password again', isDense: true)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('Saved as: ${_folder ?? '…'}${Platform.pathSeparator}$_fileName', style: const TextStyle(color: Colors.white70, fontSize: 11))),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final picked = await FilePicker.getDirectoryPath(dialogTitle: 'Where to keep the key file');
                            if (picked != null) setState(() => _folder = picked);
                          },
                    child: const Text('Change…'),
                  ),
                ],
              ),
              if (noKeytool)
                const Text('keytool was not found: install Android Studio (it includes a JDK) or set JAVA_HOME.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              if (_problem != null && (_password.text.isNotEmpty || _confirm.text.isNotEmpty))
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(_problem!, style: const TextStyle(color: Colors.amberAccent, fontSize: 11))),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(color: EmberTheme.emberOrange)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          key: const ValueKey('key-create'),
          onPressed: _busy || noKeytool || _problem != null ? null : _create,
          child: const Text('Create key'),
        ),
      ],
    );
  }
}

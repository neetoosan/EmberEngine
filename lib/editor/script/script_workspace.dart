import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/engine_loop.dart';
import '../../core/event_bus.dart' show PlayState;
import '../../core/game_script.dart';
import '../../scripting/api.dart';
import '../../scripting/script_library.dart';
import '../../scripting/templates.dart';
import '../hub/project_manifest.dart';
import '../theme/ember_theme.dart';
import 'code_editor.dart';

/// Lets other panels (e.g. the Inspector's "Edit script") open a file in the
/// Script workspace.
class ScriptWorkspaceController extends ChangeNotifier {
  static final ScriptWorkspaceController instance = ScriptWorkspaceController._();
  ScriptWorkspaceController._();

  String? pendingFile;
  int pendingLine = 0;

  void open(String file, {int line = 0}) {
    pendingFile = file;
    pendingLine = line;
    notifyListeners();
  }
}

/// The Script workspace: write Ember Script (.ember) files that run on
/// entities, with a reference of everything the engine offers.
class ScriptWorkspace extends StatefulWidget {
  final EmberEngine engine;
  final EmberProject? project;

  /// Writes the project to disk (Ctrl+S).
  final Future<void> Function()? onSaveProject;

  const ScriptWorkspace({super.key, required this.engine, this.project, this.onSaveProject});

  @override
  State<ScriptWorkspace> createState() => ScriptWorkspaceState();
}

class ScriptWorkspaceState extends State<ScriptWorkspace> {
  final Map<String, String> _scratch = {};
  final Map<String, EmberCodeController> _controllers = {};
  final List<String> _tabs = [];
  String? _active;
  final Set<String> _unsaved = {};
  final FocusNode _editorFocus = FocusNode(debugLabel: 'code editor');
  final GlobalKey<ScriptCodeEditorState> _editorKey = GlobalKey();
  Timer? _checkTimer;
  ScriptProblem? _liveError;

  bool _showReference = true;
  String _refQuery = '';
  int _bottomTab = 0; // 0 problems, 1 output

  bool _findOpen = false;
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();
  final FocusNode _findFocus = FocusNode();

  Map<String, String> get _files => widget.project?.scripts ?? _scratch;
  EmberScripts get _lib => EmberScripts.instance;

  @override
  void initState() {
    super.initState();
    _lib.addListener(_onLibraryChanged);
    ScriptWorkspaceController.instance.addListener(_onOpenRequest);
    _openFirst();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpenRequest());
  }

  @override
  void didUpdateWidget(covariant ScriptWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project != widget.project) {
      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
      _tabs.clear();
      _active = null;
      _unsaved.clear();
      _openFirst();
    }
  }

  @override
  void dispose() {
    _lib.removeListener(_onLibraryChanged);
    ScriptWorkspaceController.instance.removeListener(_onOpenRequest);
    _checkTimer?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _editorFocus.dispose();
    _find.dispose();
    _replace.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  void _onOpenRequest() {
    final c = ScriptWorkspaceController.instance;
    final file = c.pendingFile;
    if (file == null || !mounted) return;
    c.pendingFile = null;
    if (!_files.containsKey(file)) return;
    openFile(file);
    if (c.pendingLine > 0) {
      final line = c.pendingLine;
      WidgetsBinding.instance.addPostFrameCallback((_) => _editorKey.currentState?.goToLine(line));
    }
  }

  void _openFirst() {
    final ember = _files.keys.where(EmberScripts.isScriptFile).toList()..sort();
    if (ember.isNotEmpty) openFile(ember.first);
  }

  // --- Files ---

  void openFile(String file) {
    if (!_files.containsKey(file)) return;
    _controllers.putIfAbsent(file, () {
      final c = EmberCodeController(text: _files[file]);
      c.addListener(() => _onEdited(file, c));
      return c;
    });
    setState(() {
      if (!_tabs.contains(file)) _tabs.add(file);
      _active = file;
      _liveError = EmberScripts.isScriptFile(file) ? EmberScripts.check(file, _files[file]!) : null;
    });
  }

  void _closeTab(String file) {
    setState(() {
      _tabs.remove(file);
      _controllers.remove(file)?.dispose();
      if (_active == file) _active = _tabs.isEmpty ? null : _tabs.last;
    });
  }

  String? _lastSeen;
  void _onEdited(String file, EmberCodeController c) {
    if (_files[file] == c.text) return;
    _files[file] = c.text;
    _unsaved.add(file);
    if (_lastSeen != file) setState(() {});
    _lastSeen = file;
    if (!EmberScripts.isScriptFile(file)) return;
    _checkTimer?.cancel();
    _checkTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final error = EmberScripts.check(file, c.text);
      // Valid code goes live at once (running entities hot-reload); broken code waits
      if (error == null) _lib.update(file, c.text);
      setState(() => _liveError = error);
    });
  }

  Future<void> save() async {
    _checkTimer?.cancel();
    for (final f in _unsaved) {
      if (EmberScripts.isScriptFile(f)) _lib.update(f, _files[f]!);
    }
    final file = _active;
    if (file != null && EmberScripts.isScriptFile(file)) _liveError = EmberScripts.check(file, _files[file]!);
    await widget.onSaveProject?.call();
    if (mounted) setState(_unsaved.clear);
  }

  static String _fileNameFor(String name) {
    var s = name.trim().replaceAll(RegExp(r'\.ember$'), '');
    s = s.replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => '_${m[1]}').toLowerCase();
    s = s.replaceAll(RegExp(r'[^a-z0-9_]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    return s.isEmpty ? '' : '$s${EmberScripts.extension}';
  }

  /// Creates a script from a template; returns its file name.
  String createScript(String name, ScriptTemplate template) {
    var file = _fileNameFor(name);
    if (file.isEmpty) file = 'script${EmberScripts.extension}';
    var n = 2;
    final base = file.replaceAll(EmberScripts.extension, '');
    while (_files.containsKey(file)) {
      file = '${base}_$n${EmberScripts.extension}';
      n++;
    }
    _files[file] = template.source;
    _lib.update(file, template.source);
    _unsaved.add(file);
    openFile(file);
    return file;
  }

  Future<void> _newScriptDialog() async {
    final nameCtrl = TextEditingController(text: 'my_script');
    var template = scriptTemplates.first;
    final result = await showDialog<(String, ScriptTemplate)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: EmberTheme.panelBg,
          title: const Text('New Ember Script', style: TextStyle(color: Colors.white, fontSize: 15)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('new-script-name'),
                  controller: nameCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Name (e.g. player, enemy, coin)', filled: true),
                ),
                const SizedBox(height: 12),
                const Text('Start from', style: TextStyle(color: EmberTheme.textSecondary, fontSize: 11)),
                const SizedBox(height: 6),
                for (final t in scriptTemplates)
                  InkWell(
                    onTap: () => setD(() => template = t),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: template == t ? EmberTheme.accentEmber.withValues(alpha: 0.15) : EmberTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: template == t ? EmberTheme.accentEmber : EmberTheme.borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                Text(t.description, style: const TextStyle(color: EmberTheme.textSecondary, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.accentEmber, foregroundColor: Colors.white),
              onPressed: () => Navigator.of(ctx).pop((nameCtrl.text, template)),
              child: const Text('Create Script'),
            ),
          ],
        ),
      ),
    );
    if (result != null) createScript(result.$1, result.$2);
  }

  Future<void> _renameActive() async {
    final old = _active;
    if (old == null) return;
    final ctrl = TextEditingController(text: old.replaceAll(EmberScripts.extension, ''));
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EmberTheme.panelBg,
        title: const Text('Rename script', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(controller: ctrl, autofocus: true, onSubmitted: (v) => Navigator.of(ctx).pop(v)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Rename')),
        ],
      ),
    );
    if (name == null) return;
    final file = EmberScripts.isScriptFile(old) ? _fileNameFor(name) : name.trim();
    if (file.isEmpty || file == old || _files.containsKey(file)) return;
    final source = _files.remove(old)!;
    _files[file] = source;
    _lib.remove(old);
    _lib.update(file, source);
    // Entities using the old name follow the rename
    var moved = 0;
    for (final e in widget.engine.activeScene.allEntities) {
      for (final c in e.components.whereType<ScriptComponent>()) {
        if (c.scriptName == old) {
          c.scriptName = file;
          moved++;
        }
      }
    }
    _controllers.remove(old)?.dispose();
    _tabs.remove(old);
    _unsaved.add(file);
    openFile(file);
    widget.engine.log('Renamed $old to $file${moved > 0 ? ' ($moved entities updated)' : ''}', source: 'Scripts');
  }

  Future<void> _deleteActive() async {
    final file = _active;
    if (file == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EmberTheme.panelBg,
        title: Text('Delete $file?', style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: const Text('Entities using it will keep a Script Component that does nothing.',
            style: TextStyle(color: EmberTheme.textSecondary, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _files.remove(file);
    _lib.remove(file);
    _unsaved.add(file);
    _closeTab(file);
  }

  void attachToSelected() {
    final file = _active;
    final entity = widget.engine.selectedEntity;
    if (file == null || !EmberScripts.isScriptFile(file)) return;
    if (entity == null) {
      _toast('Select an entity in the Scene workspace first (Ctrl+1), then attach.');
      return;
    }
    if (entity.components.whereType<ScriptComponent>().any((c) => c.scriptName == file)) {
      _toast('${entity.name} already runs $file');
      return;
    }
    _lib.update(file, _files[file]!);
    entity.addComponent(ScriptComponent(scriptName: file));
    widget.engine.selectEntity(entity);
    _toast('Attached $file to ${entity.name}');
  }

  void _toast(String msg) {
    widget.engine.log(msg, source: 'Scripts');
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: EmberTheme.textPrimary)),
        backgroundColor: EmberTheme.surfaceCard,
        duration: const Duration(seconds: 2),
      ));
  }

  // --- Find ---

  void _openFind() {
    setState(() => _findOpen = true);
    final sel = _controllers[_active]?.selection;
    final c = _controllers[_active];
    if (c != null && sel != null && sel.isValid && !sel.isCollapsed) _find.text = sel.textInside(c.text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _findFocus.requestFocus());
  }

  void _findNext({bool backwards = false}) {
    final c = _controllers[_active];
    final q = _find.text;
    if (c == null || q.isEmpty) return;
    final text = c.text.toLowerCase(), query = q.toLowerCase();
    final from = c.selection.isValid ? (backwards ? c.selection.start - 1 : c.selection.end) : 0;
    var i = backwards ? text.lastIndexOf(query, from < 0 ? text.length : from) : text.indexOf(query, from);
    if (i < 0) i = backwards ? text.lastIndexOf(query) : text.indexOf(query);
    if (i >= 0) _editorKey.currentState?.select(i, i + q.length);
    setState(() {});
  }

  void _replaceOne() {
    final c = _controllers[_active];
    if (c == null) return;
    final sel = c.selection;
    if (sel.isValid && !sel.isCollapsed && sel.textInside(c.text).toLowerCase() == _find.text.toLowerCase()) {
      c.value = TextEditingValue(
        text: c.text.replaceRange(sel.start, sel.end, _replace.text),
        selection: TextSelection.collapsed(offset: sel.start + _replace.text.length),
      );
    }
    _findNext();
  }

  void _replaceAll() {
    final c = _controllers[_active];
    if (c == null || _find.text.isEmpty) return;
    final count = RegExp(RegExp.escape(_find.text), caseSensitive: false).allMatches(c.text).length;
    c.text = c.text.replaceAll(RegExp(RegExp.escape(_find.text), caseSensitive: false), _replace.text);
    _toast('Replaced $count');
  }

  int get _matchCount {
    final c = _controllers[_active];
    if (c == null || _find.text.isEmpty) return 0;
    return RegExp(RegExp.escape(_find.text), caseSensitive: false).allMatches(c.text).length;
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EmberTheme.surfaceCanvas,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 220, child: _fileList()),
          const VerticalDivider(width: 1, color: EmberTheme.borderSubtle),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolbar(),
                _tabBar(),
                if (_findOpen) _findBar(),
                Expanded(child: _editorArea()),
                _errorStrip(),
                SizedBox(height: 150, child: _bottomPanel()),
              ],
            ),
          ),
          if (_showReference) ...[
            const VerticalDivider(width: 1, color: EmberTheme.borderSubtle),
            SizedBox(width: 300, child: _reference()),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(text.toUpperCase(),
                  style: const TextStyle(color: EmberTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ),
            ?trailing,
          ],
        ),
      );

  Widget _fileList() {
    final ember = _files.keys.where(EmberScripts.isScriptFile).toList()..sort();
    final notes = _files.keys.where((f) => !EmberScripts.isScriptFile(f)).toList()..sort();
    final users = <String, int>{};
    for (final e in widget.engine.activeScene.allEntities) {
      for (final c in e.components.whereType<ScriptComponent>()) {
        users[c.scriptName] = (users[c.scriptName] ?? 0) + 1;
      }
    }
    return Container(
      color: EmberTheme.surfacePanel,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _sectionTitle('Scripts',
              trailing: IconButton(
                key: const ValueKey('new-script-button'),
                tooltip: 'New script',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 16, color: EmberTheme.accentEmber),
                onPressed: _newScriptDialog,
              )),
          if (ember.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No scripts yet. Scripts give entities behaviour: movement, enemies, pickups, UI…',
                      style: TextStyle(color: EmberTheme.textSecondary, fontSize: 11)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.accentEmber, foregroundColor: Colors.white),
                    onPressed: _newScriptDialog,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('New Script', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          for (final f in ember) _fileRow(f, users[f] ?? 0),
          _sectionTitle('Built into the engine'),
          for (final name in ScriptRegistry.builtInScripts.toList()..sort())
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Row(children: [
                const Icon(Icons.lock_outline, size: 12, color: EmberTheme.textMuted),
                const SizedBox(width: 6),
                Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: EmberTheme.textSecondary, fontSize: 11))),
              ]),
            ),
          if (notes.isNotEmpty) ...[
            _sectionTitle('Notes (not run)'),
            for (final f in notes) _fileRow(f, 0, note: true),
          ],
        ],
      ),
    );
  }

  Widget _fileRow(String f, int users, {bool note = false}) {
    final hasError = !note && (_lib.compileError(f) != null || _lib.problems.any((p) => p.file == f));
    final selected = f == _active;
    return InkWell(
      onTap: () => openFile(f),
      child: Container(
        color: selected ? EmberTheme.accentEmber.withValues(alpha: 0.12) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(note ? Icons.description_outlined : Icons.bolt, size: 14, color: note ? EmberTheme.textMuted : EmberTheme.accentEmber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(f,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: selected ? Colors.white : EmberTheme.textPrimary, fontSize: 12)),
            ),
            if (_unsaved.contains(f)) const Text('●', style: TextStyle(color: EmberTheme.textSecondary, fontSize: 10)),
            if (users > 0)
              Tooltip(
                message: 'Used by $users entit${users == 1 ? 'y' : 'ies'} in this scene',
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('$users', style: const TextStyle(color: EmberTheme.textMuted, fontSize: 10)),
                ),
              ),
            if (hasError) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.error, size: 12, color: Colors.redAccent)),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() {
    final file = _active;
    final isEmber = file != null && EmberScripts.isScriptFile(file);
    final playing = widget.engine.playState != PlayState.stopped;
    Widget btn(String label, IconData icon, VoidCallback? onTap, {String? tooltip, Key? key}) => Tooltip(
          message: tooltip ?? label,
          child: TextButton.icon(
            key: key,
            onPressed: onTap,
            icon: Icon(icon, size: 14),
            label: Text(label, style: const TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: EmberTheme.textPrimary,
              disabledForegroundColor: EmberTheme.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: EmberTheme.surfacePanel,
        border: Border(bottom: BorderSide(color: EmberTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          btn('New', Icons.add, _newScriptDialog, tooltip: 'New script from a template'),
          btn('Save', Icons.save_outlined, file == null ? null : save, tooltip: 'Save project (Ctrl+S)'),
          btn('Attach to selected', Icons.link, isEmber ? attachToSelected : null,
              tooltip: 'Add this script to the entity selected in the Scene workspace', key: const ValueKey('attach-script')),
          btn('Find', Icons.search, file == null ? null : _openFind, tooltip: 'Find / replace (Ctrl+F)'),
          btn('Rename', Icons.drive_file_rename_outline, file == null ? null : _renameActive),
          btn('Delete', Icons.delete_outline, file == null ? null : _deleteActive),
          const Spacer(),
          if (playing)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('● Live: saved changes apply while playing', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 11)),
            ),
          btn(playing ? 'Stop' : 'Play', playing ? Icons.stop : Icons.play_arrow,
              () => playing ? widget.engine.stop() : widget.engine.play(), tooltip: playing ? 'Stop the game' : 'Play the current scene'),
          IconButton(
            tooltip: _showReference ? 'Hide API reference' : 'Show API reference',
            icon: Icon(Icons.menu_book_outlined, size: 16, color: _showReference ? EmberTheme.accentEmber : EmberTheme.textSecondary),
            onPressed: () => setState(() => _showReference = !_showReference),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Container(
      height: 30,
      color: EmberTheme.surfaceCanvas,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final f in _tabs)
            InkWell(
              onTap: () => openFile(f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: f == _active ? const Color(0xFF1A1C22) : null,
                  border: Border(
                    top: BorderSide(color: f == _active ? EmberTheme.accentEmber : Colors.transparent, width: 2),
                    right: const BorderSide(color: EmberTheme.borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    Text(f, style: TextStyle(color: f == _active ? Colors.white : EmberTheme.textSecondary, fontSize: 11)),
                    if (_unsaved.contains(f)) const Text('  ●', style: TextStyle(color: EmberTheme.textSecondary, fontSize: 9)),
                    const SizedBox(width: 6),
                    InkWell(onTap: () => _closeTab(f), child: const Icon(Icons.close, size: 12, color: EmberTheme.textMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _findBar() {
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: EmberTheme.surfaceCard,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: EmberTheme.surfacePanel,
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: TextField(
              controller: _find,
              focusNode: _findFocus,
              style: const TextStyle(fontSize: 12),
              decoration: deco('Find'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                _findNext();
                _findFocus.requestFocus();
              },
            ),
          ),
          const SizedBox(width: 6),
          Text('$_matchCount', style: const TextStyle(color: EmberTheme.textMuted, fontSize: 11)),
          IconButton(tooltip: 'Previous', icon: const Icon(Icons.arrow_upward, size: 14), onPressed: () => _findNext(backwards: true)),
          IconButton(tooltip: 'Next (Enter)', icon: const Icon(Icons.arrow_downward, size: 14), onPressed: _findNext),
          const SizedBox(width: 8),
          SizedBox(width: 180, child: TextField(controller: _replace, style: const TextStyle(fontSize: 12), decoration: deco('Replace'))),
          TextButton(onPressed: _replaceOne, child: const Text('Replace', style: TextStyle(fontSize: 11))),
          TextButton(onPressed: _replaceAll, child: const Text('All', style: TextStyle(fontSize: 11))),
          const Spacer(),
          IconButton(icon: const Icon(Icons.close, size: 14), onPressed: () => setState(() => _findOpen = false)),
        ],
      ),
    );
  }

  Widget _editorArea() {
    final file = _active;
    final c = file == null ? null : _controllers[file];
    if (file == null || c == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, size: 40, color: EmberTheme.accentEmber),
            const SizedBox(height: 12),
            const Text('Ember Script', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Write behaviour for your entities. Scripts run when you press Play\nand in exported games — no rebuild needed.',
                textAlign: TextAlign.center, style: TextStyle(color: EmberTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.accentEmber, foregroundColor: Colors.white),
              onPressed: _newScriptDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Script'),
            ),
          ],
        ),
      );
    }
    final isEmber = EmberScripts.isScriptFile(file);
    final error = isEmber ? _liveError : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isEmber)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0x33F59E0B),
            child: const Text(
              'This file is a note: it is not run. Ember Scripts (.ember files — create one with New) run in the game.',
              style: TextStyle(color: Color(0xFFFDE68A), fontSize: 11),
            ),
          ),
        Expanded(
          child: Container(
            color: const Color(0xFF1A1C22),
            child: ScriptCodeEditor(
              key: _editorKey,
              controller: c,
              focusNode: _editorFocus,
              errorLine: error?.line ?? 0,
              errorMessage: error?.message,
              onSave: save,
              onFind: _openFind,
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorStrip() {
    final file = _active;
    final error = file != null && EmberScripts.isScriptFile(file) ? _liveError : null;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: error == null ? EmberTheme.surfacePanel : const Color(0xFF3B1414),
      child: Row(
        children: [
          Icon(error == null ? Icons.check_circle_outline : Icons.error_outline,
              size: 13, color: error == null ? const Color(0xFF4ADE80) : Colors.redAccent),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: error == null ? null : () => _editorKey.currentState?.goToLine(error.line, column: error.column),
              child: Text(
                error == null
                    ? (file == null ? '' : (EmberScripts.isScriptFile(file) ? 'No problems' : 'Note file'))
                    : 'Line ${error.line}: ${error.message}',
                key: const ValueKey('script-status'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: error == null ? EmberTheme.textSecondary : const Color(0xFFFCA5A5), fontSize: 11),
              ),
            ),
          ),
          const Text('Ctrl+Space suggestions · Ctrl+/ comment · Ctrl+F find', style: TextStyle(color: EmberTheme.textMuted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _bottomPanel() {
    final problems = _lib.problems;
    Widget tab(String label, int i) => InkWell(
          onTap: () => setState(() => _bottomTab = i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _bottomTab == i ? EmberTheme.accentEmber : Colors.transparent, width: 2)),
            ),
            child: Text(label, style: TextStyle(color: _bottomTab == i ? Colors.white : EmberTheme.textSecondary, fontSize: 11)),
          ),
        );
    return Container(
      decoration: const BoxDecoration(
        color: EmberTheme.surfacePanel,
        border: Border(top: BorderSide(color: EmberTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            tab('Problems (${problems.length})', 0),
            tab('Output (${_lib.output.length})', 1),
            const Spacer(),
            if (_bottomTab == 1)
              TextButton(
                onPressed: () => setState(_lib.output.clear),
                child: const Text('Clear', style: TextStyle(fontSize: 11)),
              ),
          ]),
          Expanded(
            child: _bottomTab == 0
                ? (problems.isEmpty
                    ? const Center(child: Text('No problems. Runtime errors from Play show up here.', style: TextStyle(color: EmberTheme.textMuted, fontSize: 11)))
                    : ListView(
                        children: [
                          for (final p in problems)
                            InkWell(
                              onTap: () {
                                openFile(p.file);
                                WidgetsBinding.instance.addPostFrameCallback((_) => _editorKey.currentState?.goToLine(p.line, column: p.column));
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                                child: Row(children: [
                                  Icon(p.runtime ? Icons.bug_report_outlined : Icons.error_outline, size: 13, color: Colors.redAccent),
                                  const SizedBox(width: 6),
                                  Text(p.location, style: const TextStyle(color: EmberTheme.textSecondary, fontSize: 11)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(p.message + (p.count > 1 ? '  (×${p.count})' : ''),
                                        overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 11)),
                                  ),
                                ]),
                              ),
                            ),
                        ],
                      ))
                : ListView(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    children: [
                      for (final line in _lib.output.reversed)
                        Text(line, style: ScriptCodeEditorState.codeStyle.copyWith(fontSize: 11, height: 1.4)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _reference() {
    final q = _refQuery.toLowerCase();
    bool matches(ApiEntry e) => q.isEmpty || e.signature.toLowerCase().contains(q) || e.doc.toLowerCase().contains(q);
    final groups = <String, List<ApiEntry>>{};
    for (final e in ScriptApi.entries) {
      if (!matches(e)) continue;
      final key = e.owner.isEmpty ? e.category : e.owner;
      groups.putIfAbsent(key, () => []).add(e);
    }
    return Container(
      color: EmberTheme.surfacePanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: TextField(
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search the API (e.g. sound, jump, damage)',
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                filled: true,
                fillColor: EmberTheme.surfaceCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _refQuery = v),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('Click an entry to insert it at the cursor.', style: TextStyle(color: EmberTheme.textMuted, fontSize: 10)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final g in groups.entries) ...[
                  _sectionTitle(g.key),
                  for (final e in g.value) _refRow(e),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _refRow(ApiEntry e) {
    return InkWell(
      onTap: () {
        final editor = _editorKey.currentState;
        if (editor == null) return;
        if (e.isCallback) {
          final params = RegExp(r'\((.*)\)').firstMatch(e.signature)?.group(1) ?? '';
          editor.insertText('\nvoid ${e.name}($params) {\n  \n}\n');
        } else {
          final prefix = e.owner.isEmpty || e.owner == 'Component' || e.owner == 'List' || e.owner == 'Text'
              ? ''
              : (e.owner == 'Entity' ? 'self.' : '${e.owner}.');
          editor.insertText(prefix == 'Vec2.' || prefix == 'Tile.' ? e.insertText : '$prefix${e.insertText}');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.signature, style: ScriptCodeEditorState.codeStyle.copyWith(fontSize: 11.5, height: 1.3, color: e.isCallback ? CodeColors.callback : CodeColors.api)),
            Text(e.doc, style: const TextStyle(color: EmberTheme.textSecondary, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/assets.dart';
import '../core/engine_loop.dart';
import '../core/save_data.dart';
import '../core/event_bus.dart';
import '../core/input.dart';
import '../core/scene.dart';
import '../scripting/script_library.dart';
import 'hub/project_launcher.dart';
import 'hub/project_manifest.dart';
import 'hub/project_storage.dart';
import 'panels/export_dialog.dart';
import 'mobile/virtual_joystick.dart';
import 'panels/bottom_drawer.dart';
import 'panels/command_palette.dart';
import 'panels/doctor_panel.dart';
import 'panels/hierarchy_panel.dart';
import 'panels/inspector_panel.dart';
import 'panels/top_bar.dart';
import 'panels/viewport_container.dart';
import 'script/script_workspace.dart';
import 'shortcuts/editor_shortcuts.dart';
import 'theme/ember_theme.dart';

/// Screen mode for Ember Editor.
enum EditorScreenMode {
  /// Startup Hub / Project Launcher.
  launcher,

  /// Full Engine Workstation.
  editor,
}

/// Ember Engine Editor Application.
///
/// Implements the "Minimal Surface, Maximum Control" workstation UI:
/// - Startup Hub & Project Launcher with Starter Templates & Package Importer
/// - 36px Top Bar with Mode, Gizmo switchers, Doctor diagnostics, and Hub return
/// - 240px Collapsible Left Hierarchy Shelf (Ctrl+B)
/// - Adaptive Central Viewport (2D Flame vs 3D Native)
/// - 300px Collapsible Right Inspector Shelf (Ctrl+I)
/// - Collapsible Bottom Console/Asset/Tilemap/Script Drawer (~)
/// - Spotlight Command Palette (Ctrl+K)
/// - Zen Mode Canvas (Tab / F11)
/// - Mobile Virtual Joystick & Touch overlay
class EmberEditorApp extends StatefulWidget {
  final bool startInLauncher;
  final EmberProject? initialProject;

  const EmberEditorApp({super.key, this.startInLauncher = true, this.initialProject});

  @override
  State<EmberEditorApp> createState() => _EmberEditorAppState();
}

class _EmberEditorAppState extends State<EmberEditorApp> {
  final EmberEngine _engine = EmberEngine.instance;

  late EditorScreenMode _screenMode;
  EmberProject? _currentProject;

  bool _showHierarchy = true;
  bool _showInspector = true;
  bool _isBottomDrawerExpanded = false;
  bool _isZenMode = false;
  bool _showVirtualJoystick = false;

  /// 0 = Scene (viewport, hierarchy, inspector), 1 = Script editor.
  int _workspace = 0;

  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    registerAllSubsystems();
    Input.bindHardwareKeyboard();
    _currentProject = widget.initialProject;
    _screenMode = widget.startInLauncher && widget.initialProject == null ? EditorScreenMode.launcher : EditorScreenMode.editor;
    _engine.addListener(_onEngineUpdate);
    ScriptWorkspaceController.instance.addListener(_onScriptOpenRequest);
    if (_currentProject != null) EmberScripts.instance.loadAll(_currentProject!.scripts);
  }

  /// "Edit script" from the Inspector: jump to the Script workspace.
  void _onScriptOpenRequest() {
    if (ScriptWorkspaceController.instance.pendingFile != null && _workspace != 1) {
      setState(() => _workspace = 1);
    }
  }

  void _setWorkspace(int w) {
    if (_workspace != w) setState(() => _workspace = w);
  }

  Widget _workspaceSwitch(BuildContext context) {
    // Narrow windows: icons only (the top bar is full)
    final compact = MediaQuery.sizeOf(context).width < 1500;
    Widget seg(String label, IconData icon, int w, String tip) => Tooltip(
      message: tip,
      child: InkWell(
        key: ValueKey('workspace-$w'),
        onTap: () => _setWorkspace(w),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 10, vertical: 4),
          decoration: BoxDecoration(
            color: _workspace == w ? EmberTheme.accentEmber.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: _workspace == w ? EmberTheme.accentEmber : EmberTheme.textSecondary),
              if (!compact) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: _workspace == w ? FontWeight.w700 : FontWeight.w500,
                    color: _workspace == w ? Colors.white : EmberTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: EmberTheme.surfaceCard,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: EmberTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Scene', Icons.view_in_ar_outlined, 0, 'Scene workspace (Ctrl+1)'),
          seg('Script', Icons.code, 1, 'Script workspace (Ctrl+2)'),
        ],
      ),
    );
  }

  void _notify(String message, {bool isError = false}) {
    _engine.log(message, severity: isError ? LogSeverity.error : LogSeverity.info, source: 'Project');
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.redAccent : EmberTheme.surfaceCard,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// Copies the edited scene into the project and writes it to disk.
  /// New projects get a folder under Documents/EmberProjects on first save.
  Future<EmberProject?> _saveProject({bool quiet = false}) async {
    final project = _currentProject;
    if (project == null) {
      if (!quiet) _notify('Nothing to save — open or create a project from the Project Hub.', isError: true);
      return null;
    }
    project.scenes[_editingSceneName ?? project.defaultSceneName] = _engine.editableScene;
    if (!ProjectStorage.isSupported) return project;

    try {
      if (!ProjectStorage.hasDiskLocation(project)) {
        project.path = await ProjectStorage.allocateProjectPath(project.name);
      }
      await ProjectStorage.save(project);
      EmberAssets.instance.root = project.path;
      _rememberRecent(project);
      if (!quiet) _notify('Saved "${project.name}" to ${project.path}');
    } catch (e) {
      if (!quiet) _notify('Save failed: $e', isError: true);
      _engine.log('Project not written to disk: $e', severity: LogSeverity.warning, source: 'Project');
    }
    return project;
  }

  void _rememberRecent(EmberProject project) {
    RecentProjectsManager.instance.addOrUpdateRecent(
      RecentProjectInfo(
        id: project.id,
        name: project.name,
        path: project.path,
        templateName: project.defaultSceneName,
        lastOpened: DateTime.now(),
        renderPipeline: project.renderPipeline,
        previewSnippet: project.description,
      ),
    );
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineUpdate);
    ScriptWorkspaceController.instance.removeListener(_onScriptOpenRequest);
    super.dispose();
  }

  void _onEngineUpdate() {
    if (mounted) setState(() {});
  }

  // --- Scenes / levels ---

  /// Key in [EmberProject.scenes] of the scene open in the editor.
  String? _editingSceneName;

  /// Scene JSON by name for `EmberEngine.loadLevel`; the scene being edited is
  /// taken as it was when Play was pressed.
  Map<String, Map<String, dynamic>> _sceneLibrary() {
    final project = _currentProject;
    if (project == null) return {};
    return {
      for (final e in project.scenes.entries)
        e.key: e.key == _editingSceneName ? _engine.editableScene.toJson() : e.value.toJson(),
    };
  }

  /// Opens another scene of the project for editing (keeping the current one).
  void _openScene(String name) {
    final project = _currentProject;
    if (project == null || !project.scenes.containsKey(name) || name == _editingSceneName) return;
    _engine.stop();
    // Store a copy: loading the next scene destroys the one on screen.
    if (_editingSceneName != null) {
      project.scenes[_editingSceneName!] = EmberScene.fromJson(_engine.activeScene.toJson());
    }
    setState(() => _editingSceneName = name);
    _engine.loadScene(EmberScene.fromJson(project.scenes[name]!.toJson()));
  }

  Future<void> _newScene(BuildContext ctx) async {
    final project = _currentProject;
    if (project == null) return;
    var n = project.scenes.length + 1;
    while (project.scenes.containsKey('Level $n')) {
      n++;
    }
    final controller = TextEditingController(text: 'Level $n');
    final name = await showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: EmberTheme.panelBg,
        title: const Text('New Scene', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Scene name'),
          onSubmitted: (v) => Navigator.of(dctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(dctx).pop(controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (project.scenes.containsKey(name)) {
      _notify('A scene called "$name" already exists', isError: true);
      return;
    }
    project.scenes[name] = EmberScene.starterFor(name, is2D: _engine.mode == EngineMode.twoD);
    _openScene(name);
    _notify('Created scene "$name"');
  }

  void _setStartScene() {
    final project = _currentProject;
    final name = _editingSceneName;
    if (project == null || name == null) return;
    setState(() => project.defaultSceneName = name);
    _notify('"$name" is now the scene the game starts in');
  }

  void _deleteScene() {
    final project = _currentProject;
    final name = _editingSceneName;
    if (project == null || name == null || project.scenes.length < 2) return;
    project.scenes.remove(name);
    if (project.defaultSceneName == name) project.defaultSceneName = project.scenes.keys.first;
    _editingSceneName = null;
    _openScene(project.defaultSceneName);
    _notify('Deleted scene "$name"');
  }

  Widget? _buildSceneMenu(BuildContext ctx) {
    final project = _currentProject;
    if (project == null) return null;
    final current = _editingSceneName ?? project.defaultSceneName;
    return PopupMenuButton<String>(
      tooltip: 'Scenes / levels',
      color: EmberTheme.surfaceCard,
      onSelected: (v) {
        switch (v) {
          case '\u0000new':
            _newScene(ctx);
          case '\u0000start':
            _setStartScene();
          case '\u0000delete':
            _deleteScene();
          default:
            _openScene(v);
        }
      },
      itemBuilder: (_) => [
        for (final name in project.scenes.keys)
          PopupMenuItem(
            value: name,
            child: Text(
              '${name == current ? '● ' : '   '}$name${name == project.defaultSceneName ? '  (start)' : ''}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '\u0000new',
          child: Text('+ New scene…', style: TextStyle(fontSize: 11)),
        ),
        const PopupMenuItem(
          value: '\u0000start',
          child: Text('Set as start scene', style: TextStyle(fontSize: 11)),
        ),
        if (project.scenes.length > 1)
          const PopupMenuItem(
            value: '\u0000delete',
            child: Text('Delete this scene', style: TextStyle(fontSize: 11)),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              current,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: EmberTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          // Flexible too: on a crowded top bar everything shrinks instead of overflowing
          const Flexible(child: Icon(Icons.arrow_drop_down, size: 16, color: EmberTheme.textSecondary)),
        ],
      ),
    );
  }

  void _onOpenProject(EmberProject project) {
    _engine.stop();
    // Sprites resolve against the project folder (template art falls back to the engine bundle).
    EmberAssets.instance.root = ProjectStorage.hasDiskLocation(project) ? project.path : null;
    SaveData.instance.open('${project.name} (editor)');
    // Before the scene loads, so its Script Components find their .ember scripts
    EmberScripts.instance.loadAll(project.scripts);
    _engine.sceneLibrary = _sceneLibrary;
    setState(() {
      _currentProject = project;
      _editingSceneName = project.scenes.containsKey(project.defaultSceneName)
          ? project.defaultSceneName
          : (project.scenes.isEmpty ? project.defaultSceneName : project.scenes.keys.first);
      final targetMode = project.renderPipeline == RenderPipelineMode.twoD ? EngineMode.twoD : EngineMode.threeD;
      _engine.preserveSceneOnModeSwitch = false;
      _engine.setMode(targetMode);
      _engine.loadScene(project.activeScene);
      _engine.preserveSceneOnModeSwitch = true;
      _screenMode = EditorScreenMode.editor;
    });

    if (ProjectStorage.hasDiskLocation(project)) {
      _rememberRecent(project);
    } else {
      // Brand-new project: give it a folder on disk right away (in the background).
      _saveProject(quiet: true).then((p) {
        if (p != null && ProjectStorage.hasDiskLocation(p)) {
          _notify('Created project folder ${p.path}');
        }
      });
    }
  }

  void _openCommandPalette(BuildContext ctx) {
    showDialog(
      context: ctx,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogCtx) => CommandPaletteDialog(
        engine: _engine,
        onToggleHierarchy: () => setState(() => _showHierarchy = !_showHierarchy),
        onToggleInspector: () => setState(() => _showInspector = !_showInspector),
        onToggleBottomDrawer: () => setState(() => _isBottomDrawerExpanded = !_isBottomDrawerExpanded),
        onToggleZenMode: _toggleZenMode,
      ),
    );
  }

  void _toggleZenMode() {
    setState(() {
      _isZenMode = !_isZenMode;
      if (_isZenMode) {
        _showHierarchy = false;
        _showInspector = false;
        _isBottomDrawerExpanded = false;
      } else {
        _showHierarchy = true;
        _showInspector = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ember Engine',
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      theme: EmberTheme.darkTheme,
      navigatorKey: _navigatorKey,
      // Shortcuts sit above the navigator, so they work wherever the focus is
      // (even after clicking out of a text field, when no widget has focus).
      builder: (context, child) => _screenMode == EditorScreenMode.editor
          ? EditorShortcutsWrapper(
              engine: _engine,
              onOpenCommandPalette: () {
                final ctx = _navigatorKey.currentContext;
                if (ctx != null) _openCommandPalette(ctx);
              },
              onToggleHierarchy: () => setState(() => _showHierarchy = !_showHierarchy),
              onToggleInspector: () => setState(() => _showInspector = !_showInspector),
              onToggleBottomDrawer: () => setState(() => _isBottomDrawerExpanded = !_isBottomDrawerExpanded),
              onToggleZenMode: _toggleZenMode,
              onSave: _saveProject,
              onSwitchWorkspace: _setWorkspace,
              child: child!,
            )
          : child!,
      home: Builder(
        builder: (appContext) {
          if (_screenMode == EditorScreenMode.launcher) {
            return ProjectLauncherScreen(onOpenProject: _onOpenProject);
          }

          return Scaffold(
            backgroundColor: EmberTheme.surfaceCanvas,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Top Bar (36px)
                EditorTopBar(
                  engine: _engine,
                  onOpenCommandPalette: () => _openCommandPalette(appContext),
                  onToggleZenMode: _toggleZenMode,
                  onToggleVirtualJoystick: () => setState(() => _showVirtualJoystick = !_showVirtualJoystick),
                  showVirtualJoystick: _showVirtualJoystick,
                  onOpenProjectHub: () => setState(() => _screenMode = EditorScreenMode.launcher),
                  onOpenDoctor: () => EmberDoctorDialog.show(appContext, project: _currentProject),
                  onSaveScene: _saveProject,
                  onExportGame: ProjectStorage.isSupported
                      ? () => ExportGameDialog.show(appContext, prepareProject: _saveProject)
                      : null,
                  sceneSelector: _buildSceneMenu(appContext),
                  workspaceSwitch: _workspaceSwitch(appContext),
                ),

                // 2. Middle: Scene workspace (Hierarchy + Viewport + Inspector) or the
                // Script workspace. Both stay alive so switching keeps their state.
                Expanded(
                  child: IndexedStack(
                    index: _workspace,
                    sizing: StackFit.expand,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left Shelf: Hierarchy
                          if (_showHierarchy) HierarchyPanel(engine: _engine),

                          // Central Viewport Canvas + Virtual Joystick
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(child: ViewportContainer(engine: _engine)),
                                if (_showVirtualJoystick) const Positioned.fill(child: VirtualJoystickOverlay(isVisible: true)),
                              ],
                            ),
                          ),

                          // Right Shelf: Inspector
                          if (_showInspector) InspectorPanel(engine: _engine),
                        ],
                      ),
                      ScriptWorkspace(
                        engine: _engine,
                        project: _currentProject,
                        onSaveProject: () async => _saveProject(quiet: false),
                      ),
                    ],
                  ),
                ),

                // 3. Bottom Console, Asset, Tilemap & Script Drawer
                BottomDrawer(
                  engine: _engine,
                  project: _currentProject,
                  isExpanded: _isBottomDrawerExpanded,
                  onToggleExpand: () => setState(() => _isBottomDrawerExpanded = !_isBottomDrawerExpanded),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

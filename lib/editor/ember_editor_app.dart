import 'package:flutter/material.dart';
import '../core/assets.dart';
import '../core/engine_loop.dart';
import '../core/save_data.dart';
import '../core/event_bus.dart';
import '../core/input.dart';
import '../core/scene.dart';
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

  const EmberEditorApp({
    super.key,
    this.startInLauncher = true,
    this.initialProject,
  });

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

  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    registerAllSubsystems();
    Input.bindHardwareKeyboard();
    _currentProject = widget.initialProject;
    _screenMode = widget.startInLauncher && widget.initialProject == null
        ? EditorScreenMode.launcher
        : EditorScreenMode.editor;
    _engine.addListener(_onEngineUpdate);
  }

  void _notify(String message, {bool isError = false}) {
    _engine.log(message, severity: isError ? LogSeverity.error : LogSeverity.info, source: 'Project');
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : EmberTheme.surfaceCard,
        duration: const Duration(seconds: 3),
      ));
  }

  /// Copies the edited scene into the project and writes it to disk.
  /// New projects get a folder under Documents/EmberProjects on first save.
  Future<EmberProject?> _saveProject({bool quiet = false}) async {
    final project = _currentProject;
    if (project == null) {
      if (!quiet) _notify('Nothing to save — open or create a project from the Project Hub.', isError: true);
      return null;
    }
    project.scenes[project.defaultSceneName] = _engine.editableScene;
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
    super.dispose();
  }

  void _onEngineUpdate() {
    if (mounted) setState(() {});
  }

  void _onOpenProject(EmberProject project) {
    _engine.stop();
    // Sprites resolve against the project folder (template art falls back to the engine bundle).
    EmberAssets.instance.root = ProjectStorage.hasDiskLocation(project) ? project.path : null;
    SaveData.instance.open('${project.name} (editor)');
    setState(() {
      _currentProject = project;
      final targetMode = project.renderPipeline == RenderPipelineMode.twoD
          ? EngineMode.twoD
          : EngineMode.threeD;
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
      home: Builder(
        builder: (appContext) {
          if (_screenMode == EditorScreenMode.launcher) {
            return ProjectLauncherScreen(
              onOpenProject: _onOpenProject,
            );
          }

          return Scaffold(
            backgroundColor: EmberTheme.surfaceCanvas,
            body: EditorShortcutsWrapper(
              engine: _engine,
              onOpenCommandPalette: () => _openCommandPalette(appContext),
              onToggleHierarchy: () => setState(() => _showHierarchy = !_showHierarchy),
              onToggleInspector: () => setState(() => _showInspector = !_showInspector),
              onToggleBottomDrawer: () => setState(() => _isBottomDrawerExpanded = !_isBottomDrawerExpanded),
              onToggleZenMode: _toggleZenMode,
              onSave: _saveProject,
              child: Column(
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
                  ),

                  // 2. Middle Workstation Area (Hierarchy + Adaptive Viewport + Inspector)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Shelf: Hierarchy
                        if (_showHierarchy)
                          HierarchyPanel(engine: _engine),

                        // Central Viewport Canvas + Virtual Joystick
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(child: ViewportContainer(engine: _engine)),
                              if (_showVirtualJoystick)
                                const Positioned.fill(
                                  child: VirtualJoystickOverlay(
                                    isVisible: true,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Right Shelf: Inspector
                        if (_showInspector)
                          InspectorPanel(engine: _engine),
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
            ),
          );
        },
      ),
    );
  }
}

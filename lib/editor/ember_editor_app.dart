import 'package:flutter/material.dart';
import '../core/engine_loop.dart';
import '../subsystems/three_d/components3d.dart';
import '../subsystems/two_d/flame_components.dart';
import 'panels/bottom_drawer.dart';
import 'panels/command_palette.dart';
import 'panels/hierarchy_panel.dart';
import 'panels/inspector_panel.dart';
import 'panels/top_bar.dart';
import 'panels/viewport_container.dart';
import 'shortcuts/editor_shortcuts.dart';
import 'theme/ember_theme.dart';

/// Ember Engine Editor Application.
///
/// Implements the "Minimal Surface, Maximum Control" workstation UI:
/// - 36px Top Bar with Mode and Gizmo switchers
/// - 240px Collapsible Left Hierarchy Shelf (Ctrl+B)
/// - Adaptive Central Viewport (2D Flame vs 3D Native)
/// - 300px Collapsible Right Inspector Shelf (Ctrl+I)
/// - Collapsible Bottom Console/Asset Drawer (~)
/// - Spotlight Command Palette (Ctrl+K)
/// - Zen Mode Canvas (Tab / F11)
class EmberEditorApp extends StatefulWidget {
  const EmberEditorApp({super.key});

  @override
  State<EmberEditorApp> createState() => _EmberEditorAppState();
}

class _EmberEditorAppState extends State<EmberEditorApp> {
  final EmberEngine _engine = EmberEngine.instance;

  bool _showHierarchy = true;
  bool _showInspector = true;
  bool _isBottomDrawerExpanded = false;
  bool _isZenMode = false;

  @override
  void initState() {
    super.initState();
    register3DComponents();
    registerFlameComponents();
    _engine.addListener(_onEngineUpdate);
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineUpdate);
    super.dispose();
  }

  void _onEngineUpdate() {
    if (mounted) setState(() {});
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
      debugShowCheckedModeBanner: false,
      theme: EmberTheme.darkTheme,
      home: Builder(
        builder: (appContext) => Scaffold(
          backgroundColor: EmberTheme.surfaceCanvas,
          body: EditorShortcutsWrapper(
            engine: _engine,
            onOpenCommandPalette: () => _openCommandPalette(appContext),
            onToggleHierarchy: () => setState(() => _showHierarchy = !_showHierarchy),
            onToggleInspector: () => setState(() => _showInspector = !_showInspector),
            onToggleBottomDrawer: () => setState(() => _isBottomDrawerExpanded = !_isBottomDrawerExpanded),
            onToggleZenMode: _toggleZenMode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Top Bar (36px)
                EditorTopBar(
                  engine: _engine,
                  onOpenCommandPalette: () => _openCommandPalette(appContext),
                  onToggleZenMode: _toggleZenMode,
                ),

                // 2. Middle Workstation Area (Hierarchy + Adaptive Viewport + Inspector)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left Shelf: Hierarchy
                      if (_showHierarchy)
                        HierarchyPanel(engine: _engine),

                      // Central Viewport Canvas
                      Expanded(
                        child: ViewportContainer(engine: _engine),
                      ),

                      // Right Shelf: Inspector
                      if (_showInspector)
                        InspectorPanel(engine: _engine),
                    ],
                  ),
                ),

                // 3. Bottom Console & Asset Drawer
                BottomDrawer(
                  engine: _engine,
                  isExpanded: _isBottomDrawerExpanded,
                  onToggleExpand: () => setState(() => _isBottomDrawerExpanded = !_isBottomDrawerExpanded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

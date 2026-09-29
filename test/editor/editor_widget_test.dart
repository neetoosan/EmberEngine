import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/editor/ember_editor_app.dart';
import 'package:ember_engine/editor/panels/command_palette.dart';
import 'package:ember_engine/editor/panels/hierarchy_panel.dart';
import 'package:ember_engine/editor/panels/inspector_panel.dart';
import 'package:ember_engine/editor/panels/top_bar.dart';

void main() {
  testWidgets('Ember Editor App full workstation smoke test', (WidgetTester tester) async {
    // Set desktop screen size for testing desktop editor layout
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const EmberEditorApp(startInLauncher: false));
    await tester.pumpAndSettle();

    // 1. Verify Top Bar
    expect(find.text('EMBER'), findsOneWidget);
    expect(find.byType(EditorTopBar), findsOneWidget);
    expect(find.text('2D (Flame)'), findsOneWidget);
    expect(find.text('3D Native'), findsOneWidget);

    // 2. Verify Hierarchy Panel
    expect(find.byType(HierarchyPanel), findsOneWidget);
    expect(find.text('Hierarchy'), findsOneWidget);
    expect(find.text('Hero Cube'), findsOneWidget);

    // 3. Verify Inspector Panel
    expect(find.byType(InspectorPanel), findsOneWidget);

    // 4. Tap on "Hero Cube" in hierarchy to select it
    await tester.tap(find.text('Hero Cube'));
    await tester.pumpAndSettle();

    expect(EmberEngine.instance.selectedEntity?.name, 'Hero Cube');
    // Inspector should now display Hero Cube's Transform 3D
    expect(find.text('Transform 3D'), findsOneWidget);
    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Scale'), findsOneWidget);

    // 5. Test Mode Switcher: Switch to 2D
    await tester.tap(find.text('2D (Flame)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(EmberEngine.instance.mode, EngineMode.twoD);
    expect(find.text('PlayerCharacter'), findsOneWidget);

    // 6. Test Bottom Drawer Toggle
    expect(find.text('Console & Assets'), findsOneWidget);
    await tester.tap(find.text('Console & Assets'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Console'), findsOneWidget);
    expect(find.text('Asset Browser'), findsOneWidget);
    expect(find.text('Tilemap Palette'), findsOneWidget);

    // 7. Test Command Palette
    await tester.tap(find.text('Ctrl+K'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CommandPaletteDialog), findsOneWidget);
    expect(find.text('Type a command or action...'), findsOneWidget);

    // Close palette
    await tester.tap(find.text('ESC to close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CommandPaletteDialog), findsNothing);
  });
}

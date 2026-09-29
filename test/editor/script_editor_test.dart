import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/panels/script_editor_panel.dart';

void main() {
  group('In-Engine Script Editor & Code Bridge Tests', () {
    testWidgets('DartSyntaxTextController parses and colors syntax elements', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      final context = tester.element(find.byType(SizedBox));

      final controller = DartSyntaxTextController();
      controller.text = '''
// This is a test comment
import 'package:ember_engine/core/game_script.dart';

class TestScript extends GameScript {
  int count = 42;
  String message = "Hello Ember";

  @override
  void onUpdate(double dt) {
    if (count > 0) {
      count -= 1;
    }
  }
}
''';

      final span = controller.buildTextSpan(
        context: context,
        withComposing: false,
      );

      expect(span.children, isNotNull);
      expect(span.children!.length, greaterThan(1));

      // Inspect span styles: comments, strings, keywords, and types should be present
      final styles = span.children!.map((s) => (s as TextSpan).style?.color).toList();
      expect(styles, contains(const Color(0xFF64748B))); // Comment slate
      expect(styles, contains(const Color(0xFFFF5722))); // Keyword ember orange
      expect(styles, contains(const Color(0xFFFBBF24))); // String amber
      expect(styles, contains(const Color(0xFF38BDF8))); // Type sky blue
    });

    testWidgets('ScriptEditorPanel renders tabs, toolbar, and visual bridge', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final project = EmberProject(
        id: 'test_proj',
        name: 'Scripting Test Project',
      );
      project.scripts['test_script.dart'] = '''
import 'package:ember_engine/core/game_script.dart';

class TestScript extends GameScript {
  @override
  void onStart() {}
}
''';

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ScriptEditorPanel(project: project),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 1. Verify tab title
      expect(find.text('test_script.dart'), findsOneWidget);

      // 2. Verify Snippet buttons
      expect(find.text('+ onStart()'), findsOneWidget);
      expect(find.text('+ onUpdate(dt)'), findsOneWidget);
      expect(find.text('+ Trigger Audio'), findsOneWidget);
      expect(find.text('+ Burst Particles'), findsOneWidget);

      // 3. Verify Code View and Visual Bridge toggles
      expect(find.text('Code View'), findsOneWidget);
      expect(find.text('Visual Logic Bridge'), findsOneWidget);

      // 4. Test clicking '+ onUpdate(dt)' snippet button
      await tester.tap(find.text('+ onUpdate(dt)'));
      await tester.pumpAndSettle();

      // 5. Switch to Visual Logic Bridge
      await tester.tap(find.text('Visual Logic Bridge'));
      await tester.pumpAndSettle();

      expect(find.text('Movement Kinematics'), findsOneWidget);
      expect(find.text('Sensory & Audio Reactions'), findsOneWidget);

      // 6. Test "+ New Script" button
      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await tester.pumpAndSettle();

      // Verify dialog appears
      expect(find.text('Create New Dart Script'), findsOneWidget);
      expect(find.text('Create Script'), findsOneWidget);

      // Enter custom script name
      await tester.enterText(find.byType(TextField), 'custom_behavior.dart');
      await tester.pumpAndSettle();

      // Tap Create Script
      await tester.tap(find.text('Create Script'));
      await tester.pumpAndSettle();

      // Verify second tab created
      expect(find.text('custom_behavior.dart'), findsOneWidget);
    });
  });
}

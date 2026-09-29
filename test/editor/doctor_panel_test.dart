import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/panels/doctor_panel.dart';

void main() {
  group('Ember Doctor & Compiler Diagnostics Tests', () {
    testWidgets('EmberDoctorDialog runs comprehensive diagnostics and displays health score', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final project = EmberProject(
        id: 'doctor_test_proj',
        name: 'Doctor Diagnostic Project',
      );
      project.scripts['player.dart'] = 'class Player { void test() {} }';

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => EmberDoctorDialog.show(ctx, project: project),
              child: const Text('Open Doctor'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Open Doctor Dialog
      await tester.tap(find.text('Open Doctor'));
      await tester.pump();
      // Wait for delayed diagnostic scan
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // 1. Verify Dialog Header
      expect(find.text('Ember Doctor & Compiler Diagnostics'), findsOneWidget);
      expect(find.text('System Health, Dependencies & Build Verification'), findsOneWidget);
      expect(find.text('100% System Health'), findsOneWidget);

      // 2. Verify Diagnostic Checks
      expect(find.text('Dart & Flutter SDK Environment'), findsOneWidget);
      expect(find.text('Core Engine Dependencies'), findsOneWidget);
      expect(find.text('GPU & Graphics Hardware Acceleration'), findsOneWidget);
      expect(find.text('Script Compilation & Static Analysis'), findsOneWidget);
      expect(find.text('Multiplatform Build & Export Readiness'), findsOneWidget);

      // 3. Verify Action Buttons
      expect(find.text('Re-run Checks'), findsOneWidget);
      expect(find.text('Export .emberpkg'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // 4. Test Re-run Diagnostics
      await tester.tap(find.text('Re-run Checks'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('100% System Health'), findsOneWidget);

      // 5. Test Export .emberpkg modal trigger
      await tester.tap(find.text('Export .emberpkg'));
      await tester.pumpAndSettle();

      expect(find.text('Exported .emberpkg Bundle'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Close Dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(EmberDoctorDialog), findsNothing);
    });
  });
}

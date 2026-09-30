import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/editor/ember_editor_app.dart';
import 'package:ember_engine/subsystems/two_d/flame_viewport.dart';

/// Regression: opening Ember Quest in the editor froze the app. Parallax
/// layers repeat to fill the visible area, and the editor view was not
/// clipped, so the "visible area" was unbounded and the repeat loop never ended.
void main() {
  testWidgets('create Ember Quest from the hub, edit, and play without freezing', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const EmberEditorApp());
    await tester.pump(const Duration(milliseconds: 100));

    // Ember Quest is the second template card
    final questCard = find.ancestor(of: find.text('Ember Quest'), matching: find.byType(Container)).first;
    expect(questCard, findsOneWidget);
    await tester.tap(find.text('Create Project').at(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('New Ember Project Wizard'), findsOneWidget);
    await tester.tap(find.text('Create & Launch Editor'));
    await tester.pump();

    // Editor frames (the frozen part)
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(FlameViewportWidget), findsOneWidget);
    expect(EmberEngine.instance.activeScene.name, 'Level 1');

    // Play frames
    EmberEngine.instance.play();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    EmberEngine.instance.stop();
    expect(sw.elapsed, lessThan(const Duration(seconds: 30)));
  });
}

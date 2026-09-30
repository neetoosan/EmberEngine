import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/main_player.dart';
import 'package:ember_engine/templates/legends_game.dart';

/// Ember Legends as the exported game runs it: the standalone player app with
/// real key events going through the hardware keyboard binding.
void main() {
  testWidgets('player app: Enter on the title starts a new game, then WASD moves the hero', (tester) async {
    registerAllSubsystems();
    final engine = EmberEngine.instance;
    final project = TemplateCatalog.getByType(ProjectTemplateType.legends).createProject(name: 'Ember Legends');
    await tester.pumpWidget(EmberPlayerApp(project: project));
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.activeScene.name, Legends.title);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(engine.activeScene.name, Legends.village);

    final hero = engine.activeScene.findByName('Hero')!;
    final x0 = Legends.centerOf(hero).x;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    expect(Legends.centerOf(hero).x, greaterThan(x0 + 20));

    engine.stop();
    await tester.pumpWidget(const SizedBox());
  });
}

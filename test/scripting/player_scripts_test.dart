import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/hub/project_package.dart';
import 'package:ember_engine/main_player.dart';
import 'package:ember_engine/scripting/script_library.dart';

/// An exported game: the package round-trips, and the standalone player runs its Ember Scripts.
void main() {
  testWidgets('exported game runs its .ember scripts in the player app', (tester) async {
    registerAllSubsystems();
    EmberScripts.instance.loadAll({}); // nothing left over from the editor
    final project = EmberProject(id: 'g', name: 'Scripted Game', renderPipeline: RenderPipelineMode.twoD, defaultSceneName: 'Main');
    project.scripts['mover.ember'] = 'var speed = 100;\nvoid onUpdate(dt) { self.x += Input.axis("horizontal") * speed * dt; }';
    project.scenes['Main'] = EmberScene(name: 'Main')
      ..addEntity(EmberEntity(name: 'Box')
        ..addComponent(Transform2DComponent(position: Vector2.zero()))
        ..addComponent(ScriptComponent(scriptName: 'mover.ember', vars: {'speed': 300})));

    // What Export writes, read back the way the player reads it
    final exported = ProjectPackageManager.importFromPackageString(ProjectPackageManager.exportToPackageString(project));
    expect(exported.scripts['mover.ember'], project.scripts['mover.ember']);

    await tester.pumpWidget(EmberPlayerApp(project: exported));
    await tester.pump(const Duration(milliseconds: 50));
    final box = EmberEngine.instance.activeScene.findByName('Box')!;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    final x = box.getComponent<Transform2DComponent>()!.position.x;
    expect(x, greaterThan(100), reason: 'moved at the Inspector speed (300 px/s), not 0');
    expect(EmberScripts.instance.problems, isEmpty);

    EmberEngine.instance.stop();
    await tester.pumpWidget(const SizedBox());
  });
}

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/editor/doctor.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/editor/project_session.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/particles/particle_system.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';

EmberEngine get engine => EmberEngine.instance;
String text(String name) => engine.activeScene.findByName(name)!.getComponent<UITextComponent>()!.text;

EmberProject open(ProjectTemplateType type) {
  final project = TemplateCatalog.getByType(type).createProject(name: type.name);
  engine.stop();
  engine.preserveSceneOnModeSwitch = false;
  engine.setMode(project.renderPipeline == RenderPipelineMode.twoD ? EngineMode.twoD : EngineMode.threeD);
  EmberScripts.instance.loadAll(project.scripts);
  engine.loadScene(project.activeScene);
  engine.step();
  return project;
}

void run(double seconds) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    engine.step();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('starter templates test');
  });
  tearDown(() {
    Input.reset();
    engine.stop();
  });

  test('every template passes the Doctor: scripts compile and run, files exist, links work', () async {
    for (final type in ProjectTemplateType.values) {
      final project = TemplateCatalog.getByType(type).createProject(name: type.name);
      EmberScripts.instance.loadAll(project.scripts);
      final items = await ProjectDoctor.run(
        DoctorInput.fromContent(ProjectSession.contentOf(project)),
        checkExports: false,
        assetExists: (path) async => File(path).existsSync(), // art is in the repo's assets folder
      );
      for (final i in items.where((i) => i.status != HealthStatus.info)) {
        expect(i.status, HealthStatus.passed, reason: '${type.name} · ${i.title}: ${i.details}');
      }
      expect(project.scripts.keys.where((f) => f.endsWith('.dart')), isEmpty, reason: '${type.name} ships no dead .dart notes');
    }
  });

  test('2D Platformer: the hero runs right, picks up the first coin, and the HUD counts it', () {
    open(ProjectTemplateType.platformer2d);
    final hero = engine.activeScene.findByName('Hero')!.getComponent<Transform2DComponent>()!;
    final startX = hero.position.x;
    expect(text('HUD'), 'Coins 0 / 12');
    Input.onKeyDown(LogicalKeyboardKey.arrowRight);
    run(1.2);
    Input.onKeyUp(LogicalKeyboardKey.arrowRight);
    expect(hero.position.x, greaterThan(startX + 100), reason: 'runs');
    expect(text('HUD'), 'Coins 1 / 12');
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('2D Platformer: falling into the pit restarts the level', () {
    open(ProjectTemplateType.platformer2d);
    final hero = engine.activeScene.findByName('Hero')!.getComponent<Transform2DComponent>()!;
    hero.position = Vector2(20 * 32 + 16, 200); // above the pit
    run(1.5);
    final again = engine.activeScene.findByName('Hero')!.getComponent<Transform2DComponent>()!;
    expect(again.position.x, lessThan(200), reason: 'back at the start');
  });

  test('3D FPS: shooting the target bot counts a hit (script on the target)', () {
    open(ProjectTemplateType.fps3d);
    expect(text('HitsText'), 'Hits 0');
    Input.onMouseDown(0);
    engine.step();
    Input.onMouseUp(0);
    run(0.1);
    expect(text('HitsText'), 'Hits 1');
    final bot = engine.activeScene.findByName('TargetBot')!.getComponent<Transform3DComponent>()!;
    final x0 = bot.position.x;
    run(1);
    expect((bot.position.x - x0).abs(), greaterThan(1), reason: 'the bot strafes');
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('Particles: Space fires bursts from both emitters', () {
    open(ProjectTemplateType.particles);
    int count(String name) => engine.activeScene.findByName(name)!.getComponent<ParticleEmitter3DComponent>()!.particles.length;
    run(0.5);
    final fire = count('FireEmitter_3D'), sparks = count('SparkEmitter_3D');
    Input.onKeyDown(LogicalKeyboardKey.space);
    engine.step();
    Input.onKeyUp(LogicalKeyboardKey.space);
    expect(count('FireEmitter_3D'), greaterThan(fire + 20));
    expect(count('SparkEmitter_3D'), greaterThan(sparks + 20));
    expect(EmberScripts.instance.problems, isEmpty);
  });
}

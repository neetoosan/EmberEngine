import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/doctor.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/editor/panels/doctor_panel.dart';
import 'package:ember_engine/editor/project_session.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/two_d/door.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';

DiagnosticReportItem item(List<DiagnosticReportItem> items, String title) => items.firstWhere((i) => i.title == title);

Future<List<DiagnosticReportItem>> check(EmberProject p, {bool unsaved = false, Set<String> presentAssets = const {}}) =>
    ProjectDoctor.run(
      DoctorInput.fromContent(ProjectSession.contentOf(p), hasUnsavedChanges: unsaved),
      checkExports: false,
      assetExists: (path) async => presentAssets.contains(path) || path.startsWith('assets/templates/'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    registerAllSubsystems();
    EmberScripts.instance.loadAll(const {});
  });

  test('a fresh template project passes every check', () async {
    final project = TemplateCatalog.getByType(ProjectTemplateType.siege).createProject(name: 'Doctor Siege');
    final items = await check(project);
    for (final i in items.where((i) => i.status != HealthStatus.info)) {
      expect(i.status, HealthStatus.passed, reason: '${i.title}: ${i.details}');
    }
    expect(ProjectDoctor.score(items), 1.0);
  });

  test('finds real problems: script errors, missing scripts, broken scene links, missing files, unsaved work', () async {
    final scene = EmberScene(name: 'Main')
      ..addEntity(EmberEntity(name: 'Hero')
        ..addComponent(Transform2DComponent(position: Vector2.zero()))
        ..addComponent(FlameSpriteComponent(assetPath: 'assets/sprites/hero.png'))
        ..addComponent(ScriptComponent(scriptName: 'ghost.ember')))
      ..addEntity(EmberEntity(name: 'Exit')
        ..addComponent(Transform2DComponent(position: Vector2.zero()))
        ..addComponent(DoorComponent(targetLevel: 'Level 9')))
      ..addEntity(EmberEntity(name: 'Play')..addComponent(UIButtonComponent(action: 'level:Bonus')));
    final project = EmberProject(id: 'p', name: 'Broken', defaultSceneName: 'Main')
      ..scenes['Main'] = scene
      ..scripts['hero.ember'] = 'void onUpdate(dt) {\n  self.x += \n}'
      ..scripts['old.dart'] = 'class Old {}'
      ..scripts['menu.ember'] = 'void onStart() { loadLevel("Credits"); }';

    final items = await check(project, unsaved: true);
    final compile = item(items, 'Scripts compile');
    expect(compile.status, HealthStatus.failed);
    expect(compile.details, contains('hero.ember:'), reason: 'names the file and line');
    expect(item(items, 'Dart note files').status, HealthStatus.warning);
    expect(item(items, 'Script Components').details, contains('ghost.ember'));
    final links = item(items, 'Scene links');
    expect(links.status, HealthStatus.failed);
    expect(links.details, allOf(contains('Level 9'), contains('Bonus'), contains('Credits')));
    final assets = item(items, 'Images and sounds');
    expect(assets.status, HealthStatus.failed);
    expect(assets.details, contains('assets/sprites/hero.png'));
    expect(item(items, 'Saved').status, HealthStatus.warning);
    expect(ProjectDoctor.score(items), lessThan(0.5));

    // Once fixed, the same checks pass
    project.scripts['hero.ember'] = 'void onUpdate(dt) { self.x += 1; }';
    project.scripts.remove('old.dart');
    project.scripts['ghost.ember'] = 'var x = 1;';
    project.scripts['menu.ember'] = 'void onStart() { loadLevel("Main"); }';
    scene.findByName('Exit')!.getComponent<DoorComponent>()!.targetLevel = 'Main';
    scene.findByName('Play')!.getComponent<UIButtonComponent>()!.action = 'level:Main';
    final fixed = await check(project, presentAssets: {'assets/sprites/hero.png'});
    for (final i in fixed.where((i) => i.status != HealthStatus.info)) {
      expect(i.status, HealthStatus.passed, reason: '${i.title}: ${i.details}');
    }
  });

  test('the placeholder sprite of a new entity is not reported as a missing file', () async {
    final project = EmberProject(id: 'p', name: 'Blank', defaultSceneName: 'Main')
      ..scenes['Main'] = (EmberScene(name: 'Main')..addEntity(EmberEntity(name: 'Box')..addComponent(FlameSpriteComponent())));
    expect(item(await check(project), 'Images and sounds').status, HealthStatus.passed);
  });

  testWidgets('the dialog shows the checks, a fix button, and re-checks after saving', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final project = TemplateCatalog.getByType(ProjectTemplateType.flappy).createProject(name: 'Doctor Dialog');
    var unsaved = true;
    var saves = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => EmberDoctorDialog.show(ctx,
                project: project,
                hasUnsavedChanges: () => unsaved,
                onSave: () async {
                  saves++;
                  unsaved = false;
                },
                checkExports: false),
            child: const Text('Open Doctor'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open Doctor'));
    await tester.pumpAndSettle();

    expect(find.text('Ember Doctor'), findsOneWidget);
    expect(find.text('Scripts compile'), findsOneWidget);
    expect(find.text('Images and sounds'), findsOneWidget);
    expect(find.textContaining('checks passed'), findsOneWidget);
    expect(find.text('Save now'), findsOneWidget);

    await tester.tap(find.text('Save now'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('Save now'), findsNothing, reason: 'checked again after saving');
    expect(find.textContaining('All changes saved'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(EmberDoctorDialog), findsNothing);
  });
}

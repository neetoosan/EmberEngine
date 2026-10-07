import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/ember_editor_app.dart';
import 'package:ember_engine/editor/hub/project_launcher.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/hub/project_storage.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/editor/project_session.dart';

EmberEngine get engine => EmberEngine.instance;
ProjectSession get session => ProjectSession.instance;

EmberEntity box(String name) => EmberEntity(name: name)..addComponent(Transform2DComponent(position: Vector2(10, 20)));

EmberProject newProject(String name) => TemplateCatalog.getByType(ProjectTemplateType.flappy).createProject(name: name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    registerAllSubsystems();
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    tmp = await Directory.systemTemp.createTemp('ember_session_test');
  });

  tearDown(() async {
    session.end();
    await tmp.delete(recursive: true);
  });

  group('unsaved changes and recovery copies', () {
    late EmberProject project;
    late Map<String, dynamic> editing; // stands in for the scene open in the editor

    setUp(() async {
      project = newProject('Session Test')..path = '${tmp.path}${Platform.pathSeparator}Session Test';
      await ProjectStorage.save(project);
      editing = project.activeScene.toJson();
      session.begin(project,
          content: () => ProjectSession.contentOf(project, editingScene: project.defaultSceneName, editingJson: editing));
    });

    test('a fresh project is clean; editing the scene or a script makes it dirty; undoing makes it clean', () {
      expect(session.isDirty, isFalse);
      final original = editing;
      editing = (EmberScene.fromJson(original)..addEntity(box('New Crate'))).toJson();
      session.refresh();
      expect(session.isDirty, isTrue);
      editing = original;
      session.refresh();
      expect(session.isDirty, isFalse, reason: 'back to what is on disk');

      project.scripts['flappy_bird.ember'] = '${project.scripts['flappy_bird.ember']}\n// tweak';
      session.refresh();
      expect(session.isDirty, isTrue);
    });

    test('recovery copies are written only with unsaved changes, found again, and removed on save', () async {
      expect(await session.writeRecovery(), isNull, reason: 'nothing to recover');
      editing = (EmberScene.fromJson(editing)..addEntity(box('Unsaved Crate'))).toJson();
      final file = await session.writeRecovery();
      expect(file, isNotNull);
      expect(file!.path, contains(ProjectSession.recoveryDirName));

      final copy = await ProjectSession.findRecovery(project);
      expect(copy, isNotNull);
      final reopened = await ProjectStorage.load(project.path);
      ProjectSession.applyContent(reopened, copy!.content);
      expect(reopened.activeScene.findByName('Unsaved Crate'), isNotNull, reason: 'the recovered scene has the unsaved edit');

      await session.markSaved();
      expect(session.isDirty, isFalse);
      expect(await ProjectSession.findRecovery(project), isNull, reason: 'saving removes the recovery copy');
    });

    test('a half-written (corrupt) recovery file is ignored', () async {
      final file = ProjectSession.recoveryFile(project);
      await file.parent.create(recursive: true);
      await file.writeAsString('{"savedAt": "2026-10-06T10:00:00", "content": {"sce');
      expect(await ProjectSession.findRecovery(project), isNull);
    });
  });

  testWidgets('leaving a project with unsaved changes asks first: Cancel stays, Don\'t Save leaves', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final project = newProject('Prompt Test');
    await tester.pumpWidget(EmberEditorApp(initialProject: project, startInLauncher: false));
    await tester.pump(const Duration(milliseconds: 100));

    engine.activeScene.addEntity(box('Unsaved Crate'));
    session.refresh();
    await tester.pump();
    expect(session.isDirty, isTrue);
    final badge = tester.widget<Badge>(find.descendant(of: find.byKey(const ValueKey('save-button')), matching: find.byType(Badge)));
    expect(badge.isLabelVisible, isTrue, reason: 'the save button shows the unsaved dot');

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('unsaved-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unsaved-cancel')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(ProjectLauncherScreen), findsNothing, reason: 'Cancel keeps the project open');
    expect(engine.activeScene.findByName('Unsaved Crate'), isNotNull);

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('unsaved-discard')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(ProjectLauncherScreen), findsOneWidget, reason: "Don't Save goes to the Project Hub");

    await tester.pumpWidget(const SizedBox());
    session.end();
  });

  testWidgets('after a crash, opening the project offers the recovery copy; Restore brings the work back', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final project = newProject('Crash Test')..path = '${tmp.path}${Platform.pathSeparator}Crash Test';
    // What the crashed session left behind: the saved project plus a recovery copy with one more crate
    await tester.runAsync(() async {
      await ProjectStorage.save(project);
      final edited = (EmberScene.fromJson(project.activeScene.toJson())..addEntity(box('Recovered Crate'))).toJson();
      final content = ProjectSession.contentOf(project, editingScene: project.defaultSceneName, editingJson: edited);
      final file = ProjectSession.recoveryFile(project);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'savedAt': DateTime(2026, 10, 6, 19, 42).toIso8601String(), 'content': content}));
    });
    final reopened = (await tester.runAsync(() => ProjectStorage.load(project.path)))!;

    await tester.pumpWidget(EmberEditorApp(initialProject: reopened, startInLauncher: false));
    for (var i = 0; i < 5 && find.byKey(const ValueKey('recovery-dialog')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('recovery-dialog')), findsOneWidget);
    expect(find.textContaining('2026-10-06 19:42'), findsOneWidget, reason: 'says when the copy was made');
    expect(engine.activeScene.findByName('Recovered Crate'), isNull, reason: 'the saved version is open until you choose');

    await tester.tap(find.byKey(const ValueKey('recovery-restore')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.activeScene.findByName('Recovered Crate'), isNotNull);
    expect(session.isDirty, isTrue, reason: 'restored work still needs saving');

    await tester.pumpWidget(const SizedBox());
    session.end();
  });
}

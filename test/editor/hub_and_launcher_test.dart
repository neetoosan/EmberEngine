import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/editor/ember_editor_app.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/hub/project_package.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/editor/panels/top_bar.dart';
import 'package:ember_engine/editor/panels/hierarchy_panel.dart';

void main() {
  group('Ember Startup Hub & Template System Tests', () {
    test('TemplateCatalog has all 4 official starter templates', () {
      final templates = TemplateCatalog.templates;
      expect(templates.length, 7);

      final types = templates.map((t) => t.type).toSet();
      expect(types, contains(ProjectTemplateType.platformer2d));
      expect(types, contains(ProjectTemplateType.fps3d));
      expect(types, contains(ProjectTemplateType.particles));
      expect(types, contains(ProjectTemplateType.blank));
    });

    test('TemplateCatalog generates complete 2D Platformer Project', () {
      final template = TemplateCatalog.getTemplate(ProjectTemplateType.platformer2d);
      final project = template.createProject(name: 'Super Knight 2D', author: 'TestDev');

      expect(project.name, 'Super Knight 2D');
      expect(project.author, 'TestDev');
      expect(project.renderPipeline, RenderPipelineMode.twoD);
      expect(project.scenes.containsKey('MainScene'), isTrue);

      final scene = project.activeScene;
      expect(scene.getEntityByName('World2D'), isNotNull);
      expect(scene.getEntityByName('HeroPlayer'), isNotNull);
      expect(scene.getEntityByName('Coin_1'), isNotNull);

      expect(project.scripts.containsKey('player_controller_2d.dart'), isTrue);
      expect(project.scripts['player_controller_2d.dart'], contains('class PlayerController2D'));
    });

    test('TemplateCatalog generates complete 3D FPS Arena Project', () {
      final template = TemplateCatalog.getTemplate(ProjectTemplateType.fps3d);
      final project = template.createProject(name: 'Arena Strike 3D');

      expect(project.name, 'Arena Strike 3D');
      expect(project.renderPipeline, RenderPipelineMode.threeD);

      final scene = project.activeScene;
      expect(scene.getEntityByName('SunLight'), isNotNull);
      expect(scene.getEntityByName('ArenaFloor'), isNotNull);
      expect(scene.getEntityByName('TargetBot'), isNotNull);
      expect(scene.getEntityByName('Player (FPS)'), isNotNull);

      expect(project.scripts.containsKey('fps_controller.dart'), isTrue);
    });

    test('TemplateCatalog generates Particle Playground and Blank projects', () {
      final pTemplate = TemplateCatalog.getTemplate(ProjectTemplateType.particles);
      final pProject = pTemplate.createProject(name: 'VFX Lab');
      expect(pProject.activeScene.getEntityByName('FireEmitter_3D'), isNotNull);
      expect(pProject.activeScene.getEntityByName('SparkEmitter_3D'), isNotNull);

      final bTemplate = TemplateCatalog.getTemplate(ProjectTemplateType.blank);
      final bProject = bTemplate.createProject(name: 'Empty Slate');
      expect(bProject.activeScene.rootEntities.length, greaterThanOrEqualTo(1));
    });

    test('ProjectPackageManager exports and imports .emberpkg bundles losslessly', () {
      final template = TemplateCatalog.getTemplate(ProjectTemplateType.fps3d);
      final originalProject = template.createProject(name: 'ExportTestGame', author: 'Alice');
      originalProject.scripts['custom_behavior.dart'] = 'class CustomBehavior {}';

      // Export to package string
      final pkgString = ProjectPackageManager.exportProjectToPackage(originalProject);
      expect(pkgString, contains('EMBER_ENGINE_PROJECT_PACKAGE'));
      expect(pkgString, contains('"checksum"'));

      // Import from package string
      final importedProject = ProjectPackageManager.importProjectFromPackage(pkgString);
      expect(importedProject.name, originalProject.name);
      expect(importedProject.author, originalProject.author);
      expect(importedProject.renderPipeline, originalProject.renderPipeline);
      expect(importedProject.scenes.length, originalProject.scenes.length);
      expect(importedProject.scripts.containsKey('custom_behavior.dart'), isTrue);
      expect(importedProject.scripts['custom_behavior.dart'], 'class CustomBehavior {}');
    });

    test('RecentProjectsManager records and manages recent project entries', () {
      final manager = RecentProjectsManager.instance;
      final info = RecentProjectInfo(
        id: 'test_rec_1',
        name: 'Recent Alpha',
        path: 'projects/recent_alpha',
        templateName: '2D Platformer',
        renderPipeline: RenderPipelineMode.twoD,
        lastOpened: DateTime.now(),
      );

      manager.addOrUpdateRecent(info);
      expect(manager.recentProjects.any((p) => p.id == 'test_rec_1'), isTrue);

      manager.togglePin('test_rec_1');
      final updated = manager.recentProjects.firstWhere((p) => p.id == 'test_rec_1');
      expect(updated.isPinned, isTrue);

      manager.removeRecent('test_rec_1');
      expect(manager.recentProjects.any((p) => p.id == 'test_rec_1'), isFalse);
    });
  });

  testWidgets('EmberEditorApp Project Launcher flow and workspace transition', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // 1. Pump with startInLauncher: true (default)
    await tester.pumpWidget(const EmberEditorApp(startInLauncher: true));
    await tester.pumpAndSettle();

    // Verify Launcher UI elements
    expect(find.text('EMBER'), findsWidgets);
    expect(find.text('Starter Templates'), findsOneWidget);
    expect(find.text('Project Templates'), findsOneWidget);
    expect(find.text('Recent Projects'), findsWidgets);
    expect(find.text('Open & Import'), findsOneWidget);

    // Verify the 5 template cards are displayed
    expect(find.text('2D Platformer Adventure'), findsOneWidget);
    expect(find.text('Ember Legends'), findsOneWidget);
    // Later cards are further down the scrolling template grid
    final gridElement = find.ancestor(of: find.text('2D Platformer Adventure'), matching: find.byType(Scrollable)).evaluate().first;
    final grid = find.byElementPredicate((e) => e == gridElement);
    await tester.scrollUntilVisible(find.text('Flappy Arcade'), 300, scrollable: grid);
    expect(find.text('Flappy Arcade'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('3D FPS Arena'), 300, scrollable: grid);
    expect(find.text('3D FPS Arena'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Procedural Particle Playground'), 300, scrollable: grid);
    expect(find.text('Procedural Particle Playground'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Blank Canvas Project'), 300, scrollable: grid);
    expect(find.text('Blank Canvas Project'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('2D Platformer Adventure'), -300, scrollable: grid);

    // 2. Click "Create Project" on the 2D Platformer Adventure card
    final createButtons = find.text('Create Project');
    expect(createButtons, findsWidgets);
    await tester.tap(createButtons.first);
    await tester.pumpAndSettle();

    // Verify Wizard Dialog appears
    expect(find.text('New Ember Project Wizard'), findsOneWidget);
    expect(find.text('Create & Launch Editor'), findsOneWidget);

    // Click "Create & Launch Editor"
    await tester.tap(find.text('Create & Launch Editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 3. Verify transition to Workstation Editor
    expect(find.byType(EditorTopBar), findsOneWidget);
    expect(find.byType(HierarchyPanel), findsOneWidget);
    expect(find.text('World2D'), findsOneWidget);
    expect(find.text('HeroPlayer'), findsOneWidget);

    // 4. Return to Project Hub via TopBar logo click
    await tester.tap(find.text('EMBER'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify back in Project Hub
    expect(find.text('Starter Templates'), findsOneWidget);
  });
}

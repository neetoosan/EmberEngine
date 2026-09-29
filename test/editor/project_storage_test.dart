import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/editor/hub/game_exporter.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/hub/project_package.dart';
import 'package:ember_engine/editor/hub/project_storage.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';

void main() {
  late Directory tmp;

  setUpAll(registerAllSubsystems);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ember_storage_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  EmberProject newPlatformer(String name) =>
      TemplateCatalog.templates.firstWhere((t) => t.type == ProjectTemplateType.platformer2d).createProject(name: name);

  test('save then load restores scenes, scripts and metadata', () async {
    final project = newPlatformer('My Platformer');
    project.path = await ProjectStorage.allocateProjectPath(project.name, root: tmp);
    await ProjectStorage.save(project);

    expect(File('${project.path}/${ProjectStorage.manifestFileName}').existsSync(), isTrue);
    expect(File('${project.path}/scenes/MainScene.scene').existsSync(), isTrue);

    final loaded = await ProjectStorage.load(project.path);
    expect(loaded.id, project.id);
    expect(loaded.name, 'My Platformer');
    expect(loaded.renderPipeline, RenderPipelineMode.twoD);
    expect(loaded.path, project.path);
    expect(loaded.scripts.keys, contains('player_controller_2d.dart'));

    final scene = loaded.activeScene;
    expect(scene.findByName('HeroPlayer'), isNotNull);
    expect(scene.findByName('World2D'), isNotNull);
    final script = scene.findByName('HeroPlayer')!.getComponent<ScriptComponent>();
    expect(script?.scriptName, 'Platformer 2D Controller');
  });

  test('saving twice overwrites files in place', () async {
    final project = newPlatformer('Resave');
    project.path = await ProjectStorage.allocateProjectPath(project.name, root: tmp);
    await ProjectStorage.save(project);

    project.activeScene.findByName('HeroPlayer')!.name = 'Renamed Hero';
    await ProjectStorage.save(project);

    final loaded = await ProjectStorage.load(project.path);
    expect(loaded.activeScene.findByName('Renamed Hero'), isNotNull);
    expect(tmp.listSync(recursive: true).where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  test('allocateProjectPath never reuses an existing folder', () async {
    final first = await ProjectStorage.allocateProjectPath('Game', root: tmp);
    await Directory(first).create();
    final second = await ProjectStorage.allocateProjectPath('Game', root: tmp);
    expect(second, isNot(first));
    expect(second.endsWith('Game_2'), isTrue);
  });

  test('loading a folder without a manifest fails clearly', () async {
    expect(() => ProjectStorage.load(tmp.path), throwsA(isA<FileSystemException>()));
  });

  test('export copies the runtime, renames the exe and writes the game file', () async {
    final runtime = await Directory('${tmp.path}/runtime/data').create(recursive: true);
    final exeName = Platform.isWindows ? 'ember_engine.exe' : 'ember_engine';
    await File('${runtime.parent.path}/$exeName').writeAsString('fake exe');
    await File('${runtime.path}/app.so').writeAsString('fake engine data');

    final project = newPlatformer('Coin Quest');
    final exe = await GameExporter.export(
      project: project,
      runtime: runtime.parent,
      outputParent: '${tmp.path}/out',
    );

    final gameDir = Directory('${tmp.path}/out/Coin Quest');
    expect(File(exe).existsSync(), isTrue);
    expect(exe.contains('Coin Quest'), isTrue);
    expect(File('${gameDir.path}/data/app.so').existsSync(), isTrue);

    final pkg = File('${gameDir.path}/${GameExporter.gameFileName}').readAsStringSync();
    final reloaded = ProjectPackageManager.importFromPackageString(pkg);
    expect(reloaded.name, 'Coin Quest');
    expect(reloaded.activeScene.findByName('HeroPlayer'), isNotNull);
  });

  test('recent projects persist to disk once storage is attached', () async {
    final file = File('${tmp.path}/recent.json');
    final manager = RecentProjectsManager.instance;
    await manager.attachStorage(file);
    manager.addOrUpdateRecent(RecentProjectInfo(
      id: 'persist_1',
      name: 'Persisted',
      path: tmp.path,
      templateName: 'MainScene',
      renderPipeline: RenderPipelineMode.threeD,
      lastOpened: DateTime.now(),
    ));
    await manager.flush();
    expect(file.readAsStringSync(), contains('Persisted'));

    manager.removeRecent('persist_1');
    await manager.flush();
    expect(file.readAsStringSync(), isNot(contains('Persisted')));
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/assets.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/editor/hub/game_exporter.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/hub/project_package.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/main_player.dart' show bundledGameKey, loadBundledGame;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late EmberProject project;

  setUp(() async {
    registerAllSubsystems();
    tmp = await Directory.systemTemp.createTemp('ember_export_test');
    project = TemplateCatalog.getByType(ProjectTemplateType.legends).createProject(name: 'Ember Legends');
    project.path = '${tmp.path}${Platform.pathSeparator}project';
    (await File('${project.path}/assets/sprites/hero.png').create(recursive: true)).writeAsBytesSync([1, 2, 3, 4]);
    (await File('${project.path}/assets/audio/boss.wav').create(recursive: true)).writeAsBytesSync([9, 8, 7]);
  });

  tearDown(() async {
    EmberAssets.instance.embedded.clear();
    await tmp.delete(recursive: true);
  });

  test('project files are collected by project-relative path', () async {
    final files = await GameExporter.collectProjectFiles(project);
    expect(files.keys, containsAll(['assets/sprites/hero.png', 'assets/audio/boss.wav']));
    expect(files['assets/sprites/hero.png'], [1, 2, 3, 4]);
  });

  test('a package can carry its files; importing gives both back', () async {
    final text = ProjectPackageManager.exportToPackageString(project, files: await GameExporter.collectProjectFiles(project));
    final (back, files) = ProjectPackageManager.importWithFiles(text);
    expect(back.name, 'Ember Legends');
    expect(back.scripts.keys, project.scripts.keys);
    expect(files['assets/audio/boss.wav'], [9, 8, 7]);
    // Packages without files still import (older exports)
    final (_, none) = ProjectPackageManager.importWithFiles(ProjectPackageManager.exportToPackageString(project));
    expect(none, isEmpty);
  });

  test('embedded files are read before disk and the engine bundle', () async {
    EmberAssets.instance.embedded['assets/templates/legends/hero.png'] = Uint8List.fromList([42]);
    expect(await EmberAssets.instance.readBytes('assets/templates/legends/hero.png'), [42]);
  });

  test('web export: player + self-contained game, relative base, title, helper files', () async {
    final runtime = await Directory('${tmp.path}/web_runtime').create();
    await File('${runtime.path}/index.html')
        .writeAsString('<html><head><base href="/"><title>ember_engine</title></head><body></body></html>');
    await File('${runtime.path}/main.dart.js').writeAsString('// player');
    await File('${runtime.path}/manifest.json').writeAsString('{"name": "Ember Engine", "short_name": "Ember", "display": "standalone"}');

    final folder = await GameExporter.exportWeb(project: project, runtime: runtime, outputParent: '${tmp.path}/out');
    expect(folder, endsWith('Ember Legends-web'));
    final index = await File('$folder/index.html').readAsString();
    expect(index, contains('<base href="./">'));
    expect(index, contains('<title>Ember Legends</title>'));
    final manifest = jsonDecode(await File('$folder/manifest.json').readAsString()) as Map;
    expect(manifest['name'], 'Ember Legends', reason: 'installs under the game name');
    expect(manifest['display'], 'standalone', reason: 'other settings kept');
    expect(File('$folder/main.dart.js').existsSync(), isTrue);
    expect(File('$folder/README.txt').existsSync(), isTrue);
    expect(File('$folder/play-locally.ps1').existsSync(), isTrue);

    final game = File('$folder/${GameExporter.webGamePath}');
    final (exported, files) = ProjectPackageManager.importWithFiles(await game.readAsString());
    expect(exported.scenes.keys, project.scenes.keys);
    expect(files['assets/sprites/hero.png'], [1, 2, 3, 4]);
  });

  test('after an Android export no copy of the game is left in the engine build folders', () async {
    final repo = await Directory('${tmp.path}/repo').create();
    final leftovers = [
      'build/app/intermediates/flutter/release/flutter_assets/assets/game/game.emberpkg.json',
      'build/unit_test_assets/assets/game/game.emberpkg.json',
    ];
    final keep = File('${repo.path}/build/player_runtime_web/assets/assets/game/game.emberpkg.json');
    for (final rel in leftovers) {
      await File('${repo.path}/$rel').create(recursive: true);
    }
    await keep.create(recursive: true);
    await GameExporter.removeStagedGameCopies(repo);
    for (final rel in leftovers) {
      expect(File('${repo.path}/$rel').existsSync(), isFalse, reason: rel);
    }
    expect(keep.existsSync(), isTrue, reason: 'exported web players are not touched');
  });

  test('Android app ids are valid and stable', () {
    expect(GameExporter.androidAppId('Ember Legends'), 'com.embergames.ember_legends');
    expect(GameExporter.androidAppId('3D Arena!!'), 'com.embergames.g_3d_arena');
    expect(GameExporter.androidAppId('???'), 'com.embergames.game');
    expect(GameExporter.androidAppId('Ember Legends'), GameExporter.androidAppId('Ember Legends'));
  });

  testWidgets('the player loads a game packed into its bundle, with embedded files', (tester) async {
    // Real file reads must run outside the widget test's fake clock
    final files = (await tester.runAsync(() => GameExporter.collectProjectFiles(project)))!;
    final text = ProjectPackageManager.exportToPackageString(project, files: files);
    tester.binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes));
      if (key != bundledGameKey) return null;
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null));

    final loaded = await loadBundledGame();
    expect(loaded?.name, 'Ember Legends');
    expect(EmberAssets.instance.embedded['assets/sprites/hero.png'], [1, 2, 3, 4]);
    expect(EmberAssets.instance.root, isNull);
  });

  test('without a bundled game the player falls back to its demo', () async {
    expect(await loadBundledGame(), isNull);
  });
}

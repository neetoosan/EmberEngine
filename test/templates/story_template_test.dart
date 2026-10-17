import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/story/story_player.dart';
import 'package:ember_engine/subsystems/story/story_script.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/templates/story_game.dart';
import 'package:ember_engine/templates/story_scripts.dart';

EmberEngine get engine => EmberEngine.instance;
StoryPlayerComponent get player => engine.activeScene.componentsOf<StoryPlayerComponent>().single;

void startProject() {
  engine.stop();
  final project = TemplateCatalog.getByType(ProjectTemplateType.story).createProject(name: 'Ember Tale');
  EmberScripts.instance.loadAll(project.scripts);
  final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
  engine.sceneLibrary = () => levels;
  engine.loadScene(project.scenes[StoryTemplate.story]!);
  engine.step();
}

/// Reads on, picking the options in [picks] (by their text) at each choice. Returns the ending.
String playThrough(List<String> picks) {
  final queue = [...picks];
  for (var guard = 0; guard < 400 && !player.ended; guard++) {
    if (player.choices.isNotEmpty) {
      final pick = queue.removeAt(0);
      final i = player.choices.indexWhere((c) => c.contains(pick));
      expect(i, greaterThanOrEqualTo(0), reason: '"$pick" in ${player.choices}');
      player.choose(i);
    } else if (player.text.isEmpty) {
      engine.step(); // a wait
    } else {
      if (!player.lineComplete) player.advance();
      player.advance();
    }
  }
  expect(player.ended, isTrue);
  expect(queue, isEmpty, reason: 'every pick was used');
  return player.ending ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('story template test');
    for (final k in ['lastember_auto', 'lastember_1', 'lastember_2', 'lastember_3', 'lastember_endings']) {
      SaveData.instance.remove(k);
    }
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() {
    Input.reset();
    engine.stop();
  });

  test('the template: a title and the story scene, a story without mistakes, scripts that compile, art on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.story).createProject(name: 'Ember Tale');
    expect(project.scenes.keys, containsAll([StoryTemplate.title, StoryTemplate.story]));
    expect(project.defaultSceneName, StoryTemplate.title);
    final story = StoryScript.parse(project.scripts[StoryTemplate.storyFile]!);
    expect(story.errors, isEmpty);
    expect(story.characters.keys, ['mira', 'kai']);
    for (final path in [...story.backgrounds.values, for (final c in story.characters.values) c.image]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in storyScripts.keys.where(EmberScripts.isScriptFile)) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in StoryTemplate.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('it opens on the dying forge with narration, then Mira speaks', () {
    startProject();
    expect(player.background, 'forge');
    expect(player.speaker, '');
    expect(player.text, startsWith('The great forge of Emberfall'));
    player.advance();
    player.advance();
    player.advance();
    player.advance();
    expect(player.speaker, 'Mira');
    expect(player.expressionOf('mira'), 'sad');
  });

  test('all four endings can be reached', () {
    startProject();
    expect(playThrough(['Open the door', "Show him the forge's heart", 'look at the stars']), 'The Northern Star (secret ending)');
    expect(player.vars['trust'], 4);

    startProject();
    expect(playThrough(['Ask who it is', "Show him the forge's heart", 'look at the stars']), 'Two Flames, One Fire');

    startProject();
    expect(playThrough(['Ask who it is', 'about the north', 'Hurry back']), "The Wanderer's Road");

    startProject();
    expect(playThrough(['Tell them to go away', "I don't need your help", 'Hurry back']), 'Cold Iron');
    expect(SaveData.instance.getMap('lastember_endings')?['names'], hasLength(4));
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('the title offers Continue once there is a save, and counts the endings found', () {
    startProject();
    player.advance(); // reading creates the autosave
    engine.loadLevel(StoryTemplate.title);
    engine.step();
    expect(engine.activeScene.findByName('ContinueButton')!.enabled, isTrue);
    expect(engine.activeScene.findByName('EndingsText')!.getComponent<UITextComponent>()!.text, 'Endings found: 0 / 4');
  });
}

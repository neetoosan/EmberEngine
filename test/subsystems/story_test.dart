import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/story/story_player.dart';
import 'package:ember_engine/subsystems/story/story_script.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';

EmberEngine get engine => EmberEngine.instance;

const _story = '''
# A small test story
@title Test
@background room assets/templates/story/forge.png
@character ann "Ann" #F59E0B assets/x.png neutral happy sad
@var trust = 0
@var name = "Kit"

label start:
scene room cut
show ann happy left
ann: Hello, {name}! Trust is {trust}.
ann sad: This is *important*.
The wind blows.
"Stranger": Who goes there?
choice:
  * Be kind {trust += 2} -> kind
  * Be rude -> rude
  * Secret [if trust > 5] -> secret

label kind:
set trust = trust + 1
if trust >= 3 jump good
ann: Not quite.
end Middle ending

label good:
event cheer
wait 0.5
ann happy: Friends!
end Good ending

label rude:
hide ann
end Bad ending

label secret:
end Secret ending
''';

StoryPlayerComponent? player;

void play(String story, {Map<String, String> extra = const {}}) {
  engine.stop();
  EmberScripts.instance.loadAll({'test.story': story, ...extra});
  player = StoryPlayerComponent(storyFile: 'test.story', saveKey: 'storytest');
  final scene = EmberScene(name: 'Story')..addEntity(EmberEntity(name: 'Story')..addComponent(player!));
  engine.loadScene(scene);
  engine.step();
}

void frames(int n) {
  for (var i = 0; i < n; i++) {
    engine.step();
  }
}

/// Click / Enter: finishes the typewriter, then the next press moves on.
void next() {
  if (!player!.lineComplete) player!.advance();
  player!.advance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('story test');
    for (final k in ['storytest_auto', 'storytest_1', 'storytest_2', 'storytest_3', 'storytest_endings']) {
      SaveData.instance.remove(k);
    }
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() {
    Input.reset();
    engine.stop();
  });

  test('the story language: directives, labels, every command and its arguments', () {
    final p = StoryScript.parse(_story);
    expect(p.errors, isEmpty);
    expect(p.title, 'Test');
    expect(p.backgrounds['room'], 'assets/templates/story/forge.png');
    final ann = p.characters['ann']!;
    expect((ann.name, ann.color), ('Ann', 0xFFF59E0B));
    expect(ann.expressions, ['neutral', 'happy', 'sad']);
    expect(ann.frameOf('sad'), 2);
    expect(p.initialVars, {'trust': 0, 'name': 'Kit'});
    expect(p.labels.keys, containsAll(['start', 'kind', 'good', 'rude', 'secret']));
    final kinds = [for (final c in p.commands) c.kind];
    expect(kinds, containsAllInOrder(['scene', 'show', 'say', 'say', 'say', 'say', 'choice', 'set', 'if', 'say', 'end', 'event', 'wait', 'say', 'end', 'hide', 'end']));
    final choice = p.commands.firstWhere((c) => c.kind == 'choice');
    expect(choice.choices.map((c) => c.text), ['Be kind', 'Be rude', 'Secret']);
    expect(choice.choices[0].effect, 'trust += 2');
    expect(choice.choices[2].condition, 'trust > 5');
    final says = p.commands.where((c) => c.kind == 'say').toList();
    expect(says[1].args['expression'], 'sad');
    expect(says[2].args.containsKey('id'), isFalse, reason: 'narration');
    expect(says[3].args['name'], 'Stranger');
  });

  test('mistakes are reported with their line', () {
    final p = StoryScript.parse('''
@character ann "Ann" #F59E0B a.png neutral
label start:
scene nowhere
show bob
ann grumpy: hi
jump missing
choice:
set = 3
wait soon
if trust >> 2 jump start
''');
    final messages = {for (final e in p.errors) e.line: e.message};
    expect(messages[3], contains('no background "nowhere"'));
    expect(messages[4], contains('no character "bob"'));
    expect(messages[5], contains('"grumpy" is not an expression'));
    expect(messages[6], contains('no label "missing"'));
    expect(messages[7], contains('no options'));
    expect(messages[8], contains('set needs'));
    expect(messages[9], contains('wait needs seconds'));
    expect(messages[10], isNotNull);
  });

  test('story expressions: maths, comparisons, logic, strings and assignments', () {
    final vars = <String, Object?>{'a': 2, 'b': 5, 'name': 'Kit', 'met': true};
    expect(StoryExpr.eval('a + b * 2', vars), 12);
    expect(StoryExpr.eval('(a + b) * 2', vars), 14);
    expect(StoryExpr.eval('b - a >= 3 and met', vars), isTrue);
    expect(StoryExpr.eval('not met or a == 3', vars), isFalse);
    expect(StoryExpr.eval('name == "Kit"', vars), isTrue);
    expect(StoryExpr.eval('"Hi " + name', vars), 'Hi Kit');
    expect(StoryExpr.eval('unknown', vars), 0, reason: 'unknown variables are 0');
    StoryExpr.assign('a += 3', vars);
    StoryExpr.assign('flag = a > 4', vars);
    expect((vars['a'], vars['flag']), (5, true));
    expect(StoryExpr.check('a +'), isNotNull);
    expect(StoryExpr.check('a + (b'), contains(')'));
  });

  test('playing: lines with names and expressions, narration, choices, effects, jumps and the ending', () {
    play(_story);
    final p = player!;
    expect(p.background, 'room');
    expect(p.onStage, ['ann']);
    expect(p.expressionOf('ann'), 'happy');
    expect((p.speaker, p.text), ('Ann', 'Hello, Kit! Trust is 0.'));
    expect(p.lineComplete, isFalse, reason: 'the typewriter is running');
    frames(90);
    expect(p.lineComplete, isTrue);
    next();
    expect(p.text, 'This is important.');
    expect(p.expressionOf('ann'), 'sad', reason: 'speaking with an expression changes it');
    next();
    expect((p.speaker, p.text), ('', 'The wind blows.'));
    next();
    expect(p.speaker, 'Stranger');
    next();
    expect(p.choices, ['Be kind', 'Be rude'], reason: 'the secret option needs trust > 5');
    p.choose(0);
    expect(p.vars['trust'], 3, reason: '+2 from the option, +1 from the label');
    expect(p.label, 'good');
    expect(p.text, '', reason: 'waiting first');
    frames(40);
    expect(p.text, 'Friends!');
    next();
    expect(p.ended, isTrue);
    expect(p.ending, 'Good ending');
    expect(SaveData.instance.getMap('storytest_endings')?['names'], ['Good ending']);
  });

  test('the other branches: rude hides the character and ends badly (picked with the 2 key)', () {
    play(_story);
    for (var i = 0; i < 4; i++) {
      next();
    }
    expect(player!.choices, hasLength(2));
    Input.onKeyDown(LogicalKeyboardKey.digit2);
    frames(1);
    Input.onKeyUp(LogicalKeyboardKey.digit2);
    expect(player!.label, isNot('good'));
    frames(20);
    expect(player!.onStage, isEmpty);
    expect(player!.ending, 'Bad ending');
  });

  test('saving and loading restore the line, variables, background and characters', () {
    play(_story);
    next();
    player!.vars['trust'] = 4;
    player!.save('2');
    final info = player!.saveInfo('2')!;
    expect(info['label'], 'start');
    expect(info['preview'], 'Ann: This is important.');
    next();
    next();
    expect(player!.speaker, 'Stranger');
    player!.load('2');
    expect(player!.text, 'This is important.');
    expect(player!.vars['trust'], 4);
    expect(player!.onStage, ['ann']);
    expect(player!.background, 'room');

    // The title's Continue: it asks for the autosave, then switches to the story scene
    final storyScene = EmberScene(name: 'Story')
      ..addEntity(EmberEntity(name: 'Story')..addComponent(StoryPlayerComponent(storyFile: 'test.story', saveKey: 'storytest')));
    engine.sceneLibrary = () => {'Story': storyScene.toJson()};
    EmberScripts.instance.gameData[StoryPlayerComponent.loadRequest] = 'auto';
    engine.loadLevel('Story');
    engine.step();
    final again = engine.activeScene.componentsOf<StoryPlayerComponent>().single;
    expect(identical(again, player), isFalse);
    expect(again.text, 'This is important.');
  });

  test('history, Auto, Skip (stops at choices) and Ctrl to skip', () {
    play(_story);
    next();
    next();
    expect(player!.history, ['Ann: Hello, Kit! Trust is 0.', 'Ann: This is important.', 'The wind blows.']);

    player!.auto = true;
    frames(60 * 6);
    expect(player!.choices, isNotEmpty, reason: 'Auto read on to the choice');

    play(_story);
    player!.skip = true;
    frames(30);
    expect(player!.choices, isNotEmpty);
    expect(player!.skip, isFalse, reason: 'a choice stops Skip');

    play(_story);
    Input.onKeyDown(LogicalKeyboardKey.controlLeft);
    frames(30);
    Input.onKeyUp(LogicalKeyboardKey.controlLeft);
    expect(player!.choices, isNotEmpty);
  });

  test('event lines call onStoryEvent in scripts', () {
    play(_story, extra: {
      'listener.ember': '''
        var heard = "";
        void onStoryEvent(name) { heard = name; }
      ''',
    });
    final listener = EmberEntity(name: 'Listener')..addComponent(ScriptComponent(scriptName: 'listener.ember'));
    engine.activeScene.addEntity(listener);
    frames(1);
    for (var i = 0; i < 4; i++) {
      next();
    }
    player!.choose(0);
    expect((listener.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior).field('heard'), 'cheer');
  });

  test('edits to the story file apply while playing', () {
    play(_story);
    EmberScripts.instance.updateText('test.story', _story.replaceFirst('Hello, {name}!', 'Howdy, {name}!'));
    frames(1);
    player!.jump('start');
    expect(player!.text, startsWith('Howdy'));
  });

  test('it paints the screen and clicks reach the choices and the quick menu', () {
    play(_story);
    for (var i = 0; i < 4; i++) {
      next();
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const view = Rect.fromLTWH(0, 0, 960, 540);
    UIRenderer.paintAll(canvas, view, 1, engine.activeScene); // the hook paints the story
    recorder.endRecording();
    // The second choice sits below the first, in the middle of the screen
    Input.onMouseMove(Vector2(480, 540 * 0.42 + 29), Vector2.zero());
    Input.onMouseDown(0);
    engine.step();
    Input.onMouseUp(0);
    expect(player!.ending, 'Bad ending', reason: 'clicked "Be rude"');

    play(_story);
    final r2 = ui.PictureRecorder();
    player!.paint(Canvas(r2), view, 1);
    r2.endRecording();
    void clickAt(Offset at) {
      Input.onMouseMove(Vector2(at.dx, at.dy), Vector2.zero());
      Input.onMouseDown(0);
      engine.step();
      Input.onMouseUp(0);
      final r = ui.PictureRecorder();
      player!.paint(Canvas(r), view, 1); // refresh the clickable areas
      r.endRecording();
    }

    // Clicking the dialogue box reads on
    final box = Rect.fromLTWH(960 * 0.06, 540 * 0.69, 960 * 0.88, 540 * 0.27);
    clickAt(box.center); // finishes the typewriter
    clickAt(box.center);
    expect(player!.text, 'This is important.');
    // The quick menu pills sit above the box's right edge: Menu, Load, Save, Skip, Auto, Log
    // (the test font is 1 em per letter: "Menu" is 48 + 18 px wide, then 6 px gaps)
    clickAt(Offset(box.right - 33, box.top - 19));
    expect(engine.activeScene.name, 'Story', reason: 'Menu with no title scene restarts the story');
    clickAt(Offset(box.right - 105, box.top - 19));
    expect(player!.overlay, 'load');
    clickAt(const Offset(480, 500)); // Back
    expect(player!.overlay, '');
    clickAt(Offset(box.right - 249, box.top - 19));
    expect(player!.skip, isTrue);
  });
}

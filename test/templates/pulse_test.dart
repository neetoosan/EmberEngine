import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/audio/audio_system.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';
import 'package:ember_engine/templates/pulse_game.dart';
import 'package:ember_engine/templates/pulse_scripts.dart';
import 'package:ember_engine/templates/pulse_song.dart';

EmberEngine get engine => EmberEngine.instance;
EmberEntity find(String name) => engine.activeScene.findByName(name)!;
EmberScriptBehavior get stage => find('Stage').getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
Map get counts => stage.field('counts') as Map;
String text(String name) => find(name).getComponent<UITextComponent>()!.text;
const laneKeys = [LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyJ, LogicalKeyboardKey.keyK];

void startStage(String difficulty) {
  engine.stop();
  final project = TemplateCatalog.getByType(ProjectTemplateType.pulse).createProject(name: 'Pulse Test');
  EmberScripts.instance.loadAll(project.scripts);
  final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
  engine.sceneLibrary = () => levels;
  engine.loadScene(project.scenes[Pulse.stage]!);
  engine.step();
  EmberScripts.instance.gameData['pulseDiff'] = difficulty;
  engine.restartScene();
  engine.step();
}

List<(double, int, double)> chart(String difficulty) => [
      for (final line in PulseSong.chart(difficulty).split('\n'))
        if (line.isNotEmpty && !line.startsWith('#'))
          () {
            final p = line.split(' ');
            return (double.parse(p[0]), int.parse(p[1]), double.parse(p[2]));
          }(),
    ];

/// Plays a chart: presses each lane on time (+ [late] seconds), holds long notes,
/// [releaseEarly] lets go of holds half-way.
void play(String difficulty, {double late = 0, bool releaseEarly = false, bool idle = false}) {
  final notes = chart(difficulty);
  final up = <int, double>{}; // lane -> when to let go
  var i = 0;
  for (var frame = 0; frame < 60 * 80 && stage.field('state') != 'done'; frame++) {
    final t = AudioSystem.instance.musicTime;
    for (final e in up.entries.toList()) {
      if (t >= e.value) {
        Input.onKeyUp(laneKeys[e.key]);
        up.remove(e.key);
      }
    }
    while (!idle && i < notes.length && notes[i].$1 + late <= t + 1 / 120) {
      final (time, lane, hold) = notes[i];
      Input.onKeyUp(laneKeys[lane]);
      Input.onKeyDown(laneKeys[lane]);
      up[lane] = hold > 0 ? time + (releaseEarly ? hold / 2 : hold + 0.05) : time + 0.05;
      i++;
    }
    engine.step();
  }
  for (final k in laneKeys) {
    Input.onKeyUp(k);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('pulse test');
    for (final d in ['easy', 'normal', 'hard']) {
      SaveData.instance.remove('pulse_best_$d');
      SaveData.instance.remove('pulse_grade_$d');
    }
    SaveData.instance.remove('pulse_offset');
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() {
    Input.reset();
    engine.timeScale = 1;
    AudioSystem.instance.musicOffset = 0;
    engine.stop();
  });

  test('the music clock: runs from the start, pauses, corrects drift, has an offset and an end', () {
    final a = AudioSystem.instance;
    a.playMusic('song.wav', loop: false);
    expect(a.musicTime, 0);
    a.update(0.5);
    expect(a.musicTime, closeTo(0.5, 1e-9));
    a.pauseMusic();
    a.update(1);
    expect(a.musicTime, closeTo(0.5, 1e-9), reason: 'paused');
    a.resumeMusic();
    a.update(0.25);
    expect(a.musicTime, closeTo(0.75, 1e-9));
    a.musicPosition(a.music!, 0.76);
    expect(a.musicTime, closeTo(0.75, 1e-9), reason: 'small jitter is ignored');
    a.musicPosition(a.music!, 1.2);
    expect(a.musicTime, closeTo(1.2, 1e-9), reason: 'drift is corrected');
    a.musicOffset = 0.05;
    expect(a.musicTime, closeTo(1.15, 1e-9));
    expect(a.musicEnded, isFalse);
    a.musicFinished(a.music!);
    expect(a.musicEnded, isTrue);
    a.stopMusic();
    expect(a.musicPlaying, isFalse);
  });

  test('the template: title and stage, scripts and three charts, art and sound on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.pulse).createProject(name: 'Pulse');
    expect(project.scenes.keys, containsAll([Pulse.title, Pulse.stage]));
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in pulseScripts.keys.where(EmberScripts.isScriptFile)) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Pulse.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    final easy = chart('easy'), normal = chart('normal'), hard = chart('hard');
    expect(easy.length, lessThan(normal.length));
    expect(normal.length, lessThan(hard.length));
    for (final c in [easy, normal, hard]) {
      for (var k = 1; k < c.length; k++) {
        expect(c[k].$1, greaterThanOrEqualTo(c[k - 1].$1), reason: 'in time order');
        expect(c[k].$1 == c[k - 1].$1 && c[k].$2 == c[k - 1].$2, isFalse, reason: 'no two notes on one lane at once');
      }
      expect(c.last.$1, lessThan(PulseSong.length));
    }
    expect(hard.any((n) => n.$3 > 0), isTrue, reason: 'hold notes');
  });

  test('hitting every note on time is a full combo with an S', () {
    startStage('normal');
    play('normal');
    expect(stage.field('state'), 'done');
    expect(counts['miss'], 0);
    expect(counts['perfect'], chart('normal').length);
    expect(text('ResultsTitle'), 'FULL COMBO!');
    expect(text('ResultsGrade'), 'S');
    expect(stage.field('maxCombo'), chart('normal').length);
    expect(SaveData.instance.getInt('pulse_best_normal'), stage.field('score'));
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('timing decides the judgement; letting go of a hold early misses it; idle misses everything', () {
    startStage('easy');
    play('easy', late: 0.07);
    expect(counts['great'], greaterThan(0));
    expect(counts['perfect'], 0);

    startStage('hard');
    play('hard', releaseEarly: true);
    final holds = chart('hard').where((n) => n.$3 > 0).length;
    expect(counts['miss'], holds);

    startStage('easy');
    play('easy', idle: true);
    expect(counts['miss'], chart('easy').length);
    expect(text('ResultsGrade'), 'D');
  });

  test('pausing freezes the song; the title sets the offset and the difficulty', () {
    startStage('normal');
    for (var i = 0; i < 60; i++) {
      engine.step();
    }
    Input.onKeyDown(LogicalKeyboardKey.keyP);
    engine.step();
    Input.onKeyUp(LogicalKeyboardKey.keyP);
    final t = AudioSystem.instance.musicTime;
    for (var i = 0; i < 60; i++) {
      engine.step();
    }
    expect(AudioSystem.instance.musicTime, t);
    expect(find('PausedText').enabled, isTrue);

    engine.stop();
    final project = TemplateCatalog.getByType(ProjectTemplateType.pulse).createProject(name: 'Pulse');
    EmberScripts.instance.loadAll(project.scripts);
    final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
    engine.sceneLibrary = () => levels;
    engine.loadScene(project.scenes[Pulse.title]!);
    engine.step();
    UIRenderer.dispatch(engine.activeScene, 'later');
    UIRenderer.dispatch(engine.activeScene, 'later');
    expect(SaveData.instance.getDouble('pulse_offset'), closeTo(0.02, 1e-9));
    expect(text('OffsetText'), 'Audio offset 20 ms');
    UIRenderer.dispatch(engine.activeScene, 'hard');
    for (var i = 0; i < 90 && engine.activeScene.name != Pulse.stage; i++) {
      engine.step();
    }
    expect(engine.activeScene.name, Pulse.stage);
    expect(stage.field('difficulty'), 'hard');
    expect(AudioSystem.instance.musicOffset, closeTo(0.02, 1e-9));
  });
}

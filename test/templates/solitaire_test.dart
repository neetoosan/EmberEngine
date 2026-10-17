import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:ember_engine/templates/solitaire_game.dart';
import 'package:ember_engine/templates/solitaire_scripts.dart';

EmberEngine get engine => EmberEngine.instance;
EmberScriptBehavior get table => engine.activeScene.findByName('Table')!.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
Object? field(String name) => table.field(name);
Object? call(String fn, [List<Object?> args = const []]) => table.callFunction(fn, args);
List<List<int>> get piles => [for (final p in field('_piles') as List) (p as List).cast<int>()];
List<bool> get up => (field('_up') as List).cast<bool>();
String text(String name) => engine.activeScene.findByName(name)!.getComponent<UITextComponent>()!.text;

/// Card ids: suit * 13 + rank - 1 (suits: 0 hearts, 1 diamonds, 2 clubs, 3 spades).
int card(int suit, int rank) => suit * 13 + rank - 1;

void start(String mode) {
  engine.stop();
  EmberScripts.instance.loadAll(solitaireScripts);
  engine.loadScene(buildSolitaireTable(mode));
  engine.step();
}

void runUntil(bool Function() done, double maxSeconds) {
  for (var i = 0; i < maxSeconds * 60 && !done(); i++) {
    engine.step();
  }
}

void frames(int n) => runUntil(() => false, n / 60);

/// Replaces the layout: [layout] maps pile index to card ids (all others empty);
/// every card is face up unless listed in [down].
void arrange(Map<int, List<int>> layout, {Set<int> down = const {}}) {
  final raw = field('_piles') as List;
  for (var p = 0; p < 13; p++) {
    final pile = raw[p] as List;
    pile
      ..clear()
      ..addAll(layout[p] ?? const []);
  }
  final u = field('_up') as List;
  for (var id = 0; id < 52; id++) {
    u[id] = !down.contains(id);
  }
  for (var id = 0; id < 52; id++) {
    final inPlay = layout.values.any((l) => l.contains(id));
    engine.activeScene.findByName('Card $id')!.enabled = inPlay;
  }
  call('layoutAll', [0]);
  frames(2);
}

Vector2 posOf(int id) => engine.activeScene.findByName('Card $id')!.getComponent<Transform2DComponent>()!.position.clone();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('solitaire test');
    for (final mode in Solitaire.modes) {
      for (final what in ['time', 'score', 'wins']) {
        SaveData.instance.remove('solitaire_${mode}_$what');
      }
    }
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
  });

  tearDown(() {
    Input.reset();
    engine.stop();
  });

  test('the template has a title and two tables, scripts that compile and art on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.solitaire).createProject(name: 'Solitaire');
    expect(project.scenes.keys, containsAll([Solitaire.title, ...Solitaire.modes]));
    expect(project.defaultSceneName, Solitaire.title);
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in solitaireScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Solitaire.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('the deal: seven columns of 1 to 7 cards with the top one face up, 24 in the stock', () {
    start('Draw 1');
    runUntil(() => field('state') == 'play', 5);
    expect(field('state'), 'play');
    final p = piles;
    for (var c = 0; c < 7; c++) {
      expect(p[6 + c], hasLength(c + 1));
      for (var j = 0; j < c; j++) {
        expect(up[p[6 + c][j]], isFalse, reason: 'column $c card $j');
      }
      expect(up[p[6 + c].last], isTrue);
    }
    expect(p[0], hasLength(24));
    expect({for (final pile in p) ...pile}, hasLength(52), reason: 'every card once');
    // Each card sits where its pile says
    final top = p[12].last;
    expect(posOf(top).distanceTo(Vector2(Solitaire.col0 + 6 * Solitaire.colStep, Solitaire.tableY + 6 * 14.0)), lessThan(1));
  });

  test('the stock turns over 1 card (Draw 1) or 3 (Draw 3); an empty stock takes the waste back', () {
    start('Draw 1');
    runUntil(() => field('state') == 'play', 5);
    call('drawStock');
    expect(piles[1], hasLength(1));
    expect(up[piles[1].last], isTrue);
    for (var i = 0; i < 23; i++) {
      call('drawStock');
    }
    expect(piles[0], isEmpty);
    call('drawStock'); // empty: recycle
    expect(piles[0], hasLength(24));
    expect(piles[1], isEmpty);
    expect(field('passes'), 1);

    start('Draw 3');
    runUntil(() => field('state') == 'play', 5);
    call('drawStock');
    expect(piles[1], hasLength(3));
  });

  test('rules: alternate colours downward in the columns, a King on an empty column, suits upward on the foundations', () {
    start('Draw 1');
    runUntil(() => field('state') == 'play', 5);
    arrange({6: [card(0, 13)], 7: [card(3, 12)], 8: [card(0, 12)], 1: [card(1, 1)]});
    expect(call('canMove', [[card(3, 12)], 6]), isTrue, reason: 'black Queen on a red King');
    expect(call('canMove', [[card(0, 12)], 6]), isFalse, reason: 'red Queen on a red King');
    expect(call('canMove', [[card(3, 12)], 9]), isFalse, reason: 'only a King goes into an empty column');
    expect(call('canMove', [[card(0, 13)], 9]), isTrue);
    expect(call('canMove', [[card(1, 1)], 2]), isTrue, reason: 'an Ace starts a foundation');
    expect(call('canMove', [[card(3, 12)], 2]), isFalse);
    arrange({2: [card(1, 1)], 6: [card(1, 2)], 7: [card(0, 2)]});
    expect(call('canMove', [[card(1, 2)], 2]), isTrue, reason: 'same suit, one higher');
    expect(call('canMove', [[card(0, 2)], 2]), isFalse, reason: 'another suit');
  });

  test('a move scores, turns over the card left behind, and can be undone', () {
    start('Draw 1');
    runUntil(() => field('state') == 'play', 5);
    arrange({6: [card(2, 9), card(0, 1)]}, down: {card(2, 9)});
    call('doMove', [[card(0, 1)], 6, 2]);
    expect(piles[2], [card(0, 1)]);
    expect(up[card(2, 9)], isTrue, reason: 'the card underneath turned over');
    expect(field('score'), 15, reason: '+10 to a foundation, +5 for turning a card');
    expect(field('moves'), 1);
    frames(20);
    expect(engine.activeScene.findByName('Card ${card(2, 9)}')!.getComponent<Transform2DComponent>()!.scale.x, 1);

    call('undo');
    expect(piles[6], [card(2, 9), card(0, 1)]);
    expect(up[card(2, 9)], isFalse);
    expect(field('score'), 0);
  });

  test('dragging a card onto a column moves it; dropping it somewhere wrong sends it back', () {
    start('Draw 1');
    runUntil(() => field('state') == 'play', 5);
    arrange({6: [card(0, 13)], 9: [card(3, 12)], 10: [card(2, 7)]});
    final from = posOf(card(3, 12));
    final onto = posOf(card(0, 13));
    Input.instance.mouseWorldPosition = from;
    Input.onMouseDown(0);
    engine.step();
    Input.instance.mouseWorldPosition = from + Vector2(0, 30);
    engine.step();
    expect(posOf(card(3, 12)).y, closeTo(from.y + 30, 0.5), reason: 'the card follows the mouse');
    Input.instance.mouseWorldPosition = onto + Vector2(4, 20);
    engine.step();
    Input.onMouseUp(0);
    engine.step();
    expect(piles[6], [card(0, 13), card(3, 12)]);
    frames(20);
    expect(posOf(card(3, 12)).distanceTo(onto + Vector2(0, 26)), lessThan(1), reason: 'fanned below the King');

    // The 7 of clubs cannot go on the Queen: it slides home
    final home = posOf(card(2, 7));
    Input.instance.mouseWorldPosition = home;
    Input.onMouseDown(0);
    engine.step();
    Input.instance.mouseWorldPosition = posOf(card(3, 12)) + Vector2(0, 20);
    engine.step();
    Input.onMouseUp(0);
    engine.step();
    frames(20);
    expect(piles[10], [card(2, 7)]);
    expect(posOf(card(2, 7)).distanceTo(home), lessThan(1));
  });

  test('clicking a card sends it to the best place', () {
    start('Draw 1');
    runUntil(() => field('state') == 'play', 5);
    arrange({1: [card(1, 1)], 6: [card(0, 6)], 7: [card(3, 5)]});
    Input.instance.mouseWorldPosition = posOf(card(1, 1));
    Input.onMouseDown(0);
    engine.step();
    Input.onMouseUp(0);
    engine.step();
    expect(piles[2], [card(1, 1)], reason: 'the Ace went up');
    Input.instance.mouseWorldPosition = posOf(card(3, 5));
    Input.onMouseDown(0);
    engine.step();
    Input.onMouseUp(0);
    engine.step();
    expect(piles[6], [card(0, 6), card(3, 5)], reason: 'black 5 onto the red 6');
  });

  test('the hint finds a move that helps, and highlights its cards', () {
    start('Draw 1');
    runUntil(() => field('state') == 'play', 5);
    // The black 5 can go on the red 6, uncovering a face-down card
    arrange({6: [card(0, 6)], 7: [card(1, 9), card(3, 5)]}, down: {card(1, 9)});
    final move = call('findMove') as List;
    expect(move[0], [card(3, 5)]);
    expect(move[1], 7);
    expect(move[2], 6);
    call('hint');
    Color tint(int id) => engine.activeScene.findByName('Card $id')!.getComponent<FlameSpriteComponent>()!.tint;
    expect(tint(card(3, 5)), isNot(const Color(0xFFFFFFFF)));
    expect(tint(card(0, 6)), isNot(const Color(0xFFFFFFFF)), reason: 'and where it goes');
    frames(70);
    expect(tint(card(3, 5)), const Color(0xFFFFFFFF), reason: 'the highlight fades');
  });

  test('when everything is face up, Finish plays the rest; winning bounces the cards and saves the record', () {
    start('Draw 1');
    runUntil(() => field('state') == 'play', 5);
    // Each suit in its own column, King at the bottom and Ace on top
    arrange({for (var s = 0; s < 4; s++) 6 + s: [for (var r = 13; r >= 1; r--) card(s, r)]});
    call('check');
    expect(engine.activeScene.findByName('AutoButton')!.enabled, isTrue);
    call('autoFinish');
    runUntil(() => field('state') == 'won', 15);
    expect(field('state'), 'won');
    expect([for (var p = 2; p <= 5; p++) piles[p].length], [13, 13, 13, 13]);
    frames(220); // the bouncing cards, then the results
    expect(engine.activeScene.findByName('ResultsPanel')!.enabled, isTrue);
    expect(text('ResultsTitle'), 'YOU WIN!');
    expect(SaveData.instance.getInt('solitaire_Draw 1_wins'), 1);
    expect(SaveData.instance.getInt('solitaire_Draw 1_time'), greaterThan(0));
  });

  test('the title shows the records of each mode', () {
    SaveData.instance.setInt('solitaire_Draw 3_wins', 2);
    SaveData.instance.setInt('solitaire_Draw 3_time', 125);
    engine.stop();
    EmberScripts.instance.loadAll(solitaireScripts);
    engine.loadScene(buildSolitaireTitle());
    engine.step();
    expect(text('Draw 1 Record'), 'No wins yet');
    expect(text('Draw 3 Record'), 'Wins 2  ·  best 2:05');
  });

  for (final mode in Solitaire.modes) {
    test('$mode: hundreds of moves, draws and undos run without a script error', () {
      start(mode);
      runUntil(() => field('state') == 'play', 5);
      for (var i = 0; i < 300 && field('state') == 'play'; i++) {
        final move = call('findMove') as List;
        if (move.isNotEmpty && i % 7 != 6) {
          call('doMove', [move[0], move[1], move[2]]);
        } else if (i % 11 == 10) {
          call('undo');
        } else {
          call('drawStock');
        }
        engine.step();
      }
      final all = [for (final p in piles) ...p];
      expect(all.toSet(), hasLength(52), reason: 'no card lost or doubled');
      expect(all, hasLength(52));
      expect(EmberScripts.instance.problems, isEmpty);
    });
  }
}

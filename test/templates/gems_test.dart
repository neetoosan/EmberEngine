import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';
import 'package:ember_engine/templates/gems_game.dart';
import 'package:ember_engine/templates/gems_scripts.dart';
import 'package:vector_math/vector_math_64.dart';

EmberEngine get engine => EmberEngine.instance;
EmberScriptBehavior scriptOf(String name) =>
    engine.activeScene.findByName(name)!.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
EmberScriptBehavior get board => scriptOf('Board');
Object? field(String name) => board.field(name);
Object? call(String fn, [List<Object?> args = const []]) => board.callFunction(fn, args);
List<int> get kinds => (field('_kinds') as List).cast<int>();
List<String> get specials => (field('_special') as List).cast<String>();
String text(String name) => engine.activeScene.findByName(name)!.getComponent<UITextComponent>()!.text;
int idx(int r, int c) => r * 8 + c;
Vector2 cellCenter(int i) => Vector2(Gems.left + (i % 8) * Gems.cell + Gems.cell / 2, Gems.top + (i ~/ 8) * Gems.cell + Gems.cell / 2);

void start(EmberScene scene) {
  engine.stop();
  EmberScripts.instance.loadAll(gemsScripts);
  engine.loadScene(scene);
  engine.step();
}

void runUntil(bool Function() done, double maxSeconds) {
  for (var i = 0; i < maxSeconds * 60 && !done(); i++) {
    engine.step();
  }
}

void waitIdle() => runUntil(() => field('state') != 'busy' && field('state') != 'starting', 10);

/// A known board without lines: colour (row + column) % 3, plus [extra] cells.
void paint([Map<int, int> extra = const {}]) {
  for (var i = 0; i < 64; i++) {
    call('setGem', [i, extra[i] ?? ((i % 8) + (i ~/ 8)) % 3, '']);
  }
}

/// Lets a swap animation finish and its clear run, before anything falls.
void afterSwap() {
  for (var i = 0; i < 13; i++) {
    engine.step();
  }
}

void click(Vector2 at) {
  Input.instance.mouseWorldPosition = at;
  Input.onMouseDown(0);
  engine.step();
  Input.onMouseUp(0);
  engine.step();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('gems test');
    for (final key in ['gems_unlocked', for (final l in Gems.levels) ...['gems_stars_$l', 'gems_best_$l']]) {
      SaveData.instance.remove(key);
    }
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
  });

  tearDown(() {
    Input.reset();
    engine.stop();
  });

  test('the template has a title and three levels, scripts that compile and art on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.gems).createProject(name: 'Gems');
    expect(project.scenes.keys, containsAll([Gems.title, ...Gems.levels]));
    expect(project.defaultSceneName, Gems.title);
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in gemsScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Gems.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('a level starts with a full board, no lines and at least one move', () {
    start(buildGemsLevel1());
    waitIdle();
    expect(field('state'), 'idle');
    expect(kinds.where((k) => k >= 0 && k < 5).length, 64, reason: 'five colours on level 1');
    expect(call('matches'), isEmpty);
    expect(call('findMove'), hasLength(2));
    expect(engine.activeScene.allEntities.where((e) => e.enabled && e.tags.contains('gem')).length, 64);
    expect(text('MovesText'), '18');
    expect(text('GoalText'), 'Score 2500');
  });

  test('a swap that makes a line clears it, scores, refills and uses a move; one that does not is undone', () {
    start(buildGemsLevel1());
    waitIdle();
    final move = (call('findMove') as List).cast<int>();
    call('swap', [move[0], move[1]]);
    waitIdle();
    expect(field('moves'), 17);
    expect(field('score') as int, greaterThanOrEqualTo(180));
    expect(kinds.every((k) => k >= 0), isTrue, reason: 'the board refilled');
    expect(call('matches'), isEmpty, reason: 'every cascade resolved');
    expect(engine.activeScene.allEntities.where((e) => e.enabled && e.tags.contains('gem')).length, 64, reason: 'cleared gems were removed');

    paint();
    final before = List<int>.of(kinds);
    call('swap', [idx(0, 0), idx(1, 0)]); // no line either way
    waitIdle();
    expect(kinds, before, reason: 'swapped back');
    expect(field('moves'), 17, reason: 'no move used');
  });

  test('clicking a gem then a neighbour swaps them, and so does dragging', () {
    start(buildGemsLevel1());
    waitIdle();
    paint({idx(7, 0): 3, idx(7, 1): 3, idx(6, 2): 3});
    click(cellCenter(idx(6, 2)));
    expect(field('_selected'), idx(6, 2));
    expect(engine.activeScene.findByName('Selector')!.enabled, isTrue);
    click(cellCenter(idx(7, 2)));
    waitIdle();
    expect(field('moves'), 17);

    paint({idx(7, 0): 4, idx(7, 1): 4, idx(6, 2): 4});
    Input.instance.mouseWorldPosition = cellCenter(idx(6, 2));
    Input.onMouseDown(0);
    engine.step();
    Input.instance.mouseWorldPosition = cellCenter(idx(6, 2)) + Vector2(0, 40); // drag down
    engine.step();
    Input.onMouseUp(0);
    waitIdle();
    expect(field('moves'), 16);
  });

  test('special gems: four makes a blast gem, a T makes a bomb, five makes a star', () {
    start(buildGemsLevel1());
    waitIdle();
    // Row 7: 3 3 _ 3, with a 3 above the gap
    paint({idx(7, 0): 3, idx(7, 1): 3, idx(7, 3): 3, idx(6, 2): 3});
    call('swap', [idx(6, 2), idx(7, 2)]);
    afterSwap();
    expect(specials[idx(7, 2)], 'row');
    waitIdle();

    // T: row 5 cols 2-4 and column 3 rows 5-7 meet at (5,3); the 4 drops in from (4,3)
    paint({idx(5, 2): 4, idx(5, 4): 4, idx(6, 3): 4, idx(7, 3): 4, idx(4, 3): 4});
    call('swap', [idx(4, 3), idx(5, 3)]);
    afterSwap();
    expect(specials[idx(5, 3)], 'bomb');
    waitIdle();

    // Row 7: 5 5 _ 5 5, with a 5 above the gap
    paint({idx(7, 0): 5, idx(7, 1): 5, idx(7, 3): 5, idx(7, 4): 5, idx(6, 2): 5});
    call('swap', [idx(6, 2), idx(7, 2)]);
    afterSwap();
    expect(specials[idx(7, 2)], 'star');
    expect(kinds[idx(7, 2)], 6);
  });

  test('special gems go off: a row blast clears its row, a bomb its 3 x 3, a star a whole colour', () {
    start(buildGemsLevel1());
    waitIdle();
    paint({idx(7, 0): 3, idx(7, 1): 3});
    call('setGem', [idx(7, 2), 3, 'row']);
    call('resolve', [call('matches')]);
    expect([for (var c = 0; c < 8; c++) kinds[idx(7, c)]], everyElement(-1), reason: 'the whole row');
    waitIdle();

    paint({idx(4, 2): 3, idx(4, 3): 3});
    call('setGem', [idx(4, 4), 3, 'bomb']);
    call('resolve', [call('matches')]);
    for (var r = 3; r <= 5; r++) {
      for (var c = 3; c <= 5; c++) {
        expect(kinds[idx(r, c)], -1, reason: 'bomb area ($r, $c)');
      }
    }
    expect(kinds[idx(2, 4)], isNot(-1), reason: 'outside the bomb');
    waitIdle();

    paint();
    call('setGem', [idx(3, 3), 6, 'star']);
    final color = kinds[idx(3, 4)];
    call('swap', [idx(3, 3), idx(3, 4)]);
    afterSwap();
    expect(kinds.where((k) => k == color), isEmpty, reason: 'every gem of that colour');
    expect(kinds[idx(3, 3)], -1, reason: 'the star is used up');
  });

  test('collect and ice goals count up; the ice level is won when the last ice breaks', () {
    start(buildGemsLevel2());
    waitIdle();
    expect(text('GoalText'), 'Collect 20 rubies  (0 / 20)');
    paint();
    call('pop', [idx(0, 0)]); // colour 0: a ruby
    call('hud');
    expect(field('collected'), 1);
    expect(text('GoalText'), 'Collect 20 rubies  (1 / 20)');

    start(buildGemsLevel3());
    waitIdle();
    expect(field('iceLeft'), 16);
    expect(engine.activeScene.allEntities.where((e) => e.enabled && e.tags.contains('ice')).length, 16);
    call('crackIce', [idx(1, 1)]);
    expect(field('iceLeft'), 16, reason: 'ice takes two hits');
    call('crackIce', [idx(1, 1)]);
    expect(field('iceLeft'), 15);
    for (var i = 0; i < 64; i++) {
      call('crackIce', [i]);
      call('crackIce', [i]);
    }
    expect(field('iceLeft'), 0);
    call('settle');
    expect(field('state'), 'won');
    expect(text('ResultsTitle'), 'LEVEL CLEAR!');
    expect(engine.activeScene.findByName('NextButton')!.enabled, isFalse, reason: 'the last level');
    expect(SaveData.instance.getInt('gems_unlocked'), 4);
  });

  test('score levels play every move: win with stars and unlock the next level, or lose', () {
    start(buildGemsLevel1());
    waitIdle();
    board.setField('moves', 0);
    call('settle');
    expect(field('state'), 'lost');
    expect(text('ResultsTitle'), 'OUT OF MOVES');
    expect(engine.activeScene.findByName('NextButton')!.enabled, isFalse);

    start(buildGemsLevel1());
    waitIdle();
    board.setField('score', 5000);
    board.setField('moves', 0);
    call('settle');
    expect(field('state'), 'won');
    expect(engine.activeScene.findByName('ResultsStars')!.getComponent<UIImageComponent>()!.filled, 2);
    final next = engine.activeScene.findByName('NextButton')!;
    expect(next.enabled, isTrue);
    expect(next.getComponent<UIButtonComponent>()!.action, 'level:Level 2');
    expect(SaveData.instance.getInt('gems_unlocked'), 2);
    expect(SaveData.instance.getInt('gems_stars_Level 1'), 2);
  });

  test('the title shows saved stars and locks levels not reached yet', () {
    SaveData.instance.setInt('gems_unlocked', 2);
    SaveData.instance.setInt('gems_stars_Level 1', 3);
    start(buildGemsTitle());
    engine.step();
    expect(engine.activeScene.findByName('Level1 Stars')!.getComponent<UIImageComponent>()!.filled, 3);
    expect(engine.activeScene.findByName('Level2 Button')!.getComponent<UIButtonComponent>()!.text, '2');
    expect(engine.activeScene.findByName('Level3 Button')!.getComponent<UIButtonComponent>()!.text, 'Locked');
  });

  for (final (name, build) in [('Level 1', buildGemsLevel1), ('Level 3', buildGemsLevel3)]) {
    test('$name can be played to the end by always making the first possible move', () {
      start(build());
      for (var turn = 0; turn < 40; turn++) {
        waitIdle();
        if (field('state') != 'idle') break;
        final move = (call('findMove') as List).cast<int>();
        expect(move, hasLength(2), reason: 'a move always exists (the board reshuffles otherwise)');
        call('swap', [move[0], move[1]]);
      }
      expect(['won', 'lost'], contains(field('state')));
      expect(EmberScripts.instance.problems, isEmpty);
    });
  }
}

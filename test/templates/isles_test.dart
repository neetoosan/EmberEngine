import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/save_data.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';
import 'package:ember_engine/templates/isles_game.dart';
import 'package:ember_engine/templates/isles_scripts.dart';
import 'package:vector_math/vector_math_64.dart';

EmberEngine get engine => EmberEngine.instance;
EmberEntity find(String name) => engine.activeScene.findByName(name)!;
EmberScriptBehavior scriptOf(EmberEntity e) => e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
EmberScriptBehavior get colony => scriptOf(find('Colony'));
Object? field(String n) => colony.field(n);
Object? call(String fn, [List<Object?> args = const []]) => colony.callFunction(fn, args);
String text(String name) => find(name).getComponent<UITextComponent>()!.text;
FlameTileMapComponent get map => find('Map').getComponent<FlameTileMapComponent>()!;
List<EmberEntity> named(String n) => engine.activeScene.allEntities.where((e) => e.enabled && e.name == n).toList();
List<EmberEntity> tagged(String t) => engine.activeScene.allEntities.where((e) => e.enabled && e.tags.contains(t)).toList();
Vector2 pos(EmberEntity e) => e.getComponent<Transform2DComponent>()!.position;

void startIsland({int seed = 1717}) {
  engine.stop();
  final project = TemplateCatalog.getByType(ProjectTemplateType.isles).createProject(name: 'Isles Test');
  EmberScripts.instance.loadAll(project.scripts);
  final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
  engine.sceneLibrary = () => levels;
  engine.loadScene(project.scenes[Isles.island]!);
  engine.step();
  EmberScripts.instance.gameData['islesSeed'] = seed;
  engine.restartScene();
  engine.step();
}

void run(double seconds, {bool Function()? until}) {
  for (var i = 0; i < seconds * 60; i++) {
    if (until != null && until()) return;
    engine.step();
  }
}

/// A cell where [kind] may be built (as the colony script decides).
List<int> spotFor(String kind) {
  for (var r = 0; r < Isles.size; r++) {
    for (var c = 0; c < Isles.size; c++) {
      if (call('whyNot', [kind, [c, r]]) == '') return [c, r];
    }
  }
  throw StateError('nowhere to build $kind');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('isles test');
    SaveData.instance.remove('isles_best');
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() {
    Input.reset();
    engine.stop();
  });

  test('the template: title and island, scripts that compile, art and sound on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.isles).createProject(name: 'Isles');
    expect(project.scenes.keys, containsAll([Isles.title, Isles.island]));
    expect(project.defaultSceneName, Isles.title);
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in islesScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Isles.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/templates/isles/'));
  });

  test('the island grows from its seed: sea around, land in the middle, trees and rocks, the Town Hall', () {
    startIsland();
    expect(EmberScripts.instance.problems, isEmpty);
    expect(map.layout, 'isometric');
    final tiles = map.tiles;
    expect(map.getTile(0, 0), anyOf(1, 2), reason: 'sea at the corner');
    expect(tiles.where((t) => t >= 4).length, greaterThan(60), reason: 'grass');
    expect(tiles.where((t) => t == 3).length, greaterThan(10), reason: 'beaches');
    expect(tagged('tree').length, greaterThan(5));
    expect(named('Town Hall'), hasLength(1));
    final first = List<int>.of(tiles);
    startIsland();
    expect(map.tiles, first);
    startIsland(seed: 42);
    expect(map.tiles, isNot(first));
  });

  test('buildings follow their rules and cost resources; the economy ticks', () {
    startIsland();
    colony.setField('wood', 200);
    expect(call('whyNot', ['Farm', [0, 0]]), 'Build on open land');
    final hall = scriptOf(named('Town Hall').single).field('cell') as List;
    expect(call('whyNot', ['House', hall]), 'Build on open land', reason: 'taken');
    final wood = field('wood') as num;
    final spot = spotFor('Lumber Camp');
    call('build', ['Lumber Camp', spot]);
    expect(field('wood'), wood - 20);
    colony.setField('wood', 200);
    expect(named('Lumber Camp'), hasLength(1));
    expect(map.isWalkable(spot[0], spot[1]), isFalse, reason: 'buildings block the way');
    call('build', ['House', spotFor('House')]);
    call('build', ['Farm', spotFor('Farm')]);
    final before = (field('wood') as num, field('food') as num, field('people') as num);
    run(10);
    expect(field('wood'), greaterThan(before.$1));
    expect(field('food'), greaterThan(before.$2));
    expect(field('people'), greaterThan(before.$3), reason: 'houses fill up');
    expect(text('PeopleText'), contains('/ 10'));
  });

  test('guards are trained, box-selected and sent with a right-click along a path', () {
    startIsland();
    colony.setField('food', 100);
    colony.setField('wood', 100);
    colony.setField('people', 8);
    call('trainGuard');
    call('trainGuard');
    run(0.1);
    final gs = named('Guard');
    expect(gs, hasLength(2));
    final hallAt = pos(named('Town Hall').single);
    expect(pos(gs[0]).distanceTo(hallAt), lessThan(90), reason: 'trained at the Town Hall');
    expect(field('guards'), 2);

    final a = pos(gs[0]), b = pos(gs[1]);
    Input.instance.mouseWorldPosition = Vector2(a.x - 60, a.y - 60);
    Input.onMouseDown(0);
    engine.step();
    Input.instance.mouseWorldPosition = Vector2(b.x + 60, b.y + 40);
    engine.step();
    expect(find('Selection Box').enabled, isTrue);
    Input.onMouseUp(0);
    engine.step();
    expect((field('selected') as List).length, 2);
    expect(gs[0].findChild('Ring')!.enabled, isTrue);

    // Send them to a far grass cell
    final from = scriptOf(gs[0]).field('cell') as List;
    List<int>? far;
    for (var r = 0; r < Isles.size && far == null; r++) {
      for (var c = 0; c < Isles.size; c++) {
        final p = map.findPath(from[0] as int, from[1] as int, c, r);
        if (p != null && p.length >= 5) {
          far = [c, r];
          break;
        }
      }
    }
    final target = map.cellRect(far![0], far[1]).center;
    Input.instance.mouseWorldPosition = Vector2(target.dx, target.dy);
    Input.onMouseDown(2);
    engine.step();
    Input.onMouseUp(2);
    run(15, until: () => pos(gs[0]).distanceTo(Vector2(target.dx, target.dy + 16)) < 6);
    expect(pos(gs[0]).distanceTo(Vector2(target.dx, target.dy + 16)), lessThan(6));
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('raiders land, attack the nearest building; guards and towers fight back', () {
    startIsland();
    colony.setField('wood', 200);
    colony.setField('stone', 100);
    colony.setField('food', 100);
    colony.setField('people', 10);
    call('build', ['Watchtower', spotFor('Watchtower')]);
    for (var i = 0; i < 3; i++) {
      call('trainGuard');
    }
    colony.setField('raidTimer', 0.1);
    run(0.3);
    expect(field('wave'), 1);
    final raiders = named('Raider');
    expect(raiders, hasLength(4));
    run(60, until: () => named('Raider').isEmpty);
    expect(named('Raider'), isEmpty, reason: 'the raid was beaten off');
    expect(field('state'), 'play');
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('losing the Town Hall ends the game; the Ember Beacon wins it', () {
    startIsland();
    final hall = named('Town Hall').single.getComponent<HealthComponent>()!;
    hall.damage(hall.maxHealth);
    run(0.2);
    expect(field('state'), 'lost');
    expect(text('ResultsTitle'), 'THE COLONY HAS FALLEN');

    startIsland();
    colony.setField('wood', 500);
    colony.setField('stone', 500);
    colony.setField('food', 500);
    call('build', ['Ember Beacon', spotFor('Ember Beacon')]);
    expect(field('state'), 'won');
    expect(find('RetryButton').enabled, isTrue);
  });

  test('the title starts a new or a fixed island', () {
    engine.stop();
    final project = TemplateCatalog.getByType(ProjectTemplateType.isles).createProject(name: 'Isles');
    EmberScripts.instance.loadAll(project.scripts);
    final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
    engine.sceneLibrary = () => levels;
    engine.loadScene(project.scenes[Isles.title]!);
    engine.step();
    UIRenderer.dispatch(engine.activeScene, 'classic');
    run(1.5, until: () => engine.activeScene.name == Isles.island);
    expect(engine.activeScene.name, Isles.island);
    expect(field('seed'), 1717);
  });
}

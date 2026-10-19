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
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/two_d/bullet_pool.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';
import 'package:ember_engine/templates/depths_game.dart';
import 'package:ember_engine/templates/depths_scripts.dart';
import 'package:vector_math/vector_math_64.dart';

EmberEngine get engine => EmberEngine.instance;
EmberEntity find(String name) => engine.activeScene.findByName(name)!;
EmberScriptBehavior scriptOf(EmberEntity e) => e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
EmberScriptBehavior get game => scriptOf(find('Dungeon'));
Map get runState => game.field('run') as Map;
String text(String name) => find(name).getComponent<UITextComponent>()!.text;
List<EmberEntity> named(String name) => engine.activeScene.allEntities.where((e) => e.enabled && e.name == name).toList();
List<EmberEntity> tagged(String tag) => engine.activeScene.allEntities.where((e) => e.enabled && e.tags.contains(tag)).toList();
Vector2 pos(EmberEntity e) => e.getComponent<Transform2DComponent>()!.position;
FlameTileMapComponent get map => find('Dungeon').getComponent<FlameTileMapComponent>()!;

void startRun({int? seed}) {
  engine.stop();
  final project = TemplateCatalog.getByType(ProjectTemplateType.depths).createProject(name: 'Depths Test');
  EmberScripts.instance.loadAll(project.scripts);
  final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
  engine.sceneLibrary = () => levels;
  engine.loadScene(project.scenes[Depths.dungeon]!);
  engine.step();
  // Play clears Game.data: set the seed, then start the floor again
  EmberScripts.instance.gameData['depths'] = null;
  EmberScripts.instance.gameData['depthsSeed'] = seed;
  engine.restartScene();
  engine.step();
}

void run(double seconds, {bool Function()? until}) {
  for (var i = 0; i < seconds * 60; i++) {
    if (until != null && until()) return;
    engine.step();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('depths test');
    SaveData.instance.remove('depths_best');
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() {
    Input.reset();
    engine.timeScale = 1;
    engine.stop();
  });

  test('the template: title and dungeon, scripts that compile, art and sound on disk', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.depths).createProject(name: 'Depths');
    expect(project.scenes.keys, containsAll([Depths.title, Depths.dungeon]));
    expect(project.defaultSceneName, Depths.title);
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in depthsScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Depths.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/templates/depths/'));
  });

  test('a floor is generated from the seed: rooms, walls, the hero in the first room, stairs, monsters, torches', () {
    startRun(seed: 1234);
    expect(EmberScripts.instance.problems, isEmpty);
    expect(runState['seed'], 1234);
    final tiles = map.tiles;
    expect(tiles.where((t) => t >= 2 && t <= 5).length, greaterThan(300), reason: 'floors');
    expect(tiles.where((t) => t >= 10 && t <= 25).length, greaterThan(500), reason: 'auto-tiled walls');
    expect(tiles.contains(1), isFalse);
    final hero = pos(find('Hero'));
    final cell = map.cellRect(0, 0);
    expect(map.getTile((hero.x / cell.width).floor(), (hero.y / cell.height).floor()), inInclusiveRange(2, 5), reason: 'standing on floor');
    expect(named('Stairs'), hasLength(1));
    expect(tagged('enemy'), isNotEmpty);
    expect(tagged('torch').length, greaterThanOrEqualTo(4));
    expect(text('FloorText'), 'Floor 1');
    expect(text('SeedText'), 'Seed 1234');

    final first = List<int>.of(tiles);
    startRun(seed: 1234);
    expect(map.tiles, first, reason: 'the same seed makes the same dungeon');
    startRun(seed: 99);
    expect(map.tiles, isNot(first));
  });

  test('the hero walks but not through walls, casts bolts that stop at walls, and dashes', () {
    startRun(seed: 7);
    final hero = find('Hero');
    final start = pos(hero).clone();
    Input.onKeyDown(LogicalKeyboardKey.keyD);
    run(0.5);
    Input.onKeyUp(LogicalKeyboardKey.keyD);
    final moved = pos(hero).x - start.x;
    expect(moved, greaterThan(10));
    // Walk into a wall for a long time: it stops at it
    Input.onKeyDown(LogicalKeyboardKey.keyW);
    run(6);
    Input.onKeyUp(LogicalKeyboardKey.keyW);
    final y = pos(hero).y;
    final cell = map.cellRect(0, 0);
    final above = map.getTile((pos(hero).x / cell.width).floor(), ((y - 20) / cell.height).floor());
    expect(above, inInclusiveRange(10, 25), reason: 'a wall right above');

    final bolts = find('Bolts').getComponent<BulletPool2DComponent>()!;
    Input.onKeyDown(LogicalKeyboardKey.arrowUp);
    run(0.2);
    Input.onKeyUp(LogicalKeyboardKey.arrowUp);
    run(0.6);
    expect(bolts.count, 0, reason: 'bolts fired at the wall stopped there');

    Input.onKeyDown(LogicalKeyboardKey.keyS);
    engine.step();
    Input.onKeyDown(LogicalKeyboardKey.shiftLeft);
    engine.step();
    Input.onKeyUp(LogicalKeyboardKey.shiftLeft);
    expect(hero.getComponent<HealthComponent>()!.enabled, isFalse, reason: "can't be hurt mid-dash");
    run(0.4);
    Input.onKeyUp(LogicalKeyboardKey.keyS);
    expect(hero.getComponent<HealthComponent>()!.enabled, isTrue);
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('monsters can be killed for coins; chests give relics that change the hero', () {
    startRun(seed: 21);
    final monster = tagged('enemy').first;
    final health = monster.getComponent<HealthComponent>()!;
    health.damage(health.maxHealth, source: find('Bolts'));
    engine.step();
    engine.step();
    expect(game.field('kills'), 1);

    game.callFunction('openChest', [pos(find('Hero'))]);
    final relic = named('Relic').single;
    final kind = scriptOf(relic).field('kind') as String;
    expect(['power', 'haste', 'split', 'vigor', 'swift', 'fortune'], contains(kind));
    final before = Map.of(runState);
    run(1.5, until: () => !engine.activeScene.allEntities.contains(relic));
    expect(engine.activeScene.allEntities.contains(relic), isFalse, reason: 'picked up');
    expect(runState['relics'], [kind]);
    expect(runState, isNot(before));
    expect(text('RelicsText'), isNotEmpty);

    game.callFunction('collect', ['split']);
    expect(runState['shots'], greaterThanOrEqualTo(2));
    game.callFunction('collect', ['vigor']);
    expect(find('Hero').getComponent<HealthComponent>()!.maxHealth, runState['maxHearts']);
  });

  test('the stairs lead to a new floor that keeps the hero and relics', () {
    startRun(seed: 5);
    game.callFunction('collect', ['power']);
    find('Hero').getComponent<HealthComponent>()!.damage(1);
    final stairs = named('Stairs').single;
    find('Hero').getComponent<Transform2DComponent>()!.position = pos(stairs);
    run(2, until: () => text('FloorText') == 'Floor 2');
    expect(runState['floor'], 2);
    expect(runState['damage'], 2);
    expect(find('Hero').getComponent<HealthComponent>()!.health, 3);
    expect(text('FloorText'), 'Floor 2');
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('dying ends the run and saves the deepest floor; the same seed can be replayed', () {
    startRun(seed: 77);
    final hero = find('Hero').getComponent<HealthComponent>()!;
    hero.invulnerableTime = 0;
    for (var i = 0; i < 4; i++) {
      hero.damage(1);
    }
    run(0.2);
    expect(game.field('state'), 'dead');
    expect(SaveData.instance.getInt('depths_best'), 1);
    expect(text('ResultsTitle'), 'YOU FELL ON FLOOR 1');
    expect(find('SameSeedButton').enabled, isTrue);
    UIRenderer.dispatch(engine.activeScene, 'same');
    run(1, until: () => game.field('state') == 'play');
    expect(runState['seed'], 77);
    expect(runState['floor'], 1);
  });
}

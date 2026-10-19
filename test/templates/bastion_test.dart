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
import 'package:ember_engine/subsystems/two_d/path_follower.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';
import 'package:ember_engine/templates/bastion_game.dart';
import 'package:ember_engine/templates/bastion_layout.dart';
import 'package:ember_engine/templates/bastion_scripts.dart';
import 'package:vector_math/vector_math_64.dart';

EmberEngine get engine => EmberEngine.instance;
EmberEntity find(String name) => engine.activeScene.findByName(name)!;
EmberScriptBehavior scriptOf(EmberEntity e) => e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
EmberScriptBehavior get game => scriptOf(find('Game'));
Object? field(String name) => game.field(name);
Object? call(String fn, [List<Object?> args = const []]) => game.callFunction(fn, args);
String text(String name) => find(name).getComponent<UITextComponent>()!.text;
List<EmberEntity> tagged(String tag) => engine.activeScene.allEntities.where((e) => e.enabled && e.tags.contains(tag)).toList();
Vector2 pos(EmberEntity e) => e.getComponent<Transform2DComponent>()!.position;

void startBattle({bool hard = false}) {
  engine.stop();
  final project = TemplateCatalog.getByType(ProjectTemplateType.bastion).createProject(name: 'Bastion Test');
  EmberScripts.instance.loadAll(project.scripts);
  final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
  engine.sceneLibrary = () => levels;
  engine.loadScene(project.scenes[Bastion.battle]!);
  engine.step();
  EmberScripts.instance.gameData['bastionHard'] = hard;
  game.callFunction('onStart', const []); // pick up the difficulty set after Play
}

void run(double seconds, {bool Function()? until}) {
  for (var i = 0; i < seconds * 60; i++) {
    if (until != null && until()) return;
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

void key(LogicalKeyboardKey k) {
  Input.onKeyDown(k);
  engine.step();
  Input.onKeyUp(k);
  engine.step();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerAllSubsystems();
    await SaveData.instance.open('bastion test');
    SaveData.instance.remove('bastion_stars');
    SaveData.instance.remove('bastion_stars_hard');
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() {
    Input.reset();
    engine.timeScale = 1;
    engine.stop();
  });

  test('the template: title and battle, scripts that compile, art and sound on disk, the road matches the layout', () {
    final project = TemplateCatalog.getByType(ProjectTemplateType.bastion).createProject(name: 'Bastion');
    expect(project.scenes.keys, containsAll([Bastion.title, Bastion.battle]));
    expect(project.defaultSceneName, Bastion.title);
    EmberScripts.instance.loadAll(project.scripts);
    for (final file in bastionScripts.keys) {
      expect(EmberScripts.instance.compileError(file), isNull, reason: file);
    }
    for (final asset in Bastion.assetFiles) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/templates/bastion/'));
  });

  test('pick a tower, see where it can go, build it on grass but not on the road, trees or another tower', () {
    startBattle();
    expect(field('gold'), 220);
    UIRenderer.dispatch(engine.activeScene, 'build:Archer');
    engine.step();
    expect(find('Ghost').enabled, isTrue);
    expect(find('Range').enabled, isTrue);

    click(Vector2(196, 230)); // on the road
    expect(tagged('tower'), isEmpty);
    expect(text('Subtitle'), "You can't build there");
    final (dx, dy, _) = BastionLayout.decor.first;
    click(Vector2(dx, dy)); // a tree
    expect(tagged('tower'), isEmpty);

    click(Vector2(258, 228));
    final towers = tagged('tower');
    expect(towers, hasLength(1));
    expect(pos(towers.single), Vector2(260, 220), reason: 'snapped to the grid');
    expect(field('gold'), 170);
    expect(find('Ghost').enabled, isFalse, reason: 'placing ends after one tower');

    key(LogicalKeyboardKey.digit1);
    expect(find('Cell').enabled, isTrue);
    click(Vector2(262, 222));
    expect(tagged('tower'), hasLength(1), reason: 'that cell is taken');
    expect(field('selected'), towers.single, reason: 'clicking a tower while building selects it');
    expect(field('placing'), '');
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('a wave marches along the road; towers shoot, enemies die for gold; leaks cost lives', () {
    startBattle();
    call('build', ['Archer', Vector2(260, 220)]);
    call('build', ['Cannon', Vector2(300, 300)]);
    final gold = field('gold') as num;
    UIRenderer.dispatch(engine.activeScene, 'start');
    engine.step();
    expect(field('state'), 'wave');
    run(3);
    final walkers = tagged('enemy');
    expect(walkers, isNotEmpty);
    expect(walkers.first.getComponent<PathFollower2DComponent>()!.progress, greaterThan(0));
    run(60, until: () => field('state') == 'build');
    expect(field('state'), 'build', reason: 'wave 1 is over');
    expect(field('gold'), greaterThan(gold), reason: 'rewards and the wave bonus');
    expect(field('wave'), 1);
    expect(EmberScripts.instance.problems, isEmpty);

    // With no towers, wave 2 reaches the keep
    for (final t in tagged('tower')) {
      call('select', [t]);
      call('sell');
    }
    engine.step();
    expect(tagged('tower'), isEmpty);
    UIRenderer.dispatch(engine.activeScene, 'start');
    run(80, until: () => field('state') == 'build');
    expect(field('lives'), lessThan(20));
    expect(field('leaks'), greaterThan(0));
  });

  test('upgrading costs gold and makes a tower stronger; selling gives most of it back', () {
    startBattle();
    call('build', ['Archer', Vector2(260, 220)]);
    final tower = tagged('tower').single;
    final range = scriptOf(tower).field('range') as num;
    click(Vector2(260, 220));
    expect(field('selected'), tower);
    expect(find('UpgradeButton').enabled, isTrue);
    UIRenderer.dispatch(engine.activeScene, 'upgrade');
    engine.step();
    expect(scriptOf(tower).field('level'), 1);
    expect(scriptOf(tower).field('range'), greaterThan(range));
    expect(field('gold'), 220 - 50 - 60);
    expect(tower.getComponent<Transform2DComponent>()!.zIndex, 5);
    UIRenderer.dispatch(engine.activeScene, 'sell');
    engine.step();
    expect(field('gold'), 110 + 77);
    expect(tower.enabled && engine.activeScene.allEntities.contains(tower), isFalse);
  });

  test('frost slows, tesla chains, cannons splash', () {
    startBattle();
    call('build', ['Frost', Vector2(260, 220)]);
    call('build', ['Tesla', Vector2(140, 180)]);
    UIRenderer.dispatch(engine.activeScene, 'start');
    var slowed = false;
    var hurtTogether = 0;
    run(25, until: () {
      final e = tagged('enemy');
      slowed = slowed || e.any((x) => x.getComponent<PathFollower2DComponent>()!.slowed);
      final hurt = e.where((x) => x.getComponent<HealthComponent>()!.health < x.getComponent<HealthComponent>()!.maxHealth).length;
      if (hurt > hurtTogether) hurtTogether = hurt;
      return slowed && hurtTogether >= 3;
    });
    expect(slowed, isTrue);
    expect(hurtTogether, greaterThanOrEqualTo(3), reason: 'lightning jumps between enemies');
    expect(EmberScripts.instance.problems, isEmpty);
  });

  test('waves get bigger, bring new enemies and a Dark Knight every fifth wave', () {
    startBattle();
    List<String> kinds(int n) => [for (final e in (call('makeWave', [n]) as List)) (e as List)[1] as String];
    expect(kinds(1).toSet(), {'Grunt'});
    expect(kinds(4).toSet(), {'Grunt', 'Runner', 'Golem'});
    expect(kinds(5), contains('Knight'));
    expect(kinds(15).where((k) => k == 'Knight'), hasLength(3));
    expect(kinds(10).length, greaterThan(kinds(2).length));
  });

  test('surviving the last wave is a victory with stars; losing every life is a defeat', () {
    startBattle();
    game.setField('wave', 14);
    call('startWave');
    expect(field('wave'), 15);
    for (final e in tagged('enemy')) {
      e.enabled = false;
    }
    game.setField('queue', []);
    game.setField('alive', 0);
    run(0.2);
    expect(field('state'), 'won');
    expect(text('ResultsTitle'), 'VICTORY');
    expect(SaveData.instance.getInt('bastion_stars'), 3);

    startBattle(hard: true);
    expect(field('gold'), 180);
    call('leaked', [25]);
    expect(field('state'), 'lost');
    expect(find('RetryButton').enabled, isTrue);
  });

  test('the title shows the stars and starts Normal or Hard', () {
    SaveData.instance.setInt('bastion_stars', 2);
    engine.stop();
    final project = TemplateCatalog.getByType(ProjectTemplateType.bastion).createProject(name: 'Bastion');
    EmberScripts.instance.loadAll(project.scripts);
    final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
    engine.sceneLibrary = () => levels;
    engine.loadScene(project.scenes[Bastion.title]!);
    engine.step();
    expect(find('NormalStars').getComponent<UIImageComponent>()!.filled, 2);
    UIRenderer.dispatch(engine.activeScene, 'hard');
    run(1.5, until: () => engine.activeScene.name == Bastion.battle);
    expect(engine.activeScene.name, Bastion.battle);
    expect(field('gold'), 180, reason: 'hard starts with less gold');
  });
}

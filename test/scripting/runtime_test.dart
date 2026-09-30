import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';

EmberEngine get engine => EmberEngine.instance;
EmberScripts get scripts => EmberScripts.instance;

EmberEntity box(String name, Vector2 at, {String? script, Map<String, Object?>? vars, Set<String>? tags}) {
  final e = EmberEntity(name: name, tags: tags)
    ..addComponent(Transform2DComponent(position: at, size: Vector2(20, 20)))
    ..addComponent(FlameHitbox2DComponent(size: Vector2(20, 20), isSolid: false, debugDraw: false));
  if (script != null) e.addComponent(ScriptComponent(scriptName: script, vars: vars));
  return e;
}

void frames(int n, {Set<LogicalKeyboardKey> hold = const {}}) {
  for (var i = 0; i < n; i++) {
    for (final k in hold) {
      Input.onKeyDown(k);
    }
    engine.step();
  }
  for (final k in hold) {
    Input.onKeyUp(k);
  }
}

void play(EmberScene scene) {
  engine.loadScene(scene);
  engine.step();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    scripts.loadAll({});
  });
  tearDown(engine.stop);

  test('a script moves its entity with the keyboard; Inspector values override defaults', () {
    scripts.loadAll({
      'mover.ember': '''
        var speed = 100;
        var label = "hero";
        void onUpdate(dt) {
          self.position = self.position + Input.move * speed * dt;
          if (Input.pressed("Space")) print("jump by \$label");
        }
      ''',
    });
    final a = box('A', Vector2.zero(), script: 'mover.ember');
    final b = box('B', Vector2.zero(), script: 'mover.ember', vars: {'speed': 200});
    play(EmberScene()..addEntity(a)..addEntity(b));
    frames(60, hold: {LogicalKeyboardKey.keyD});
    expect(a.getComponent<Transform2DComponent>()!.position.x, closeTo(100, 3));
    expect(b.getComponent<Transform2DComponent>()!.position.x, closeTo(200, 6));
    frames(1, hold: {LogicalKeyboardKey.space});
    expect(scripts.output, containsAll(['jump by hero']));
  });

  test('script variables show in the Inspector and save with the scene', () {
    scripts.loadAll({'enemy.ember': 'var speed = 80;\nvar angry = false;\nvar title = "Slime";\nfinal secret = 1;\nvar _hidden = 2;\nvar list = [];'});
    final e = box('E', Vector2.zero(), script: 'enemy.ember');
    final sc = e.getComponent<ScriptComponent>()!;
    final props = {for (final p in sc.inspectableProperties) p.label: p};
    expect(props.keys, containsAll(['Script', 'Speed', 'Angry', 'Title']));
    expect(props.keys, isNot(contains('Secret')));
    props['Speed']!.setValue(120.0);
    props['Angry']!.setValue(true);
    final copy = EmberEntity.fromJson(e.toJson());
    final cs = copy.getComponent<ScriptComponent>()!;
    expect(cs.vars, {'speed': 120, 'angry': true});
    expect((cs.scriptInstance as ConfigurableScript).exposedFields['speed'], 120);
  });

  test('scripts attach even when loaded after the scene (project open order)', () {
    final json = (EmberScene()..addEntity(box('Late', Vector2.zero(), script: 'late.ember'))).toJson();
    final scene = EmberScene.fromJson(json); // script not known yet
    scripts.loadAll({'late.ember': 'var ran = false;\nvoid onStart() { ran = true; print("late ok"); }'});
    play(scene);
    expect(scripts.output, contains('late ok'));
  });

  test('triggers, tags, find, destroy and cross-entity calls', () {
    scripts.loadAll({
      'collector.ember': '''
        var coins = 0;
        void onTriggerEnter(other) {
          if (other.hasTag("coin")) {
            coins += other.script.value;
            destroy(other);
            find("Door").call("open", coins);
          }
        }
      ''',
      'coin.ember': 'var value = 5;',
      'door.ember': 'var isOpen = false;\nopen(n) { isOpen = n >= 5; return isOpen; }',
    });
    final hero = box('Hero', Vector2.zero(), script: 'collector.ember');
    final coin = box('Coin', Vector2(5, 0), script: 'coin.ember', tags: {'coin'});
    final door = box('Door', Vector2(500, 0), script: 'door.ember');
    play(EmberScene()..addEntity(hero)..addEntity(coin)..addEntity(door));
    frames(3);
    expect(coin.scene, isNull);
    final heroScript = hero.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    final doorScript = door.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    expect(heroScript.field('coins'), 5);
    expect(doorScript.field('isOpen'), true);
  });

  test('components by name, health events, spawn copies, timers and tweens', () {
    scripts.loadAll({
      'boss.ember': '''
        var log = [];
        void onStart() {
          self.add("Health");
          self.health.maxHealth = 10;
          self.health.health = 10;
          self.health.team = "monster";
          after(0.5, () => log.add("half second"));
          var n = 0;
          every(0.1, () { n++; if (n == 3) { log.add("ticked 3"); return false; } });
          tween(0.2, (t) => self.x = t * 100, ease: "linear", then: () => log.add("tween done"));
          spawn("Template", vec(300, 0)).name = "Spawned";
        }
        void onDamaged(amount, source) { log.add("hurt \${amount.round()}"); }
        void onDeath(killer) { log.add("died"); }
      ''',
    });
    final boss = box('Boss', Vector2.zero(), script: 'boss.ember');
    final template = box('Template', Vector2.zero())..enabled = false;
    play(EmberScene()..addEntity(boss)..addEntity(template));
    frames(40);
    expect(scripts.problems.map((p) => '$p'), isEmpty);
    final s = boss.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    final health = boss.getComponent<HealthComponent>()!;
    expect(health.maxHealth, 10);
    health.damage(4);
    health.invulnerableTime = 0;
    frames(20);
    health.damage(20);
    frames(2);
    expect(boss.scene, isNull, reason: 'Health removes it on death');
    expect(s.field('log'), containsAll(['hurt 4', 'died', 'half second', 'ticked 3', 'tween done']));
    expect(boss.getComponent<Transform2DComponent>()?.position.x ?? 100, closeTo(100, 0.01));
    final spawned = engine.activeScene.findByName('Spawned');
    expect(spawned, isNotNull);
    expect(spawned!.enabled, isTrue);
    expect(spawned.getComponent<Transform2DComponent>()!.position.x, 300);
  });

  test('runtime errors are reported once with a line number and do not stop other scripts', () {
    scripts.loadAll({
      'broken.ember': 'var n = 0;\nvoid onUpdate(dt) {\n  n++;\n  self.nope = 1;\n}',
      'fine.ember': 'var ticks = 0;\nvoid onUpdate(dt) { ticks++; }',
    });
    final broken = box('Broken', Vector2.zero(), script: 'broken.ember');
    final fine = box('Fine', Vector2.zero(), script: 'fine.ember');
    play(EmberScene()..addEntity(broken)..addEntity(fine));
    frames(30);
    final problems = scripts.problems.where((p) => p.runtime).toList();
    expect(problems, hasLength(1));
    expect(problems.single.file, 'broken.ember');
    expect(problems.single.line, 4);
    expect(problems.single.message, contains('nope'));
    expect(problems.single.count, greaterThan(20));
    final fineScript = fine.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    expect(fineScript.field('ticks'), greaterThan(29));
  });

  test('an endless loop is stopped instead of freezing the engine', () {
    scripts.loadAll({'loop.ember': 'void onUpdate(dt) { while (true) {} }'});
    play(EmberScene()..addEntity(box('L', Vector2.zero(), script: 'loop.ember')));
    frames(2);
    expect(scripts.problems.single.message, contains('endless loop'));
  });

  test('compile errors are listed, and the entity just does nothing', () {
    scripts.loadAll({'bad.ember': 'void onUpdate(dt) {\n  var x = ;\n}'});
    expect(scripts.compileError('bad.ember')!.line, 2);
    play(EmberScene()..addEntity(box('B', Vector2.zero(), script: 'bad.ember')));
    frames(3);
    expect(engine.logs.any((l) => l.message.contains('bad.ember has an error')), isTrue);
  });

  test('hot reload: editing a running script swaps the code and keeps its variables', () {
    scripts.loadAll({'counter.ember': 'var count = 0;\nvoid onUpdate(dt) { count += 1; }'});
    final e = box('C', Vector2.zero(), script: 'counter.ember');
    play(EmberScene()..addEntity(e));
    frames(10);
    final s = e.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    final before = s.field('count') as int;
    expect(scripts.update('counter.ember', 'var count = 0;\nvar bonus = 100;\nvoid onUpdate(dt) { count += bonus; }'), isNull);
    frames(1);
    expect(s.field('count'), before + 100);
    // A broken edit is rejected; the old code keeps running
    expect(scripts.update('counter.ember', 'void onUpdate(dt) { count += ; }'), isNotNull);
    frames(1);
    expect(s.field('count'), before + 200);
  });
}

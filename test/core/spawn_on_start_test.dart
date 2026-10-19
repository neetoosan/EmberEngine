import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';

EmberEngine get engine => EmberEngine.instance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() => engine.stop());

  test('entities spawned while the scene starts are started too (their scripts get events)', () {
    EmberScripts.instance.loadAll({
      'maker.ember': 'var made = null;\nvoid onStart() { made = spawn("Minion", vec(10, 10)); }\n',
      'minion.ember': 'var started = false;\nvar died = false;\nvoid onStart() { started = true; }\nvoid onDeath(killer) { died = true; }\n',
    });
    final scene = EmberScene(name: 'Spawn')
      ..addEntity(EmberEntity(name: 'Minion', enabled: false)
        ..addComponent(Transform2DComponent())
        ..addComponent(HealthComponent(maxHealth: 1, destroyOnDeath: false))
        ..addComponent(ScriptComponent(scriptName: 'minion.ember')))
      ..addEntity(EmberEntity(name: 'Maker')..addComponent(ScriptComponent(scriptName: 'maker.ember')));
    engine.loadScene(scene);
    engine.step();
    final maker = engine.activeScene.findByName('Maker')!.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    final made = maker.field('made') as EmberEntity;
    final minion = made.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    expect(minion.field('started'), isTrue);
    made.getComponent<HealthComponent>()!.damage(1);
    expect(minion.field('died'), isTrue);
  });

  test('find() prefers a visible entity to a hidden template of the same name', () {
    EmberScripts.instance.loadAll({
      'f.ember': '''
var a = null;
var b = null;
void onStart() { a = find("Minion"); spawn("Minion", vec(5, 5)); b = find("Minion"); }
''',
    });
    final template = EmberEntity(name: 'Minion', enabled: false)..addComponent(Transform2DComponent());
    final f = EmberEntity(name: 'F')..addComponent(ScriptComponent(scriptName: 'f.ember'));
    engine.loadScene(EmberScene(name: 'Find')
      ..addEntity(template)
      ..addEntity(f));
    engine.step();
    final s = f.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    expect(identical(s.field('a'), template), isTrue, reason: 'only the template exists yet');
    expect(identical(s.field('b'), template), isFalse);
    expect((s.field('b') as EmberEntity).enabled, isTrue);
  });
}

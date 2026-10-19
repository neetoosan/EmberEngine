import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/subsystems/combat/combat.dart';
import 'package:ember_engine/subsystems/particles/particle_system.dart';
import 'package:ember_engine/subsystems/two_d/bullet_pool.dart';
import 'package:ember_engine/subsystems/two_d/camera2d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/two_d/flame_game.dart';
import 'package:ember_engine/subsystems/two_d/parallax.dart';
import 'package:ember_engine/subsystems/ui/ui_text.dart';
import 'package:ember_engine/subsystems/ui/ui_widgets.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flame/game.dart' as flame;

EmberEngine get engine => EmberEngine.instance;

EmberEntity target(String name, Vector2 at, String team) => EmberEntity(name: name)
  ..addComponent(Transform2DComponent(position: at, size: Vector2(20, 20), anchor: EmberAnchor.center))
  ..addComponent(HealthComponent(maxHealth: 5, team: team, invulnerableTime: 0, destroyOnDeath: false));

/// A scene with a 960×540 camera, a pool for [team] and whatever [extra] holds.
BulletPool2DComponent start({String team = 'monster', List<EmberEntity> extra = const [], Map<String, String> scripts = const {}}) {
  engine.stop();
  EmberScripts.instance.loadAll(scripts);
  final scene = EmberScene(name: 'Bullets')
    ..addEntity(EmberEntity(name: 'Camera')
      ..addComponent(Transform2DComponent(position: Vector2(480, 270), size: Vector2.zero()))
      ..addComponent(Camera2DComponent(designWidth: 960, designHeight: 540)));
  final pool = BulletPool2DComponent(team: team, margin: 20);
  scene.addEntity(EmberEntity(name: 'Shots')
    ..addComponent(Transform2DComponent(position: Vector2.zero(), size: Vector2.zero()))
    ..addComponent(pool));
  for (final e in extra) {
    scene.addEntity(e);
  }
  engine.loadScene(scene);
  engine.step();
  return pool;
}

void steps(int n) {
  for (var i = 0; i < n; i++) {
    engine.step();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.setMode(EngineMode.twoD);
  });
  tearDown(() => engine.stop());

  test('fire, ring and spread make bullets that fly, curve, speed up and leave the screen', () {
    final pool = start();
    pool.fire(100, 100, 0, 600);
    pool.ring(480, 270, 12, 100);
    pool.spread(480, 270, 90, 5, 60, 100);
    expect(pool.count, 18);
    final b = pool.bullets.first;
    steps(30); // half a second
    expect(b.x, closeTo(400, 2));
    expect(b.y, closeTo(100, 0.01));

    final spread = pool.bullets.skip(13).map((b) => b.angle).toList();
    expect(spread, [60, 75, 90, 105, 120]);

    pool.clear();
    pool.fire(480, 270, 0, 100, curve: 90, accel: 100, maxSpeed: 150);
    steps(60);
    expect(pool.bullets.single.angle, closeTo(90, 1), reason: 'turned 90°/s for a second');
    expect(pool.bullets.single.speed, 150, reason: 'sped up to its limit');

    pool.clear();
    pool.fire(950, 270, 0, 600);
    steps(10);
    expect(pool.count, 0, reason: 'gone once past the camera plus the margin');
    pool.fire(480, 270, 0, 0, life: 0.5);
    steps(40);
    expect(pool.count, 0, reason: 'gone after its life');
  });

  test('bullets damage other teams, pass through their own team and flashing targets, and are used up', () {
    final enemy = target('Enemy', Vector2(300, 100), 'monster');
    final friend = target('Friend', Vector2(200, 100), 'player');
    final pool = start(team: 'player', extra: [enemy, friend]);
    pool.fire(100, 100, 0, 600, damage: 2);
    steps(30);
    expect(friend.getComponent<HealthComponent>()!.health, 5, reason: 'same team');
    expect(enemy.getComponent<HealthComponent>()!.health, 3);
    expect(pool.count, 0, reason: 'the bullet was used up');

    enemy.getComponent<HealthComponent>()!.invulnerableTime = 10;
    enemy.getComponent<HealthComponent>()!.damage(1);
    pool.fire(100, 100, 0, 600);
    steps(30);
    expect(enemy.getComponent<HealthComponent>()!.health, 2, reason: 'a flashing target lets bullets through');
    expect(pool.count, 1);

    enemy.getComponent<HealthComponent>()!.enabled = false;
    pool.clear();
    pool.fire(100, 100, 0, 600);
    steps(30);
    expect(pool.count, 1, reason: 'a disabled Health is not a target');
  });

  test('bullets passing close send onGraze; clearAround removes nearby bullets', () {
    final ship = target('Ship', Vector2(300, 120), 'player')
      ..addComponent(ScriptComponent(scriptName: 'ship.ember'));
    final pool = start(extra: [ship], scripts: {'ship.ember': 'var grazed = 0;\nvoid onGraze() { grazed++; }\n'});
    pool.grazeRadius = 20;
    pool.fire(100, 100, 0, 600, radius: 4);
    steps(40);
    final script = ship.getComponent<ScriptComponent>()!.scriptInstance as EmberScriptBehavior;
    expect(script.field('grazed'), 1, reason: 'once per bullet');
    expect(ship.getComponent<HealthComponent>()!.health, 5);

    pool.clear();
    pool.ring(480, 270, 20, 0);
    pool.fire(100, 100, 0, 0);
    expect(pool.clearAround(480, 270, 50), 20);
    expect(pool.count, 1);
  });

  test('scripts fire with named options, aim with angleTo, and read count', () {
    const src = '''
void onStart() {
  var shots = self.bullets;
  shots.fire(vec(100, 100), angleTo(vec(100, 100), vec(100, 300)), 200, frame: 2, curve: 10);
  shots.ring(vec(480, 270), 8, 50, offset: 45);
  shots.spread(vec(480, 270), 0, 3, 30, 50);
  print(shots.count);
}
''';
    engine.stop();
    EmberScripts.instance.loadAll({'gun.ember': src});
    final pool = BulletPool2DComponent();
    final scene = EmberScene(name: 'Gun')
      ..addEntity(EmberEntity(name: 'Gun')
        ..addComponent(Transform2DComponent())
        ..addComponent(pool)
        ..addComponent(ScriptComponent(scriptName: 'gun.ember')));
    engine.loadScene(scene);
    engine.step();
    expect(EmberScripts.instance.problems, isEmpty);
    expect(pool.count, 12);
    expect(pool.bullets.first.angle, closeTo(90, 0.2), reason: 'straight down (curving a little since)');
    expect(pool.bullets.first.frame, 2);
    expect(pool.bullets[1].angle, 45);
  });

  test('2,000 bullets update quickly', () {
    final pool = start(extra: [for (var i = 0; i < 20; i++) target('T$i', Vector2(50.0 * i, 500), 'player')]);
    pool.maxBullets = 5000;
    for (var i = 0; i < 2000; i++) {
      pool.fire(480, 270, i * 0.18, 20);
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < 60; i++) {
      pool.onUpdate(1 / 60);
    }
    watch.stop();
    expect(pool.count, 2000);
    expect(watch.elapsedMilliseconds / 60, lessThan(4), reason: 'per frame, with 20 targets');
  });

  test('saving keeps the settings; glow sprites, glow particles, auto-scroll, flash and vignette', () {
    final pool = BulletPool2DComponent(image: 'a.png', columns: 8, size: 30, team: 'player', grazeRadius: 12, additive: false);
    final copy = BulletPool2DComponent()..fromJson(pool.toJson());
    expect((copy.image, copy.columns, copy.size, copy.team, copy.grazeRadius, copy.additive), ('a.png', 8, 30.0, 'player', 12.0, false));

    final sprite = FlameSpriteComponent(additive: true);
    expect((FlameSpriteComponent()..fromJson(sprite.toJson())).additive, isTrue);
    expect(FlameSpriteComponent().toJson().containsKey('additive'), isFalse, reason: 'old scenes stay the same');
    expect((ParticleEmitter2DComponent()..fromJson(ParticleEmitter2DComponent(glow: true).toJson())).glow, isTrue);

    final layer = ParallaxLayerComponent(scrollX: -40, repeatY: true);
    final layerCopy = ParallaxLayerComponent()..fromJson(layer.toJson());
    expect((layerCopy.scrollX, layerCopy.repeatY), (-40.0, true));
    layer.onUpdate(0.5);
    expect(layer.scrolled.x, -20);

    final cam = Camera2DComponent(vignette: 0.4);
    expect((Camera2DComponent()..fromJson(cam.toJson())).vignette, 0.4);
    cam.flash(const Color(0xFFFFFFFF), 1);
    expect(cam.flashColor.a, 1);
    cam.onUpdate(0.5);
    expect(cam.flashColor.a, closeTo(0.25, 0.01), reason: 'fades out');

    final text = UITextComponent(glow: true, letterSpacing: 4);
    final textCopy = UITextComponent()..fromJson(text.toJson());
    expect((textCopy.glow, textCopy.letterSpacing), (true, 4.0));
    expect((UIButtonComponent()..fromJson(UIButtonComponent(style: 'outline').toJson())).style, 'outline');
    expect((UIImageComponent()..fromJson((UIImageComponent()..smooth = true).toJson())).smooth, isTrue);
  });

  test('a white hit flash brightens the sprite briefly instead of tinting it', () {
    final enemy = target('Enemy', Vector2(300, 100), 'monster')..addComponent(FlameSpriteComponent());
    start(extra: [enemy]);
    final health = enemy.getComponent<HealthComponent>()!..hitFlash = 'white';
    final sprite = enemy.getComponent<FlameSpriteComponent>()!;
    health.damage(1);
    expect(sprite.flash, 1);
    expect(sprite.tint, const Color(0xFFFFFFFF), reason: 'not tinted red');
    steps(12);
    expect(sprite.flash, 0);
    expect((HealthComponent()..fromJson(health.toJson())).hitFlash, 'white');
    expect(HealthComponent().toJson().containsKey('hitFlash'), isFalse, reason: 'old scenes stay the same');
  });

  test('the 2D view draws pools, glowing sprites and particles, scrolling layers and screen effects without errors', () async {
    final pool = start(extra: [
      EmberEntity(name: 'Glow')
        ..addComponent(Transform2DComponent(position: Vector2(100, 100), size: Vector2(40, 40)))
        ..addComponent(FlameSpriteComponent(additive: true, smooth: true)),
      EmberEntity(name: 'Sparks')
        ..addComponent(Transform2DComponent(position: Vector2(200, 200)))
        ..addComponent(ParticleEmitter2DComponent(glow: true)),
      EmberEntity(name: 'Stars')
        ..addComponent(Transform2DComponent(position: Vector2.zero(), size: Vector2(300, 200)))
        ..addComponent(FlameSpriteComponent())
        ..addComponent(ParallaxLayerComponent(factorX: 1, repeatX: true, repeatY: true, scrollX: -50, scrollY: 30)),
    ]);
    pool.ring(480, 270, 30, 50);
    Camera2DComponent.findIn(engine.activeScene)!
      ..vignette = 0.5
      ..flash(const Color(0xFFFFFFFF), 1);
    engine.activeScene.findByName('Sparks')!.getComponent<ParticleEmitter2DComponent>()!.burst(20);
    steps(10);
    final game = EmberFlameGame(engine: engine)..onGameResize(flame.Vector2(960, 540));
    final recorder = PictureRecorder();
    game.render(Canvas(recorder));
    recorder.endRecording();
  });
}

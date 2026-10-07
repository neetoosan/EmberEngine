import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/physics/character_controller2d.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/parallax.dart';
import '../subsystems/two_d/sprite_animator.dart';
import '../subsystems/ui/ui_text.dart';
import 'quest_game.dart' show Quest;

/// "2D Platformer Adventure": one short level to learn from. Run, jump over
/// a pit, collect every coin. Uses Ember Quest's art; the gameplay is the
/// three small Ember Scripts in [platformerStarterScripts].
EmberScene buildPlatformerStarter() {
  const cols = 48, rows = Quest.rows, tile = Quest.tile;
  final tiles = List<int>.filled(cols * rows, 0);
  void set(int c, int r, int id) => tiles[r * cols + c] = id;

  for (var c = 0; c < cols; c++) {
    if (c >= 19 && c <= 21) continue; // the pit
    set(c, 10, Quest.grass);
    set(c, 11, Quest.dirt);
  }
  for (final c in [8, 9, 10]) {
    set(c, 7, Quest.plank); // one-way: jump up through it
  }
  for (final c in [14, 15]) {
    set(c, 9, Quest.stone);
  }
  set(15, 8, Quest.stone);
  for (final c in [26, 27, 28, 29]) {
    set(c, 6, Quest.stone);
  }
  for (final (c, id) in [(4, Quest.bush), (12, Quest.tuft), (24, Quest.flower), (33, Quest.bush), (40, Quest.tuft)]) {
    set(c, 9, id);
  }
  for (var r = 4; r <= 9; r++) {
    set(46, r, Quest.stone); // wall at the end
  }

  final scene = EmberScene(name: 'MainScene');
  const worldW = cols * tile, worldH = rows * tile;
  vm.Vector2 feet(int c, int r) => vm.Vector2(c * tile + tile / 2, (r + 1) * tile);

  scene.addEntity(EmberEntity(name: 'Camera')
    ..addComponent(Transform2DComponent(position: vm.Vector2(320, worldH / 2), size: vm.Vector2.zero()))
    ..addComponent(Camera2DComponent(
      designWidth: 640,
      designHeight: worldH,
      followTarget: 'Hero',
      smoothing: 0.8,
      deadZone: vm.Vector2(40, 400),
      boundsEnabled: true,
      boundsMin: vm.Vector2.zero(),
      boundsMax: vm.Vector2(worldW, worldH),
      backgroundColor: const Color(0xFF6CB4EE),
    )));
  scene.addEntity(EmberEntity(name: 'Clouds')
    ..addComponent(Transform2DComponent(position: vm.Vector2(0, 20), size: vm.Vector2(384, 120), zIndex: -11))
    ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/bg_clouds.png'))
    ..addComponent(ParallaxLayerComponent(factorX: 0.15, factorY: 1.0)));
  scene.addEntity(EmberEntity(name: 'Hills')
    ..addComponent(Transform2DComponent(position: vm.Vector2(0, worldH - 64 - 160), size: vm.Vector2(480, 192), zIndex: -10))
    ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/bg_hills.png'))
    ..addComponent(ParallaxLayerComponent(factorX: 0.35, factorY: 1.0)));

  scene.addEntity(EmberEntity(name: 'Level')
    ..addComponent(Transform2DComponent(size: vm.Vector2.zero()))
    ..addComponent(FlameTileMapComponent(
      columns: cols,
      rows: rows,
      tileSize: tile,
      tiles: tiles,
      tilesetPath: '${Quest.art}/tiles.png',
      tilesetColumns: 8,
      tilesetTileSize: 16,
      tileKinds: Map.of(Quest.tileKinds),
    )));

  scene.addEntity(EmberEntity(name: 'Hero', tags: {'player'})
    ..addComponent(Transform2DComponent(position: feet(2, 9), size: vm.Vector2(32, 32), anchor: EmberAnchor.bottomCenter, zIndex: 5))
    ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/hero.png', columns: 6))
    ..addComponent(SpriteAnimatorComponent(clips: 'idle=0; run=1-3@12; jump=4; dead=5', defaultClip: 'idle'))
    ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(22, 28), offset: vm.Vector2(5, 4), isSolid: false))
    ..addComponent(CharacterController2DComponent(moveSpeed: 200, jumpVelocity: 560, gravity: 1500, groundY: 1e6))
    ..addComponent(ScriptComponent(scriptName: 'player.ember')));

  var n = 0;
  for (final (c, r) in [(6, 9), (8, 6), (9, 6), (10, 6), (15, 7), (20, 7), (27, 5), (28, 5), (36, 9), (37, 9), (38, 9), (43, 9)]) {
    scene.addEntity(EmberEntity(name: 'Coin_${++n}', tags: {'coin'})
      ..addComponent(Transform2DComponent(position: feet(c, r) - vm.Vector2(0, 4), size: vm.Vector2(24, 24), anchor: EmberAnchor.bottomCenter, zIndex: 2))
      ..addComponent(FlameSpriteComponent(assetPath: '${Quest.art}/coin.png', columns: 4))
      ..addComponent(SpriteAnimatorComponent(clips: 'spin=0-3@8', defaultClip: 'spin'))
      ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(18, 20), offset: vm.Vector2(3, 2), isSolid: false, debugDraw: false))
      ..addComponent(ScriptComponent(scriptName: 'coin.ember')));
  }

  scene.addEntity(EmberEntity(name: 'HUD')
    ..addComponent(UITextComponent(text: 'Coins 0', fontSize: 20, anchor: EmberAnchor.topLeft, offset: vm.Vector2(16, 12)))
    ..addComponent(ScriptComponent(scriptName: 'hud.ember')));
  scene.addEntity(EmberEntity(name: 'Message')
    ..addComponent(UITextComponent(text: 'Arrows / A D to run, Space to jump', fontSize: 16, anchor: EmberAnchor.topCenter, offset: vm.Vector2(0, 48))));
  return scene;
}

/// Every file the starter level uses.
const platformerStarterAssets = [
  '${Quest.art}/tiles.png', '${Quest.art}/hero.png', '${Quest.art}/coin.png', '${Quest.art}/bg_hills.png', '${Quest.art}/bg_clouds.png',
];

const platformerStarterScripts = <String, String>{
  'player.ember': r'''
// The hero: run, jump, animate. Needs a Platformer Controller 2D.
var runSpeed = 200;
var fallLimit = 600;      // below this y the hero fell into a pit

void onUpdate(dt) {
  var c = self.controller;
  c.moveSpeed = Input.key("Shift") ? runSpeed * 1.5 : runSpeed;
  var jumpHeld = Input.action("jump") || Input.key("W") || Input.key("Up");
  var jumpPressed = Input.actionPressed("jump") || Input.pressed("W") || Input.pressed("Up");
  if (jumpPressed && c.canJump) playSound("jump", volume: 0.5);
  c.move(Input.axis("horizontal"), jumpHeld, jumpPressed);

  if (!c.grounded) {
    self.animator.play("jump");
  } else if (c.velocity.x.abs() > 20) {
    self.animator.play("run");
  } else {
    self.animator.play("idle");
  }
  if (c.velocity.x.abs() > 1) self.sprite.flipX = c.velocity.x < 0;

  if (self.y > fallLimit) restart();
}
''',
  'coin.ember': r'''
// A coin: the hero picks it up by touching it.
var points = 1;

void onTriggerEnter(other) {
  if (!other.hasTag("player")) return;
  Game.data["coins"] = (Game.data["coins"] ?? 0) + points;
  playSound("coin", volume: 0.6);
  destroy();
}
''',
  'hud.ember': r'''
// Shows the coin count and cheers when every coin is found.
var _total = 0;
var _done = false;

void onStart() {
  Game.data["coins"] = 0;
  _total = findAll("coin").length;
}

void onUpdate(dt) {
  var got = Game.data["coins"] ?? 0;
  setText(self, "Coins $got / $_total");
  if (!_done && got >= _total) {
    _done = true;
    setText("Message", "You found every coin!");
    playSound("coin", volume: 0.9, pitch: 1.5);
  }
}
''',
};

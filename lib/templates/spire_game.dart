import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/combat/combat.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/physics/character_controller2d.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/camera_room.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/light2d.dart';
import '../subsystems/two_d/parallax.dart';
import '../subsystems/ui/minimap.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';
import 'spire_layout.dart';

/// "Ember Spire": a metroidvania. Nine linked rooms in one big tilemap
/// ([SpireLayout]); the camera keeps to the room you are in (Camera Room 2D)
/// and the minimap fills in as you explore. Double jump, dash and wall jump
/// open new ways; shrines save; the Thornback guards the Ember Heart.
/// Logic: [spireScripts].
class Spire {
  static const String art = 'assets/templates/spire';
  static const String title = 'Title';
  static const String world = 'Spire';

  static const List<String> assetFiles = [
    '$art/tiles.png', '$art/hero.png', '$art/slash.png', '$art/enemies.png', '$art/boss.png', '$art/objects.png', '$art/icons.png',
    '$art/bg_far.png', '$art/bg_mid.png', '$art/panel.png',
    '$art/spire.wav', '$art/slash.wav', '$art/hit.wav', '$art/hurt.wav', '$art/jump.wav', '$art/airjump.wav', '$art/dash.wav',
    '$art/power.wav', '$art/save.wav', '$art/gem.wav', '$art/roar.wav', '$art/slam.wav',
  ];

  static const Color ink = Color(0xFFE0F2FE);
  static const Color teal = Color(0xFF2DD4BF);
  static const Color dim = Color(0xFF99F6E4);
}

const double _t = SpireLayout.tile;

EmberEntity _sprite(String name, vm.Vector2 pos, vm.Vector2 size, String image,
    {int z = 0, int columns = 1, int frame = 0, bool additive = false, bool enabled = true}) {
  return EmberEntity(name: name, enabled: enabled)
    ..addComponent(Transform2DComponent(position: pos, size: size, anchor: EmberAnchor.center, zIndex: z))
    ..addComponent(FlameSpriteComponent(assetPath: '${Spire.art}/$image', smooth: true, additive: additive)
      ..columns = columns
      ..frame = frame);
}

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset,
        {Color color = Spire.ink, bool glow = false, double spacing = 0, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color, outline: true, glow: glow, letterSpacing: spacing));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size,
        {String hotkey = '', Color color = Spire.teal, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UIButtonComponent(text: text, action: action, hotkey: hotkey, anchor: EmberAnchor.center, offset: offset, size: size, color: color, style: 'outline', fontSize: 15));

EmberEntity _emitter(String name, Color start, Color end, {double size = 4, double speed = 120, double gravity = 0, double life = 0.5}) =>
    EmberEntity(name: name)
      ..addComponent(Transform2DComponent(position: vm.Vector2(-5000, -5000), size: vm.Vector2.zero(), zIndex: 9))
      ..addComponent(ParticleEmitter2DComponent(
        spawnRate: 0, // bursts only
        maxParticles: 300,
        particleLifetime: life,
        startColor: start,
        endColor: end,
        startSize: size,
        endSize: 0.5,
        speed: speed,
        gravity: gravity,
        glow: true,
      ));

/// Centre of map cell ([col], [row]).
vm.Vector2 _cell(int col, int row) => vm.Vector2(col * _t + _t / 2, row * _t + _t / 2);

void _addBackdrop(EmberScene scene, {bool follow = true}) {
  scene.addEntity(EmberEntity(name: 'Camera')
    ..addComponent(Transform2DComponent(position: vm.Vector2(480, 272), size: vm.Vector2.zero()))
    ..addComponent(Camera2DComponent(
      designWidth: 960,
      designHeight: 544,
      followTarget: follow ? 'Hero' : '',
      smoothing: 0.88,
      boundsEnabled: true,
      boundsMin: vm.Vector2.zero(),
      boundsMax: vm.Vector2(SpireLayout.columns * _t, SpireLayout.rows * _t),
      backgroundColor: const Color(0xFF0B1022),
      vignette: 0.3,
      darkness: 0.3,
      darknessColor: const Color(0xFF060814),
    )));
  for (final (name, image, factor, z) in [('Far Cavern', 'bg_far.png', 0.12, -30), ('Near Cavern', 'bg_mid.png', 0.4, -28)]) {
    scene.addEntity(EmberEntity(name: name)
      ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2(960, 544), zIndex: z))
      ..addComponent(FlameSpriteComponent(assetPath: '${Spire.art}/$image', smooth: true))
      ..addComponent(ParallaxLayerComponent(factorX: factor, factorY: factor, repeatX: true, repeatY: true)));
  }
}

EmberEntity _map() => EmberEntity(name: 'World')
  ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2(SpireLayout.columns * _t, SpireLayout.rows * _t), zIndex: -10))
  ..addComponent(FlameTileMapComponent(
    columns: SpireLayout.columns,
    rows: SpireLayout.rows,
    tileSize: _t,
    tiles: SpireLayout.tiles(),
    tilesetPath: '${Spire.art}/tiles.png',
    tilesetColumns: 8,
    tilesetTileSize: 64,
    tileKinds: {6: TileKind.oneWay, 7: TileKind.hazard},
    smooth: true,
  ));

CharacterController2DComponent _walker(double speed) => CharacterController2DComponent(moveSpeed: speed, jumpVelocity: 640, gravity: 1600, groundY: 1e6);

EmberEntity _pickup(String name, String kind, int frame, vm.Vector2 at, {double size = 36, Color light = const Color(0xFF67E8F9), bool enabled = true}) =>
    _sprite(name, at, vm.Vector2(size, size), 'objects.png', columns: 7, frame: frame, z: 3, enabled: enabled)
      ..tags.add(kind == 'gem' ? 'gem' : 'item')
      ..addComponent(Light2DComponent(radius: 90, color: light, intensity: 0.7, flicker: 0.2))
      ..addComponent(ScriptComponent(scriptName: 'spire_pickup.ember', vars: {'kind': kind}));

/// The whole spire: map, rooms, everything placed in them, hero, HUD.
EmberScene buildSpireWorld() {
  final scene = EmberScene(name: Spire.world);
  _addBackdrop(scene);
  scene.addEntity(_map()..addComponent(ScriptComponent(scriptName: 'spire_game.ember')));

  for (final MapEntry(key: (rc, rr), value: (name, _)) in SpireLayout.rooms.entries) {
    scene.addEntity(EmberEntity(name: name)
      ..addComponent(Transform2DComponent(
          position: vm.Vector2(rc * SpireLayout.roomColumns * _t, rr * SpireLayout.roomRows * _t),
          size: vm.Vector2(SpireLayout.roomColumns * _t, SpireLayout.roomRows * _t)))
      ..addComponent(CameraRoom2DComponent()));
  }

  vm.Vector2 start = _cell(3, 30);
  for (final (ch, c, r) in SpireLayout.things()) {
    final at = _cell(c, r);
    switch (ch) {
      case 'P':
        start = at;
      case 'S':
        scene.addEntity(_sprite('Shrine $c,$r', at - vm.Vector2(0, 8), vm.Vector2(48, 48), 'objects.png', columns: 7, frame: 0, z: 2)
          ..tags.add('save')
          ..addComponent(Light2DComponent(radius: 140, color: Spire.teal, intensity: 0.9, flicker: 0.15))
          ..addComponent(ScriptComponent(scriptName: 'spire_shrine.ember')));
      case 'D':
        scene.addEntity(_pickup('Double Jump Orb', 'double', 1, at, size: 40));
      case 'H':
        scene.addEntity(_pickup('Dash Orb', 'dash', 2, at, size: 40, light: const Color(0xFFF97316)));
      case 'W':
        scene.addEntity(_pickup('Wall Jump Orb', 'wall', 3, at, size: 40, light: const Color(0xFF4ADE80)));
      case 'h':
        scene.addEntity(_pickup('Heart $c,$r', 'heart', 4, at, size: 34, light: const Color(0xFFF43F5E)));
      case 'g':
        scene.addEntity(_pickup('Gem $c,$r', 'gem', 5, at, size: 26, light: const Color(0xFFA855F7)));
      case 'E':
        scene.addEntity(_pickup('Ember Heart', 'goal', 6, at, size: 48, light: const Color(0xFFF97316), enabled: false));
      case 'c':
        scene.addEntity(_sprite('Crawler', at, vm.Vector2(34, 26), 'enemies.png', columns: 2, frame: 0, z: 4)
          ..tags.add('enemy')
          ..addComponent(_walker(50))
          ..addComponent(HealthComponent(maxHealth: 3, team: 'monster', invulnerableTime: 0.15, hitFlash: 'white', showBar: true))
          ..addComponent(ScriptComponent(scriptName: 'spire_crawler.ember')));
      case 'f':
        scene.addEntity(_sprite('Moth', at, vm.Vector2(34, 34), 'enemies.png', columns: 2, frame: 1, z: 4)
          ..tags.add('enemy')
          ..addComponent(HealthComponent(maxHealth: 2, team: 'monster', invulnerableTime: 0.15, hitFlash: 'white', showBar: true))
          ..addComponent(Light2DComponent(radius: 60, color: const Color(0xFF67E8F9), intensity: 0.5))
          ..addComponent(ScriptComponent(scriptName: 'spire_flyer.ember')));
      case 'B':
        scene.addEntity(_sprite('Thornback', at - vm.Vector2(0, 20), vm.Vector2(96, 80), 'boss.png', z: 4)
          ..tags.add('enemy')
          ..addComponent(_walker(70))
          ..addComponent(HealthComponent(maxHealth: 16, team: 'monster', invulnerableTime: 0.25, hitFlash: 'white'))
          ..addComponent(ScriptComponent(scriptName: 'spire_boss.ember')));
    }
  }

  // The hero: a small body for collisions, the picture as a child
  scene.addEntity(EmberEntity(name: 'Hero')
    ..tags.add('player')
    ..addComponent(Transform2DComponent(position: start, size: vm.Vector2(20, 36), anchor: EmberAnchor.center, zIndex: 5))
    ..addComponent(CharacterController2DComponent(moveSpeed: 230, jumpVelocity: 640, gravity: 1600, groundY: 1e6))
    ..addComponent(HealthComponent(maxHealth: 4, team: 'player', invulnerableTime: 1.0, destroyOnDeath: false, hitFlash: 'none'))
    ..addComponent(Light2DComponent(radius: 230, color: const Color(0xFFFFE4B5), intensity: 0.9, flicker: 0.1))
    ..addComponent(ScriptComponent(scriptName: 'spire_hero.ember'))
    ..addChild(_sprite('Body', vm.Vector2(0, -6), vm.Vector2(54, 54), 'hero.png', columns: 4, z: 5)));

  scene
    ..addEntity(_sprite('Slash', vm.Vector2(-900, -900), vm.Vector2(64, 48), 'slash.png', z: 8, additive: true, enabled: false))
    ..addEntity(_sprite('Quake', vm.Vector2(-900, -900), vm.Vector2(40, 30), 'slash.png', z: 8, additive: true, enabled: false)
      ..addComponent(ScriptComponent(scriptName: 'spire_quake.ember')))
    ..addEntity(_emitter('Spark FX', const Color(0xFFFFFFFF), const Color(0x0067E8F9), size: 3.5, speed: 160))
    ..addEntity(_emitter('Pop FX', const Color(0xFFF0ABFC), const Color(0x00A855F7), size: 5, speed: 130))
    ..addEntity(_emitter('Dust FX', const Color(0xFFE2E8F0), const Color(0x0094A3B8), size: 5, speed: 60, gravity: 40))
    ..addEntity(_emitter('Dash FX', const Color(0xFFFED7AA), const Color(0x00F97316), size: 5, speed: 40, life: 0.35));

  // HUD
  scene
    ..addEntity(EmberEntity(name: 'Hearts')
      ..addComponent(UIImageComponent(assetPath: '${Spire.art}/icons.png', columns: 3, frame: 0, emptyFrame: 1, count: 4, filled: 4, spacing: 2,
          anchor: EmberAnchor.topLeft, offset: vm.Vector2(14, 12), size: vm.Vector2(28, 28))
        ..smooth = true))
    ..addEntity(EmberEntity(name: 'GemIcon')
      ..addComponent(UIImageComponent(assetPath: '${Spire.art}/icons.png', columns: 3, frame: 2, anchor: EmberAnchor.topLeft, offset: vm.Vector2(14, 46), size: vm.Vector2(22, 22))
        ..smooth = true))
    ..addEntity(_text('GemText', '0 / 3', 16, EmberAnchor.topLeft, vm.Vector2(42, 47), color: const Color(0xFFE9D5FF)))
    ..addEntity(EmberEntity(name: 'Minimap')
      ..addComponent(UIMinimapComponent(tilemap: 'World', target: 'Hero', markers: 'save:#2DD4BF, item:#FBBF24, gem:#C084FC',
          anchor: EmberAnchor.topRight, offset: vm.Vector2(-14, 12), size: vm.Vector2(190, 112))))
    ..addEntity(_text('RoomText', '', 22, EmberAnchor.bottomCenter, vm.Vector2(0, -40), glow: true, spacing: 4))
    ..addEntity(_text('Prompt', '', 14, EmberAnchor.bottomCenter, vm.Vector2(0, -16), color: Spire.dim))
    ..addEntity(_text('Banner', '', 34, EmberAnchor.topCenter, vm.Vector2(0, 80), color: const Color(0xFFCCFBF1), glow: true, spacing: 5))
    ..addEntity(_text('Subtitle', '', 15, EmberAnchor.topCenter, vm.Vector2(0, 124), color: Spire.dim))
    ..addEntity(_text('BossName', 'THE THORNBACK', 12, EmberAnchor.bottomCenter, vm.Vector2(0, -80), color: const Color(0xFFF0ABFC), spacing: 3, enabled: false))
    ..addEntity(EmberEntity(name: 'BossBar', enabled: false)
      ..addComponent(UIBarComponent(value: 1, max: 1, fillColor: const Color(0xFFC084FC), backColor: const Color(0x99101830),
          anchor: EmberAnchor.bottomCenter, offset: vm.Vector2(0, -66), size: vm.Vector2(380, 8))));

  // Results
  scene
    ..addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Spire.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(460, 270))
        ..smooth = true))
    ..addEntity(_text('ResultsTitle', '', 30, EmberAnchor.center, vm.Vector2(0, -80), color: const Color(0xFFFED7AA), glow: true, spacing: 4, enabled: false))
    ..addEntity(_text('ResultsLine', '', 20, EmberAnchor.center, vm.Vector2(0, -26), enabled: false))
    ..addEntity(_text('ResultsStats', '', 14, EmberAnchor.center, vm.Vector2(0, 10), color: Spire.dim, enabled: false))
    ..addEntity(_button('MenuButton', 'MENU', 'menu', vm.Vector2(0, 80), vm.Vector2(160, 40), hotkey: 'Enter', enabled: false));
  return scene;
}

EmberScene buildSpireTitle() {
  final scene = EmberScene(name: Spire.title);
  _addBackdrop(scene, follow: false);
  // The start room as a backdrop
  scene.addEntity(_map());
  // Look at Cinder Hollow, the first room
  scene.findByName('Camera')!.getComponent<Transform2DComponent>()!.position = vm.Vector2(480, SpireLayout.roomRows * _t + 272);
  scene.addEntity(_sprite('Title Hero', vm.Vector2(300, 990), vm.Vector2(80, 80), 'hero.png', columns: 4, z: 5)
    ..addComponent(Light2DComponent(radius: 260, color: const Color(0xFFFFE4B5))));
  scene.addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'spire_title.ember')));
  scene
    ..addEntity(_text('Logo', 'EMBER SPIRE', 64, EmberAnchor.center, vm.Vector2(0, -120), color: const Color(0xFFCCFBF1), glow: true, spacing: 12))
    ..addEntity(_text('Tagline', 'Explore the caverns. Find the old powers. Climb to the Ember Heart.', 16, EmberAnchor.center, vm.Vector2(0, -62)))
    ..addEntity(_button('NewButton', 'NEW GAME', 'new', vm.Vector2(-100, 10), vm.Vector2(180, 46), hotkey: 'Enter'))
    ..addEntity(_button('ContinueButton', 'CONTINUE', 'continue', vm.Vector2(100, 10), vm.Vector2(180, 46), color: Spire.dim))
    ..addEntity(_text('BestText', '', 14, EmberAnchor.center, vm.Vector2(0, 62), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('Controls', 'A / D run  ·  Space jump  ·  J attack  ·  Shift dash  ·  W rest at shrines', 13, EmberAnchor.bottomCenter,
        vm.Vector2(0, -18), color: Spire.dim));
  return scene;
}

import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/combat/combat.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/two_d/bullet_pool.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/line2d.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "Ember Isles": an isometric colony builder with a little real-time
/// strategy. The island grows from a seed (noise) on an isometric TileMap;
/// buildings, trees and units are Y-sorted; guards are box-selected and sent
/// with right-click along grid paths. Logic: [islesScripts].
class Isles {
  static const String art = 'assets/templates/isles';
  static const String title = 'Title';
  static const String island = 'Island';
  static const int size = 22;
  static const double tile = 32;

  static const List<String> assetFiles = [
    '$art/tiles.png', '$art/objects.png', '$art/units.png', '$art/icons.png', '$art/ring.png', '$art/cell.png', '$art/arrow.png',
    '$art/panel.png',
    '$art/isles.wav', '$art/build.wav', '$art/horn.wav', '$art/clash.wav', '$art/arrow.wav', '$art/select.wav', '$art/win.wav', '$art/lose.wav',
  ];

  /// Buildings: (name, object frame, health).
  static const List<(String, int, double)> buildings = [
    ('Town Hall', 3, 60), ('House', 4, 20), ('Farm', 5, 15), ('Lumber Camp', 6, 18), ('Quarry', 7, 18), ('Watchtower', 8, 40), ('Ember Beacon', 9, 80),
  ];

  static const Color ink = Color(0xFFFFFBEB);
  static const Color gold = Color(0xFFFBBF24);
}

EmberEntity _object(String name, int frame, {bool enabled = false, int z = 5}) => EmberEntity(name: name, enabled: enabled)
  ..addComponent(Transform2DComponent(position: vm.Vector2(-900, -900), size: vm.Vector2(64, 80), anchor: EmberAnchor.bottomCenter, zIndex: z)..ySort = true)
  ..addComponent(FlameSpriteComponent(assetPath: '${Isles.art}/objects.png', smooth: true)
    ..columns = 6
    ..rows = 2
    ..frame = frame);

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset,
        {Color color = Isles.ink, bool glow = false, double spacing = 0, bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color, outline: true, glow: glow, letterSpacing: spacing));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, vm.Vector2 size,
    {EmberAnchor anchor = EmberAnchor.center, String hotkey = '', Color color = Isles.gold, bool enabled = true, int? icon}) {
  final b = UIButtonComponent(text: text, action: action, hotkey: hotkey, anchor: anchor, offset: offset, size: size, color: color, style: 'outline', fontSize: 12);
  if (icon != null) {
    b
      ..icon = '${Isles.art}/objects.png'
      ..iconColumns = 6
      ..iconRows = 2
      ..iconFrame = icon;
  }
  return EmberEntity(name: name, enabled: enabled)..addComponent(b);
}

EmberEntity _icon(String name, int frame, vm.Vector2 offset) => EmberEntity(name: name)
  ..addComponent(UIImageComponent(assetPath: '${Isles.art}/icons.png', columns: 6, frame: frame, anchor: EmberAnchor.topLeft, offset: offset, size: vm.Vector2(24, 24))
    ..smooth = true);

EmberEntity _emitter(String name, Color start, Color end, {double size = 5, double speed = 70}) => EmberEntity(name: name)
  ..addComponent(Transform2DComponent(position: vm.Vector2(-5000, -5000), size: vm.Vector2.zero(), zIndex: 50))
  ..addComponent(ParticleEmitter2DComponent(
    spawnRate: 0, // bursts only
    maxParticles: 300,
    particleLifetime: 0.6,
    startColor: start,
    endColor: end,
    startSize: size,
    endSize: 0.5,
    speed: speed,
    gravity: -20,
    glow: true,
  ));

EmberEntity _map() {
  final map = FlameTileMapComponent(
    columns: Isles.size,
    rows: Isles.size,
    tileSize: Isles.tile,
    layout: 'isometric',
    tiles: List.filled(Isles.size * Isles.size, 1),
    tilesetPath: '${Isles.art}/tiles.png',
    tilesetColumns: 8,
    tilesetTileSize: 128,
    tileKinds: {for (final id in [3, 4, 5, 6]) id: TileKind.decoration},
    smooth: true,
  )..tilesetRows = 1;
  return EmberEntity(name: 'Map')
    ..addComponent(Transform2DComponent(position: vm.Vector2(0, 30), size: vm.Vector2(map.extent.width, map.extent.height), zIndex: -10))
    ..addComponent(map);
}

EmberEntity _camera(vm.Vector2 at) => EmberEntity(name: 'Camera')
  ..addComponent(Transform2DComponent(position: at, size: vm.Vector2.zero()))
  ..addComponent(Camera2DComponent(designWidth: 960, designHeight: 540, backgroundColor: const Color(0xFF1E5FA8), vignette: 0.25));

EmberEntity _unit(String name, String team, int frame) => EmberEntity(name: name, enabled: false)
  ..tags.add(team)
  ..addComponent(Transform2DComponent(position: vm.Vector2(-900, -900), size: vm.Vector2(30, 30), anchor: EmberAnchor.bottomCenter, zIndex: 5)..ySort = true)
  ..addComponent(FlameSpriteComponent(assetPath: '${Isles.art}/units.png', smooth: true)
    ..columns = 4
    ..frame = frame)
  ..addComponent(HealthComponent(maxHealth: team == 'guard' ? 6 : 4, team: team == 'guard' ? 'player' : 'monster', invulnerableTime: 0.1, hitFlash: 'white', showBar: true))
  ..addComponent(ScriptComponent(scriptName: 'isles_unit.ember', vars: {'team': team, 'speed': team == 'guard' ? 60.0 : 45.0}))
  ..addChild(EmberEntity(name: 'Ring', enabled: false)
    ..addComponent(Transform2DComponent(position: vm.Vector2(0, -2), size: vm.Vector2(36, 18), anchor: EmberAnchor.center, zIndex: 4))
    ..addComponent(FlameSpriteComponent(assetPath: '${Isles.art}/ring.png', smooth: true, tint: const Color(0xFF7DD3FC))));

/// The island (generated when it starts), templates for everything placed, HUD.
EmberScene buildIslesIsland() {
  final scene = EmberScene(name: Isles.island);
  scene.addEntity(_camera(vm.Vector2(704, 380)));
  scene.addEntity(_map());

  // Templates the colony script copies
  scene
    ..addEntity(_object('Tree', 0)..tags.add('tree'))
    ..addEntity(_object('Pine', 1)..tags.add('tree'))
    ..addEntity(_object('Rock', 2)..tags.add('rock'))
    ..addEntity(_object('Boat', 10));
  for (final (name, frame, hp) in Isles.buildings) {
    scene.addEntity(_object(name, frame)
      ..tags.add('building')
      ..addComponent(HealthComponent(maxHealth: hp, team: 'player', invulnerableTime: 0.1, hitFlash: 'white', showBar: true))
      ..addComponent(ScriptComponent(scriptName: 'isles_tower.ember')));
  }
  scene
    ..addEntity(_unit('Guard', 'guard', 0))
    ..addEntity(_unit('Raider', 'raider', 1))
    ..addEntity(_object('Ghost', 4, z: 20)..getComponent<FlameSpriteComponent>()!.opacity = 0.8)
    ..addEntity(EmberEntity(name: 'Cell', enabled: false)
      ..addComponent(Transform2DComponent(position: vm.Vector2(-900, -900), size: vm.Vector2(64, 32), anchor: EmberAnchor.center, zIndex: -5))
      ..addComponent(FlameSpriteComponent(assetPath: '${Isles.art}/cell.png', smooth: true)))
    ..addEntity(EmberEntity(name: 'Move Marker', enabled: false)
      ..addComponent(Transform2DComponent(position: vm.Vector2(-900, -900), size: vm.Vector2(48, 24), anchor: EmberAnchor.center, zIndex: -4))
      ..addComponent(FlameSpriteComponent(assetPath: '${Isles.art}/ring.png', smooth: true, tint: const Color(0xFF86EFAC))))
    ..addEntity(EmberEntity(name: 'Selection Box', enabled: false)
      ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero(), zIndex: 60))
      ..addComponent(Line2DComponent(color: const Color(0xFFE0F2FE), width: 2, glow: true)))
    ..addEntity(EmberEntity(name: 'Arrows')
      ..addComponent(Transform2DComponent(position: vm.Vector2.zero(), size: vm.Vector2.zero(), zIndex: 40))
      ..addComponent(BulletPool2DComponent(image: '${Isles.art}/arrow.png', size: 22, team: 'player', additive: false, margin: 40, maxBullets: 200)))
    ..addEntity(_emitter('Dust FX', const Color(0xFFF5E6C8), const Color(0x00B08A55), size: 6))
    ..addEntity(_emitter('Spark FX', const Color(0xFFFFFFFF), const Color(0x00FBBF24), size: 3, speed: 110));

  scene.addEntity(EmberEntity(name: 'Colony')..addComponent(ScriptComponent(scriptName: 'isles_colony.ember')));

  // HUD: resources along the top
  final top = [('WoodIcon', 0, 'WoodText'), ('StoneIcon', 1, 'StoneText'), ('FoodIcon', 2, 'FoodText'), ('PeopleIcon', 3, 'PeopleText'), ('GuardIcon', 4, 'GuardText')];
  for (var i = 0; i < top.length; i++) {
    final (icon, frame, text) = top[i];
    scene
      ..addEntity(_icon(icon, frame, vm.Vector2(14.0 + i * 104, 12)))
      ..addEntity(_text(text, '0', 17, EmberAnchor.topLeft, vm.Vector2(44.0 + i * 104, 13)));
  }
  scene
    ..addEntity(_text('RaidText', '', 16, EmberAnchor.topRight, vm.Vector2(-16, 14), color: const Color(0xFFFCA5A5)))
    ..addEntity(_text('Banner', '', 34, EmberAnchor.topCenter, vm.Vector2(0, 70), color: const Color(0xFFFDE68A), glow: true, spacing: 4))
    ..addEntity(_text('Subtitle', '', 15, EmberAnchor.topCenter, vm.Vector2(0, 114)))
    ..addEntity(_text('Help', '', 13, EmberAnchor.bottomCenter, vm.Vector2(0, -66), color: const Color(0xFFE0F2FE)));

  // Build bar
  final bar = [
    ('House', 'House', '20w'), ('Farm', 'Farm', '25w'), ('Lumber Camp', 'Lumber', '20w'), ('Quarry', 'Quarry', '30w'),
    ('Watchtower', 'Tower', '40w 25s'), ('Ember Beacon', 'Beacon', '150w 120s 80f'),
  ];
  for (var i = 0; i < bar.length; i++) {
    final (name, label, cost) = bar[i];
    final frame = Isles.buildings.firstWhere((b) => b.$1 == name).$2;
    scene.addEntity(_button('$name Button', '$label\n$cost', 'build:$name', vm.Vector2(10.0 + i * 128, -10), vm.Vector2(122, 46),
        anchor: EmberAnchor.bottomLeft, icon: frame));
  }
  scene.addEntity(_button('GuardButton', 'Guard\n15f 10w', 'guard', vm.Vector2(-10, -10), vm.Vector2(150, 46), anchor: EmberAnchor.bottomRight,
      hotkey: 'G', color: const Color(0xFF7DD3FC)));

  // Results
  scene
    ..addEntity(EmberEntity(name: 'ResultsPanel', enabled: false)
      ..addComponent(UIImageComponent(assetPath: '${Isles.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(480, 240))
        ..smooth = true))
    ..addEntity(_text('ResultsTitle', '', 28, EmberAnchor.center, vm.Vector2(0, -60), color: const Color(0xFFFDE68A), glow: true, spacing: 3, enabled: false))
    ..addEntity(_text('ResultsLine', '', 15, EmberAnchor.center, vm.Vector2(0, -10), enabled: false))
    ..addEntity(_button('RetryButton', 'NEW ISLAND', 'retry', vm.Vector2(-80, 62), vm.Vector2(140, 40), hotkey: 'Enter', enabled: false))
    ..addEntity(_button('MenuButton', 'MENU', 'menu', vm.Vector2(80, 62), vm.Vector2(140, 40), enabled: false, color: const Color(0xFFD9F99D)));
  return scene;
}

EmberScene buildIslesTitle() {
  final scene = EmberScene(name: Isles.title);
  scene.addEntity(_camera(vm.Vector2(480, 270)));
  // A small island scene drawn from the same art
  final m = FlameTileMapComponent(
    columns: 10,
    rows: 10,
    tileSize: Isles.tile,
    layout: 'isometric',
    tiles: [
      for (var r = 0; r < 10; r++)
        for (var c = 0; c < 10; c++) ((c - 4.5).abs() + (r - 4.5).abs() > 6.5 ? 1 : ((c - 4.5).abs() + (r - 4.5).abs() > 5 ? 3 : 4)),
    ],
    tilesetPath: '${Isles.art}/tiles.png',
    tilesetColumns: 8,
    tilesetTileSize: 128,
    smooth: true,
  )..tilesetRows = 1;
  scene.addEntity(EmberEntity(name: 'Map')
    ..addComponent(Transform2DComponent(position: vm.Vector2(160, 150), size: vm.Vector2(m.extent.width, m.extent.height), zIndex: -10))
    ..addComponent(m));
  for (final (c, r, frame) in [(5, 5, 3), (4, 6, 4), (6, 4, 4), (3, 3, 0), (7, 7, 1), (6, 7, 5), (2, 6, 8), (7, 3, 2)]) {
    final centre = m.isoCenter(c, r, Isles.tile);
    scene.addEntity(_object('Decor', frame, enabled: true)..getComponent<Transform2DComponent>()!.position = vm.Vector2(160 + centre.dx, 150 + centre.dy + 16));
  }
  scene.addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'isles_title.ember')));
  scene
    ..addEntity(_text('Logo', 'EMBER ISLES', 60, EmberAnchor.topCenter, vm.Vector2(0, 36), color: const Color(0xFFFFF7ED), glow: true, spacing: 10))
    ..addEntity(_text('Tagline', 'Settle an island. Grow a colony. Hold off the raiders. Light the Ember Beacon.', 15, EmberAnchor.topCenter, vm.Vector2(0, 110)))
    ..addEntity(_button('NewButton', 'NEW ISLAND', 'new', vm.Vector2(-100, -70), vm.Vector2(180, 46), anchor: EmberAnchor.bottomCenter, hotkey: 'Enter'))
    ..addEntity(_button('ClassicButton', 'ISLAND 1717', 'classic', vm.Vector2(100, -70), vm.Vector2(180, 46), anchor: EmberAnchor.bottomCenter,
        color: const Color(0xFFD9F99D)))
    ..addEntity(_text('BestText', '', 14, EmberAnchor.bottomCenter, vm.Vector2(0, -40), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('Controls', 'Click a building, then the island  ·  drag to select guards  ·  right-click sends them  ·  WASD moves the view', 12,
        EmberAnchor.bottomCenter, vm.Vector2(0, -16), color: const Color(0xFFE0F2FE)));
  return scene;
}

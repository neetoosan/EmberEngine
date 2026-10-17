import 'dart:math' as math;
import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart' show EmberAnchor;
import '../core/transform3d.dart';
import '../subsystems/ai/enemy_ai3d.dart';
import '../subsystems/combat/combat.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/physics/character_controller3d.dart';
import '../subsystems/three_d/camera3d.dart';
import '../subsystems/three_d/components3d.dart';
import '../subsystems/three_d/environment3d.dart';
import '../subsystems/three_d/lighting.dart';
import '../subsystems/three_d/material.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "Ember Arena": a first-person wave shooter in a low-poly foundry. Robots
/// (Drones, Gunners, Brutes) come through four portals; the player has a
/// blaster and a scatter gun. Built from the engine's 3D primitives, Enemy
/// AI 3D and Ember Script ([arenaScripts]).
class Arena {
  static const String art = 'assets/templates/arena';
  static const String music = '$art/arena.wav';
  static const String title = 'Title';
  static const String level = 'Arena';

  /// Half the width of the square arena (metres).
  static const double half = 18;

  static const List<String> assetFiles = ['$art/vignette.png', '$art/panel.png', music];

  // Palette
  static const Color floorA = Color(0xFF2B2F37);
  static const Color floorB = Color(0xFF24272E);
  static const Color wallA = Color(0xFF3D4452);
  static const Color wallB = Color(0xFF353B47);
  static const Color steel = Color(0xFF4B5563);
  static const Color dark = Color(0xFF1F2329);
  static const Color molten = Color(0xFFFF6A1A);
  static const Color portal = Color(0xFFA855F7);
}

// ---------------------------------------------------------------------------
// Building blocks

/// A mesh entity: [scale] sizes the unit primitive (cube 1 m, sphere / cylinder 1 m across).
EmberEntity _part(String name, MeshPrimitiveType type, vm.Vector3 pos, vm.Vector3 scale, Color color,
    {double emission = 0, double roughness = 0.75, double metallic = 0.2, vm.Vector3? euler, bool solid = false, double bias = 0, int segments = 16}) {
  final e = EmberEntity(name: name)
    ..addComponent(Transform3DComponent(position: pos, scale: scale, euler: euler))
    ..addComponent(MeshRenderer3DComponent(
      primitiveType: type,
      material: Material3D(color: color, emission: emission, roughness: roughness, metallic: metallic),
      segments: segments,
    )..depthBias = bias);
  if (solid) e.addComponent(Collider3DComponent());
  return e;
}

EmberEntity _box(String name, vm.Vector3 pos, vm.Vector3 size, Color color, {double emission = 0, bool solid = true, double metallic = 0.3, double bias = 0}) =>
    _part(name, MeshPrimitiveType.cube, pos, size, color, emission: emission, solid: solid, metallic: metallic, bias: bias);

/// A flat plane of [w] x [d] metres (the unit plane is 10 m); always drawn under objects.
EmberEntity _plane(String name, vm.Vector3 pos, double w, double d, Color color, {double emission = 0}) =>
    _part(name, MeshPrimitiveType.plane, pos, vm.Vector3(w / 10, 1, d / 10), color, emission: emission, roughness: 0.9, metallic: 0.1);

/// An invisible solid box (for shapes drawn with planes).
EmberEntity _blocker(String name, vm.Vector3 pos, vm.Vector3 size) =>
    EmberEntity(name: name)
      ..addComponent(Transform3DComponent(position: pos))
      ..addComponent(Collider3DComponent(size: size));

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset, {Color color = const Color(0xFFFFFFFF)}) =>
    EmberEntity(name: name)..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color));

EmberEntity _fx(String name, Color start, Color end, {double size = 0.12, double speed = 3, double life = 0.6, double gravity = -6}) =>
    EmberEntity(name: name)
      ..addComponent(Transform3DComponent(position: vm.Vector3(0, -20, 0)))
      ..addComponent(ParticleEmitter3DComponent(
        maxParticles: 160,
        spawnRate: 0, // bursts only (scripts call particles.burst(count, where))
        particleLifetime: life,
        startColor: start,
        endColor: end,
        size: size,
        speed: speed,
        gravity: vm.Vector3(0, gravity, 0),
      ));

// ---------------------------------------------------------------------------
// The arena (shared by the title backdrop and the level)

void _buildArena(EmberScene scene) {
  const h = Arena.half;
  scene.addEntity(EmberEntity(name: 'Environment')
    ..addComponent(Environment3DComponent(
      skyTop: const Color(0xFF0B1020),
      horizon: const Color(0xFF6B2C17),
      ground: const Color(0xFF15171B),
      fogColor: const Color(0xFF2A1C18),
      fogStart: 16,
      fogEnd: 60,
      fogMax: 0.7,
    )));
  scene.addEntity(EmberEntity(name: 'Ambient Light')
    ..addComponent(Transform3DComponent())
    ..addComponent(LightComponent(type: LightType.ambient, color: const Color(0xFF8EA4C8), intensity: 0.32)));
  scene.addEntity(EmberEntity(name: 'Forge Light')
    ..addComponent(Transform3DComponent(position: vm.Vector3(8, 20, 6), euler: vm.Vector3(-55, 30, 0)))
    ..addComponent(LightComponent(type: LightType.directional, color: const Color(0xFFFFD6A8), intensity: 0.95)));
  scene.addEntity(EmberEntity(name: 'Molten Glow')
    ..addComponent(Transform3DComponent(position: vm.Vector3(0, 2.5, 0)))
    ..addComponent(LightComponent(type: LightType.point, color: const Color(0xFFFF7A2E), intensity: 1.2, range: 14)));

  // Floor: a 4 x 4 checker of steel plates
  const tile = h * 2 / 4;
  for (var ix = 0; ix < 4; ix++) {
    for (var iz = 0; iz < 4; iz++) {
      scene.addEntity(_plane('Floor ${ix * 4 + iz + 1}', vm.Vector3(-h + tile * (ix + 0.5), 0, -h + tile * (iz + 0.5)), tile, tile,
          (ix + iz).isEven ? Arena.floorA : Arena.floorB));
    }
  }
  // Molten channels around the central forge
  for (final (x, z, w, d) in [(0.0, -6.2, 12.4, 0.5), (0.0, 6.2, 12.4, 0.5), (-6.2, 0.0, 0.5, 12.4), (6.2, 0.0, 0.5, 12.4)]) {
    scene.addEntity(_plane('Molten Channel', vm.Vector3(x, 0.01, z), w, d, Arena.molten, emission: 0.95));
  }
  // Supply pads in the corners
  for (final (x, z) in [(-9.0, -9.0), (9.0, -9.0), (9.0, 9.0), (-9.0, 9.0)]) {
    scene.addEntity(_plane('Supply Pad', vm.Vector3(x, 0.01, z), 2.2, 2.2, const Color(0xFF14532D), emission: 0.5));
  }

  // Central forge: a raised platform (top drawn as a plane so robots on it stay in front)
  scene.addEntity(_plane('Forge Top', vm.Vector3(0, 1.0, 0), 7, 7, const Color(0xFF3A3F49)));
  scene.addEntity(_blocker('Forge Block', vm.Vector3(0, 0.5, 0), vm.Vector3(7, 1, 7)));
  for (final (x, z, w, d) in [(0.0, -3.45, 7.0, 0.1), (0.0, 3.45, 7.0, 0.1), (-3.45, 0.0, 0.1, 7.0), (3.45, 0.0, 0.1, 7.0)]) {
    scene.addEntity(_box('Forge Side', vm.Vector3(x, 0.5, z), vm.Vector3(w, 1, d), Arena.steel, solid: false));
  }
  // Steps up to the forge on every side
  for (var side = 0; side < 4; side++) {
    final a = side * math.pi / 2;
    for (var s = 0; s < 2; s++) {
      final dist = 3.85 + (1 - s) * 0.7, top = 0.34 * (s + 1); // flush against the platform
      final c = vm.Vector3(math.sin(a) * dist, top / 2, math.cos(a) * dist);
      final size = side.isEven ? vm.Vector3(2.4, top, 0.7) : vm.Vector3(0.7, top, 2.4);
      scene.addEntity(_box('Forge Step', c, size, const Color(0xFF454B57)));
    }
  }
  // The forge's heart
  scene.addEntity(_part('Forge Core', MeshPrimitiveType.cylinder, vm.Vector3(0, 1.55, 0), vm.Vector3(1.6, 1.1, 1.6), Arena.molten,
      emission: 0.85, solid: true));
  scene.addEntity(_part('Forge Cap', MeshPrimitiveType.cylinder, vm.Vector3(0, 2.2, 0), vm.Vector3(2.0, 0.2, 2.0), Arena.dark, metallic: 0.6));

  // Outer walls in 3 m segments, with a molten trim along the top
  const seg = 3.0, wallH = 4.5;
  for (var side = 0; side < 4; side++) {
    for (var i = 0; i < 12; i++) {
      final along = -h + seg * (i + 0.5);
      final isPortal = i == 5 || i == 6; // the middle two segments hold a portal
      final color = i.isEven ? Arena.wallA : Arena.wallB;
      final (x, z) = switch (side) { 0 => (along, -h - 0.5), 1 => (h + 0.5, along), 2 => (along, h + 0.5), _ => (-h - 0.5, along) };
      final size = side.isEven ? vm.Vector3(seg, wallH, 1) : vm.Vector3(1, wallH, seg);
      scene.addEntity(_box(isPortal ? 'Portal Wall' : 'Wall', vm.Vector3(x, wallH / 2, z), size, isPortal ? Arena.dark : color));
    }
    // A molten trim along the top of the whole wall
    final (tx, tz) = switch (side) { 0 => (0.0, -h - 0.5), 1 => (h + 0.5, 0.0), 2 => (0.0, h + 0.5), _ => (-h - 0.5, 0.0) };
    final trim = side.isEven ? vm.Vector3(h * 2, 0.14, 1.06) : vm.Vector3(1.06, 0.14, h * 2);
    scene.addEntity(_box('Wall Trim', vm.Vector3(tx, wallH - 0.25, tz), trim, Arena.molten, emission: 0.8, solid: false, bias: 2));
  }
  // Portals in the middle of each wall: a glowing disc in a heavy frame
  for (var side = 0; side < 4; side++) {
    final a = side * math.pi / 2;
    final dir = vm.Vector3(-math.sin(a), 0, -math.cos(a)); // from the centre toward this wall (0 = north, -Z)
    final c = dir * (h - 0.12);
    final northSouth = side.isEven;
    final across = northSouth ? vm.Vector3(1, 0, 0) : vm.Vector3(0, 0, 1); // along the wall
    // A cylinder's axis is Y: tip it over to face out of the wall
    scene.addEntity(_part('Portal', MeshPrimitiveType.cylinder, c + vm.Vector3(0, 2.0, 0), vm.Vector3(3.2, 0.12, 3.2), Arena.portal,
        emission: 0.9, euler: northSouth ? vm.Vector3(90, 0, 0) : vm.Vector3(0, 0, 90), bias: 3)); // keep it in front of its wall
    for (final s in [-1.0, 1.0]) {
      scene.addEntity(_box('Portal Frame', c + across * (1.95 * s) + vm.Vector3(0, 2.0, 0) - dir * 0.2, vm.Vector3(0.55, 4.0, 0.55), Arena.dark));
    }
    scene.addEntity(_box('Portal Lintel', c + vm.Vector3(0, 3.95, 0) - dir * 0.2, northSouth ? vm.Vector3(4.4, 0.5, 0.55) : vm.Vector3(0.55, 0.5, 4.4),
        Arena.dark, solid: false));
    scene.addEntity(EmberEntity(name: 'Portal Light')
      ..addComponent(Transform3DComponent(position: c * 0.9 + vm.Vector3(0, 2.2, 0)))
      ..addComponent(LightComponent(type: LightType.point, color: Arena.portal, intensity: 1.0, range: 9)));
  }

  // Cover: four pillars and crate stacks
  for (final (x, z) in [(-7.5, -2.5), (7.5, 2.5), (2.5, -7.5), (-2.5, 7.5)]) {
    scene.addEntity(_part('Pillar', MeshPrimitiveType.cylinder, vm.Vector3(x, 2.5, z), vm.Vector3(1.5, 5, 1.5), Arena.steel, metallic: 0.5, segments: 12));
    scene.addEntity(_blocker('Pillar Block', vm.Vector3(x, 2.5, z), vm.Vector3(1.4, 5, 1.4)));
    scene.addEntity(_part('Pillar Ring', MeshPrimitiveType.tube, vm.Vector3(x, 3.2, z), vm.Vector3(1.62, 0.16, 1.62), Arena.molten, emission: 0.8, bias: 0.3, segments: 12));
  }
  for (final (x, z, stack) in [(-12.0, -4.0, 2), (12.0, 4.0, 2), (4.0, -12.0, 1), (-4.0, 12.0, 1), (-12.5, 9.5, 1), (12.5, -9.5, 1)]) {
    for (var k = 0; k < stack; k++) {
      scene.addEntity(_box('Crate', vm.Vector3(x + k * 0.15, 0.7 + k * 1.4, z - k * 0.1), vm.Vector3(1.4, 1.4, 1.4),
          k.isEven ? const Color(0xFF5B6472) : const Color(0xFF515A67)));
    }
  }
}

// ---------------------------------------------------------------------------
// Robots (disabled templates that the arena script spawns copies of)

EmberEntity _robotRoot(String name, double height, double radius, vm.Vector3 collider, double hp, EnemyAI3DComponent ai, int points) =>
    EmberEntity(name: name, tags: {'enemy'})
      ..enabled = false
      ..addComponent(Transform3DComponent(position: vm.Vector3(0, -30, 0)))
      ..addComponent(Collider3DComponent(size: collider))
      ..addComponent(CharacterController3DComponent(walkSpeed: ai.moveSpeed, height: height, radius: radius))
      ..addComponent(HealthComponent(maxHealth: hp, team: 'monster', invulnerableTime: 0.05))
      ..addComponent(ai)
      ..addComponent(ScriptComponent(scriptName: 'arena_robot.ember', vars: {'points': points}));

EmberEntity _drone() {
  final d = _robotRoot('Drone', 0.8, 0.4, vm.Vector3(0.9, 0.9, 0.9), 2,
      EnemyAI3DComponent(moveSpeed: 7, turnSpeed: 420, attackRange: 1.4, attackDamage: 16, selfDestruct: true, explosionRadius: 2.6, hoverHeight: 1.6,
          impact: 'Explosion FX'),
      50);
  d
    ..addChild(_part('Body', MeshPrimitiveType.sphere, vm.Vector3.zero(), vm.Vector3.all(0.8), const Color(0xFF334155), metallic: 0.6, roughness: 0.4,
        segments: 10))
    ..addChild(_part('Eye', MeshPrimitiveType.sphere, vm.Vector3(0, 0.05, -0.34), vm.Vector3.all(0.26), const Color(0xFFFF3B3B), emission: 0.95,
        segments: 6))
    ..addChild(_part('Fin L', MeshPrimitiveType.cube, vm.Vector3(-0.5, 0, 0.05), vm.Vector3(0.35, 0.06, 0.45), Arena.molten, emission: 0.5))
    ..addChild(_part('Fin R', MeshPrimitiveType.cube, vm.Vector3(0.5, 0, 0.05), vm.Vector3(0.35, 0.06, 0.45), Arena.molten, emission: 0.5))
    ..addChild(_part('Spike', MeshPrimitiveType.pyramid, vm.Vector3(0, -0.5, 0), vm.Vector3(0.3, 0.35, 0.3), Arena.dark, euler: vm.Vector3(180, 0, 0)));
  return d;
}

EmberEntity _gunner() {
  final g = _robotRoot('Gunner', 1.9, 0.45, vm.Vector3(0.9, 1.9, 0.8), 4,
      EnemyAI3DComponent(behavior: EnemyBehavior3D.shooter, moveSpeed: 3.6, preferredDistance: 11, fireRange: 32, fireCooldown: 1.8, shotSpeed: 13,
          shotDamage: 8, shotColor: const Color(0xFFFFA726), aimHeight: 0.2, impact: 'Spark FX'),
      100);
  const body = Color(0xFF3B6E9E);
  g
    ..addChild(_part('Leg L', MeshPrimitiveType.cube, vm.Vector3(-0.2, -0.55, 0), vm.Vector3(0.22, 0.8, 0.26), Arena.dark))
    ..addChild(_part('Leg R', MeshPrimitiveType.cube, vm.Vector3(0.2, -0.55, 0), vm.Vector3(0.22, 0.8, 0.26), Arena.dark))
    ..addChild(_part('Torso', MeshPrimitiveType.cube, vm.Vector3(0, 0.15, 0), vm.Vector3(0.78, 0.7, 0.5), body, metallic: 0.4))
    ..addChild(_part('Head', MeshPrimitiveType.cube, vm.Vector3(0, 0.68, 0), vm.Vector3(0.46, 0.34, 0.42), const Color(0xFF2F5A82)))
    ..addChild(_part('Eye', MeshPrimitiveType.cube, vm.Vector3(0, 0.7, -0.22), vm.Vector3(0.38, 0.09, 0.04), const Color(0xFF22D3EE), emission: 1))
    ..addChild(_part('Gun Arm', MeshPrimitiveType.cube, vm.Vector3(0.48, 0.2, -0.22), vm.Vector3(0.16, 0.16, 0.75), Arena.dark))
    ..addChild(_part('Muzzle', MeshPrimitiveType.sphere, vm.Vector3(0.48, 0.2, -0.62), vm.Vector3.all(0.14), const Color(0xFFFFA726), emission: 1,
        segments: 6));
  return g;
}

EmberEntity _brute() {
  final b = _robotRoot('Brute', 2.4, 0.75, vm.Vector3(1.5, 2.4, 1.3), 14,
      EnemyAI3DComponent(behavior: EnemyBehavior3D.charger, moveSpeed: 2.8, turnSpeed: 200, attackRange: 1.9, attackDamage: 26, attackCooldown: 1.4,
          chargeSpeed: 16, chargeRange: 14, windup: 0.85, dizzyTime: 1.6, impact: 'Spark FX'),
      300);
  const body = Color(0xFF9A3B1F);
  b
    ..addChild(_part('Leg L', MeshPrimitiveType.cube, vm.Vector3(-0.38, -0.72, 0), vm.Vector3(0.45, 0.95, 0.5), Arena.dark))
    ..addChild(_part('Leg R', MeshPrimitiveType.cube, vm.Vector3(0.38, -0.72, 0), vm.Vector3(0.45, 0.95, 0.5), Arena.dark))
    ..addChild(_part('Torso', MeshPrimitiveType.cube, vm.Vector3(0, 0.25, 0), vm.Vector3(1.4, 1.0, 0.9), body, metallic: 0.4))
    ..addChild(_part('Shoulder L', MeshPrimitiveType.cube, vm.Vector3(-0.86, 0.58, 0), vm.Vector3(0.5, 0.5, 0.62), const Color(0xFF7C2D12)))
    ..addChild(_part('Shoulder R', MeshPrimitiveType.cube, vm.Vector3(0.86, 0.58, 0), vm.Vector3(0.5, 0.5, 0.62), const Color(0xFF7C2D12)))
    ..addChild(_part('Fist L', MeshPrimitiveType.cube, vm.Vector3(-0.86, -0.18, -0.2), vm.Vector3(0.42, 0.46, 0.46), Arena.dark))
    ..addChild(_part('Fist R', MeshPrimitiveType.cube, vm.Vector3(0.86, -0.18, -0.2), vm.Vector3(0.42, 0.46, 0.46), Arena.dark))
    ..addChild(_part('Head', MeshPrimitiveType.cube, vm.Vector3(0, 0.95, -0.05), vm.Vector3(0.62, 0.44, 0.56), const Color(0xFF7C2D12)))
    ..addChild(_part('Eye', MeshPrimitiveType.cube, vm.Vector3(0, 0.97, -0.34), vm.Vector3(0.42, 0.1, 0.04), const Color(0xFFFFB020), emission: 1));
  return b;
}

/// Health pack (red cross) or ammo crate (blue shells); spawned by the arena script.
EmberEntity _pickupTemplate(String name, String kind, int amount, Color color) {
  final p = EmberEntity(name: name, tags: {'pickup'})
    ..enabled = false
    ..addComponent(Transform3DComponent(position: vm.Vector3(0, -30, 0)))
    ..addComponent(Collider3DComponent(size: vm.Vector3(1, 1, 1), isTrigger: true))
    ..addComponent(ScriptComponent(scriptName: 'arena_pickup.ember', vars: {'kind': kind, 'amount': amount}));
  p.addChild(_part('Case', MeshPrimitiveType.cube, vm.Vector3.zero(), vm.Vector3(0.6, 0.45, 0.6), const Color(0xFFE5E7EB), metallic: 0.1));
  if (kind == 'health') {
    p
      ..addChild(_part('Cross H', MeshPrimitiveType.cube, vm.Vector3(0, 0, 0), vm.Vector3(0.64, 0.12, 0.3), color, emission: 0.9))
      ..addChild(_part('Cross V', MeshPrimitiveType.cube, vm.Vector3(0, 0, 0), vm.Vector3(0.3, 0.12, 0.64), color, emission: 0.9));
  } else {
    p.addChild(_part('Band', MeshPrimitiveType.cube, vm.Vector3(0, 0, 0), vm.Vector3(0.64, 0.14, 0.64), color, emission: 0.9));
  }
  return p;
}

// ---------------------------------------------------------------------------
// Scenes

EmberScene buildArenaLevel() {
  final scene = EmberScene(name: Arena.level);
  _buildArena(scene);

  // Effects (bursts at positions given by scripts)
  scene
    ..addEntity(_fx('Spark FX', const Color(0xFFFFE08A), const Color(0x00FF7A1A), size: 0.09, speed: 2.4, life: 0.35, gravity: -9))
    ..addEntity(_fx('Explosion FX', const Color(0xFFFFE6A0), const Color(0x00DC2626), size: 0.15, speed: 3.4, life: 0.5, gravity: -3))
    ..addEntity(_fx('Portal FX', const Color(0xFFE9D5FF), const Color(0x00A855F7), size: 0.2, speed: 1.6, life: 0.8, gravity: 0.5));

  // The player, with a gun held in front of the camera
  final player = EmberEntity(name: 'Player', tags: {'player'})
    ..addComponent(Transform3DComponent(position: vm.Vector3(0, 0.9, 12)))
    ..addComponent(CameraComponent(fov: 78, near: 0.05))
    ..addComponent(CharacterController3DComponent(walkSpeed: 7, sprintSpeed: 10.5, jumpForce: 7, gravity: 20))
    ..addComponent(HealthComponent(maxHealth: 100, team: 'player', invulnerableTime: 0.35, destroyOnDeath: false))
    ..addComponent(ScriptComponent(scriptName: 'arena_player.ember'));
  final gun = EmberEntity(name: 'Gun')..addComponent(Transform3DComponent(position: vm.Vector3(0.26, 0.45, -0.66), scale: vm.Vector3.all(0.8)));
  gun
    ..addChild(_part('Body', MeshPrimitiveType.cube, vm.Vector3(0, 0, 0), vm.Vector3(0.12, 0.14, 0.44), const Color(0xFF3F4652), metallic: 0.6))
    ..addChild(_part('Barrel', MeshPrimitiveType.cylinder, vm.Vector3(0, 0.01, -0.3), vm.Vector3(0.07, 0.2, 0.07), const Color(0xFF2A2E35),
        euler: vm.Vector3(90, 0, 0), segments: 8))
    ..addChild(_part('Core', MeshPrimitiveType.cube, vm.Vector3(0, 0.085, -0.02), vm.Vector3(0.06, 0.03, 0.24), Arena.molten, emission: 1, bias: 0.05))
    ..addChild(_part('Grip', MeshPrimitiveType.cube, vm.Vector3(0, -0.12, 0.1), vm.Vector3(0.07, 0.14, 0.09), Arena.dark));
  player.addChild(gun);
  scene.addEntity(player);

  // Robot and pickup templates (copied by spawn())
  scene
    ..addEntity(_drone())
    ..addEntity(_gunner())
    ..addEntity(_brute())
    ..addEntity(_pickupTemplate('Health Pack', 'health', 30, const Color(0xFFEF4444)))
    ..addEntity(_pickupTemplate('Ammo Crate', 'ammo', 12, const Color(0xFF38BDF8)));

  // The game director
  scene.addEntity(EmberEntity(name: 'Arena')..addComponent(ScriptComponent(scriptName: 'arena.ember')));

  // HUD
  scene
    ..addEntity(EmberEntity(name: 'HurtFlash')
      ..enabled = false
      ..addComponent(UIImageComponent(assetPath: '${Arena.art}/vignette.png', anchor: EmberAnchor.center, size: vm.Vector2(2400, 1350))))
    ..addEntity(_text('Crosshair', '+', 28, EmberAnchor.center, vm.Vector2(0, -17), color: const Color(0xDDFFFFFF)))
    ..addEntity(_text('HitMarker', '', 22, EmberAnchor.center, vm.Vector2(0, -15), color: const Color(0xFFFFE08A)))
    ..addEntity(EmberEntity(name: 'HealthBar')
      ..addComponent(UIBarComponent(
        value: 100,
        max: 100,
        label: 'HP 100',
        fillColor: const Color(0xFFEF4444),
        anchor: EmberAnchor.bottomLeft,
        offset: vm.Vector2(24, -28),
        size: vm.Vector2(240, 22),
      )))
    ..addEntity(_text('WeaponText', '1  BLASTER', 18, EmberAnchor.bottomRight, vm.Vector2(-24, -58), color: const Color(0xFFFDBA74)))
    ..addEntity(_text('AmmoText', '∞', 26, EmberAnchor.bottomRight, vm.Vector2(-24, -30)))
    ..addEntity(_text('WaveText', 'WAVE -', 24, EmberAnchor.topCenter, vm.Vector2(0, 14), color: const Color(0xFFFDBA74)))
    ..addEntity(_text('RobotsText', 'Robots 0', 16, EmberAnchor.topCenter, vm.Vector2(0, 44)))
    ..addEntity(_text('ScoreText', '0', 26, EmberAnchor.topRight, vm.Vector2(-24, 14)))
    ..addEntity(_text('Banner', '', 44, EmberAnchor.center, vm.Vector2(0, -120), color: const Color(0xFFFDBA74)))
    ..addEntity(_text('BannerLine', '', 18, EmberAnchor.center, vm.Vector2(0, -72)))
    ..addEntity(_text('Controls', 'WASD move · Mouse aim · Click fire · 1/2 or Q switch · Space jump · Shift sprint', 12, EmberAnchor.bottomCenter,
        vm.Vector2(0, -10), color: const Color(0x99FFFFFF)));

  // Game over (shown by the arena script)
  EmberEntity hidden(EmberEntity e) => e..enabled = false;
  scene
    ..addEntity(hidden(EmberEntity(name: 'GameOverPanel')
      ..addComponent(UIImageComponent(assetPath: '${Arena.art}/panel.png', anchor: EmberAnchor.center, offset: vm.Vector2(0, 10), size: vm.Vector2(480, 300)))))
    ..addEntity(hidden(_text('GameOverTitle', 'DEFEATED', 44, EmberAnchor.center, vm.Vector2(0, -90), color: const Color(0xFFF87171))))
    ..addEntity(hidden(_text('GameOverStats', '', 16, EmberAnchor.center, vm.Vector2(0, -20))))
    ..addEntity(hidden(EmberEntity(name: 'RetryButton')
      ..addComponent(UIButtonComponent(text: 'Fight again', action: 'retry', hotkey: 'Enter', anchor: EmberAnchor.center, offset: vm.Vector2(-100, 85)))))
    ..addEntity(hidden(EmberEntity(name: 'MenuButton')
      ..addComponent(UIButtonComponent(text: 'Menu', action: 'level:${Arena.title}', color: const Color(0xFF64748B), anchor: EmberAnchor.center,
          offset: vm.Vector2(100, 85)))));
  return scene;
}

EmberScene buildArenaTitle() {
  final scene = EmberScene(name: Arena.title);
  _buildArena(scene);
  // A few robots on show around the forge
  for (final (robot, x, z, yaw) in [(_gunner(), -2.0, 5.5, 20.0), (_brute(), 3.0, 5.0, -25.0), (_drone(), 0.5, 7.0, 0.0)]) {
    robot
      ..enabled = true
      ..removeComponent(robot.getComponent<EnemyAI3DComponent>()!)
      ..removeComponent(robot.getComponent<ScriptComponent>()!);
    final cc = robot.getComponent<CharacterController3DComponent>()!;
    final y = robot.name == 'Drone' ? 1.7 : cc.height / 2;
    robot.getComponent<Transform3DComponent>()!
      ..position = vm.Vector3(x, y, z)
      ..euler = vm.Vector3(0, 180 + yaw, 0);
    robot.removeComponent(cc); // statues: no gravity
    scene.addEntity(robot);
  }
  scene.addEntity(EmberEntity(name: 'Title Camera')
    ..addComponent(Transform3DComponent(position: vm.Vector3(10, 9, 20)))
    ..addComponent(CameraComponent(fov: 60))
    ..addComponent(ScriptComponent(scriptName: 'arena_title.ember')));
  scene
    ..addEntity(_text('Logo', 'EMBER ARENA', 64, EmberAnchor.topCenter, vm.Vector2(0, 60), color: const Color(0xFFFDBA74)))
    ..addEntity(_text('Tagline', 'Robots from four portals. Two guns. How many waves can you last?', 17, EmberAnchor.topCenter, vm.Vector2(0, 138)))
    ..addEntity(EmberEntity(name: 'PlayButton')
      ..addComponent(UIButtonComponent(text: 'Play', action: 'level:${Arena.level}', hotkey: 'Enter', anchor: EmberAnchor.center, offset: vm.Vector2(0, 40),
          size: vm.Vector2(220, 52), fontSize: 22)))
    ..addEntity(_text('BestText', 'Best: wave 0', 16, EmberAnchor.center, vm.Vector2(0, 100)))
    ..addEntity(_text('ControlsTitle', 'WASD move · Mouse aim · Click fire · 1/2 or Q switch weapon · Space jump · Shift sprint · Esc frees the mouse', 13,
        EmberAnchor.bottomCenter, vm.Vector2(0, -44), color: const Color(0xCCFFFFFF)))
    ..addEntity(EmberEntity(name: 'ResetButton')
      ..addComponent(UIButtonComponent(text: 'Reset best', action: 'reset', color: const Color(0xFF475569), anchor: EmberAnchor.bottomRight,
          offset: vm.Vector2(-20, -16), size: vm.Vector2(120, 30), fontSize: 13)));
  return scene;
}

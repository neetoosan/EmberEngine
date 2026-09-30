import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/entity.dart';
import '../../core/game_script.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import '../../core/transform3d.dart';
import '../../subsystems/two_d/flame_components.dart';
import '../../subsystems/three_d/camera3d.dart';
import '../../subsystems/three_d/components3d.dart';
import '../../subsystems/three_d/lighting.dart';
import '../../subsystems/three_d/material.dart';
import '../../subsystems/physics/character_controller2d.dart';
import '../../subsystems/physics/character_controller3d.dart';
import '../../subsystems/particles/particle_system.dart';
import '../../subsystems/audio/audio_component.dart';
import '../../subsystems/audio/audio_system.dart';
import '../../templates/flappy_game.dart';
import '../../templates/legends_game.dart';
import '../../templates/quest_game.dart';
import 'project_manifest.dart';

/// Identifier enum for built-in starter templates.
enum ProjectTemplateType {
  legends,
  quest,
  flappy,
  platformer2d,
  fps3d,
  particles,
  blank,
}

/// Rich metadata describing a starter template in the Startup Hub.
class ProjectTemplate {
  final ProjectTemplateType type;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color accentColor;
  final RenderPipelineMode defaultPipeline;
  final List<String> tags;
  final List<String> features;

  const ProjectTemplate({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.defaultPipeline,
    required this.tags,
    required this.features,
  });

  /// Instantiates a brand new [EmberProject] initialized with this template's assets & scene.
  EmberProject createProject({
    required String name,
    String? author,
    RenderPipelineMode? overridePipeline,
  }) {
    final projId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    final pipeline = overridePipeline ?? defaultPipeline;

    final project = EmberProject(
      id: projId,
      name: name.trim().isEmpty ? title : name.trim(),
      author: author ?? 'Ember Developer',
      description: description,
      renderPipeline: pipeline,
      defaultSceneName: 'MainScene',
    );

    // Build template specific scene & scripts
    switch (type) {
      case ProjectTemplateType.legends:
        project.scenes[Legends.title] = buildLegendsTitle();
        project.scenes[Legends.village] = buildLegendsVillage();
        project.scenes[Legends.field] = buildLegendsField();
        project.scenes[Legends.dungeon] = buildLegendsDungeon();
        project.defaultSceneName = Legends.title;
        project.assets.addAll(Legends.assetFiles);
        break;
      case ProjectTemplateType.quest:
        project.scenes['Level 1'] = buildQuestLevel1();
        project.scenes['Level 2'] = buildQuestLevel2();
        project.defaultSceneName = 'Level 1';
        project.assets.addAll(Quest.assetFiles);
        break;
      case ProjectTemplateType.flappy:
        project.scenes['MainScene'] = buildFlappyScene();
        // Pipes are spawned by script, so list their art explicitly
        project.assets.addAll(['${Flappy.art}/pipe_body.png', '${Flappy.art}/pipe_cap.png']);
        break;
      case ProjectTemplateType.platformer2d:
        _build2DPlatformerTemplate(project);
        break;
      case ProjectTemplateType.fps3d:
        _build3DFpsTemplate(project);
        break;
      case ProjectTemplateType.particles:
        _buildParticlePlaygroundTemplate(project);
        break;
      case ProjectTemplateType.blank:
        _buildBlankTemplate(project, pipeline);
        break;
    }

    return project;
  }

  // --- Template Generators ---

  void _build2DPlatformerTemplate(EmberProject project) {
    final scene = EmberScene(name: 'MainScene');

    // 1. World & TileMap
    final world = EmberEntity(name: 'World2D');
    world.addComponent(Transform2DComponent(position: vm.Vector2(0, 0)));

    final tiles = List.filled(24 * 14, 0);
    // Ground floor line (row 12 & 13) with tile ID 1
    for (int col = 0; col < 24; col++) {
      tiles[12 * 24 + col] = 1;
      tiles[13 * 24 + col] = 1;
    }
    // Floating platforms with tile ID 5
    for (final col in [4, 5, 6]) {
      tiles[9 * 24 + col] = 5;
    }
    for (final col in [10, 11, 12, 13]) {
      tiles[7 * 24 + col] = 5;
    }
    for (final col in [17, 18, 19]) {
      tiles[5 * 24 + col] = 5;
    }

    world.addComponent(FlameTileMapComponent(
      columns: 24,
      rows: 14,
      tileSize: 32.0,
      tiles: tiles,
    ));
    scene.addEntity(world);

    // 2. Player Character
    final player = EmberEntity(name: 'HeroPlayer');
    player.addComponent(Transform2DComponent(
      position: vm.Vector2(64, 300),
      size: vm.Vector2(48, 48),
      anchor: EmberAnchor.bottomCenter,
    ));
    player.addComponent(FlameSpriteComponent(
      assetPath: 'assets/sprites/hero_knight.png',
      tint: const Color(0xFFFFFFFF),
    ));
    player.addComponent(CharacterController2DComponent(
      moveSpeed: 240.0,
      jumpVelocity: 480.0,
      gravity: 980.0,
      coyoteTimeDuration: 0.12,
      jumpBufferDuration: 0.10,
      groundY: 600.0, // Safety floor below the level; tiles are the real ground
    ));
    player.addComponent(ScriptComponent(scriptName: 'Platformer 2D Controller'));
    player.addComponent(ParticleEmitter2DComponent(
      preset: ParticlePreset.sparkBurst,
      startColor: const Color(0xFFFF9100),
      endColor: const Color(0xFFFFD54F),
      maxParticles: 40,
      spawnRate: 0.0, // bursts on jump
    ));
    player.addComponent(AudioSourceComponent(
      clip: 'jump',
      category: AudioCategory.sfx,
      volume: 0.8,
    ));
    scene.addEntity(player);

    // 3. Collectable Coins
    final coinPositions = [
      vm.Vector2(160, 240),
      vm.Vector2(380, 180),
      vm.Vector2(580, 120),
    ];
    for (int i = 0; i < coinPositions.length; i++) {
      final coin = EmberEntity(name: 'Coin_${i + 1}');
      coin.addComponent(Transform2DComponent(
        position: coinPositions[i],
        size: vm.Vector2(24, 24),
        anchor: EmberAnchor.center,
      ));
      coin.addComponent(FlameSpriteComponent(
        assetPath: 'assets/sprites/gold_coin.png',
        tint: const Color(0xFFFFD700),
      ));
      coin.addComponent(FlameHitbox2DComponent(
        size: vm.Vector2(24, 24),
        isSolid: false,
      ));
      coin.addComponent(ScriptComponent(scriptName: 'Collectible'));
      scene.addEntity(coin);
    }

    project.scenes['MainScene'] = scene;

    // Attach Starter Scripts
    project.scripts['player_controller_2d.dart'] = '''
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/subsystems/physics/character_controller2d.dart';
import 'package:ember_engine/subsystems/audio/audio_component.dart';
import 'package:ember_engine/subsystems/particles/particle_system.dart';

/// 2D Platformer Player Controller Script
class PlayerController2D extends GameScript {
  CharacterController2DComponent? controller;
  AudioSourceComponent? jumpAudio;
  ParticleEmitter2DComponent? trailParticles;

  @override
  void onStart() {
    controller = getComponent<CharacterController2DComponent>();
    jumpAudio = getComponent<AudioSourceComponent>();
    trailParticles = getComponent<ParticleEmitter2DComponent>();
  }

  @override
  void onUpdate(double dt) {
    if (controller == null) return;

    double horizontal = 0.0;
    if (Input.isActionPressed(EngineAction.moveRight)) horizontal += 1.0;
    if (Input.isActionPressed(EngineAction.moveLeft)) horizontal -= 1.0;

    controller?.move(horizontal, dt);

    if (Input.isActionJustPressed(EngineAction.jump)) {
      if (controller?.jump() ?? false) {
        jumpAudio?.play();
        trailParticles?.triggerBurst(15);
      }
    }
  }
}
''';

    project.scripts['coin_collector.dart'] = '''
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/subsystems/audio/audio_system.dart';

/// Coin Pick-up & Scoring Logic
class CoinCollector extends GameScript {
  int score = 0;

  void onCollectCoin(String coinEntityName) {
    score += 100;
    AudioSystem.instance.play(clip: 'coin');
    scene?.removeEntity(scene!.findByName(coinEntityName)!);
  }
}
''';
  }

  void _build3DFpsTemplate(EmberProject project) {
    final scene = EmberScene(name: 'MainScene');

    // 1. Directional Sun & Ambient Light
    final sun = EmberEntity(name: 'SunLight');
    sun.addComponent(Transform3DComponent(
      position: vm.Vector3(10, 20, 10),
      euler: vm.Vector3(-45, -30, 0), // negative pitch = pointing down
    ));
    sun.addComponent(LightComponent(
      type: LightType.directional,
      color: const Color(0xFFFFF7E6),
      intensity: 1.2,
    ));
    scene.addEntity(sun);

    // 2. Arena Floor
    final floor = EmberEntity(name: 'ArenaFloor');
    floor.addComponent(Transform3DComponent(
      position: vm.Vector3(0, 0, 0),
      scale: vm.Vector3(40, 1, 40),
    ));
    floor.addComponent(MeshRenderer3DComponent(
      primitiveType: MeshPrimitiveType.plane,
      material: Material3D(
        color: const Color(0xFF1E293B),
        metallic: 0.1,
        roughness: 0.8,
        wireframe: false,
      ),
    ));
    scene.addEntity(floor);

    // 3. Tactical Arena Pillars
    final pillarCoords = [
      vm.Vector3(-8, 3, -8),
      vm.Vector3(8, 3, -8),
      vm.Vector3(-8, 3, 8),
      vm.Vector3(8, 3, 8),
    ];
    for (int i = 0; i < pillarCoords.length; i++) {
      final pillar = EmberEntity(name: 'Pillar_${i + 1}');
      pillar.addComponent(Transform3DComponent(
        position: pillarCoords[i],
        scale: vm.Vector3(2, 6, 2),
      ));
      pillar.addComponent(MeshRenderer3DComponent(
        primitiveType: MeshPrimitiveType.cylinder,
        material: Material3D(
          color: const Color(0xFF334155),
          metallic: 0.4,
          roughness: 0.4,
        ),
      ));
      pillar.addComponent(Collider3DComponent());
      scene.addEntity(pillar);
    }

    // 4. Target Bot with Hit Sparks
    final target = EmberEntity(name: 'TargetBot');
    target.addComponent(Transform3DComponent(
      position: vm.Vector3(0, 1.5, -12),
      scale: vm.Vector3(1.2, 2.0, 1.2),
    ));
    target.addComponent(MeshRenderer3DComponent(
      primitiveType: MeshPrimitiveType.cube,
      material: Material3D(
        color: const Color(0xFFEF4444),
        metallic: 0.7,
        roughness: 0.2,
      ),
    ));
    target.addComponent(ParticleEmitter3DComponent(
      preset: ParticlePreset.sparkBurst,
      startColor: const Color(0xFFF97316),
      endColor: const Color(0xFFFDE047),
      spawnRate: 0.0, // only bursts when shot
    ));
    target.addComponent(Collider3DComponent());
    scene.addEntity(target);

    // 5. FPS Player (faces -Z, toward the target bot)
    final player = EmberEntity(name: 'Player (FPS)');
    player.addComponent(Transform3DComponent(
      position: vm.Vector3(0, 0.9, 10),
    ));
    player.addComponent(CameraComponent(
      fov: 75.0,
      isMainCamera: true,
    ));
    player.addComponent(CharacterController3DComponent(
      walkSpeed: 7.0,
      sprintSpeed: 12.0,
      jumpForce: 7.0,
      gravity: 18.0,
    ));
    player.addComponent(ScriptComponent(scriptName: 'FPS Player Controller'));
    player.addComponent(AudioSourceComponent(
      clip: 'laser',
      category: AudioCategory.sfx,
      volume: 0.9,
    ));
    scene.addEntity(player);

    project.scenes['MainScene'] = scene;

    // Attach Starter Scripts
    project.scripts['fps_controller.dart'] = '''
import 'package:flutter/services.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/subsystems/physics/character_controller3d.dart';
import 'package:ember_engine/subsystems/audio/audio_component.dart';

/// 3D First Person Shooter Controller Script
class FpsController extends GameScript {
  CharacterController3DComponent? controller;
  AudioSourceComponent? weaponAudio;

  @override
  void onStart() {
    controller = getComponent<CharacterController3DComponent>();
    weaponAudio = getComponent<AudioSourceComponent>();
  }

  @override
  void onUpdate(double dt) {
    if (controller == null) return;

    double moveX = 0;
    double moveZ = 0;

    if (Input.isActionPressed(EngineAction.moveForward)) moveZ -= 1;
    if (Input.isActionPressed(EngineAction.moveBackward)) moveZ += 1;
    if (Input.isActionPressed(EngineAction.moveLeft)) moveX -= 1;
    if (Input.isActionPressed(EngineAction.moveRight)) moveX += 1;

    final isSprinting = Input.isKeyPressed(LogicalKeyboardKey.shiftLeft);
    controller?.move(moveX, moveZ, isSprinting: isSprinting, dt: dt);

    if (Input.isActionJustPressed(EngineAction.jump)) {
      controller?.jump();
    }
    if (Input.isActionJustPressed(EngineAction.fire)) {
      weaponAudio?.play();
    }
  }
}
''';
  }

  void _buildParticlePlaygroundTemplate(EmberProject project) {
    final scene = EmberScene(name: 'MainScene');

    // 1. Ambient & Point Light
    final light = EmberEntity(name: 'StudioLight');
    light.addComponent(Transform3DComponent(position: vm.Vector3(0, 10, 0)));
    light.addComponent(LightComponent(
      type: LightType.point,
      color: const Color(0xFF60A5FA),
      intensity: 2.0,
    ));
    scene.addEntity(light);

    // 2. Center 3D Flame Station
    final flame3d = EmberEntity(name: 'FireEmitter_3D');
    flame3d.addComponent(Transform3DComponent(position: vm.Vector3(-4, 0, 0)));
    flame3d.addComponent(MeshRenderer3DComponent(
      primitiveType: MeshPrimitiveType.cylinder,
      material: Material3D(color: const Color(0xFF1E293B)),
    ));
    flame3d.addComponent(ParticleEmitter3DComponent(
      preset: ParticlePreset.emberFire,
      maxParticles: 120,
      spawnRate: 45.0,
    ));
    scene.addEntity(flame3d);

    // 3. 3D Spark Burst Station
    final spark3d = EmberEntity(name: 'SparkEmitter_3D');
    spark3d.addComponent(Transform3DComponent(position: vm.Vector3(4, 0, 0)));
    spark3d.addComponent(MeshRenderer3DComponent(
      primitiveType: MeshPrimitiveType.sphere,
      material: Material3D(color: const Color(0xFF0F172A)),
    ));
    spark3d.addComponent(ParticleEmitter3DComponent(
      preset: ParticlePreset.sparkBurst,
      maxParticles: 150,
      spawnRate: 50.0,
    ));
    scene.addEntity(spark3d);

    // 4. Primary Orbit Camera
    final cam = EmberEntity(name: 'MainCamera');
    cam.addComponent(Transform3DComponent(
      position: vm.Vector3(0, 4, 12),
      euler: vm.Vector3(-15, 0, 0),
    ));
    cam.addComponent(CameraComponent(fov: 60.0, isMainCamera: true));
    scene.addEntity(cam);

    project.scenes['MainScene'] = scene;

    // Attach Starter Scripts
    project.scripts['particle_burst_trigger.dart'] = '''
import 'package:flutter/services.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/subsystems/particles/particle_system.dart';

/// Triggers particle bursts upon spacebar or mouse click
class ParticleBurstTrigger extends GameScript {
  @override
  void onUpdate(double dt) {
    if (Input.isKeyJustPressed(LogicalKeyboardKey.space)) {
      final emitter = getComponent<ParticleEmitter3DComponent>();
      emitter?.triggerBurst(40);
    }
  }
}
''';
  }

  void _buildBlankTemplate(EmberProject project, RenderPipelineMode pipeline) {
    final scene = EmberScene(name: 'MainScene');

    if (pipeline == RenderPipelineMode.twoD) {
      final cam2d = EmberEntity(name: 'Camera2D');
      cam2d.addComponent(Transform2DComponent(position: vm.Vector2(0, 0)));
      scene.addEntity(cam2d);
    } else {
      final sun = EmberEntity(name: 'Directional Light');
      sun.addComponent(Transform3DComponent(
        position: vm.Vector3(5, 10, 5),
        euler: vm.Vector3(-45, -45, 0), // negative pitch = pointing down
      ));
      sun.addComponent(LightComponent(intensity: 1.0));
      scene.addEntity(sun);

      final cam3d = EmberEntity(name: 'Main Camera');
      cam3d.addComponent(Transform3DComponent(
        position: vm.Vector3(0, 3, 8),
        euler: vm.Vector3(-15, 0, 0),
      ));
      cam3d.addComponent(CameraComponent(fov: 60.0, isMainCamera: true));
      scene.addEntity(cam3d);
    }

    project.scenes['MainScene'] = scene;
  }
}

/// Catalog of all 4 official built-in starter templates.
class TemplateCatalog {
  static const List<ProjectTemplate> templates = [
    ProjectTemplate(
      type: ProjectTemplateType.platformer2d,
      title: '2D Platformer Adventure',
      subtitle: 'Flame 2D Engine with Tilemaps & Kinematic Character',
      description:
          'A complete 2D side-scrolling platformer featuring Flame tilemap collision grids, animated knight sprites, collectable coins, and responsive 2D physics with coyote time & jump buffering.',
      icon: Icons.videogame_asset_rounded,
      accentColor: Color(0xFFFF5722),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Flame', 'Platformer', 'Physics', 'Tilemap'],
      features: [
        'Flame 2D Tilemap grid system',
        'Kinematic 2D Character with Coyote Time',
        'Animated sprite sheets & jump bursts',
        'Collectable coins with sound FX',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.legends,
      title: 'Ember Legends',
      subtitle: 'Top-Down Monster-Slaying Action RPG',
      description:
          'Sword in hand, clear the field of slimes and bats, descend into the Ember Depths past skeleton archers, and defeat the Ember Golem. XP and level-ups, loot, potions, a village with NPCs, save crystal, pause menu and continue.',
      icon: Icons.shield_rounded,
      accentColor: Color(0xFFB45309),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Top-down', 'RPG', 'Combat', 'Pixel art', 'Music'],
      features: [
        'Sword combat, monster AI with pathfinding, boss fight',
        'XP, level-ups, gold, potions and hearts',
        'Village, field and dungeon linked by doors',
        'Title screen, pause menu, save & continue',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.quest,
      title: 'Ember Quest',
      subtitle: 'Mario-style Side-Scrolling Platformer',
      description:
          'Two complete levels: run and jump, stomp slimes, bump "?" blocks for coins and a power berry, break bricks when big, dodge spikes and pits, and reach the flag. Score, coins, lives, music and level progression included.',
      icon: Icons.castle_rounded,
      accentColor: Color(0xFF0F766E),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Platformer', 'Levels', 'Pixel art', 'Music'],
      features: [
        'Stomp enemies, power-up, lives & score',
        '"?" blocks, breakable bricks, one-way planks, spikes',
        'Tileset level you can repaint in the editor',
        'Two levels linked by a goal flag, chiptune loop',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.flappy,
      title: 'Flappy Arcade',
      subtitle: 'One-Button Endless Flyer (Flappy Bird-style)',
      description:
          'Tap to flap between endless pipes. Pixel-art sprites, animated wings, scrolling ground and parallax hills, score and best-score saving, and instant restart — a complete, exportable arcade game.',
      icon: Icons.flutter_dash,
      accentColor: Color(0xFFF97316),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Arcade', 'One-button', 'Pixel art'],
      features: [
        'Tap / click / Space to flap',
        'Random pipe gaps with scoring gates',
        'Score HUD, Game Over and saved best score',
        'Letterboxed 288×512 camera fits any window',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.fps3d,
      title: '3D FPS Arena',
      subtitle: 'Spatial 3D Viewport, Capsule Physics & Lighting',
      description:
          'A combat arena with first-person capsule movement, mouse-look camera, procedural geometry, real-time lighting with shadows, weapon audio triggers, and 3D hit spark emitters.',
      icon: Icons.view_in_ar_rounded,
      accentColor: Color(0xFF3B82F6),
      defaultPipeline: RenderPipelineMode.threeD,
      tags: ['3D', 'FPS', 'Kinematics', 'Lighting', 'Audio'],
      features: [
        '3D FPS Character Controller (WASD + Mouse Look)',
        'Directional & Point light shadow casting',
        'Spatial 3D audio playback',
        'Procedural cylinder arena pillars & target dummy',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.particles,
      title: 'Procedural Particle Playground',
      subtitle: '2D & 3D GPU Particle Emitters & Simulation',
      description:
          'An interactive visual laboratory for crafting custom particle effects. Pre-configured with emberFire, sparkBurst, and smokeTrail presets, color ramps, and burst triggers.',
      icon: Icons.auto_awesome_rounded,
      accentColor: Color(0xFFEC4899),
      defaultPipeline: RenderPipelineMode.hybrid,
      tags: ['Particles', 'VFX', 'Simulation', 'Color Ramps'],
      features: [
        'Multi-preset 2D & 3D particle emitters',
        'Interactive burst testing station',
        'Smooth color gradient & size interpolation',
        'Orbit camera inspection scene',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.blank,
      title: 'Blank Canvas Project',
      subtitle: 'Clean Slate for Custom 2D or 3D Game Architecture',
      description:
          'A minimal clean project structure ready for your custom game architecture. Choose 2D, 3D, or Hybrid pipelines to start from scratch without preset assets.',
      icon: Icons.layers_outlined,
      accentColor: Color(0xFF10B981),
      defaultPipeline: RenderPipelineMode.hybrid,
      tags: ['Blank', 'Clean Slate', 'Flexible', '2D/3D'],
      features: [
        'Minimal scene structure with primary camera',
        'Choice of 2D Flat or 3D Spatial rendering',
        'Clean component registry ready for extension',
        'Zero bloat startup template',
      ],
    ),
  ];

  static ProjectTemplate getByType(ProjectTemplateType type) {
    return templates.firstWhere(
      (t) => t.type == type,
      orElse: () => templates.last,
    );
  }

  static ProjectTemplate getTemplate(ProjectTemplateType type) => getByType(type);
}

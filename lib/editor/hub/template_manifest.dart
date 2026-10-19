import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/entity.dart';
import '../../core/game_script.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import '../../core/transform3d.dart';
import '../../subsystems/three_d/camera3d.dart';
import '../../subsystems/three_d/components3d.dart';
import '../../subsystems/three_d/lighting.dart';
import '../../subsystems/three_d/material.dart';
import '../../subsystems/physics/character_controller3d.dart';
import '../../subsystems/particles/particle_system.dart';
import '../../subsystems/audio/audio_component.dart';
import '../../subsystems/audio/audio_system.dart';
import '../../templates/flappy_game.dart';
import '../../templates/flappy_scripts.dart';
import '../../subsystems/ui/ui_text.dart';
import '../../templates/legends_game.dart';
import '../../templates/legends_scripts.dart';
import '../../templates/quest_game.dart';
import '../../templates/platformer_starter.dart';
import '../../templates/quest_scripts.dart';
import '../../templates/arena_game.dart';
import '../../templates/arena_scripts.dart';
import '../../templates/gems_game.dart';
import '../../templates/gems_scripts.dart';
import '../../templates/bastion_game.dart';
import '../../templates/clash_game.dart';
import '../../templates/kindred_game.dart';
import '../../templates/kindred_scripts.dart';
import '../../templates/clash_scripts.dart';
import '../../templates/depths_game.dart';
import '../../templates/isles_game.dart';
import '../../templates/pulse_game.dart';
import '../../templates/pulse_scripts.dart';
import '../../templates/isles_scripts.dart';
import '../../templates/spire_game.dart';
import '../../templates/spire_scripts.dart';
import '../../templates/depths_scripts.dart';
import '../../templates/bastion_scripts.dart';
import '../../templates/nova_game.dart';
import '../../templates/nova_scripts.dart';
import '../../templates/siege_game.dart';
import '../../templates/solitaire_game.dart';
import '../../templates/solitaire_scripts.dart';
import '../../templates/story_game.dart';
import '../../templates/story_scripts.dart';
import '../../templates/siege_scripts.dart';
import 'project_manifest.dart';

/// Identifier enum for built-in starter templates.
enum ProjectTemplateType {
  kindred,
  clash,
  pulse,
  isles,
  spire,
  depths,
  bastion,
  nova,
  arena,
  gems,
  solitaire,
  story,
  siege,
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
      case ProjectTemplateType.kindred:
        project.scenes[Kindred.title] = buildKindredTitle();
        project.scenes[Kindred.grove] = buildKindredGrove();
        project.defaultSceneName = Kindred.title;
        project.scripts.addAll(kindredScripts); // editable in the Script workspace
        project.assets.addAll(Kindred.assetFiles);
        break;
      case ProjectTemplateType.clash:
        project.scenes[Clash.title] = buildClashTitle();
        project.scenes[Clash.arena] = buildClashArena();
        project.defaultSceneName = Clash.title;
        project.scripts.addAll(clashScripts); // editable in the Script workspace
        project.assets.addAll(Clash.assetFiles);
        break;
      case ProjectTemplateType.pulse:
        project.scenes[Pulse.title] = buildPulseTitle();
        project.scenes[Pulse.stage] = buildPulseStage();
        project.defaultSceneName = Pulse.title;
        project.scripts.addAll(pulseScripts); // the scripts and the three charts, editable in the Script workspace
        project.assets.addAll(Pulse.assetFiles);
        break;
      case ProjectTemplateType.isles:
        project.scenes[Isles.title] = buildIslesTitle();
        project.scenes[Isles.island] = buildIslesIsland();
        project.defaultSceneName = Isles.title;
        project.scripts.addAll(islesScripts); // editable in the Script workspace
        project.assets.addAll(Isles.assetFiles);
        break;
      case ProjectTemplateType.spire:
        project.scenes[Spire.title] = buildSpireTitle();
        project.scenes[Spire.world] = buildSpireWorld();
        project.defaultSceneName = Spire.title;
        project.scripts.addAll(spireScripts); // editable in the Script workspace
        project.assets.addAll(Spire.assetFiles);
        break;
      case ProjectTemplateType.depths:
        project.scenes[Depths.title] = buildDepthsTitle();
        project.scenes[Depths.dungeon] = buildDepthsDungeon();
        project.defaultSceneName = Depths.title;
        project.scripts.addAll(depthsScripts); // editable in the Script workspace
        project.assets.addAll(Depths.assetFiles);
        break;
      case ProjectTemplateType.bastion:
        project.scenes[Bastion.title] = buildBastionTitle();
        project.scenes[Bastion.battle] = buildBastionBattle();
        project.defaultSceneName = Bastion.title;
        project.scripts.addAll(bastionScripts); // editable in the Script workspace
        project.assets.addAll(Bastion.assetFiles);
        break;
      case ProjectTemplateType.nova:
        project.scenes[Nova.title] = buildNovaTitle();
        project.scenes[Nova.stage] = buildNovaStage();
        project.defaultSceneName = Nova.title;
        project.scripts.addAll(novaScripts); // editable in the Script workspace
        project.assets.addAll(Nova.assetFiles);
        break;
      case ProjectTemplateType.arena:
        project.scenes[Arena.title] = buildArenaTitle();
        project.scenes[Arena.level] = buildArenaLevel();
        project.defaultSceneName = Arena.title;
        project.scripts.addAll(arenaScripts); // editable in the Script workspace
        project.assets.addAll(Arena.assetFiles);
        break;
      case ProjectTemplateType.gems:
        project.scenes[Gems.title] = buildGemsTitle();
        project.scenes['Level 1'] = buildGemsLevel1();
        project.scenes['Level 2'] = buildGemsLevel2();
        project.scenes['Level 3'] = buildGemsLevel3();
        project.defaultSceneName = Gems.title;
        project.scripts.addAll(gemsScripts); // editable in the Script workspace
        project.assets.addAll(Gems.assetFiles);
        break;
      case ProjectTemplateType.solitaire:
        project.scenes[Solitaire.title] = buildSolitaireTitle();
        for (final mode in Solitaire.modes) {
          project.scenes[mode] = buildSolitaireTable(mode);
        }
        project.defaultSceneName = Solitaire.title;
        project.scripts.addAll(solitaireScripts); // editable in the Script workspace
        project.assets.addAll(Solitaire.assetFiles);
        break;
      case ProjectTemplateType.story:
        project.scenes[StoryTemplate.title] = buildStoryTitle();
        project.scenes[StoryTemplate.story] = buildStoryScene();
        project.defaultSceneName = StoryTemplate.title;
        project.scripts.addAll(storyScripts); // the story and scripts, editable in the Script workspace
        project.assets.addAll(StoryTemplate.assetFiles);
        break;
      case ProjectTemplateType.siege:
        project.scenes[Siege.title] = buildSiegeTitle();
        project.scenes['Level 1'] = buildSiegeLevel1();
        project.scenes['Level 2'] = buildSiegeLevel2();
        project.scenes['Level 3'] = buildSiegeLevel3();
        project.defaultSceneName = Siege.title;
        project.scripts.addAll(siegeScripts); // editable in the Script workspace
        project.assets.addAll(Siege.assetFiles);
        break;
      case ProjectTemplateType.legends:
        project.scenes[Legends.title] = buildLegendsTitle();
        project.scenes[Legends.village] = buildLegendsVillage();
        project.scenes[Legends.field] = buildLegendsField();
        project.scenes[Legends.dungeon] = buildLegendsDungeon();
        project.defaultSceneName = Legends.title;
        project.scripts.addAll(legendsScripts); // editable in the Script workspace
        project.assets.addAll(Legends.assetFiles);
        break;
      case ProjectTemplateType.quest:
        project.scenes['Level 1'] = buildQuestLevel1();
        project.scenes['Level 2'] = buildQuestLevel2();
        project.defaultSceneName = 'Level 1';
        project.scripts.addAll(questScripts); // editable in the Script workspace
        project.assets.addAll(Quest.assetFiles);
        break;
      case ProjectTemplateType.flappy:
        project.scenes['MainScene'] = buildFlappyScene();
        project.scripts.addAll(flappyScripts); // editable in the Script workspace
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
    project.scenes['MainScene'] = buildPlatformerStarter();
    project.scripts.addAll(platformerStarterScripts); // editable in the Script workspace
    project.assets.addAll(platformerStarterAssets);
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

    // Crosshair and hit counter (on-screen UI), and the target's Ember Script
    scene.addEntity(EmberEntity(name: 'Crosshair')
      ..addComponent(UITextComponent(text: '+', fontSize: 28, anchor: EmberAnchor.center, offset: vm.Vector2(0, -14))));
    scene.addEntity(EmberEntity(name: 'HitsText')
      ..addComponent(UITextComponent(text: 'Hits 0', fontSize: 20, anchor: EmberAnchor.topRight, offset: vm.Vector2(-20, 14))));
    scene.addEntity(EmberEntity(name: 'HelpText')
      ..addComponent(UITextComponent(
          text: 'WASD move · mouse look · click / F shoot · Space jump · Shift sprint', fontSize: 13, anchor: EmberAnchor.bottomCenter, offset: vm.Vector2(0, -14))));
    target.addComponent(ScriptComponent(scriptName: 'target_bot.ember'));
    project.scripts['target_bot.ember'] = '''
// The target bot: strafes left and right; counts the hits it takes.
// (Movement and shooting come from the built-in FPS Player Controller.)
var range = 5.0;       // how far it strafes from the middle
var speed = 1.2;
var _hits = 0;
var _homeX = 0.0;

void onStart() {
  _homeX = self.x;
}

void onUpdate(dt) {
  self.x = _homeX + sin(Game.time * speed) * range;
}

void onDamaged(amount, source) {
  _hits++;
  setText("HitsText", "Hits \$_hits");
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

    flame3d.addComponent(ScriptComponent(scriptName: 'bursts.ember'));
    spark3d.addComponent(ScriptComponent(scriptName: 'bursts.ember'));
    scene.addEntity(EmberEntity(name: 'HelpText')
      ..addComponent(UITextComponent(
          text: 'Press Space or click to fire bursts · select an emitter to tweak it', fontSize: 14, anchor: EmberAnchor.bottomCenter, offset: vm.Vector2(0, -14))));
    project.scripts['bursts.ember'] = '''
// Fires a burst of particles on Space or a click (on both emitters).
var count = 40;

void onUpdate(dt) {
  if (Input.pressed("Space") || Input.click) self.get("Particle Emitter 3D").burst(count);
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

/// Every built-in starter template, in the order the Project Hub shows them.
class TemplateCatalog {
  static const List<ProjectTemplate> templates = [
    ProjectTemplate(
      type: ProjectTemplateType.platformer2d,
      title: '2D Platformer Adventure',
      subtitle: 'A Small Level to Learn From',
      description:
          'One short side-scrolling level: run, jump over a pit and up the stone steps, and collect all 12 coins. The hero, coins and HUD are three short Ember Scripts, a good first read before Ember Quest.',
      icon: Icons.videogame_asset_rounded,
      accentColor: Color(0xFFFF5722),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Platformer', 'Tilemap', 'Beginner'],
      features: [
        'Platformer controller with coyote time and jump buffering',
        'Animated hero sprite sheet (idle, run, jump)',
        'Tilemap level you can repaint, one-way planks',
        'Coins, a coin counter and a pit that restarts the level',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.arena,
      title: 'Ember Arena',
      subtitle: 'First-Person 3D Wave Shooter',
      description:
          'Robots pour out of four portals in a low-poly foundry: exploding drones, strafing gunners and charging brutes. A blaster and a scatter gun, health and ammo drops, waves that keep getting bigger, and saved best wave and score.',
      icon: Icons.gps_fixed_rounded,
      accentColor: Color(0xFFF97316),
      defaultPipeline: RenderPipelineMode.threeD,
      tags: ['3D', 'First-person', 'Shooter', 'AI', 'Music'],
      features: [
        'Mouse-look with real mouse capture (Windows and web)',
        'Enemy AI 3D: chasers, shooters and chargers',
        '3D projectiles, hitscan weapons and hit flashes',
        'Sky, fog and glowing materials',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.gems,
      title: 'Ember Gems',
      subtitle: 'Match-3 Puzzle',
      description:
          'Swap gems to line up three of a colour. Lines of four make blast gems, L and T shapes make bombs, five make a star that clears a colour. Three levels with different goals (score, collect rubies, break the ice), cascades, hints, stars and unlocks.',
      icon: Icons.diamond_rounded,
      accentColor: Color(0xFFA855F7),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Puzzle', 'Match-3', 'Touch', 'Pixel art', 'Music'],
      features: [
        'Click or drag to swap; cascades and combos',
        'Blast gems, bombs and colour-clearing stars',
        'Score, collect and ice goals with move limits',
        'Hints, automatic reshuffle, stars and unlocks',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.solitaire,
      title: 'Ember Solitaire',
      subtitle: 'Klondike Card Game',
      description:
          'The classic patience game: drag cards and runs between the seven columns, build the four suits from Ace to King. Click a card to send it to the best place, undo any move, ask for a hint, finish automatically, and watch the cards bounce when you win. Draw 1 and Draw 3, with best times.',
      icon: Icons.style_rounded,
      accentColor: Color(0xFF16A34A),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Cards', 'Puzzle', 'Drag & drop', 'Pixel art', 'Music'],
      features: [
        'Drag cards and runs; one-click moves',
        'Undo, hints and auto-finish',
        'Score, moves, timer and saved records',
        'A full pixel-art deck to reuse in other card games',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.kindred,
      title: 'Ember Kindred',
      subtitle: 'Co-op Arena (1-4 players)',
      description:
          'Four lantern spirits hold a moonlit grove against ten waves of shadow and the Hollow. Up to four players share one screen, on keyboard halves or gamepads, and friends join at any time. The camera zooms out to keep everyone in view, a bond of light between spirits burns whatever crosses it, and a fallen spirit gets back up when a friend stays close.',
      icon: Icons.groups_rounded,
      accentColor: Color(0xFF5EEAD4),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Co-op', 'Local multiplayer', 'Gamepad', 'Modern', 'Music'],
      features: [
        'Drop-in play for 1 to 4 players (keyboard halves, gamepads)',
        'A shared camera that zooms to fit every player',
        'Light bonds between players that burn enemies',
        'Revive a fallen friend by staying close; ten waves and a boss',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.clash,
      title: 'Ember Clash',
      subtitle: 'Fighting Game',
      description:
          'Kai of the ember temple against Ryn of the frost clan, best of three rounds. Jabs, kicks, low kicks and air kicks, an orb on down, down-forward, forward and a rising strike on forward, down, down-forward. Guard high and low, chain combos, play the CPU on three levels or a second player on the keyboard or gamepads.',
      icon: Icons.sports_martial_arts_rounded,
      accentColor: Color(0xFFF97316),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Fighting', 'Local multiplayer', 'Gamepad', 'Music'],
      features: [
        'Frame-data moves at a fixed 60 steps a second',
        'Motion inputs from the input buffer (236, 623)',
        'Guarding high and low, hitstop, combos, rounds and a timer',
        'CPU opponent on three levels, or 2 players (keyboard or pads)',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.pulse,
      title: 'Ember Pulse',
      subtitle: 'Rhythm Game',
      description:
          'Notes fall down four neon lanes in time with Neon Drift, a synthwave track. Hit them as they reach the line, hold the long ones, keep the combo going. Easy, Normal and Hard charts, Perfect / Great / Good timing, accuracy and grades, best scores, and an audio offset for your speakers.',
      icon: Icons.music_note_rounded,
      accentColor: Color(0xFFF472B6),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Rhythm', 'Music', 'Modern'],
      features: [
        'Music.time: a clock that follows the music you hear',
        'Charts as plain text files (time, lane, hold)',
        'Taps and holds, judgement windows, combo and grades',
        'Audio offset calibration, pause, best scores',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.isles,
      title: 'Ember Isles',
      subtitle: 'Isometric Colony Strategy',
      description:
          'Settle an island grown from a seed. Houses bring people, farms feed them, lumber camps and quarries bring wood and stone. Raiders land every few minutes: train guards, drag a box to select them, right-click to send them, and build watchtowers. Light the Ember Beacon to win.',
      icon: Icons.sailing_rounded,
      accentColor: Color(0xFF38BDF8),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Strategy', 'City builder', 'Isometric', 'Music'],
      features: [
        'Isometric TileMap (also hex), Y-sorted buildings and units',
        'Box selection, right-click orders, grid path finding',
        'Resources, buildings with rules, raids and towers',
        'Islands grown from a seed with noise',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.spire,
      title: 'Ember Spire',
      subtitle: 'Metroidvania',
      description:
          'Nine linked rooms of glowing crystal caverns. Find the double jump, the dash and the wall jump to reach new places, rest at shrines to save, fill in the map as you explore, and defeat the Thornback to claim the Ember Heart. Sword combat, heart containers, gems and a best time.',
      icon: Icons.terrain_rounded,
      accentColor: Color(0xFF2DD4BF),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Metroidvania', 'Platformer', 'Exploration', 'Music'],
      features: [
        'Camera Room 2D: the view keeps to each room and glides between them',
        'UI Minimap that fills in as you explore (saved with the game)',
        'Double jump, dash and wall jump on the platformer controller',
        'Save shrines, a boss with charges and shockwaves, best time',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.depths,
      title: 'Ember Depths',
      subtitle: 'Roguelike Dungeon Crawler',
      description:
          'Every floor is a new dungeon grown from a seed: rooms, corridors and torch-lit walls. Cast at slimes, bats, skeleton archers and the Ember Warden, open chests for relics that change how you fight, and see how deep you get. Death is final; share a seed or play the daily dungeon.',
      icon: Icons.local_fire_department_outlined,
      accentColor: Color(0xFFF97316),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Roguelike', 'Procedural', 'Lighting', 'Music'],
      features: [
        'Seeded dungeon generation with auto-tiled walls',
        "Light 2D: darkness, torches and the hero's light",
        'Monster AI hunters, relics, chests and stairs',
        'Permadeath, best floor, same-seed and daily runs',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.bastion,
      title: 'Ember Bastion',
      subtitle: 'Tower Defense',
      description:
          'Goblins, wolves, golems, wisps and dark knights march down the road to your keep. Build Archer, Cannon, Frost and Tesla towers on the grass, upgrade them twice, sell them, and survive 15 waves on Normal or Hard. Splash damage, slowing frost, chain lightning, health bars and stars.',
      icon: Icons.castle_rounded,
      accentColor: Color(0xFF4ADE80),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Tower defense', 'Strategy', 'Modern', 'Music'],
      features: [
        'Path Follower 2D: enemies walk a road drawn with a Line 2D',
        'Grid building, upgrades and selling, range previews',
        'Homing and splash shots, slowing frost, chain lightning',
        '15 waves, Normal and Hard, health bars and stars',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.nova,
      title: 'Ember Nova',
      subtitle: "Neon Shoot-'em-up",
      description:
          'A side-scrolling space shooter with modern neon art. Waves of drones, darts, turrets, spinners and cruisers fill the screen with glowing bullet patterns, then the three-phase Ember Dreadnought. Power-ups, bombs, shields, grazing for a score multiplier, and loops that get harder.',
      icon: Icons.rocket_launch_rounded,
      accentColor: Color(0xFF22D3EE),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Shooter', 'Bullet hell', 'Modern', 'Music'],
      features: [
        'Bullet Pool 2D: thousands of glowing bullets in one batch',
        'Rings, spreads, spirals and curving shots from Ember Script',
        'A three-phase boss, bombs, shields and power levels',
        'Parallax space, glow particles, screen flash and shake',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.story,
      title: 'The Last Ember',
      subtitle: 'Visual Novel (Story Player)',
      description:
          'A short branching story: backgrounds, two characters with expressions, a typewriter dialogue box, choices that change how much Kai trusts you, and four endings (one secret). History log, Auto, Skip, three save slots and Continue. Written in a simple story file you can edit while it plays.',
      icon: Icons.auto_stories_rounded,
      accentColor: Color(0xFFF59E0B),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Visual novel', 'Story', 'Choices', 'Pixel art', 'Music'],
      features: [
        'Story Player: write scenes, lines, choices and endings in plain text',
        'Characters with expressions, backgrounds with fades',
        'Variables and conditions, four endings',
        'History, Auto, Skip, save slots and Continue',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.siege,
      title: 'Ember Siege',
      subtitle: 'Physics Slingshot Puzzle (Angry Birds-style)',
      description:
          'Drag back the slingshot and fling embers at frost castles. Real rigid-body physics: wood, ice and stone that tip, stack, crack and shatter, powder kegs that blow, and imps to defeat. Three levels, stars, unlocks and saved best scores.',
      icon: Icons.local_fire_department_rounded,
      accentColor: Color(0xFFEA580C),
      defaultPipeline: RenderPipelineMode.twoD,
      tags: ['2D', 'Physics', 'Puzzle', 'Touch', 'Pixel art', 'Music'],
      features: [
        'Rigid Body 2D: stacking, tipping, impacts, explosions',
        'Drag-to-aim slingshot with trajectory preview',
        'Embers, heavy coal and splitting sparks',
        'Three castles, stars, unlocks and best scores',
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
      subtitle: 'First-Person Movement, Shooting & Lighting in Basic 3D',
      description:
          'A small arena to walk around in first person: mouse-look, jumping and sprinting, pillars that block you, and a target bot that sparks when you shoot it. Lit by a sun light. (3D in Ember is basic: primitive shapes, no shadows.)',
      icon: Icons.view_in_ar_rounded,
      accentColor: Color(0xFF3B82F6),
      defaultPipeline: RenderPipelineMode.threeD,
      tags: ['3D', 'FPS', 'Lighting', 'Audio'],
      features: [
        'First-person controller (WASD, mouse look, jump, sprint)',
        'Click or F to shoot: hits spark and score',
        'Directional sun light and materials',
        'Pillars with collision, a target bot',
      ],
    ),
    ProjectTemplate(
      type: ProjectTemplateType.particles,
      title: 'Procedural Particle Playground',
      subtitle: '3D Particle Emitters to Experiment With',
      description:
          'A playground for particle effects: fire and spark emitters with colour and size ramps. Press Space or click while playing to fire bursts, then tweak the emitters in the Inspector.',
      icon: Icons.auto_awesome_rounded,
      accentColor: Color(0xFFEC4899),
      defaultPipeline: RenderPipelineMode.hybrid,
      tags: ['Particles', 'VFX', 'Simulation', 'Color Ramps'],
      features: [
        'Fire, spark, smoke and magic presets',
        'Space / click fires bursts while playing',
        'Colour and size over lifetime',
        'Edit every emitter setting live in the Inspector',
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

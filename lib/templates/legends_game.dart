import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/engine_loop.dart';
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/input.dart';
import '../core/inventory.dart';
import '../core/save_data.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../core/tween.dart';
import '../subsystems/ai/monster_ai.dart';
import '../subsystems/audio/audio_system.dart';
import '../subsystems/combat/combat.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/two_d/door.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/sprite_animator.dart';
import '../subsystems/two_d/top_down_controller.dart';
import '../subsystems/ui/dialogue.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "Ember Legends": a top-down monster-slaying action RPG built from engine
/// components (Top-Down Controller, Health, Monster AI, Doors, Dialogue,
/// UI widgets, save slots) plus the scripts in this file. Original art and music.
class Legends {
  static const String art = 'assets/templates/legends';
  static const String music = '$art/theme.wav';
  static const String dungeonMusic = '$art/dungeon.wav';
  static const double tile = 32;

  static const String title = 'Title', village = 'Village', field = 'Field', dungeon = 'Dungeon';
  static const List<String> scenes = [title, village, field, dungeon];

  // Tile IDs (cells of tiles.png)
  static const int grass = 1, path = 2, water = 3, tree = 4, rock = 5, bush = 6, flower = 7, houseWall = 8;
  static const int roof = 9, floor = 10, wall = 11, cave = 12, bridge = 13, fence = 14, torch = 15, houseDoor = 16;

  /// Obstacle-layer tiles you can walk over; everything else there is solid.
  static const Map<int, TileKind> tileKinds = {flower: TileKind.decoration, cave: TileKind.decoration};

  static const List<String> assetFiles = [
    '$art/tiles.png', '$art/hero.png', '$art/slash.png', '$art/slime.png', '$art/bat.png', '$art/skeleton.png',
    '$art/arrow.png', '$art/golem.png', '$art/fireball.png', '$art/elder.png', '$art/merchant.png', '$art/heart.png',
    '$art/coin.png', '$art/potion.png', '$art/crystal.png', music, dungeonMusic,
  ];

  static const int saveSlot = 1;

  static void newGame() {
    LegendsSession.reset();
    EmberEngine.instance.loadLevel(village);
  }

  /// Loads the saved game, or starts a new one if there is none.
  static void continueGame() {
    final data = SaveSlots.load(saveSlot);
    if (data == null) return newGame();
    final scene = LegendsSession.fromJson(data);
    if (!EmberEngine.instance.loadLevel(scene)) newGame();
  }

  static void save(EmberEntity hero) {
    final c = Combat.bodyOf(hero).center;
    SaveSlots.save(saveSlot, LegendsSession.toJson(hero.scene?.name ?? village, vm.Vector2(c.dx, c.dy)));
  }

  /// Loot rolls (replaceable for deterministic tests).
  static math.Random rng = math.Random();

  /// Gold, a heart or a potion lying on the ground, flying out from [at].
  static EmberEntity spawnPickup(EmberScene scene, String kind, vm.Vector2 at, {int amount = 1}) {
    final (asset, cols, tag) = switch (kind) {
      'gold' => ('coin.png', 4, 'gold:$amount'),
      'heart' => ('heart.png', 2, 'heal:$amount'),
      _ => ('potion.png', 1, 'item:Potion'),
    };
    final t = Transform2DComponent(position: at.clone(), size: vm.Vector2(20, 20), anchor: EmberAnchor.center, zIndex: 1);
    final e = EmberEntity(name: kind == 'gold' ? 'Gold' : (kind == 'heart' ? 'Heart' : 'Potion'), tags: {'pickup', tag})
      ..addComponent(t)
      ..addComponent(FlameSpriteComponent(assetPath: '$art/$asset', columns: cols))
      ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(18, 18), offset: vm.Vector2(1, 1), isSolid: false, debugDraw: false));
    if (kind == 'gold') e.addComponent(SpriteAnimatorComponent(clips: 'spin=0-3@8', defaultClip: 'spin'));
    scene.addEntity(e);
    // Scatter a little, but never into a wall
    final a = rng.nextDouble() * math.pi * 2;
    final to = at + vm.Vector2(math.cos(a), math.sin(a)) * (6 + rng.nextDouble() * 14);
    final area = Rect.fromCenter(center: Offset(to.x, to.y), width: 16, height: 16);
    if (!_blocked(scene, area)) {
      final from = at.clone();
      EmberTween.run(0.25, (p) => t.position = from + (to - from) * p, ease: Ease.outQuad, owner: e);
    }
    return e;
  }

  static bool _blocked(EmberScene scene, Rect area) {
    for (final map in scene.componentsOf<FlameTileMapComponent>()) {
      if (!map.collision) continue;
      for (final hit in map.tilesIn(area)) {
        if (hit.kind.blocks) return true;
      }
    }
    return false;
  }

  /// A one-shot particle puff (monster death, sparks).
  static void puff(EmberScene scene, vm.Vector2 at, Color start, Color end, {int count = 14}) {
    final e = EmberEntity(name: 'Puff')
      ..addComponent(Transform2DComponent(position: at.clone(), size: vm.Vector2.zero(), zIndex: 8))
      ..addComponent(ParticleEmitter2DComponent(
        preset: ParticlePreset.sparkBurst,
        spawnRate: 0,
        startColor: start,
        endColor: end,
        startSize: 5,
        endSize: 1,
        speed: 110,
        gravity: 0,
      ));
    scene.addEntity(e);
    e.getComponent<ParticleEmitter2DComponent>()?.burst(count);
    EmberTween.delay(1.2, () => scene.destroyLater(e));
  }

  static vm.Vector2 centerOf(EmberEntity e) {
    final c = Combat.bodyOf(e).center;
    return vm.Vector2(c.dx, c.dy);
  }
}

/// Hero progress that survives scene changes (and goes into save slots).
class LegendsSession {
  static int level = 1;
  static int xp = 0;
  static double maxHp = 5;
  static double hp = 5;
  static final Inventory inventory = Inventory();
  static bool bossDefeated = false;
  static bool metElder = false;

  /// Where the hero should appear when a saved game is loaded.
  static vm.Vector2? pendingPosition;

  static double get attack => 1 + (level - 1) * 0.5;
  static int get xpToNext => 6 + level * 6;

  static void reset() {
    level = 1;
    xp = 0;
    maxHp = 5;
    hp = 5;
    inventory.clear();
    bossDefeated = false;
    metElder = false;
    pendingPosition = null;
  }

  /// Adds experience; returns true if the hero levelled up.
  static bool addXp(int amount) {
    xp += amount;
    var up = false;
    while (xp >= xpToNext) {
      xp -= xpToNext;
      level++;
      maxHp = math.min(12, maxHp + 1);
      hp = maxHp;
      up = true;
    }
    return up;
  }

  static Map<String, dynamic> toJson(String scene, vm.Vector2 position) => {
        'scene': scene,
        'x': position.x,
        'y': position.y,
        'level': level,
        'xp': xp,
        'maxHp': maxHp,
        'inventory': inventory.toJson(),
        'bossDefeated': bossDefeated,
        'metElder': metElder,
      };

  /// Restores progress (at full health) and returns the saved scene name.
  static String fromJson(Map<String, dynamic> json) {
    level = (json['level'] as num?)?.toInt() ?? 1;
    xp = (json['xp'] as num?)?.toInt() ?? 0;
    maxHp = (json['maxHp'] as num?)?.toDouble() ?? 5;
    hp = maxHp;
    inventory.fromJson((json['inventory'] as Map?)?.cast<String, dynamic>());
    bossDefeated = json['bossDefeated'] as bool? ?? false;
    metElder = json['metElder'] as bool? ?? false;
    final x = (json['x'] as num?)?.toDouble(), y = (json['y'] as num?)?.toDouble();
    pendingPosition = x == null || y == null ? null : vm.Vector2(x, y);
    return json['scene'] as String? ?? Legends.village;
  }
}

// ---------------------------------------------------------------------------
// Hero

/// The player: 8-way movement, sword swings, potions, talking, pickups,
/// XP and level-ups, pause menu, death and respawn.
class LegendsHero extends GameScript {
  static const double swingTime = 0.3;

  double _swing = 0;
  bool _struck = false;
  double _dying = 0;
  bool _dead = false;
  double _bannerTime = 0;
  double _time = 0;
  bool _paused = false;

  HealthComponent? get _health => getComponent<HealthComponent>();
  TopDownController2DComponent? get _mover => getComponent<TopDownController2DComponent>();

  bool get isSwinging => _swing > 0;
  bool get paused => _paused;

  static String placeName(String scene) => switch (scene) {
        Legends.village => 'Oakvale Village',
        Legends.field => 'Whispering Field',
        Legends.dungeon => 'The Ember Depths',
        _ => scene,
      };

  @override
  void onStart() {
    final health = _health;
    if (health != null) {
      health.maxHealth = LegendsSession.maxHp;
      health.health = LegendsSession.hp.clamp(1, LegendsSession.maxHp).toDouble();
    }
    final pending = LegendsSession.pendingPosition;
    final t = getComponent<Transform2DComponent>();
    if (pending != null && t != null) {
      final c = Legends.centerOf(entity!);
      t.position = t.position + (pending - c);
      LegendsSession.pendingPosition = null;
    }
    final name = scene?.name ?? '';
    AudioSystem.instance.playMusic(name == Legends.dungeon ? Legends.dungeonMusic : Legends.music, volume: 0.4);
    _showMenu(false);
    banner(placeName(name), seconds: 1.8);
    _updateHud();
  }

  @override
  void onUpdate(double dt) {
    final self = entity;
    final mover = _mover;
    final health = _health;
    if (self == null || mover == null || health == null) return;
    _time += dt;
    if (_bannerTime > 0) {
      _bannerTime -= dt;
      if (_bannerTime <= 0) banner('');
    }

    if (_dead) {
      mover.move(vm.Vector2.zero(), dt);
      _dying += dt;
      if (_dying > 2.6) {
        _dead = false; // only once
        if (SaveSlots.exists(Legends.saveSlot)) {
          Legends.continueGame();
        } else {
          Legends.newGame();
        }
      }
      return;
    }

    // Movement (slowed while swinging)
    final input = vm.Vector2(Input.getAxis('horizontal'), -Input.getAxis('vertical'));
    if (_swing > 0) {
      _swing -= dt;
      if (!_struck && _swing <= swingTime - 0.05) {
        _struck = true;
        _strike(self, mover);
      }
      mover.move(input * 0.2, dt);
      mover.facing = _swingFacing;
    } else {
      mover.move(input, dt);
      if (_attackPressed) _startSwing(mover);
    }

    if (Input.isActionJustPressed(EngineAction.interact)) {
      final s = scene;
      if (s != null) Interaction.interact(s, self, range: 22);
    }
    if (Input.isKeyJustPressed(LogicalKeyboardKey.keyQ)) drinkPotion();

    _animate(mover, health);
    LegendsSession.hp = health.health;
    _updateHud();
  }

  static bool get _attackPressed =>
      Input.isActionJustPressed(EngineAction.jump) ||
      Input.isActionJustPressed(EngineAction.fire) ||
      Input.isKeyJustPressed(LogicalKeyboardKey.keyJ) ||
      Input.isMouseButtonJustPressed(0);

  Facing _swingFacing = Facing.down;

  void _startSwing(TopDownController2DComponent mover) {
    _swing = swingTime;
    _struck = false;
    _swingFacing = mover.facing;
    AudioSystem.instance.playProcedural('laser', volume: 0.25, pitch: 0.5);
  }

  /// The sword's hit box in front of the hero.
  Rect swordArea() {
    final self = entity!;
    final c = Combat.bodyOf(self).center;
    final f = _mover?.facingVector ?? vm.Vector2(0, 1);
    final horizontal = f.x != 0;
    final center = Offset(c.dx + f.x * 22, c.dy + f.y * 20 - 4);
    return Rect.fromCenter(center: center, width: horizontal ? 32 : 40, height: horizontal ? 40 : 32);
  }

  void _strike(EmberEntity self, TopDownController2DComponent mover) {
    final s = scene;
    if (s == null) return;
    final hits = Combat.strike(s, swordArea(), team: 'player', damage: LegendsSession.attack, source: self, knockback: 260);
    if (hits.isNotEmpty) AudioSystem.instance.playProcedural('hit', volume: 0.7, pitch: 1.3);
    // Slash effect
    final f = mover.facingVector;
    final c = Legends.centerOf(self);
    final sprite = FlameSpriteComponent(assetPath: '${Legends.art}/slash.png');
    final slash = EmberEntity(name: 'Slash')
      ..addComponent(Transform2DComponent(
        position: c + vm.Vector2(f.x * 20, f.y * 18 - 4),
        size: vm.Vector2(30, 30),
        anchor: EmberAnchor.center,
        rotation: math.atan2(f.y, f.x),
        zIndex: 7,
      ))
      ..addComponent(sprite);
    spawn(slash);
    EmberTween.run(0.14, (t) => sprite.opacity = 1 - t, onComplete: () => s.destroyLater(slash));
  }

  void _animate(TopDownController2DComponent mover, HealthComponent health) {
    final dir = switch (mover.facing) { Facing.down => 'down', Facing.up => 'up', _ => 'side' };
    final action = _swing > 0 ? 'attack' : (mover.isMoving ? 'walk' : 'idle');
    getComponent<SpriteAnimatorComponent>()?.play('${action}_$dir');
    final sprite = getComponent<FlameSpriteComponent>();
    if (sprite != null) {
      final left = mover.facing == Facing.left;
      if (sprite.flipX != left) sprite.flipX = left;
      final blink = health.isInvulnerable && (_time * 16).floor().isOdd;
      sprite.opacity = blink ? 0.35 : 1.0;
    }
  }

  void drinkPotion() {
    final health = _health;
    if (health == null || health.health >= health.maxHealth) return;
    if (!LegendsSession.inventory.take('Potion')) {
      banner('No potions! (Merchant sells them)', seconds: 1.5);
      return;
    }
    health.heal(3);
    AudioSystem.instance.playProcedural('coin', volume: 0.7, pitch: 0.7);
    Legends.puff(scene!, Legends.centerOf(entity!), const Color(0xFFF87171), const Color(0x00FFFFFF), count: 10);
  }

  // --- Combat events ---

  @override
  void onDamaged(double amount, EmberEntity? source) {
    AudioSystem.instance.playProcedural('hit', volume: 0.9, pitch: 0.7);
    LegendsSession.hp = _health?.health ?? LegendsSession.hp;
  }

  @override
  void onDeath(EmberEntity? killer) {
    _dead = true;
    _dying = 0;
    LegendsSession.hp = LegendsSession.maxHp;
    AudioSystem.instance.stopMusic();
    AudioSystem.instance.playProcedural('explosion', volume: 0.6, pitch: 0.6);
    banner('YOU HAVE FALLEN...');
    getComponent<FlameSpriteComponent>()?.opacity = 0.5;
  }

  @override
  void onKill(EmberEntity victim) {
    final xp = victim.getComponent<MonsterAIComponent>()?.xpReward.round() ?? 0;
    if (LegendsSession.addXp(xp)) {
      final health = _health;
      if (health != null) {
        health.maxHealth = LegendsSession.maxHp;
        health.heal(LegendsSession.maxHp);
      }
      AudioSystem.instance.playProcedural('coin', volume: 0.9, pitch: 1.5);
      banner('LEVEL UP!  Lv ${LegendsSession.level}', seconds: 1.6);
    }
    if (victim.tags.contains('boss')) {
      LegendsSession.bossDefeated = true;
      banner('THE EMBER GOLEM IS DEFEATED!', seconds: 4);
    }
  }

  @override
  void onTriggerEnter(EmberEntity other) {
    if (_dead || !other.tags.contains('pickup')) return;
    for (final tag in other.tags) {
      if (tag.startsWith('gold:')) {
        LegendsSession.inventory.addGold(int.tryParse(tag.substring(5)) ?? 1);
        AudioSystem.instance.playProcedural('coin', volume: 0.5, pitch: 1.2);
      } else if (tag.startsWith('heal:')) {
        _health?.heal(double.tryParse(tag.substring(5)) ?? 1);
        AudioSystem.instance.playProcedural('coin', volume: 0.6, pitch: 0.8);
      } else if (tag.startsWith('item:')) {
        LegendsSession.inventory.add(tag.substring(5));
        AudioSystem.instance.playProcedural('coin', volume: 0.7, pitch: 1.0);
        banner('Got a ${tag.substring(5)}! (Q to use)', seconds: 1.5);
      }
    }
    destroy(other);
  }

  // --- Menus ---

  @override
  void onUIAction(String action) {
    switch (action) {
      case 'pause':
        _setPaused(!_paused);
      case 'resume':
        _setPaused(false);
      case 'save':
        if (entity != null && !_dead) Legends.save(entity!);
        banner('Game saved.', seconds: 1.2);
        _setPaused(false);
      case 'title':
        _setPaused(false);
        EmberEngine.instance.loadLevel(Legends.title);
    }
  }

  void _setPaused(bool value) {
    if (_dead && value) return;
    _paused = value;
    EmberEngine.instance.timeScale = value ? 0 : 1;
    _showMenu(value);
    if (value) {
      banner('PAUSED');
    } else if (_bannerTime <= 0) {
      banner('');
    }
  }

  void _showMenu(bool show) {
    for (final name in ['Menu Resume', 'Menu Save', 'Menu Title']) {
      find(name)?.enabled = show;
    }
  }

  // --- HUD ---

  void banner(String text, {double seconds = 0}) {
    find('Banner')?.getComponent<UITextComponent>()?.text = text;
    _bannerTime = seconds;
  }

  String get hint {
    final name = scene?.name ?? '';
    if (LegendsSession.bossDefeated) return 'The Golem is gone. Visit the Elder in Oakvale.';
    return switch (name) {
      Legends.village => LegendsSession.metElder ? 'Head east to the field.' : 'Talk to the Elder (E).',
      Legends.field => 'The cave to the north-east leads to the Ember Depths.',
      Legends.dungeon => 'Find and defeat the Ember Golem!',
      _ => '',
    };
  }

  void _updateHud() {
    final health = _health;
    final hearts = find('Hearts')?.getComponent<UIImageComponent>();
    if (hearts != null && health != null) {
      hearts.count = health.maxHealth.round();
      hearts.filled = health.health.ceil();
    }
    final bar = find('XP Bar')?.getComponent<UIBarComponent>();
    if (bar != null) {
      bar.value = LegendsSession.xp.toDouble();
      bar.max = LegendsSession.xpToNext.toDouble();
      bar.label = 'Lv ${LegendsSession.level}';
    }
    final inv = LegendsSession.inventory;
    find('Info')?.getComponent<UITextComponent>()?.text = 'Gold ${inv.gold}    Potions ${inv.count('Potion')}';
    find('Hint')?.getComponent<UITextComponent>()?.text = hint;
  }
}

// ---------------------------------------------------------------------------
// Monsters

/// Loot and a death puff when the monster dies; its brain is the Monster AI component.
class LegendsMonster extends GameScript {
  @override
  void onDamaged(double amount, EmberEntity? source) {
    final s = scene, self = entity;
    if (s == null || self == null) return;
    Legends.puff(s, Legends.centerOf(self), const Color(0xFFFFFFFF), const Color(0x00FFFFFF), count: 5);
  }

  @override
  void onDeath(EmberEntity? killer) {
    final s = scene, self = entity;
    if (s == null || self == null) return;
    final at = Legends.centerOf(self);
    Legends.puff(s, at, const Color(0xFFFDE68A), const Color(0x00F97316), count: 16);
    AudioSystem.instance.playProcedural('explosion', volume: 0.35, pitch: 1.6);
    dropLoot(s, at);
  }

  void dropLoot(EmberScene s, vm.Vector2 at) {
    final r = Legends.rng.nextDouble();
    if (r < 0.65) {
      Legends.spawnPickup(s, 'gold', at, amount: 1 + Legends.rng.nextInt(4));
    } else if (r < 0.85) {
      Legends.spawnPickup(s, 'heart', at);
    } else if (r < 0.9) {
      Legends.spawnPickup(s, 'potion', at);
    }
  }
}

/// The Ember Golem: aimed fireballs (Monster AI) plus fireball rings that get
/// denser when it is hurt. Shows a boss health bar while the hero is near.
class LegendsBoss extends LegendsMonster {
  double _ringTimer = 4;
  bool _awake = false;

  @override
  void onUpdate(double dt) {
    final self = entity, s = scene;
    final ai = getComponent<MonsterAIComponent>();
    final health = getComponent<HealthComponent>();
    if (self == null || s == null || ai == null || health == null || health.isDead) return;
    final hero = s.allEntities.where((e) => e.tags.contains('player')).firstOrNull;
    final near = hero != null && Legends.centerOf(hero).distanceTo(Legends.centerOf(self)) < 300;
    if (near && !_awake) {
      _awake = true;
      AudioSystem.instance.playProcedural('explosion', volume: 0.8, pitch: 0.5);
      final h = hero.getComponent<ScriptComponent>()?.scriptInstance;
      if (h is LegendsHero) h.banner('THE EMBER GOLEM AWAKENS', seconds: 2);
    }
    final bar = find('Boss Bar');
    if (bar != null) {
      bar.enabled = _awake;
      final b = bar.getComponent<UIBarComponent>();
      b?.value = health.health;
      b?.max = health.maxHealth;
    }
    if (!_awake || ai.state == MonsterState.wander || ai.state == MonsterState.returning) return;

    _ringTimer -= dt;
    if (_ringTimer <= 0) {
      final enraged = health.health < health.maxHealth / 2;
      _ringTimer = enraged ? 3 : 4.5;
      final n = enraged ? 12 : 8;
      final c = Legends.centerOf(self);
      final offset = Legends.rng.nextDouble();
      for (var i = 0; i < n; i++) {
        final a = (i + offset) / n * math.pi * 2;
        ai.spawnProjectile(s, self, c, vm.Vector2(math.cos(a), math.sin(a)), 'monster');
      }
      AudioSystem.instance.playProcedural('explosion', volume: 0.5, pitch: 0.8);
    }
  }

  @override
  void onDeath(EmberEntity? killer) {
    super.onDeath(killer);
    find('Boss Bar')?.enabled = false;
  }

  @override
  void dropLoot(EmberScene s, vm.Vector2 at) {
    for (var i = 0; i < 6; i++) {
      Legends.spawnPickup(s, 'gold', at, amount: 5);
    }
    Legends.spawnPickup(s, 'heart', at, amount: 3);
  }
}

// ---------------------------------------------------------------------------
// Villagers and objects

class LegendsElder extends GameScript {
  @override
  void onInteract(EmberEntity by) {
    if (LegendsSession.bossDefeated) {
      DialogueSystem.instance.start(DialogueSystem.parse(
        'Elder: You did it! The Ember Golem is no more.\n'
        'Elder: Oakvale is safe thanks to you, hero.\n'
        'Elder: Rest now... or keep hunting monsters in the field!',
      ));
      return;
    }
    LegendsSession.metElder = true;
    DialogueSystem.instance.start(DialogueSystem.parse(
      'Elder: Monsters are pouring out of the Ember Depths!\n'
      'Elder: Deep inside sleeps the Ember Golem. Defeat it and they will scatter.\n'
      'Elder: Slay monsters to grow stronger. Touch the crystal to save and heal.\n'
      'Elder: Go east through the field, then find the cave in the north-east.',
    ));
  }
}

class LegendsMerchant extends GameScript {
  static const int potionPrice = 10;

  @override
  void onInteract(EmberEntity by) {
    final inv = LegendsSession.inventory;
    final text = inv.spend(potionPrice)
        ? (() {
            inv.add('Potion');
            AudioSystem.instance.playProcedural('coin', volume: 0.7);
            return 'Merchant: One potion, fresh! Press Q to drink it when you are hurt.';
          })()
        : 'Merchant: Potions are $potionPrice gold. Monsters in the field drop plenty of coins!';
    DialogueSystem.instance.start(DialogueSystem.parse(text));
  }
}

/// Save point: heals the hero fully and saves the game.
class LegendsCrystal extends GameScript {
  @override
  void onInteract(EmberEntity by) {
    final health = by.getComponent<HealthComponent>();
    if (health != null) {
      health.heal(health.maxHealth);
      LegendsSession.hp = health.health;
    }
    Legends.save(by);
    AudioSystem.instance.playProcedural('coin', volume: 0.8, pitch: 1.8);
    DialogueSystem.instance.start(DialogueSystem.parse('The crystal glows warmly. Your wounds are healed and your journey is saved.'));
  }
}

/// Title screen buttons.
class LegendsTitle extends GameScript {
  @override
  void onStart() {
    AudioSystem.instance.playMusic(Legends.music, volume: 0.4);
    find('Continue')?.enabled = SaveSlots.exists(Legends.saveSlot);
  }

  @override
  void onUIAction(String action) {
    if (action == 'new') Legends.newGame();
    if (action == 'continue') Legends.continueGame();
  }
}

void registerLegendsScripts() {
  ScriptRegistry.register('Legends Hero', () => LegendsHero());
  ScriptRegistry.register('Legends Monster', () => LegendsMonster());
  ScriptRegistry.register('Legends Boss', () => LegendsBoss());
  ScriptRegistry.register('Legends Elder', () => LegendsElder());
  ScriptRegistry.register('Legends Merchant', () => LegendsMerchant());
  ScriptRegistry.register('Legends Crystal', () => LegendsCrystal());
  ScriptRegistry.register('Legends Title', () => LegendsTitle());
}

// ---------------------------------------------------------------------------
// Scenes

/// Builds a scene from a character map (one char per 32px tile).
///
/// Terrain: `.` grass, `,` path, `~` water, `T` tree, `o` rock, `b` bush,
/// `*` flowers, `H` house wall, `R` roof, `D` house door, `f` fence,
/// `=` bridge, `#` dungeon wall, `_` dungeon floor, `t` wall torch, `C` cave.
/// Things (standing on [floorChar]): `@` hero, `E` elder, `M` merchant,
/// `N` villager, `V` save crystal, `s` slime, `v` bat, `k` skeleton archer,
/// `G` Ember Golem, `$` gold, `p` potion, `h` heart. [doors] and [markers]
/// map extra characters to doors (scene, arrival marker) and named spots.
class LegendsLevelBuilder {
  final String name;
  final List<String> map;
  final String floorChar;
  final Map<String, (String, String)> doors;
  final Map<String, String> markers;
  final Color background;

  LegendsLevelBuilder(
    this.name,
    this.map, {
    this.floorChar = '.',
    this.doors = const {},
    this.markers = const {},
    this.background = const Color(0xFF14532D),
  }) {
    final w = map.first.length;
    for (var r = 0; r < map.length; r++) {
      if (map[r].length != w) throw ArgumentError('$name row $r is ${map[r].length} wide, expected $w');
    }
  }

  int get columns => map.first.length;
  int get rows => map.length;

  static const Map<String, (int, int)> terrain = {
    '.': (Legends.grass, 0),
    ',': (Legends.path, 0),
    '~': (Legends.water, Legends.water),
    'T': (Legends.grass, Legends.tree),
    'o': (Legends.grass, Legends.rock),
    'b': (Legends.grass, Legends.bush),
    '*': (Legends.grass, Legends.flower),
    'H': (Legends.grass, Legends.houseWall),
    'R': (Legends.grass, Legends.roof),
    'D': (Legends.grass, Legends.houseDoor),
    'f': (Legends.grass, Legends.fence),
    '=': (Legends.bridge, 0),
    '#': (Legends.floor, Legends.wall),
    '_': (Legends.floor, 0),
    't': (Legends.floor, Legends.torch),
    'C': (Legends.grass, Legends.cave),
    'S': (Legends.bridge, 0),
  };

  (int, int) _tilesAt(String ch) => terrain[ch] ?? terrain[floorChar]!;

  vm.Vector2 _center(int c, int r) => vm.Vector2((c + 0.5) * Legends.tile, (r + 0.5) * Legends.tile);

  EmberScene build({bool withHero = true, bool withHud = true, bool withNpcs = true}) {
    final scene = EmberScene(name: name);
    final ground = List<int>.filled(columns * rows, 0);
    final obstacles = List<int>.filled(columns * rows, 0);
    final worldW = columns * Legends.tile, worldH = rows * Legends.tile;

    scene.addEntity(EmberEntity(name: 'Camera')
      ..addComponent(Transform2DComponent(position: vm.Vector2(worldW / 2, worldH / 2), size: vm.Vector2.zero()))
      ..addComponent(Camera2DComponent(
        designWidth: 640,
        designHeight: 360,
        followTarget: withHero ? 'Hero' : '',
        smoothing: 0.8,
        deadZone: vm.Vector2(24, 16),
        boundsEnabled: true,
        boundsMin: vm.Vector2.zero(),
        boundsMax: vm.Vector2(worldW, worldH),
        backgroundColor: background,
      )));

    final things = <(String, int, int)>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final ch = map[r][c];
        final (g, o) = _tilesAt(ch);
        ground[r * columns + c] = g;
        obstacles[r * columns + c] = o;
        if (!terrain.containsKey(ch) || ch == 'C' || ch == 'S') things.add((ch, c, r));
      }
    }

    scene.addEntity(EmberEntity(name: 'Ground')
      ..addComponent(Transform2DComponent(size: vm.Vector2.zero(), zIndex: -20))
      ..addComponent(_tilemap(ground, collision: false)));
    scene.addEntity(EmberEntity(name: 'Obstacles')
      ..addComponent(Transform2DComponent(size: vm.Vector2.zero(), zIndex: -19))
      ..addComponent(_tilemap(obstacles, collision: true)));

    final counts = <String, int>{};
    String numbered(String base) => '${base}_${counts[base] = (counts[base] ?? 0) + 1}';
    for (final (ch, c, r) in things) {
      final at = _center(c, r);
      final door = doors[ch];
      if (door != null) {
        scene.addEntity(EmberEntity(name: numbered('Door to ${door.$1}'))
          ..addComponent(Transform2DComponent(position: at, size: vm.Vector2(32, 32), anchor: EmberAnchor.center))
          ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(32, 32), isSolid: false, debugDraw: false))
          ..addComponent(DoorComponent(targetLevel: door.$1, spawnAt: door.$2)));
        continue;
      }
      final marker = markers[ch];
      if (marker != null) {
        scene.addEntity(EmberEntity(name: marker)
          ..addComponent(Transform2DComponent(position: at, size: vm.Vector2(32, 32), anchor: EmberAnchor.center)));
        continue;
      }
      switch (ch) {
        case '@' when withHero:
          scene.addEntity(hero(at));
        case 'E' when withNpcs:
          scene.addEntity(_npc('Elder', 'elder.png', at)..addComponent(ScriptComponent(scriptName: 'Legends Elder')));
        case 'M' when withNpcs:
          scene.addEntity(_npc('Merchant', 'merchant.png', at)..addComponent(ScriptComponent(scriptName: 'Legends Merchant')));
        case 'N' when withNpcs:
          scene.addEntity(_npc('Villager', 'merchant.png', at)
            ..addComponent(DialogueComponent(
              lines: 'Villager: They say the cave in the north-east leads to the Ember Depths.\n'
                  'Villager: Skeleton archers down there shoot from afar. Keep moving!',
            )));
        case 'V' when withNpcs:
          scene.addEntity(EmberEntity(name: 'Save Crystal')
            ..addComponent(Transform2DComponent(position: at, size: vm.Vector2(32, 32), anchor: EmberAnchor.center, zIndex: 2))
            ..addComponent(FlameSpriteComponent(assetPath: '${Legends.art}/crystal.png', columns: 2))
            ..addComponent(SpriteAnimatorComponent(clips: 'idle=0-1@2'))
            ..addComponent(ScriptComponent(scriptName: 'Legends Crystal')));
        case 's' || 'v' || 'k' || 'G':
          scene.addEntity(monster(ch, at, numbered(_monsterName(ch))));
        case '\$':
          scene.addEntity(_pickupEntity('gold', at, numbered('Gold')));
        case 'p':
          scene.addEntity(_pickupEntity('potion', at, numbered('Potion')));
        case 'h':
          scene.addEntity(_pickupEntity('heart', at, numbered('Heart')));
      }
    }

    // Maps without an '@' start the hero on their first arrival marker (doors
    // move it to the right one anyway)
    if (withHero && !things.any((t) => t.$1 == '@')) {
      final first = things.where((t) => markers.containsKey(t.$1)).firstOrNull;
      if (first != null) scene.addEntity(hero(_center(first.$2, first.$3)));
    }

    if (withHud) _addHud(scene, boss: things.any((t) => t.$1 == 'G'));
    return scene;
  }

  FlameTileMapComponent _tilemap(List<int> tiles, {required bool collision}) => FlameTileMapComponent(
        columns: columns,
        rows: rows,
        tileSize: Legends.tile,
        tiles: tiles,
        tilesetPath: '${Legends.art}/tiles.png',
        tilesetColumns: 8,
        tilesetTileSize: 16,
        tileKinds: Map.of(Legends.tileKinds),
        collision: collision,
      );

  static String _monsterName(String ch) => switch (ch) { 's' => 'Slime', 'v' => 'Bat', 'k' => 'Skeleton Archer', _ => 'Ember Golem' };

  static EmberEntity hero(vm.Vector2 at) => EmberEntity(name: 'Hero', tags: {'player'})
    ..addComponent(Transform2DComponent(position: at, size: vm.Vector2(32, 32), anchor: EmberAnchor.center, zIndex: 5))
    ..addComponent(FlameSpriteComponent(assetPath: '${Legends.art}/hero.png', columns: 4, rows: 3))
    ..addComponent(SpriteAnimatorComponent(
      clips: 'idle_down=0; walk_down=1-2@7; attack_down=3; idle_up=4; walk_up=5-6@7; attack_up=7; '
          'idle_side=8; walk_side=9-10@7; attack_side=11',
      defaultClip: 'idle_down',
    ))
    ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(18, 18), offset: vm.Vector2(7, 13), isSolid: false, debugDraw: false))
    ..addComponent(TopDownController2DComponent(moveSpeed: 125, acceleration: 16))
    ..addComponent(HealthComponent(maxHealth: 5, team: 'player', invulnerableTime: 1.0, destroyOnDeath: false))
    ..addComponent(ScriptComponent(scriptName: 'Legends Hero'));

  static EmberEntity monster(String kind, vm.Vector2 at, String name) {
    final boss = kind == 'G';
    final size = boss ? 64.0 : 32.0;
    final (asset, cols, clips) = switch (kind) {
      's' => ('slime.png', 2, 'idle=0-1@3; walk=0-1@6'),
      'v' => ('bat.png', 2, 'idle=0-1@8; walk=0-1@12'),
      'k' => ('skeleton.png', 3, 'idle=0; walk=0-1@5; attack=2'),
      _ => ('golem.png', 3, 'idle=0-1@2; walk=0-1@4; attack=2'),
    };
    final (hbSize, hbOffset) = switch (kind) {
      's' => (vm.Vector2(22, 16), vm.Vector2(5, 13)),
      'v' => (vm.Vector2(20, 14), vm.Vector2(6, 6)),
      'k' => (vm.Vector2(18, 20), vm.Vector2(7, 11)),
      _ => (vm.Vector2(44, 36), vm.Vector2(10, 26)),
    };
    final (speed, hp) = switch (kind) { 's' => (45.0, 2.0), 'v' => (85.0, 1.0), 'k' => (45.0, 3.0), _ => (38.0, 30.0) };
    final ai = switch (kind) {
      's' => MonsterAIComponent(sightRange: 120, attackRange: 6, windup: 0.3, attackCooldown: 1.0, xpReward: 3, wanderRadius: 48, knockbackPower: 160),
      'v' => MonsterAIComponent(sightRange: 150, attackRange: 4, windup: 0.1, attackCooldown: 0.8, xpReward: 4, wanderRadius: 96, knockbackPower: 140),
      'k' => MonsterAIComponent(
          sightRange: 190, attackRange: 150, loseRange: 320, windup: 0.45, attackCooldown: 1.8, ranged: true,
          projectileSpeed: 170, projectileAsset: '${Legends.art}/arrow.png', xpReward: 8, wanderRadius: 32),
      _ => MonsterAIComponent(
          sightRange: 260, attackRange: 220, loseRange: 420, windup: 0.6, attackCooldown: 1.6, ranged: true, touchDamage: 2,
          projectileSpeed: 150, projectileAsset: '${Legends.art}/fireball.png', wander: false, xpReward: 60, knockbackPower: 260),
    };
    return EmberEntity(name: name, tags: {'monster', if (boss) 'boss'})
      ..addComponent(Transform2DComponent(position: at, size: vm.Vector2(size, size), anchor: EmberAnchor.center, zIndex: 4))
      ..addComponent(FlameSpriteComponent(assetPath: '${Legends.art}/$asset', columns: cols))
      ..addComponent(SpriteAnimatorComponent(clips: clips))
      ..addComponent(FlameHitbox2DComponent(size: hbSize, offset: hbOffset, isSolid: false, debugDraw: false))
      ..addComponent(TopDownController2DComponent(moveSpeed: speed, acceleration: 10))
      ..addComponent(HealthComponent(maxHealth: hp, team: 'monster', invulnerableTime: boss ? 0.15 : 0.25))
      ..addComponent(ai)
      ..addComponent(ScriptComponent(scriptName: boss ? 'Legends Boss' : 'Legends Monster'));
  }

  static EmberEntity _npc(String name, String asset, vm.Vector2 at) => EmberEntity(name: name, tags: {'npc'})
    ..addComponent(Transform2DComponent(position: at, size: vm.Vector2(32, 32), anchor: EmberAnchor.center, zIndex: 3))
    ..addComponent(FlameSpriteComponent(assetPath: '${Legends.art}/$asset', columns: 2))
    ..addComponent(SpriteAnimatorComponent(clips: 'idle=0-1@2'));

  static EmberEntity _pickupEntity(String kind, vm.Vector2 at, String name) {
    final (asset, cols, tag) = switch (kind) {
      'gold' => ('coin.png', 4, 'gold:5'),
      'heart' => ('heart.png', 2, 'heal:1'),
      _ => ('potion.png', 1, 'item:Potion'),
    };
    final e = EmberEntity(name: name, tags: {'pickup', tag})
      ..addComponent(Transform2DComponent(position: at, size: vm.Vector2(20, 20), anchor: EmberAnchor.center, zIndex: 1))
      ..addComponent(FlameSpriteComponent(assetPath: '${Legends.art}/$asset', columns: cols))
      ..addComponent(FlameHitbox2DComponent(size: vm.Vector2(18, 18), offset: vm.Vector2(1, 1), isSolid: false, debugDraw: false));
    if (kind == 'gold') e.addComponent(SpriteAnimatorComponent(clips: 'spin=0-3@8', defaultClip: 'spin'));
    return e;
  }

  static void _addHud(EmberScene scene, {required bool boss}) {
    scene.addEntity(EmberEntity(name: 'Hearts')
      ..addComponent(UIImageComponent(
        assetPath: '${Legends.art}/heart.png',
        columns: 2,
        frame: 0,
        emptyFrame: 1,
        count: 5,
        spacing: 2,
        offset: vm.Vector2(12, 10),
        size: vm.Vector2(18, 18),
      )));
    scene.addEntity(EmberEntity(name: 'XP Bar')
      ..addComponent(UIBarComponent(
        value: 0,
        max: 12,
        fillColor: const Color(0xFFFACC15),
        label: 'Lv 1',
        offset: vm.Vector2(12, 34),
        size: vm.Vector2(128, 12),
      )));
    scene.addEntity(EmberEntity(name: 'Info')
      ..addComponent(UITextComponent(text: '', fontSize: 13, anchor: EmberAnchor.topLeft, offset: vm.Vector2(12, 50))));
    scene.addEntity(EmberEntity(name: 'Hint')
      ..addComponent(UITextComponent(text: '', fontSize: 12, anchor: EmberAnchor.bottomCenter, offset: vm.Vector2(0, -10), color: const Color(0xFFFDE68A))));
    scene.addEntity(EmberEntity(name: 'Banner')
      ..addComponent(UITextComponent(text: '', fontSize: 26, anchor: EmberAnchor.center, offset: vm.Vector2(0, -60))));
    if (boss) {
      scene.addEntity(EmberEntity(name: 'Boss Bar', enabled: false)
        ..addComponent(UIBarComponent(
          value: 30,
          max: 30,
          fillColor: const Color(0xFFF97316),
          label: 'EMBER GOLEM',
          anchor: EmberAnchor.topCenter,
          offset: vm.Vector2(0, 14),
          size: vm.Vector2(260, 14),
        )));
    }
    scene.addEntity(EmberEntity(name: 'Pause Button')
      ..addComponent(UIButtonComponent(
        text: 'II',
        action: 'pause',
        hotkey: 'Escape',
        fontSize: 14,
        anchor: EmberAnchor.topRight,
        offset: vm.Vector2(-10, 10),
        size: vm.Vector2(36, 28),
      )));
    for (final (name, text, action, y) in [
      ('Menu Resume', 'Resume', 'resume', -10.0),
      ('Menu Save', 'Save Game', 'save', 40.0),
      ('Menu Title', 'Quit to Title', 'title', 90.0),
    ]) {
      scene.addEntity(EmberEntity(name: name, enabled: false)
        ..addComponent(UIButtonComponent(text: text, action: action, offset: vm.Vector2(0, y), size: vm.Vector2(190, 40))));
    }
  }
}

const _villageMap = [
  'TTTTTTTTTTTTTTTTTTTTTTTTTTTTTT',
  'T............................T',
  'T..RRRRR.......*.......RRRRR.T',
  'T..HHDHH...............HHDHH.T',
  'T....,..................,....T',
  'T....,,,,,,,,,,,,,,,,,,,,,...T',
  'T.*.........,.......*........T',
  'T...........,..E.............T',
  'T..ff.......,...V..N.........T',
  'T..ff.......,,,,,,,,,,,,,,,,,>',
  'T...........,........M......a>',
  'T..*........,..b..b..........T',
  'T...........,................T',
  'T....o......,,,,,,,,,....*...T',
  'T...........@................T',
  'T~~~~~.............bb........T',
  'T~~~~~~~.....................T',
  'T~~~~~~~~~......*.......o....T',
  'T~~~~~~~~~~..................T',
  'TTTTTTTTTTTTTTTTTTTTTTTTTTTTTT',
];

const _fieldMap = [
  'TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT',
  'T.......T.........o.........TTTTTCCTTTTT',
  'T..s....T...................TT.....TTTTT',
  'T.......TT.......v...........T...c..,TTT',
  'T...........,,,,,,,,,,,,,,,,,,,,,,,,,TTT',
  'T...b.......,.......................bTTT',
  'T...........,...s.........v...........TT',
  'T....oo.....,..........................T',
  'T...........,.......~~~~~~~.....s......T',
  'T...........,......~~~~~~~~~...........T',
  'T.....s.....,.....~~~~~~~~~~~..........T',
  'T...........,.....~~~~~~~~~~~....v.....T',
  'T...........,,,,,,===========,,,,,,,,..T',
  '<a..........,.....~~~~~~~~~~~....s.....T',
  '<,,,,,,,,,,,,.....~~~~~~~~~~~..........T',
  'T.........b.......~~~~~~~~~.......v....T',
  'T..s................~~~~~..............T',
  'T.......oo.............................T',
  'T......................s.......TT......T',
  'T....*.........T..............TTT....s.T',
  'T.........s....TT.....v........T.......T',
  'T...........................*..........T',
  'T....oo.......s............b....s......T',
  'T..................p...................T',
  'T..*.......T............v.......*......T',
  'T.......TTTT.........................\$.T',
  'T......................................T',
  'TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT',
];

const _dungeonMap = [
  '################################',
  '########t######t######t#########',
  '#######__________________#######',
  '#######__________________#######',
  '#######________G_________#######',
  '#######__________________#######',
  '#######__________________#######',
  '#######__________________#######',
  '#######__________________#######',
  '###############__###############',
  '#t________#####__#####________t#',
  '#_________#####__#####_________#',
  '#___k_____#####__#####_____k___#',
  '#_________#####__#####_________#',
  '#_____________v____v___________#',
  '#_s_______#####__#####______s__#',
  '#_________#####__#####_________#',
  '#####__########__########__#####',
  '#___s__________________k_______#',
  '#______________________________#',
  '#t____________________________t#',
  '#___p__________________v_______#',
  '#______________a_______________#',
  '#______________SS______________#',
  '################################',
];

EmberScene buildLegendsVillage() => LegendsLevelBuilder(
      Legends.village,
      _villageMap,
      doors: const {'>': (Legends.field, 'From Village')},
      markers: const {'a': 'From Field'},
    ).build();

EmberScene buildLegendsField() => LegendsLevelBuilder(
      Legends.field,
      _fieldMap,
      doors: const {'<': (Legends.village, 'From Field'), 'C': (Legends.dungeon, 'From Field')},
      markers: const {'a': 'From Village', 'c': 'From Cave'},
    ).build();

EmberScene buildLegendsDungeon() => LegendsLevelBuilder(
      Legends.dungeon,
      _dungeonMap,
      floorChar: '_',
      doors: const {'S': (Legends.field, 'From Cave')},
      markers: const {'a': 'From Field'},
      background: const Color(0xFF0C0A09),
    ).build();

/// Title screen over the village, with a couple of slimes wandering about.
EmberScene buildLegendsTitle() {
  final map = [for (final row in _villageMap) row.replaceAll(RegExp('[@>a]'), '.')];
  for (final (r, c) in [(12, 18), (16, 18), (11, 24)]) {
    map[r] = map[r].replaceRange(c, c + 1, 's');
  }
  final scene = LegendsLevelBuilder(Legends.title, map).build(withHero: false, withHud: false, withNpcs: true);
  scene.addEntity(EmberEntity(name: 'Title Menu')..addComponent(ScriptComponent(scriptName: 'Legends Title')));
  scene.addEntity(EmberEntity(name: 'Title Text')
    ..addComponent(UITextComponent(text: 'EMBER LEGENDS', fontSize: 46, anchor: EmberAnchor.center, offset: vm.Vector2(0, -95), color: const Color(0xFFFBBF24))));
  scene.addEntity(EmberEntity(name: 'Subtitle')
    ..addComponent(UITextComponent(text: 'Slay the monsters. Defeat the Ember Golem.', fontSize: 15, anchor: EmberAnchor.center, offset: vm.Vector2(0, -52))));
  scene.addEntity(EmberEntity(name: 'New Game')
    ..addComponent(UIButtonComponent(text: 'New Game', action: 'new', hotkey: 'Enter', offset: vm.Vector2(0, 5), size: vm.Vector2(200, 42))));
  scene.addEntity(EmberEntity(name: 'Continue')
    ..addComponent(UIButtonComponent(
      text: 'Continue',
      action: 'continue',
      hotkey: 'C',
      color: const Color(0xFF14B8A6),
      offset: vm.Vector2(0, 57),
      size: vm.Vector2(200, 42),
    )));
  scene.addEntity(EmberEntity(name: 'Controls')
    ..addComponent(UITextComponent(
      text: 'WASD / Arrows move   ·   Space / J / Click attack   ·   E talk   ·   Q potion   ·   Esc pause',
      fontSize: 12,
      anchor: EmberAnchor.bottomCenter,
      offset: vm.Vector2(0, -12),
      color: const Color(0xFFE5E7EB),
    )));
  return scene;
}

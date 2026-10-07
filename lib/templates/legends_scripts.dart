/// Ember Legends' gameplay as Ember Script. New projects get these as
/// editable `.ember` files (Script workspace). Monster brains are the engine's
/// Monster AI component; these scripts add the game on top.
library;

const legendsScripts = <String, String>{
  'legends_hero.ember': _hero,
  'legends_monster.ember': _monster,
  'legends_boss.ember': _boss,
  'legends_elder.ember': _elder,
  'legends_merchant.ember': _merchant,
  'legends_crystal.ember': _crystal,
  'legends_title.ember': _title,
  'legends_effect.ember': _effect,
};

/// Progress lives in Game.data so it survives level changes. The save slot is
/// the value "legends_save" (see save() in the hero script).
const _hero = r'''
// The player: 8-way movement, sword swings, potions, talking, pickups,
// XP and level-ups, pause menu, death and respawn.
var swingTime = 0.3;
var potionHeal = 3;
var music = "assets/templates/legends/theme.wav";
var dungeonMusic = "assets/templates/legends/dungeon.wav";

var _swing = 0.0;
var _struck = false;
var _swingFacing = "down";
var _dead = false;
var _dying = 0.0;
var _respawned = false;
var _bannerTime = 0.0;
var _time = 0.0;
var paused = false;

// --- Progress (Game.data) ---

session() {
  var d = Game.data;
  if (!d.containsKey("level")) {
    d["level"] = 1;
    d["xp"] = 0;
    d["maxHp"] = 5;
    d["hp"] = 5;
    d["gold"] = 0;
    d["potions"] = 0;
    d["bossDefeated"] = false;
    d["metElder"] = false;
  }
  return d;
}

attackDamage() => 1 + (session()["level"] - 1) * 0.5;
xpToNext() => 6 + session()["level"] * 6;

/// Adds experience; returns true on a level-up.
bool addXp(amount) {
  var s = session();
  s["xp"] += amount;
  var up = false;
  while (s["xp"] >= xpToNext()) {
    s["xp"] -= xpToNext();
    s["level"] += 1;
    s["maxHp"] = min(12, s["maxHp"] + 1);
    s["hp"] = s["maxHp"];
    up = true;
  }
  return up;
}

placeName(scene) {
  if (scene == "Village") return "Oakvale Village";
  if (scene == "Field") return "Whispering Field";
  if (scene == "Dungeon") return "The Ember Depths";
  return scene;
}

// --- Events ---

void onStart() {
  var s = session();
  self.health.maxHealth = s["maxHp"];
  self.health.health = clamp(s["hp"], 1, s["maxHp"]);
  if (s.containsKey("pendingX")) {
    self.center = vec(s["pendingX"], s["pendingY"]);   // continuing a saved game
    s.remove("pendingX");
    s.remove("pendingY");
  }
  playMusic(Game.level == "Dungeon" ? dungeonMusic : music, 0.4);
  showMenu(false);
  banner(placeName(Game.level), 1.8);
  updateHud();
}

void onUpdate(dt) {
  _time += dt;
  if (_bannerTime > 0) {
    _bannerTime -= dt;
    if (_bannerTime <= 0) banner("");
  }

  if (_dead) {
    self.mover.move(vec(0, 0));
    _dying += dt;
    if (_dying > 2.6 && !_respawned) {
      _respawned = true;
      if (loadValue("legends_save", null) != null) {
        continueGame();
      } else {
        newGame();
      }
    }
    return;
  }

  // Movement (slowed while swinging)
  var input = Input.move;
  if (_swing > 0) {
    _swing -= dt;
    if (!_struck && _swing <= swingTime - 0.05) {
      _struck = true;
      strikeNow();
    }
    self.mover.move(input * 0.2);
    self.mover.facing = _swingFacing;
  } else {
    self.mover.move(input);
    if (attackPressed()) startSwing();
  }

  if (Input.actionPressed("interact")) self.interact(22);
  if (Input.pressed("Q")) drinkPotion();

  animate();
  session()["hp"] = self.health.health;
  updateHud();
}

bool attackPressed() => Input.actionPressed("jump") || Input.actionPressed("fire") || Input.pressed("J") || Input.click;

facingVector() {
  var f = self.mover.facing;
  if (f == "up") return vec(0, -1);
  if (f == "left") return vec(-1, 0);
  if (f == "right") return vec(1, 0);
  return vec(0, 1);
}

// --- Sword ---

void startSwing() {
  _swing = swingTime;
  _struck = false;
  _swingFacing = self.mover.facing;
  playSound("laser", volume: 0.25, pitch: 0.5);
}

/// The sword's hit box in front of the hero: [center, width, height].
swordArea() {
  var f = facingVector();
  var horizontal = f.x != 0;
  var center = self.center + vec(f.x * 22, f.y * 20 - 4);
  return [center, horizontal ? 32 : 40, horizontal ? 40 : 32];
}

void strikeNow() {
  var area = swordArea();
  var hits = strike(area[0], area[1], area[2], damage: attackDamage(), knockback: 260, team: "player");
  if (hits.isNotEmpty) playSound("hit", volume: 0.7, pitch: 1.3);

  // Slash effect: a copy of the hidden "Slash Template", fading out
  var f = facingVector();
  var slash = spawn("Slash Template", self.center + vec(f.x * 20, f.y * 18 - 4));
  slash.rotation = atan2(f.y, f.x);
  tween(0.14, (t) { slash.sprite.opacity = 1 - t; }, ease: "linear", then: () => destroy(slash));
}

void animate() {
  var f = self.mover.facing;
  var dir = f == "down" ? "down" : (f == "up" ? "up" : "side");
  var action = _swing > 0 ? "attack" : (self.mover.moving ? "walk" : "idle");
  self.animator.play("${action}_$dir");
  self.sprite.flipX = f == "left";
  var blink = self.health.invulnerable && (_time * 16).floor().isOdd;
  self.sprite.opacity = blink ? 0.35 : 1.0;
}

void drinkPotion() {
  var s = session();
  if (self.health.health >= self.health.maxHealth) return;
  if (s["potions"] <= 0) {
    banner("No potions! (Merchant sells them)", 1.5);
    return;
  }
  s["potions"] -= 1;
  self.health.heal(potionHeal);
  playSound("coin", volume: 0.7, pitch: 0.7);
  puff(self.center, "#F87171", 10);
}

// --- Combat events ---

void onDamaged(amount, source) {
  playSound("hit", volume: 0.9, pitch: 0.7);
  session()["hp"] = self.health.health;
}

void onDeath(killer) {
  _dead = true;
  _dying = 0;
  session()["hp"] = session()["maxHp"];
  stopMusic();
  playSound("explosion", volume: 0.6, pitch: 0.6);
  banner("YOU HAVE FALLEN...");
  self.sprite.opacity = 0.5;
}

void onKill(victim) {
  var xp = victim.has("Monster AI") ? victim.ai.xpReward.round() : 0;
  if (addXp(xp)) {
    self.health.maxHealth = session()["maxHp"];
    self.health.heal(session()["maxHp"]);
    playSound("coin", volume: 0.9, pitch: 1.5);
    banner("LEVEL UP!  Lv ${session()["level"]}", 1.6);
  }
  if (victim.hasTag("boss")) {
    session()["bossDefeated"] = true;
    banner("THE EMBER GOLEM IS DEFEATED!", 4);
  }
}

void onTriggerEnter(other) {
  if (_dead || !other.hasTag("pickup")) return;
  var s = session();
  for (var tag in other.tags) {
    if (tag.startsWith("gold:")) {
      s["gold"] += tag.substring(5).toNumber();
      playSound("coin", volume: 0.5, pitch: 1.2);
    } else if (tag.startsWith("heal:")) {
      self.health.heal(tag.substring(5).toNumber());
      playSound("coin", volume: 0.6, pitch: 0.8);
    } else if (tag == "item:Potion") {
      s["potions"] += 1;
      playSound("coin", volume: 0.7);
      banner("Got a Potion! (Q to use)", 1.5);
    }
  }
  destroy(other);
}

// --- Saving ---

void save() {
  var s = session();
  saveValue("legends_save", {
    "scene": Game.level,
    "x": self.center.x,
    "y": self.center.y,
    "level": s["level"],
    "xp": s["xp"],
    "maxHp": s["maxHp"],
    "gold": s["gold"],
    "potions": s["potions"],
    "bossDefeated": s["bossDefeated"],
    "metElder": s["metElder"],
  });
}

/// Loads the save (at full health), or starts a new game if there is none.
void continueGame() {
  var d = loadValue("legends_save", null);
  if (d == null) return newGame();
  var s = Game.data;
  s.clear();
  for (var key in ["level", "xp", "maxHp", "gold", "potions", "bossDefeated", "metElder"]) s[key] = d[key];
  s["hp"] = d["maxHp"];
  s["pendingX"] = d["x"];
  s["pendingY"] = d["y"];
  loadLevel(d["scene"]);
}

void newGame() {
  Game.data.clear();
  loadLevel("Village");
}

// --- Menus ---

void onUIAction(action) {
  if (action == "pause") {
    setPaused(!paused);
  } else if (action == "resume") {
    setPaused(false);
  } else if (action == "save") {
    if (!_dead) save();
    banner("Game saved.", 1.2);
    setPaused(false);
  } else if (action == "title") {
    setPaused(false);
    loadLevel("Title");
  }
}

void setPaused(value) {
  if (_dead && value) return;
  paused = value;
  Game.timeScale = value ? 0 : 1;
  showMenu(value);
  if (value) {
    banner("PAUSED");
  } else if (_bannerTime <= 0) {
    banner("");
  }
}

void showMenu(show) {
  for (var name in ["Menu Resume", "Menu Save", "Menu Title"]) {
    var e = find(name);
    if (e != null) e.enabled = show;
  }
}

// --- HUD ---

void banner(text, [seconds = 0]) {
  setText("Banner", text);
  _bannerTime = seconds;
}

hint() {
  var s = session();
  if (s["bossDefeated"]) return "The Golem is gone. Visit the Elder in Oakvale.";
  if (Game.level == "Village") return s["metElder"] ? "Head east to the field." : "Talk to the Elder (E).";
  if (Game.level == "Field") return "The cave to the north-east leads to the Ember Depths.";
  if (Game.level == "Dungeon") return "Find and defeat the Ember Golem!";
  return "";
}

void updateHud() {
  var s = session();
  var hearts = find("Hearts");
  if (hearts != null) {
    hearts.image.count = self.health.maxHealth.round();
    hearts.image.filled = self.health.health.ceil();
  }
  var bar = find("XP Bar");
  if (bar != null) {
    bar.bar.value = s["xp"];
    bar.bar.max = xpToNext();
    bar.bar.label = "Lv ${s["level"]}";
  }
  setText("Info", "Gold ${s["gold"]}    Potions ${s["potions"]}");
  setText("Hint", hint());
}

// --- Effects ---

void puff(at, color, count) {
  var p = spawn("Puff Template", at);
  p.particles.startColor = color;
  p.script.count = count;
}
''';

const _monster = r'''
// A monster's life and loot. Its brain (wander, chase, attack) is the
// Monster AI component: tune sight range, damage, speed... in the Inspector.
var goldChance = 0.65;
var heartChance = 0.2;
var potionChance = 0.05;

void onDamaged(amount, source) {
  puff(self.center, "#FFFFFF", 5);
}

void onDeath(killer) {
  puff(self.center, "#FDE68A", 16);
  playSound("explosion", volume: 0.35, pitch: 1.6);
  dropLoot(self.center);
}

void dropLoot(at) {
  var r = random();
  if (r < goldChance) {
    dropPickup("gold", at, 1 + randomInt(4));
  } else if (r < goldChance + heartChance) {
    dropPickup("heart", at, 1);
  } else if (r < goldChance + heartChance + potionChance) {
    dropPickup("potion", at, 1);
  }
}

/// A copy of the "Gold/Heart/Potion Template", flying out a little.
dropPickup(kind, at, amount) {
  var template = kind == "gold" ? "Gold Template" : (kind == "heart" ? "Heart Template" : "Potion Template");
  var p = spawn(template, at);
  if (kind == "gold") {
    p.removeTag("gold:5");
    p.addTag("gold:$amount");
  } else if (kind == "heart") {
    p.removeTag("heal:1");
    p.addTag("heal:$amount");
  }
  var angle = random() * pi * 2;
  var to = at + vec(cos(angle), sin(angle)) * randomRange(6, 20);
  if (!solidAt(to, 16)) {
    tween(0.25, (t) { p.center = lerp(at, to, t); }, ease: "out");
  }
  return p;
}

void puff(at, color, count) {
  var p = spawn("Puff Template", at);
  p.particles.startColor = color;
  p.script.count = count;
}
''';

const _boss = r'''
// The Ember Golem: aimed fireballs (its Monster AI) plus rings of fireballs
// that get denser when it is hurt. Shows a boss health bar once awake.
var wakeDistance = 300;
var ringEvery = 4.5;
var enragedRingEvery = 3.0;
var ringSize = 8;
var enragedRingSize = 12;
var goldPiles = 6;

var _ringTimer = 4.0;
var _awake = false;

void onUpdate(dt) {
  if (self.health.dead) return;
  var hero = findNearest("player");
  var near = hero != null && self.distanceTo(hero) < wakeDistance;
  if (near && !_awake) {
    _awake = true;
    playSound("explosion", volume: 0.8, pitch: 0.5);
    hero.call("banner", "THE EMBER GOLEM AWAKENS", 2);
  }
  var bar = find("Boss Bar");
  if (bar != null) {
    bar.enabled = _awake;
    bar.bar.value = self.health.health;
    bar.bar.max = self.health.maxHealth;
  }
  var state = self.ai.state;
  if (!_awake || state == "wander" || state == "returning") return;

  _ringTimer -= dt;
  if (_ringTimer <= 0) {
    var enraged = self.health.health < self.health.maxHealth / 2;
    _ringTimer = enraged ? enragedRingEvery : ringEvery;
    var n = enraged ? enragedRingSize : ringSize;
    var offset = random();
    for (var i = 0; i < n; i++) {
      var a = (i + offset) / n * pi * 2;
      self.ai.shoot(vec(cos(a), sin(a)));
    }
    playSound("explosion", volume: 0.5, pitch: 0.8);
  }
}

void onDamaged(amount, source) {
  puff(self.center, "#FFFFFF", 5);
}

void onDeath(killer) {
  puff(self.center, "#FDE68A", 24);
  playSound("explosion", volume: 0.6, pitch: 1.2);
  var bar = find("Boss Bar");
  if (bar != null) bar.enabled = false;
  for (var i = 0; i < goldPiles; i++) {
    var p = spawn("Gold Template", self.center + vec(randomRange(-24, 24), randomRange(-24, 24)));
    p.removeTag("gold:5");
    p.addTag("gold:5");
  }
  var heart = spawn("Heart Template", self.center);
  heart.removeTag("heal:1");
  heart.addTag("heal:3");
}

void puff(at, color, count) {
  var p = spawn("Puff Template", at);
  p.particles.startColor = color;
  p.script.count = count;
}
''';

const _elder = r'''
// The village Elder: explains the quest, and thanks you at the end.
void onInteract(by) {
  if (Game.data["bossDefeated"] == true) {
    say("Elder: You did it! The Ember Golem is no more.\n"
        "Elder: Oakvale is safe thanks to you, hero.\n"
        "Elder: Rest now... or keep hunting monsters in the field!");
    return;
  }
  Game.data["metElder"] = true;
  say("Elder: Monsters are pouring out of the Ember Depths!\n"
      "Elder: Deep inside sleeps the Ember Golem. Defeat it and they will scatter.\n"
      "Elder: Slay monsters to grow stronger. Touch the crystal to save and heal.\n"
      "Elder: Go east through the field, then find the cave in the north-east.");
}
''';

const _merchant = r'''
// Sells potions for gold.
var potionPrice = 10;

void onInteract(by) {
  var gold = Game.data["gold"] ?? 0;
  if (gold >= potionPrice) {
    Game.data["gold"] = gold - potionPrice;
    Game.data["potions"] = (Game.data["potions"] ?? 0) + 1;
    playSound("coin", volume: 0.7);
    say("Merchant: One potion, fresh! Press Q to drink it when you are hurt.");
  } else {
    say("Merchant: Potions are $potionPrice gold. Monsters in the field drop plenty of coins!");
  }
}
''';

const _crystal = r'''
// Save point: heals the hero fully and saves the game.
void onInteract(by) {
  by.health.heal(by.health.maxHealth);
  Game.data["hp"] = by.health.health;
  by.call("save");
  playSound("coin", volume: 0.8, pitch: 1.8);
  say("The crystal glows warmly. Your wounds are healed and your journey is saved.");
}
''';

const _title = r'''
// Title screen: New Game (Enter) and Continue (C, only with a save).
void onStart() {
  playMusic("assets/templates/legends/theme.wav", 0.4);
  find("Continue").enabled = loadValue("legends_save", null) != null;
}

void onUIAction(action) {
  if (action == "new") {
    Game.data.clear();
    loadLevel("Village");
  } else if (action == "continue") {
    var d = loadValue("legends_save", null);
    if (d == null) return;
    Game.data.clear();
    for (var key in ["level", "xp", "maxHp", "gold", "potions", "bossDefeated", "metElder"]) Game.data[key] = d[key];
    Game.data["hp"] = d["maxHp"];
    Game.data["pendingX"] = d["x"];
    Game.data["pendingY"] = d["y"];
    loadLevel(d["scene"]);
  }
}
''';

const _effect = r'''
// A one-shot particle puff that cleans itself up.
var count = 14;

void onStart() {
  after(0, () => self.particles.burst(count));   // after the spawner has set count
  self.destroy(1.2);
}
''';

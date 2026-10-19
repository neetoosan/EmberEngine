/// Ember Script source for the "Ember Depths" template (editable in the Script
/// workspace once a project is created from it).
const Map<String, String> depthsScripts = {
  'depths_game.ember': _game,
  'depths_hero.ember': _hero,
  'depths_monster.ember': _monster,
  'depths_chest.ember': _chest,
  'depths_pickup.ember': _pickup,
  'depths_stairs.ember': _stairs,
  'depths_title.ember': _title,
};

const _game = r'''
// Ember Depths: every floor is a new dungeon grown from the run's seed (the
// same seed always makes the same dungeons). Find the stairs, open chests for
// relics, and see how deep you get. Death ends the run.
var startHearts = 4;
var art = "assets/templates/depths/";
var relicNames = {"power": "Ember Fang (+1 damage)", "haste": "Quick Quill (faster casting)", "split": "Twin Spark (+1 shot)",
  "vigor": "Heart Stone (+1 heart)", "swift": "Wind Boots (faster)", "fortune": "Golden Idol (+25 gold)"};
var relicFrames = {"power": 2, "haste": 3, "split": 4, "vigor": 5, "swift": 6, "fortune": 7};

var run = null;
var rooms = [];
var rng = null;
var state = "play";       // play, descending, dead
var kills = 0;
var _banner = 0.0;

void onStart() {
  run = Game.data["depths"];
  if (run == null) {
    var seed = Game.data["depthsSeed"] ?? Random().integer(1000000);
    run = {"seed": seed, "floor": 1, "hearts": startHearts, "maxHearts": startHearts, "gold": 0, "kills": 0,
      "damage": 1, "rate": 1.0, "shots": 1, "speed": 1.0, "relics": []};
    Game.data["depths"] = run;
  }
  var floorSeed = run["seed"] * 31 + run["floor"] * 7919;
  var map = self.tilemap;
  rooms = map.dungeon(floorSeed, rooms: min(7 + run["floor"], 13), minSize: 5, maxSize: 9, wall: 1, floor: 2, corridor: 2);
  map.vary(2, [3, 4, 5], 0.16, seed: floorSeed);
  map.autotile(1, 10);
  rng = Random(floorSeed);

  var hero = find("Hero");
  hero.position = rooms[0]["center"];
  hero.health.maxHealth = run["maxHearts"];
  hero.health.health = run["hearts"];
  find("Camera").position = hero.position;

  // The stairs go in the room farthest from the start
  var far = rooms[1];
  for (var r in rooms) {
    if (r["center"].distanceTo(rooms[0]["center"]) > far["center"].distanceTo(rooms[0]["center"])) far = r;
  }
  spawn("Stairs", far["center"]);
  for (var i = 1; i < rooms.length; i++) populate(rooms[i], rooms[i] == far);
  for (var r in rooms) torches(r);
  playMusic(art + "depths.wav", 0.45);
  banner("FLOOR ${run["floor"]}", run["floor"] == 1 ? "Find the stairs down" : "Deeper. Darker.", 2.5);
  hud();
}

// A random floor cell inside a room (not touching its walls).
Vec2 spot(room) {
  var map = self.tilemap;
  return map.cellCenter(room["col"] + 1 + rng.integer(max(1, room["width"] - 2)), room["row"] + 1 + rng.integer(max(1, room["height"] - 2)));
}

void populate(room, stairsRoom) {
  var floor = run["floor"];
  var count = min(6, 1 + rng.integer(2 + floor ~/ 2));
  var kinds = floor == 1 ? ["Slime", "Slime", "Bat"] : ["Slime", "Bat", "Archer", "Archer"];
  for (var i = 0; i < count; i++) {
    var e = spawn(rng.pick(kinds), spot(room));
    toughen(e);
  }
  if (stairsRoom && floor % 3 == 0) {
    var w = spawn("Warden", room["center"] + vec(0, -40));
    toughen(w);
    banner("FLOOR $floor", "Something big guards the stairs", 3);
  }
  if (rng.chance(0.4)) spawn("Chest", spot(room));
}

void toughen(e) {
  e.health.maxHealth = round(e.health.maxHealth * (1 + (run["floor"] - 1) * 0.3));
  e.health.health = e.health.maxHealth;
}

// Torches on the wall above a room (where the wall has a front face)
void torches(room) {
  var map = self.tilemap;
  for (var k = 0; k < 2; k++) {
    var col = room["col"] + 1 + rng.integer(max(1, room["width"] - 2));
    var p = map.cellCenter(col, room["row"] - 1);
    if (findInRange("torch", p, 70).isEmpty) spawn("Torch", p + vec(0, 4));
  }
}

void onUpdate(dt) {
  if (_banner > 0) {
    _banner -= dt;
    if (_banner <= 0) banner("", "", 0);
  }
}

// --- Called by other scripts --------------------------------------------------

void enemyDown(where, kind) {
  kills++;
  run["kills"] = run["kills"] + 1;
  find("Pop FX").particles.burst(kind == "Warden" ? 50 : 16, where);
  if (kind == "Warden") {
    spawn("Relic", where).call("become", rng.pick(relicNames.keys.toList()));
  } else if (rng.chance(0.45)) {
    spawn("Coin", where);
  } else if (rng.chance(0.12)) {
    spawn("Heart", where);
  }
}

void openChest(where) {
  var kind = rng.pick(relicNames.keys.toList());
  var relic = spawn("Relic", where + vec(0, 26));
  relic.call("become", kind);
  for (var i = 0; i < 3; i++) spawn("Coin", where + vec(randomRange(-20, 20), randomRange(10, 30)));
}

void collect(kind) {
  var hero = find("Hero");
  if (kind == "coin") {
    run["gold"] = run["gold"] + 1;
    playSound(art + "coin.wav", 0.3);
  } else if (kind == "heart") {
    hero.health.heal(1);
    playSound(art + "chest.wav", 0.3);
  } else {
    if (kind == "power") run["damage"] = run["damage"] + 1;
    if (kind == "haste") run["rate"] = run["rate"] * 1.25;
    if (kind == "split") run["shots"] = run["shots"] + 1;
    if (kind == "swift") run["speed"] = run["speed"] * 1.15;
    if (kind == "fortune") run["gold"] = run["gold"] + 25;
    if (kind == "vigor") {
      run["maxHearts"] = run["maxHearts"] + 1;
      hero.health.maxHealth = run["maxHearts"];
      hero.health.heal(run["maxHearts"]);
    }
    run["relics"].add(kind);
    banner(relicNames[kind], "", 2.2);
    playSound(art + "chest.wav", 0.6);
  }
  hud();
}

void descend() {
  if (state != "play") return;
  state = "descending";
  run["floor"] = run["floor"] + 1;
  run["hearts"] = find("Hero").health.health;
  playSound(art + "stairs.wav", 0.7);
  find("Camera").camera.flash("#000000", 0.6);
  after(0.5, () { restart(); });
}

void heroDied() {
  if (state == "dead") return;
  state = "dead";
  playSound(art + "die.wav", 0.7);
  var floor = run["floor"];
  if (floor > loadValue("depths_best", 0)) saveValue("depths_best", floor);
  for (var n in ["ResultsPanel", "ResultsTitle", "ResultsLine", "ResultsStats", "RetryButton", "SameSeedButton", "MenuButton"]) find(n).enabled = true;
  find("ResultsTitle").text.text = "YOU FELL ON FLOOR $floor";
  find("ResultsLine").text.text = "Best: floor ${loadValue("depths_best", floor)}";
  find("ResultsStats").text.text = "${run["kills"]} monsters   ${run["gold"]} gold   ${run["relics"].length} relics   seed ${run["seed"]}";
}

// --- HUD ----------------------------------------------------------------------

void hud() {
  var hero = find("Hero");
  var hearts = find("Hearts").image;
  hearts.count = round(hero.health.maxHealth);
  hearts.filled = round(hero.health.health);
  setText("GoldText", "${run["gold"]}");
  setText("FloorText", "Floor ${run["floor"]}");
  setText("SeedText", "Seed ${run["seed"]}");
  var names = [];
  for (var k in run["relics"]) names.add(relicNames[k].split(" (")[0]);
  setText("RelicsText", names.join("  ·  "));
}

void banner(title, subtitle, seconds) {
  setText("Banner", title);
  setText("Subtitle", subtitle);
  _banner = seconds;
}

void onUIAction(action) {
  if (action == "retry" || action == "same") {
    var seed = run["seed"];
    Game.data["depths"] = null;
    Game.data["depthsSeed"] = action == "same" ? seed : null;
    restart();
  }
  if (action == "menu") {
    Game.data["depths"] = null;
    loadLevel("Title");
  }
}
''';

const _hero = r'''
// The hero. WASD moves, the mouse (or the arrow keys) aims and fires,
// Shift dashes (you can't be hurt mid-dash).
var speed = 150.0;
var fireRate = 2.6;       // casts per second before relics
var shotSpeed = 430.0;
var dashSpeed = 560.0;

var art = "assets/templates/depths/";
var _cool = 0.0;
var _dash = 0.0;
var _dashCool = 0.0;
var _t = 0.0;

void onUpdate(dt) {
  var game = find("Dungeon").script;
  if (game.state != "play") return;
  var run = game.run;
  _t += dt;
  _cool -= dt;
  _dashCool -= dt;

  var pad = Input.pad(1);
  var dir = vec((Input.key("D") ? 1 : 0) - (Input.key("A") ? 1 : 0), (Input.key("S") ? 1 : 0) - (Input.key("W") ? 1 : 0));
  if (dir.length == 0) dir = pad.stick;
  self.mover.moveSpeed = speed * run["speed"];
  self.mover.move(dir.length > 0 ? dir.normalized() : dir);
  self.scale = dir.length > 0 ? 1 + sin(_t * 16) * 0.04 : 1;

  // Aim with the arrow keys, or at the mouse
  var aim = vec((Input.key("Right") ? 1 : 0) - (Input.key("Left") ? 1 : 0), (Input.key("Down") ? 1 : 0) - (Input.key("Up") ? 1 : 0));
  if (aim.length == 0) aim = pad.rightStick;
  var firing = aim.length > 0 || Input.mouseDown || Input.key("Space") || pad.trigger("right") > 0.5;
  var angle = aim.length > 0 ? degrees(atan2(aim.y, aim.x)) : angleTo(self, Input.mouse);
  if (aim.length > 0 || Input.mouseDown) self.sprite.flipX = cos(radians(angle)) < 0;
  else if (dir.x != 0) self.sprite.flipX = dir.x < 0;

  if (firing && _cool <= 0) {
    _cool = 1 / (fireRate * run["rate"]);
    var n = run["shots"];
    var from = self.center + vec(cos(radians(angle)), sin(radians(angle))) * 14;
    find("Bolts").bullets.spread(from, angle, n, (n - 1) * 9, shotSpeed, frame: 0, damage: run["damage"], radius: 6);
    playSound(art + "cast.wav", 0.2);
  }

  if (_dash > 0) {
    _dash -= dt;
    find("Dash FX").particles.burst(2, self.center);
    if (_dash <= 0) self.health.enabled = true;
  }
  if ((Input.pressed("Shift") || pad.pressed("b") || pad.pressed("lb")) && _dashCool <= 0 && dir.length > 0) {
    _dash = 0.22;
    _dashCool = 0.8;
    self.health.enabled = false;
    self.mover.knockback(dir.normalized() * dashSpeed);
    playSound(art + "dash.wav", 0.4);
  }
}

void onDamaged(amount, source) {
  playSound(art + "hurt.wav", 0.6);
  find("Camera").camera.shake(6, 0.3);
  find("Camera").camera.flash("#7F1D1D", 0.3);
  find("Dungeon").call("hud");
}

void onDeath(killer) {
  self.enabled = false;
  find("Pop FX").particles.burst(40, self.center);
  find("Dungeon").call("heroDied");
}
''';

const _monster = r'''
// A monster (Monster AI does the hunting). Tells the dungeon when it dies.
var kind = "Slime";

void onDeath(killer) {
  playSound("assets/templates/depths/hit.wav", 0.4, pitch: 0.7);
  find("Dungeon").call("enemyDown", self.center, kind);
}

void onDamaged(amount, source) {
  playSound("assets/templates/depths/hit.wav", 0.25);
}
''';

const _chest = r'''
// A chest: walk up to it to open it.
var opened = false;

void onUpdate(dt) {
  if (opened) return;
  var hero = find("Hero");
  if (hero.enabled && self.distanceTo(hero) < 36) {
    opened = true;
    self.sprite.frame = 1;
    playSound("assets/templates/depths/chest.wav", 0.6);
    find("Dungeon").call("openChest", self.position);
  }
}
''';

const _pickup = r'''
// A coin, heart or relic. Flies to the hero when close.
var kind = "coin";
var t = 0.0;
var _base = 0.0;

void onStart() {
  _base = self.y;
}

// Turns this pickup into a relic of the given kind.
void become(k) {
  kind = k;
  self.sprite.frame = find("Dungeon").script.relicFrames[k];
}

void onUpdate(dt) {
  t += dt;
  var hero = find("Hero");
  if (!hero.enabled) return;
  var d = self.distanceTo(hero);
  if (d < 70 && t > 0.4) {
    self.position = self.position + self.directionTo(hero) * 280 * dt;
  } else {
    self.y = _base + sin(t * 4) * 3;
  }
  if (d < 18 && t > 0.4) {
    find("Dungeon").call("collect", kind);
    destroy();
  }
}
''';

const _stairs = r'''
// Stairs down: step on them to go deeper.
void onUpdate(dt) {
  var hero = find("Hero");
  if (hero.enabled && self.distanceTo(hero) < 20) find("Dungeon").call("descend");
}
''';

const _title = r'''
// Title screen: a dungeon grown from a fixed seed, lit by torches.
void onStart() {
  Game.timeScale = 1;
  Game.data["depths"] = null;
  var map = find("Dungeon").tilemap;
  var rooms = map.dungeon(2024, rooms: 9, minSize: 5, maxSize: 9);
  map.vary(2, [3, 4, 5], 0.16, seed: 2024);
  map.autotile(1, 10);
  for (var r in rooms) spawn("Torch", map.cellCenter(r["col"] + r["width"] ~/ 2, r["row"] - 1) + vec(0, 4));
  var c = rooms[0]["center"];
  find("Camera").position = vec(clamp(c.x, 640, 1152), clamp(c.y, 270, 882));
  playMusic("assets/templates/depths/depths.wav", 0.4);
  var best = loadValue("depths_best", 0);
  setText("BestText", best > 0 ? "Deepest floor: $best" : "");
}

var t = 0.0;
var _startX = 0.0;

void onUpdate(dt) {
  var cam = find("Camera");
  if (t == 0) _startX = cam.x;
  t += dt;
  cam.x = _startX + sin(t * 0.15) * 160;   // stays inside the 1792-pixel map
}

void onUIAction(action) {
  if (action == "start") Game.data["depthsSeed"] = null;
  if (action == "daily") {
    // The same dungeon for everyone today
    Game.data["depthsSeed"] = Game.today;
  }
  if (action == "start" || action == "daily") loadLevel("Dungeon");
}
''';

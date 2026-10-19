/// Ember Script source for the "Ember Spire" template (editable in the Script
/// workspace once a project is created from it).
const Map<String, String> spireScripts = {
  'spire_game.ember': _game,
  'spire_hero.ember': _hero,
  'spire_crawler.ember': _crawler,
  'spire_flyer.ember': _flyer,
  'spire_boss.ember': _boss,
  'spire_quake.ember': _quake,
  'spire_pickup.ember': _pickup,
  'spire_shrine.ember': _shrine,
  'spire_title.ember': _title,
};

const _game = r'''
// Ember Spire: explore the caverns, find the three abilities that open new
// ways (double jump, dash, wall jump), defeat the Thornback and take the
// Ember Heart. Shrines save; abilities, hearts and gems are kept even if you
// fall. Everything you have seen shows on the minimap.
var startHearts = 4;
var art = "assets/templates/spire/";
var names = {"double": "DOUBLE JUMP", "dash": "DASH", "wall": "WALL JUMP"};
var hints = {"double": "Jump again in mid-air", "dash": "Shift or C dashes forward, even in mid-air", "wall": "Jump while sliding down a wall"};

var state = "play";       // play, dead, won
var abilities = {"double": false, "dash": false, "wall": false};
var maxHearts = 4;
var gems = 0;
var deaths = 0;
var time = 0.0;
var taken = [];           // names of pickups already collected
var bossDown = false;
var respawnAt = null;     // where the hero comes back (the last shrine)
var _banner = 0.0;
var _roomLabel = 0.0;

void onStart() {
  self.tilemap.autotile(1, 10);
  var hero = find("Hero");
  var save = loadValue("spire_save", null);
  if (Game.data["spireContinue"] == true && save != null) {
    abilities = save["abilities"];
    maxHearts = save["maxHearts"];
    gems = save["gems"];
    deaths = save["deaths"];
    time = save["time"];
    taken = save["taken"];
    bossDown = save["bossDown"];
    find("Minimap").minimap.explored = save["explored"];
    if (save["spawn"] != null) respawnAt = vec(save["spawn"][0], save["spawn"][1]);
  } else {
    maxHearts = startHearts;
    deleteValue("spire_save");
  }
  Game.data["spireContinue"] = true;    // falling brings you back to the last shrine
  if (respawnAt != null) hero.position = respawnAt;
  find("Camera").camera.snapToTarget();
  for (var n in taken) {
    var e = find(n);
    if (e != null) destroy(e);
  }
  if (bossDown) {
    var boss = find("Thornback");
    if (boss != null) destroy(boss);
    var heart = find("Ember Heart");
    if (heart != null && !taken.contains("Ember Heart")) heart.enabled = true;
  }
  hero.health.maxHealth = maxHearts;
  hero.health.health = maxHearts;
  applyAbilities();
  playMusic(art + "spire.wav", 0.4);
  if (save == null || Game.data["spireNew"] == true) {
    Game.data["spireNew"] = false;
    banner("EMBER SPIRE", "Find a way up to the Ember Throne", 3);
  }
  hud();
}

void onUpdate(dt) {
  if (state == "play") time += dt;
  if (_banner > 0) {
    _banner -= dt;
    if (_banner <= 0) banner("", "", 0);
  }
  if (_roomLabel > 0) {
    _roomLabel -= dt;
    if (_roomLabel <= 0) setText("RoomText", "");
  }
}

void applyAbilities() {
  var c = find("Hero").controller;
  c.airJumps = abilities["double"] ? 1 : 0;
  c.dashSpeed = abilities["dash"] ? 720 : 0;
  c.wallJump = abilities["wall"];
}

// --- Called by other scripts --------------------------------------------------

void roomEntered(name) {
  setText("RoomText", name);
  _roomLabel = 2.5;
  var inThrone = name == "Ember Throne" && !bossDown;
  find("BossBar").enabled = inThrone;
  find("BossName").enabled = inThrone;
  if (inThrone) {
    playSound(art + "roar.wav", 0.6);
    find("Thornback").call("wake");
  }
}

void collect(kind, name) {
  taken.add(name);
  if (kind == "double" || kind == "dash" || kind == "wall") {
    abilities[kind] = true;
    applyAbilities();
    banner(names[kind], hints[kind], 4);
    playSound(art + "power.wav", 0.7);
    find("Camera").camera.flash("#99F6E4", 0.5);
  } else if (kind == "heart") {
    maxHearts++;
    var h = find("Hero").health;
    h.maxHealth = maxHearts;
    h.heal(maxHearts);
    banner("HEART CONTAINER", "One more heart", 2.5);
    playSound(art + "power.wav", 0.5);
  } else if (kind == "gem") {
    gems++;
    playSound(art + "gem.wav", 0.5);
  } else if (kind == "goal") {
    win();
    return;
  }
  keep();
  hud();
}

// Saves what was found (not where you are: that is the shrines' job).
void keep() {
  var old = loadValue("spire_save", null);
  var at = old == null ? null : old["spawn"];
  saveValue("spire_save", {"abilities": abilities, "maxHearts": maxHearts, "gems": gems, "deaths": deaths, "time": time,
    "taken": taken, "bossDown": bossDown, "explored": find("Minimap").minimap.explored, "spawn": at});
}

void rest(at) {
  respawnAt = at;
  var h = find("Hero").health;
  h.heal(h.maxHealth);
  keep();
  var s = loadValue("spire_save", null);
  s["spawn"] = [at.x, at.y];
  saveValue("spire_save", s);
  playSound(art + "save.wav", 0.6);
  banner("", "Rested. Your progress is saved.", 2);
  hud();
}

void heroDied() {
  if (state != "play") return;
  state = "dead";
  deaths++;
  keep();
  banner("YOU FELL", "", 1.5);
  after(1.6, () { restart(); });
}

void bossDefeated(where) {
  bossDown = true;
  find("BossBar").enabled = false;
  find("BossName").enabled = false;
  find("Camera").camera.shake(14, 1.0);
  find("Camera").camera.flash("#FFFFFF", 0.6);
  playSound(art + "slam.wav", 0.8);
  var heart = find("Ember Heart");
  heart.enabled = true;
  banner("THE THORNBACK FALLS", "The Ember Heart is yours to take", 3);
  keep();
}

void bossHealth(value, maxValue) {
  var bar = find("BossBar").bar;
  bar.max = maxValue;
  bar.value = value;
}

void win() {
  state = "won";
  var m = floor(time / 60);
  var s = floor(time % 60);
  var clock = "$m:${s < 10 ? "0" : ""}$s";
  var best = loadValue("spire_best", 0);
  if (best == 0 || time < best) saveValue("spire_best", time);
  deleteValue("spire_save");
  Game.data["spireContinue"] = false;
  playSound(art + "power.wav", 0.8);
  for (var n in ["ResultsPanel", "ResultsTitle", "ResultsLine", "ResultsStats", "MenuButton"]) find(n).enabled = true;
  find("ResultsTitle").text.text = "THE EMBER HEART";
  find("ResultsLine").text.text = "Time $clock";
  var map = round(find("Minimap").minimap.exploredFraction * 100);
  find("ResultsStats").text.text = "Map $map%   Gems $gems / 3   Falls $deaths";
}

// --- HUD ----------------------------------------------------------------------

void hud() {
  var h = find("Hero").health;
  var hearts = find("Hearts").image;
  hearts.count = round(h.maxHealth);
  hearts.filled = round(h.health);
  setText("GemText", "$gems / 3");
}

void banner(title, subtitle, seconds) {
  setText("Banner", title);
  setText("Subtitle", subtitle);
  _banner = seconds;
}

void onUIAction(action) {
  if (action == "menu") loadLevel("Title");
}
''';

const _hero = r'''
// The explorer. A / D (or arrows) run, Space, Z or K jump, J or X swing the
// sword, Shift or C dash once found, W or Up uses shrines.
var attackTime = 0.32;
var art = "assets/templates/spire/";

var _attack = 0.0;
var _t = 0.0;
var _safe = null;
var _blink = 0.0;
var dead = false;

void onUpdate(dt) {
  if (dead) return;
    _t += dt;
  _attack -= dt;
  var c = self.controller;
  var pad = Input.pad(1);
  var x = (Input.key("D") || Input.key("Right") || pad.button("right") ? 1 : 0) - (Input.key("A") || Input.key("Left") || pad.button("left") ? 1 : 0);
  if (x == 0 && abs(pad.stick.x) > 0.4) x = sign(pad.stick.x);
  var held = Input.key("Space") || Input.key("Z") || Input.key("K") || pad.button("a");
  var pressed = Input.pressed("Space") || Input.pressed("Z") || Input.pressed("K") || pad.pressed("a");
  var wasGrounded = c.grounded;
  c.move(x, held, pressed);
  if (pressed && wasGrounded) playSound(art + "jump.wav", 0.25);
  if ((Input.pressed("Shift") || Input.pressed("C") || pad.pressed("b") || pad.pressed("rb")) && c.dash()) {}

  // Look: run, jump, face the way we go
  var body = self.child("Body");
  var dir = c.facing == "left" ? -1 : 1;
  body.sprite.flipX = dir < 0;
  if (!c.grounded) body.sprite.frame = 3;
  else if (abs(c.velocity.x) > 30) body.sprite.frame = 1 + floor(_t * 10) % 2;
  else body.sprite.frame = 0;
  if (c.grounded && x == 0) _safe = self.position;

  if ((Input.pressed("J") || Input.pressed("X") || Input.click || pad.pressed("x")) && _attack <= 0) swing(dir);

  // Touching enemies hurts
  for (var e in findAll("enemy")) {
    if (self.overlaps(e)) {
      self.health.damage(1, e);
      break;
    }
  }
  if (_blink > 0) {
    _blink -= dt;
    body.sprite.opacity = floor(_blink * 14) % 2 == 0 ? 1 : 0.35;
    if (_blink <= 0) body.sprite.opacity = 1;
  }
}

void swing(dir) {
  _attack = attackTime;
  var at = self.center + vec(dir * 30, -2);
  var s = spawn("Slash", at);
  s.sprite.flipX = dir < 0;
  s.destroy(0.12);
  var hits = strike(at, 58, 46, damage: 1, team: "player", knockback: 240);
  playSound(art + "slash.wav", 0.35);
  if (hits.isNotEmpty) {
    playSound(art + "hit.wav", 0.4);
    find("Spark FX").particles.burst(10, at);
  }
}

void onDamaged(amount, source) {
  playSound(art + "hurt.wav", 0.6);
  find("Camera").camera.shake(6, 0.3);
  var push = source != null && source.x > self.x ? -1 : 1;
  self.controller.velocity = vec(push * 260, -300);
  _blink = 1.0;
  find("World").call("hud");
}

// Spikes: lose a heart and go back to solid ground
void onTileTouch(tile) {
  if (dead || self.health.invulnerable) return;
  self.health.damage(1);
  if (!self.health.dead && _safe != null) {
    self.position = _safe;
    self.controller.velocity = vec(0, 0);
  }
}

void onAirJump() {
  playSound(art + "airjump.wav", 0.35);
  find("Dust FX").particles.burst(10, self.center + vec(0, 16));
}

void onWallJump() {
  playSound(art + "jump.wav", 0.3);
  find("Dust FX").particles.burst(8, self.center);
}

void onDash() {
  playSound(art + "dash.wav", 0.4);
  find("Dash FX").particles.burst(14, self.center);
}

void onRoomEnter(room) {
  find("World").call("roomEntered", room.name);
}

void onDeath(killer) {
  dead = true;
  self.child("Body").enabled = false;
  find("Spark FX").particles.burst(30, self.center);
  find("World").call("heroDied");
}
''';

const _crawler = r'''
// A crawler: walks back and forth, turning at walls and ledges.
var speed = 50.0;
var _dir = -1;

void onUpdate(dt) {
  var c = self.controller;
  var ahead = self.center + vec(_dir * 18, 24);
  if (c.hitWall || !c.groundAt(ahead.x, ahead.y)) _dir = -_dir;
  c.moveSpeed = speed;
  c.move(_dir, false, false);
  self.sprite.flipX = _dir < 0;
}

void onDeath(killer) {
  playSound("assets/templates/spire/hit.wav", 0.4, pitch: 0.7);
  find("Pop FX").particles.burst(18, self.center);
}
''';

const _flyer = r'''
// A moth: hovers near home and drifts toward you when you come close.
var range = 200.0;
var speed = 70.0;
var _home = null;
var t = 0.0;

void onStart() {
  _home = self.position;
  t = random() * 6;
}

void onUpdate(dt) {
  t += dt;
  var hero = find("Hero");
  var goal = _home + vec(sin(t * 0.8) * 40, sin(t * 1.7) * 18);
  if (hero.enabled && self.distanceTo(hero) < range) goal = hero.center;
  self.position = self.position + (goal - self.position).normalized() * min(speed * dt, (goal - self.position).length);
  self.sprite.flipX = hero.x < self.x;
  self.scale = vec(1, 0.9 + sin(t * 12) * 0.1);
}

void onDeath(killer) {
  playSound("assets/templates/spire/hit.wav", 0.4, pitch: 1.3);
  find("Pop FX").particles.burst(18, self.center);
}
''';

const _boss = r'''
// The Thornback: walks at you, charges across the floor, and leaps to slam
// the ground, sending shockwaves both ways (jump over them).
var art = "assets/templates/spire/";
var state = "sleep";      // sleep, walk, windup, charge, leap, rest
var timer = 0.0;
var _dir = -1;
var _next = 0;

void wake() {
  if (state == "sleep") {
    state = "walk";
    timer = 1.2;
  }
}

void onUpdate(dt) {
  var c = self.controller;
  find("World").call("bossHealth", self.health.health, self.health.maxHealth);
  if (state == "sleep") {
    c.move(0, false, false);
    return;
  }
  var hero = find("Hero");
  timer -= dt;
  if (state == "walk") {
    _dir = hero.center.x < self.center.x ? -1 : 1;
    c.moveSpeed = 70;
    c.move(_dir, false, false);
    if (timer <= 0) {
      _next++;
      state = _next % 2 == 0 ? "leap" : "windup";
      timer = 0.6;
      if (state == "leap") {
        c.bounce(760);
        playSound(art + "roar.wav", 0.4);
      }
    }
  } else if (state == "windup") {
    c.move(0, false, false);
    self.sprite.tint = floor(timer * 12) % 2 == 0 ? "#FFB4A0" : "#FFFFFF";
    if (timer <= 0) {
      state = "charge";
      timer = 1.6;
      self.sprite.tint = "#FFFFFF";
    }
  } else if (state == "charge") {
    c.moveSpeed = 420;
    c.move(_dir, false, false);
    if (c.hitWall || timer <= 0) {
      state = "rest";
      timer = 1.0;
      find("Camera").camera.shake(8, 0.4);
      playSound(art + "slam.wav", 0.5);
    }
  } else if (state == "leap") {
    c.moveSpeed = 180;
    c.move(_dir, false, false);
    if (c.grounded && timer <= 0.3) {
      state = "rest";
      timer = 0.9;
      slam();
    }
  } else if (state == "rest") {
    c.move(0, false, false);
    if (timer <= 0) {
      state = "walk";
      timer = 1.5;
    }
  }
  self.sprite.flipX = _dir < 0;
}

void slam() {
  find("Camera").camera.shake(12, 0.5);
  playSound(art + "slam.wav", 0.7);
  for (var d in [-1, 1]) {
    var q = spawn("Quake", vec(self.center.x + d * 60, self.y + self.height / 2 - 14));
    q.script.dir = d;
  }
}

void onDamaged(amount, source) {
  playSound(art + "hit.wav", 0.5, pitch: 0.6);
}

void onDeath(killer) {
  find("Pop FX").particles.burst(60, self.center);
  find("World").call("bossDefeated", self.center);
}
''';

const _quake = r'''
// A shockwave rolling along the floor. Only hurts you on the ground.
var dir = 1;
var speed = 300.0;
var t = 0.0;

void onUpdate(dt) {
  t += dt;
  self.x += dir * speed * dt;
  self.sprite.opacity = 1 - t / 1.4;
  var hero = find("Hero");
  if (hero.enabled && self.overlaps(hero) && hero.controller.grounded) hero.health.damage(1, self);
  if (t > 1.4) destroy();
}
''';

const _pickup = r'''
// An ability orb, heart container, gem or the Ember Heart.
var kind = "gem";
var t = 0.0;
var _y = 0.0;

void onStart() {
  _y = self.y;
}

void onUpdate(dt) {
  t += dt;
  self.y = _y + sin(t * 2.5) * 4;
  var hero = find("Hero");
  if (hero.enabled && self.overlaps(hero)) {
    find("Spark FX").particles.burst(24, self.center);
    find("World").call("collect", kind, self.name);
    destroy();
  }
}
''';

const _shrine = r'''
// A save shrine: stand next to it and press W or Up to rest (full health, save).
var near = false;

void onUpdate(dt) {
  var hero = find("Hero");
  var close = hero.enabled && self.distanceTo(hero) < 50;
  if (close != near) {
    near = close;
    setText("Prompt", near ? "W  rest at the shrine" : "");
  }
  if (near && (Input.pressed("W") || Input.pressed("Up"))) {
    find("World").call("rest", vec(self.center.x, self.center.y - 10));
    find("Spark FX").particles.burst(30, self.center);
  }
}
''';

const _title = r'''
// Title screen: new game or continue from the last shrine.
var t = 0.0;

void onStart() {
  Game.timeScale = 1;
  find("World").tilemap.autotile(1, 10);
  playMusic("assets/templates/spire/spire.wav", 0.35);
  var save = loadValue("spire_save", null);
  find("ContinueButton").enabled = save != null;
  if (save == null) find("NewButton").button.offset = vec(0, 10);
  var best = loadValue("spire_best", 0);
  if (best > 0) {
    var s = floor(best % 60);
    setText("BestText", "Best time ${floor(best / 60)}:${s < 10 ? "0" : ""}$s");
  }
}

void onUpdate(dt) {
  t += dt;
  find("Title Hero").y = 990 + sin(t * 2) * 6;
}

void onUIAction(action) {
  if (action == "new") {
    deleteValue("spire_save");
    Game.data["spireContinue"] = false;
    Game.data["spireNew"] = true;
    loadLevel("Spire");
  }
  if (action == "continue") {
    Game.data["spireContinue"] = true;
    loadLevel("Spire");
  }
}
''';

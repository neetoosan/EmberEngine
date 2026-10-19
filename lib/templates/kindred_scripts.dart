/// Ember Script source for the "Ember Kindred" template (editable in the
/// Script workspace once a project is created from it).
const Map<String, String> kindredScripts = {
  'kindred_game.ember': _game,
  'kindred_spirit.ember': _spirit,
  'kindred_foe.ember': _foe,
  'kindred_hollow.ember': _hollow,
  'kindred_mote.ember': _mote,
  'kindred_title.ember': _title,
};

const _game = r'''
// Ember Kindred: hold the grove for ten waves, together. Up to four spirits
// share one screen and friends join at any time by pressing shoot. A bond
// of light joins neighbouring spirits and burns any shadow that crosses it.
// A fallen spirit gets back up when a friend stays close; when every spirit
// is down at once, the light fades.
var art = "assets/templates/kindred/";
var names = ["Sol", "Lume", "Iris", "Wren"];
var bondRange = 380.0;    // longer than this and the bond breaks
var bondDamage = 1;
var bondTick = 0.25;      // seconds between bond burns
var spawnGap = 0.45;
var lastWave = 10;
var waves = [
  {"Wisp": 8},
  {"Wisp": 12},
  {"Wisp": 10, "Brute": 2},
  {"Wisp": 10, "Spitter": 3},
  {"Wisp": 14, "Brute": 2, "Spitter": 3},
  {"Wisp": 18, "Brute": 3, "Spitter": 3},
  {"Wisp": 12, "Brute": 3, "Spitter": 6},
  {"Wisp": 22, "Brute": 4, "Spitter": 4},
  {"Wisp": 26, "Brute": 5, "Spitter": 6},
  {"Hollow": 1, "Wisp": 6},
];
var points = {"Wisp": 10, "Spitter": 25, "Brute": 40, "Hollow": 1000};

var state = "rest";       // rest (a banner before the wave), play, clear, over
var wave = 0;
var score = 0;
var kills = 0;
var joined = [true, false, false, false];
var queue = [];
var rng = null;
var _spawn = 0.0;
var _bond = 0.0;
var _wait = 0.0;
var _banner = 0.0;

void onStart() {
  rng = Random();
  // "Again" keeps the same team
  var team = Game.data["kindredTeam"];
  if (team != null) joined = team;
  for (var i = 1; i < 4; i++) {
    if (joined[i]) enter(i, false);
  }
  playMusic(art + "kindred.wav", 0.5);
  find("Camera").camera.snapToTarget();
  nextWave();
  hud();
}

int teamSize() {
  var n = 0;
  for (var j in joined) {
    if (j) n++;
  }
  return n;
}

// --- Waves ----------------------------------------------------------------

void nextWave() {
  wave++;
  state = "rest";
  _wait = 2.6;
  queue = [];
  var def = waves[wave - 1];
  var scale = 1 + 0.55 * (teamSize() - 1);
  for (var kind in def.keys.toList()) {
    if (kind == "Hollow") continue;
    var n = round(def[kind] * scale);
    for (var i = 0; i < n; i++) queue.add(kind);
  }
  rng.shuffle(queue);
  if (def["Hollow"] != null) queue.insert(0, "Hollow");
  if (wave == lastWave) banner("THE HOLLOW", "It wakes beneath the grove", 2.6);
  else banner("WAVE $wave", wave == 1 ? "Stay close: the bond between you burns the shadows" : "", 2.6);
  playSound(art + "wave.wav", 0.6);
}

void onUpdate(dt) {
  if (pausePressed()) togglePause();
  if (Game.paused || state == "over") return;
  for (var i = 1; i < 4; i++) {
    if (!joined[i] && Input.player(i + 1).pressed("attack")) join(i);
  }
  bonds(dt);
  hud();
  if (_banner > 0) {
    _banner -= dt;
    if (_banner <= 0) banner("", "", 0);
  }
  if (state == "rest") {
    _wait -= dt;
    if (_wait <= 0) state = "play";
  } else if (state == "play") {
    _spawn -= dt;
    if (queue.isNotEmpty && _spawn <= 0) {
      _spawn = findAll("foe").length > 28 ? spawnGap * 3 : spawnGap;
      appear(queue.removeAt(0));
    }
    if (queue.isEmpty && findAll("foe").isEmpty) waveCleared();
  } else if (state == "clear") {
    _wait -= dt;
    if (_wait <= 0) nextWave();
  }
}

// A point at the edge of the grove, away from every spirit
Vec2 edgePoint() {
  var p = vec(800, 120);
  for (var tries = 0; tries < 10; tries++) {
    var side = rng.integer(4);
    if (side == 0) p = vec(rng.range(150, 1450), 125);
    if (side == 1) p = vec(rng.range(150, 1450), 875);
    if (side == 2) p = vec(125, rng.range(150, 850));
    if (side == 3) p = vec(1475, rng.range(150, 850));
    var near = findNearest("alive", p);
    if (near == null || near.center.distanceTo(p) > 300) return p;
  }
  return p;
}

void appear(kind) {
  var e = spawn(kind, kind == "Hollow" ? vec(800, 200) : edgePoint());
  var tough = kind == "Hollow" ? 1 + 0.5 * (teamSize() - 1) : 1 + (wave - 1) * 0.08;
  e.health.maxHealth = round(e.health.maxHealth * tough);
  e.health.health = e.health.maxHealth;
}

// The Hollow calls more wisps from the trees
void summon(n) {
  for (var i = 0; i < n; i++) queue.add("Wisp");
}

void waveCleared() {
  if (wave >= lastWave) return;
  state = "clear";
  _wait = 3.0;
  score += 100 * wave;
  // Everyone gets back up between waves
  for (var i = 0; i < 4; i++) {
    var s = find(names[i]);
    if (joined[i]) s.call("rest");
  }
  banner("WAVE CLEAR", "+${100 * wave}  ·  the light returns", 2.6);
  playSound(art + "revive.wav", 0.5);
}

// --- The light bond -------------------------------------------------------

void bonds(dt) {
  var chain = [];
  for (var i = 0; i < 4; i++) {
    var s = find(names[i]);
    if (joined[i] && s.hasTag("alive")) chain.add(s);
  }
  _bond -= dt;
  var burn = _bond <= 0 && state == "play";
  if (_bond <= 0) _bond = bondTick;
  for (var k = 1; k <= 3; k++) {
    var line = find("Bond $k").line;
    if (k < chain.length && chain[k - 1].distanceTo(chain[k]) < bondRange) {
      line.points = [chain[k - 1].center, chain[k].center];
      line.width = 3.5 + sin(Game.time * 9 + k) * 1.2;
      if (burn) {
        for (var f in findAll("foe")) {
          if (line.distanceTo(f.center) < 14 + f.width * 0.35) {
            f.health.damage(bondDamage);
            find("Spark FX").particles.burst(4, f.center);
          }
        }
      }
    } else {
      line.points = [];
    }
  }
}

// --- Players --------------------------------------------------------------

void join(i) {
  joined[i] = true;
  Game.data["kindredTeam"] = joined;
  enter(i, true);
  banner("${names[i].toUpperCase()} JOINS", "Player ${i + 1}", 1.8);
  playSound(art + "join.wav", 0.7);
}

// Brings spirit i into the grove next to the others
void enter(i, flashy) {
  var s = find(names[i]);
  var sum = vec(0, 0);
  var n = 0;
  for (var other in findAll("alive")) {
    sum = sum + other.position;
    n++;
  }
  var at = n > 0 ? sum * (1 / n) : vec(800, 500);
  s.enabled = true;
  s.position = at + vec(rng.range(-60, 60), rng.range(30, 60));
  s.call("reset");
  if (flashy) find("Revive FX").particles.burst(40, s.center);
}

void spiritDown(slot) {
  if (findAll("alive").isEmpty && state != "won") lose();
}

// --- Called by foes and motes ---------------------------------------------

void foeDown(where, kind) {
  kills++;
  score += points[kind];
  find("Shadow FX").particles.burst(kind == "Hollow" ? 90 : (kind == "Brute" ? 30 : 14), where);
  var motes = kind == "Hollow" ? 20 : (kind == "Brute" ? 4 : (kind == "Spitter" ? 2 : 1));
  for (var i = 0; i < motes; i++) spawn("Mote", where + vec(rng.range(-10, 10), rng.range(-10, 10)));
  if (rng.chance(kind == "Brute" ? 0.2 : 0.05)) spawn("Bloom", where);
  if (kind == "Hollow") {
    // Its shadows fade with it
    state = "won";
    queue = [];
    for (var f in findAll("foe")) f.health.damage(999);
    after(2.0, () { win(); });
  }
}

void collect(kind, spirit) {
  if (kind == "bloom") {
    spirit.health.heal(2);
    playSound(art + "revive.wav", 0.35);
  } else {
    score += 5;
    playSound(art + "shoot.wav", 0.08, pitch: 1.8);
  }
}

// --- The end --------------------------------------------------------------

void win() {
  finish("THE GROVE IS SAFE", "All ten waves held, and the Hollow is gone");
  playSound(art + "win.wav", 0.7);
}

void lose() {
  if (state == "over") return;
  finish("THE LIGHT FADED", "On wave $wave of $lastWave");
  playSound(art + "lose.wav", 0.7);
}

void finish(title, line) {
  state = "over";
  find("Shadow Shots").bullets.clear();
  for (var k = 1; k <= 3; k++) find("Bond $k").line.points = [];
  var best = loadValue("kindred_best", 0);
  if (score > best) saveValue("kindred_best", score);
  if (wave > loadValue("kindred_wave", 0)) saveValue("kindred_wave", wave);
  for (var n in ["ResultsPanel", "ResultsTitle", "ResultsLine", "ResultsStats", "RetryButton", "MenuButton"]) find(n).enabled = true;
  banner("", "", 0);
  setText("ResultsTitle", title);
  setText("ResultsLine", line);
  var size = teamSize();
  setText("ResultsStats", "Score $score   ·   $kills shadows   ·   ${size == 1 ? "1 spirit" : "$size spirits"}   ·   best ${max(best, score)}");
}

// --- HUD and menus ----------------------------------------------------------

void hud() {
  for (var i = 0; i < 4; i++) {
    var n = i + 1;
    var s = find(names[i]);
    for (var part in ["Face$n", "Name$n", "Bar$n"]) find(part).enabled = joined[i];
    find("Join$n").enabled = !joined[i];
    if (joined[i]) {
      find("Bar$n").bar.max = s.health.maxHealth;
      find("Bar$n").bar.value = s.health.health;
      setText("Name$n", s.hasTag("alive") ? names[i].toUpperCase() : "${names[i].toUpperCase()}  ·  DOWN");
    }
  }
  setText("WaveText", "WAVE $wave / $lastWave");
  setText("ScoreText", "$score");
}

void banner(title, subtitle, seconds) {
  setText("Banner", title);
  setText("Subtitle", subtitle);
  _banner = seconds;
}

bool pausePressed() {
  if (Input.pressed("P")) return true;
  for (var i = 0; i < 4; i++) {
    if (joined[i] && Input.player(i + 1).pressed("start")) return true;
  }
  return false;
}

void togglePause() {
  if (state == "over") return;
  var on = !Game.paused;
  Game.paused = on;
  for (var n in ["PausedText", "ResumeButton", "QuitButton"]) find(n).enabled = on;
}

void onUIAction(action) {
  if (action == "resume") togglePause();
  if (action == "retry") {
    Game.paused = false;
    restart();
  }
  if (action == "menu") {
    Game.paused = false;
    loadLevel("Title");
  }
}
''';

const _spirit = r'''
// A lantern spirit, played by player `slot` (1 to 4). Hold shoot to fire at
// the nearest shadow (or the way you face), dash to slip through danger. At
// zero health the spirit falls; a friend staying close brings it back.
var slot = 1;
var fireRate = 5.0;       // shots a second
var shotSpeed = 560.0;
var range = 360.0;        // how far it looks for something to aim at
var dashSpeed = 640.0;
var reviveTime = 2.0;     // seconds a friend must stay close

var art = "assets/templates/kindred/";
var down = false;
var revive = 0.0;
var _cool = 0.0;
var _dash = 0.0;
var _dashCool = 0.0;
var _shield = 0.0;
var _t = 0.0;
var _aim = vec(1, 0);

// Full health, standing, briefly shielded (joining and Again)
void reset() {
  down = false;
  revive = 0;
  self.health.health = self.health.maxHealth;
  stand();
}

// Between waves: fallen spirits get up, the others heal a little
void rest() {
  if (down) {
    self.health.health = self.health.maxHealth / 2;
    stand();
    find("Revive FX").particles.burst(30, self.center);
  } else {
    self.health.heal(2);
  }
}

void stand() {
  down = false;
  revive = 0;
  self.addTag("alive");
  self.sprite.frame = (slot - 1) * 3;
  self.child("Ring").enabled = false;
  shield(1.5);
}

void shield(seconds) {
  _shield = seconds;
  self.health.enabled = false;
}

void onUpdate(dt) {
  var game = find("Grove").script;
  if (game.state == "over" || Game.paused) {
    self.mover.move(vec(0, 0));
    return;
  }
  _t += dt;
  _cool -= dt;
  _dashCool -= dt;
  if (_shield > 0) {
    _shield -= dt;
    self.sprite.opacity = 0.55 + 0.45 * abs(sin(_t * 14));
    if (_shield <= 0) {
      self.health.enabled = true;
      self.sprite.opacity = 1;
    }
  }
  if (down) {
    fallen(dt);
    return;
  }

  var me = Input.player(slot);
  var move = me.move;
  self.mover.move(move);
  if (move.length > 0.2) _aim = move.normalized();
  var base = (slot - 1) * 3;
  self.sprite.frame = move.length > 0.2 ? base + 1 : base;
  if (abs(move.x) > 0.2) self.sprite.flipX = move.x < 0;
  self.scale = 1 + sin(_t * 5 + slot) * 0.04;
  // Stay in the grove, and on the shared screen
  self.x = clamp(self.x, 110, 1490);
  self.y = clamp(self.y, 110, 890);
  find("Camera").camera.keepInView(self, 40);

  if (me.key("attack") && _cool <= 0) shoot();
  if (me.pressed("special") && _dashCool <= 0) dash(move.length > 0.2 ? move.normalized() : _aim);
  if (_dash > 0) {
    _dash -= dt;
    find("Revive FX").particles.burst(1, self.center);
  }
}

void shoot() {
  _cool = 1 / fireRate;
  var dir = _aim;
  var target = findNearest("foe", self.center);
  if (target != null && self.distanceTo(target) < range) dir = self.directionTo(target);
  find("Bolts").bullets.fire(self.center + dir * 18, degrees(atan2(dir.y, dir.x)), shotSpeed, frame: slot - 1, radius: 7);
  playSound(art + "shoot.wav", 0.1);
}

void dash(dir) {
  _dash = 0.2;
  _dashCool = 0.9;
  shield(0.3);
  self.mover.knockback(dir * dashSpeed);
  playSound(art + "dash.wav", 0.4);
}

void onDamaged(amount, source) {
  playSound(art + "hurt.wav", 0.5);
  find("Camera").camera.shake(5, 0.25);
}

void onDeath(killer) {
  down = true;
  revive = 0;
  self.removeTag("alive");
  self.sprite.frame = (slot - 1) * 3 + 2;
  self.sprite.opacity = 1;
  self.scale = 1;
  self.child("Ring").enabled = true;
  playSound(art + "down.wav", 0.6);
  find("Grove").call("spiritDown", slot);
}

// Lying down: a friend close by fills the ring; alone, it slowly empties
void fallen(dt) {
  self.mover.move(vec(0, 0));
  var helped = false;
  for (var s in findAll("alive")) {
    if (s.distanceTo(self) < 80) helped = true;
  }
  revive = helped ? min(1, revive + dt / reviveTime) : max(0, revive - dt * 0.4);
  var ring = self.child("Ring");
  ring.scale = 1.25 - revive * 0.55;
  ring.sprite.opacity = 0.35 + revive * 0.65;
  if (revive >= 1) {
    self.health.health = self.health.maxHealth / 2;
    stand();
    find("Revive FX").particles.burst(30, self.center);
    playSound(art + "revive.wav", 0.6);
  }
}
''';

const _foe = r'''
// A shadow thing. Wisps weave toward the nearest spirit, brutes wind up and
// charge, spitters keep their distance and spit. Touching a spirit hurts it.
var kind = "Wisp";
var touch = 1;
var _t = 0.0;
var _cool = 0.0;
var _charge = 0.0;
var _wob = 0.0;

void onStart() {
  self.scale = 0.2;
  _cool = randomRange(1.2, 2.6);
  _wob = randomRange(0, 6.28);
}

void onUpdate(dt) {
  var game = find("Grove").script;
  if (game.state == "over") {
    self.mover.move(vec(0, 0));
    return;
  }
  _t += dt;
  if (self.scale.x < 1) self.scale = min(1, self.scale.x + dt * 2.5);
  var target = findNearest("alive", self.center);
  if (target == null) {
    self.mover.move(vec(0, 0));
    return;
  }
  var to = target.center - self.center;
  var d = to.length;
  var dir = d > 0 ? to * (1 / d) : vec(0, 0);
  if (dir.x != 0) self.sprite.flipX = dir.x < 0;

  if (kind == "Spitter") {
    // Hover at range, circling, and spit three shots
    var want = d > 320 ? dir : (d < 220 ? dir * -1 : dir.rotated(1.5708) * 0.6);
    self.mover.move(want);
    _cool -= dt;
    if (_cool <= 0 && d < 520) {
      _cool = randomRange(1.8, 2.6);
      find("Shadow Shots").bullets.spread(self.center, degrees(atan2(dir.y, dir.x)), 3, 26, 190, frame: 4, radius: 8);
    }
  } else if (kind == "Brute") {
    _cool -= dt;
    if (_charge > 0) {
      // Winding up: stop and tremble, then charge
      _charge -= dt;
      self.mover.move(vec(0, 0));
      self.scale = 1 + sin(_t * 50) * 0.05;
      if (_charge <= 0) self.mover.knockback(dir * 560);
    } else {
      self.mover.move(dir);
      if (_cool <= 0 && d < 300) {
        _charge = 0.55;
        _cool = 3.2;
      }
    }
  } else {
    self.mover.move((dir + dir.rotated(1.5708) * sin(_t * 3 + _wob) * 0.6).normalized());
  }

  // Touching a spirit hurts it (not while it is shielded or dashing)
  if (d < self.width * 0.4 + 20 && target.health.enabled) target.health.damage(touch, self);
}

void onDamaged(amount, source) {
  playSound("assets/templates/kindred/hit.wav", 0.15, pitch: randomRange(0.9, 1.25));
}

void onDeath(killer) {
  find("Grove").call("foeDown", self.center, kind);
}
''';

const _hollow = r'''
// The Hollow: drifts over the grove sending out rings of shadow, aimed
// bursts, and wisps called from the trees. Fiercer below half health.
var art = "assets/templates/kindred/";
var dying = false;
var _t = 0.0;
var _ring = 2.0;
var _aimed = 3.5;
var _call = 7.0;
var _spin = 0.0;
var _rage = false;

void onStart() {
  self.scale = 0.3;
  find("BossBar").enabled = true;
  find("Camera").camera.shake(10, 0.8);
  playSound(art + "roar.wav", 0.8);
}

void onUpdate(dt) {
  if (dying) {
    self.scale = max(0.05, self.scale.x - dt * 0.5);
    self.sprite.opacity = max(0, self.sprite.opacity - dt * 0.6);
    return;
  }
  var game = find("Grove").script;
  if (game.state == "over") return;
  _t += dt;
  if (self.scale.x < 1) self.scale = min(1, self.scale.x + dt);
  var h = self.health;
  var bar = find("BossBar").bar;
  bar.max = h.maxHealth;
  bar.value = h.health;
  var rage = h.health < h.maxHealth / 2;
  if (rage && !_rage) {
    _rage = true;
    find("Grove").call("banner", "THE HOLLOW RAGES", "", 2.0);
    playSound(art + "roar.wav", 0.7);
    find("Camera").camera.shake(8, 0.6);
  }

  // Drift in a slow figure of eight over the middle of the grove
  var home = vec(800 + sin(_t * 0.4) * 330, 440 + sin(_t * 0.8) * 170);
  self.mover.move(self.center.distanceTo(home) > 20 ? (home - self.center).normalized() : vec(0, 0));

  var shots = find("Shadow Shots").bullets;
  var target = findNearest("alive", self.center);
  _ring -= dt;
  _aimed -= dt;
  _call -= dt;
  if (_ring <= 0) {
    _ring = rage ? 1.7 : 2.6;
    _spin += 11;
    shots.ring(self.center, rage ? 22 : 16, 150, offset: _spin, frame: 4, radius: 9);
  }
  if (_aimed <= 0 && target != null) {
    _aimed = rage ? 2.0 : 3.2;
    var d = self.directionTo(target);
    shots.spread(self.center, degrees(atan2(d.y, d.x)), rage ? 7 : 5, 50, 230, frame: 4, radius: 9);
  }
  if (_call <= 0) {
    _call = rage ? 6.0 : 9.0;
    find("Grove").call("summon", rage ? 4 : 3);
  }
  if (target != null && self.distanceTo(target) < 90 && target.health.enabled) target.health.damage(2, self);
}

void onDeath(killer) {
  dying = true;
  self.removeTag("foe");
  find("BossBar").enabled = false;
  find("Shadow Shots").bullets.clear();
  find("Camera").camera.shake(14, 1.2);
  find("Camera").camera.flash("#F5D0FE", 0.5);
  playSound(art + "roar.wav", 0.9, pitch: 0.7);
  find("Grove").call("foeDown", self.center, "Hollow");
}
''';

const _mote = r'''
// A mote of light (score) or a bloom (heals two). Scatters, then flies to the
// nearest spirit.
var kind = "mote";
var t = 0.0;
var _drift = vec(0, 0);

void onStart() {
  _drift = vec(randomRange(-90, 90), randomRange(-90, 90));
}

void onUpdate(dt) {
  t += dt;
  if (t > 14) {
    destroy();
    return;
  }
  _drift = _drift * max(0, 1 - dt * 5);
  self.position = self.position + _drift * dt;
  self.scale = 1 + sin(t * 8) * 0.12;
  var s = findNearest("alive", self.center);
  if (s == null || t < 0.35) return;
  var d = self.distanceTo(s);
  var pull = t > 1.2 ? 520 : (d < 150 ? 460 - d * 2 : 0);
  self.position = self.position + self.directionTo(s) * pull * dt;
  if (d < 24) {
    find("Grove").call("collect", kind, s);
    destroy();
  }
}
''';

const _title = r'''
// Title screen: the four spirits bob in the grove.
var names = ["Sol", "Lume", "Iris", "Wren"];
var t = 0.0;

void onStart() {
  Game.paused = false;
  Game.data["kindredTeam"] = null;
  playMusic("assets/templates/kindred/kindred.wav", 0.45);
  var best = loadValue("kindred_best", 0);
  var bestWave = loadValue("kindred_wave", 0);
  setText("BestText", best > 0 ? "Best score $best  ·  reached wave $bestWave" : "");
}

void onUpdate(dt) {
  t += dt;
  for (var i = 0; i < 4; i++) {
    var pose = find(names[i] + " Pose");
    var bob = sin(t * 2.2 + i * 1.3);
    pose.y = 750 + bob * 10;
    pose.sprite.frame = i * 3 + (bob > 0.7 ? 1 : 0);
  }
}

void onUIAction(action) {
  if (action == "play") loadLevel("Grove");
}
''';

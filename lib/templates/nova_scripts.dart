/// Ember Script source for the "Ember Nova" template (editable in the Script
/// workspace once a project is created from it).
const Map<String, String> novaScripts = {
  'nova_stage.ember': _stage,
  'nova_player.ember': _player,
  'nova_enemy.ember': _enemy,
  'nova_boss.ember': _boss,
  'nova_pickup.ember': _pickup,
  'nova_title.ember': _title,
};

const _stage = r'''
// Ember Nova: the stage. Sends waves of enemies on a timeline, then the boss.
// Beat the boss to start the next loop: faster bullets, more of them.
// Score, multiplier, lives, bombs and power are kept here.
var stageLength = 96.0;   // seconds of waves before the boss arrives
var startLives = 3;
var startBombs = 2;
var maxMult = 8.0;

var art = "assets/templates/nova/";
var time = 0.0;
var score = 0;
var shown = 0.0;          // the score on screen counts up to the real one
var mult = 1.0;
var lives = 3;
var bombs = 2;
var power = 1;
var loop = 1;
var best = 0;
var kills = 0;
var grazes = 0;
var state = "play";       // play, warning, boss, clear, over
var events = [];          // [time, kind, x, y, path, param], in time order
var next = 0;
var _banner = 0.0;
var _warning = 0.0;
var _chain = 0.0;
var _chainAt = null;
var paused = false;

void onStart() {
  var carry = Game.data["nova"];
  if (carry != null) {
    loop = carry["loop"];
    score = carry["score"];
    lives = carry["lives"];
    bombs = carry["bombs"];
    power = carry["power"];
    shown = score;
  } else {
    lives = startLives;
    bombs = startBombs;
  }
  best = loadValue("nova_best", 0);
  plan();
  playMusic(art + "nova.wav", 0.45);
  banner(loop == 1 ? "STAGE 1" : "LOOP $loop", loop == 1 ? "Destroy the armada" : "Faster. Denser. Good luck.", 2.6);
  hud();
}

// --- The timeline -------------------------------------------------------------

void plan() {
  drones(2, 170, 5, "sine");
  drones(5, 370, 5, "sine");
  darts(9, 3);
  drones(12, 120, 6, "sine");
  drones(13, 420, 6, "sine");
  add(16, "Turret", 1000, 160, "hold", 760);
  add(16.5, "Turret", 1000, 380, "hold", 760);
  darts(22, 4);
  add(26, "Spinner", 1000, 270, "hold", 700);
  drones(29, 200, 5, "cross");
  drones(30, 340, 5, "cross");
  add(35, "Cruiser", 1060, 270, "hold", 720);
  darts(42, 5);
  drones(46, 100, 7, "sine");
  drones(47, 440, 7, "sine");
  add(50, "Spinner", 1000, 150, "hold", 760);
  add(50.5, "Spinner", 1000, 390, "hold", 760);
  add(56, "Turret", 1000, 110, "hold", 820);
  add(56.5, "Turret", 1000, 270, "hold", 720);
  add(57, "Turret", 1000, 430, "hold", 820);
  darts(62, 6);
  drones(66, 270, 8, "sine");
  add(70, "Cruiser", 1060, 160, "hold", 760);
  add(72, "Cruiser", 1060, 390, "hold", 760);
  drones(78, 130, 6, "cross");
  drones(79, 410, 6, "cross");
  add(82, "Spinner", 1000, 270, "hold", 650);
  darts(86, 8);
}

// A line of drones, one after another.
void drones(t, y, count, path) {
  for (var i = 0; i < count; i++) add(t + i * 0.32, "Drone", 1000, y, path, i);
}

// Darts dive in from the right at random heights.
void darts(t, count) {
  for (var i = 0; i < count; i++) add(t + i * 0.45, "Dart", 1000, randomRange(80, 460), "dive", randomRange(560, 760));
}

void add(t, kind, x, y, path, param) {
  var e = [t, kind, x, y, path, param];
  var i = events.length;
  while (i > 0 && events[i - 1][0] > t) i--;
  events.insert(i, e);
}

void onUpdate(dt) {
  if (Input.pressed("P") || Input.pressed("Escape")) togglePause();
  if (paused) return;
  shown = shown + (score - shown) * min(1, dt * 10);
  find("ScoreText").text.text = fmt(round(shown));
  if (_banner > 0) {
    _banner -= dt;
    if (_banner <= 0) banner("", "", 0);
  }
  if (_chain > 0) chainExplosions(dt);
  if (state == "play") {
    time += dt;
    while (next < events.length && events[next][0] <= time) {
      var e = events[next];
      next++;
      var enemy = spawn(e[1], vec(e[2], e[3]));
      enemy.call("launch", e[4], e[5], loop);
    }
    if (time >= stageLength && findAll("enemy").isEmpty) startWarning();
  } else if (state == "warning") {
    _warning -= dt;
    find("Banner").enabled = floor(_warning * 4) % 2 == 0;
    if (_warning <= 0) startBoss();
  }
}

// --- Boss ---------------------------------------------------------------------

void startWarning() {
  state = "warning";
  _warning = 3.2;
  stopMusic();
  playSound(art + "hurt.wav", 0.5);
  banner("WARNING", "A huge energy signature is closing in", 3.2);
  find("Banner").text.color = "#FF4D6D";
}

void startBoss() {
  state = "boss";
  find("Banner").enabled = true;
  find("Banner").text.color = "#E0F2FE";
  banner("", "", 0);
  playMusic(art + "nova_boss.wav", 0.5);
  var boss = spawn("Boss", vec(1200, 270));
  boss.call("launch", loop);
  find("BossBar").enabled = true;
  find("BossName").enabled = true;
}

// Called by the boss every frame while it lives.
void bossHealth(value, maxValue) {
  var bar = find("BossBar").bar;
  bar.max = maxValue;
  bar.value = value;
}

// Called by the boss when it is destroyed.
void bossDown(where) {
  find("BossBar").enabled = false;
  find("BossName").enabled = false;
  addScore(50000);
  _chain = 2.2;
  _chainAt = where;
  find("Enemy Shots").bullets.clear();
  Game.timeScale = 0.4;
  after(0.8, () { Game.timeScale = 1; });
}

void chainExplosions(dt) {
  _chain -= dt;
  if (randomInt(4) == 0) explode(_chainAt + vec(randomRange(-150, 150), randomRange(-110, 110)), 1.2);
  if (_chain <= 0) {
    explode(_chainAt, 3.2);
    playSound(art + "bigboom.wav", 0.8);
    find("Camera").camera.flash("#FFFFFF", 0.9);
    find("Camera").camera.shake(18, 1.2);
    after(2.5, stageClear);
  }
}

void stageClear() {
  state = "clear";
  var bonus = lives * 10000 + bombs * 5000;
  addScore(bonus);
  saveBest();
  showResults("STAGE CLEAR", "Loop $loop cleared   +${fmt(bonus)} bonus", true);
}

// --- Scoring ------------------------------------------------------------------

void addScore(points) {
  score += round(points);
  if (score > best) find("HiText").text.text = "HI " + fmt(score);
}

// Called by enemies when they are destroyed.
void enemyDown(points, where, kind, crystals) {
  kills++;
  addScore(points * mult);
  mult = min(maxMult, mult + 0.05);
  explode(where, kind == "Cruiser" ? 2.0 : 0.9);
  for (var i = 0; i < crystals; i++) spawn("Crystal", where + vec(randomRange(-24, 24), randomRange(-24, 24)));
  var p = kind == "Cruiser" ? 1.0 : 0.06;
  if (power < 4 && chance(p)) spawn("Power", where);
  else if (chance(0.03)) spawn("Bomb Pickup", where);
  else if (chance(0.025)) spawn("Shield Pickup", where);
  hud();
}

// Called by the ship when an enemy bullet passes very close.
void graze(where) {
  grazes++;
  addScore(20);
  mult = min(maxMult, mult + 0.01);
  find("Spark FX").particles.burst(3, where);
  hud();
}

void collect(kind) {
  if (kind == "power") {
    if (power < 4) {
      power++;
      banner("POWER UP", "", 1.0);
    } else addScore(5000);
  }
  if (kind == "bomb") bombs = min(5, bombs + 1);
  if (kind == "crystal") {
    addScore(100);
    mult = min(maxMult, mult + 0.02);
  }
  hud();
}

// Called by the ship when it is hit.
void playerHit() {
  lives--;
  power = max(1, power - 1);
  mult = 1.0;
  find("Enemy Shots").bullets.clear();
  hud();
  if (lives <= 0) {
    state = "over";
    saveBest();
    after(1.6, () { showResults("GAME OVER", "You reached loop $loop", false); });
  }
}

bool canRespawn() => lives > 0;

// Called by the ship when it bombs. Returns false if there are none left.
bool useBomb() {
  if (bombs <= 0 || state == "over" || state == "clear") return false;
  bombs--;
  var cleared = find("Enemy Shots").bullets.clear();
  addScore(cleared * 10);
  hud();
  return true;
}

void saveBest() {
  if (score > best) {
    best = score;
    saveValue("nova_best", best);
  }
  if (loop > loadValue("nova_loop", 1)) saveValue("nova_loop", loop);
}

// --- Effects ------------------------------------------------------------------

void explode(where, size) {
  find("Boom FX").particles.burst(round(14 * size), where);
  find("Spark FX").particles.burst(round(10 * size), where);
  var ring = spawn("Shockwave", where);
  ring.scale = 0.1;
  tween(0.5 + size * 0.1, (t) {
    ring.scale = 0.1 + t * size * 0.9;
    ring.sprite.opacity = 1 - t;
  }, ease: "out", then: () { destroy(ring); });
  playSound(art + "boom.wav", min(0.9, 0.35 + size * 0.15));
  find("Camera").camera.shake(3 + size * 3, 0.25 + size * 0.1);
}

// --- HUD ----------------------------------------------------------------------

void hud() {
  find("MultText").text.text = "x" + mult.toStringAsFixed(1);
  find("Lives").image.count = max(0, lives);
  find("Bombs").image.count = bombs;
  find("PowerBar").bar.value = power;
  find("HiText").text.text = "HI " + fmt(max(best, score));
}

void banner(title, subtitle, seconds) {
  find("Banner").text.text = title;
  find("Subtitle").text.text = subtitle;
  _banner = seconds;
}

// 1234567 -> "1,234,567"
String fmt(n) {
  var s = "$n";
  var out = "";
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out = out + ",";
    out = out + s[i];
  }
  return out;
}

void showResults(title, line, cleared) {
  for (var n in ["ResultsPanel", "ResultsTitle", "ResultsScore", "ResultsLine", "ResultsStats", "MenuButton"]) find(n).enabled = true;
  find("RetryButton").enabled = !cleared;
  find("NextButton").enabled = cleared;
  find("ResultsTitle").text.text = title;
  find("ResultsScore").text.text = fmt(score);
  find("ResultsLine").text.text = line;
  var newBest = score >= best && score > 0 ? "   NEW BEST!" : "";
  find("ResultsStats").text.text = "Destroyed $kills   Grazes $grazes$newBest";
}

void togglePause() {
  if (state == "over" || state == "clear") return;
  paused = !paused;
  Game.timeScale = paused ? 0 : 1;
  for (var n in ["PausedText", "ResumeButton", "QuitButton"]) find(n).enabled = paused;
}

void onUIAction(action) {
  if (action == "resume") togglePause();
  if (action == "retry") {
    Game.data["nova"] = null;
    Game.timeScale = 1;
    restart();
  }
  if (action == "next") {
    Game.data["nova"] = {"loop": loop + 1, "score": score, "lives": lives, "bombs": bombs, "power": power};
    restart();
  }
  if (action == "menu") {
    Game.timeScale = 1;
    Game.data["nova"] = null;
    loadLevel("Title");
  }
}
''';

const _player = r'''
// The ship. Arrows / WASD fly (Shift: slow and precise), it fires by itself.
// Drag with the mouse or a finger to fly too. X, K or the BOMB button clears
// the screen. Only the glowing dot in the middle can be hit.
var speed = 340.0;
var focusSpeed = 150.0;
var fireRate = 12.0;
var dragSpeed = 1.15;     // how far the ship moves per pixel dragged

var art = "assets/templates/nova/";
var _cool = 0.0;
var _shots = 0;
var _blink = 0.0;         // invulnerable while blinking (spawn, respawn, bomb)
var _drag = null;
var _flicker = 0.0;
var shield = false;
var dead = false;

void onStart() {
  self.child("Shield").enabled = false;
  protect(2.0);
}

void onUpdate(dt) {
  if (dead || Game.paused) return;
  var stage = find("Stage");
  var focus = Input.key("Shift") || Input.pad(1).button("b") || Input.pad(1).trigger("left") > 0.5;
  var move = Input.move;
  var v = move.length > 0 ? move.normalized() * (focus ? focusSpeed : speed) : vec(0, 0);
  self.position = self.position + v * dt;
  if (Input.mouseDown) {
    if (_drag != null) self.position = self.position + (Input.mouse - _drag) * dragSpeed;
    _drag = Input.mouse;
  } else {
    _drag = null;
  }
  self.x = clamp(self.x, 40, 910);
  self.y = clamp(self.y, 34, 506);
  self.rotation = lerp(self.rotation, v.y * 0.0005, min(1, dt * 10));
  self.child("Core").enabled = focus;

  _flicker += dt;
  self.child("Thruster").sprite.frame = floor(_flicker * 24) % 2;
  self.child("Thruster").scale = vec(move.x > 0 ? 1.25 : (move.x < 0 ? 0.7 : 1), 1);

  if (_blink > 0) {
    _blink -= dt;
    self.sprite.opacity = floor(_blink * 14) % 2 == 0 ? 1 : 0.3;
    if (_blink <= 0) {
      self.sprite.opacity = 1;
      self.health.enabled = true;
    }
  } else {
    for (var e in findAll("enemy")) {
      if (self.overlaps(e)) {
        hit();
        return;
      }
    }
  }

  _cool -= dt;
  if (_cool <= 0) {
    _cool += 1 / fireRate;
    if (_cool < 0) _cool = 0;
    shoot(stage.script.power);
  }
  if (Input.pressed("X") || Input.pressed("K") || Input.pressed("B")) bomb();
}

void shoot(power) {
  var shots = find("Player Shots").bullets;
  var p = self.position + vec(34, 0);
  shots.fire(p + vec(0, -7), 0, 950);
  shots.fire(p + vec(0, 7), 0, 950);
  if (power >= 2) {
    shots.fire(p, -4, 930);
    shots.fire(p, 4, 930);
  }
  if (power >= 3) {
    shots.fire(self.position + vec(-6, -26), -10, 800, frame: 1, damage: 0.7);
    shots.fire(self.position + vec(-6, 26), 10, 800, frame: 1, damage: 0.7);
  }
  if (power >= 4) {
    shots.fire(self.position + vec(-10, -30), -20, 760, frame: 1, damage: 0.7);
    shots.fire(self.position + vec(-10, 30), 20, 760, frame: 1, damage: 0.7);
  }
  _shots++;
  if (_shots % 3 == 0) playSound(art + "shot.wav", 0.18);
}

void bomb() {
  if (dead || !find("Stage").call("useBomb")) return;
  strike(vec(480, 270), 1000, 600, damage: 14, team: "player");
  find("Camera").camera.flash("#FFE4C4", 0.7);
  find("Camera").camera.shake(14, 0.8);
  playSound(art + "bomb.wav", 0.8);
  var ring = spawn("Shockwave", self.position);
  tween(0.8, (t) {
    ring.scale = 0.2 + t * 6;
    ring.sprite.opacity = 1 - t;
  }, ease: "out", then: () { destroy(ring); });
  protect(2.0);
}

void protect(seconds) {
  _blink = max(_blink, seconds);
  self.health.enabled = false;
}

// Enemy bullets passing close by (Graze Radius on the Enemy Shots pool).
void onGraze() {
  if (!dead) find("Stage").call("graze", self.position);
}

void onDamaged(amount, source) {
  hit();
}

void hit() {
  if (dead || _blink > 0) return;
  if (shield) {
    shield = false;
    self.child("Shield").enabled = false;
    playSound(art + "hurt.wav", 0.4);
    find("Camera").camera.flash("#22D3EE", 0.3);
    find("Enemy Shots").bullets.clearAround(self.position, 160);
    protect(1.5);
    return;
  }
  dead = true;
  self.health.enabled = false;
  self.sprite.opacity = 0;
  self.child("Thruster").enabled = false;
  self.child("Core").enabled = false;
  playSound(art + "hurt.wav", 0.7);
  find("Stage").call("explode", self.position, 1.6);
  find("Camera").camera.flash("#FF4D6D", 0.4);
  var stage = find("Stage");
  stage.call("playerHit");
  if (stage.call("canRespawn")) after(1.3, respawn);
}

void respawn() {
  dead = false;
  self.position = vec(-60, 270);
  self.sprite.opacity = 1;
  self.child("Thruster").enabled = true;
  protect(2.6);
  tween(0.7, (t) { self.x = -60 + t * 210; }, ease: "out");
}

void collect(kind) {
  if (kind == "shield") {
    shield = true;
    self.child("Shield").enabled = true;
  }
  playSound(art + (kind == "crystal" ? "shot.wav" : "power.wav"), kind == "crystal" ? 0.12 : 0.6);
  find("Stage").call("collect", kind);
}

void onUIAction(action) {
  if (action == "bomb") bomb();
}
''';

const _enemy = r'''
// An enemy: Drone, Dart, Turret, Spinner or Cruiser (the "kind" variable).
// The stage calls launch(path, param, loop) right after spawning it:
//   sine  - weaves left;            cross - flies straight across
//   dive  - darts in to x = param, aims a burst, darts away
//   hold  - glides in to x = param, fights for a while, then leaves
var kind = "Drone";
var points = 100;
var crystals = 1;
var speed = 180.0;

var path = "sine";
var param = 0.0;
var diff = 1.0;
var t = 0.0;
var baseY = 0.0;
var _fire = 1.0;
var _spin = 0.0;
var _stay = 0.0;
var _leaving = false;

void launch(p, value, loop) {
  path = p;
  param = value;
  diff = 1 + (loop - 1) * 0.3;
  baseY = self.y;
  _fire = randomRange(0.6, 1.6) / diff;
  _stay = kind == "Cruiser" ? 12 : (kind == "Spinner" ? 9 : 7);
}

void onUpdate(dt) {
  t += dt;
  if (path == "sine") {
    self.x -= speed * dt;
    self.y = baseY + sin(t * 2.6 + param * 0.5) * 60;
  } else if (path == "cross") {
    self.x -= speed * 1.4 * dt;
  } else if (path == "dive") {
    dive(dt);
  } else {
    hold(dt);
  }
  if (kind == "Spinner") self.rotation += dt * 2.2;
  if (self.x < -120 || self.y < -140 || self.y > 680) destroy();
  if (self.x < 930) fight(dt);
}

void dive(dt) {
  if (!_leaving && self.x > param) {
    self.x -= max(80, (self.x - param) * 3.5) * dt;
    return;
  }
  if (!_leaving) {
    _leaving = true;
    var shots = find("Enemy Shots").bullets;
    shots.spread(self.position, angleTo(self, find("Ship")), 3, 26, 230 * diff, frame: 5);
    playSound("assets/templates/nova/shot.wav", 0.15, pitch: 0.6);
  }
  self.x -= 60 * dt;
  self.y += (baseY < 270 ? -1 : 1) * 420 * dt;
}

void hold(dt) {
  if (_stay > 0) {
    self.x += (param - self.x) * min(1, dt * 1.6);
    _stay -= dt;
  } else {
    self.x -= speed * 0.7 * dt;
  }
  self.y = baseY + sin(t * 0.9) * (kind == "Cruiser" ? 30 : 18);
}

void fight(dt) {
  if (path == "dive") return;
  _fire -= dt;
  if (_fire > 0) return;
  var shots = find("Enemy Shots").bullets;
  var ship = find("Ship");
  if (kind == "Drone") {
    _fire = 2.2 / diff;
    if (chance(0.6)) shots.fire(self.position, angleTo(self, ship), 170 * diff, frame: 2);
  } else if (kind == "Turret") {
    _fire = 0.11 / diff;
    _spin += 17;
    shots.fire(self.position + vec(-30, 0), _spin, 135 * diff, frame: 5);
    shots.fire(self.position + vec(-30, 0), _spin + 180, 135 * diff, frame: 5);
  } else if (kind == "Spinner") {
    _fire = 1.15 / diff;
    _spin += 13;
    shots.ring(self.position, 14, 115 * diff, offset: _spin, curve: _spin % 26 < 13 ? 22 : -22, frame: 4);
  } else if (kind == "Cruiser") {
    _fire = 1.6 / diff;
    _spin++;
    if (_spin % 2 == 0) shots.spread(self.position + vec(-120, 0), angleTo(self, ship), 7, 50, 180 * diff, frame: 3);
    else shots.ring(self.position, 22, 120 * diff, offset: randomRange(0, 16), frame: 6, scale: 1.1);
  }
}

void onDeath(killer) {
  find("Stage").call("enemyDown", points, self.position, kind, crystals);
}
''';

const _boss = r'''
// The Ember Dreadnought. Three phases (by health left), each with its own
// bullet patterns; moving between phases clears the screen.
var maxHealth = 900.0;

var art = "assets/templates/nova/";
var diff = 1.0;
var t = 0.0;
var phase = 0;
var entering = true;
var _fire = 0.0;
var _fire2 = 0.0;
var _spin = 0.0;
var _rest = 0.0;
var _flip = 1;

void launch(loop) {
  diff = 1 + (loop - 1) * 0.3;
  self.health.maxHealth = maxHealth * (1 + (loop - 1) * 0.4);
  self.health.health = self.health.maxHealth;
  self.health.enabled = false;   // can't be hurt while flying in
}

void onUpdate(dt) {
  t += dt;
  var core = self.child("Core");
  core.scale = 1 + sin(t * 6) * 0.08;
  find("Stage").call("bossHealth", self.health.health, self.health.maxHealth);
  if (entering) {
    self.x -= max(40, (self.x - 730) * 1.2) * dt;
    if (self.x <= 735) {
      entering = false;
      self.health.enabled = true;
      phase = 1;
      _rest = 0.8;
    }
    return;
  }
  var amp = phase == 3 ? 150 : 80;
  self.y = 270 + sin(t * 0.55) * amp;
  if (phase == 3) self.x = 730 + sin(t * 0.8) * 50;

  var left = self.health.health / self.health.maxHealth;
  var want = left > 0.66 ? 1 : (left > 0.33 ? 2 : 3);
  if (want != phase) changePhase(want);
  if (_rest > 0) {
    _rest -= dt;
    return;
  }
  if (phase == 1) phaseOne(dt);
  if (phase == 2) phaseTwo(dt);
  if (phase == 3) phaseThree(dt);
}

Vec2 corePos() => self.position + vec(-68, 0);
Vec2 cannon(side) => self.position + vec(-160, side * 87);

void phaseOne(dt) {
  var shots = find("Enemy Shots").bullets;
  var ship = find("Ship");
  _fire -= dt;
  _fire2 -= dt;
  if (_fire <= 0) {
    _fire = 0.9 / diff;
    _flip = -_flip;
    shots.spread(cannon(_flip), angleTo(cannon(_flip), ship), 5, 40, 210 * diff, frame: 3);
  }
  if (_fire2 <= 0) {
    _fire2 = 1.7 / diff;
    _spin += 11;
    shots.ring(corePos(), 18, 130 * diff, offset: _spin, frame: 2);
  }
}

void phaseTwo(dt) {
  var shots = find("Enemy Shots").bullets;
  _fire -= dt;
  _fire2 -= dt;
  if (_fire <= 0) {
    _fire = 0.075 / diff;
    _spin += 11;
    for (var k = 0; k < 3; k++) shots.fire(corePos(), _spin + k * 120, 150 * diff, frame: 5);
  }
  if (_fire2 <= 0) {
    _fire2 = 1.6 / diff;
    var c = cannon(randomInt(2) == 0 ? -1 : 1);
    shots.spread(c, angleTo(c, find("Ship")), 7, 60, 190 * diff, frame: 6);
  }
}

void phaseThree(dt) {
  var shots = find("Enemy Shots").bullets;
  _fire -= dt;
  _fire2 -= dt;
  if (_fire <= 0) {
    _fire = 0.55 / diff;
    _flip = -_flip;
    _spin += 7;
    shots.ring(corePos(), 20, 115 * diff, offset: _spin, curve: _flip * 30, frame: 4);
  }
  if (_fire2 <= 0) {
    _fire2 = 0.8 / diff;
    for (var side in [-1, 1]) shots.spread(cannon(side), angleTo(cannon(side), find("Ship")), 3, 12, 260 * diff, frame: 2);
  }
}

void changePhase(p) {
  phase = p;
  _rest = 1.4;
  _fire = 0;
  _fire2 = 0;
  var cleared = find("Enemy Shots").bullets.clear();
  find("Stage").call("addScore", cleared * 20 + 5000);
  find("Stage").call("explode", corePos(), 2.2);
  find("Camera").camera.flash("#F9A8D4", 0.5);
  find("Stage").call("banner", p == 2 ? "CORE EXPOSED" : "FINAL PHASE", "", 1.4);
}

void onDeath(killer) {
  find("Stage").call("bossDown", self.position);
}
''';

const _pickup = r'''
// A pickup: "power", "bomb", "shield" or "crystal" (score). It drifts left,
// and flies to the ship when the ship comes close.
var kind = "crystal";
var magnetRange = 150.0;

var t = 0.0;
var _v = vec(0, 0);

void onStart() {
  _v = vec(randomRange(-60, 40), randomRange(-90, 90));
}

void onUpdate(dt) {
  t += dt;
  var ship = find("Ship");
  var d = self.distanceTo(ship);
  if (d < magnetRange || kind == "crystal" && t > 0.6 && ship.script.dead == false) {
    var pull = kind == "crystal" ? 620 : 420;
    self.position = self.position + self.directionTo(ship) * pull * dt;
  } else {
    _v = _v * (1 - min(1, dt * 2)) + vec(-60, 0) * min(1, dt * 2);
    self.position = self.position + _v * dt;
    if (kind != "crystal") self.y += sin(t * 3) * 0.4;
  }
  self.rotation = kind == "crystal" ? t * 3 : 0;
  if (d < 26 && ship.script.dead == false) {
    ship.call("collect", kind);
    destroy();
  }
  if (self.x < -60 || t > 14) destroy();
}
''';

const _title = r'''
// Title screen: best score and loop, a gliding ship, start.
var t = 0.0;

void onStart() {
  Game.timeScale = 1;
  Game.data["nova"] = null;
  playMusic("assets/templates/nova/nova.wav", 0.4);
  var best = loadValue("nova_best", 0);
  var loop = loadValue("nova_loop", 1);
  setText("BestText", best > 0 ? "BEST  $best     LOOP $loop" : "");
}

void onUpdate(dt) {
  t += dt;
  var ship = find("Title Ship");
  ship.y = 330 + sin(t * 1.6) * 14;
  ship.rotation = cos(t * 1.6) * 0.04;
  ship.child("Thruster").sprite.frame = floor(t * 24) % 2;
}

void onUIAction(action) {
  if (action == "start") loadLevel("Stage");
}
''';

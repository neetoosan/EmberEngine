/// Ember Script source for the "Ember Arena" template (editable in the
/// Script workspace once a project is created from it).
const Map<String, String> arenaScripts = {
  'arena.ember': _arena,
  'arena_player.ember': _player,
  'arena_robot.ember': _robot,
  'arena_pickup.ember': _pickup,
  'arena_title.ember': _title,
};

const _arena = r'''
// Ember Arena: robots pour out of four portals in waves. Each wave is bigger;
// survive as long as you can. Score, best wave and best score are saved.
var firstWaveDelay = 2.5;   // seconds before wave 1
var breakTime = 5.0;        // rest between waves
var spawnInterval = 0.8;    // seconds between robots coming through
var maxAlive = 12;          // robots in the arena at once (more wait their turn)
var dropChance = 0.2;       // a destroyed robot sometimes leaves a pickup

var portals = [vec3(0, 0, -15.5), vec3(15.5, 0, 0), vec3(0, 0, 15.5), vec3(-15.5, 0, 0)];
var pads = [vec3(-9, 0.7, -9), vec3(9, 0.7, -9), vec3(9, 0.7, 9), vec3(-9, 0.7, 9)];

var wave = 0;
var score = 0;
var alive = 0;
var queue = [];
var state = "start";   // start, fight, break, over
var timer = 0.0;
var _banner = 0.0;

void onStart() {
  playMusic("assets/templates/arena/arena.wav", 0.35);
  timer = firstWaveDelay;
  banner("GET READY", "Robots come through the portals", 2.4);
  hud();
}

void onUpdate(dt) {
  if (_banner > 0) {
    _banner -= dt;
    if (_banner <= 0) banner("", "", 0);
  }
  if (state == "over") return;
  timer -= dt;
  if (state == "start" || state == "break") {
    if (timer <= 0) startWave();
    return;
  }
  if (queue.isNotEmpty && timer <= 0 && alive < maxAlive) {
    spawnNext();
    timer = spawnInterval;
  }
  if (queue.isEmpty && alive == 0) waveCleared();
}

// Which robots a wave sends: more of everything, Brutes from wave 4.
List roster(n) {
  var list = [];
  for (var i = 0; i < min(3 + n, 10); i++) list.add("Drone");
  if (n >= 2) for (var i = 0; i < min(n, 8); i++) list.add("Gunner");
  if (n >= 4) for (var i = 0; i < min(floor((n - 2) / 2), 5); i++) list.add("Brute");
  // Shuffle so the kinds arrive mixed
  for (var i = list.length - 1; i > 0; i--) {
    var j = randomInt(i + 1);
    var t = list[i];
    list[i] = list[j];
    list[j] = t;
  }
  return list;
}

void startWave() {
  wave++;
  state = "fight";
  timer = 0.6;
  queue = roster(wave);
  banner("WAVE $wave", "${queue.length} robots", 2.0);
  playSound("coin", 0.5);
  hud();
}

void spawnNext() {
  var kind = queue.removeAt(0);
  var p = portals[randomInt(portals.length)];
  var y = kind == "Drone" ? 1.6 : (kind == "Brute" ? 1.2 : 0.95);
  var robot = spawn(kind, vec3(p.x * 0.92 + randomRange(-1.5, 1.5), y, p.z * 0.92 + randomRange(-1.5, 1.5)));
  robot.lookAt(vec3(0, y, 0));
  find("Portal FX").particles.burst(24, p * 0.95 + vec3(0, 1.6, 0));
  alive++;
  hud();
}

// Called by each robot's script when it is destroyed.
void robotDown(points, where) {
  alive = max(0, alive - 1);
  score += points;
  if (points > 0 && chance(dropChance)) {
    spawn(chance(0.5) ? "Health Pack" : "Ammo Crate", vec3(where.x, 0.7, where.z));
  }
  hud();
}

void waveCleared() {
  state = "break";
  timer = breakTime;
  var bonus = wave * 150;
  score += bonus;
  banner("WAVE $wave CLEARED", "+$bonus bonus", 2.8);
  // Supplies on two of the corner pads
  spawn("Health Pack", pads[randomInt(2) * 2]);
  spawn("Ammo Crate", pads[randomInt(2) * 2 + 1]);
  saveBest();
  hud();
}

// Called by the player's script when its health runs out.
void playerDied() {
  if (state == "over") return;
  state = "over";
  saveBest();
  stopMusic();
  Input.lockMouse(false);
  banner("", "", 0);
  for (var name in ["GameOverPanel", "GameOverTitle", "GameOverStats", "RetryButton", "MenuButton"]) {
    find(name).enabled = true;
  }
  setText("GameOverStats", "You reached wave $wave with $score points\nBest: wave ${loadValue("arena_best_wave", 0)}  ·  ${loadValue("arena_best_score", 0)} points");
}

void saveBest() {
  saveValue("arena_best_wave", max(wave, loadValue("arena_best_wave", 0)));
  saveValue("arena_best_score", max(score, loadValue("arena_best_score", 0)));
}

void onUIAction(action) {
  if (action == "retry") restart();
}

void hud() {
  setText("WaveText", wave == 0 ? "WAVE -" : "WAVE $wave");
  setText("RobotsText", "Robots ${alive + queue.length}");
  setText("ScoreText", "$score");
}

void banner(title, line, seconds) {
  setText("Banner", title);
  setText("BannerLine", line);
  _banner = seconds;
}
''';

const _player = r'''
// The player: mouse-look, WASD + Space + Shift, and two weapons.
//   1 / 2 or Q: switch weapon     Left mouse: fire (hold for the blaster)
var sensitivity = 0.15;     // degrees per pixel of mouse movement
var blasterDamage = 1;
var blasterRate = 0.14;     // seconds between blaster shots
var scatterPellets = 8;
var scatterDamage = 1;
var scatterSpread = 0.07;
var scatterRate = 0.75;
var maxAmmo = 40;
var ammo = 12;              // scatter shells
var weapon = 1;

var _cool = 0.0;
var _pitch = 0.0;
var _kick = 0.0;
var _bob = 0.0;
var _hurt = 0.0;
var _marker = 0.0;
var _gunHome = vec3(0.26, 0.45, -0.66);

void onStart() {
  Input.lockMouse();      // the mouse aims (click the game to capture it)
  _pitch = self.pitch;
  setWeapon(1);
}

void onUpdate(dt) {
  timers(dt);
  if (self.health.dead) return;
  look();
  walk(dt);
  weapons();
}

void timers(dt) {
  _cool -= dt;
  _kick = max(0, _kick - dt * 6);
  if (_hurt > 0) {
    _hurt -= dt;
    if (_hurt <= 0) find("HurtFlash").enabled = false;
  }
  if (_marker > 0) {
    _marker -= dt;
    if (_marker <= 0) setText("HitMarker", "");
  }
}

void look() {
  var m = Input.mouseDelta;
  self.yaw = self.yaw - m.x * sensitivity;
  _pitch = clamp(_pitch - m.y * sensitivity, -85, 85);
  self.pitch = _pitch;
}

void walk(dt) {
  var mv = Input.move;   // x: right, y: back (so -y is forward)
  var dir = self.forward.flat.normalized() * -mv.y + self.right.flat.normalized() * mv.x;
  var sprint = Input.action("sprint");
  self.controller.move(dir, sprint);
  if (Input.actionPressed("jump") && self.controller.jump()) playSound("jump", 0.35);
  // Gun sway while walking, kick when firing
  if (dir.length > 0.1 && self.controller.grounded) _bob += dt * (sprint ? 13 : 9);
  self.child("Gun").position = _gunHome + vec3(sin(_bob) * 0.012, abs(cos(_bob)) * 0.012 - _kick * 0.03, _kick * 0.09);
}

void weapons() {
  if (Input.pressed("1")) setWeapon(1);
  if (Input.pressed("2")) setWeapon(2);
  if (Input.pressed("Q")) setWeapon(3 - weapon);
  if (_cool > 0 || !Input.mouseDown) return;
  if (weapon == 1) {
    fireBlaster();
  } else if (ammo > 0) {
    fireScatter();
  } else if (Input.click) {
    playSound("click", 0.6);
    setWeapon(1);
  }
}

void setWeapon(w) {
  weapon = w;
  var core = self.child("Gun").child("Core").mesh;
  core.color = w == 1 ? "#FF7A1A" : "#38BDF8";
  hud();
}

Vec3 eye() => self.worldPosition + vec3(0, 0.72, 0);

void fireBlaster() {
  _cool = blasterRate;
  _kick = 1;
  playSound("laser", 0.3);
  self.child("Gun").child("Core").mesh.flash("#FFFFFF", 0.06);
  shoot(self.forward, blasterDamage, 2);
}

void fireScatter() {
  _cool = scatterRate;
  _kick = 2;
  ammo--;
  playSound("explosion", 0.25);
  self.child("Gun").child("Core").mesh.flash("#FFFFFF", 0.1);
  var f = self.forward;
  var r = self.right;
  var u = self.up;
  for (var i = 0; i < scatterPellets; i++) {
    var d = f + r * randomRange(-scatterSpread, scatterSpread) + u * randomRange(-scatterSpread, scatterSpread);
    shoot(d.normalized(), scatterDamage, 3);
  }
  hud();
}

// One hitscan ray: sparks where it lands, damage if it hit a robot.
void shoot(dir, damage, push) {
  var from = eye();
  var hit = Physics.raycast(from, from + dir * 90, self);
  if (hit == null) return;
  find("Spark FX").particles.burst(5, hit.point);
  var e = hit.entity;
  if (e.has("Health") && !e.health.dead) {
    e.health.damage(damage, self, dir * push);
    setText("HitMarker", "x");
    _marker = 0.12;
  }
}

void onDamaged(amount, source) {
  playSound("hit", 0.8);
  find("HurtFlash").enabled = true;
  _hurt = 0.18;
  hud();
}

void onDeath(killer) {
  find("Arena").call("playerDied");
}

// Called by pickups. Returns true when used.
bool pickup(kind, amount) {
  if (kind == "health") {
    if (self.health.health >= self.health.maxHealth) return false;
    self.health.heal(amount);
  } else {
    if (ammo >= maxAmmo) return false;
    ammo = min(maxAmmo, ammo + amount);
  }
  hud();
  return true;
}

void hud() {
  var hp = self.health;
  var bar = find("HealthBar").bar;
  bar.value = hp.health;
  bar.max = hp.maxHealth;
  bar.label = "HP ${round(hp.health)}";
  setText("WeaponText", weapon == 1 ? "1  BLASTER" : "2  SCATTER");
  setText("AmmoText", weapon == 1 ? "∞" : "$ammo / $maxAmmo");
}
''';

const _robot = r'''
// A robot (Drone, Gunner or Brute): it moves and fights with its Enemy AI 3D.
// This script adds points, sound and sparks, and the Brute's warning glow.
var points = 100;

void onUpdate(dt) {
  // A Brute's eye flares while it winds up a charge: time to dodge
  if (self.enemy.state == "windup") self.child("Eye").mesh.flash("#FFFFFF", 0.08);
}

void onDamaged(amount, source) {
  playSound("hit", 0.45);
}

void onDeath(killer) {
  find("Explosion FX").particles.burst(26, self.worldPosition);
  playSound("explosion", 0.5);
  // A drone that blew itself up on the player scores nothing
  find("Arena").call("robotDown", killer == self ? 0 : points, self.worldPosition);
}
''';

const _pickup = r'''
// A pickup: spins and bobs; walk into it for health or scatter shells.
var kind = "health";   // health or ammo
var amount = 30;
var lifetime = 25.0;   // seconds before it fades away
var _t = 0.0;
var _baseY = 0.7;

void onStart() {
  _baseY = self.y;
}

void onUpdate(dt) {
  _t += dt;
  self.yaw = self.yaw + 120 * dt;
  self.y = _baseY + sin(_t * 3) * 0.12;
  var player = find("Player");
  if (player != null && self.distanceTo(player) < 1.5 && player.call("pickup", kind, amount)) {
    playSound("coin", 0.7);
    destroy();
  }
  if (_t > lifetime) destroy();
}
''';

const _title = r'''
// Title screen: the camera circles the arena; shows your best run.
var radius = 14.5;
var height = 8.5;
var speed = 0.12;   // radians per second
var _a = 0.6;

void onStart() {
  playMusic("assets/templates/arena/arena.wav", 0.3);
  setText("BestText", "Best: wave ${loadValue("arena_best_wave", 0)}  ·  ${loadValue("arena_best_score", 0)} points");
}

void onUpdate(dt) {
  _a += speed * dt;
  self.position = vec3(sin(_a) * radius, height, cos(_a) * radius);
  self.lookAt(vec3(0, 1, 0), false);
}

void onUIAction(action) {
  if (action != "reset") return;
  deleteValue("arena_best_wave");
  deleteValue("arena_best_score");
  restart();
}
''';

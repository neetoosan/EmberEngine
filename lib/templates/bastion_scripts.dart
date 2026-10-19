/// Ember Script source for the "Ember Bastion" template (editable in the
/// Script workspace once a project is created from it).
const Map<String, String> bastionScripts = {
  'bastion_game.ember': _game,
  'bastion_tower.ember': _tower,
  'bastion_enemy.ember': _enemy,
  'bastion_shots.ember': _shots,
  'bastion_title.ember': _title,
};

const _game = r'''
// Ember Bastion: stop every wave before it reaches the keep. Build towers on
// the grass (not on the road), upgrade them, sell them. 15 waves.
var startGold = 220;
var startLives = 20;
var waveCount = 15;
var cell = 40;
var sellBack = 0.7;       // selling returns this share of what was spent

var art = "assets/templates/bastion/";
var kinds = ["Archer", "Cannon", "Frost", "Tesla"];
var costs = {"Archer": [50, 60, 90], "Cannon": [90, 100, 140], "Frost": [70, 80, 110], "Tesla": [120, 130, 170]};
var gold = 0;
var lives = 0;
var wave = 0;
var hard = false;
var state = "build";      // build, wave, won, lost
var queue = [];           // [seconds into the wave, kind]
var waveTime = 0.0;
var alive = 0;
var placing = "";         // the tower type being placed, or ""
var selected = null;
var towers = {};          // "x,y" -> tower
var fast = false;
var leaks = 0;
var _banner = 0.0;

void onStart() {
  hard = Game.data["bastionHard"] == true;
  gold = hard ? startGold - 40 : startGold;
  lives = startLives;
  playMusic(art + "bastion.wav", 0.4);
  banner("BUILD YOUR DEFENCES", "Pick a tower below, then click the grass. Press Start when ready.", 4);
  hud();
}

// --- Every frame ---------------------------------------------------------------

void onUpdate(dt) {
  if (_banner > 0) {
    _banner -= dt;
    if (_banner <= 0) banner("", "", 0);
  }
  if (state == "won" || state == "lost") return;
  for (var i = 0; i < kinds.length; i++) {
    if (Input.pressed("${i + 1}")) choose(kinds[i]);
  }
  if (Input.pressed("Space") && state == "build") startWave();
  if (Input.pressed("F")) toggleSpeed();
  if (Input.pressed("Escape")) {
    choose("");
    select(null);
  }

  if (placing != "") updateGhost();
  else if (Input.click) select(towerAt(snap(Input.mouse, cell)));

  if (state == "wave") {
    waveTime += dt;
    while (queue.isNotEmpty && queue[0][0] <= waveTime) {
      spawnEnemy(queue.removeAt(0)[1]);
    }
    if (queue.isEmpty && alive <= 0) waveCleared();
  }
}

// --- Building ------------------------------------------------------------------

void choose(kind) {
  placing = placing == kind ? "" : kind;
  select(null);
  find("Ghost").enabled = placing != "";
  find("Cell").enabled = placing != "";
  find("Range").enabled = placing != "";
  if (placing != "") {
    var i = kinds.indexOf(placing);
    find("Ghost").sprite.frame = i * 3;
    find("Ghost").child("Top").sprite.frame = i * 3;
    showRange(find("Ghost").position, rangeOf(placing, 0));
  }
  hud();
}

void updateGhost() {
  var at = snap(Input.mouse, cell);
  var ghost = find("Ghost");
  ghost.position = at;
  var ok = canBuild(at) && gold >= costs[placing][0];
  ghost.sprite.tint = ok ? "#FFFFFF" : "#FF7A7A";
  ghost.child("Top").sprite.tint = ok ? "#FFFFFF" : "#FF7A7A";
  find("Cell").position = at;
  find("Cell").sprite.tint = ok ? "#BBF7D0" : "#FCA5A5";
  showRange(at, rangeOf(placing, 0));
  find("Range").sprite.tint = ok ? "#FFFFFF" : "#FF8A8A";
  if (Input.click && towerAt(at) != null) {
    // Clicking a tower while building selects it instead
    var t = towerAt(at);
    choose("");
    select(t);
    return;
  }
  if (Input.click && Input.mouse.y > 44 && Input.mouse.y < 470) {
    if (ok) build(placing, at);
    else if (gold < costs[placing][0]) banner("", "Not enough gold", 1.2);
    else banner("", "You can't build there", 1.2);
  }
}

bool canBuild(at) {
  if (at.x < 20 || at.x > 940 || at.y < 60 || at.y > 452) return false;
  if (towerAt(at) != null) return false;
  if (find("Path").line.distanceTo(at) < 44) return false;
  if (findInRange("blocked", at, 30).isNotEmpty) return false;
  return true;
}

String key(at) => "${round(at.x)},${round(at.y)}";
Object towerAt(at) => towers[key(at)];

void build(kind, at) {
  var cost = costs[kind][0];
  gold -= cost;
  var t = spawn(kind + " Tower", at);
  t.script.spent = cost;
  towers[key(at)] = t;
  playSound(art + "build.wav", 0.6);
  find("Dust FX").particles.burst(16, at + vec(0, 10));
  t.scale = 0.6;
  tween(0.25, (k) { t.scale = 0.6 + k * 0.4; }, ease: "back");
  if (!Input.key("Shift")) choose("");   // hold Shift to keep building
  hud();
}

int rangeOf(kind, level) {
  if (kind == "Archer") return [130, 145, 165][level];
  if (kind == "Cannon") return [115, 125, 140][level];
  if (kind == "Frost") return [95, 105, 120][level];
  return [120, 130, 145][level];
}

void showRange(at, r) {
  var ring = find("Range");
  ring.enabled = true;
  ring.position = at;
  ring.scale = r / 64;
}

// --- Selecting, upgrading, selling --------------------------------------------

void select(t) {
  selected = t;
  var on = t != null;
  find("UpgradeButton").enabled = on;
  find("SellButton").enabled = on;
  find("Range").enabled = on || placing != "";
  if (!on) return;
  find("Range").sprite.tint = "#FFFFFF";
  showRange(t.position, t.script.range);
  var x = clamp(t.x - 70, 8, 812);
  var y = t.y > 360 ? t.y - 92 : t.y + 30;
  find("UpgradeButton").button.offset = vec(x, y);
  find("SellButton").button.offset = vec(x, y + 34);
  hud();
}

void upgrade() {
  if (selected == null || selected.script.level >= 2) return;
  var cost = costs[selected.script.type][selected.script.level + 1];
  if (gold < cost) {
    banner("", "Not enough gold", 1.2);
    return;
  }
  gold -= cost;
  selected.script.spent += cost;
  selected.call("levelUp");
  playSound(art + "build.wav", 0.6, pitch: 1.3);
  find("Dust FX").particles.burst(10, selected.position);
  select(selected);
}

void sell() {
  if (selected == null) return;
  gold += floor(selected.script.spent * sellBack);
  towers.remove(key(selected.position));
  find("Dust FX").particles.burst(14, selected.position);
  playSound(art + "coin.wav", 0.5);
  destroy(selected);
  select(null);
  hud();
}

// --- Waves ---------------------------------------------------------------------

// What wave n sends: more of everything; runners from 3, golems from 4,
// wisps from 6, and a dark knight every fifth wave.
List makeWave(n) {
  _plan = [];
  _planTime = 0.0;
  group("Grunt", 5 + n * 2, max(0.45, 1.0 - n * 0.04));
  if (n >= 3) group("Runner", 2 + n, 0.5);
  if (n >= 4) group("Golem", floor(n / 3), 2.0);
  if (n >= 6) group("Wisp", n, 0.3);
  if (n % 5 == 0) group("Knight", round(n / 5), 3.0);
  return _plan;
}

var _plan = [];
var _planTime = 0.0;

// count enemies of a kind, gap seconds apart, after the previous group
void group(kind, count, gap) {
  for (var i = 0; i < count; i++) {
    _plan.add([_planTime, kind]);
    _planTime += gap;
  }
  _planTime += 1.2;
}

void startWave() {
  if (state != "build") return;
  wave++;
  state = "wave";
  waveTime = 0;
  queue = makeWave(wave);
  playSound(art + "horn.wav", 0.5);
  banner("WAVE $wave", wave % 5 == 0 ? "A Dark Knight leads them" : "${queue.length} enemies", 2.2);
  hud();
}

void spawnEnemy(kind) {
  var e = spawn(kind, vec(-30, 112));
  e.call("setup", wave, hard ? 1.35 : 1.0);
  alive++;
}

// Called by an enemy when it is defeated.
void enemyDown(reward, where) {
  alive = max(0, alive - 1);
  gold += reward;
  find("Coin FX").particles.burst(6, where);
  playSound(art + "coin.wav", 0.25);
  hud();
}

// Called by an enemy that reaches the keep.
void leaked(cost) {
  alive = max(0, alive - 1);
  lives = max(0, lives - cost);
  leaks++;
  playSound(art + "leak.wav", 0.6);
  find("Camera").camera.shake(6, 0.3);
  find("Camera").camera.flash("#EF4444", 0.25);
  hud();
  if (lives <= 0 && state != "lost") defeat();
}

void waveCleared() {
  if (wave >= waveCount) {
    victory();
    return;
  }
  state = "build";
  var bonus = 20 + wave * 5;
  gold += bonus;
  banner("WAVE $wave CLEARED", "+$bonus gold. Build, then start wave ${wave + 1}.", 3);
  hud();
}

void toggleSpeed() {
  fast = !fast;
  Game.timeScale = fast ? 2 : 1;
  find("SpeedButton").button.text = fast ? "x2" : "x1";
}

// --- Ending --------------------------------------------------------------------

void victory() {
  state = "won";
  Game.timeScale = 1;
  var stars = lives >= startLives ? 3 : (lives >= startLives / 2 ? 2 : 1);
  var saveKey = hard ? "bastion_stars_hard" : "bastion_stars";
  if (stars > loadValue(saveKey, 0)) saveValue(saveKey, stars);
  playSound(art + "victory.wav", 0.7);
  showResults("VICTORY", "The keep stands. Lives left: $lives", stars);
}

void defeat() {
  state = "lost";
  Game.timeScale = 1;
  find("Camera").camera.shake(14, 0.8);
  showResults("THE KEEP HAS FALLEN", "You held out until wave $wave", 0);
}

void showResults(title, line, stars) {
  choose("");
  select(null);
  for (var n in ["ResultsPanel", "ResultsTitle", "ResultsLine", "RetryButton", "MenuButton"]) find(n).enabled = true;
  find("ResultsTitle").text.text = title;
  find("ResultsLine").text.text = line;
  find("ResultsStars").enabled = stars > 0;
  find("ResultsStars").image.filled = stars;
}

// --- HUD -----------------------------------------------------------------------

void hud() {
  setText("GoldText", "$gold");
  setText("LivesText", "$lives");
  setText("WaveText", "Wave $wave / $waveCount");
  find("StartButton").enabled = state == "build";
  find("StartButton").button.text = "START WAVE ${wave + 1}";
  for (var k in kinds) {
    var b = find(k + "Button").button;
    b.text = "$k  ${costs[k][0]}";
    b.color = placing == k ? "#FBBF24" : (gold >= costs[k][0] ? "#E7E5E4" : "#78716C");
  }
  if (selected != null) {
    var lvl = selected.script.level;
    var up = find("UpgradeButton").button;
    up.text = lvl >= 2 ? "MAX LEVEL" : "UPGRADE  ${costs[selected.script.type][lvl + 1]}";
    up.color = lvl < 2 && gold >= costs[selected.script.type][lvl + 1] ? "#4ADE80" : "#78716C";
    find("SellButton").button.text = "SELL  ${floor(selected.script.spent * sellBack)}";
  }
}

void banner(title, subtitle, seconds) {
  setText("Banner", title);
  setText("Subtitle", subtitle);
  _banner = seconds;
}

void onUIAction(action) {
  if (action.startsWith("build:")) choose(action.substring(6));
  if (action == "start") startWave();
  if (action == "speed") toggleSpeed();
  if (action == "upgrade") upgrade();
  if (action == "sell") sell();
  if (action == "retry") {
    Game.timeScale = 1;
    restart();
  }
  if (action == "menu") {
    Game.timeScale = 1;
    loadLevel("Title");
  }
}
''';

const _tower = r'''
// A tower: Archer (fast arrows), Cannon (splash), Frost (slows everything
// near it) or Tesla (lightning that jumps between enemies). Three levels.
// It aims at the enemy furthest along the road.
var type = "Archer";
var level = 0;
var spent = 0;

var range = 130.0;
var rate = 1.0;           // shots per second
var damage = 6.0;
var splash = 0.0;
var slowBy = 0.5;
var chains = 3;
var art = "assets/templates/bastion/";
var _cool = 0.0;

void onStart() {
  apply();
}

void apply() {
  var t = ["Archer", "Cannon", "Frost", "Tesla"].indexOf(type);
  self.sprite.frame = t * 3 + level;
  self.child("Top").sprite.frame = t * 3 + level;
  if (type == "Archer") {
    range = [130, 145, 165][level];
    rate = [1.4, 1.8, 2.4][level];
    damage = [6, 10, 16][level];
  } else if (type == "Cannon") {
    range = [115, 125, 140][level];
    rate = [0.55, 0.65, 0.8][level];
    damage = [14, 22, 34][level];
    splash = [45, 55, 65][level];
  } else if (type == "Frost") {
    range = [95, 105, 120][level];
    rate = [0.8, 0.9, 1.0][level];
    damage = [3, 5, 8][level];
    slowBy = [0.55, 0.45, 0.35][level];
  } else {
    range = [120, 130, 145][level];
    rate = [0.8, 0.95, 1.1][level];
    damage = [12, 18, 26][level];
    chains = [3, 4, 5][level];
  }
}

void levelUp() {
  if (level >= 2) return;
  level++;
  apply();
  self.scale = 1.25;
  tween(0.3, (k) { self.scale = 1.25 - k * 0.25; }, ease: "out");
}

void onUpdate(dt) {
  _cool -= dt;
  var targets = findInRange("enemy", self.position, range);
  if (targets.isEmpty) return;
  var target = targets[0];
  for (var e in targets) {
    if (e.follower.progress > target.follower.progress) target = e;
  }
  var top = self.child("Top");
  if (type == "Archer" || type == "Cannon") top.rotation = radians(angleTo(self, target));
  if (type == "Tesla") top.rotation += dt * 2;
  if (_cool > 0) return;
  _cool = 1 / rate;
  if (type == "Archer") arrow(target);
  if (type == "Cannon") cannon(target);
  if (type == "Frost") frost(targets);
  if (type == "Tesla") lightning(target);
}

void arrow(target) {
  var armor = target.script.armor;
  find("Shots").bullets.fire(self.position, angleTo(self, target), 560, frame: 0, target: target, turn: 900, damage: max(1, damage - armor), radius: 7);
  playSound(art + "arrow.wav", 0.25);
}

void cannon(target) {
  var a = radians(angleTo(self, target));
  find("Shots").bullets.fire(self.position + vec(cos(a), sin(a)) * 26, degrees(a), 340, frame: 1, target: target, turn: 420, damage: damage, splash: splash, radius: 8);
  playSound(art + "cannon.wav", 0.35);
  self.child("Top").scale = 0.88;
  tween(0.2, (k) { self.child("Top").scale = 0.88 + k * 0.12; });
}

void frost(targets) {
  for (var e in targets) {
    e.follower.slow(slowBy, 1.8);
    e.health.damage(damage);
  }
  var ring = spawn("Frost Ring", self.position);
  tween(0.5, (k) {
    ring.scale = 0.2 + k * range / 64;
    ring.sprite.opacity = 1 - k;
  }, ease: "out", then: () { destroy(ring); });
  playSound(art + "frost.wav", 0.3);
}

// Strikes the target, then jumps to the next nearest enemy, and so on.
void lightning(target) {
  var hit = [target];
  var current = target;
  for (var k = 1; k < chains; k++) {
    var next = null;
    for (var e in findInRange("enemy", current.position, 95)) {
      if (!hit.contains(e)) {
        next = e;
        break;
      }
    }
    if (next == null) break;
    hit.add(next);
    current = next;
  }
  var points = [self.position + vec(0, -6)];
  for (var i = 0; i < hit.length; i++) {
    var from = points[points.length - 1];
    var to = hit[i].position;
    // A jagged bolt: two kinks between each pair
    for (var j = 1; j <= 2; j++) {
      var p = lerp(from, to, j / 3);
      points.add(p + vec(randomRange(-9, 9), randomRange(-9, 9)));
    }
    points.add(to);
    hit[i].health.damage(damage * (1 - i * 0.12));
  }
  var bolt = spawn("Bolt", vec(0, 0));
  bolt.line.points = points;
  bolt.destroy(0.12);
  find("Spark FX").particles.burst(8, hit[hit.length - 1].position);
  playSound(art + "zap.wav", 0.3);
}
''';

const _enemy = r'''
// An enemy marching along the road (its Path Follower). It gets tougher
// every wave. Reaching the keep costs lives; defeating it pays gold.
var kind = "Grunt";
var hp = 30.0;
var speed = 55.0;
var reward = 5;
var leak = 1;             // lives lost if it reaches the keep
var armor = 0;            // arrows do this much less damage
var growth = 0.16;        // extra health per wave

var t = 0.0;

void setup(wave, difficulty) {
  var tough = (1 + (wave - 1) * growth) * difficulty;
  self.health.maxHealth = round(hp * tough);
  self.health.health = self.health.maxHealth;
  self.follower.speed = speed * randomRange(0.94, 1.06);
}

void onUpdate(dt) {
  t += dt;
  // A little bob as it walks; a blue tint while frozen
  var s = 1 + sin(t * 10) * 0.04;
  if (kind == "Wisp") s = 1 + sin(t * 6) * 0.1;
  self.scale = s;
  self.sprite.tint = self.follower.slowed ? "#9BD7FF" : "#FFFFFF";
}

void onPathEnd() {
  find("Game").call("leaked", leak);
  destroy();
}

void onDeath(killer) {
  find("Game").call("enemyDown", reward, self.position);
  find("Pop FX").particles.burst(kind == "Knight" ? 40 : 14, self.position);
}
''';

const _shots = r'''
// Effects where tower shots land: cannonballs explode.
var art = "assets/templates/bastion/";

void onBulletHit(at, victim, frame) {
  if (frame == 1) {
    find("Boom FX").particles.burst(18, at);
    var ring = spawn("Blast Ring", at);
    tween(0.35, (k) {
      ring.scale = 0.2 + k * 0.9;
      ring.sprite.opacity = 1 - k;
    }, ease: "out", then: () { destroy(ring); });
    find("Camera").camera.shake(2, 0.15);
  }
}
''';

const _title = r'''
// Title screen: Normal or Hard, and the stars earned on each.
void onStart() {
  Game.timeScale = 1;
  playMusic("assets/templates/bastion/bastion.wav", 0.35);
  find("NormalStars").image.filled = loadValue("bastion_stars", 0);
  find("HardStars").image.filled = loadValue("bastion_stars_hard", 0);
}

void onUIAction(action) {
  if (action == "normal" || action == "hard") {
    Game.data["bastionHard"] = action == "hard";
    loadLevel("Battle");
  }
}
''';

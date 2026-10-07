/// Ember Siege's gameplay as Ember Script. New projects get these as
/// editable `.ember` files (Script workspace).
library;

const siegeScripts = <String, String>{
  'siege_level.ember': _level,
  'siege_slingshot.ember': _slingshot,
  'siege_shot.ember': _shot,
  'siege_block.ember': _block,
  'siege_imp.ember': _imp,
  'siege_keg.ember': _keg,
  'siege_title.ember': _title,
};

const _level = r'''
// Level flow: load each shot onto the slingshot, wait for the castle to
// settle, count the frost imps, then score, stars, saving and results.
var ammo = "ember,ember,ember";   // shots in order: ember, coal or spark
var levelTitle = "Frostgate";
var nextLevel = "Level 2";        // empty on the last level
var twoStars = 18000;             // score needed for two / three stars
var threeStars = 28000;
var impPoints = 5000;
var unusedShotBonus = 10000;

var state = "starting";           // loading, aiming, flying, settling, won, lost
var score = 0;
var _waiting = [];                // shots lined up behind the slingshot
var _total = 0;
var _fired = 0;
var _imps = 0;
var _wait = 0.0;
var _over = false;

title(kind) => kind == "coal" ? "Coal" : (kind == "spark" ? "Spark" : "Ember");
bestKey() => "siege_best_${Game.level}";
starsKey() => "siege_stars_${Game.level}";
levelNumber() => Game.level.split(" ").last.toNumber();

void onStart() {
  _imps = findAll("imp").length;
  var i = 0;
  for (var kind in ammo.split(",")) {
    kind = kind.trim();
    if (kind == "") continue;
    var shot = spawn("${title(kind)} Template", vec(170 - i * 34, 594));
    shot.name = title(kind);
    _waiting.add(shot);
    i++;
  }
  _total = _waiting.length;
  setText("LevelText", "${Game.level}  ·  $levelTitle");
  setText("BestText", "Best ${loadValue(bestKey(), 0)}");
  showResults(false);
  updateHud();
  playMusic("assets/templates/siege/siege.wav", 0.4);
  after(0.4, () => loadNext());
}

void onUpdate(dt) {
  if (Input.pressed("R")) restart();
  if (state != "settling") return;
  _wait += dt;
  if ((_wait > 0.8 && Physics.settled) || _wait > 5) {
    if (_imps <= 0) {
      win();
    } else if (_waiting.isEmpty) {
      lose();
    } else {
      loadNext();
    }
  }
}

/// Hops the next shot from the line-up into the slingshot.
void loadNext() {
  if (_over || _waiting.isEmpty) return;
  state = "loading";
  var shot = _waiting.removeAt(0);
  var sling = find("Slingshot");
  var from = shot.position;
  var to = sling.call("pouch");
  tween(0.35, (t) { shot.position = lerp(from, to, t) + vec(0, -sin(t * pi) * 70); }, ease: "out", then: () {
    sling.call("load", shot);
    state = "aiming";
  });
  var i = 0;
  for (var w in _waiting) {
    w.x = 170 - i * 34;
    i++;
  }
}

void shotFired() {
  state = "flying";
  _fired++;
  setText("HintText", "");
  updateHud();
}

void shotFinished() {
  if (state != "flying") return;
  state = "settling";
  _wait = 0;
}

void addScore(points) {
  score += points;
  updateHud();
}

void shake(amount) => find("Camera").camera.shake(amount, 0.35);

void blockBroken(block) {
  var m = block.script.material;
  addScore(block.script.points);
  find("${m == "ice" ? "Ice" : (m == "stone" ? "Stone" : "Wood")} Debris").particles.burst(16, block.center);
  playSound("hit", volume: 0.45, pitch: m == "ice" ? 1.8 : (m == "stone" ? 0.6 : 1.0));
}

void impDefeated(imp) {
  _imps--;
  addScore(impPoints);
  find("Puff").particles.burst(28, imp.center);
  playSound("coin", volume: 0.7, pitch: 0.8);
}

void updateHud() {
  setText("ScoreText", "Score $score");
  var icons = find("ShotsHud").get("UI Image");
  icons.count = _total;
  icons.filled = _total - _fired;
}

void win() {
  if (_over) return;
  _over = true;
  state = "won";
  var bonus = _waiting.length * unusedShotBonus;
  score += bonus;
  for (var w in _waiting) {
    find("Puff").particles.burst(12, w.center);
    destroy(w);
  }
  var stars = score >= threeStars ? 3 : (score >= twoStars ? 2 : 1);
  var best = max(score, loadValue(bestKey(), 0));
  saveValue(bestKey(), best);
  saveValue(starsKey(), max(stars, loadValue(starsKey(), 0)));
  saveValue("siege_unlocked", max(loadValue("siege_unlocked", 1), levelNumber() + 1));
  updateHud();
  playSound("coin", volume: 0.9, pitch: 1.3);
  showResults(true, "SIEGE BROKEN!", stars, bonus > 0 ? "Score $score   (+$bonus for unused shots)" : "Score $score");
}

void lose() {
  if (_over) return;
  _over = true;
  state = "lost";
  playSound("hit", volume: 0.8, pitch: 0.5);
  showResults(true, "OUT OF SHOTS", 0, _imps == 1 ? "1 frost imp survived" : "$_imps frost imps survived");
}

void showResults(show, [heading, stars, line]) {
  for (var name in ["ResultsPanel", "ResultsTitle", "ResultsStars", "ResultsScore", "RetryButton", "MenuButton"]) {
    find(name).enabled = show;
  }
  find("NextButton").enabled = show && state == "won" && nextLevel != "";
  if (!show) return;
  setText("ResultsTitle", heading);
  setText("ResultsScore", line);
  find("ResultsStars").get("UI Image").filled = stars;
  find("NextButton").get("UI Button").action = "level:$nextLevel";
}
''';

const _slingshot = r'''
// Drag the loaded shot back and let go (mouse or touch).
// Keyboard: Left/Right aim, Up/Down power, Space fires.
var maxPull = 110;          // pixels
var power = 10.0;           // launch speed per pixel of pull
var grabRadius = 130;       // a drag must start this close to the pouch
var pouchHeight = 104;      // pouch above the slingshot's foot

var _shot = null;
var _dragging = false;
var _pull = vec(0, 0);
var _angle = 35.0;
var _strength = 0.85;
var _keyAim = false;

pouch() => vec(self.x, self.y - pouchHeight);
bool loaded() => _shot != null;

void load(shot) {
  _shot = shot;
  _pull = vec(0, 0);
  shot.position = pouch();
}

void onUpdate(dt) {
  if (_shot == null || !_shot.alive) {
    _shot = null;
    bands(pouch());
    find("Trajectory").line.clear();
    return;
  }
  // Mouse / touch drag
  if (Input.click && Input.mouse.distanceTo(pouch()) < grabRadius) {
    _dragging = true;
    _keyAim = false;
  }
  if (_dragging) {
    var p = Input.mouse - pouch();
    if (p.length > maxPull) p = p.normalized() * maxPull;
    _pull = p;
    if (Input.mouseReleased || !Input.mouseDown) {
      _dragging = false;
      if (_pull.length > 18) {
        fire(_pull * -power);
        return;
      }
      _pull = vec(0, 0);
    }
  } else {
    // Keyboard aim
    if (Input.key("Left")) { _angle = min(80, _angle + 40 * dt); _keyAim = true; }
    if (Input.key("Right")) { _angle = max(-10, _angle - 40 * dt); _keyAim = true; }
    if (Input.key("Up")) { _strength = min(1, _strength + 0.6 * dt); _keyAim = true; }
    if (Input.key("Down")) { _strength = max(0.2, _strength - 0.6 * dt); _keyAim = true; }
    if (_keyAim) _pull = vec(-cos(radians(_angle)), sin(radians(_angle))) * (maxPull * _strength);
    if (Input.pressed("Space") || Input.pressed("Enter")) {
      fireAt(_angle, _strength);
      return;
    }
  }
  _shot.position = pouch() + _pull;
  bands(_shot.position);
  if (_pull.length > 18) trajectory(_shot.position, _pull * -power); else find("Trajectory").line.clear();
}

/// Fires at [angle] degrees above the horizon with [strength] 0..1 (keyboard, tests, demos).
void fireAt(angle, strength) {
  if (_shot == null) return;
  var dir = vec(cos(radians(angle)), -sin(radians(angle)));
  _shot.position = pouch() - dir * (maxPull * clamp(strength, 0, 1));
  fire(dir * (maxPull * clamp(strength, 0, 1) * power));
}

void fire(velocity) {
  var shot = _shot;
  _shot = null;
  _dragging = false;
  _keyAim = false;
  _pull = vec(0, 0);
  shot.call("launch", velocity);
  find("Siege").call("shotFired");
  find("Trajectory").line.clear();
  bands(pouch());
  playSound("jump", volume: 0.6, pitch: 0.7);
}

void bands(at) {
  find("BandBack").line.points = [vec(self.x - 15, self.y - pouchHeight), at];
  find("BandFront").line.points = [vec(self.x + 15, self.y - pouchHeight), at];
}

/// Dotted preview of the flight (same gravity as the physics world).
void trajectory(from, velocity) {
  var g = Physics.gravity.y;
  var points = [];
  for (var i = 1; i <= 14; i++) {
    var t = i * 0.07;
    points.add(from + velocity * t + vec(0, 0.5 * g * t * t));
  }
  find("Trajectory").line.points = points;
}
''';

const _shot = r'''
// A shot: waits on the slingshot, then flies under real physics.
// Tap (or Space) in flight for its power: a spark splits in three,
// coal slams straight down. Embers are plain but heavy.
var kind = "ember";
var isFragment = false;     // split-off sparks don't count as a shot
var trailRate = 30;         // trail particles per second while flying

var _flying = false;
var _time = 0.0;
var _still = 0.0;
var _done = false;
var _usedPower = false;

void onStart() {
  self.particles.spawnRate = 0;    // smoulders quietly until launched
}

void launch(velocity) {
  _flying = true;
  self.rigidbody.enabled = true;
  self.rigidbody.velocity = velocity;
  self.particles.spawnRate = trailRate;
}

void onUpdate(dt) {
  self.sprite.frame = floor(Game.time * 10) % 2;
  if (!_flying || _done) return;
  _time += dt;
  if (!_usedPower && !isFragment && _time > 0.08 && (Input.click || Input.pressed("Space"))) usePower();
  if (self.rigidbody.speed < 30) _still += dt; else _still = 0;
  if (_still > 0.7 || _time > 8 || self.y > 900 || self.x > 2300 || self.x < -400) finish();
}

void usePower() {
  _usedPower = true;
  var v = self.rigidbody.velocity;
  if (kind == "spark") {
    for (var a in [-0.25, 0.25]) {
      var side = v.normalized().rotated(a * 6) * 18;
      var s = spawn("Spark Template", self.position + side);
      s.name = "Spark";
      s.script.isFragment = true;
      s.call("launch", v.rotated(a));
    }
    playSound("laser", volume: 0.5, pitch: 1.6);
  } else if (kind == "coal") {
    self.rigidbody.velocity = vec(v.x * 0.25, 1300);
    playSound("jump", volume: 0.6, pitch: 0.45);
  }
}

void onHit(other, impulse, speed) {
  if (impulse > 400) playSound("hit", volume: min(0.6, impulse / 4000), pitch: 1.3);
}

void finish() {
  _done = true;
  self.particles.spawnRate = 0;
  if (!isFragment) find("Siege").call("shotFinished");
  tween(0.6, (t) { self.sprite.opacity = 1 - t; }, then: () => destroy());
}
''';

const _block = r'''
// A breakable block: hard hits wear it down (cracks show), then it shatters.
var material = "wood";      // wood, ice or stone (debris colour and sound)
var health = 380;
var points = 100;           // score when destroyed
var resistance = 60;        // hits weaker than this do nothing

var _maxHealth = 1.0;
var _broken = false;

void onStart() {
  _maxHealth = health;
}

void onHit(other, impulse, speed) {
  if (impulse > resistance) damage(impulse - resistance);
}

void damage(amount) {
  if (_broken) return;
  health -= amount;
  if (health <= 0) {
    _broken = true;
    find("Siege").call("blockBroken", self);
    destroy();
    return;
  }
  var left = health / _maxHealth;
  self.sprite.frame = left < 0.35 ? 2 : (left < 0.7 ? 1 : 0);
}

void onUpdate(dt) {
  if (self.y > 1000) destroy();   // fell off the world
}
''';

const _imp = r'''
// A frost imp: hard hits hurt it; defeat them all to win.
var health = 220;
var resistance = 40;

var _hurt = 0.0;
var _blink = 0.0;
var _nextBlink = 2.0;
var _defeated = false;

void onUpdate(dt) {
  if (_defeated) return;
  _hurt -= dt;
  _blink -= dt;
  _nextBlink -= dt;
  if (_nextBlink <= 0) {
    _blink = 0.12;
    _nextBlink = randomRange(1.5, 4.5);
  }
  self.sprite.frame = _hurt > 0 ? 2 : (_blink > 0 ? 1 : 0);
  if (self.y > 900) defeat();     // knocked off the world
}

void onHit(other, impulse, speed) {
  if (impulse > resistance) damage(impulse - resistance);
}

void damage(amount) {
  if (_defeated) return;
  health -= amount;
  _hurt = 0.4;
  if (health <= 0) defeat();
}

void defeat() {
  if (_defeated) return;
  _defeated = true;
  find("Siege").call("impDefeated", self);
  destroy();
}
''';

const _keg = r'''
// Powder keg: blows up when hit hard, flinging and damaging everything nearby.
var radius = 150;
var strength = 1300;        // push at the centre (kg·px/s)
var blastDamage = 520;      // damage at the centre, less further away
var trigger = 120;          // hit strength that sets it off

var _blown = false;

void onHit(other, impulse, speed) {
  if (impulse > trigger) explode();
}

void damage(amount) {
  if (amount > 30) after(0.08, () => explode());   // chain reactions
}

void explode() {
  if (_blown) return;
  _blown = true;
  var at = self.center;
  for (var e in Physics.explode(at, radius, strength)) {
    if (e != self && e.alive && e.hasTag("breakable")) {
      var f = 1 - e.distanceTo(at) / radius;
      if (f > 0) e.call("damage", blastDamage * f);
    }
  }
  find("Blast").particles.burst(40, at);
  find("Siege").call("shake", 14);
  find("Siege").call("addScore", 500);
  playSound("explosion", volume: 0.9);
  destroy();
}
''';

const _title = r'''
// Title screen: level buttons with saved stars; later levels unlock as you win.
var levels = 3;

void onStart() {
  var unlocked = loadValue("siege_unlocked", 1);
  for (var i = 1; i <= levels; i++) {
    var button = find("Level$i Button").get("UI Button");
    var stars = find("Level$i Stars").get("UI Image");
    if (i <= unlocked) {
      button.text = "$i";
      button.action = "level:Level $i";
      stars.filled = loadValue("siege_stars_Level $i", 0);
    } else {
      button.text = "Locked";
      button.action = "";
      button.color = "#475569";
      stars.filled = 0;
    }
  }
  playMusic("assets/templates/siege/siege.wav", 0.4);
}

void onUIAction(action) {
  if (action != "reset") return;
  for (var i = 1; i <= levels; i++) {
    deleteValue("siege_stars_Level $i");
    deleteValue("siege_best_Level $i");
  }
  deleteValue("siege_unlocked");
  restart();
}
''';

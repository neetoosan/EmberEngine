/// Ember Quest's gameplay as Ember Script. New projects get these as
/// editable `.ember` files (Script workspace).
library;

const questScripts = <String, String>{
  'quest_hero.ember': _hero,
  'quest_enemy.ember': _enemy,
  'quest_coin_pop.ember': _coinPop,
  'quest_berry.ember': _berry,
  'quest_debris.ember': _debris,
};

const _hero = r'''
// The player: run, jump, stomp, grow, get hurt, die, reach the flag.
// Lives, score, coins and size live in Game.data, so they carry across levels.
var walkSpeed = 190;
var runSpeed = 290;
var stompBounce = 380;
var stompBounceHeld = 560;
var pitY = 448;                 // falling below this loses a life
var firstLevel = "Level 1";
var music = "assets/templates/quest/theme.wav";
var art = "assets/templates/quest";

// Tile ids (cells of tiles.png)
final usedBlock = 5;
final powerBlock = 12;

var state = "playing";          // "playing", "dead" or "cleared"
var big = false;
var invulnerable = 0.0;
var _stateTime = 0.0;
var _bannerTime = 0.0;
var _time = 0.0;
var _deadVelocity = 0.0;
var _gameOver = false;
var _won = false;
var _leaving = false;
var _nextLevel;

// --- Progress shared by all levels ---

session() {
  var d = Game.data;
  if (!d.containsKey("lives")) resetSession();
  return d;
}

void resetSession() {
  Game.data["lives"] = 3;
  Game.data["score"] = 0;
  Game.data["coins"] = 0;
  Game.data["big"] = false;
}

void addScore(points) {
  session()["score"] += points;
}

void addCoin() {
  var s = session();
  s["coins"] += 1;
  s["score"] += 200;
  if (s["coins"] >= 100) {
    s["coins"] -= 100;
    s["lives"] += 1;
  }
}

worldLabel() => "1-" + Game.level.split(" ").last;

bool jumpHeld() => Input.action("jump") || Input.action("up");
bool jumpPressed() => Input.actionPressed("jump") || Input.actionPressed("up");

// --- Events ---

void onStart() {
  setBig(session()["big"], false);
  playMusic(music, 0.45);
  banner("WORLD " + worldLabel(), 1.6);
  updateHud();
}

void onUpdate(dt) {
  _time += dt;
  _stateTime += dt;
  if (_bannerTime > 0) {
    _bannerTime -= dt;
    if (_bannerTime <= 0 && state == "playing") banner("");
  }

  if (state == "playing") {
    play(dt);
  } else if (state == "dead") {
    // Classic death hop: no collisions, just up and off the screen
    _deadVelocity += 1500 * dt;
    self.y += _deadVelocity * dt;
    if (_stateTime > 2.4 && !_gameOver) afterDeath();
    if (_gameOver && _stateTime > 3.0) restartGame();
  } else {
    self.controller.move(0, false, false);
    self.animator.play("idle");
    if (!_won && !_leaving && _stateTime > 2.5) {
      if (_nextLevel != null && Game.levels.contains(_nextLevel)) {
        _leaving = true;
        loadLevel(_nextLevel);
      } else {
        _won = true;
        _stateTime = 0;
        banner("YOU WIN!\n\nScore ${session()["score"]}\nThanks for playing");
      }
    }
    if (_won && _stateTime > 5) restartGame();
  }
  updateHud();
}

void play(dt) {
  var c = self.controller;
  c.moveSpeed = Input.action("sprint") ? runSpeed : walkSpeed;
  var wasGrounded = c.grounded;
  c.move(Input.axis("horizontal"), jumpHeld(), jumpPressed());
  if (wasGrounded && !c.grounded && c.velocity.y < -100) playSound("jump", volume: 0.5, pitch: big ? 0.9 : 1.15);

  self.sprite.flipX = c.facing == "left";
  if (invulnerable > 0) {
    invulnerable -= dt;
    self.sprite.opacity = (_time * 20).floor().isOdd ? 0.25 : 1.0;
  } else {
    self.sprite.opacity = 1.0;
  }
  if (!c.grounded) {
    self.animator.play("jump");
  } else if (c.velocity.x.abs() > 20) {
    self.animator.play("run");
  } else {
    self.animator.play("idle");
  }

  if (self.y > pitY) die();   // fell into a pit
}

// --- Blocks, hazards, pickups, enemies ---

void onHeadBump(tile) {
  if (state != "playing") return;
  if (tile.kind == "question") {
    tile.set(usedBlock);
    if (tile.id == powerBlock) {
      playSound("jump", volume: 0.6, pitch: 0.7);
      spawn("Berry Template", vec(tile.x, tile.top - 1));
    } else {
      spawn("Coin Pop Template", vec(tile.x, tile.top));
      addCoin();
      playSound("coin", volume: 0.7);
    }
  } else if (tile.kind == "breakable") {
    if (big) {
      tile.set(0);
      addScore(50);
      spawn("Debris Template", vec(tile.x, tile.y));
      playSound("explosion", volume: 0.45, pitch: 1.5);
    } else {
      playSound("click", volume: 0.6, pitch: 0.6);
    }
  } else {
    playSound("click", volume: 0.4, pitch: 0.5);
  }
}

void onTileTouch(tile) {
  if (tile.kind == "hazard") hurt();
}

void onTriggerEnter(other) {
  if (state != "playing") return;
  if (other.hasTag("enemy")) {
    touchEnemy(other);
  } else if (other.hasTag("coin")) {
    destroy(other);
    addCoin();
    playSound("coin", volume: 0.6);
  } else if (other.hasTag("powerup")) {
    destroy(other);
    addScore(1000);
    setBig(true, true);
  } else if (other.hasTag("goal")) {
    reachGoal(other);
  }
}

void touchEnemy(enemy) {
  if (enemy.script != null && enemy.script.squashed) return;
  var c = self.controller;
  var enemyTop = enemy.y - enemy.height + 12;
  // Landing on top of it (falling, feet near its head) squashes it
  if (c.velocity.y > 0 && self.y <= enemyTop + 14) {
    enemy.call("squash");
    c.bounce(jumpHeld() ? stompBounceHeld : stompBounce);
    addScore(100);
  } else {
    hurt();
  }
}

void hurt() {
  if (state != "playing" || invulnerable > 0) return;
  if (big) {
    setBig(false, false);
    invulnerable = 2.0;
    playSound("hit", volume: 0.8, pitch: 0.8);
  } else {
    die();
  }
}

void die() {
  if (state != "playing") return;
  state = "dead";
  _stateTime = 0;
  _deadVelocity = -520;
  session()["big"] = false;
  stopMusic();
  playSound("hit", volume: 1.0, pitch: 0.6);
  self.hitbox.enabled = false;
  self.animator.play("dead");
  self.sprite.opacity = 1.0;
}

void afterDeath() {
  session()["lives"] -= 1;
  if (session()["lives"] > 0) {
    restart();
  } else {
    _gameOver = true;
    _stateTime = 0;
    banner("GAME OVER");
  }
}

void restartGame() {
  if (_leaving) return;
  _leaving = true;
  resetSession();
  if (Game.levels.contains(firstLevel)) {
    loadLevel(firstLevel);
  } else {
    restart();
  }
}

void reachGoal(goal) {
  state = "cleared";
  _stateTime = 0;
  addScore(1000);
  _nextLevel = null;
  for (var tag in goal.tags) {
    if (tag.startsWith("next:")) _nextLevel = tag.substring(5);
  }
  stopMusic();
  playSound("coin", volume: 0.9, pitch: 0.8);
  banner("LEVEL CLEAR!");
}

// --- Size ---

void setBig(value, announce) {
  big = value;
  session()["big"] = value;
  self.height = value ? 48 : 32;
  self.sprite.asset = art + (value ? "/hero_big.png" : "/hero.png");
  self.hitbox.size = vec(22, value ? 42 : 28);
  self.hitbox.offset = vec(5, value ? 6 : 4);
  if (announce && value) playSound("coin", volume: 0.8, pitch: 1.5);
}

// --- HUD ---

void banner(text, [seconds = 0]) {
  setText("Banner", text);
  _bannerTime = seconds;
}

void updateHud() {
  var s = session();
  var score = "${s["score"]}".padLeft(6, "0");
  var coins = "${s["coins"]}".padLeft(2, "0");
  setText("Hud", "SCORE $score     COINS x$coins     WORLD ${worldLabel()}     LIVES x${s["lives"]}");
}
''';

const _enemy = r'''
// Walks back and forth; turns at walls, ledges and spikes. The hero squashes it
// by landing on top (calls squash()).
var direction = -1;
var turnAtLedges = true;
var squashed = false;
var _squashTime = 0.0;

void onUpdate(dt) {
  if (squashed) {
    _squashTime += dt;
    if (_squashTime > 0.5) destroy();
    return;
  }
  var c = self.controller;
  c.move(direction);
  if (c.hitWall) {
    direction = -direction;
  } else if (turnAtLedges && c.grounded) {
    var left = self.x - self.width / 2;
    var frontX = direction > 0 ? left + self.width + 2 : left - 2;
    // Turn back at ledges and in front of spikes/lava
    if (!c.groundAt(frontX, self.y + 4) || c.hazardAt(frontX, self.y - 8)) direction = -direction;
  }
  self.sprite.flipX = direction > 0;
  self.animator.play("walk");

  if (self.y > 5000) destroy();   // fell into a pit
}

void squash() {
  if (squashed) return;
  squashed = true;
  self.hitbox.enabled = false;
  self.animator.play("squashed");
  playSound("hit", volume: 0.7, pitch: 1.3);
}
''';

const _coinPop = r'''
// A coin that pops out of a "?" block, rises and vanishes.
var _time = 0.0;

void onUpdate(dt) {
  _time += dt;
  self.y -= 180 * dt * clamp(1 - _time * 2, 0, 1);
  if (_time > 0.45) destroy();
}
''';

const _berry = r'''
// Power-up that slides along the ground; touching it makes the hero big.
var direction = 1;

void onUpdate(dt) {
  var c = self.controller;
  c.move(direction);
  if (c.hitWall) direction = -direction;
  if (self.y > 600) destroy();
}
''';

const _debris = r'''
// Brick fragments: one burst, then the helper entity removes itself.
void onStart() {
  self.particles.burst(14);
  self.destroy(1.2);
}
''';

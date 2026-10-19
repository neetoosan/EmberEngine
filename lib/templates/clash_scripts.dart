/// Ember Script source for the "Ember Clash" template (editable in the Script
/// workspace once a project is created from it).
const Map<String, String> clashScripts = {
  'clash_match.ember': _match,
  'clash_fighter.ember': _fighter,
  'clash_orb.ember': _orb,
  'clash_title.ember': _title,
};

const _match = r'''
// Ember Clash: best of three rounds. Runs the rounds, the timer, hitstop
// (both fighters freeze for a moment on a hit) and the HUD.
var roundTime = 60.0;
var art = "assets/templates/clash/";

var roundNo = 0;
var wins = [0, 0];
var timer = 60.0;
var state = "intro";      // intro, fight, ko, over
var freeze = 0;           // hitstop frames left
var _wait = 0.0;
var cpu = true;
var level = "normal";

void onStart() {
  cpu = Game.data["clashCpu"] ?? true;
  level = Game.data["clashLevel"] ?? "normal";
  find("Ryn").script.cpu = cpu;
  find("Ryn").script.level = level;
  setText("P2Name", cpu ? "RYN  (CPU)" : "RYN  (PLAYER 2)");
  playMusic(art + "clash.wav", 0.4);
  nextRound();
}

void nextRound() {
  roundNo++;
  timer = roundTime;
  state = "intro";
  _wait = 2.0;
  find("Kai").call("reset", 330, 1);
  find("Ryn").call("reset", 630, -1);
  banner("ROUND $roundNo", "");
  playSound(art + "gong.wav", 0.6);
  hud();
}

void onFixedUpdate(dt) {
  if (freeze > 0) freeze--;
}

void onUpdate(dt) {
  if (Input.pressed("P") || Input.player(1).pressed("start") || Input.player(2).pressed("start")) togglePause();
  if (Game.paused) return;
  if (state == "intro") {
    _wait -= dt;
    if (_wait <= 0.6 && find("Banner").text.text != "FIGHT!") banner("FIGHT!", "");
    if (_wait <= 0) {
      state = "fight";
      banner("", "");
    }
  } else if (state == "fight") {
    timer -= dt;
    if (timer <= 0) {
      timer = 0;
      var a = find("Kai").health.health;
      var b = find("Ryn").health.health;
      roundOver(a >= b ? 0 : 1, "TIME");
    }
  } else if (state == "ko") {
    _wait -= dt;
    if (_wait <= 0) {
      Game.timeScale = 1;
      if (wins[0] >= 2 || wins[1] >= 2) matchOver();
      else nextRound();
    }
  }
  hud();
}

// Called by a fighter whose health runs out.
void knockedOut(loser) {
  if (state != "fight") return;
  roundOver(loser == 1 ? 1 : 0, "K.O.");
}

void roundOver(winner, how) {
  state = "ko";
  wins[winner]++;
  _wait = 3.0;
  banner(how, (winner == 0 ? "KAI" : "RYN") + " WINS THE ROUND");
  playSound(art + "ko.wav", 0.8);
  find("Camera").camera.shake(10, 0.6);
  Game.timeScale = 0.35;
  after(1.0, () { Game.timeScale = 1; });
  find(winner == 0 ? "Kai" : "Ryn").call("victory");
}

void matchOver() {
  state = "over";
  var winner = wins[0] >= 2 ? "KAI" : "RYN";
  if (cpu && wins[0] >= 2) {
    var best = loadValue("clash_wins_" + level, 0);
    saveValue("clash_wins_" + level, best + 1);
  }
  for (var n in ["ResultsPanel", "ResultsTitle", "ResultsLine", "RetryButton", "MenuButton"]) find(n).enabled = true;
  setText("ResultsTitle", winner + " WINS");
  setText("ResultsLine", "Rounds ${wins[0]} - ${wins[1]}");
  banner("", "");
}

// Hitstop: both fighters stop for [frames] fixed frames.
void hitstop(frames) {
  freeze = max(freeze, frames);
}

void hud() {
  var kai = find("Kai").health;
  var ryn = find("Ryn").health;
  find("P1Bar").bar.value = kai.health;
  find("P2Bar").bar.value = ryn.health;
  setText("TimerText", "${max(0, round(timer))}");
  setText("P1Wins", wins[0] == 0 ? "" : (wins[0] == 1 ? "●" : "● ●"));
  setText("P2Wins", wins[1] == 0 ? "" : (wins[1] == 1 ? "●" : "● ●"));
}

void banner(title, subtitle) {
  setText("Banner", title);
  setText("Subtitle", subtitle);
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
    Game.timeScale = 1;
    restart();
  }
  if (action == "menu") {
    Game.timeScale = 1;
    loadLevel("Title");
  }
}
''';

const _fighter = r'''
// A fighter. Moves are frame data at 60 steps a second: startup frames, then
// active frames when the hitbox can hit, then recovery. Hold back (or block)
// to guard: crouch to stop low kicks, stand for jumping attacks.
//   attack: jab · special: kick · down + either: low kick · in the air: air kick
//   down, down-forward, forward + attack: ember orb · forward, down, down-forward + attack: rising strike
var player = 1;
var cpu = false;
var level = "normal";
var orbName = "Kai Orb";  // the orb template this fighter throws (tagged with its name)
var art = "assets/templates/clash/";

var moves = {
  "jab": {"startup": 4, "active": 3, "recovery": 9, "damage": 5, "hitstun": 14, "blockstun": 9, "box": [24, -128, 82, 28], "push": 170, "level": "high", "frame": 5, "sound": "punch"},
  "kick": {"startup": 8, "active": 4, "recovery": 16, "damage": 9, "hitstun": 20, "blockstun": 13, "box": [26, -100, 104, 32], "push": 260, "level": "mid", "frame": 6, "sound": "kick"},
  "low": {"startup": 6, "active": 3, "recovery": 13, "damage": 6, "hitstun": 16, "blockstun": 10, "box": [22, -36, 104, 32], "push": 180, "level": "low", "frame": 7, "sound": "kick"},
  "air": {"startup": 5, "active": 10, "recovery": 3, "damage": 7, "hitstun": 18, "blockstun": 11, "box": [8, -84, 80, 46], "push": 160, "level": "overhead", "frame": 8, "sound": "kick"},
  "orb": {"startup": 12, "active": 1, "recovery": 26, "damage": 8, "hitstun": 20, "blockstun": 12, "frame": 9, "sound": "fireball", "level": "mid"},
  "rise": {"startup": 3, "active": 12, "recovery": 24, "damage": 12, "hitstun": 34, "blockstun": 14, "box": [0, -190, 66, 150], "push": 120, "level": "mid", "frame": 10, "sound": "kick", "safe": 8},
};

var x = 330.0;
var y = 440.0;
var vx = 0.0;
var vy = 0.0;
var facing = 1;
var state = "idle";       // idle, walk, crouch, jump, attack, block, hit, ko, win
var move = "";
var frame = 0;            // frames into the current move or stun
var stun = 0;
var hitDone = false;
var combo = 0;
var _comboShow = 0.0;
var _t = 0;
var _ai = {"left": false, "right": false, "down": false, "up": false, "attack": false, "special": false, "block": false};
var _aiTimer = 0;

void reset(px, face) {
  x = px;
  y = 440;
  vx = 0;
  vy = 0;
  facing = face;
  state = "idle";
  move = "";
  stun = 0;
  self.health.health = self.health.maxHealth;
  self.position = vec(x, y + 10);
}

Object other() => find(player == 1 ? "Ryn" : "Kai");

// --- Input: a player, or the CPU -------------------------------------------------

bool held(a) => cpu ? _ai[a] : Input.player(player).key(a);
bool tapped(a) => cpu ? _ai[a] : Input.player(player).buffered(a, 4);
bool forward() => facing > 0 ? held("right") : held("left");
bool back() => facing > 0 ? held("left") : held("right");

void think() {
  _aiTimer--;
  for (var k in _ai.keys) {
    if (k == "attack" || k == "special") _ai[k] = false;
  }
  if (_aiTimer > 0) return;
  var skill = {"easy": 0.35, "normal": 0.6, "hard": 0.85}[level];
  _aiTimer = {"easy": 16, "normal": 11, "hard": 7}[level];
  var o = other();
  var dist = abs(o.script.x - x);
  var oState = o.script.state;
  var toward = o.script.x > x ? "right" : "left";
  var away = toward == "right" ? "left" : "right";
  for (var k in ["left", "right", "down", "up", "block"]) _ai[k] = false;
  if (oState == "jump" && dist < 170 && chance(skill * 0.6)) {
    // anti-air: the rising strike (623)
    _ai["attack"] = true;
    _ai["_rise"] = true;
  } else if ((oState == "attack" || o.call("orbOut")) && dist < 260 && chance(skill)) {
    _ai[away] = true;
    if (o.script.move == "low") _ai["down"] = true;
  } else if (dist > 320) {
    if (chance(0.3 * skill) && !orbOut()) _ai["_orb"] = true;
    else _ai[toward] = true;
  } else if (dist > 150) {
    _ai[toward] = true;
    if (chance(0.12)) _ai["up"] = true;
  } else {
    var r = random();
    if (r < 0.35) _ai["attack"] = true;
    else if (r < 0.6) _ai["special"] = true;
    else if (r < 0.8) {
      _ai["down"] = true;
      _ai["attack"] = true;
    } else _ai[away] = true;
  }
}

// --- Every fixed step (60 a second) ------------------------------------------------

void onFixedUpdate(dt) {
  var match = find("Match");
  var fighting = match.script.state == "fight";
  if (match.script.freeze > 0) return;
  _t++;
  if (cpu && fighting && state != "ko") think();
  var o = other();
  var onGround = y >= 440;

  if (state == "ko" || state == "win") {
    vx = vx * 0.9;
  } else if (state == "hit" || state == "block") {
    stun--;
    vx = vx * 0.85;
    if (stun <= 0) state = onGround ? "idle" : "jump";
  } else if (state == "attack") {
    stepMove(o);
  } else if (fighting) {
    control(o, onGround);
  } else {
    vx = 0;
  }

  // Physics: gravity, the floor, the stage edges, and not overlapping
  if (!onGround || vy < 0) vy += 2600 * dt;
  x += vx * dt;
  y += vy * dt;
  if (y >= 440) {
    y = 440;
    vy = 0;
    if (state == "jump") state = "idle";
    if (state == "attack" && move == "air") endMove();
  }
  x = clamp(x, 60, 900);
  var gap = x - o.script.x;
  if (abs(gap) < 56 && abs(y - o.script.y) < 120) {
    var push = (56 - abs(gap)) / 2 * (gap < 0 ? -1 : 1);
    x += push;
  }
  self.position = vec(x, y + 10);   // the feet are a little above the picture's bottom edge
  look();
}

void control(o, onGround) {
  if (onGround && (state == "idle" || state == "walk" || state == "crouch")) facing = o.script.x > x ? 1 : -1;
  // Specials need the motion; cpu has shortcuts
  var orb = cpu ? _ai["_orb"] == true : Input.player(player).motion("236", "attack", facingRight: facing > 0);
  var rise = cpu ? _ai["_rise"] == true : Input.player(player).motion("623", "attack", facingRight: facing > 0);
  _ai["_orb"] = false;
  _ai["_rise"] = false;
  if (onGround && rise) return start("rise");
  if (onGround && orb && !orbOut()) return start("orb");
  if (!onGround) {
    if (tapped("attack") || tapped("special")) start("air");
    return;
  }
  var crouching = held("down");
  if (tapped("attack") || tapped("special")) {
    if (crouching) return start("low");
    return start(tapped("special") ? "kick" : "jab");
  }
  if (held("up") || tapped("jump")) {
    state = "jump";
    vy = -900;
    vx = (forward() ? 230 : (back() ? -190 : 0)) * facing;
    playSound(art + "swoosh.wav", 0.25);
    return;
  }
  if (crouching) {
    state = "crouch";
    vx = 0;
  } else if (forward()) {
    state = "walk";
    vx = 210 * facing;
  } else if (back()) {
    state = "walk";
    vx = -170 * facing;
  } else {
    state = "idle";
    vx = 0;
  }
}

void start(name) {
  state = "attack";
  move = name;
  frame = 0;
  hitDone = false;
  if (y >= 440) vx = 0;
  if (name == "rise") {
    vy = -720;
    vx = 120 * facing;
  }
  playSound(art + "swoosh.wav", 0.2);
}

void stepMove(o) {
  var m = moves[move];
  frame++;
  var a = m["startup"];
  var b = a + m["active"];
  if (move == "orb" && frame == a) {
    var orb = spawn(orbName, vec(x + facing * 70, y - 110));
    orb.script.dir = facing;
    orb.script.owner = player;
    playSound(art + "fireball.wav", 0.5);
  }
  if (m["box"] != null && frame > a && frame <= b && !hitDone) {
    var box = m["box"];
    var left = facing > 0 ? x + box[0] : x - box[0] - box[2];
    if (o.call("hurtbox", left, y + box[1], box[2], box[3])) {
      hitDone = true;
      o.call("takeHit", move, self);
    }
  }
  if (frame > b + m["recovery"]) endMove();
}

void endMove() {
  state = y >= 440 ? "idle" : "jump";
  move = "";
}

// Does the box (x, y, w, h) touch this fighter?
bool hurtbox(bx, by, bw, bh) {
  if (state == "ko") return false;
  if (state == "attack" && move == "rise" && frame <= moves["rise"]["safe"]) return false; // the rising strike can't be hit at first
  var crouch = state == "crouch" || (state == "attack" && move == "low") || (state == "block" && held("down"));
  var top = y - (crouch ? 100 : 150);
  return bx < x + 26 && bx + bw > x - 26 && by < y && by + bh > top;
}

bool orbOut() => findAll(orbName).length > 0;   // orbs are tagged with their template's name

void takeHit(name, attacker) {
  var m = moves[name];
  var crouch = held("down");
  var canGuard = (state == "idle" || state == "walk" || state == "crouch" || state == "block") && y >= 440;
  var guarding = canGuard && (back() || held("block"));
  var hits = m["level"];
  if (guarding && hits == "low" && !crouch) guarding = false;
  if (guarding && hits == "overhead" && crouch) guarding = false;
  var dir = attacker.script.x < x ? 1 : -1;
  if (guarding) {
    state = "block";
    stun = m["blockstun"];
    vx = dir * m["push"] * 0.8;
    find("Match").call("hitstop", 3);
    playSound(art + "block.wav", 0.5);
    spark(0.6);
    if (name == "orb") self.health.damage(1, attacker);
    return;
  }
  var wasHurt = state == "hit";
  state = "hit";
  move = "";
  stun = m["hitstun"];
  vx = dir * (m["push"] ?? 200);
  if (name == "rise") vy = -700;
  attacker.script.combo = wasHurt ? attacker.script.combo + 1 : 1;
  if (attacker.script.combo >= 2) attacker.call("showCombo");
  find("Match").call("hitstop", name == "rise" ? 8 : 5);
  playSound(art + m["sound"] + ".wav", 0.6);
  find("Camera").camera.shake(name == "rise" ? 9 : 4, 0.2);
  spark(1.0);
  self.health.damage(m["damage"], attacker);
  if (self.health.health <= 0) {
    state = "ko";
    vx = dir * 380;
    vy = -520;
    find("Match").call("knockedOut", player);
  }
}

void spark(size) {
  var s = spawn("Spark", vec(x - facing * 10, y - 110));
  s.scale = size;
  tween(0.2, (k) {
    s.scale = size * (0.6 + k);
    s.sprite.opacity = 1 - k;
  }, then: () { destroy(s); });
  find("Hit FX").particles.burst(round(10 * size), vec(x, y - 110));
}

void showCombo() {
  setText(player == 1 ? "P1Combo" : "P2Combo", "$combo HITS");
  _comboShow = 1.2;
}

void victory() {
  if (state != "ko") state = "win";
}

void onUpdate(dt) {
  if (_comboShow > 0) {
    _comboShow -= dt;
    if (_comboShow <= 0) setText(player == 1 ? "P1Combo" : "P2Combo", "");
  }
}

void look() {
  var f = 0;
  if (state == "walk") f = floor(_t / 8) % 2 == 0 ? 1 : 2;
  if (state == "crouch") f = 3;
  if (state == "jump") f = 4;
  if (state == "attack") f = frame <= moves[move]["startup"] ? (move == "low" ? 3 : 0) : moves[move]["frame"];
  if (state == "attack" && move == "air") f = frame <= 2 ? 4 : 8;
  if (state == "block") f = 11;
  if (state == "hit") f = 12;
  if (state == "ko") f = y >= 440 ? 13 : 12;
  if (state == "win") f = 14;
  self.sprite.frame = f;
  self.sprite.flipX = facing < 0;
}
''';

const _orb = r'''
// An ember (or frost) orb thrown with down, down-forward, forward + attack.
var dir = 1;
var owner = 1;
var speed = 430.0;
var t = 0.0;

void onFixedUpdate(dt) {
  if (find("Match").script.freeze > 0) return;
  t += dt;
  self.x += dir * speed * dt;
  self.sprite.flipX = dir < 0;
  var target = find(owner == 1 ? "Ryn" : "Kai");
  if (target.call("hurtbox", self.x - 22, self.y - 22, 44, 44)) {
    target.call("takeHit", "orb", find(owner == 1 ? "Kai" : "Ryn"));
    destroy();
    return;
  }
  // Two orbs cancel out
  var rival = find(owner == 1 ? "Ryn Orb" : "Kai Orb");
  if (rival != null && rival.enabled && self.distanceTo(rival) < 40) {
    find("Hit FX").particles.burst(20, self.position);
    destroy(rival);
    destroy();
    return;
  }
  if (self.x < -60 || self.x > 1020 || t > 3) destroy();
}
''';

const _title = r'''
// Title screen: fight the CPU (three levels) or a second player.
void onStart() {
  Game.timeScale = 1;
  Game.paused = false;
  playMusic("assets/templates/clash/clash.wav", 0.35);
  var wins = loadValue("clash_wins_normal", 0) + loadValue("clash_wins_hard", 0) + loadValue("clash_wins_easy", 0);
  setText("WinsText", wins > 0 ? "Matches won against the CPU: $wins" : "");
}

void onUIAction(action) {
  if (action == "easy" || action == "normal" || action == "hard") {
    Game.data["clashCpu"] = true;
    Game.data["clashLevel"] = action;
    loadLevel("Arena");
  }
  if (action == "versus") {
    Game.data["clashCpu"] = false;
    loadLevel("Arena");
  }
}
''';

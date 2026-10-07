/// Flappy Arcade's gameplay as Ember Script. New projects get these as
/// editable `.ember` files (Script workspace).
library;

const flappyScripts = <String, String>{
  'flappy_game.ember': _game,
  'flappy_bird.ember': _bird,
  'flappy_pipe.ember': _pipe,
  'flappy_scroller.ember': _scroller,
  'flappy_cloud.ember': _cloud,
};

const _game = r'''
// Game flow: ready -> playing -> dead -> restart.
// Spawns pipe pairs (copies of the hidden "Pipe Template") and keeps score.
var pipeInterval = 1.45;   // seconds between pipe pairs
var lowestGap = 150;       // gap centre range (world y)
var highestGap = 330;

var state = "ready";       // "ready", "playing" or "dead"
var score = 0;
var _spawnTimer = 0.0;
var _deadTime = 0.0;

/// Space, W, Up, a mouse click or a touch.
bool flapPressed() => Input.actionPressed("jump") || Input.click || Input.pressed("W") || Input.pressed("Up");

void onStart() {
  setText("ScoreText", "");
  setText("MessageText", "GET READY\n\nClick, tap or press Space\nto flap");
}

void onUpdate(dt) {
  if (state == "ready") {
    if (flapPressed()) {
      state = "playing";
      _spawnTimer = 0.9;
      setText("MessageText", "");
      setText("ScoreText", "0");
      find("Bird").call("flap");
    }
  } else if (state == "playing") {
    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnTimer += pipeInterval;
      spawnPipes();
    }
  } else {
    _deadTime += dt;
    if (_deadTime > 0.8 && flapPressed()) restart();
  }
}

/// A pipe pair just past the right edge, gap at a random height.
spawnPipes([gapCenter]) {
  var pair = spawn("Pipe Template", vec(328, gapCenter ?? randomRange(lowestGap, highestGap)));
  pair.name = "PipePair";
  return pair;
}

void addPoint() {
  if (state != "playing") return;
  score++;
  setText("ScoreText", "$score");
  playSound("coin", volume: 0.6);
}

void gameOver() {
  if (state == "dead") return;
  state = "dead";
  _deadTime = 0;
  var best = max(score, loadValue("best", 0));
  saveValue("best", best);
  playSound("hit", volume: 0.9);
  setText("MessageText", "GAME OVER\n\nScore $score    Best $best\n\nClick or Space to retry");
}
''';

const _bird = r'''
// The bird: gravity, flapping, nose tilt, wing animation, crashing.
var gravity = 1500;
var flapVelocity = -430;
var maxFall = 620;
var groundY = 448;        // top of the ground

var velocity = 0.0;
var alive = true;
var _time = 0.0;
var _baseY = 0.0;
var _game;

void onStart() {
  _game = find("Game");
  _baseY = self.y;
}

void flap() {
  if (!alive) return;
  velocity = flapVelocity;
  playSound("jump", volume: 0.5, pitch: 1.4);
}

void onUpdate(dt) {
  _time += dt;
  if (alive) self.sprite.frame = (_time / 0.09).floor() % 3;   // wings

  var state = _game.script.state;
  if (state == "ready") {
    self.y = _baseY + sin(_time * 6) * 6;                        // hover
    self.rotation = 0;
    return;
  }
  if (state == "playing" && _game.call("flapPressed")) flap();

  velocity = min(velocity + gravity * dt, maxFall);
  var y = self.y + velocity * dt;
  if (y < -20) {
    y = -20;
    velocity = 0;
  }
  if (y + 12 >= groundY) {
    y = groundY - 12;
    velocity = 0;
    if (alive) die();
  }
  self.y = y;

  // Nose up while rising, dive as it falls
  var target = !alive ? 90 : (velocity < 0 ? -25 : min(90, velocity / maxFall * 110));
  var current = degrees(self.rotation);
  self.rotation = radians(current + (target - current) * min(1, dt * (velocity < 0 ? 20 : 6)));
}

void onTriggerEnter(other) {
  if (!alive) return;
  if (other.name == "ScoreGate") {
    _game.call("addPoint");
  } else if (other.hasTag("deadly")) {
    die();
  }
}

void die() {
  alive = false;
  velocity = max(velocity, 0);
  _game.call("gameOver");
}
''';

const _pipe = r'''
// Moves a pipe pair left while playing; removes it once off-screen.
var speed = 120;
var _game;

void onStart() {
  _game = find("Game");
}

void onUpdate(dt) {
  if (_game.script.state != "playing") return;
  self.x -= speed * dt;
  if (self.x < -60) destroy();
}
''';

const _scroller = r'''
// Scrolls a row of identical tiles (ground, hills) and wraps seamlessly.
// Each scrolling entity sets its own speedFactor and wrapWidth in the Inspector.
var speed = 120;
var speedFactor = 1.0;
var wrapWidth = 32;
var _game;

void onStart() {
  _game = find("Game");
}

void onUpdate(dt) {
  if (_game.script.state == "dead") return;
  var x = self.x - speed * speedFactor * dt;
  while (x <= -wrapWidth) x += wrapWidth;
  self.x = x;
}
''';

const _cloud = r'''
// Slow cloud drift that wraps around the screen.
var speed = 14;

void onUpdate(dt) {
  var x = self.x - speed * dt;
  if (x < -40) x = 328;
  self.x = x;
}
''';

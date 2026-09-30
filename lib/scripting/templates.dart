/// Starter Ember Scripts offered by "New Script".
library;

class ScriptTemplate {
  final String id, title, description, source;
  const ScriptTemplate(this.id, this.title, this.description, this.source);
}

const scriptTemplates = <ScriptTemplate>[
  ScriptTemplate('blank', 'Empty script', 'The main events, ready to fill in.', r'''
// Variables declared here are per entity and show up in the Inspector.
var speed = 100;

void onStart() {
  // Runs once when the game starts.
}

void onUpdate(dt) {
  // Runs every frame. dt = seconds since the last frame.
}
'''),
  ScriptTemplate('topdown', 'Top-down player', 'WASD / arrows move in 8 directions; Space swings a sword.', r'''
// Top-down hero. Needs: Transform 2D (+ a Hitbox 2D for walls).
// Tag the entity "player" so enemies can find it.
var speed = 140;
var damage = 1;

var _cooldown = 0.0;

void onUpdate(dt) {
  var move = Input.move;
  if (self.has("Top-Down Controller 2D")) {
    self.mover.move(move);            // slides along walls
  } else {
    self.position = self.position + move * speed * dt;
  }

  if (move.x != 0 && self.has("sprite")) self.sprite.flipX = move.x < 0;

  _cooldown -= dt;
  if (Input.actionPressed("attack") || Input.pressed("Space")) {
    if (_cooldown <= 0) attack(move);
  }
}

void attack(direction) {
  _cooldown = 0.35;
  if (direction.length == 0) direction = vec(1, 0);
  var hitAt = self.center + direction.normalized() * 24;
  var hits = strike(hitAt, 32, 32, damage: damage);
  playSound(hits.isEmpty ? "laser" : "hit", volume: 0.5);
}
'''),
  ScriptTemplate('platformer', 'Platformer player', 'Run and jump with a Platformer Controller 2D.', r'''
// Side-scrolling hero. Needs: Transform 2D + Platformer Controller 2D (+ Sprite Animator).
var runSpeed = 220;

void onUpdate(dt) {
  var c = self.controller;
  c.moveSpeed = Input.key("Shift") ? runSpeed * 1.5 : runSpeed;
  var jumpHeld = Input.action("jump") || Input.key("W") || Input.key("Up");
  var jumpPressed = Input.actionPressed("jump") || Input.pressed("W") || Input.pressed("Up");
  c.move(Input.axis("horizontal"), jumpHeld, jumpPressed);

  if (jumpPressed && c.canJump) playSound("jump", volume: 0.5);

  if (self.has("animator")) {
    if (!c.grounded) {
      self.animator.play("jump");
    } else if (c.velocity.x.abs() > 20) {
      self.animator.play("run");
    } else {
      self.animator.play("idle");
    }
  }

  // Fell off the level
  if (self.y > 2000) restart();
}
'''),
  ScriptTemplate('chaser', 'Enemy: chase the player', 'Walks toward the nearest "player" when it gets close; hurts on touch.', r'''
// Simple enemy. Tag your hero "player". Add a Health component to make it killable.
var speed = 60;
var sightRange = 200;
var touchDamage = 1;

void onUpdate(dt) {
  var target = findNearest("player");
  if (target == null) return;
  if (self.distanceTo(target) < sightRange) {
    var dir = self.directionTo(target);
    self.position = self.position + dir * speed * dt;
    if (self.has("sprite")) self.sprite.flipX = dir.x < 0;
  }
}

void onTriggerEnter(other) {
  if (other.hasTag("player") && other.has("Health")) {
    other.health.damage(touchDamage, self, self.directionTo(other) * 200);
  }
}

void onDeath(killer) {
  playSound("explosion", volume: 0.4);
  if (self.has("particles")) self.particles.burst(20);
}
'''),
  ScriptTemplate('collectible', 'Collectible (coin)', 'Disappears when the player touches it and adds to the score.', r'''
// Put on a coin with a Hitbox 2D. The player needs a Hitbox 2D and the tag "player".
var points = 10;

void onTriggerEnter(other) {
  if (!other.hasTag("player")) return;
  var score = loadValue("score", 0) + points;
  saveValue("score", score);
  var hud = find("Score");
  if (hud != null) setText(hud, "Score: $score");
  playSound("coin");
  destroy();
}
'''),
  ScriptTemplate('spawner', 'Spawner', 'Copies a template entity every few seconds.', r'''
// Make an entity called "Bullet" (or anything) and untick "enabled" so it's a template.
var templateName = "Bullet";
var interval = 2.0;
var maxAlive = 10;

var _spawned = [];

void onStart() {
  every(interval, () {
    _spawned = _spawned.where((e) => e.alive).toList();
    if (_spawned.length >= maxAlive) return;
    var copy = spawn(templateName, self.position + vec(randomRange(-40, 40), 0));
    _spawned.add(copy);
  });
}
'''),
  ScriptTemplate('ui', 'HUD / score display', 'Updates a UI Text every frame.', r'''
// Put on an entity with a UI Text component.
var prefix = "Time";

void onUpdate(dt) {
  self.text.text = "$prefix ${Game.time.toStringAsFixed(1)}";
}
'''),
];

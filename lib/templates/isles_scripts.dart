/// Ember Script source for the "Ember Isles" template (editable in the Script
/// workspace once a project is created from it).
const Map<String, String> islesScripts = {
  'isles_colony.ember': _colony,
  'isles_unit.ember': _unit,
  'isles_tower.ember': _tower,
  'isles_title.ember': _title,
};

const _colony = r'''
// Ember Isles: settle an island grown from a seed. Houses bring people, farms
// feed them, lumber camps (next to trees) and quarries (next to rocks) bring
// wood and stone. Raiders land every few minutes: train guards, drag a box to
// select them, right-click to send them, and build watchtowers. Light the
// Ember Beacon to win; lose the Town Hall and the colony is gone.
var size = 22;
var raidEvery = 80.0;
var firstRaid = 100.0;
var art = "assets/templates/isles/";
var costs = {
  "House": {"wood": 20, "stone": 0, "food": 0},
  "Farm": {"wood": 25, "stone": 0, "food": 0},
  "Lumber Camp": {"wood": 20, "stone": 0, "food": 0},
  "Quarry": {"wood": 30, "stone": 0, "food": 0},
  "Watchtower": {"wood": 40, "stone": 25, "food": 0},
  "Ember Beacon": {"wood": 150, "stone": 120, "food": 80},
};

var seed = 0;
var wood = 60.0;
var stone = 10.0;
var food = 50.0;
var people = 4;
var guards = 0;
var houses = 0;
var buildings = [];       // every standing building
var state = "play";       // play, won, lost
var placing = "";
var selected = [];
var raidTimer = 0.0;
var wave = 0;
var _tick = 0.0;
var _grow = 0.0;
var _banner = 0.0;
var _dragging = false;
var map = null;
var hall = null;          // the Town Hall on the island (find() would give its hidden template)

void onStart() {
  seed = Game.data["islesSeed"] ?? Random().integer(100000);
  map = find("Map").tilemap;
  grow();
  raidTimer = firstRaid;
  playMusic(art + "isles.wav", 0.4);
  banner("EMBER ISLES", "Build houses and farms. Raiders come from the sea.", 4);
  hud();
}

// --- The island ---------------------------------------------------------------

void grow() {
  var rng = Random(seed);
  var mid = (size - 1) / 2;
  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      var d = sqrt((c - mid) * (c - mid) + (r - mid) * (r - mid)) / mid;
      var h = smoothNoise(c * 0.17, r * 0.17, seed) - d * 0.85 + 0.32;
      if (d < 0.25) h = max(h, 0.3);
      var tile = h < 0.02 ? 2 : (h < 0.1 ? 1 : (h < 0.17 ? 3 : (rng.chance(0.12) ? 6 : (rng.chance(0.4) ? 5 : 4))));
      map.setTile(c, r, tile);
    }
  }
  hall = place("Town Hall", [floor(mid), floor(mid)]);
  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      var t = map.getTile(c, r);
      var near = abs(c - mid) < 2.5 && abs(r - mid) < 2.5;
      if (near || !map.walkable(c, r)) continue;
      if (t >= 4 && noise(c * 0.35, r * 0.35, seed + 7) > 0.62) {
        decorate(rng.chance(0.5) ? "Tree" : "Pine", [c, r]);
      } else if (noise(c * 0.5, r * 0.5, seed + 13) > 0.72) {
        decorate("Rock", [c, r]);
      }
    }
  }
}

Vec2 ground(cell) => map.cellCenter(cell[0], cell[1]) + vec(0, 16);

void decorate(kind, cell) {
  spawn(kind, ground(cell));
  map.block(cell[0], cell[1], true);
}

Object place(kind, cell) {
  var e = spawn(kind, ground(cell));
  e.script.cell = cell;
  map.block(cell[0], cell[1], true);
  buildings.add(e);
  if (kind == "House") houses++;
  return e;
}

// Things within [radius] cells (by tag)
int countNear(tag, cell, radius) => findInRange(tag, ground(cell), radius * 46).length;

// --- Every frame ---------------------------------------------------------------

void onUpdate(dt) {
  if (_banner > 0) {
    _banner -= dt;
    if (_banner <= 0) banner("", "", 0);
  }
  if (state != "play") return;
  panCamera(dt);
  economy(dt);
  raids(dt);
  if (placing != "") updateGhost();
  else selection();
  if (Input.pressed("Escape")) {
    choose("");
    selectUnits([]);
  }
  if (Input.pressed("G")) trainGuard();
}

void panCamera(dt) {
  var cam = find("Camera");
  var v = vec((Input.key("D") || Input.key("Right") ? 1 : 0) - (Input.key("A") || Input.key("Left") ? 1 : 0),
    (Input.key("S") || Input.key("Down") ? 1 : 0) - (Input.key("W") || Input.key("Up") ? 1 : 0));
  cam.position = cam.position + v * 420 * dt;
  cam.x = clamp(cam.x, 480, 1408 - 480);
  cam.y = clamp(cam.y, 270, 760 - 270);
}

void economy(dt) {
  _tick += dt;
  if (_tick < 1) return;
  _tick -= 1;
  var camps = 0;
  var quarries = 0;
  var farms = 0;
  for (var b in buildings) {
    if (b.name == "Lumber Camp") camps++;
    if (b.name == "Quarry") quarries++;
    if (b.name == "Farm") farms++;
  }
  wood += camps * 1.5;
  stone += quarries * 1.0;
  food += farms * 1.6 - (people + guards) * 0.1;
  if (food < 0) food = 0;
  _grow += 1;
  var cap = 5 + houses * 5;
  if (_grow >= 4 && people + guards < cap && food > 5) {
    _grow = 0;
    people++;
  }
  hud();
}

// --- Building ------------------------------------------------------------------

void choose(kind) {
  placing = placing == kind ? "" : kind;
  find("Ghost").enabled = placing != "";
  find("Cell").enabled = placing != "";
  if (placing != "") {
    find("Ghost").sprite.frame = frameOf(placing);
    selectUnits([]);
  }
  hud();
}

int frameOf(kind) => {"House": 4, "Farm": 5, "Lumber Camp": 6, "Quarry": 7, "Watchtower": 8, "Ember Beacon": 9}[kind];

String whyNot(kind, cell) {
  if (cell == null || !map.walkable(cell[0], cell[1])) return "Build on open land";
  var t = map.getTile(cell[0], cell[1]);
  if (kind == "Farm" && t == 3) return "Farms need grass";
  if (kind == "Lumber Camp" && countNear("tree", cell, 2) == 0) return "Lumber camps go next to trees";
  if (kind == "Quarry" && countNear("rock", cell, 2) == 0) return "Quarries go next to rocks";
  var c = costs[kind];
  if (wood < c["wood"] || stone < c["stone"] || food < c["food"]) return "Not enough resources";
  return "";
}

void updateGhost() {
  var cell = map.cellAt(Input.mouse);
  if (cell == null) return;
  var why = whyNot(placing, cell);
  find("Ghost").position = ground(cell);
  find("Ghost").sprite.tint = why == "" ? "#FFFFFF" : "#FF8A8A";
  find("Cell").position = map.cellCenter(cell[0], cell[1]);
  find("Cell").sprite.tint = why == "" ? "#BBF7D0" : "#FCA5A5";
  setText("Help", why == "" ? "Click to build the $placing  ·  Esc cancels" : why);
  if (Input.click && Input.mouse.y < find("Camera").y + 200) {
    if (why == "") build(placing, cell);
    else playSound(art + "select.wav", 0.3, pitch: 0.6);
  }
}

void build(kind, cell) {
  var c = costs[kind];
  wood -= c["wood"];
  stone -= c["stone"];
  food -= c["food"];
  var b = place(kind, cell);
  playSound(art + "build.wav", 0.6);
  find("Dust FX").particles.burst(16, ground(cell));
  b.scale = 0.6;
  tween(0.25, (k) { b.scale = 0.6 + k * 0.4; }, ease: "back");
  if (kind == "Ember Beacon") {
    victory();
    return;
  }
  if (!Input.key("Shift")) choose("");
  hud();
}

// Called when a building's health runs out.
void buildingLost(b) {
  buildings.remove(b);
  if (b.name == "House") houses--;
  map.block(b.script.cell[0], b.script.cell[1], false);
  find("Dust FX").particles.burst(30, b.position);
  find("Camera").camera.shake(6, 0.4);
  if (b.name == "Town Hall") defeat();
  hud();
}

// --- Units -----------------------------------------------------------------------

void trainGuard() {
  if (state != "play") return;
  if (food < 15 || wood < 10) {
    banner("", "A guard needs 15 food and 10 wood", 2);
    return;
  }
  if (people <= 1) {
    banner("", "Not enough people: build houses", 2);
    return;
  }
  food -= 15;
  wood -= 10;
  people--;
  guards++;
  var spot = freeCellNear(hall.script.cell);
  var g = spawn("Guard", ground(spot) + vec(randomRange(-6, 6), randomRange(-3, 3)));
  g.script.cell = spot;
  playSound(art + "select.wav", 0.4);
  hud();
}

// A walkable cell next to [cell] (for units arriving at a building)
Object freeCellNear(cell) {
  for (var radius = 1; radius < 4; radius++) {
    for (var dr = -radius; dr <= radius; dr++) {
      for (var dc = -radius; dc <= radius; dc++) {
        if (map.walkable(cell[0] + dc, cell[1] + dr)) return [cell[0] + dc, cell[1] + dr];
      }
    }
  }
  return cell;
}

void selection() {
  var box = find("Selection Box");
  if (Input.click) _dragging = true;
  if (_dragging && Input.mouseDown) {
    var a = Input.dragStart;
    var b = Input.mouse;
    box.enabled = a.distanceTo(b) > 8;
    box.line.points = [a, vec(b.x, a.y), b, vec(a.x, b.y), a];
  }
  if (_dragging && Input.mouseReleased) {
    _dragging = false;
    box.enabled = false;
    var a = Input.dragStart;
    var b = Input.mouse;
    if (a.distanceTo(b) > 8) {
      selectUnits(findInBox("guard", a, b));
    } else {
      var hit = pick(Input.mouse, "guard");
      selectUnits(hit == null ? [] : [hit]);
    }
  }
  if (Input.rightClick && selected.isNotEmpty) {
    var cell = map.cellAt(Input.mouse);
    if (cell != null) {
      for (var g in selected) g.call("moveTo", cell);
      if (selected[0].script.path.isEmpty) setText("Help", "They can't get there");
      var mark = spawn("Move Marker", map.cellCenter(cell[0], cell[1]));
      mark.destroy(0.5);
      playSound(art + "select.wav", 0.3, pitch: 1.4);
    }
  }
}

void selectUnits(list) {
  for (var g in selected) {
    if (g.alive) g.call("setSelected", false);
  }
  selected = list;
  for (var g in selected) g.call("setSelected", true);
  if (list.isNotEmpty) playSound(art + "select.wav", 0.3);
  hud();
}

// The nearest standing building to a point (raiders' target)
Object nearestBuilding(p) {
  var best = null;
  for (var b in buildings) {
    if (b.alive && (best == null || b.distanceTo(p) < best.distanceTo(p))) best = b;
  }
  return best;
}

void unitDown(unit) {
  if (unit.script.team == "guard") {
    guards--;
    selected.remove(unit);
  }
  hud();
}

// --- Raids ---------------------------------------------------------------------

void raids(dt) {
  raidTimer -= dt;
  if (raidTimer <= 0) {
    raidTimer = raidEvery;
    wave++;
    landRaiders(2 + wave * 2);
  }
}

void landRaiders(count) {
  // A beach: a land cell next to the sea, far from the Town Hall
  var rng = Random(seed + wave * 101);
  var beach = null;
  for (var tries = 0; tries < 400 && beach == null; tries++) {
    var c = rng.integer(size);
    var r = rng.integer(size);
    if (map.getTile(c, r) == 3 && map.walkable(c, r)) beach = [c, r];
  }
  if (beach == null) beach = [1, 1];
  var boat = spawn("Boat", ground(beach) + vec(-30, -10));
  boat.destroy(12);
  for (var i = 0; i < count; i++) {
    var raider = spawn("Raider", ground(beach) + vec(randomRange(-10, 10), randomRange(-5, 5)));
    raider.script.cell = beach;
    raider.health.maxHealth = 3 + wave;
    raider.health.health = raider.health.maxHealth;
  }
  playSound(art + "horn.wav", 0.6);
  banner("RAIDERS!", "$count raiders have landed. Send your guards.", 3);
  find("Camera").camera.flash("#7F1D1D", 0.4);
}

// --- Ending ----------------------------------------------------------------------

void victory() {
  state = "won";
  choose("");
  playSound(art + "win.wav", 0.7);
  var best = loadValue("isles_best", 0);
  if (wave > best) saveValue("isles_best", wave);
  showResults("THE BEACON BURNS", "Your colony thrives. Raids survived: $wave");
}

void defeat() {
  state = "lost";
  choose("");
  playSound(art + "lose.wav", 0.7);
  showResults("THE COLONY HAS FALLEN", "The Town Hall was burned in raid $wave");
}

void showResults(title, line) {
  for (var n in ["ResultsPanel", "ResultsTitle", "ResultsLine", "RetryButton", "MenuButton"]) find(n).enabled = true;
  setText("ResultsTitle", title);
  setText("ResultsLine", line + "   (island $seed)");
}

// --- HUD ---------------------------------------------------------------------------

void hud() {
  setText("WoodText", "${floor(wood)}");
  setText("StoneText", "${floor(stone)}");
  setText("FoodText", "${floor(food)}");
  setText("PeopleText", "$people / ${5 + houses * 5}");
  setText("GuardText", "$guards");
  var t = max(0, round(raidTimer));
  setText("RaidText", "Raid ${wave + 1} in ${t ~/ 60}:${t % 60 < 10 ? "0" : ""}${t % 60}");
  for (var k in costs.keys) {
    var b = find(k + " Button");
    if (b == null) continue;
    var c = costs[k];
    var ok = wood >= c["wood"] && stone >= c["stone"] && food >= c["food"];
    b.button.color = placing == k ? "#FBBF24" : (ok ? "#E7E5E4" : "#78716C");
  }
  if (placing == "") setText("Help", selected.isNotEmpty ? "${selected.length} selected: right-click to send them" : "Drag to select guards  ·  WASD moves the view  ·  G trains a guard");
}

void banner(title, subtitle, seconds) {
  setText("Banner", title);
  setText("Subtitle", subtitle);
  _banner = seconds;
}

void onUIAction(action) {
  if (action.startsWith("build:")) choose(action.substring(6));
  if (action == "guard") trainGuard();
  if (action == "retry") restart();
  if (action == "menu") loadLevel("Title");
}
''';

const _unit = r'''
// A guard (yours) or a raider. Units walk cell to cell along paths on the
// island's grid. Raiders head for the nearest building; guards go where you
// send them and fight raiders that come close.
var team = "guard";
var speed = 55.0;
var damage = 1.0;
var cooldown = 0.9;
var sight = 130.0;
var art = "assets/templates/isles/";

var cell = [0, 0];
var path = [];
var goal = null;
var target = null;
var _cool = 0.0;
var _repath = 0.0;
var _t = 0.0;
var selected = false;

void setSelected(on) {
  selected = on;
  self.child("Ring").enabled = on;
}

void moveTo(c) {
  goal = c;
  target = null;
  plan();
}

void plan() {
  var map = find("Map").tilemap;
  var here = map.cellAt(self.position + vec(0, -8)) ?? cell;
  var p = goal == null ? null : map.findPath(here[0], here[1], goal[0], goal[1]);
  path = p ?? [];
}

void onUpdate(dt) {
  var colony = find("Colony");
  if (colony.script.state != "play") return;
  _t += dt;
  _cool -= dt;
  _repath -= dt;
  var map = find("Map").tilemap;

  // Choose what to fight
  if (target != null && !target.alive) target = null;
  if (team == "raider" && target == null) {
    target = colony.call("nearestBuilding", self.position);
    if (target != null) {
      goal = colony.call("freeCellNear", target.script.cell);
      plan();
    }
  }
  if (team == "guard" && (goal == null || path.isEmpty)) {
    var foes = findInRange("raider", self.position, sight);
    if (foes.isNotEmpty) target = foes[0];
  }
  if (team == "raider") {
    var foes = findInRange("guard", self.position, 40);
    if (foes.isNotEmpty) target = foes[0];
  }

  // Close enough: fight
  var reach = target != null && target.hasTag("building") ? 46 : 26;
  if (target != null && self.distanceTo(target) < reach) {
    self.sprite.flipX = target.x < self.x;
    if (_cool <= 0) {
      _cool = cooldown;
      target.health.damage(damage, self);
      playSound(art + "clash.wav", 0.25, pitch: randomRange(0.9, 1.1));
      find("Spark FX").particles.burst(5, (self.position + target.position) * 0.5 + vec(0, -16));
    }
    return;
  }
  // Chasing a unit: follow it every so often
  if (target != null && !target.hasTag("building") && _repath <= 0) {
    _repath = 0.8;
    goal = map.cellAt(target.position + vec(0, -8));
    plan();
  }

  // Walk along the path
  if (path.isNotEmpty) {
    var next = map.cellCenter(path[0][0], path[0][1]) + vec(0, 16);
    var d = next - self.position;
    if (d.length < 3) {
      cell = path.removeAt(0);
    } else {
      self.position = self.position + d.normalized() * min(speed * dt, d.length);
      self.sprite.flipX = d.x < 0;
    }
    self.sprite.frame = (team == "guard" ? 0 : 1) + (floor(_t * 6) % 2 == 0 ? 0 : 2);
  } else {
    self.sprite.frame = team == "guard" ? 0 : 1;
  }
}

void onDeath(killer) {
  find("Spark FX").particles.burst(16, self.position + vec(0, -16));
  find("Colony").call("unitDown", self);
}
''';

const _tower = r'''
// A watchtower shoots raiders in range. Any building: losing its health
// tells the colony.
var range = 170.0;
var rate = 0.9;           // shots per second (towers only)
var cell = [0, 0];
var _cool = 0.0;

void onUpdate(dt) {
  if (self.name != "Watchtower") return;
  _cool -= dt;
  if (_cool > 0) return;
  var foes = findInRange("raider", self.position, range);
  if (foes.isEmpty) return;
  _cool = 1 / rate;
  var from = self.position + vec(0, -60);
  find("Arrows").bullets.fire(from, angleTo(from, foes[0]), 380, target: foes[0], damage: 1, turn: 720, radius: 6);
  playSound("assets/templates/isles/arrow.wav", 0.25);
}

void onDeath(killer) {
  find("Colony").call("buildingLost", self);
}
''';

const _title = r'''
// Title screen: a new random island, or a fixed one to share.
void onStart() {
  Game.timeScale = 1;
  playMusic("assets/templates/isles/isles.wav", 0.35);
  var best = loadValue("isles_best", 0);
  setText("BestText", best > 0 ? "Most raids survived: $best" : "");
}

void onUIAction(action) {
  if (action == "new") Game.data["islesSeed"] = null;
  if (action == "classic") Game.data["islesSeed"] = 1717;
  if (action == "new" || action == "classic") loadLevel("Island");
}
''';

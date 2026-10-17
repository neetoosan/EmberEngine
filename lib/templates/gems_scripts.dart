/// Ember Script source for the "Ember Gems" template (editable in the Script
/// workspace once a project is created from it).
const Map<String, String> gemsScripts = {
  'gems_board.ember': _board,
  'gems_title.ember': _title,
};

const _board = r'''
// Ember Gems: swap two neighbouring gems to line up three or more of a colour.
//   4 in a line  -> a blast gem that clears its row or column
//   an L or a T  -> a bomb that clears the 3 x 3 around it
//   5 in a line  -> a star: swap it with a gem to clear that whole colour
// Click a gem then a neighbour, or drag a gem toward a neighbour.
var levelTitle = "Ember Mine";
var moves = 18;
var goal = "score";        // score, collect or ice
var goalTarget = 2500;     // points (score) or gems (collect); ice: break it all
var goalColor = 0;         // collect: 0 ruby, 1 ember, 2 topaz, 3 emerald, 4 sapphire, 5 amethyst
var colors = 5;            // how many gem colours appear (4 to 6)
var twoStars = 4500;       // score for two / three stars
var threeStars = 6500;
var ice = "";              // 8 rows split by /, # = ice under that cell
var nextLevel = "Level 2"; // empty on the last level
var moveBonus = 300;       // points per move left when the goal is reached early

var size = 8;
var cell = 56;
var left = 256;
var top = 64;
var colorNames = ["rubies", "embers", "topazes", "emeralds", "sapphires", "amethysts"];

var state = "starting";    // idle, busy, won, lost
var score = 0;
var collected = 0;
var iceLeft = 0;
var cascade = 0;

var _gems = [];            // the gem entity in each cell (or null)
var _kinds = [];           // colour per cell: 0-5, 6 = star, -1 = empty
var _special = [];         // "", "row", "col", "bomb" or "star"
var _ice = [];             // ice hits left per cell
var _iceTiles = [];
var _selected = -1;
var _press = null;
var _idle = 0.0;
var _hint = [];
var _swapA = -1;
var _swapB = -1;
var _over = false;

// --- Board geometry

pos(i) => vec(left + (i % size) * cell + cell / 2, top + (i ~/ size) * cell + cell / 2);

cellAt(p) {
  var c = floor((p.x - left) / cell);
  var r = floor((p.y - top) / cell);
  if (c < 0 || r < 0 || c >= size || r >= size) return -1;
  return r * size + c;
}

bool adjacent(a, b) {
  if (a % size == b % size) return abs(a - b) == size;
  return a ~/ size == b ~/ size && abs(a - b) == 1;
}

bestKey() => "gems_best_${Game.level}";
starsKey() => "gems_stars_${Game.level}";
levelNumber() => Game.level.split(" ").last.toNumber();

// --- Setup

void onStart() {
  for (var i = 0; i < size * size; i++) {
    _gems.add(null);
    _kinds.add(-1);
    _special.add("");
    _ice.add(0);
    _iceTiles.add(null);
  }
  // Ice under some cells
  var rows = ice.trim() == "" ? [] : ice.trim().split("/");
  for (var r = 0; r < rows.length && r < size; r++) {
    for (var c = 0; c < rows[r].length && c < size; c++) {
      if (rows[r].substring(c, c + 1) != "#") continue;
      var i = r * size + c;
      _ice[i] = 2;
      _iceTiles[i] = spawn("Ice", pos(i));
      iceLeft++;
    }
  }
  // Gems, with no lines at the start and at least one possible move
  for (var i = 0; i < size * size; i++) place(i, freshKind(i), "");
  while (findMove().isEmpty) reroll();
  // They drop in, row by row
  for (var i = 0; i < size * size; i++) {
    var g = _gems[i];
    var to = pos(i);
    g.position = to - vec(0, 520);
    var delay = (size - 1 - i ~/ size) * 0.05 + (i % size) * 0.01;
    after(delay, () => slide(g, to, 0.45, "out"));
  }
  state = "busy";
  after(0.95, () { state = "idle"; });
  showResults(false);
  setText("LevelText", "${Game.level}  ·  $levelTitle");
  setText("BestText", "Best ${loadValue(bestKey(), 0)}");
  hud();
  playMusic("assets/templates/gems/gems.wav", 0.35);
}

// A colour that doesn't complete a line with the gems to the left and above.
int freshKind(i) {
  var c = i % size;
  var r = i ~/ size;
  for (var tries = 0; tries < 30; tries++) {
    var k = randomInt(colors);
    if (c >= 2 && _kinds[i - 1] == k && _kinds[i - 2] == k) continue;
    if (r >= 2 && _kinds[i - size] == k && _kinds[i - 2 * size] == k) continue;
    return k;
  }
  return randomInt(colors);
}

void place(i, k, special) {
  var g = spawn("Gem", pos(i));
  _gems[i] = g;
  setGem(i, k, special);
}

// Shows a cell's colour and special mark on its gem.
void setGem(i, k, special) {
  _kinds[i] = k;
  _special[i] = special;
  var g = _gems[i];
  if (g == null) return;
  g.sprite.frame = k;
  var mark = g.child("Mark");
  mark.enabled = special == "row" || special == "col" || special == "bomb";
  if (mark.enabled) mark.sprite.frame = special == "row" ? 0 : (special == "col" ? 1 : 2);
}

// New colours for every plain gem (start of level / no moves left).
void reroll() {
  for (var i = 0; i < size * size; i++) _kinds[i] = -1;
  for (var i = 0; i < size * size; i++) setGem(i, freshKind(i), "");
}

// --- Input

void onUpdate(dt) {
  if (state != "idle") return;
  _idle += dt;
  if (_idle > 5 && _hint.isEmpty) showHint();
  var m = Input.mouse;
  if (Input.click) {
    var i = cellAt(m);
    if (i < 0) {
      select(-1);
      return;
    }
    if (_selected >= 0 && adjacent(_selected, i)) {
      var a = _selected;
      select(-1);
      swap(a, i);
      return;
    }
    select(i == _selected ? -1 : i);
    _press = m;
    return;
  }
  // Dragging a gem toward a neighbour swaps them
  if (_selected >= 0 && _press != null && Input.mouseDown) {
    var d = m - _press;
    if (d.length > cell * 0.45) {
      var c = _selected % size;
      var r = _selected ~/ size;
      var j = -1;
      if (abs(d.x) > abs(d.y)) {
        if (d.x > 0 && c < size - 1) j = _selected + 1;
        if (d.x < 0 && c > 0) j = _selected - 1;
      } else {
        if (d.y > 0 && r < size - 1) j = _selected + size;
        if (d.y < 0 && r > 0) j = _selected - size;
      }
      var a = _selected;
      select(-1);
      _press = null;
      if (j >= 0) swap(a, j);
    }
  }
  if (Input.mouseReleased) _press = null;
}

void select(i) {
  _selected = i;
  _idle = 0;
  var s = find("Selector");
  s.enabled = i >= 0;
  if (i >= 0) {
    s.position = pos(i);
    playSound("click", volume: 0.3, pitch: 1.4);
  }
}

// --- Moves

void exchange(a, b) {
  var g = _gems[a];
  _gems[a] = _gems[b];
  _gems[b] = g;
  var k = _kinds[a];
  _kinds[a] = _kinds[b];
  _kinds[b] = k;
  var s = _special[a];
  _special[a] = _special[b];
  _special[b] = s;
}

void slide(g, to, seconds, ease) {
  if (g == null) return;
  var from = g.position;
  tween(seconds, (t) {
    if (g.alive) g.position = lerp(from, to, t);
  }, ease: ease);
}

void swap(a, b) {
  state = "busy";
  clearHint();
  _swapA = a;
  _swapB = b;
  slide(_gems[a], pos(b), 0.16, "inOut");
  slide(_gems[b], pos(a), 0.16, "inOut");
  exchange(a, b);
  after(0.18, () {
    if (_kinds[a] == 6 || _kinds[b] == 6) {
      useMove();
      starBlast(a, b);
      return;
    }
    var hit = matches();
    if (hit.isEmpty) {
      // Not a match: they swap back
      playSound("hit", volume: 0.35, pitch: 0.7);
      slide(_gems[a], pos(b), 0.16, "inOut");
      slide(_gems[b], pos(a), 0.16, "inOut");
      exchange(a, b);
      after(0.18, () { state = "idle"; });
      return;
    }
    useMove();
    cascade = 0;
    resolve(hit);
  });
}

void useMove() {
  moves--;
  hud();
}

// --- Finding lines

// Every line of 3+: returns [] or [cells to clear, specials to create], where
// each special is [cell, kind of special, colour].
List matches() {
  var mark = [];
  for (var i = 0; i < size * size; i++) mark.add(0);
  var runs = [];
  for (var horizontal in [true, false]) {
    for (var line = 0; line < size; line++) {
      var p = 0;
      while (p < size) {
        var first = horizontal ? line * size + p : p * size + line;
        var k = _kinds[first];
        var e = p + 1;
        while (e < size && k >= 0 && k < 6 && _kinds[horizontal ? line * size + e : e * size + line] == k) e++;
        if (k >= 0 && k < 6 && e - p >= 3) {
          var cells = [];
          for (var q = p; q < e; q++) {
            var i = horizontal ? line * size + q : q * size + line;
            cells.add(i);
            mark[i] = mark[i] + (horizontal ? 1 : 2);
          }
          runs.add([cells, horizontal]);
        }
        p = e;
      }
    }
  }
  if (runs.isEmpty) return [];
  var clear = [];
  var make = [];
  for (var run in runs) {
    var cells = run[0];
    for (var i in cells) {
      if (!clear.contains(i)) clear.add(i);
    }
    var k = _kinds[cells[0]];
    var cross = -1;
    for (var i in cells) {
      if (mark[i] == 3) cross = i;
    }
    var at = cells.contains(_swapB) ? _swapB : (cells.contains(_swapA) ? _swapA : cells[cells.length ~/ 2]);
    if (cross >= 0) {
      if (!madeAt(make, cross)) make.add([cross, "bomb", k]);
    } else if (cells.length >= 5) {
      make.add([at, "star", 6]);
    } else if (cells.length == 4) {
      make.add([at, run[1] ? "row" : "col", k]);
    }
  }
  return [clear, make];
}

bool madeAt(make, i) => make.any((m) => m[0] == i);

// --- Clearing

void resolve(hit) {
  cascade++;
  var make = hit[1];
  var queue = [];
  queue.addAll(hit[0]);
  var gone = [];
  var blasts = 0;
  while (queue.isNotEmpty) {
    var i = queue.removeLast();
    if (gone.contains(i) || _kinds[i] < 0 || madeAt(make, i)) continue;
    gone.add(i);
    var sp = _special[i];
    var c = i % size;
    var r = i ~/ size;
    if (sp == "row") {
      blasts++;
      for (var x = 0; x < size; x++) queue.add(r * size + x);
    } else if (sp == "col") {
      blasts++;
      for (var y = 0; y < size; y++) queue.add(y * size + c);
    } else if (sp == "bomb") {
      blasts++;
      for (var y = max(0, r - 1); y <= min(size - 1, r + 1); y++) {
        for (var x = max(0, c - 1); x <= min(size - 1, c + 1); x++) queue.add(y * size + x);
      }
    } else if (sp == "star") {
      // A star caught in a blast takes a random colour with it
      blasts++;
      var k = randomInt(colors);
      for (var j = 0; j < size * size; j++) {
        if (_kinds[j] == k) queue.add(j);
      }
    }
  }
  for (var i in gone) pop(i);
  for (var m in make) {
    var i = m[0];
    if (_gems[i] == null) continue;
    setGem(i, m[2], m[1]);
    score += 200;
    var g = _gems[i];
    tween(0.25, (t) {
      if (g.alive) g.scale = 1 + sin(t * pi) * 0.35;
    }, ease: "out");
  }
  playSound("coin", volume: 0.45, pitch: 0.9 + cascade * 0.12);
  if (blasts > 0) {
    playSound("explosion", volume: 0.4);
    find("Camera").camera.shake(4 + blasts * 2, 0.25);
  }
  if (cascade >= 3) praise(cascade);
  hud();
  after(0.22, () => collapse());
}

// Swapping a star: every gem of the other colour goes (two stars: the whole board).
void starBlast(a, b) {
  var star = _kinds[a] == 6 ? a : b;
  var other = star == a ? b : a;
  var k = _kinds[other];
  var cells = [star];
  for (var i = 0; i < size * size; i++) {
    if (k == 6 || _kinds[i] == k) cells.add(i);
  }
  cascade = 0;
  find("Camera").camera.shake(8, 0.35);
  resolve([cells, []]);
}

void pop(i) {
  var g = _gems[i];
  var k = _kinds[i];
  if (goal == "collect" && k == goalColor) collected++;
  score += (_special[i] == "" ? 60 : 150) * cascade;
  _gems[i] = null;
  _kinds[i] = -1;
  _special[i] = "";
  crackIce(i);
  find("Pop FX").particles.burst(8, pos(i));
  if (g == null) return;
  g.layer = 6;
  tween(0.18, (t) {
    if (g.alive) {
      g.scale = 1 + t * 0.5;
      g.sprite.opacity = 1 - t;
    }
  }, ease: "out", then: () => destroy(g));
}

void crackIce(i) {
  if (_ice[i] <= 0) return;
  _ice[i]--;
  var tile = _iceTiles[i];
  if (_ice[i] == 1) {
    tile.sprite.frame = 3;
  } else {
    destroy(tile);
    _iceTiles[i] = null;
    iceLeft--;
    score += 100;
    find("Ice FX").particles.burst(14, pos(i));
  }
}

// --- Falling

void collapse() {
  var longest = 0;
  for (var c = 0; c < size; c++) {
    var write = size - 1;
    for (var r = size - 1; r >= 0; r--) {
      var i = r * size + c;
      if (_kinds[i] < 0) continue;
      if (r != write) {
        var j = write * size + c;
        _gems[j] = _gems[i];
        _kinds[j] = _kinds[i];
        _special[j] = _special[i];
        _gems[i] = null;
        _kinds[i] = -1;
        _special[i] = "";
        drop(_gems[j], j, write - r, false);
        longest = max(longest, write - r);
      }
      write--;
    }
    // New gems fall in from above the board
    var missing = write + 1;
    for (var r = write; r >= 0; r--) {
      var i = r * size + c;
      place(i, randomInt(colors), "");
      _gems[i].position = pos(i) - vec(0, missing * cell);
      drop(_gems[i], i, missing, true);
      longest = max(longest, missing);
    }
  }
  after(0.16 + longest * 0.055, () => settle());
}

void drop(g, i, cells, fresh) {
  var from = g.position;
  var to = pos(i);
  if (fresh) g.sprite.opacity = 0;
  tween(0.14 + cells * 0.055, (t) {
    if (!g.alive) return;
    g.position = lerp(from, to, t);
    // New gems appear as they enter the board, not above it
    if (fresh) g.sprite.opacity = clamp((g.y - top + cell / 2) / (cell / 2), 0, 1);
  }, ease: "in");
}

void settle() {
  _swapA = -1;
  _swapB = -1;
  var hit = matches();
  if (hit.isNotEmpty) {
    resolve(hit);
    return;
  }
  hud();
  if (checkEnd()) return;
  if (findMove().isEmpty) {
    banner("No moves left: shuffling");
    reroll();
    while (findMove().isEmpty) reroll();
  }
  state = "idle";
  _idle = 0;
}

// --- Possible moves and hints

// A swap that would make a line: [a, b], or [] when there is none.
List findMove() {
  for (var i = 0; i < size * size; i++) {
    if (_kinds[i] == 6) return [i, i % size < size - 1 ? i + 1 : i - 1];
    if (i % size < size - 1 && swapMakesLine(i, i + 1)) return [i, i + 1];
    if (i + size < size * size && swapMakesLine(i, i + size)) return [i, i + size];
  }
  return [];
}

bool swapMakesLine(a, b) {
  if (_kinds[a] == _kinds[b]) return false;
  var k = _kinds[a];
  _kinds[a] = _kinds[b];
  _kinds[b] = k;
  var ok = lineAt(a) || lineAt(b);
  _kinds[b] = _kinds[a];
  _kinds[a] = k;
  return ok;
}

bool lineAt(i) {
  var k = _kinds[i];
  if (k < 0 || k > 5) return false;
  var c = i % size;
  var r = i ~/ size;
  var n = 1;
  var x = c - 1;
  while (x >= 0 && _kinds[r * size + x] == k) {
    n++;
    x--;
  }
  x = c + 1;
  while (x < size && _kinds[r * size + x] == k) {
    n++;
    x++;
  }
  if (n >= 3) return true;
  n = 1;
  var y = r - 1;
  while (y >= 0 && _kinds[y * size + c] == k) {
    n++;
    y--;
  }
  y = r + 1;
  while (y < size && _kinds[y * size + c] == k) {
    n++;
    y++;
  }
  return n >= 3;
}

void showHint() {
  _hint = findMove();
  for (var n = 0; n < _hint.length; n++) {
    var h = find("Hint ${n + 1}");
    h.enabled = true;
    h.position = pos(_hint[n]);
  }
}

void clearHint() {
  _hint = [];
  _idle = 0;
  find("Hint 1").enabled = false;
  find("Hint 2").enabled = false;
}

// --- Goals and the end of the level

bool goalMet() {
  if (goal == "collect") return collected >= goalTarget;
  if (goal == "ice") return iceLeft == 0;
  return score >= goalTarget;
}

// A score goal plays all its moves; collect and ice goals end as soon as they are met.
bool checkEnd() {
  if (goal != "score" && goalMet()) {
    win();
    return true;
  }
  if (moves <= 0) {
    if (goalMet()) {
      win();
    } else {
      lose();
    }
    return true;
  }
  return false;
}

void win() {
  if (_over) return;
  _over = true;
  state = "won";
  var bonus = moves * moveBonus;
  score += bonus;
  var stars = score >= threeStars ? 3 : (score >= twoStars ? 2 : 1);
  saveValue(bestKey(), max(score, loadValue(bestKey(), 0)));
  saveValue(starsKey(), max(stars, loadValue(starsKey(), 0)));
  saveValue("gems_unlocked", max(loadValue("gems_unlocked", 1), levelNumber() + 1));
  hud();
  playSound("coin", volume: 0.9, pitch: 1.3);
  showResults(true, "LEVEL CLEAR!", stars, bonus > 0 ? "Score $score   (+$bonus for $moves moves left)" : "Score $score");
}

void lose() {
  if (_over) return;
  _over = true;
  state = "lost";
  playSound("hit", volume: 0.8, pitch: 0.5);
  showResults(true, "OUT OF MOVES", 0, "Goal: ${goalLine()}");
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

// --- HUD

goalLine() {
  if (goal == "collect") return "Collect $goalTarget ${colorNames[goalColor]}  ($collected / $goalTarget)";
  if (goal == "ice") return "Break all the ice  ($iceLeft left)";
  return "Score $goalTarget";
}

void hud() {
  setText("MovesText", "$moves");
  setText("ScoreText", "$score");
  setText("GoalText", goalLine());
  var bar = find("StarBar").bar;
  bar.value = min(score, threeStars);
  bar.max = threeStars;
}

void banner(text) {
  setText("Banner", text);
  after(1.4, () => setText("Banner", ""));
}

void praise(n) {
  banner(n >= 5 ? "INCREDIBLE!" : (n >= 4 ? "BRILLIANT!" : "GREAT!"));
}
''';

const _title = r'''
// Title screen: level buttons with saved stars; later levels unlock as you win.
var levels = 3;
var _decor = [];
var _baseY = [];

void onStart() {
  var unlocked = loadValue("gems_unlocked", 1);
  for (var i = 1; i <= levels; i++) {
    var button = find("Level$i Button").get("UI Button");
    var stars = find("Level$i Stars").get("UI Image");
    if (i <= unlocked) {
      button.text = "$i";
      button.action = "level:Level $i";
      stars.filled = loadValue("gems_stars_Level $i", 0);
    } else {
      button.text = "Locked";
      button.action = "";
      button.color = "#475569";
      stars.filled = 0;
    }
  }
  for (var g in findAll("decor")) {
    _decor.add(g);
    _baseY.add(g.y);
  }
  playMusic("assets/templates/gems/gems.wav", 0.3);
}

// The gems around the logo sway gently
void onUpdate(dt) {
  for (var i = 0; i < _decor.length; i++) {
    _decor[i].y = _baseY[i] + sin(Game.time * 2 + i * 0.9) * 6;
  }
}

void onUIAction(action) {
  if (action != "reset") return;
  for (var i = 1; i <= levels; i++) {
    deleteValue("gems_stars_Level $i");
    deleteValue("gems_best_Level $i");
  }
  deleteValue("gems_unlocked");
  restart();
}
''';

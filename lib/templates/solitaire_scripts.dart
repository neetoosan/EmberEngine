/// Ember Script source for the "Ember Solitaire" template (editable in the
/// Script workspace once a project is created from it).
const Map<String, String> solitaireScripts = {
  'solitaire_table.ember': _table,
  'solitaire_title.ember': _title,
};

const _table = r'''
// Klondike solitaire. Build the four foundations up from Ace to King by suit.
// In the seven columns, stack cards downward in alternating colours; only a
// King may go into an empty column. Click the stock to turn cards over.
//   Drag a card (and the cards on it) to move them; click a card to send it
//   to the best place. Ctrl+Z undoes, H shows a hint.
var draw = 1;              // cards turned over from the stock at a time (1 or 3)
var mode = "Draw 1";       // used for the saved best times

var col0 = 152;            // centre of the first column
var colStep = 108;
var topY = 84;             // stock, waste and foundations
var tableY = 204;          // first card of each column
var downGap = 14;          // fan for face-down / face-up cards
var upGap = 26;
var lowest = 478;          // a column squeezes its fan to stay above this

var state = "dealing";     // dealing, play, auto, won
var score = 0;
var moves = 0;
var time = 0.0;
var passes = 0;

var _piles = [];           // 0 stock, 1 waste, 2-5 foundations, 6-12 columns
var _up = [];              // face up, per card
var _cards = [];           // the entity of each card (id 0-51)
var _history = [];
var _drag = [];
var _dragFrom = -1;
var _grab = vec(0, 0);
var _pressAt = null;
var _pressCard = -1;
var _hud = 0.0;
var _hinted = [];

suit(id) => id ~/ 13;      // 0 hearts, 1 diamonds, 2 clubs, 3 spades
rank(id) => id % 13 + 1;   // 1 = Ace ... 13 = King
bool red(id) => suit(id) < 2;
colX(c) => col0 + c * colStep;
cardId(e) => round(e.name.split(" ").last.toNumber());

int pileOf(id) {
  for (var p = 0; p < _piles.length; p++) {
    if (_piles[p].contains(id)) return p;
  }
  return -1;
}

// Where card number j of pile p goes.
cardPos(p, j) {
  if (p == 0) return vec(colX(0), topY);
  if (p == 1) {
    var n = _piles[1].length;
    var shown = draw == 3 ? min(3, n) : 1;
    return vec(colX(1) + max(0, j - (n - shown)) * 18, topY);
  }
  if (p <= 5) return vec(colX(p + 1), topY);
  var pile = _piles[p];
  var need = 0;
  for (var i = 0; i < pile.length - 1; i++) need += _up[pile[i]] ? upGap : downGap;
  var squeeze = need > lowest - tableY ? (lowest - tableY) / need : 1;
  var y = tableY;
  for (var i = 0; i < j; i++) y += (_up[pile[i]] ? upGap : downGap) * squeeze;
  return vec(colX(p - 6), y);
}

void show(id) {
  _cards[id].sprite.frame = _up[id] ? suit(id) * 13 + rank(id) - 1 : 52;
}

void slide(e, to, seconds) {
  var from = e.position;
  tween(seconds, (t) {
    if (e.alive) e.position = lerp(from, to, t);
  }, ease: "out");
}

// Puts every card of a pile in its place (animated).
void layout(p, seconds) {
  var pile = _piles[p];
  for (var j = 0; j < pile.length; j++) {
    var id = pile[j];
    var c = _cards[id];
    c.layer = 10 + j;
    show(id);
    slide(c, cardPos(p, j), seconds);
  }
}

void layoutAll(seconds) {
  for (var p = 0; p < _piles.length; p++) layout(p, seconds);
}

// --- Dealing

void onStart() {
  for (var p = 0; p < 13; p++) _piles.add([]);
  var deck = [];
  for (var id = 0; id < 52; id++) {
    deck.add(id);
    _up.add(false);
    _cards.add(null);
  }
  for (var i = deck.length - 1; i > 0; i--) {
    var j = randomInt(i + 1);
    var t = deck[i];
    deck[i] = deck[j];
    deck[j] = t;
  }
  for (var id in deck) {
    var c = spawn("Card", vec(colX(0), topY));
    c.name = "Card $id";
    _cards[id] = c;
  }
  // Column c gets c + 1 cards; the last one is face up. The rest is the stock.
  var order = [];
  var k = 0;
  for (var row = 0; row < 7; row++) {
    for (var c = row; c < 7; c++) {
      var id = deck[k];
      k++;
      _piles[6 + c].add(id);
      if (row == c) _up[id] = true;
      order.add(id);
    }
  }
  while (k < 52) {
    _piles[0].add(deck[k]);
    k++;
  }
  for (var id in _piles[0]) show(id);
  layout(0, 0);
  var delay = 0.0;
  for (var id in order) {
    var p = pileOf(id);
    var j = _piles[p].indexOf(id);
    var c = _cards[id];
    c.layer = 60 + j;
    _cards[id].sprite.frame = 52;
    after(delay, () {
      slide(c, cardPos(p, j), 0.22);
      playSound("click", volume: 0.15, pitch: 1.6);
    });
    after(delay + 0.22, () {
      c.layer = 10 + j;
      show(id);
    });
    delay += 0.035;
  }
  after(delay + 0.3, () { state = "play"; });
  find("AutoButton").enabled = false;
  showResults(false);
  setText("ModeText", mode);
  setText("BestText", bestLine());
  hud();
  playMusic("assets/templates/solitaire/solitaire.wav", 0.3);
}

// --- Input

void onUpdate(dt) {
  if (state == "play" || state == "auto") {
    time += dt;
    _hud += dt;
    if (_hud > 0.25) {
      _hud = 0;
      hud();
    }
  }
  if (state != "play") return;
  var m = Input.mouse;
  if (Input.click) press(m);
  if (_drag.isNotEmpty && Input.mouseDown && _pressAt != null && (m - _pressAt).length > 6) {
    for (var i = 0; i < _drag.length; i++) {
      _cards[_drag[i]].position = m - _grab + vec(0, i * upGap);
    }
  }
  if (Input.mouseReleased && _pressCard >= 0) release(m);
  if (Input.pressed("Z") && Input.key("Control")) undo();
  if (Input.pressed("H")) hint();
}

void press(m) {
  clearHint();
  var e = pick(m, "card");
  if (e == null) {
    // The empty stock: turn the waste over
    if (abs(m.x - colX(0)) < 32 && abs(m.y - topY) < 44) recycle();
    return;
  }
  var id = cardId(e);
  var p = pileOf(id);
  if (p == 0) {
    drawStock();
    return;
  }
  if (!_up[id]) return;
  var pile = _piles[p];
  var j = pile.indexOf(id);
  if (p <= 5 && j != pile.length - 1) return; // waste and foundations: only the top card
  _drag = [];
  for (var i = j; i < pile.length; i++) _drag.add(pile[i]);
  _dragFrom = p;
  _pressAt = m;
  _pressCard = id;
  _grab = m - e.position;
  for (var i = 0; i < _drag.length; i++) _cards[_drag[i]].layer = 200 + i;
}

void release(m) {
  var moved = _pressAt != null && (m - _pressAt).length > 6;
  _pressAt = null;
  _pressCard = -1;
  var cards = _drag;
  _drag = [];
  if (cards.isEmpty) return;
  var from = _dragFrom;
  var to = moved ? dropTarget(cards, m - _grab) : bestTarget(cards, from);
  if (to >= 0 && to != from && canMove(cards, to)) {
    doMove(cards, from, to);
    return;
  }
  if (moved) playSound("hit", volume: 0.25, pitch: 1.4);
  layout(from, 0.18);
}

// The pile under a dropped card (the nearest column top or foundation).
int dropTarget(cards, at) {
  var best = -1;
  var bestD = 70;
  for (var p = 2; p < 13; p++) {
    var d = at.distanceTo(cardPos(p, max(0, _piles[p].length - 1))); // its top card (or base)
    if (d < bestD && canMove(cards, p)) {
      bestD = d;
      best = p;
    }
  }
  return best;
}

// Where a clicked card goes: a foundation first, then a column.
int bestTarget(cards, from) {
  if (cards.length == 1) {
    for (var p = 2; p <= 5; p++) {
      if (canMove(cards, p)) return p;
    }
  }
  for (var p = 6; p < 13; p++) {
    if (p != from && _piles[p].isNotEmpty && canMove(cards, p)) return p;
  }
  // A King into an empty column (but not one already at the bottom of its column)
  var bottomKing = from >= 6 && _piles[from].indexOf(cards[0]) == 0;
  for (var p = 6; p < 13; p++) {
    if (p != from && _piles[p].isEmpty && canMove(cards, p) && !bottomKing) return p;
  }
  return -1;
}

bool canMove(cards, to) {
  var first = cards[0];
  if (to >= 2 && to <= 5) {
    if (cards.length != 1) return false;
    var f = _piles[to];
    if (f.isEmpty) return rank(first) == 1;
    return suit(f.last) == suit(first) && rank(first) == rank(f.last) + 1;
  }
  if (to >= 6) {
    var t = _piles[to];
    if (t.isEmpty) return rank(first) == 13;
    var top = t.last;
    return _up[top] && red(top) != red(first) && rank(first) == rank(top) - 1;
  }
  return false;
}

// --- Moves

void snapshot() {
  _history.add([_piles.map((p) => p.map((x) => x)), _up.map((u) => u), score, moves, passes]);
  if (_history.length > 300) _history.removeAt(0);
}

void doMove(cards, from, to) {
  snapshot();
  for (var id in cards) {
    _piles[from].remove(id);
    _piles[to].add(id);
  }
  if (to >= 2 && to <= 5) score += 10;
  if (from == 1 && to >= 6) score += 5;
  if (from >= 2 && from <= 5 && to >= 6) score = max(0, score - 15);
  moves++;
  layout(to, 0.16);
  layout(from, 0.16);
  flipTop(from);
  playSound(to <= 5 ? "coin" : "click", volume: to <= 5 ? 0.35 : 0.3, pitch: to <= 5 ? 1.2 + rank(cards[0]) * 0.03 : 1.1);
  hud();
  check();
}

// A face-down card left on top of a column turns over.
void flipTop(p) {
  if (p < 6 || _piles[p].isEmpty) return;
  var id = _piles[p].last;
  if (_up[id]) return;
  score += 5;
  var c = _cards[id];
  show(id);          // still the back
  _up[id] = true;    // the face shows half way through the turn
  tween(0.2, (t) {
    if (!c.alive) return;
    if (t >= 0.5) show(id);
    c.scale = vec(abs(1 - t * 2), 1);
  }, ease: "linear", then: () { c.scale = 1; });
}

void drawStock() {
  if (_piles[0].isEmpty) {
    recycle();
    return;
  }
  snapshot();
  for (var k = 0; k < draw && _piles[0].isNotEmpty; k++) {
    var id = _piles[0].removeLast();
    _up[id] = true;
    _piles[1].add(id);
  }
  moves++;
  layout(1, 0.16);
  playSound("click", volume: 0.3, pitch: 1.3);
  hud();
  check();
}

// The waste turns back over into the stock.
void recycle() {
  if (_piles[0].isNotEmpty || _piles[1].isEmpty) return;
  snapshot();
  while (_piles[1].isNotEmpty) {
    var id = _piles[1].removeLast();
    _up[id] = false;
    _piles[0].add(id);
  }
  passes++;
  if (draw == 1) score = max(0, score - 100);
  layout(0, 0.2);
  playSound("click", volume: 0.3, pitch: 0.8);
  hud();
}

void undo() {
  if (_history.isEmpty || state != "play") return;
  var h = _history.removeLast();
  _piles = h[0];
  _up = h[1];
  score = h[2];
  moves = h[3] + 1;
  passes = h[4];
  layoutAll(0.18);
  for (var id = 0; id < 52; id++) _cards[id].scale = 1;
  playSound("click", volume: 0.25, pitch: 0.9);
  find("AutoButton").enabled = false;
  hud();
}

// --- Hints

// A useful move: [cards, from, to], or [] (then the stock is the hint).
List findMove() {
  var sources = [];
  if (_piles[1].isNotEmpty) sources.add([[_piles[1].last], 1]);
  for (var p = 6; p < 13; p++) {
    var pile = _piles[p];
    for (var j = 0; j < pile.length; j++) {
      if (!_up[pile[j]]) continue;
      var cards = [];
      for (var i = j; i < pile.length; i++) cards.add(pile[i]);
      sources.add([cards, p]);
      break; // the whole face-up run
    }
    if (pile.isNotEmpty && _up[pile.last] && pile.length > 1) sources.add([[pile.last], p]);
  }
  for (var s in sources) {
    if (s[0].length == 1) {
      for (var to = 2; to <= 5; to++) {
        if (canMove(s[0], to)) return [s[0], s[1], to];
      }
    }
  }
  for (var s in sources) {
    var from = s[1];
    var at = _piles[from].indexOf(s[0][0]);
    for (var to = 6; to < 13; to++) {
      if (to == from || !canMove(s[0], to)) continue;
      // Useful: from the waste, or it turns a card over, or it empties a column onto another card
      var useful = from == 1 || (at > 0 ? !_up[_piles[from][at - 1]] : _piles[to].isNotEmpty);
      if (useful) return [s[0], from, to];
    }
  }
  return [];
}

void hint() {
  clearHint();
  var m = findMove();
  if (m.isEmpty) {
    if (_piles[0].isNotEmpty) _hinted = [_piles[0].last];
  } else {
    _hinted = [];
    _hinted.addAll(m[0]);
    if (_piles[m[2]].isNotEmpty) _hinted.add(_piles[m[2]].last);
  }
  for (var id in _hinted) _cards[id].sprite.tint = "#FDE68A";
  after(0.9, () => clearHint());
}

void clearHint() {
  for (var id in _hinted) {
    if (_cards[id].alive) _cards[id].sprite.tint = "#FFFFFF";
  }
  _hinted = [];
}

// --- Finishing

int onFoundations() => _piles[2].length + _piles[3].length + _piles[4].length + _piles[5].length;

void check() {
  if (onFoundations() == 52) {
    win();
    return;
  }
  // Everything is face up and the stock is empty: offer to finish
  var open = _piles[0].isEmpty && _piles[1].isEmpty;
  for (var p = 6; p < 13 && open; p++) {
    for (var id in _piles[p]) {
      if (!_up[id]) open = false;
    }
  }
  find("AutoButton").enabled = open && state == "play";
}

void autoFinish() {
  if (state != "play") return;
  state = "auto";
  find("AutoButton").enabled = false;
  autoStep();
}

void autoStep() {
  // The lowest card that can go up
  var best = -1;
  var bestFrom = -1;
  for (var p = 1; p < 13; p++) {
    if (p >= 2 && p <= 5) continue;
    if (_piles[p].isEmpty) continue;
    var id = _piles[p].last;
    for (var to = 2; to <= 5; to++) {
      if (canMove([id], to) && (best < 0 || rank(id) < rank(best))) {
        best = id;
        bestFrom = p;
      }
    }
  }
  if (best < 0) {
    state = "play";
    return;
  }
  doMove([best], bestFrom, bestTarget([best], bestFrom));
  if (state == "auto") after(0.08, () => autoStep());
}

void win() {
  state = "won";
  find("AutoButton").enabled = false;
  var bonus = time > 30 ? max(0, 1500 - floor(time) * 3) : 1500;
  score += bonus;
  var key = "solitaire_${mode}";
  var bestTime = loadValue("${key}_time", 0);
  if (bestTime == 0 || time < bestTime) saveValue("${key}_time", round(time));
  saveValue("${key}_score", max(score, loadValue("${key}_score", 0)));
  saveValue("${key}_wins", loadValue("${key}_wins", 0) + 1);
  hud();
  playSound("coin", volume: 0.9, pitch: 1.5);
  celebrate();
  after(3.2, () => showResults(true, "YOU WIN!", "Time ${clock(time)}  ·  Moves $moves  ·  Score $score  (+$bonus time bonus)"));
}

// The classic finish: the cards bounce off the foundations one by one.
void celebrate() {
  var n = 0;
  for (var r = 13; r >= 1; r--) {
    for (var p = 2; p <= 5; p++) {
      var pile = _piles[p];
      if (pile.length < r) continue;
      var c = _cards[pile[r - 1]];
      var from = c.position;
      var dir = randomRange(-1, 1) > 0 ? 1 : -1;
      var speed = randomRange(260, 480);
      var height = randomRange(140, 260);
      after(n * 0.05, () {
        c.layer = 300;
        tween(1.8, (t) {
          if (!c.alive) return;
          var floorY = 470;
          var x = from.x + dir * speed * t * 1.8;
          var bounce = abs(sin(t * pi * 3.5)) * height * (1 - t);
          var y = from.y + (floorY - from.y) * min(1, t * 4) - bounce;
          c.position = vec(x, y);
        }, ease: "linear");
      });
      n++;
    }
  }
}

void showResults(show, [heading, line]) {
  for (var name in ["ResultsPanel", "ResultsTitle", "ResultsLine", "ResultsBest", "AgainButton", "MenuButton"]) {
    find(name).enabled = show;
  }
  if (!show) return;
  setText("ResultsTitle", heading);
  setText("ResultsLine", line);
  setText("ResultsBest", bestLine());
}

// --- HUD and buttons

clock(seconds) {
  var s = floor(seconds);
  var sec = s % 60;
  return "${s ~/ 60}:${sec < 10 ? "0" : ""}$sec";
}

bestLine() {
  var key = "solitaire_${mode}";
  var t = loadValue("${key}_time", 0);
  var wins = loadValue("${key}_wins", 0);
  if (wins == 0) return "No wins yet in $mode";
  return "Best time ${clock(t)}  ·  Best score ${loadValue("${key}_score", 0)}  ·  Wins $wins";
}

void hud() {
  setText("ScoreText", "$score");
  setText("MovesText", "$moves");
  setText("TimeText", clock(time));
}

void onUIAction(action) {
  if (action == "undo") undo();
  if (action == "hint") hint();
  if (action == "auto") autoFinish();
}
''';

const _title = r'''
// Title screen: choose Draw 1 or Draw 3; shows your records for each.
void onStart() {
  for (var mode in ["Draw 1", "Draw 3"]) {
    var key = "solitaire_${mode}";
    var wins = loadValue("${key}_wins", 0);
    var t = loadValue("${key}_time", 0);
    var line = wins == 0 ? "No wins yet" : "Wins $wins  ·  best ${t ~/ 60}:${t % 60 < 10 ? "0" : ""}${t % 60}";
    setText("$mode Record", line);
  }
  playMusic("assets/templates/solitaire/solitaire.wav", 0.3);
}

void onUIAction(action) {
  if (action != "reset") return;
  for (var mode in ["Draw 1", "Draw 3"]) {
    for (var what in ["time", "score", "wins"]) deleteValue("solitaire_${mode}_$what");
  }
  restart();
}
''';

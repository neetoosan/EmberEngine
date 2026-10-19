import 'pulse_song.dart';

/// Ember Script source and charts for the "Ember Pulse" template (all of it
/// editable in the Script workspace once a project is created from it).
final Map<String, String> pulseScripts = {
  'pulse_stage.ember': _stage,
  'pulse_title.ember': _title,
  'pulse_easy.chart': PulseSong.chart('easy'),
  'pulse_normal.chart': PulseSong.chart('normal'),
  'pulse_hard.chart': PulseSong.chart('hard'),
};

const _stage = r'''
// Ember Pulse: notes fall down four lanes in time with the song. Hit D F J K
// (or the arrow keys, or tap the lane) as they reach the line. Hold the long
// ones. Timing comes from Music.time, the clock of the music you hear.
var perfect = 0.045;      // seconds early or late for each judgement
var great = 0.09;
var good = 0.14;
var hitY = 450.0;
var laneX = [345, 435, 525, 615];
var keys = [["D", "Left"], ["F", "Down"], ["J", "Up"], ["K", "Right"]];
var travel = {"easy": 1.6, "normal": 1.35, "hard": 1.1};
var song = "assets/templates/pulse/song.wav";
var songLength = 0.0;

var difficulty = "normal";
var notes = [];           // each: [time, lane, hold, state, note, trail]; state 0 waiting, 1 falling, 2 hit, 3 holding, 4 done
var next = 0;
var score = 0;
var combo = 0;
var maxCombo = 0;
var counts = {"perfect": 0, "great": 0, "good": 0, "miss": 0};
var state = "play";       // play, paused, done
var _judge = 0.0;
var _last = 0.0;

void onStart() {
  difficulty = Game.data["pulseDiff"] ?? "normal";
  Music.offset = loadValue("pulse_offset", 0.0);
  for (var line in readText("pulse_" + difficulty + ".chart").split("\n")) {
    var parts = line.trim().split(" ");
    if (parts.length != 3 || line.startsWith("#")) continue;
    notes.add([parts[0].toNumber(), parts[1].toNumber(), parts[2].toNumber(), 0, null, null]);
  }
  songLength = notes[notes.length - 1][0] + notes[notes.length - 1][2] + 2.5;
  setText("SongText", "NEON DRIFT  ·  " + difficulty.toUpperCase());
  playMusic(song, 0.8, loop: false);
  hud();
}

void onUpdate(dt) {
  if (Input.pressed("P") || Input.pressed("Escape")) togglePause();
  if (state != "play") return;
  var t = Music.time;
  var fall = travel[difficulty];

  // Notes appear [fall] seconds before they should be hit
  while (next < notes.length && notes[next][0] - fall <= t) {
    var n = notes[next];
    n[3] = 1;
    n[4] = spawn("Note", vec(laneX[n[1]], -40));
    n[4].sprite.frame = n[1];
    if (n[2] > 0) {
      n[5] = spawn("Trail", vec(laneX[n[1]], -40));
      n[5].sprite.tint = ["#67E8F9", "#C084FC", "#F9A8D4", "#FDBA74"][n[1]];
    }
    next++;
  }

  // Press, hold and release, lane by lane
  for (var lane = 0; lane < 4; lane++) {
    var down = Input.key(keys[lane][0]) || Input.key(keys[lane][1]) || (Input.mouseDown && laneAt(Input.mouse) == lane);
    var pressed = Input.pressed(keys[lane][0]) || Input.pressed(keys[lane][1]) || (Input.click && laneAt(Input.mouse) == lane);
    var receptor = find("Receptor $lane");
    receptor.scale = down ? 1.12 : 1;
    if (pressed) press(lane, t);
    for (var n in notes) {
      if (n[1] == lane && n[3] == 3) {
        if (t >= n[0] + n[2]) finishHold(n, true);
        else if (!down) finishHold(n, t >= n[0] + n[2] - good);
      }
    }
  }

  // Positions, and notes that went by
  for (var n in notes) {
    if (n[3] == 1 || n[3] == 3) {
      var y = hitY - (n[0] - t) / fall * (hitY + 40);
      if (n[3] == 3) y = hitY;
      n[4].y = y;
      if (n[5] != null) {
        var top = hitY - (n[0] + n[2] - t) / fall * (hitY + 40);
        n[5].y = (top + y) / 2;
        n[5].scale = vec(1, max(0.01, (y - top) / 256));
      }
      if (n[3] == 1 && t - n[0] > good) miss(n);
    }
  }

  // The beat pulses through the stage
  var beat = (t - 2.0) * 124 / 60;
  var pulse = beat > 0 ? 1 - (beat % 1) : 0;
  find("Background").sprite.opacity = 0.85 + pulse * 0.15;
  if (_judge > 0) {
    _judge -= dt;
    if (_judge <= 0) setText("Judgement", "");
  }
  find("Progress").bar.value = clamp(t / songLength, 0, 1);
  if (Music.ended || t > songLength) finish();
}

int laneAt(p) {
  if (p.y < 260) return -1;
  for (var i = 0; i < 4; i++) {
    if (abs(p.x - laneX[i]) < 45) return i;
  }
  return -1;
}

void press(lane, t) {
  var best = null;
  for (var n in notes) {
    if (n[1] == lane && n[3] == 1 && abs(n[0] - t) <= good + 0.02) {
      if (best == null || abs(n[0] - t) < abs(best[0] - t)) best = n;
    }
  }
  if (best == null) return;
  var off = abs(best[0] - t);
  var kind = off <= perfect ? "perfect" : (off <= great ? "great" : "good");
  judge(kind, lane);
  if (best[2] > 0) {
    best[3] = 3;
  } else {
    best[3] = 4;
    destroy(best[4]);
  }
}

void finishHold(n, ok) {
  n[3] = 4;
  destroy(n[4]);
  if (n[5] != null) destroy(n[5]);
  if (ok) {
    score += 150;
    flash(n[1], "#FFFFFF");
  } else {
    combo = 0;
    counts["miss"] = counts["miss"] + 1;
    show("MISS", "#94A3B8");
  }
  hud();
}

void miss(n) {
  n[3] = 4;
  if (n[4] != null) destroy(n[4]);
  if (n[5] != null) destroy(n[5]);
  combo = 0;
  counts["miss"] = counts["miss"] + 1;
  show("MISS", "#94A3B8");
  playSound("assets/templates/pulse/miss.wav", 0.25);
  hud();
}

void judge(kind, lane) {
  counts[kind] = counts[kind] + 1;
  combo++;
  maxCombo = max(maxCombo, combo);
  var points = {"perfect": 300, "great": 200, "good": 100}[kind];
  score += round(points * (1 + min(combo, 100) / 100));
  show(kind.toUpperCase(), {"perfect": "#FDE68A", "great": "#67E8F9", "good": "#C4B5FD"}[kind]);
  flash(lane, ["#67E8F9", "#C084FC", "#F9A8D4", "#FDBA74"][lane]);
  hud();
}

void flash(lane, color) {
  var f = spawn("Flash", vec(laneX[lane], hitY));
  f.sprite.tint = color;
  tween(0.25, (k) {
    f.scale = 1 + k * 0.6;
    f.sprite.opacity = 1 - k;
  }, ease: "out", then: () { destroy(f); });
  find("Sparks").particles.burst(10, vec(laneX[lane], hitY));
}

void show(text, color) {
  setText("Judgement", text);
  find("Judgement").text.color = color;
  _judge = 0.5;
}

double accuracy() {
  var total = counts["perfect"] + counts["great"] + counts["good"] + counts["miss"];
  if (total == 0) return 1;
  return (counts["perfect"] + counts["great"] * 0.7 + counts["good"] * 0.4) / total;
}

void hud() {
  setText("ScoreText", "$score");
  setText("ComboText", combo >= 5 ? "$combo" : "");
  setText("AccuracyText", "${(accuracy() * 100).toStringAsFixed(1)}%");
}

void togglePause() {
  if (state == "done") return;
  if (state == "play") {
    state = "paused";
    Music.pause();
    Game.timeScale = 0;
  } else {
    state = "play";
    Music.resume();
    Game.timeScale = 1;
  }
  for (var n in ["PausedText", "ResumeButton", "QuitButton"]) find(n).enabled = state == "paused";
}

void finish() {
  if (state == "done") return;
  state = "done";
  var acc = accuracy();
  var grade = acc >= 0.95 ? "S" : (acc >= 0.9 ? "A" : (acc >= 0.8 ? "B" : (acc >= 0.7 ? "C" : "D")));
  var full = counts["miss"] == 0;
  var key = "pulse_best_" + difficulty;
  var best = loadValue(key, 0);
  if (score > best) {
    saveValue(key, score);
    saveValue("pulse_grade_" + difficulty, grade);
  }
  playSound("assets/templates/pulse/cheer.wav", 0.6);
  for (var n in ["ResultsPanel", "ResultsTitle", "ResultsGrade", "ResultsLine", "ResultsStats", "RetryButton", "MenuButton"]) find(n).enabled = true;
  setText("ResultsTitle", full ? "FULL COMBO!" : "SONG CLEAR");
  setText("ResultsGrade", grade);
  setText("ResultsLine", "Score $score   ·   Accuracy ${(acc * 100).toStringAsFixed(1)}%   ·   Max combo $maxCombo${score > best ? "   ·   NEW BEST" : ""}");
  setText("ResultsStats", "Perfect ${counts["perfect"]}   Great ${counts["great"]}   Good ${counts["good"]}   Miss ${counts["miss"]}");
}

void onUIAction(action) {
  if (action == "resume") togglePause();
  if (action == "retry") {
    Game.timeScale = 1;
    restart();
  }
  if (action == "menu") {
    Game.timeScale = 1;
    Music.stop();
    loadLevel("Title");
  }
}
''';

const _title = r'''
// Title screen: pick a difficulty, set the audio offset if hits feel late.
var offset = 0.0;

void onStart() {
  Game.timeScale = 1;
  offset = loadValue("pulse_offset", 0.0);
  playMusic("assets/templates/pulse/song.wav", 0.35);
  for (var d in ["easy", "normal", "hard"]) {
    var best = loadValue("pulse_best_" + d, 0);
    var grade = loadValue("pulse_grade_" + d, "");
    setText(d.toUpperCase() + "Best", best > 0 ? "$grade  ·  $best" : "");
  }
  showOffset();
}

void showOffset() {
  setText("OffsetText", "Audio offset ${round(offset * 1000)} ms");
}

void onUIAction(action) {
  if (action == "easy" || action == "normal" || action == "hard") {
    Game.data["pulseDiff"] = action;
    loadLevel("Stage");
  }
  if (action == "later" || action == "sooner") {
    offset = clamp(offset + (action == "later" ? 0.01 : -0.01), -0.3, 0.3);
    saveValue("pulse_offset", offset);
    showOffset();
  }
}
''';

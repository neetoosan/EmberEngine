part of 'paint_art_test.dart';

// Ember Clash: a 1v1 fighting game. The two fighters are drawn with a small
// puppet rig (joint angles per pose, rounded shaded limbs), so each of the
// 15 poses is just a list of angles. A temple at dusk for the stage.

const _clash = 'clash';

/// A fighter's look: gi colours, skin, hair/hood, accent (belt, headband).
class _Look {
  final Color gi, giDark, skin, hair, accent;
  final bool hood;
  const _Look(this.gi, this.giDark, this.skin, this.hair, this.accent, {this.hood = false});
}

const _kai = _Look(Color(0xFFF97316), Color(0xFFC2410C), Color(0xFFF2C29B), Color(0xFF292524), Color(0xFFDC2626));
const _ryn = _Look(Color(0xFF38BDF8), Color(0xFF0369A1), Color(0xFFE8B996), Color(0xFF1E293B), Color(0xFFE0F2FE), hood: true);

/// Joint angles in degrees (0 = straight down; positive turns toward the facing side).
class _Pose {
  final double dx, dy, lean; // body offset and torso lean
  final double armB, elbowB, armF, elbowF; // back / front arm: shoulder and elbow
  final double legB, kneeB, legF, kneeF; // back / front leg: hip and knee
  const _Pose({this.dx = 0, this.dy = 0, this.lean = 0, this.armB = 20, this.elbowB = 90, this.armF = 40, this.elbowF = 100, this.legB = -14, this.kneeB = 4,
      this.legF = 16, this.kneeF = -6});
}

const _poses = [
  _Pose(), // 0 idle
  _Pose(dy: -3, legB: -26, kneeB: 20, legF: 22, kneeF: -2, armB: 10, armF: 50), // 1 walk
  _Pose(dy: -1, legB: 6, kneeB: 4, legF: -10, kneeF: 24, armB: 34, armF: 30), // 2 walk
  _Pose(dy: 36, lean: 18, legB: -50, kneeB: 110, legF: 60, kneeF: -40, armB: 30, armF: 60), // 3 crouch
  _Pose(dy: -10, lean: 10, legB: -40, kneeB: 120, legF: 60, kneeF: 70, armB: 60, armF: 80), // 4 jump
  _Pose(lean: 10, armF: 92, elbowF: 0, armB: 10, elbowB: 110), // 5 jab
  _Pose(lean: -18, legF: 105, kneeF: -10, legB: -8, armB: -20, armF: 30), // 6 kick
  _Pose(dy: 30, lean: 12, legB: -50, kneeB: 100, legF: 92, kneeF: -4, armB: 30, armF: 60), // 7 low kick
  _Pose(dy: -12, lean: 20, legF: 60, kneeF: 0, legB: -40, kneeB: 100, armB: 50, armF: 70), // 8 air kick
  _Pose(lean: 12, armF: 90, elbowF: 6, armB: 84, elbowB: 10, legB: -24, legF: 26), // 9 cast
  _Pose(dy: -18, lean: -6, armF: 175, elbowF: 0, armB: 30, legB: -10, kneeB: 50, legF: 30, kneeF: 20), // 10 uppercut
  _Pose(lean: -4, armF: 120, elbowF: -120, armB: 110, elbowB: -110), // 11 block
  _Pose(dx: -8, lean: -26, armF: -20, elbowF: 40, armB: -40, elbowB: 30, legF: 26, legB: -10), // 12 hit
  _Pose(), // 13 knocked out (drawn lying down)
  _Pose(armF: 170, elbowF: 0, armB: 30, elbowB: 60), // 14 win
];

Offset _from(Offset p, double deg, double len) => p + Offset(math.sin(deg * math.pi / 180), math.cos(deg * math.pi / 180)) * len;

void _limb(Canvas c, Offset a, Offset b, double width, Color light, Color dark) {
  final paint = Paint()
    ..shader = LinearGradient(colors: [light, dark]).createShader(Rect.fromPoints(a, b).inflate(width))
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  c.drawLine(a, b, paint);
}

void _fighter(Canvas c, int poseIndex, _Look look) {
  final pose = _poses[poseIndex];
  if (poseIndex == 13) {
    // Lying on the ground
    c.save();
    c.translate(96, 176);
    c.rotate(-math.pi / 2);
    c.translate(-96, -176);
    _drawFighter(c, const _Pose(armB: 160, armF: 170, elbowF: 10, legB: -4, legF: 6), look, base: const Offset(96, 214));
    c.restore();
    return;
  }
  c.drawOval(const Rect.fromLTWH(56, 174, 80, 14), _glow(const Color(0x66000000), 4));
  _drawFighter(c, pose, look, base: Offset(96 + pose.dx, 180));
}

void _drawFighter(Canvas c, _Pose pose, _Look look, {required Offset base}) {
  const thigh = 40.0, shin = 40.0, upper = 32.0, fore = 30.0, torso = 52.0;
  final hip = base + Offset(0, -thigh - shin + 6 + pose.dy);
  final neck = _from(hip, 180 - pose.lean, torso);
  final shoulder = neck + const Offset(0, 6);
  void leg(double hipA, double kneeA, bool front) {
    final knee = _from(hip, hipA, thigh);
    final foot = _from(knee, hipA + kneeA, shin);
    _limb(c, hip, knee, 22, front ? look.gi : look.giDark, look.giDark);
    _limb(c, knee, foot, 18, front ? look.gi : look.giDark, look.giDark);
    _limb(c, foot, foot + const Offset(11, 0), 11, look.hair, look.hair);
  }

  void arm(double shA, double elA, bool front) {
    final elbow = _from(shoulder, shA, upper);
    final hand = _from(elbow, shA + elA, fore);
    _limb(c, shoulder, elbow, 17, front ? look.gi : look.giDark, look.giDark);
    _limb(c, elbow, hand, 14, look.skin, Color.lerp(look.skin, const Color(0xFF000000), 0.2)!);
    c.drawCircle(hand, 8.5, _fill(Color.lerp(look.skin, const Color(0xFF000000), 0.08)!));
  }

  arm(pose.armB, pose.elbowB, false);
  leg(pose.legB, pose.kneeB, false);
  // Torso (gi) with belt
  final body = Path()
    ..moveTo(hip.dx - 19, hip.dy)
    ..lineTo(neck.dx - 18, neck.dy + 4)
    ..quadraticBezierTo(neck.dx, neck.dy - 6, neck.dx + 18, neck.dy + 4)
    ..lineTo(hip.dx + 19, hip.dy)
    ..close();
  c.drawPath(body, _linear(Rect.fromPoints(neck, hip).inflate(16), [look.gi, look.giDark], begin: Alignment.topRight, end: Alignment.bottomLeft));
  c.drawPath(_poly([neck + const Offset(-4, 6), neck + const Offset(6, 6), hip + const Offset(4, -8)]), _fill(const Color(0x33000000)));
  c.drawLine(hip + const Offset(-19, -4), hip + const Offset(19, -4), _stroke(look.accent, 7));
  leg(pose.legF, pose.kneeF, true);
  // Head
  final head = _from(neck, 180 - pose.lean * 0.6, 16);
  if (look.hood) {
    c.drawCircle(head, 19, _radial(head - const Offset(5, 6), 26, [look.gi, look.giDark]));
    c.drawOval(Rect.fromCenter(center: head + const Offset(5, 2), width: 22, height: 18), _fill(look.skin));
    c.drawRect(Rect.fromCenter(center: head + const Offset(5, 7), width: 24, height: 9), _fill(look.giDark));
    c.drawCircle(head + const Offset(10, 0), 2.2, _fill(const Color(0xFF0F172A)));
  } else {
    c.drawCircle(head, 16, _radial(head - const Offset(4, 5), 22, [look.skin, Color.lerp(look.skin, const Color(0xFF000000), 0.25)!]));
    c.drawArc(Rect.fromCircle(center: head, radius: 17), math.pi * 0.95, math.pi * 1.2, true, _fill(look.hair));
    c.drawLine(head + const Offset(-16, -4), head + const Offset(15, -6), _stroke(look.accent, 5));
    c.drawLine(head + const Offset(-16, -4), head + const Offset(-30, 4), _stroke(look.accent, 3.5));
    c.drawCircle(head + const Offset(9, 1), 2.2, _fill(const Color(0xFF1C1917)));
  }
  arm(pose.armF, pose.elbowF, true);
}

Future<void> _paintClash() async {
  await _sheet(_clash, 'kai.png', 192, 192, 15, (c, i) => _fighter(c, i, _kai), columns: 5);
  await _sheet(_clash, 'ryn.png', 192, 192, 15, (c, i) => _fighter(c, i, _ryn), columns: 5);
  await _png(_clash, 'stage.png', 960, 540, _clashStage);
  await _sheet(_clash, 'orbs.png', 96, 96, 2, (c, i) {
    final color = i == 0 ? const Color(0xFFF97316) : const Color(0xFF38BDF8);
    _softDot(c, const Offset(48, 48), 46, color, core: 0.15);
    c.drawCircle(const Offset(48, 48), 15, _radial(const Offset(43, 43), 20, [const Color(0xFFFFFFFF), color]));
    for (var k = 0; k < 3; k++) {
      c.drawOval(Rect.fromCenter(center: Offset(26.0 - k * 8, 48), width: 26 - k * 6.0, height: 14 - k * 3.0), _glow(color.withValues(alpha: 0.6 - k * 0.15), 4));
    }
  });
  await _png(_clash, 'spark.png', 128, 128, (c) {
    _softDot(c, const Offset(64, 64), 60, const Color(0xCCFFF7ED), core: 0.1);
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4;
      c.drawLine(Offset(64 + math.cos(a) * 14, 64 + math.sin(a) * 14), Offset(64 + math.cos(a) * (k.isEven ? 60 : 40), 64 + math.sin(a) * (k.isEven ? 60 : 40)),
          _stroke(const Color(0xFFFFFFFF), 5, blur: 1.5));
    }
  });
  await _png(_clash, 'panel.png', 840, 520, _depthsPanelLike);

  _writeWav(_clash, 'clash.wav', _clashTheme());
  final thudLp = _LowPass();
  _writeWav(_clash, 'punch.wav', _effect(0.22, (t) => thudLp.process(_noise(), 1800) * math.exp(-t * 26) * 1.4 + math.sin(2 * math.pi * (120 + 160 * math.exp(-t * 40)) * t) * math.exp(-t * 22), peak: 0.6));
  final kickLp = _LowPass();
  _writeWav(_clash, 'kick.wav', _effect(0.3, (t) => kickLp.process(_noise(), 1200) * math.exp(-t * 18) * 1.4 + math.sin(2 * math.pi * (80 + 140 * math.exp(-t * 30)) * t) * math.exp(-t * 14), peak: 0.7));
  _writeWav(_clash, 'block.wav', _effect(0.15, (t) => (math.sin(2 * math.pi * 1400 * t) * 0.5 + _noise() * 0.3) * math.exp(-t * 35), peak: 0.45));
  _writeWav(_clash, 'swoosh.wav', _effect(0.2, (t) {
    final lp = 1 - t / 0.2;
    return _noise() * lp * lp * 0.45;
  }, peak: 0.3));
  _writeWav(_clash, 'fireball.wav', _effect(0.6, (t) {
    final f = 200 + 600 * math.exp(-t * 6);
    return (math.sin(2 * math.pi * f * t) * 0.4 + _noise() * 0.3) * math.exp(-t * 4);
  }, peak: 0.55));
  final koLp = _LowPass();
  _writeWav(_clash, 'ko.wav', _effect(1.8, (t) => koLp.process(_noise(), 1500 * math.exp(-t * 2) + 80) * math.exp(-t * 2) * 1.6 + math.sin(2 * math.pi * (40 + 70 * math.exp(-t * 6)) * t) * math.exp(-t * 2), peak: 0.8));
  _writeWav(_clash, 'gong.wav', _effect(2.0, (t) {
    var v = 0.0;
    for (final (f, k) in [(110.0, 1.0), (174.0, 0.6), (231.0, 0.5), (362.0, 0.3)]) {
      v += math.sin(2 * math.pi * f * t) * k;
    }
    return v * math.exp(-t * 1.6) * 0.4;
  }, peak: 0.6));
}

void _depthsPanelLike(Canvas c) {
  const r = Rect.fromLTWH(24, 24, 792, 472);
  final rr = RRect.fromRectAndRadius(r, const Radius.circular(36));
  c.drawRRect(rr, _glow(const Color(0x66F97316), 18));
  c.drawRRect(rr, _linear(r, const [Color(0xF01F1308), Color(0xF00F0904)]));
  c.drawRRect(rr, _stroke(const Color(0xFFF59E0B), 2.5));
}

void _clashStage(Canvas c) {
  const r = Rect.fromLTWH(0, 0, 960, 540);
  c.drawRect(r, _linear(r, const [Color(0xFF2E1065), Color(0xFFBE185D), Color(0xFFF97316), Color(0xFFFDBA74)], stops: const [0, 0.35, 0.6, 0.7]));
  _softDot(c, const Offset(700, 300), 130, const Color(0xCCFEF3C7), core: 0.35);
  // Mountains
  final rng = math.Random(5);
  for (final (y, color) in [(300.0, const Color(0xFF7C2D12)), (340.0, const Color(0xFF431407))]) {
    final p = Path()..moveTo(0, 540);
    for (var x = 0.0; x <= 960; x += 60) {
      p.lineTo(x, y - rng.nextDouble() * 90);
    }
    p
      ..lineTo(960, 540)
      ..close();
    c.drawPath(p, _fill(color));
  }
  // Temple gates and lanterns
  for (final x in [140.0, 820.0]) {
    c.drawRect(Rect.fromLTWH(x - 46, 210, 14, 230), _fill(const Color(0xFF450A0A)));
    c.drawRect(Rect.fromLTWH(x + 32, 210, 14, 230), _fill(const Color(0xFF450A0A)));
    c.drawRect(Rect.fromLTWH(x - 70, 196, 140, 16), _fill(const Color(0xFF7F1D1D)));
    c.drawRect(Rect.fromLTWH(x - 60, 230, 120, 10), _fill(const Color(0xFF7F1D1D)));
    _softDot(c, Offset(x, 270), 28, const Color(0xCCFDBA74));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, 270), width: 22, height: 30), const Radius.circular(8)), _fill(const Color(0xFFFB923C)));
  }
  // The stone floor with perspective lines
  const floorTop = 430.0;
  c.drawRect(const Rect.fromLTWH(0, floorTop, 960, 110), _linear(const Rect.fromLTWH(0, floorTop, 960, 110), const [Color(0xFF57534E), Color(0xFF292524)]));
  for (var k = -8; k <= 8; k++) {
    c.drawLine(Offset(480 + k * 60.0, floorTop), Offset(480 + k * 130.0, 540), _stroke(const Color(0x33000000), 2));
  }
  for (final y in [452.0, 482.0, 518.0]) {
    c.drawLine(Offset(0, y), Offset(960, y), _stroke(const Color(0x33000000), 2));
  }
  c.drawLine(const Offset(0, floorTop), const Offset(960, floorTop), _stroke(const Color(0x88FDBA74), 2));
}

/// A driving fight theme in E minor, 140 bpm.
List<double> _clashTheme() {
  const bpm = 140.0;
  const beat = 60 / bpm;
  const bars = 16;
  final out = List<double>.filled((bars * 4 * beat * _rate).round(), 0);
  const chords = [[52, 55, 59], [48, 52, 55], [50, 54, 57], [47, 50, 54]]; // Em C D Bm
  final lead = List<double>.filled(out.length, 0);
  for (var bar = 0; bar < bars; bar++) {
    final chord = chords[bar % 4];
    final t0 = bar * 4 * beat;
    for (var k = 0; k < 8; k++) {
      _synthNote(out, t0 + k * beat / 2, beat / 2 - 0.02, _hz(chord[0] - 24 + (k % 2 == 1 ? 12 : 0)), voices: 2, detune: 0.006, bright: 1200, dark: 250, gain: 0.26, a: 0.002, d: 0.1, s: 0.5, r: 0.03);
    }
    for (final n in chord) {
      _synthNote(out, t0, 4 * beat, _hz(n), voices: 3, detune: 0.012, bright: 2000, dark: 800, gain: 0.04, a: 0.05, d: 0.3, s: 0.7, r: 0.2);
    }
    if (bar >= 4) {
      final riff = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[1] + 12, chord[0] + 24, chord[2] + 12, chord[1] + 12, chord[0] + 12];
      for (var k = 0; k < 8; k++) {
        _synthNote(lead, t0 + k * beat / 2, beat / 2, _hz(riff[k]), voices: 2, detune: 0.008, bright: 4000, dark: 900, gain: 0.07, a: 0.002, d: 0.12, s: 0.3, r: 0.05);
      }
    }
    for (var k = 0; k < 4; k++) {
      _kick(out, t0 + k * beat, gain: 0.8);
      if (k == 1 || k == 3) _snare(out, t0 + k * beat, gain: 0.4);
      _hat(out, t0 + k * beat + beat / 2, gain: 0.1);
      _hat(out, t0 + k * beat + beat / 4, gain: 0.05, decay: 90);
    }
  }
  _delay(lead, beat * 0.5, 0.3, 0.4);
  for (var i = 0; i < out.length; i++) {
    out[i] += lead[i];
  }
  return _master(out);
}

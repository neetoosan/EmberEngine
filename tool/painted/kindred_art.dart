part of 'paint_art_test.dart';

// Ember Kindred: a co-op arena for 1 to 4 players. Four lantern spirits
// (ember, tide, bloom and sun), the shadow things that hunt them, the Hollow,
// and a moonlit grove with glowing mushrooms and fireflies.

const _kindred = 'kindred';

/// Each spirit's light: body, deep shade, halo.
const _spiritColors = [
  (Color(0xFFFDBA74), Color(0xFFEA580C), Color(0xFFF97316)), // Sol
  (Color(0xFF7DD3FC), Color(0xFF0369A1), Color(0xFF38BDF8)), // Lume
  (Color(0xFFE9D5FF), Color(0xFF7E22CE), Color(0xFFC084FC)), // Iris
  (Color(0xFFFEF08A), Color(0xFFCA8A04), Color(0xFFFACC15)), // Wren
];

/// A lantern spirit: a glowing drop with a flame crest, big eyes and a
/// little leaf cloak. [pose] 0 idle, 1 moving (squashed, leaning), 2 down.
void _spirit(Canvas c, int who, int pose, {double size = 96}) {
  final (body, shade, halo) = _spiritColors[who];
  c.save();
  c.scale(size / 96);
  const centre = Offset(48, 54);
  if (pose == 2) {
    // Down: dim, lying low, eyes shut, the flame a small ember
    final grey = Color.lerp(body, const Color(0xFF64748B), 0.55)!;
    c.drawOval(const Rect.fromLTWH(18, 70, 60, 14), _glow(const Color(0x66000000), 4));
    _softDot(c, const Offset(48, 64), 34, halo.withValues(alpha: 0.25));
    c.drawOval(Rect.fromCenter(center: const Offset(48, 64), width: 54, height: 30),
        _radial(const Offset(40, 58), 34, [Color.lerp(grey, const Color(0xFFFFFFFF), 0.3)!, Color.lerp(shade, const Color(0xFF1E293B), 0.5)!]));
    for (final dx in [-10.0, 10.0]) {
      c.drawArc(Rect.fromCenter(center: Offset(48 + dx, 62), width: 9, height: 6), 0, math.pi, false, _stroke(const Color(0xFF1E293B), 2.2));
    }
    _softDot(c, const Offset(48, 46), 9, halo.withValues(alpha: 0.7), core: 0.3);
    c.restore();
    return;
  }
  final squash = pose == 1 ? 0.9 : 1.0;
  final lean = pose == 1 ? 0.12 : 0.0;
  c.drawOval(const Rect.fromLTWH(26, 80, 44, 10), _glow(const Color(0x55000000), 4));
  _softDot(c, centre, 46, halo.withValues(alpha: 0.45), core: 0.2);
  c.save();
  c.translate(centre.dx, centre.dy + 22);
  c.rotate(lean);
  c.scale(1 / squash, squash);
  c.translate(-centre.dx, -centre.dy - 22);
  // Flame crest (three licks)
  for (final (dx, h, w) in [(-9.0, 26.0, 12.0), (9.0, 24.0, 12.0), (0.0, 36.0, 16.0)]) {
    final base = Offset(48 + dx, 36);
    final tip = Offset(48 + dx * 1.4 + (pose == 1 ? -8 : 0), 36 - h);
    final p = Path()
      ..moveTo(base.dx - w / 2, base.dy)
      ..quadraticBezierTo(base.dx - w / 2, tip.dy + h * 0.4, tip.dx, tip.dy)
      ..quadraticBezierTo(base.dx + w / 2, tip.dy + h * 0.4, base.dx + w / 2, base.dy)
      ..close();
    c.drawPath(p, _glow(halo.withValues(alpha: 0.8), 3));
    c.drawPath(p, _linear(Rect.fromPoints(tip, base).inflate(w), [const Color(0xFFFFFFFF), body, halo], stops: const [0, 0.45, 1]));
  }
  // The drop-shaped body
  final drop = Path()
    ..moveTo(48, 22)
    ..cubicTo(64, 30, 76, 46, 74, 62)
    ..cubicTo(72, 78, 60, 84, 48, 84)
    ..cubicTo(36, 84, 24, 78, 22, 62)
    ..cubicTo(20, 46, 32, 30, 48, 22)
    ..close();
  c.drawPath(drop, _radial(const Offset(40, 46), 46, [const Color(0xFFFFFFFF), body, shade], stops: const [0, 0.45, 1]));
  // Leaf cloak around the bottom
  final leaf = Path()
    ..moveTo(23, 66)
    ..quadraticBezierTo(30, 86, 48, 86)
    ..quadraticBezierTo(66, 86, 73, 66)
    ..quadraticBezierTo(60, 76, 48, 74)
    ..quadraticBezierTo(36, 76, 23, 66)
    ..close();
  c.drawPath(leaf, _linear(const Rect.fromLTWH(22, 64, 52, 24), [Color.lerp(shade, const Color(0xFF14532D), 0.5)!, Color.lerp(shade, const Color(0xFF052E16), 0.7)!]));
  c.drawPath(drop, _stroke(const Color(0x66FFFFFF), 1.5));
  // Eyes with highlights
  for (final dx in [-10.0, 10.0]) {
    final e = Offset(48 + dx + (pose == 1 ? 3 : 0), 56);
    c.drawOval(Rect.fromCenter(center: e, width: 9, height: 13), _fill(const Color(0xFF1E1B4B)));
    c.drawCircle(e + const Offset(-1.5, -3), 2.2, _fill(const Color(0xFFFFFFFF)));
  }
  c.drawOval(Rect.fromCenter(center: const Offset(36, 66), width: 8, height: 4), _fill(const Color(0x55F472B6)));
  c.drawOval(Rect.fromCenter(center: const Offset(60, 66), width: 8, height: 4), _fill(const Color(0x55F472B6)));
  c.restore();
  c.restore();
}

/// Shadow things: 0 wisp, 1 brute, 2 spitter.
void _foe(Canvas c, int kind) {
  const violet = Color(0xFFA855F7), magenta = Color(0xFFEC4899);
  if (kind == 0) {
    // A wisp of smoke with a hungry glow
    _softDot(c, const Offset(48, 48), 40, const Color(0x557C3AED));
    final rng = math.Random(3);
    for (var k = 0; k < 6; k++) {
      final a = k * math.pi / 3 + 0.3;
      final tail = Path()
        ..moveTo(48, 48)
        ..quadraticBezierTo(48 + math.cos(a) * 30 + rng.nextDouble() * 8, 48 + math.sin(a) * 30, 48 + math.cos(a + 0.5) * 40, 48 + math.sin(a + 0.5) * 40);
      c.drawPath(tail, _stroke(const Color(0xCC2E1065), 9, blur: 2));
    }
    c.drawCircle(const Offset(48, 48), 22, _radial(const Offset(44, 42), 26, [const Color(0xFF4C1D95), const Color(0xFF1E0B3B)]));
    for (final dx in [-8.0, 8.0]) {
      _softDot(c, Offset(48 + dx, 46), 7, magenta);
      c.drawOval(Rect.fromCenter(center: Offset(48 + dx, 46), width: 6, height: 4), _fill(const Color(0xFFFFE4F1)));
    }
  } else if (kind == 1) {
    // A brute: a hunched beast of dark stone, cracks glowing violet
    c.drawOval(const Rect.fromLTWH(14, 76, 68, 14), _glow(const Color(0x77000000), 5));
    final body = Path()
      ..moveTo(14, 78)
      ..cubicTo(8, 46, 26, 16, 50, 16)
      ..cubicTo(74, 16, 90, 44, 84, 78)
      ..close();
    c.drawPath(body, _radial(const Offset(40, 34), 70, [const Color(0xFF475569), const Color(0xFF1E1B2E), const Color(0xFF0F0A1A)], stops: const [0, 0.6, 1]));
    for (final (a, b) in [(const Offset(30, 30), const Offset(40, 52)), (const Offset(62, 26), const Offset(56, 50)), (const Offset(46, 60), const Offset(58, 74))]) {
      c.drawLine(a, b, _stroke(violet, 3, blur: 1.5));
      c.drawLine(a, b, _stroke(const Color(0xFFF3E8FF), 1));
    }
    // Horns
    for (final s in [-1.0, 1.0]) {
      c.drawPath(_poly([Offset(48 + s * 18, 24), Offset(48 + s * 34, 4), Offset(48 + s * 26, 28)]), _fill(const Color(0xFF334155)));
    }
    for (final dx in [-12.0, 12.0]) {
      _softDot(c, Offset(48 + dx, 40), 9, violet);
      c.drawCircle(Offset(48 + dx, 40), 3.5, _fill(const Color(0xFFFAF5FF)));
    }
  } else {
    // A spitter: a thorny bulb that opens to spit shadow
    c.drawOval(const Rect.fromLTWH(22, 78, 52, 10), _glow(const Color(0x66000000), 4));
    for (var k = 0; k < 5; k++) {
      final a = -math.pi / 2 + (k - 2) * 0.55;
      c.drawPath(_poly([Offset(48 + math.cos(a) * 22, 52 + math.sin(a) * 22), Offset(48 + math.cos(a) * 44, 52 + math.sin(a) * 44), Offset(48 + math.cos(a + 0.2) * 22, 52 + math.sin(a + 0.2) * 22)]),
          _fill(const Color(0xFF3B0764)));
    }
    c.drawCircle(const Offset(48, 54), 26, _radial(const Offset(40, 44), 34, [const Color(0xFF86198F), const Color(0xFF3B0764)]));
    _softDot(c, const Offset(48, 58), 16, magenta);
    c.drawOval(Rect.fromCenter(center: const Offset(48, 58), width: 18, height: 12), _fill(const Color(0xFF1E0B2E)));
    c.drawOval(Rect.fromCenter(center: const Offset(48, 58), width: 8, height: 5), _fill(const Color(0xFFFBCFE8)));
    for (final dx in [-11.0, 11.0]) {
      c.drawCircle(Offset(48 + dx, 42), 3, _fill(const Color(0xFFFDF4FF)));
    }
    // Leaves at the base
    for (final s in [-1.0, 1.0]) {
      final leaf = Path()
        ..moveTo(48, 78)
        ..quadraticBezierTo(48 + s * 30, 84, 48 + s * 38, 70)
        ..quadraticBezierTo(48 + s * 20, 70, 48, 78);
      c.drawPath(leaf, _fill(const Color(0xFF14532D)));
    }
  }
}

/// The Hollow: a great mask of shadow wood with a thorn crown and two moon eyes.
void _hollow(Canvas c) {
  const s = 256.0;
  _softDot(c, const Offset(s / 2, s / 2), 128, const Color(0x667C3AED), core: 0.3);
  // Thorn crown
  for (var k = 0; k < 9; k++) {
    final a = -math.pi + k * math.pi / 8;
    final base = Offset(128 + math.cos(a) * 70, 120 + math.sin(a) * 66);
    final tip = Offset(128 + math.cos(a) * 120, 120 + math.sin(a) * 112);
    c.drawPath(_poly([base + Offset(math.sin(a) * 12, -math.cos(a) * 12), tip, base - Offset(math.sin(a) * 12, -math.cos(a) * 12)]),
        _linear(Rect.fromPoints(base, tip).inflate(12), const [Color(0xFF2E1065), Color(0xFF0B0418)]));
  }
  // The mask
  final mask = Path()
    ..moveTo(128, 40)
    ..cubicTo(196, 44, 214, 120, 196, 168)
    ..cubicTo(180, 214, 150, 236, 128, 236)
    ..cubicTo(106, 236, 76, 214, 60, 168)
    ..cubicTo(42, 120, 60, 44, 128, 40)
    ..close();
  c.drawPath(mask, _glow(const Color(0xAAA855F7), 10));
  c.drawPath(mask, _radial(const Offset(112, 96), 160, [const Color(0xFF3F3F5A), const Color(0xFF1C1530), const Color(0xFF09060F)], stops: const [0, 0.55, 1]));
  // Grain and cracks that glow
  for (var k = 0; k < 6; k++) {
    final x = 84.0 + k * 18;
    c.drawLine(Offset(x, 60 + (k % 2) * 10), Offset(x + (k - 2.5) * 4, 214 - (k % 3) * 14), _stroke(const Color(0x33000000), 3));
  }
  c.drawLine(const Offset(128, 44), const Offset(118, 96), _stroke(const Color(0xFFD946EF), 3, blur: 2));
  c.drawLine(const Offset(118, 96), const Offset(132, 128), _stroke(const Color(0xFFD946EF), 2.5, blur: 2));
  // Eyes and mouth
  for (final dx in [-34.0, 34.0]) {
    final e = Offset(128 + dx, 128);
    c.drawOval(Rect.fromCenter(center: e, width: 46, height: 30), _fill(const Color(0xFF05020A)));
    _softDot(c, e, 26, const Color(0xFFF0ABFC), core: 0.3);
    c.drawOval(Rect.fromCenter(center: e, width: 16, height: 10), _fill(const Color(0xFFFFFFFF)));
  }
  final mouth = Path()
    ..moveTo(98, 186)
    ..quadraticBezierTo(128, 170, 158, 186)
    ..quadraticBezierTo(128, 206, 98, 186)
    ..close();
  c.drawPath(mouth, _fill(const Color(0xFF05020A)));
  for (var k = 0; k < 5; k++) {
    c.drawPath(_poly([Offset(104 + k * 12.0, 182), Offset(110 + k * 12.0, 194), Offset(116 + k * 12.0, 182)]), _fill(const Color(0xFFE9D5FF)));
  }
}

/// The grove at night, 1600 × 1000.
void _grove(Canvas c) {
  const w = 1600.0, h = 1000.0;
  const r = Rect.fromLTWH(0, 0, w, h);
  c.drawRect(r, _radial(const Offset(800, 500), 950, const [Color(0xFF1F4D45), Color(0xFF12302F), Color(0xFF0A1A1F)], stops: const [0, 0.55, 1]));
  final rng = math.Random(11);
  // Soft patches of moss and moonlight
  for (var k = 0; k < 70; k++) {
    final p = Offset(rng.nextDouble() * w, rng.nextDouble() * h);
    final rad = 40 + rng.nextDouble() * 120;
    final col = rng.nextBool() ? const Color(0x2234D399) : const Color(0x1A0EA5E9);
    c.drawCircle(p, rad, _radial(p, rad, [col, col.withValues(alpha: 0)]));
  }
  // Grass blades
  for (var k = 0; k < 2600; k++) {
    final p = Offset(rng.nextDouble() * w, rng.nextDouble() * h);
    final len = 5 + rng.nextDouble() * 9;
    final lean = (rng.nextDouble() - 0.5) * 6;
    c.drawLine(p, p + Offset(lean, -len), _stroke(Color.lerp(const Color(0xFF1E5B47), const Color(0xFF3F8F6A), rng.nextDouble())!.withValues(alpha: 0.55), 1.6));
  }
  // The stone circle in the middle, a path ring and the shrine stones
  const mid = Offset(800, 500);
  c.drawCircle(mid, 210, _radial(mid, 210, const [Color(0x33A7F3D0), Color(0x00A7F3D0)]));
  c.drawCircle(mid, 170, _stroke(const Color(0x4494A3B8), 26));
  for (var k = 0; k < 28; k++) {
    final a = k * math.pi * 2 / 28;
    final p = mid + Offset(math.cos(a) * 170, math.sin(a) * 170);
    c.drawOval(Rect.fromCenter(center: p, width: 30 + rng.nextDouble() * 8, height: 18 + rng.nextDouble() * 6), _fill(const Color(0xFF3B4A55)));
    c.drawOval(Rect.fromCenter(center: p - const Offset(2, 3), width: 22, height: 9), _fill(const Color(0x3394A3B8)));
  }
  for (var k = 0; k < 6; k++) {
    final a = k * math.pi / 3 + 0.5;
    final p = mid + Offset(math.cos(a) * 250, math.sin(a) * 210);
    c.drawOval(Rect.fromCenter(center: p + const Offset(0, 22), width: 46, height: 14), _glow(const Color(0x66000000), 4));
    final stone = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 34, height: 54), const Radius.circular(14));
    c.drawRRect(stone, _linear(stone.outerRect, const [Color(0xFF64748B), Color(0xFF1E293B)]));
    c.drawLine(p + const Offset(-6, -12), p + const Offset(6, 4), _stroke(const Color(0xFF5EEAD4), 2.5, blur: 1.5));
    _softDot(c, p, 34, const Color(0x335EEAD4));
  }
  // Glowing mushrooms and flowers
  for (var k = 0; k < 90; k++) {
    final p = Offset(rng.nextDouble() * w, rng.nextDouble() * h);
    if ((p - mid).distance < 230) continue;
    if (rng.nextDouble() < 0.5) {
      final col = [const Color(0xFF22D3EE), const Color(0xFFA78BFA), const Color(0xFF34D399)][rng.nextInt(3)];
      for (var m = 0; m < 1 + rng.nextInt(3); m++) {
        final q = p + Offset(m * 9.0 - 6, m * 3.0);
        final cap = 6 + rng.nextDouble() * 5;
        c.drawLine(q, q + const Offset(0, 10), _stroke(const Color(0xFFE2E8F0), 2.5));
        _softDot(c, q, cap * 2.6, col.withValues(alpha: 0.35));
        c.drawArc(Rect.fromCenter(center: q, width: cap * 2, height: cap * 1.4), math.pi, math.pi, true, _fill(col));
      }
    } else {
      final col = [const Color(0xFFF9A8D4), const Color(0xFFFDE68A), const Color(0xFFBFDBFE)][rng.nextInt(3)];
      for (var petal = 0; petal < 5; petal++) {
        final a = petal * math.pi * 2 / 5;
        c.drawCircle(p + Offset(math.cos(a) * 3.5, math.sin(a) * 3.5), 2.8, _fill(col.withValues(alpha: 0.85)));
      }
      c.drawCircle(p, 1.8, _fill(const Color(0xFFFFFBEB)));
    }
  }
  // Ferns
  for (var k = 0; k < 60; k++) {
    final p = Offset(rng.nextDouble() * w, rng.nextDouble() * h);
    if ((p - mid).distance < 240) continue;
    for (var f = 0; f < 5; f++) {
      final a = -math.pi / 2 + (f - 2) * 0.45;
      final tip = p + Offset(math.cos(a), math.sin(a)) * (22 + rng.nextDouble() * 10);
      c.drawLine(p, tip, _stroke(const Color(0xAA166534), 4));
      c.drawLine(p, tip, _stroke(const Color(0x664ADE80), 1.2));
    }
  }
  // Trees crowding the edges (dark canopies with a moonlit rim)
  void tree(Offset p, double rad) {
    c.drawCircle(p + const Offset(10, 18), rad, _glow(const Color(0x88000000), 18));
    c.drawCircle(p, rad, _radial(p - Offset(rad * 0.3, rad * 0.4), rad * 1.3, const [Color(0xFF1F5145), Color(0xFF0C2622), Color(0xFF061412)], stops: const [0, 0.6, 1]));
    for (var l = 0; l < 7; l++) {
      final a = rng.nextDouble() * math.pi * 2;
      final q = p + Offset(math.cos(a), math.sin(a)) * rad * 0.55;
      c.drawCircle(q, rad * 0.4, _fill(const Color(0x22000000)));
      c.drawCircle(q - Offset(rad * 0.08, rad * 0.1), rad * 0.3, _fill(const Color(0x1A86EFAC)));
    }
  }

  for (var x = -40.0; x < w + 80; x += 120 + rng.nextDouble() * 60) {
    tree(Offset(x, -30 + rng.nextDouble() * 40), 90 + rng.nextDouble() * 40);
    tree(Offset(x + 50, h + 20 - rng.nextDouble() * 40), 90 + rng.nextDouble() * 40);
  }
  for (var y = 80.0; y < h - 60; y += 120 + rng.nextDouble() * 60) {
    tree(Offset(-30 + rng.nextDouble() * 40, y), 90 + rng.nextDouble() * 40);
    tree(Offset(w + 30 - rng.nextDouble() * 40, y + 40), 90 + rng.nextDouble() * 40);
  }
  // Fireflies
  for (var k = 0; k < 140; k++) {
    final p = Offset(rng.nextDouble() * w, rng.nextDouble() * h);
    _softDot(c, p, 5 + rng.nextDouble() * 6, const Color(0xCCFEF08A), core: 0.3);
  }
}

Future<void> _paintKindred() async {
  await _sheet(_kindred, 'spirits.png', 96, 96, 12, (c, i) => _spirit(c, i ~/ 3, i % 3), columns: 3);
  await _sheet(_kindred, 'faces.png', 64, 64, 4, (c, i) {
    c.scale(64 / 96);
    _spirit(c, i, 0);
  });
  await _sheet(_kindred, 'foes.png', 96, 96, 3, _foe);
  await _png(_kindred, 'hollow.png', 256, 256, _hollow);
  await _png(_kindred, 'grove.png', 1600, 1000, _grove);
  await _sheet(_kindred, 'shots.png', 48, 48, 5, (c, i) {
    final color = i < 4 ? _spiritColors[i].$3 : const Color(0xFFE879F9);
    _softDot(c, const Offset(24, 24), 23, color, core: 0.2);
    c.drawCircle(const Offset(24, 24), i < 4 ? 6 : 8, _radial(const Offset(22, 22), 9, [const Color(0xFFFFFFFF), i < 4 ? _spiritColors[i].$1 : const Color(0xFFF5D0FE)]));
    if (i == 4) c.drawCircle(const Offset(24, 24), 9, _stroke(const Color(0xFF581C87), 2));
  });
  await _sheet(_kindred, 'motes.png', 48, 48, 2, (c, i) {
    if (i == 0) {
      _softDot(c, const Offset(24, 24), 22, const Color(0xCCFDE68A), core: 0.15);
      c.drawPath(_poly(const [Offset(24, 10), Offset(28, 20), Offset(38, 24), Offset(28, 28), Offset(24, 38), Offset(20, 28), Offset(10, 24), Offset(20, 20)]),
          _fill(const Color(0xFFFFFBEB)));
    } else {
      _softDot(c, const Offset(24, 24), 22, const Color(0x99F472B6), core: 0.2);
      for (var p = 0; p < 6; p++) {
        final a = p * math.pi / 3;
        c.drawOval(Rect.fromCenter(center: Offset(24 + math.cos(a) * 7, 24 + math.sin(a) * 7), width: 10, height: 10), _fill(const Color(0xFFF9A8D4)));
      }
      c.drawCircle(const Offset(24, 24), 5, _fill(const Color(0xFFFEF3C7)));
    }
  });
  await _png(_kindred, 'ring.png', 128, 128, (c) {
    c.drawCircle(const Offset(64, 64), 50, _stroke(const Color(0xAAFFFFFF), 8, blur: 6));
    c.drawCircle(const Offset(64, 64), 50, _stroke(const Color(0xFFFFFFFF), 3));
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4;
      _softDot(c, Offset(64 + math.cos(a) * 50, 64 + math.sin(a) * 50), 8, const Color(0xFFFFFFFF));
    }
  });
  await _png(_kindred, 'panel.png', 840, 520, (c) {
    const r = Rect.fromLTWH(24, 24, 792, 472);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(36));
    c.drawRRect(rr, _glow(const Color(0x665EEAD4), 18));
    c.drawRRect(rr, _linear(r, const [Color(0xF0102A2A), Color(0xF0071415)]));
    c.drawRRect(rr, _stroke(const Color(0xFF5EEAD4), 2.5));
  });

  _writeWav(_kindred, 'kindred.wav', _kindredTheme());
  _writeWav(_kindred, 'shoot.wav', _effect(0.14, (t) => math.sin(2 * math.pi * (900 - t * 2400) * t) * math.exp(-t * 30) * 0.6, peak: 0.3));
  final popLp = _LowPass();
  _writeWav(_kindred, 'hit.wav', _effect(0.16, (t) => popLp.process(_noise(), 2400) * math.exp(-t * 30) + math.sin(2 * math.pi * (300 + 300 * math.exp(-t * 40)) * t) * math.exp(-t * 26) * 0.7, peak: 0.45));
  final hurtLp = _LowPass();
  _writeWav(_kindred, 'hurt.wav', _effect(0.3, (t) => hurtLp.process(_noise(), 900) * math.exp(-t * 12) + math.sin(2 * math.pi * (180 - t * 300) * t) * math.exp(-t * 10) * 0.6, peak: 0.6));
  _writeWav(_kindred, 'down.wav', _effect(0.9, (t) {
    var v = 0.0;
    for (final (k, f) in [(0, 660.0), (1, 523.0), (2, 392.0)]) {
      final s = t - k * 0.18;
      if (s > 0) v += math.sin(2 * math.pi * f * s) * math.exp(-s * 5);
    }
    return v * 0.4;
  }, peak: 0.55));
  _writeWav(_kindred, 'revive.wav', _effect(1.0, (t) {
    var v = 0.0;
    for (final (k, f) in [(0, 523.0), (1, 659.0), (2, 784.0), (3, 1047.0)]) {
      final s = t - k * 0.09;
      if (s > 0) v += (math.sin(2 * math.pi * f * s) + 0.3 * math.sin(4 * math.pi * f * s)) * math.exp(-s * 4);
    }
    return v * 0.3;
  }, peak: 0.6));
  _writeWav(_kindred, 'join.wav', _effect(0.7, (t) {
    var v = 0.0;
    for (final (k, f) in [(0, 587.0), (1, 740.0), (2, 880.0)]) {
      final s = t - k * 0.06;
      if (s > 0) v += math.sin(2 * math.pi * f * s) * math.exp(-s * 5);
    }
    return v * 0.35;
  }, peak: 0.55));
  _writeWav(_kindred, 'wave.wav', _effect(1.6, (t) {
    var v = 0.0;
    for (final (f, k) in [(147.0, 1.0), (220.0, 0.6), (294.0, 0.5), (440.0, 0.25)]) {
      v += math.sin(2 * math.pi * f * t) * k;
    }
    final swell = t < 0.3 ? t / 0.3 : math.exp(-(t - 0.3) * 2.2);
    return v * swell * 0.35;
  }, peak: 0.6));
  _writeWav(_kindred, 'dash.wav', _effect(0.22, (t) {
    final e = 1 - t / 0.22;
    return _noise() * e * e * 0.5;
  }, peak: 0.3));
  final roarLp = _LowPass();
  _writeWav(_kindred, 'roar.wav', _effect(1.6, (t) => roarLp.process(_noise(), 400 + 300 * math.sin(t * 9)) * math.exp(-t * 1.2) * 1.8 + math.sin(2 * math.pi * (55 + 10 * math.sin(t * 20)) * t) * math.exp(-t * 1.4) * 0.8, peak: 0.8));
  _writeWav(_kindred, 'win.wav', _effect(2.2, (t) {
    var v = 0.0;
    for (final (k, f) in [(0, 587.0), (1, 740.0), (2, 880.0), (3, 1175.0)]) {
      final s = t - k * 0.14;
      if (s > 0) v += math.sin(2 * math.pi * f * s) * math.exp(-s * 1.8);
    }
    return v * 0.3;
  }, peak: 0.6));
  _writeWav(_kindred, 'lose.wav', _effect(1.8, (t) {
    var v = 0.0;
    for (final (k, f) in [(0, 440.0), (1, 349.0), (2, 294.0)]) {
      final s = t - k * 0.3;
      if (s > 0) v += math.sin(2 * math.pi * f * s) * math.exp(-s * 2);
    }
    return v * 0.35;
  }, peak: 0.55));
}

/// A warm, hopeful loop in D major, 112 bpm: soft pads, a plucked arpeggio,
/// a bell lead that comes in later, light drums.
List<double> _kindredTheme() {
  const bpm = 112.0;
  const beat = 60 / bpm;
  const bars = 16;
  final out = List<double>.filled((bars * 4 * beat * _rate).round(), 0);
  final echo = List<double>.filled(out.length, 0);
  const chords = [[50, 54, 57], [47, 50, 54], [43, 47, 50], [45, 49, 52]]; // D Bm G A
  const melody = [74, 73, 71, 69, 71, 73, 74, 76, 78, 76, 74, 73, 71, 73, 69, -1];
  for (var bar = 0; bar < bars; bar++) {
    final chord = chords[bar % 4];
    final t0 = bar * 4 * beat;
    // Pad
    for (final n in chord) {
      _synthNote(out, t0, 4 * beat, _hz(n + 12), voices: 3, detune: 0.01, bright: 1600, dark: 700, gain: 0.035, a: 0.4, d: 0.5, s: 0.8, r: 0.6);
    }
    // Bass on the beat
    for (var k = 0; k < 4; k++) {
      _synthNote(out, t0 + k * beat, beat * 0.9, _hz(chord[0] - 12), voices: 1, bright: 700, dark: 220, gain: 0.2, a: 0.004, d: 0.2, s: 0.5, r: 0.05);
    }
    // Plucked arpeggio in eighths, into the echo
    final arp = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[1] + 24, chord[2] + 12, chord[1] + 12, chord[0] + 24, chord[2] + 12];
    for (var k = 0; k < 8; k++) {
      _synthNote(echo, t0 + k * beat / 2, beat / 3, _hz(arp[k]), voices: 2, detune: 0.005, bright: 3800, dark: 700, gain: 0.05, a: 0.002, d: 0.12, s: 0.2, r: 0.1);
    }
    // A bell lead from bar 8
    if (bar >= 8) {
      for (var k = 0; k < 2; k++) {
        final n = melody[((bar - 8) * 2 + k) % melody.length];
        if (n < 0) continue;
        _mix(echo, t0 + k * 2 * beat, 2 * beat, (t) {
          final f = _hz(n);
          return (math.sin(2 * math.pi * f * t) + 0.35 * math.sin(2 * math.pi * f * 2.01 * t) * math.exp(-t * 6)) * math.exp(-t * 2.2);
        }, gain: 0.07);
      }
    }
    // Drums: from bar 4
    if (bar >= 4) {
      for (var k = 0; k < 4; k++) {
        if (k == 0 || k == 2) _kick(out, t0 + k * beat, gain: 0.55);
        if (k == 1 || k == 3) _snare(out, t0 + k * beat, gain: 0.22);
        _hat(out, t0 + k * beat + beat / 2, gain: 0.06);
      }
    }
  }
  _delay(echo, beat * 0.75, 0.35, 0.5);
  for (var i = 0; i < out.length; i++) {
    out[i] += echo[i];
  }
  return _master(out);
}

part of 'paint_art_test.dart';

// Ember Spire: a metroidvania in glowing crystal caverns. Side-view rock in
// 16 auto-tiled pieces (moss on top, lit edges, roots below), ledges, crystal
// spikes, a hero with a sword, crawlers, moths, the Thornback, ability orbs,
// and two parallax cavern layers.

const _spire = 'spire';

Future<void> _paintSpire() async {
  // Tileset: 64 px cells (shown at 32), 8 columns. id 1 rock, 6 ledge, 7 spikes, 10-25 rock pieces.
  await _sheet(_spire, 'tiles.png', 64, 64, 32, (c, i) {
    final id = i + 1;
    if (id == 1) _spireRock(c, 15);
    if (id == 6) _spireLedge(c);
    if (id == 7) _spireSpikes(c);
    if (id >= 10 && id <= 25) _spireRock(c, id - 10);
  }, columns: 8);
  await _sheet(_spire, 'hero.png', 96, 96, 4, _spireHero);
  await _png(_spire, 'slash.png', 128, 96, _spireSlash);
  await _sheet(_spire, 'enemies.png', 96, 96, 2, _spireEnemy);
  await _png(_spire, 'boss.png', 192, 160, _spireBoss);
  await _sheet(_spire, 'objects.png', 96, 96, 7, _spireObject);
  await _sheet(_spire, 'icons.png', 64, 64, 3, (c, i) {
    if (i == 0) _bastionIcon(c, 1);
    if (i == 1) _depthsIcon(c, 2);
    if (i == 2) _spireGem(c, const Offset(32, 32), 18);
  });
  await _png(_spire, 'bg_far.png', 960, 544, _spireFar);
  await _png(_spire, 'bg_mid.png', 960, 544, _spireMid);
  await _png(_spire, 'panel.png', 840, 520, (c) {
    const r = Rect.fromLTWH(24, 24, 792, 472);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(36));
    c.drawRRect(rr, _glow(const Color(0x6622D3EE), 18));
    c.drawRRect(rr, _linear(r, const [Color(0xF0142033), Color(0xF00A111E)]));
    c.drawRRect(rr.deflate(1), _stroke(const Color(0x22FFFFFF), 1));
    c.drawRRect(rr, _stroke(const Color(0xFF2DD4BF), 2.5));
  });

  _writeWav(_spire, 'spire.wav', _spireTheme());
  _writeWav(_spire, 'slash.wav', _effect(0.2, (t) {
    final lp = 1 - t / 0.2;
    return _noise() * lp * lp * 0.5 + math.sin(2 * math.pi * (900 - 2500 * t) * t) * lp * 0.2;
  }, peak: 0.4));
  final hitLp = _LowPass();
  _writeWav(_spire, 'hit.wav', _effect(0.22, (t) => hitLp.process(_noise(), 3000) * math.exp(-t * 22) + math.sin(2 * math.pi * 140 * t) * math.exp(-t * 26), peak: 0.5));
  _writeWav(_spire, 'hurt.wav', _effect(0.45, (t) => (((260 * math.exp(-t * 3) * t) % 1) * 2 - 1) * math.exp(-t * 7) * 0.6, peak: 0.6));
  _writeWav(_spire, 'jump.wav', _effect(0.15, (t) => math.sin(2 * math.pi * (300 + 900 * t) * t) * math.exp(-t * 20) * 0.5, peak: 0.3));
  _writeWav(_spire, 'airjump.wav', _effect(0.3, (t) {
    final lp = 1 - t / 0.3;
    return (_noise() * 0.4 + math.sin(2 * math.pi * (500 + 1400 * t) * t) * 0.5) * lp * lp;
  }, peak: 0.35));
  _writeWav(_spire, 'dash.wav', _effect(0.3, (t) {
    final lp = 1 - t / 0.3;
    return _noise() * lp * 0.6;
  }, peak: 0.4));
  _writeWav(_spire, 'power.wav', _effect(1.6, (t) {
    var v = 0.0;
    for (final (n, at) in [(62, 0.0), (66, 0.12), (69, 0.24), (74, 0.36), (78, 0.5)]) {
      if (t > at) v += (math.sin(2 * math.pi * _hz(n) * t) + 0.3 * math.sin(4 * math.pi * _hz(n) * t)) * math.exp(-(t - at) * 3);
    }
    return v * 0.3;
  }, peak: 0.6));
  _writeWav(_spire, 'save.wav', _effect(1.2, (t) {
    var v = 0.0;
    for (final (f, k) in [(880.0, 1.0), (1320.0, 0.6), (1760.0, 0.4)]) {
      v += math.sin(2 * math.pi * f * t) * k * math.exp(-t * 3);
    }
    return v * 0.35;
  }, peak: 0.45));
  _writeWav(_spire, 'gem.wav', _effect(0.4, (t) => math.sin(2 * math.pi * (t < 0.07 ? 1760 : 2637) * t) * math.exp(-t * 9) * 0.5, peak: 0.35));
  final roarLp = _LowPass();
  _writeWav(_spire, 'roar.wav', _effect(1.3, (t) {
    final growl = ((90 + 30 * math.sin(t * 40)) * t % 1) * 2 - 1;
    return (growl * 0.5 + roarLp.process(_noise(), 700) * 0.8) * math.min(1, t * 8) * math.exp(-t * 2);
  }, peak: 0.65));
  final slamLp = _LowPass();
  _writeWav(_spire, 'slam.wav', _effect(0.7, (t) => slamLp.process(_noise(), 900 * math.exp(-t * 4) + 60) * math.exp(-t * 5) * 1.5 + math.sin(2 * math.pi * (45 + 60 * math.exp(-t * 18)) * t) * math.exp(-t * 6), peak: 0.7));
}

// --- Terrain -------------------------------------------------------------------

/// Rock seen from the side. [mask]: 1 rock above, 2 right, 4 below, 8 left.
void _spireRock(Canvas c, int mask) {
  const r = Rect.fromLTWH(0, 0, 64, 64);
  final up = mask & 1 != 0, right = mask & 2 != 0, down = mask & 4 != 0, left = mask & 8 != 0;
  c.drawRect(r, _linear(r, const [Color(0xFF332B4A), Color(0xFF241E36)]));
  final rng = math.Random(mask * 13 + 5);
  for (var k = 0; k < 6; k++) {
    final at = Offset(rng.nextDouble() * 64, rng.nextDouble() * 64);
    c.drawOval(Rect.fromCenter(center: at, width: 10 + rng.nextDouble() * 14, height: 7 + rng.nextDouble() * 8), _fill(const Color(0x22FFFFFF)));
    c.drawOval(Rect.fromCenter(center: at + const Offset(1, 2), width: 10, height: 5), _fill(const Color(0x22000000)));
  }
  if (!left) c.drawRect(const Rect.fromLTWH(0, 0, 5, 64), _linear(const Rect.fromLTWH(0, 0, 5, 64), const [Color(0xFF54487A), Color(0xFF3A3156)], begin: Alignment.centerLeft, end: Alignment.centerRight));
  if (!right) c.drawRect(const Rect.fromLTWH(59, 0, 5, 64), _fill(const Color(0xFF1A1528)));
  if (!down) {
    c.drawRect(const Rect.fromLTWH(0, 56, 64, 8), _fill(const Color(0xFF17121F)));
    for (var k = 0; k < 3; k++) {
      final x = 10.0 + k * 20 + rng.nextDouble() * 6;
      final len = 6 + rng.nextDouble() * 10;
      c.drawLine(Offset(x, 60), Offset(x + 2, 60 + len), _stroke(const Color(0xFF2E6B4F), 2));
    }
  }
  if (!up) {
    // Moss and grass on top, with a few glowing buds
    final moss = Path()
      ..moveTo(0, 14)
      ..quadraticBezierTo(16, 8, 32, 13)
      ..quadraticBezierTo(48, 18, 64, 12)
      ..lineTo(64, 0)
      ..lineTo(0, 0)
      ..close();
    c.drawPath(moss, _linear(const Rect.fromLTWH(0, 0, 64, 18), const [Color(0xFF6EE7B7), Color(0xFF15803D)]));
    for (var k = 0; k < 8; k++) {
      final x = 2.0 + k * 8 + rng.nextDouble() * 4;
      c.drawLine(Offset(x, 2), Offset(x + 1.5, -4 + rng.nextDouble() * 3), _stroke(const Color(0xFF86EFAC), 1.6));
    }
    if (mask % 3 == 0) _softDot(c, Offset(14 + rng.nextDouble() * 36, 4), 6, const Color(0xFF67E8F9));
  }
}

void _spireLedge(Canvas c) {
  const slab = Rect.fromLTWH(0, 0, 64, 20);
  c.drawRRect(RRect.fromRectAndRadius(slab.shift(const Offset(0, 4)), const Radius.circular(6)), _fill(const Color(0x66000000)));
  c.drawRRect(RRect.fromRectAndRadius(slab, const Radius.circular(6)), _linear(slab, const [Color(0xFF6B5B95), Color(0xFF3B3157)]));
  c.drawRect(const Rect.fromLTWH(2, 0, 60, 5), _fill(const Color(0xFF4ADE80)));
  for (var k = 0; k < 4; k++) {
    c.drawLine(Offset(10.0 + k * 14, 20), Offset(12.0 + k * 14, 28), _stroke(const Color(0xFF2E6B4F), 2));
  }
}

void _spireSpikes(Canvas c) {
  c.drawRect(const Rect.fromLTWH(0, 54, 64, 10), _fill(const Color(0xFF241E36)));
  for (var k = 0; k < 4; k++) {
    final x = 8.0 + k * 16;
    final h = k.isEven ? 40.0 : 30.0;
    final spike = _poly([Offset(x - 7, 56), Offset(x, 56 - h), Offset(x + 7, 56)]);
    c.drawPath(spike, _glow(const Color(0x8822D3EE), 4));
    c.drawPath(spike, _linear(Rect.fromLTWH(x - 7, 56 - h, 14, h), const [Color(0xFFE0F2FE), Color(0xFF22D3EE), Color(0xFF6D28D9)]));
  }
}

// --- Characters ----------------------------------------------------------------

/// The hero, side view facing right. Frames: idle, run, run, jump.
void _spireHero(Canvas c, int f) {
  final bob = f == 1 ? -2.0 : (f == 2 ? 1.0 : 0.0);
  _shadow(c, const Offset(48, 90), 40, 8);
  // Legs
  final legA = f == 1 ? 8.0 : (f == 2 ? -8.0 : (f == 3 ? 6 : 0.0));
  for (final (dx, a) in [(-6.0, legA), (6.0, -legA)]) {
    c.drawLine(Offset(48 + dx, 66 + bob), Offset(48 + dx + a, 88), _stroke(const Color(0xFF1E293B), 7));
  }
  // Cloak and body
  final cloak = Path()
    ..moveTo(36, 40 + bob)
    ..quadraticBezierTo(22, 62 + bob, 28 - (f == 3 ? 6 : 0), 76 + bob)
    ..lineTo(60, 72 + bob)
    ..quadraticBezierTo(62, 52 + bob, 56, 40 + bob)
    ..close();
  c.drawPath(cloak, _linear(const Rect.fromLTWH(22, 40, 40, 36), const [Color(0xFF14B8A6), Color(0xFF115E59)]));
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(38, 42 + bob, 22, 28), const Radius.circular(8)), _linear(const Rect.fromLTWH(38, 42, 22, 28), const [Color(0xFF475569), Color(0xFF1E293B)]));
  // Scarf
  c.drawPath(_poly([Offset(38, 40 + bob), Offset(60, 40 + bob), Offset(56, 48 + bob), Offset(26, 50 + bob - (f == 1 || f == 2 ? 4 : 0))]), _fill(const Color(0xFFF97316)));
  // Head
  c.drawCircle(Offset(50, 30 + bob), 13, _radial(Offset(46, 26 + bob), 18, const [Color(0xFFFDE68A), Color(0xFFD97706)]));
  c.drawPath(
      Path()
        ..moveTo(36, 30 + bob)
        ..quadraticBezierTo(48, 8 + bob, 64, 26 + bob)
        ..lineTo(60, 22 + bob)
        ..quadraticBezierTo(48, 14 + bob, 38, 30 + bob)
        ..close(),
      _fill(const Color(0xFF0F766E)));
  c.drawCircle(Offset(56, 30 + bob), 2.4, _fill(const Color(0xFF1C1917)));
  // Sword on the back
  c.drawLine(Offset(34, 62 + bob), Offset(26, 38 + bob), _stroke(const Color(0xFFCBD5E1), 3));
  c.drawLine(Offset(31, 60 + bob), Offset(37, 56 + bob), _stroke(const Color(0xFFFBBF24), 3));
}

void _spireSlash(Canvas c) {
  final arc = Path()
    ..moveTo(20, 10)
    ..quadraticBezierTo(124, 20, 104, 86)
    ..quadraticBezierTo(108, 34, 20, 26)
    ..close();
  c.drawPath(arc, _glow(const Color(0xAA5EEAD4), 8));
  c.drawPath(arc, _linear(const Rect.fromLTWH(20, 10, 100, 76), const [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFF99F6E4)], begin: Alignment.topLeft, end: Alignment.bottomRight));
}

void _spireEnemy(Canvas c, int i) {
  if (i == 0) {
    // Crawler: an armoured beetle with a glowing eye
    _shadow(c, const Offset(48, 86), 66, 10);
    for (var k = 0; k < 3; k++) {
      c.drawLine(Offset(30.0 + k * 16, 74), Offset(24.0 + k * 16, 86), _stroke(const Color(0xFF1E1B4B), 4));
    }
    final shell = Path()
      ..moveTo(14, 78)
      ..quadraticBezierTo(16, 38, 52, 38)
      ..quadraticBezierTo(84, 40, 82, 78)
      ..close();
    c.drawPath(shell, _linear(const Rect.fromLTWH(14, 38, 70, 40), const [Color(0xFFA78BFA), Color(0xFF4C1D95)]));
    for (var k = 0; k < 3; k++) {
      c.drawLine(Offset(28.0 + k * 16, 44), Offset(26.0 + k * 16, 76), _stroke(const Color(0x553B0764), 2));
    }
    c.drawCircle(const Offset(80, 64), 10, _fill(const Color(0xFF2E1065)));
    _softDot(c, const Offset(84, 62), 8, const Color(0xFFF472B6));
  } else {
    // Moth: soft glowing wings
    _shadow(c, const Offset(48, 90), 30, 6);
    for (final s in [-1.0, 1.0]) {
      final wing = Path()
        ..moveTo(48, 48)
        ..quadraticBezierTo(48 + s * 44, 14, 48 + s * 40, 52)
        ..quadraticBezierTo(48 + s * 30, 70, 48, 54)
        ..close();
      c.drawPath(wing, _glow(const Color(0x5567E8F9), 6));
      c.drawPath(wing, _linear(const Rect.fromLTWH(4, 14, 88, 56), const [Color(0xFFCFFAFE), Color(0xFF0891B2)]));
      c.drawCircle(Offset(48 + s * 26, 40), 5, _fill(const Color(0xFFF0ABFC)));
    }
    c.drawOval(Rect.fromCenter(center: const Offset(48, 54), width: 12, height: 30), _fill(const Color(0xFF1E293B)));
    _softDot(c, const Offset(48, 42), 6, const Color(0xFFFDE68A));
  }
}

void _spireBoss(Canvas c) {
  // The Thornback: a heavy beast with a shell of crystal thorns (faces right)
  _shadow(c, const Offset(96, 150), 160, 18);
  for (final x in [56.0, 92.0, 128.0]) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 112, 18, 38), const Radius.circular(8)), _fill(const Color(0xFF1E1B2E)));
  }
  final body = Path()
    ..moveTo(26, 124)
    ..quadraticBezierTo(24, 50, 100, 46)
    ..quadraticBezierTo(170, 48, 168, 124)
    ..close();
  c.drawPath(body, _linear(const Rect.fromLTWH(24, 46, 146, 78), const [Color(0xFF6B5B95), Color(0xFF2B2440)]));
  for (var k = 0; k < 6; k++) {
    final x = 40.0 + k * 20;
    final h = 30.0 + (k % 3) * 10;
    final thorn = _poly([Offset(x - 9, 62 - (k == 0 || k == 5 ? -10 : 0)), Offset(x + 3, 62 - h), Offset(x + 11, 64)]);
    c.drawPath(thorn, _glow(const Color(0x8822D3EE), 4));
    c.drawPath(thorn, _linear(Rect.fromLTWH(x - 9, 62 - h, 20, h), const [Color(0xFFE0F2FE), Color(0xFF22D3EE), Color(0xFF6D28D9)]));
  }
  // Head with glowing eyes and tusks
  c.drawCircle(const Offset(160, 104), 26, _radial(const Offset(152, 96), 34, const [Color(0xFF7C6FA0), Color(0xFF2B2440)]));
  _softDot(c, const Offset(170, 98), 10, const Color(0xFFF97316));
  c.drawCircle(const Offset(170, 98), 3.5, _fill(const Color(0xFFFFEDD5)));
  c.drawPath(_poly(const [Offset(176, 114), Offset(192, 124), Offset(174, 122)]), _fill(const Color(0xFFF5F5F4)));
}

void _spireGem(Canvas c, Offset at, double r) {
  _softDot(c, at, r * 1.8, const Color(0xAAA855F7), core: 0.15);
  final gem = _poly([at + Offset(0, -r), at + Offset(r * 0.8, -r * 0.2), at + Offset(0, r), at + Offset(-r * 0.8, -r * 0.2)]);
  c.drawPath(gem, _linear(Rect.fromCircle(center: at, radius: r), const [Color(0xFFF5D0FE), Color(0xFFA855F7), Color(0xFF581C87)]));
  c.drawPath(_poly([at + Offset(0, -r), at + Offset(r * 0.8, -r * 0.2), at + Offset(0, -r * 0.1)]), _fill(const Color(0x88FFFFFF)));
}

/// 0 save shrine, 1 double jump, 2 dash, 3 wall jump, 4 heart container, 5 gem, 6 the Ember Heart.
void _spireObject(Canvas c, int i) {
  const center = Offset(48, 48);
  Color orbColor(int k) => [const Color(0xFF67E8F9), const Color(0xFFF97316), const Color(0xFF4ADE80)][k];
  switch (i) {
    case 0:
      _shadow(c, const Offset(48, 90), 60, 10);
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(26, 70, 44, 20), const Radius.circular(6)),
          _linear(const Rect.fromLTWH(26, 70, 44, 20), const [Color(0xFF94A3B8), Color(0xFF334155)]));
      _softDot(c, const Offset(48, 44), 40, const Color(0x6622D3EE), core: 0.2);
      final crystal = _poly(const [Offset(48, 10), Offset(62, 40), Offset(48, 70), Offset(34, 40)]);
      c.drawPath(crystal, _linear(const Rect.fromLTWH(34, 10, 28, 60), const [Color(0xFFF0FDFA), Color(0xFF2DD4BF), Color(0xFF0F766E)]));
      c.drawPath(_poly(const [Offset(48, 10), Offset(62, 40), Offset(48, 40)]), _fill(const Color(0x66FFFFFF)));
    case 1 || 2 || 3:
      final color = orbColor(i - 1);
      _softDot(c, center, 44, color.withValues(alpha: 0.75), core: 0.15);
      c.drawCircle(center, 20, _radial(center - const Offset(6, 6), 28, [const Color(0xFFFFFFFF), color, Color.lerp(color, const Color(0xFF000000), 0.45)!]));
      final white = _stroke(const Color(0xFFFFFFFF), 3.5);
      if (i == 1) {
        // two chevrons up
        for (final dy in [4.0, -6.0]) {
          c.drawPath(
              Path()
                ..moveTo(38, 54 + dy)
                ..lineTo(48, 44 + dy)
                ..lineTo(58, 54 + dy),
              white);
        }
      } else if (i == 2) {
        // chevrons forward
        for (final dx in [-6.0, 4.0]) {
          c.drawPath(
              Path()
                ..moveTo(42 + dx, 38)
                ..lineTo(52 + dx, 48)
                ..lineTo(42 + dx, 58),
              white);
        }
      } else {
        // a claw
        for (final dy in [-8.0, 0.0, 8.0]) {
          c.drawLine(Offset(40, 48 + dy), Offset(56, 44 + dy), white);
        }
      }
    case 4:
      _softDot(c, center, 40, const Color(0x99F43F5E), core: 0.2);
      c.save();
      c.translate(16, 14);
      _bastionIcon(c, 1);
      c.restore();
    case 5:
      _spireGem(c, center, 20);
    case 6:
      _softDot(c, center, 48, const Color(0xCCF97316), core: 0.1);
      final heart = _poly(const [Offset(48, 8), Offset(76, 40), Offset(48, 88), Offset(20, 40)]);
      c.drawPath(heart, _linear(const Rect.fromLTWH(20, 8, 56, 80), const [Color(0xFFFFF7ED), Color(0xFFFB923C), Color(0xFFB91C1C)]));
      c.drawPath(_poly(const [Offset(48, 8), Offset(76, 40), Offset(48, 40)]), _fill(const Color(0x77FFFFFF)));
  }
}

// --- Backgrounds -------------------------------------------------------------------

void _spireFar(Canvas c) {
  const r = Rect.fromLTWH(0, 0, 960, 544);
  c.drawRect(r, _linear(r, const [Color(0xFF0E1530), Color(0xFF1A1036), Color(0xFF0B1A2A)]));
  final rng = math.Random(31);
  // Distant glows and crystal pillars, wrapped so the image repeats both ways
  for (var k = 0; k < 10; k++) {
    final at = Offset(rng.nextDouble() * 960, rng.nextDouble() * 544);
    final tint = [const Color(0x2222D3EE), const Color(0x22A855F7), const Color(0x1A2DD4BF)][k % 3];
    for (final dx in [0.0, -960.0, 960.0]) {
      for (final dy in [0.0, -544.0, 544.0]) {
        c.drawCircle(at + Offset(dx, dy), 120 + rng.nextDouble() * 10, _glow(tint, 60));
      }
    }
  }
  for (var k = 0; k < 9; k++) {
    final x = rng.nextDouble() * 960;
    final h = 120 + rng.nextDouble() * 200;
    final w = 18 + rng.nextDouble() * 26;
    for (final dx in [0.0, -960.0, 960.0]) {
      final pillar = _poly([Offset(x + dx - w, 544), Offset(x + dx, 544 - h), Offset(x + dx + w, 544)]);
      c.drawPath(pillar, _fill(const Color(0x332A2350)));
      final top = _poly([Offset(x + dx - w * 0.6, 0), Offset(x + dx, h * 0.5), Offset(x + dx + w * 0.6, 0)]);
      c.drawPath(top, _fill(const Color(0x332A2350)));
    }
  }
}

void _spireMid(Canvas c) {
  final rng = math.Random(47);
  // Darker stalactites and stalagmites, with crystal glints (transparent elsewhere)
  for (var k = 0; k < 14; k++) {
    final x = rng.nextDouble() * 960;
    final w = 20 + rng.nextDouble() * 40;
    final h = 60 + rng.nextDouble() * 160;
    final fromTop = k.isEven;
    for (final dx in [0.0, -960.0, 960.0]) {
      final p = fromTop
          ? _poly([Offset(x + dx - w, 0), Offset(x + dx, h), Offset(x + dx + w, 0)])
          : _poly([Offset(x + dx - w, 544), Offset(x + dx, 544 - h), Offset(x + dx + w, 544)]);
      c.drawPath(p, _linear(Rect.fromLTWH(x + dx - w, fromTop ? 0 : 544 - h, w * 2, h), const [Color(0x88241C3C), Color(0x55120E20)]));
      if (k % 3 == 0) _softDot(c, Offset(x + dx, fromTop ? h - 10 : 544 - h + 10), 10, const Color(0x8867E8F9));
    }
  }
}

// --- Music -----------------------------------------------------------------------

/// An adventurous loop in D dorian: driving bass, bright arps, a warm pad.
List<double> _spireTheme() {
  const bpm = 104.0;
  const beat = 60 / bpm;
  const bars = 16;
  final out = List<double>.filled((bars * 4 * beat * _rate).round(), 0);
  const chords = [[62, 65, 69], [60, 64, 67], [55, 59, 62], [57, 60, 64]]; // Dm C G Am
  final arp = List<double>.filled(out.length, 0);
  for (var bar = 0; bar < bars; bar++) {
    final chord = chords[(bar ~/ 2) % 4];
    final t0 = bar * 4 * beat;
    for (final n in chord) {
      _synthNote(out, t0, 4 * beat, _hz(n - 12), voices: 3, detune: 0.009, bright: 1300, dark: 600, gain: 0.06, a: 0.4, d: 0.6, s: 0.8, r: 0.4);
    }
    for (var k = 0; k < 8; k++) {
      final note = chord[0] - 24 + (k % 4 == 3 ? 7 : 0);
      _synthNote(out, t0 + k * beat / 2, beat / 2 - 0.03, _hz(note), voices: 2, detune: 0.005, bright: 800, dark: 200, gain: 0.24, a: 0.003, d: 0.12, s: 0.5, r: 0.04);
    }
    if (bar >= 2) {
      final pattern = [chord[0], chord[1], chord[2], chord[0] + 12, chord[2], chord[1] + 12, chord[2] + 12, chord[1]];
      for (var k = 0; k < 16; k++) {
        _synthNote(arp, t0 + k * beat / 4, beat / 4, _hz(pattern[k % 8] + 12), voices: 1, bright: 3600, dark: 700, gain: 0.07, a: 0.002, d: 0.1, s: 0.2, r: 0.05);
      }
    }
    if (bar >= 4) {
      for (var k = 0; k < 4; k++) {
        _kick(out, t0 + k * beat, gain: 0.55);
        if (k == 1 || k == 3) _snare(out, t0 + k * beat, gain: 0.3);
        _hat(out, t0 + k * beat + beat / 2, gain: 0.07);
      }
    }
  }
  _delay(arp, beat * 0.75, 0.35, 0.5);
  for (var i = 0; i < out.length; i++) {
    out[i] += arp[i];
  }
  return _master(out);
}

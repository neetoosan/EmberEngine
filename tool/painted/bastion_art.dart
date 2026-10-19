part of 'paint_art_test.dart';

// Ember Bastion: a tower-defense map, towers, enemies and effects in a soft,
// modern style (rounded shapes, gentle gradients and drop shadows). Sprites
// are painted at twice the size they are shown.

const _bastion = 'bastion';

Future<void> _paintBastion() async {
  await _png(_bastion, 'map.png', 960, 540, _bastionMap);
  await _sheet(_bastion, 'decor.png', 96, 96, 4, _bastionDecor);
  await _png(_bastion, 'keep.png', 200, 200, _bastionKeep);
  await _sheet(_bastion, 'bases.png', 96, 96, 12, (c, i) => _bastionBase(c, i ~/ 3, i % 3), columns: 3);
  await _sheet(_bastion, 'tops.png', 96, 96, 12, (c, i) => _bastionTop(c, i ~/ 3, i % 3), columns: 3);
  await _sheet(_bastion, 'enemies.png', 96, 96, 5, _bastionEnemy);
  await _sheet(_bastion, 'shots.png', 48, 48, 4, _bastionShot);
  await _sheet(_bastion, 'icons.png', 64, 64, 5, _bastionIcon);
  await _png(_bastion, 'range.png', 256, 256, (c) {
    c.drawCircle(const Offset(128, 128), 124, _fill(const Color(0x22FFFFFF)));
    c.drawCircle(const Offset(128, 128), 124, _stroke(const Color(0xCCFFFFFF), 3));
  });
  await _png(_bastion, 'cell.png', 64, 64, (c) {
    final r = RRect.fromRectAndRadius(const Rect.fromLTWH(4, 4, 56, 56), const Radius.circular(12));
    c.drawRRect(r, _fill(const Color(0x33FFFFFF)));
    c.drawRRect(r, _stroke(const Color(0xEEFFFFFF), 3));
  });
  await _png(_bastion, 'ring.png', 256, 256, _novaRing);
  await _png(_bastion, 'panel.png', 840, 520, _bastionPanel);

  _writeWav(_bastion, 'bastion.wav', _bastionTheme());
  _writeWav(_bastion, 'arrow.wav', _effect(0.18, (t) {
    final f = 900 * math.exp(-t * 18) + 300;
    return math.sin(2 * math.pi * f * t) * math.exp(-t * 30) * 0.6 + _noise() * math.exp(-t * 60) * 0.3;
  }, peak: 0.45));
  final cannonLp = _LowPass();
  _writeWav(_bastion, 'cannon.wav', _effect(0.6, (t) {
    final body = cannonLp.process(_noise(), 900 * math.exp(-t * 6) + 80);
    return body * math.exp(-t * 7) * 1.5 + math.sin(2 * math.pi * (55 + 70 * math.exp(-t * 25)) * t) * math.exp(-t * 9);
  }, peak: 0.7));
  _writeWav(_bastion, 'frost.wav', _effect(0.7, (t) {
    var v = 0.0;
    for (final (f, k) in [(1568.0, 1.0), (2093.0, 0.7), (2637.0, 0.5), (3136.0, 0.3)]) {
      v += math.sin(2 * math.pi * f * t) * k * math.exp(-t * (5 + f / 800));
    }
    return v * 0.5;
  }, peak: 0.45));
  _writeWav(_bastion, 'zap.wav', _effect(0.3, (t) {
    final buzz = ((t * 110 * (1 + 3 * _noise().abs())) % 1) * 2 - 1;
    return (buzz * 0.5 + _noise() * 0.5) * math.exp(-t * 12);
  }, peak: 0.45));
  _writeWav(_bastion, 'build.wav', _effect(0.5, (t) {
    final thunk = math.sin(2 * math.pi * (90 + 120 * math.exp(-t * 30)) * t) * math.exp(-t * 18);
    final chime = t > 0.08 ? math.sin(2 * math.pi * 1175 * t) * math.exp(-(t - 0.08) * 9) * 0.4 : 0.0;
    return thunk + chime;
  }, peak: 0.6));
  _writeWav(_bastion, 'coin.wav', _effect(0.3, (t) {
    final f = t < 0.06 ? 1319.0 : 1976.0;
    return math.sin(2 * math.pi * f * t) * math.exp(-t * 14) * 0.6;
  }, peak: 0.35));
  _writeWav(_bastion, 'leak.wav', _effect(0.7, (t) {
    final f = 330 * math.exp(-t * 2.5);
    return ((f * t) % 1 * 2 - 1) * math.exp(-t * 4) * 0.5;
  }, peak: 0.55));
  _writeWav(_bastion, 'horn.wav', _effect(1.4, (t) {
    var v = 0.0;
    for (final n in [50, 57, 62]) {
      final f = _hz(n);
      v += ((f * t) % 1 * 2 - 1) * 0.3;
    }
    return v * math.min(1, t * 6) * math.exp(-math.max(0, t - 0.9) * 6);
  }, peak: 0.55));
  _writeWav(_bastion, 'victory.wav', _effect(1.6, (t) {
    const notes = [62, 66, 69, 74];
    final step = (t / 0.16).floor().clamp(0, 3);
    final local = t - step * 0.16;
    final f = _hz(notes[step]);
    return (math.sin(2 * math.pi * f * t) + 0.4 * math.sin(4 * math.pi * f * t)) * math.exp(-local * (step == 3 ? 2 : 8));
  }, peak: 0.6));
}

// --- Map ------------------------------------------------------------------------

void _bastionMap(Canvas c) {
  const r = Rect.fromLTWH(0, 0, 960, 540);
  c.drawRect(r, _linear(r, const [Color(0xFF6DB257), Color(0xFF4E9446), Color(0xFF3F7F3C)], begin: Alignment.topLeft, end: Alignment.bottomRight));
  final rng = math.Random(21);
  // Soft patches of lighter and darker grass
  for (var k = 0; k < 40; k++) {
    final at = Offset(rng.nextDouble() * 960, rng.nextDouble() * 540);
    final tint = k.isEven ? const Color(0x1AFFF7C2) : const Color(0x1A0B3D1A);
    c.drawOval(Rect.fromCenter(center: at, width: 80 + rng.nextDouble() * 200, height: 50 + rng.nextDouble() * 110), _glow(tint, 24));
  }
  final road = Path()..moveTo(BastionLayout.path.first.$1, BastionLayout.path.first.$2);
  for (final (x, y) in BastionLayout.path.skip(1)) {
    road.lineTo(x, y);
  }
  // Grass tufts and flowers, kept off the road
  final roadMetric = road.computeMetrics().toList();
  bool nearRoad(Offset p) {
    for (final m in roadMetric) {
      for (var d = 0.0; d < m.length; d += 8) {
        if ((m.getTangentForOffset(d)!.position - p).distance < BastionLayout.roadWidth * 0.75) return true;
      }
    }
    return false;
  }

  for (var k = 0; k < 420; k++) {
    final at = Offset(rng.nextDouble() * 960, rng.nextDouble() * 540);
    if (nearRoad(at)) continue;
    if (k % 9 == 0) {
      final petal = [const Color(0xFFFDE68A), const Color(0xFFFBCFE8), const Color(0xFFFFFFFF), const Color(0xFFC4B5FD)][k % 4];
      for (var p = 0; p < 5; p++) {
        final a = p * math.pi * 2 / 5;
        c.drawCircle(at + Offset(math.cos(a), math.sin(a)) * 2.6, 2, _fill(petal));
      }
      c.drawCircle(at, 1.6, _fill(const Color(0xFFF59E0B)));
    } else {
      final blade = _stroke(Color.lerp(const Color(0xFF8BD06E), const Color(0xFF2F6B2E), rng.nextDouble())!.withValues(alpha: 0.8), 1.6);
      for (final dx in [-3.0, 0.0, 3.0]) {
        c.drawLine(at + Offset(dx, 0), at + Offset(dx * 1.6, -6 - rng.nextDouble() * 4), blade);
      }
    }
  }
  // The road: a soft shadow, a darker edge, the sandy top and a worn middle
  Paint roadPaint(Color color, double width, {double blur = 0}) => _stroke(color, width, blur: blur)..strokeCap = StrokeCap.square;
  c.drawPath(road.shift(const Offset(0, 5)), roadPaint(const Color(0x55163A14), BastionLayout.roadWidth + 10, blur: 6));
  c.drawPath(road, roadPaint(const Color(0xFFB08A55), BastionLayout.roadWidth + 6));
  c.drawPath(road, roadPaint(const Color(0xFFE6C38A), BastionLayout.roadWidth));
  c.drawPath(road, roadPaint(const Color(0x33FFFFFF), BastionLayout.roadWidth * 0.35, blur: 4));
  for (final m in roadMetric) {
    for (var d = 0.0; d < m.length; d += 13) {
      final tan = m.getTangentForOffset(d)!;
      final side = Offset(-tan.vector.dy, tan.vector.dx) * ((rng.nextDouble() - 0.5) * BastionLayout.roadWidth * 0.8);
      c.drawCircle(tan.position + side, 1.2 + rng.nextDouble() * 1.8, _fill(const Color(0x55A07A45)));
    }
  }
  // A cave mouth where enemies come from
  final (gx, gy) = (0.0, BastionLayout.path.first.$2);
  c.drawOval(Rect.fromCenter(center: Offset(gx + 8, gy), width: 90, height: 120), _glow(const Color(0x88000000), 10));
  c.drawOval(Rect.fromCenter(center: Offset(gx, gy), width: 80, height: 104), _linear(Rect.fromCenter(center: Offset(gx, gy), width: 80, height: 104),
      const [Color(0xFF8C8478), Color(0xFF57514A)]));
  c.drawOval(Rect.fromCenter(center: Offset(gx + 4, gy + 4), width: 46, height: 66), _fill(const Color(0xFF17130F)));
  _softDot(c, Offset(gx + 6, gy + 8), 26, const Color(0x55A855F7));
}

void _shadow(Canvas c, Offset at, double w, double h) => c.drawOval(Rect.fromCenter(center: at, width: w, height: h), _glow(const Color(0x66173016), 5));

void _bastionDecor(Canvas c, int i) {
  const center = Offset(48, 48);
  switch (i) {
    case 0: // round tree
      _shadow(c, const Offset(54, 62), 70, 40);
      for (final (o, r, col) in [(const Offset(-12, 4), 22.0, 0xFF2F7D32), (const Offset(12, 2), 22.0, 0xFF2E7A31), (const Offset(0, -10), 26.0, 0xFF3C9440)]) {
        c.drawCircle(center + o, r, _radial(center + o - const Offset(6, 8), r * 1.6, [const Color(0xFF7CCB5E), Color(col)]));
      }
      c.drawCircle(center + const Offset(-6, -18), 7, _fill(const Color(0x55E9FFD9)));
    case 1: // pine
      _shadow(c, const Offset(54, 66), 56, 30);
      for (final (y, w) in [(56.0, 30.0), (40.0, 24.0), (26.0, 17.0)]) {
        final tri = _poly([Offset(48, y - w), Offset(48 + w, y + 12), Offset(48 - w, y + 12)]);
        c.drawPath(tri, _linear(Rect.fromLTWH(48 - w, y - w, w * 2, w + 12), const [Color(0xFF5BAF52), Color(0xFF1F5E2A)], begin: Alignment.topLeft, end: Alignment.bottomRight));
      }
    case 2: // rock
      _shadow(c, const Offset(52, 62), 64, 30);
      final rock = _poly(const [Offset(20, 60), Offset(28, 38), Offset(46, 28), Offset(66, 34), Offset(76, 54), Offset(66, 66), Offset(34, 68)]);
      c.drawPath(rock, _linear(const Rect.fromLTWH(20, 28, 56, 40), const [Color(0xFFD6D3CE), Color(0xFF8A847C), Color(0xFF615C55)]));
      c.drawPath(_poly(const [Offset(30, 40), Offset(46, 31), Offset(52, 40), Offset(38, 48)]), _fill(const Color(0x44FFFFFF)));
    case 3: // bush with berries
      _shadow(c, const Offset(52, 60), 64, 28);
      for (final (o, r) in [(const Offset(-14, 4), 15.0), (const Offset(12, 4), 16.0), (const Offset(0, -6), 18.0)]) {
        c.drawCircle(center + o, r, _radial(center + o - const Offset(5, 6), r * 1.5, const [Color(0xFF86D16B), Color(0xFF2E7F36)]));
      }
      for (final o in [const Offset(-8, -4), const Offset(8, 2), const Offset(-2, 8), const Offset(14, -8)]) {
        c.drawCircle(center + o, 3, _fill(const Color(0xFFE11D48)));
      }
  }
}

void _bastionKeep(Canvas c) {
  // A small castle seen from above at an angle
  _shadow(c, const Offset(108, 168), 170, 50);
  const wall = Rect.fromLTWH(34, 70, 132, 92);
  c.drawRRect(RRect.fromRectAndRadius(wall, const Radius.circular(10)), _linear(wall, const [Color(0xFFE7E1D6), Color(0xFFB9B0A2), Color(0xFF8F8679)]));
  for (var k = 0; k < 6; k++) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(38.0 + k * 22, 60, 14, 16), const Radius.circular(3)), _fill(const Color(0xFFD9D2C5)));
  }
  // Gate
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(84, 118, 32, 44), const Radius.circular(16)), _fill(const Color(0xFF5B3A1E)));
  c.drawLine(const Offset(100, 120), const Offset(100, 162), _stroke(const Color(0x66000000), 2));
  // Towers with blue roofs and flags
  for (final x in [42.0, 158.0]) {
    final body = Rect.fromCenter(center: Offset(x, 96), width: 40, height: 84);
    c.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(8)), _linear(body, const [Color(0xFFF1ECE3), Color(0xFFA79E90)], begin: Alignment.centerLeft, end: Alignment.centerRight));
    final roof = _poly([Offset(x - 26, 58), Offset(x, 14), Offset(x + 26, 58)]);
    c.drawPath(roof, _linear(Rect.fromLTWH(x - 26, 14, 52, 44), const [Color(0xFF60A5FA), Color(0xFF1E40AF)], begin: Alignment.topLeft, end: Alignment.bottomRight));
    c.drawLine(Offset(x, 14), Offset(x, 0), _stroke(const Color(0xFF5B3A1E), 2.5));
    c.drawPath(_poly([Offset(x, 0), Offset(x + 18, 5), Offset(x, 10)]), _fill(const Color(0xFFF97316)));
  }
  // Keep in the middle
  final keep = Rect.fromCenter(center: const Offset(100, 76), width: 56, height: 64);
  c.drawRRect(RRect.fromRectAndRadius(keep, const Radius.circular(6)), _linear(keep, const [Color(0xFFF6F2EA), Color(0xFFB2A898)], begin: Alignment.centerLeft, end: Alignment.centerRight));
  c.drawPath(_poly(const [Offset(66, 46), Offset(100, 6), Offset(134, 46)]),
      _linear(const Rect.fromLTWH(66, 6, 68, 40), const [Color(0xFF93C5FD), Color(0xFF1D4ED8)], begin: Alignment.topLeft, end: Alignment.bottomRight));
  c.drawCircle(const Offset(100, 76), 7, _fill(const Color(0xFFFDE68A)));
  _softDot(c, const Offset(100, 76), 16, const Color(0x66FDE68A));
}

// --- Towers ----------------------------------------------------------------------

const _towerAccent = [Color(0xFF4ADE80), Color(0xFFF97316), Color(0xFF38BDF8), Color(0xFFA78BFA)];

/// A round plinth: wood (level 1), stone (2), marble with gold (3), with the tower's colour.
void _bastionBase(Canvas c, int type, int level) {
  const center = Offset(48, 50);
  _shadow(c, const Offset(52, 60), 80, 44);
  final top = [const Color(0xFFC08A55), const Color(0xFFB8B3AC), const Color(0xFFF3EEE6)][level];
  final side = [const Color(0xFF7A522D), const Color(0xFF6E6963), const Color(0xFFB8AE9E)][level];
  c.drawCircle(center + const Offset(0, 6), 36, _fill(side));
  c.drawCircle(center, 36, _radial(center - const Offset(10, 12), 60, [Color.lerp(top, const Color(0xFFFFFFFF), 0.3)!, top]));
  if (level == 0) {
    for (var k = -2; k <= 2; k++) {
      c.drawLine(center + Offset(k * 12.0, -33 + k.abs() * 3.0), center + Offset(k * 12.0, 33 - k.abs() * 3.0), _stroke(const Color(0x33000000), 1.5));
    }
  } else {
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4;
      c.drawLine(center + Offset(math.cos(a), math.sin(a)) * 24, center + Offset(math.cos(a), math.sin(a)) * 35, _stroke(const Color(0x30000000), 1.5));
    }
  }
  c.drawCircle(center, 24, _stroke(_towerAccent[type], 4));
  if (level == 2) c.drawCircle(center, 35, _stroke(const Color(0xFFFBBF24), 3));
  for (var k = 0; k <= level; k++) {
    c.drawCircle(center + Offset(-8.0 + k * 8 - (level - 0) * 0.0, 30), 3, _fill(const Color(0xFFFDE68A)));
  }
}

/// The turning top of a tower (faces right). type: 0 archer, 1 cannon, 2 frost, 3 tesla.
void _bastionTop(Canvas c, int type, int level) {
  const center = Offset(48, 48);
  final gold = level == 2;
  switch (type) {
    case 0: // crossbow
      final wood = gold ? const Color(0xFFB45309) : const Color(0xFF8B5A2B);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: center + const Offset(6, 0), width: 50, height: 10), const Radius.circular(4)),
          _linear(Rect.fromCenter(center: center, width: 50, height: 10), [Color.lerp(wood, const Color(0xFFFFFFFF), 0.3)!, wood]));
      final bow = Path()
        ..moveTo(62, 18)
        ..quadraticBezierTo(80, 48, 62, 78);
      c.drawPath(bow, _stroke(gold ? const Color(0xFFFBBF24) : const Color(0xFF5B3A1E), 5));
      c.drawLine(const Offset(62, 18), const Offset(46, 48), _stroke(const Color(0xDDFFFFFF), 1.2));
      c.drawLine(const Offset(62, 78), const Offset(46, 48), _stroke(const Color(0xDDFFFFFF), 1.2));
      c.drawLine(const Offset(46, 48), const Offset(84, 48), _stroke(const Color(0xFFE5E7EB), 2.5));
      if (level >= 1) c.drawPath(_poly(const [Offset(84, 43), Offset(92, 48), Offset(84, 53)]), _fill(const Color(0xFFCBD5E1)));
      c.drawCircle(center, 9, _fill(_towerAccent[0]));
    case 1: // cannon
      final len = [34.0, 40.0, 44.0][level];
      for (final dy in level == 2 ? [-9.0, 9.0] : [0.0]) {
        final barrel = Rect.fromLTWH(46, 48 + dy - 8, len, 16);
        c.drawRRect(RRect.fromRectAndRadius(barrel, const Radius.circular(7)),
            _linear(barrel, const [Color(0xFF6B7280), Color(0xFF1F2937), Color(0xFF111827)], stops: const [0, 0.5, 1]));
        c.drawCircle(Offset(46 + len, 48 + dy), 7, _fill(const Color(0xFF0B0F17)));
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(46 + len - 6, 48 + dy - 9, 6, 18), const Radius.circular(3)),
            _fill(gold ? const Color(0xFFFBBF24) : const Color(0xFF9CA3AF)));
      }
      c.drawCircle(center, 18, _radial(center - const Offset(6, 6), 28, const [Color(0xFF9CA3AF), Color(0xFF374151)]));
      c.drawCircle(center, 7, _fill(_towerAccent[1]));
    case 2: // frost crystals
      final n = [3, 4, 5][level];
      _softDot(c, center, 40, const Color(0x5538BDF8));
      for (var k = 0; k < n; k++) {
        final a = k * math.pi * 2 / n - math.pi / 2;
        final at = center + Offset(math.cos(a), math.sin(a)) * 12;
        final h = 18.0 + level * 4;
        final shard = _poly([at + Offset(0, -h), at + const Offset(7, -2), at + Offset(0, h * 0.5), at + const Offset(-7, -2)]);
        c.drawPath(shard, _linear(Rect.fromCenter(center: at, width: 14, height: h * 1.5), const [Color(0xFFF0F9FF), Color(0xFF7DD3FC), Color(0xFF0284C7)]));
        c.drawPath(shard, _stroke(const Color(0xAAFFFFFF), 1));
      }
      c.drawCircle(center, 8, _fill(const Color(0xFFE0F2FE)));
    case 3: // tesla coil with an orb
      for (var k = 0; k < 3; k++) {
        c.drawCircle(center, 22.0 - k * 6, _stroke(k.isEven ? const Color(0xFFB45309) : const Color(0xFFD97706), 4));
      }
      final orb = 10.0 + level * 2;
      _softDot(c, center, orb * 3, const Color(0xAAA78BFA));
      c.drawCircle(center, orb, _radial(center - Offset(orb * 0.3, orb * 0.3), orb * 1.4, const [Color(0xFFFFFFFF), Color(0xFFC4B5FD), Color(0xFF7C3AED)]));
  }
}

// --- Enemies (face right) ------------------------------------------------------

void _bastionEnemy(Canvas c, int i) {
  const center = Offset(48, 48);
  _shadow(c, const Offset(50, 60), [52.0, 58.0, 72.0, 44.0, 80.0][i], 24);
  switch (i) {
    case 0: // goblin grunt: a round green body, helmet, little shield
      c.drawCircle(center, 22, _radial(center - const Offset(6, 8), 34, const [Color(0xFFA3E635), Color(0xFF4D7C0F)]));
      c.drawArc(Rect.fromCircle(center: center + const Offset(-4, 0), radius: 22), -2.2, 4.4, false, _stroke(const Color(0xFF94A3B8), 7));
      c.drawCircle(center + const Offset(12, -7), 3.5, _fill(const Color(0xFFFFFFFF)));
      c.drawCircle(center + const Offset(12, 7), 3.5, _fill(const Color(0xFFFFFFFF)));
      c.drawCircle(center + const Offset(13, -7), 1.8, _fill(const Color(0xFF111827)));
      c.drawCircle(center + const Offset(13, 7), 1.8, _fill(const Color(0xFF111827)));
      c.drawOval(Rect.fromCenter(center: center + const Offset(4, 24), width: 20, height: 12), _fill(const Color(0xFF92400E)));
    case 1: // wolf: long and grey
      final body = Rect.fromCenter(center: center, width: 64, height: 28);
      c.drawOval(body, _linear(body, const [Color(0xFFE5E7EB), Color(0xFF6B7280)]));
      c.drawPath(_poly(const [Offset(70, 40), Offset(90, 48), Offset(70, 56)]), _fill(const Color(0xFF9CA3AF)));
      c.drawPath(_poly(const [Offset(68, 38), Offset(74, 30), Offset(76, 40)]), _fill(const Color(0xFF4B5563)));
      c.drawPath(_poly(const [Offset(68, 58), Offset(74, 66), Offset(76, 56)]), _fill(const Color(0xFF4B5563)));
      c.drawPath(_poly(const [Offset(18, 48), Offset(2, 42), Offset(6, 48), Offset(2, 54)]), _fill(const Color(0xFF6B7280)));
      c.drawCircle(const Offset(80, 45), 2, _fill(const Color(0xFFFDE047)));
    case 2: // stone golem: big, cracked, glowing eyes
      c.drawCircle(center, 30, _radial(center - const Offset(8, 10), 46, const [Color(0xFFD6D3D1), Color(0xFF78716C), Color(0xFF44403C)]));
      for (final (a, b) in [(const Offset(30, 34), const Offset(44, 44)), (const Offset(44, 44), const Offset(38, 60)), (const Offset(54, 24), const Offset(60, 40))]) {
        c.drawLine(a, b, _stroke(const Color(0x88292524), 2));
      }
      for (final dy in [-9.0, 9.0]) {
        _softDot(c, center + Offset(18, dy), 9, const Color(0xFFF97316));
        c.drawCircle(center + Offset(18, dy), 3, _fill(const Color(0xFFFFEDD5)));
      }
      for (final dy in [-28.0, 28.0]) {
        c.drawCircle(center + Offset(4, dy), 10, _radial(center + Offset(0, dy), 14, const [Color(0xFFA8A29E), Color(0xFF57534E)]));
      }
    case 3: // wisp: a quick blue spirit with a trail
      for (var k = 3; k >= 0; k--) {
        _softDot(c, center - Offset(k * 9.0, 0), 18.0 - k * 3, Color.fromRGBO(56, 189, 248, 0.5 - k * 0.1));
      }
      c.drawCircle(center, 13, _radial(center - const Offset(3, 3), 16, const [Color(0xFFFFFFFF), Color(0xFF7DD3FC), Color(0xFF0369A1)]));
      c.drawCircle(center + const Offset(5, -4), 2.5, _fill(const Color(0xFF0C4A6E)));
      c.drawCircle(center + const Offset(5, 4), 2.5, _fill(const Color(0xFF0C4A6E)));
    case 4: // dark knight: armour, red cape, a crown
      final cape = _poly(const [Offset(46, 18), Offset(8, 30), Offset(4, 48), Offset(8, 66), Offset(46, 78)]);
      c.drawPath(cape, _linear(const Rect.fromLTWH(4, 18, 42, 60), const [Color(0xFFDC2626), Color(0xFF7F1D1D)], begin: Alignment.centerLeft, end: Alignment.centerRight));
      c.drawCircle(center, 26, _radial(center - const Offset(7, 8), 40, const [Color(0xFF94A3B8), Color(0xFF334155), Color(0xFF0F172A)]));
      for (final dy in [-24.0, 24.0]) {
        c.drawCircle(center + Offset(6, dy), 9, _radial(center + Offset(4, dy), 12, const [Color(0xFF64748B), Color(0xFF1E293B)]));
      }
      final crown = _poly(const [Offset(36, 36), Offset(42, 30), Offset(48, 36), Offset(54, 30), Offset(60, 36), Offset(60, 44), Offset(36, 44)]);
      c.drawPath(crown, _fill(const Color(0xFFFBBF24)));
      c.drawLine(const Offset(64, 42), const Offset(64, 54), _stroke(const Color(0xFFEF4444), 3));
      _softDot(c, const Offset(66, 48), 10, const Color(0x88EF4444));
  }
}

void _bastionShot(Canvas c, int i) {
  const center = Offset(24, 24);
  switch (i) {
    case 0: // arrow
      c.drawLine(const Offset(6, 24), const Offset(38, 24), _stroke(const Color(0xFF8B5A2B), 2.5));
      c.drawPath(_poly(const [Offset(36, 19), Offset(46, 24), Offset(36, 29)]), _fill(const Color(0xFFE5E7EB)));
      c.drawPath(_poly(const [Offset(4, 18), Offset(12, 24), Offset(4, 30), Offset(8, 24)]), _fill(const Color(0xFFF8FAFC)));
    case 1: // cannonball
      _shadow(c, const Offset(26, 30), 20, 8);
      c.drawCircle(center, 9, _radial(center - const Offset(3, 3), 13, const [Color(0xFF9CA3AF), Color(0xFF1F2937)]));
    case 2: // frost shard
      _softDot(c, center, 20, const Color(0xFF38BDF8));
      c.drawPath(_poly(const [Offset(10, 24), Offset(24, 18), Offset(42, 24), Offset(24, 30)]), _fill(const Color(0xFFE0F2FE)));
    case 3: // spark
      _softDot(c, center, 22, const Color(0xFFC4B5FD));
      c.drawCircle(center, 5, _fill(const Color(0xFFFFFFFF)));
  }
}

void _bastionIcon(Canvas c, int i) {
  const center = Offset(32, 32);
  switch (i) {
    case 0: // coin
      c.drawCircle(center + const Offset(0, 3), 24, _fill(const Color(0xFFB45309)));
      c.drawCircle(center, 24, _radial(center - const Offset(8, 8), 34, const [Color(0xFFFEF08A), Color(0xFFF59E0B)]));
      c.drawCircle(center, 16, _stroke(const Color(0xFFD97706), 3));
      c.drawCircle(center - const Offset(8, 8), 4, _fill(const Color(0xAAFFFFFF)));
    case 1: // heart
      final heart = Path()
        ..moveTo(32, 54)
        ..cubicTo(4, 34, 10, 8, 32, 20)
        ..cubicTo(54, 8, 60, 34, 32, 54)
        ..close();
      c.drawPath(heart.shift(const Offset(0, 3)), _fill(const Color(0xFF9F1239)));
      c.drawPath(heart, _linear(const Rect.fromLTWH(8, 10, 48, 44), const [Color(0xFFFDA4AF), Color(0xFFE11D48)]));
      c.drawCircle(const Offset(22, 24), 4, _fill(const Color(0x99FFFFFF)));
    case 3 || 4: // star, filled or empty
      final star = _poly([for (var k = 0; k < 10; k++) center + Offset(math.cos(k * math.pi / 5 - math.pi / 2), math.sin(k * math.pi / 5 - math.pi / 2)) * (k.isEven ? 28 : 12)]);
      if (i == 3) {
        c.drawPath(star.shift(const Offset(0, 3)), _fill(const Color(0xFFB45309)));
        c.drawPath(star, _linear(const Rect.fromLTWH(4, 4, 56, 56), const [Color(0xFFFEF08A), Color(0xFFF59E0B)]));
      } else {
        c.drawPath(star, _fill(const Color(0x55000000)));
        c.drawPath(star, _stroke(const Color(0x88FFFFFF), 2));
      }
    case 2: // banner (waves)
      c.drawLine(const Offset(18, 8), const Offset(18, 58), _stroke(const Color(0xFF78350F), 4));
      c.drawPath(_poly(const [Offset(20, 10), Offset(54, 16), Offset(46, 26), Offset(54, 36), Offset(20, 34)]),
          _linear(const Rect.fromLTWH(20, 10, 34, 26), const [Color(0xFFF87171), Color(0xFFB91C1C)]));
  }
}

void _bastionPanel(Canvas c) {
  const r = Rect.fromLTWH(24, 24, 792, 472);
  final rr = RRect.fromRectAndRadius(r, const Radius.circular(36));
  c.drawRRect(rr.shift(const Offset(0, 10)), _glow(const Color(0x88000000), 18));
  c.drawRRect(rr, _linear(r, const [Color(0xF2213A2A), Color(0xF2122017)]));
  c.drawRRect(rr.deflate(1), _stroke(const Color(0x33FFFFFF), 1));
  c.drawRRect(rr, _stroke(const Color(0xFFFBBF24), 2.5));
}

// --- Music -----------------------------------------------------------------------

/// A warm loop in D major: plucked arpeggios over a soft pad, light drums.
List<double> _bastionTheme() {
  const bpm = 100.0;
  const beat = 60 / bpm;
  const bars = 16;
  final out = List<double>.filled((bars * 4 * beat * _rate).round(), 0);
  const chords = [[62, 66, 69], [59, 62, 66], [55, 59, 62], [57, 61, 64]]; // D Bm G A
  final pluck = List<double>.filled(out.length, 0);
  for (var bar = 0; bar < bars; bar++) {
    final chord = chords[(bar ~/ 2) % 4];
    final t0 = bar * 4 * beat;
    for (final n in chord) {
      _synthNote(out, t0, 4 * beat - 0.05, _hz(n - 12), voices: 3, detune: 0.008, bright: 1200, dark: 600, gain: 0.06, a: 0.5, d: 0.6, s: 0.8, r: 0.4);
    }
    for (var k = 0; k < 4; k++) {
      _synthNote(out, t0 + k * beat, beat * 0.9, _hz(chord[0] - 24), voices: 2, detune: 0.004, bright: 700, dark: 200, gain: 0.22, a: 0.005, d: 0.2, s: 0.4, r: 0.1);
    }
    if (bar >= 2) {
      final pattern = [chord[0], chord[1], chord[2], chord[1] + 12, chord[2], chord[1], chord[0] + 12, chord[2]];
      for (var k = 0; k < 8; k++) {
        _synthNote(pluck, t0 + k * beat / 2, beat / 2, _hz(pattern[k] + 12), voices: 1, bright: 3200, dark: 500, gain: 0.1, a: 0.002, d: 0.18, s: 0.0, r: 0.05);
      }
    }
    if (bar >= 4) {
      for (var k = 0; k < 4; k++) {
        if (k == 0 || k == 2) _kick(out, t0 + k * beat, gain: 0.55);
        if (k == 1 || k == 3) _snare(out, t0 + k * beat, gain: 0.25);
        _hat(out, t0 + k * beat + beat / 2, gain: 0.06);
      }
    }
  }
  _delay(pluck, beat * 0.75, 0.3, 0.5);
  for (var i = 0; i < out.length; i++) {
    out[i] += pluck[i];
  }
  return _master(out);
}

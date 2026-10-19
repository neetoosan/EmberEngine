part of 'paint_art_test.dart';

// Ember Depths: a dungeon roguelike. Stone floors and raised walls (16
// pieces for auto-tiling), a hero, monsters, chests, stairs and relics, in a
// soft modern style meant to be lit by Light 2D in the dark.

const _depths = 'depths';

Future<void> _paintDepths() async {
  // Tileset: 64px cells (shown at 32), 8 columns. Tile id n uses cell n-1:
  // 1 wall (before auto-tiling), 2 floor, 3-5 floor variants, 10-25 wall pieces.
  await _sheet(_depths, 'tiles.png', 64, 64, 32, (c, i) {
    final id = i + 1;
    if (id == 1) _depthsWall(c, 15);
    if (id >= 2 && id <= 5) _depthsFloor(c, id - 2);
    if (id >= 10 && id <= 25) _depthsWall(c, id - 10);
  }, columns: 8);
  await _png(_depths, 'hero.png', 128, 128, _depthsHero);
  await _sheet(_depths, 'monsters.png', 128, 128, 4, _depthsMonster);
  await _sheet(_depths, 'props.png', 128, 128, 4, _depthsProp);
  await _sheet(_depths, 'items.png', 64, 64, 8, _depthsItem);
  await _sheet(_depths, 'shots.png', 64, 64, 3, _depthsShot);
  await _png(_depths, 'arrow.png', 48, 16, (c) {
    c.drawLine(const Offset(4, 8), const Offset(36, 8), _stroke(const Color(0xFFD6D3D1), 2.5));
    c.drawPath(_poly(const [Offset(34, 3), Offset(46, 8), Offset(34, 13)]), _fill(const Color(0xFFF87171)));
    _softDot(c, const Offset(40, 8), 10, const Color(0x88F87171));
  });
  await _sheet(_depths, 'icons.png', 64, 64, 4, _depthsIcon);
  await _png(_depths, 'panel.png', 840, 520, (c) {
    const r = Rect.fromLTWH(24, 24, 792, 472);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(36));
    c.drawRRect(rr, _glow(const Color(0x66F97316), 18));
    c.drawRRect(rr, _linear(r, const [Color(0xF01C1526), Color(0xF00D0A14)]));
    c.drawRRect(rr.deflate(1), _stroke(const Color(0x22FFFFFF), 1));
    c.drawRRect(rr, _stroke(const Color(0xFFF97316), 2.5));
  });

  _writeWav(_depths, 'depths.wav', _depthsTheme());
  _writeWav(_depths, 'cast.wav', _effect(0.22, (t) {
    final f = 700 + 900 * math.exp(-t * 20);
    return math.sin(2 * math.pi * f * t) * math.exp(-t * 16) * 0.5 + _noise() * math.exp(-t * 40) * 0.15;
  }, peak: 0.35));
  final hitLp = _LowPass();
  _writeWav(_depths, 'hit.wav', _effect(0.2, (t) => hitLp.process(_noise(), 2500) * math.exp(-t * 25) + math.sin(2 * math.pi * 160 * t) * math.exp(-t * 30), peak: 0.5));
  _writeWav(_depths, 'hurt.wav', _effect(0.45, (t) {
    final f = 300 * math.exp(-t * 3);
    return (((f * t) % 1) * 2 - 1) * math.exp(-t * 7) * 0.6;
  }, peak: 0.6));
  _writeWav(_depths, 'chest.wav', _effect(0.9, (t) {
    var v = 0.0;
    for (final (n, at) in [(72, 0.0), (76, 0.1), (79, 0.2), (84, 0.3)]) {
      if (t > at) v += math.sin(2 * math.pi * _hz(n) * t) * math.exp(-(t - at) * 5);
    }
    return v * 0.4;
  }, peak: 0.5));
  _writeWav(_depths, 'coin.wav', _effect(0.25, (t) => math.sin(2 * math.pi * (t < 0.05 ? 1568 : 2093) * t) * math.exp(-t * 15) * 0.5, peak: 0.3));
  final stairLp = _LowPass();
  _writeWav(_depths, 'stairs.wav', _effect(1.2, (t) {
    final sweep = stairLp.process(_noise(), 200 + 2000 * math.exp(-t * 3));
    return sweep * math.exp(-t * 2) + math.sin(2 * math.pi * (110 - 50 * t) * t) * math.exp(-t * 2.5) * 0.5;
  }, peak: 0.55));
  _writeWav(_depths, 'dash.wav', _effect(0.3, (t) {
    final lp = 1 - t / 0.3;
    return _noise() * lp * lp * 0.6;
  }, peak: 0.4));
  _writeWav(_depths, 'die.wav', _effect(1.6, (t) {
    final f = 220 * math.exp(-t * 1.2);
    return (math.sin(2 * math.pi * f * t) + 0.3 * math.sin(2 * math.pi * f * 1.5 * t)) * math.exp(-t * 1.5) * 0.6;
  }, peak: 0.6));
}

// --- Tiles ----------------------------------------------------------------------

/// Floor stones: [variant] 0 plain, 1 cracked, 2 mossy, 3 a faint rune.
void _depthsFloor(Canvas c, int variant) {
  const r = Rect.fromLTWH(0, 0, 64, 64);
  c.drawRect(r, _fill(const Color(0xFF221D2B)));
  final rng = math.Random(17 + variant);
  // Four slabs with slightly different shades and soft bevels
  for (final s in [const Rect.fromLTWH(1, 1, 30, 30), const Rect.fromLTWH(33, 1, 30, 30), const Rect.fromLTWH(1, 33, 30, 30), const Rect.fromLTWH(33, 33, 30, 30)]) {
    final shade = 0.85 + rng.nextDouble() * 0.3;
    final base = Color.fromRGBO((58 * shade).round(), (52 * shade).round(), (70 * shade).round(), 1);
    final rr = RRect.fromRectAndRadius(s, const Radius.circular(4));
    c.drawRRect(rr, _linear(s, [Color.lerp(base, const Color(0xFFFFFFFF), 0.08)!, base, Color.lerp(base, const Color(0xFF000000), 0.25)!], begin: Alignment.topLeft, end: Alignment.bottomRight));
  }
  if (variant == 1) {
    c.drawPath(
        Path()
          ..moveTo(10, 14)
          ..lineTo(22, 26)
          ..lineTo(20, 40)
          ..lineTo(34, 50),
        _stroke(const Color(0xAA120E18), 1.6));
  }
  if (variant == 2) {
    for (var k = 0; k < 7; k++) {
      c.drawCircle(Offset(8 + rng.nextDouble() * 48, 8 + rng.nextDouble() * 48), 3 + rng.nextDouble() * 5, _glow(const Color(0x664D7C0F), 2));
    }
  }
  if (variant == 3) {
    c.drawCircle(const Offset(32, 32), 13, _stroke(const Color(0x55F97316), 1.5));
    c.drawPath(_poly(const [Offset(32, 22), Offset(40, 36), Offset(24, 36)]), _stroke(const Color(0x66F97316), 1.5));
  }
}

/// A wall block seen from above at an angle. [mask]: 1 wall above, 2 right,
/// 4 below, 8 left. Sides facing floor get a lit rim; a wall with floor below
/// shows its front face (bricks), which gives the rooms depth.
void _depthsWall(Canvas c, int mask) {
  const r = Rect.fromLTWH(0, 0, 64, 64);
  final up = mask & 1 != 0, right = mask & 2 != 0, down = mask & 4 != 0, left = mask & 8 != 0;
  // Top of the wall
  final topBottom = down ? 64.0 : 34.0;
  final top = Rect.fromLTRB(0, 0, 64, topBottom);
  c.drawRect(top, _linear(top, const [Color(0xFF4A4060), Color(0xFF362E48)]));
  // Soft noise on the top
  final rng = math.Random(mask * 7 + 3);
  for (var k = 0; k < 10; k++) {
    c.drawCircle(Offset(rng.nextDouble() * 64, rng.nextDouble() * topBottom), 2 + rng.nextDouble() * 4, _fill(const Color(0x14FFFFFF)));
  }
  // Lit rims where the wall meets the floor
  const rim = Color(0xFF6E6290);
  if (!up) c.drawLine(const Offset(0, 1.5), const Offset(64, 1.5), _stroke(rim, 3));
  if (!left) c.drawLine(Offset(1.5, 0), Offset(1.5, topBottom), _stroke(rim, 3));
  if (!right) c.drawLine(Offset(62.5, 0), Offset(62.5, topBottom), _stroke(const Color(0xFF2A2338), 3));
  if (!down) {
    // Front face: bricks, darker toward the floor, with a shadow line at the foot
    final face = Rect.fromLTRB(0, topBottom, 64, 64);
    c.drawRect(face, _linear(face, const [Color(0xFF5B4E70), Color(0xFF2B2438)]));
    c.drawLine(Offset(0, topBottom), Offset(64, topBottom), _stroke(const Color(0xFF7C6F98), 2));
    for (final (y, offset) in [(topBottom + 10.0, 0.0), (topBottom + 20.0, 16.0)]) {
      c.drawLine(Offset(0, y), Offset(64, y), _stroke(const Color(0x55120E18), 1.5));
      for (var x = offset; x < 64; x += 32) {
        c.drawLine(Offset(x, y - 10), Offset(x, y), _stroke(const Color(0x44120E18), 1.5));
      }
    }
    c.drawRect(Rect.fromLTRB(0, 60, 64, 64), _fill(const Color(0x66000000)));
  }
  c.drawRect(r, _stroke(const Color(0x10000000), 1));
}

// --- Characters --------------------------------------------------------------------

void _depthsHero(Canvas c) {
  // A small mage in a hooded robe with a glowing staff (faces right)
  _shadow(c, const Offset(64, 112), 56, 16);
  final robe = Path()
    ..moveTo(64, 40)
    ..quadraticBezierTo(92, 62, 90, 108)
    ..lineTo(38, 108)
    ..quadraticBezierTo(36, 62, 64, 40)
    ..close();
  c.drawPath(robe, _linear(const Rect.fromLTWH(36, 40, 56, 68), const [Color(0xFF3B82F6), Color(0xFF1E3A8A)], begin: Alignment.topLeft, end: Alignment.bottomRight));
  c.drawPath(_poly(const [Offset(60, 64), Offset(68, 64), Offset(70, 108), Offset(58, 108)]), _fill(const Color(0xFFF97316)));
  // Hood and face
  c.drawCircle(const Offset(64, 40), 22, _radial(const Offset(58, 32), 30, const [Color(0xFF60A5FA), Color(0xFF1E40AF)]));
  c.drawOval(Rect.fromCenter(center: const Offset(70, 44), width: 24, height: 20), _fill(const Color(0xFF0F172A)));
  c.drawCircle(const Offset(74, 43), 2.6, _fill(const Color(0xFFFDE68A)));
  c.drawCircle(const Offset(66, 43), 2.6, _fill(const Color(0xFFFDE68A)));
  // Staff
  c.drawLine(const Offset(96, 50), const Offset(90, 112), _stroke(const Color(0xFF8B5A2B), 4));
  _softDot(c, const Offset(97, 44), 22, const Color(0xFFF97316), core: 0.2);
  c.drawCircle(const Offset(97, 44), 6, _fill(const Color(0xFFFFEDD5)));
}

void _depthsMonster(Canvas c, int i) {
  switch (i) {
    case 0: // slime: a glossy teal blob
      _shadow(c, const Offset(64, 106), 76, 18);
      final body = Path()
        ..moveTo(26, 104)
        ..quadraticBezierTo(22, 52, 64, 46)
        ..quadraticBezierTo(106, 52, 102, 104)
        ..close();
      c.drawPath(body, _linear(const Rect.fromLTWH(22, 46, 80, 58), const [Color(0xFF5EEAD4), Color(0xFF0F766E)]));
      c.drawOval(const Rect.fromLTWH(40, 56, 22, 12), _fill(const Color(0x88FFFFFF)));
      for (final x in [56.0, 76.0]) {
        c.drawCircle(Offset(x, 80), 6, _fill(const Color(0xFF042F2E)));
        c.drawCircle(Offset(x + 1.5, 78), 2, _fill(const Color(0xFFFFFFFF)));
      }
    case 1: // skeleton archer
      _shadow(c, const Offset(64, 112), 50, 14);
      for (final x in [54.0, 74.0]) {
        c.drawLine(Offset(x, 88), Offset(x, 110), _stroke(const Color(0xFFE7E5E4), 5));
      }
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(48, 56, 32, 34), const Radius.circular(8)), _fill(const Color(0xFF57534E)));
      for (var k = 0; k < 3; k++) {
        c.drawLine(Offset(52, 62.0 + k * 9), Offset(76, 62.0 + k * 9), _stroke(const Color(0xFFE7E5E4), 3));
      }
      c.drawCircle(const Offset(64, 40), 18, _radial(const Offset(58, 34), 24, const [Color(0xFFFFFFFF), Color(0xFFD6D3D1)]));
      for (final x in [58.0, 72.0]) {
        c.drawCircle(Offset(x, 40), 4.5, _fill(const Color(0xFF1C1917)));
        _softDot(c, Offset(x, 40), 5, const Color(0xAAF87171));
      }
      final bow = Path()
        ..moveTo(92, 44)
        ..quadraticBezierTo(108, 72, 92, 100);
      c.drawPath(bow, _stroke(const Color(0xFF92400E), 4));
      c.drawLine(const Offset(92, 44), const Offset(92, 100), _stroke(const Color(0xCCFFFFFF), 1));
    case 2: // bat
      _shadow(c, const Offset(64, 108), 40, 10);
      for (final s in [-1.0, 1.0]) {
        final wing = _poly([const Offset(64, 60), Offset(64 + s * 50, 40), Offset(64 + s * 44, 62), Offset(64 + s * 50, 78), Offset(64 + s * 20, 70)]);
        c.drawPath(wing, _linear(const Rect.fromLTWH(14, 40, 100, 40), const [Color(0xFF7C3AED), Color(0xFF3B0764)]));
      }
      c.drawCircle(const Offset(64, 62), 14, _radial(const Offset(60, 58), 18, const [Color(0xFFA78BFA), Color(0xFF4C1D95)]));
      for (final x in [59.0, 69.0]) {
        _softDot(c, Offset(x, 60), 5, const Color(0xFFFDE047));
      }
    case 3: // the warden: a big armoured knight of embers
      _shadow(c, const Offset(64, 114), 90, 18);
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 50, 68, 60), const Radius.circular(18)),
          _linear(const Rect.fromLTWH(30, 50, 68, 60), const [Color(0xFF78716C), Color(0xFF292524)]));
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(44, 64, 40, 30), const Radius.circular(8)), _fill(const Color(0xFF1C1917)));
      _softDot(c, const Offset(64, 79), 22, const Color(0xFFF97316));
      c.drawCircle(const Offset(64, 36), 22, _radial(const Offset(58, 30), 30, const [Color(0xFFA8A29E), Color(0xFF44403C)]));
      c.drawRect(const Rect.fromLTWH(50, 32, 28, 6), _fill(const Color(0xFF0C0A09)));
      _softDot(c, const Offset(64, 35), 12, const Color(0xFFFB923C));
      for (final x in [26.0, 102.0]) {
        c.drawCircle(Offset(x, 60), 12, _radial(Offset(x - 3, 56), 16, const [Color(0xFFA8A29E), Color(0xFF44403C)]));
      }
  }
}

void _depthsProp(Canvas c, int i) {
  switch (i) {
    case 0 || 1: // chest, closed / open
      _shadow(c, const Offset(64, 104), 84, 18);
      const box = Rect.fromLTWH(26, 56, 76, 46);
      c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(6)), _linear(box, const [Color(0xFFB45309), Color(0xFF78350F)]));
      for (final x in [36.0, 92.0]) {
        c.drawRect(Rect.fromLTWH(x - 3, 56, 6, 46), _fill(const Color(0xFFFBBF24)));
      }
      if (i == 0) {
        final lid = Rect.fromLTWH(24, 34, 80, 26);
        c.drawRRect(RRect.fromRectAndCorners(lid, topLeft: const Radius.circular(18), topRight: const Radius.circular(18)),
            _linear(lid, const [Color(0xFFD97706), Color(0xFF92400E)]));
        c.drawRect(const Rect.fromLTWH(58, 52, 12, 14), _fill(const Color(0xFFFDE68A)));
      } else {
        _softDot(c, const Offset(64, 54), 44, const Color(0xCCFDE68A), core: 0.2);
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(24, 20, 80, 14), const Radius.circular(6)), _fill(const Color(0xFF92400E)));
        c.drawRect(const Rect.fromLTWH(30, 58, 68, 8), _fill(const Color(0xFF1C1917)));
      }
    case 2: // stairs down: a glowing pit with steps
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(14, 14, 100, 100), const Radius.circular(18)), _fill(const Color(0xFF0B0812)));
      for (var k = 0; k < 5; k++) {
        final inset = 16.0 + k * 9;
        final rr = RRect.fromRectAndRadius(Rect.fromLTRB(inset, inset, 128 - inset, 128 - inset), const Radius.circular(12));
        c.drawRRect(rr, _stroke(Color.lerp(const Color(0xFF6E6290), const Color(0xFF1C1526), k / 5)!, 7));
      }
      _softDot(c, const Offset(64, 64), 34, const Color(0xAAF97316), core: 0.1);
    case 3: // wall torch
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(56, 70, 16, 34), const Radius.circular(4)), _fill(const Color(0xFF57534E)));
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(50, 62, 28, 12), const Radius.circular(4)), _fill(const Color(0xFF78716C)));
      final flame = Path()
        ..moveTo(64, 22)
        ..quadraticBezierTo(82, 46, 64, 64)
        ..quadraticBezierTo(46, 46, 64, 22)
        ..close();
      c.drawPath(flame, _glow(const Color(0xFFF97316), 6));
      c.drawPath(flame, _linear(const Rect.fromLTWH(46, 22, 36, 42), const [Color(0xFFFEF08A), Color(0xFFF97316)]));
  }
}

void _depthsItem(Canvas c, int i) {
  const center = Offset(32, 32);
  if (i == 0) {
    _bastionIcon(c, 1); // heart
    return;
  }
  if (i == 1) {
    _bastionIcon(c, 0); // coin
    return;
  }
  // Relics: glowing orbs in the colour of what they do
  const colors = [Color(0xFFEF4444), Color(0xFF22D3EE), Color(0xFFA855F7), Color(0xFFF472B6), Color(0xFF4ADE80), Color(0xFFFBBF24)];
  final color = colors[i - 2];
  _softDot(c, center, 30, color.withValues(alpha: 0.8), core: 0.15);
  c.drawCircle(center, 14, _radial(center - const Offset(5, 5), 20, [const Color(0xFFFFFFFF), color, Color.lerp(color, const Color(0xFF000000), 0.4)!]));
  c.drawCircle(center - const Offset(5, 5), 4, _fill(const Color(0xCCFFFFFF)));
}

void _depthsShot(Canvas c, int i) {
  const center = Offset(32, 32);
  final color = [const Color(0xFFF97316), const Color(0xFF22D3EE), const Color(0xFFEF4444)][i];
  _softDot(c, center, 28, color, core: 0.15);
  c.drawCircle(center, 8, _fill(const Color(0xFFFFFFFF)));
}

void _depthsIcon(Canvas c, int i) {
  if (i <= 1) {
    _bastionIcon(c, i == 0 ? 1 : 0); // heart, coin
    if (i == 0) return;
    return;
  }
  if (i == 2) {
    // empty heart
    final heart = Path()
      ..moveTo(32, 54)
      ..cubicTo(4, 34, 10, 8, 32, 20)
      ..cubicTo(54, 8, 60, 34, 32, 54)
      ..close();
    c.drawPath(heart, _fill(const Color(0x66000000)));
    c.drawPath(heart, _stroke(const Color(0x99FECDD3), 2.5));
    return;
  }
  // stairs icon (floor)
  for (var k = 0; k < 4; k++) {
    c.drawRect(Rect.fromLTWH(10.0 + k * 11, 14.0 + k * 10, 44.0 - k * 11, 10), _fill(Color.lerp(const Color(0xFFD6D3D1), const Color(0xFF57534E), k / 4)!));
  }
}

// --- Music -----------------------------------------------------------------------

/// A dark, steady loop in E minor: low drones, a ticking arp, soft drums.
List<double> _depthsTheme() {
  const bpm = 92.0;
  const beat = 60 / bpm;
  const bars = 16;
  final out = List<double>.filled((bars * 4 * beat * _rate).round(), 0);
  const chords = [[52, 55, 59], [48, 52, 55], [50, 53, 57], [47, 51, 54]]; // Em C Dm B
  final arp = List<double>.filled(out.length, 0);
  for (var bar = 0; bar < bars; bar++) {
    final chord = chords[(bar ~/ 2) % 4];
    final t0 = bar * 4 * beat;
    for (final n in chord) {
      _synthNote(out, t0, 4 * beat, _hz(n - 12), voices: 4, detune: 0.012, bright: 900, dark: 400, gain: 0.07, a: 0.8, d: 0.5, s: 0.9, r: 0.6);
    }
    _synthNote(out, t0, 4 * beat - 0.1, _hz(chord[0] - 24), voices: 2, detune: 0.004, bright: 500, dark: 160, gain: 0.25, a: 0.05, d: 0.5, s: 0.7, r: 0.3);
    if (bar >= 2) {
      final pattern = [chord[0], chord[2], chord[1] + 12, chord[2]];
      for (var k = 0; k < 8; k++) {
        _synthNote(arp, t0 + k * beat / 2, beat / 2, _hz(pattern[k % 4] + 12), voices: 1, bright: 2400, dark: 500, gain: 0.07, a: 0.002, d: 0.15, s: 0.0, r: 0.05);
      }
    }
    if (bar >= 4) {
      for (var k = 0; k < 4; k++) {
        if (k == 0 || k == 2) _kick(out, t0 + k * beat, gain: 0.5);
        if (k == 3) _snare(out, t0 + k * beat, gain: 0.18);
        _hat(out, t0 + k * beat + beat / 2, gain: 0.04);
      }
    }
  }
  _delay(arp, beat * 0.75, 0.45, 0.55);
  for (var i = 0; i < out.length; i++) {
    out[i] += arp[i];
  }
  return _master(out);
}

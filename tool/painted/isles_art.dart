part of 'paint_art_test.dart';

// Ember Isles: an isometric colony builder. Flat, softly shaded diamond tiles
// (water, sand, grass), low-poly trees, rocks and buildings that stand on a
// diamond footprint, guards and raiders, and a calm building theme.

const _isles = 'isles';

/// The diamond footprint (128 × 64) at the bottom of a 128 × [h] cell.
Path _diamond(double h, {double inset = 0}) => _poly([
      Offset(64, h - 64 + inset),
      Offset(128 - inset * 2, h - 32),
      Offset(64, h - inset),
      Offset(inset * 2, h - 32),
    ]);

Future<void> _paintIsles() async {
  // Ground tiles, 128 × 64 each, 8 columns: 1 water, 2 deep water, 3 sand, 4 grass, 5 grass, 6 flowers
  await _sheet(_isles, 'tiles.png', 128, 64, 8, (c, i) {
    if (i < 6) _islesTile(c, i);
  }, columns: 8);
  // Things that stand on a cell, 128 × 160 each
  await _sheet(_isles, 'objects.png', 128, 160, 12, _islesObject, columns: 6);
  await _sheet(_isles, 'units.png', 64, 64, 4, _islesUnit);
  await _sheet(_isles, 'icons.png', 64, 64, 6, _islesIcon);
  await _png(_isles, 'ring.png', 128, 64, (c) {
    c.drawOval(const Rect.fromLTWH(8, 8, 112, 48), _stroke(const Color(0xFFFFFFFF), 5));
    c.drawOval(const Rect.fromLTWH(8, 8, 112, 48), _stroke(const Color(0x88FFFFFF), 10, blur: 4));
  });
  await _png(_isles, 'cell.png', 128, 64, (c) {
    c.drawPath(_diamond(64, inset: 3), _fill(const Color(0x33FFFFFF)));
    c.drawPath(_diamond(64, inset: 3), _stroke(const Color(0xEEFFFFFF), 3));
  });
  await _png(_isles, 'arrow.png', 48, 16, (c) {
    c.drawLine(const Offset(4, 8), const Offset(38, 8), _stroke(const Color(0xFF8B5A2B), 2.5));
    c.drawPath(_poly(const [Offset(36, 3), Offset(46, 8), Offset(36, 13)]), _fill(const Color(0xFFE5E7EB)));
  });
  await _png(_isles, 'panel.png', 840, 520, _bastionPanel);

  _writeWav(_isles, 'isles.wav', _islesTheme());
  _writeWav(_isles, 'build.wav', _effect(0.5, (t) {
    final thunk = math.sin(2 * math.pi * (110 + 140 * math.exp(-t * 30)) * t) * math.exp(-t * 16);
    return thunk + (t > 0.1 ? math.sin(2 * math.pi * 988 * t) * math.exp(-(t - 0.1) * 10) * 0.35 : 0.0);
  }, peak: 0.55));
  _writeWav(_isles, 'horn.wav', _effect(1.8, (t) {
    var v = 0.0;
    for (final n in [45, 52]) {
      v += ((_hz(n) * t) % 1 * 2 - 1) * 0.35;
    }
    return v * math.min(1, t * 4) * math.exp(-math.max(0, t - 1.2) * 5);
  }, peak: 0.55));
  final clashLp = _LowPass();
  _writeWav(_isles, 'clash.wav', _effect(0.25, (t) => (clashLp.process(_noise(), 6000) * 0.5 + math.sin(2 * math.pi * 1900 * t) * 0.3) * math.exp(-t * 18), peak: 0.4));
  _writeWav(_isles, 'arrow.wav', _effect(0.18, (t) => math.sin(2 * math.pi * (900 * math.exp(-t * 18) + 300) * t) * math.exp(-t * 30) * 0.6, peak: 0.4));
  _writeWav(_isles, 'select.wav', _effect(0.12, (t) => math.sin(2 * math.pi * 1320 * t) * math.exp(-t * 30) * 0.5, peak: 0.3));
  _writeWav(_isles, 'win.wav', _effect(2.0, (t) {
    var v = 0.0;
    for (final (n, at) in [(60, 0.0), (64, 0.15), (67, 0.3), (72, 0.45), (76, 0.7)]) {
      if (t > at) v += math.sin(2 * math.pi * _hz(n) * t) * math.exp(-(t - at) * 2.5);
    }
    return v * 0.35;
  }, peak: 0.6));
  _writeWav(_isles, 'lose.wav', _effect(1.6, (t) => math.sin(2 * math.pi * _hz(t < 0.5 ? 57 : (t < 1.0 ? 53 : 50)) * t) * math.exp(-t * 1.2) * 0.5, peak: 0.55));
}

void _islesTile(Canvas c, int i) {
  final shape = _diamond(64);
  final colors = const [
    [Color(0xFF7DD3FC), Color(0xFF38BDF8)], // water
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // deep water
    [Color(0xFFFDE7B0), Color(0xFFF2CC80)], // sand
    [Color(0xFF9BE36D), Color(0xFF6BC34A)], // grass
    [Color(0xFF8FD964), Color(0xFF5DB13E)], // grass, darker
    [Color(0xFF9BE36D), Color(0xFF6BC34A)], // grass with flowers
  ][i];
  c.drawPath(shape, _linear(const Rect.fromLTWH(0, 0, 128, 64), colors, begin: Alignment.topLeft, end: Alignment.bottomRight));
  // Soft light on the upper edges, shade on the lower
  c.drawPath(
      Path()
        ..moveTo(2, 32)
        ..lineTo(64, 1)
        ..lineTo(126, 32),
      _stroke(const Color(0x40FFFFFF), 2));
  c.drawPath(
      Path()
        ..moveTo(2, 32)
        ..lineTo(64, 63)
        ..lineTo(126, 32),
      _stroke(const Color(0x26000000), 2));
  final rng = math.Random(i * 7 + 1);
  if (i <= 1) {
    for (var k = 0; k < 3; k++) {
      final x = 34 + rng.nextDouble() * 60, y = 22 + rng.nextDouble() * 20;
      c.drawLine(Offset(x - 8, y), Offset(x + 8, y), _stroke(const Color(0x66FFFFFF), 2));
    }
  }
  if (i == 5) {
    for (var k = 0; k < 6; k++) {
      final at = Offset(30 + rng.nextDouble() * 68, 18 + rng.nextDouble() * 28);
      c.drawCircle(at, 2.6, _fill([const Color(0xFFFDE68A), const Color(0xFFFBCFE8), const Color(0xFFFFFFFF)][k % 3]));
    }
  }
}

/// Low-poly box: a top face and two lit sides, standing on the cell's footprint.
void _isoBox(Canvas c, double w, double d, double h, Color top, Color left, Color right, {double baseY = 144}) {
  // w/d are half-sizes along the diamond's axes (in pixels at the footprint)
  final b = Offset(64, baseY); // bottom corner of the footprint
  final lPt = Offset(64 - w, baseY - w / 2), rPt = Offset(64 + d, baseY - d / 2), back = Offset(64 - w + d, baseY - (w + d) / 2);
  final up = Offset(0, -h);
  c.drawPath(_poly([lPt, b, b + up, lPt + up]), _fill(left));
  c.drawPath(_poly([b, rPt, rPt + up, b + up]), _fill(right));
  c.drawPath(_poly([lPt + up, b + up, rPt + up, back + up]), _fill(top));
}

/// 0 round tree, 1 pine, 2 rock, 3 town hall, 4 house, 5 farm, 6 lumber camp,
/// 7 quarry, 8 watchtower, 9 the Ember Beacon, 10 boat, 11 ruin (a destroyed building).
void _islesObject(Canvas c, int i) {
  const footY = 128.0; // centre of the footprint diamond
  c.drawOval(Rect.fromCenter(center: const Offset(64, footY + 4), width: 76, height: 30), _glow(const Color(0x44173016), 4));
  switch (i) {
    case 0:
      c.drawRect(const Rect.fromLTWH(60, 100, 8, 30), _fill(const Color(0xFF8B5A2B)));
      for (final (o, r) in [(const Offset(52, 86), 20.0), (const Offset(76, 84), 20.0), (const Offset(64, 68), 24.0)]) {
        c.drawCircle(o, r, _radial(o - const Offset(6, 8), r * 1.6, const [Color(0xFF86EFAC), Color(0xFF22A34A)]));
      }
    case 1:
      c.drawRect(const Rect.fromLTWH(60, 110, 8, 22), _fill(const Color(0xFF7C4A21)));
      for (final (y, w) in [(112.0, 30.0), (90.0, 24.0), (70.0, 17.0)]) {
        c.drawPath(_poly([Offset(64, y - w * 1.3), Offset(64 + w, y), Offset(64 - w, y)]),
            _linear(Rect.fromLTWH(64 - w, y - w * 1.3, w * 2, w * 1.3), const [Color(0xFF4ADE80), Color(0xFF166534)], begin: Alignment.topLeft, end: Alignment.bottomRight));
      }
    case 2:
      c.drawPath(_poly(const [Offset(34, 130), Offset(42, 104), Offset(62, 92), Offset(86, 98), Offset(96, 122), Offset(80, 136), Offset(48, 138)]),
          _linear(const Rect.fromLTWH(34, 92, 62, 46), const [Color(0xFFE7E5E4), Color(0xFF9CA3AF), Color(0xFF6B7280)]));
      c.drawPath(_poly(const [Offset(46, 106), Offset(62, 94), Offset(70, 104), Offset(54, 114)]), _fill(const Color(0x55FFFFFF)));
    case 3: // town hall
      _isoBox(c, 44, 44, 40, const Color(0xFFFFF7ED), const Color(0xFFE7D7C1), const Color(0xFFC9B79E));
      c.drawPath(_poly(const [Offset(20, 82), Offset(64, 40), Offset(108, 82), Offset(64, 104)]), _fill(const Color(0xFFDC2626)));
      c.drawPath(_poly(const [Offset(64, 40), Offset(108, 82), Offset(64, 104)]), _fill(const Color(0xFFB91C1C)));
      c.drawLine(const Offset(64, 40), const Offset(64, 18), _stroke(const Color(0xFF78350F), 2.5));
      c.drawPath(_poly(const [Offset(64, 18), Offset(82, 23), Offset(64, 28)]), _fill(const Color(0xFFF97316)));
      c.drawRect(const Rect.fromLTWH(56, 118, 12, 18), _fill(const Color(0xFF78350F)));
    case 4: // house
      _isoBox(c, 30, 30, 26, const Color(0xFFFFFBEB), const Color(0xFFF5E6C8), const Color(0xFFDCC7A1));
      c.drawPath(_poly(const [Offset(32, 102), Offset(64, 70), Offset(96, 102), Offset(64, 118)]), _fill(const Color(0xFF2563EB)));
      c.drawPath(_poly(const [Offset(64, 70), Offset(96, 102), Offset(64, 118)]), _fill(const Color(0xFF1D4ED8)));
      c.drawRect(const Rect.fromLTWH(74, 122, 8, 12), _fill(const Color(0xFF78350F)));
    case 5: // farm: crop rows and a small shed
      for (var k = 0; k < 4; k++) {
        final y = 112.0 + k * 7;
        c.drawLine(Offset(30 + k * 6, y), Offset(84 + k * 6, y + 6), _stroke(const Color(0xFFEAB308), 5));
      }
      _isoBox(c, 12, 12, 16, const Color(0xFFFCA5A5), const Color(0xFFB91C1C), const Color(0xFF991B1B), baseY: 120);
    case 6: // lumber camp: a log pile and a saw-hut
      _isoBox(c, 22, 18, 20, const Color(0xFFD6A26B), const Color(0xFF9A6B3C), const Color(0xFF7C5230));
      for (var k = 0; k < 3; k++) {
        c.drawCircle(Offset(88.0 + k * 9, 128 - k * 5), 6, _fill(const Color(0xFFB07A44)));
        c.drawCircle(Offset(88.0 + k * 9, 128 - k * 5), 3, _fill(const Color(0xFFE7C493)));
      }
    case 7: // quarry: a crane and stone blocks
      _isoBox(c, 14, 14, 14, const Color(0xFFE5E7EB), const Color(0xFF9CA3AF), const Color(0xFF6B7280), baseY: 136);
      _isoBox(c, 10, 10, 10, const Color(0xFFE5E7EB), const Color(0xFF9CA3AF), const Color(0xFF6B7280), baseY: 120);
      c.drawLine(const Offset(84, 128), const Offset(84, 70), _stroke(const Color(0xFF78350F), 4));
      c.drawLine(const Offset(84, 72), const Offset(54, 84), _stroke(const Color(0xFF78350F), 3));
    case 8: // watchtower
      _isoBox(c, 18, 18, 70, const Color(0xFFE7E5E4), const Color(0xFFA8A29E), const Color(0xFF78716C));
      c.drawPath(_poly(const [Offset(38, 66), Offset(64, 40), Offset(90, 66), Offset(64, 80)]), _fill(const Color(0xFF16A34A)));
      c.drawPath(_poly(const [Offset(64, 40), Offset(90, 66), Offset(64, 80)]), _fill(const Color(0xFF15803D)));
    case 9: // the Ember Beacon: a tall spire with a burning top
      _isoBox(c, 26, 26, 30, const Color(0xFFF5F5F4), const Color(0xFFD6D3D1), const Color(0xFFA8A29E));
      c.drawPath(_poly(const [Offset(46, 100), Offset(64, 20), Offset(82, 100)]),
          _linear(const Rect.fromLTWH(46, 20, 36, 80), const [Color(0xFFF5F5F4), Color(0xFFA8A29E)], begin: Alignment.centerLeft, end: Alignment.centerRight));
      _softDot(c, const Offset(64, 22), 26, const Color(0xFFF97316), core: 0.2);
      c.drawCircle(const Offset(64, 22), 7, _fill(const Color(0xFFFFEDD5)));
    case 10: // boat
      c.drawPath(_poly(const [Offset(26, 116), Offset(102, 116), Offset(88, 136), Offset(40, 136)]), _fill(const Color(0xFF7C2D12)));
      c.drawLine(const Offset(64, 116), const Offset(64, 64), _stroke(const Color(0xFF451A03), 3));
      c.drawPath(_poly(const [Offset(66, 66), Offset(96, 104), Offset(66, 108)]), _fill(const Color(0xFFDC2626)));
    case 11: // ruin
      _isoBox(c, 26, 26, 10, const Color(0xFF78716C), const Color(0xFF57534E), const Color(0xFF44403C));
      for (var k = 0; k < 3; k++) {
        _softDot(c, Offset(54.0 + k * 10, 104 - k * 6), 8, const Color(0x55374151));
      }
  }
}

/// 0 guard, 1 raider, 2 guard (other step), 3 raider (other step).
void _islesUnit(Canvas c, int i) {
  final guard = i.isEven;
  final step = i >= 2 ? 3.0 : -3.0;
  c.drawOval(const Rect.fromLTWH(18, 52, 28, 10), _glow(const Color(0x55000000), 2));
  for (final s in [-1.0, 1.0]) {
    c.drawLine(Offset(32 + s * 5, 44), Offset(32 + s * 5 + s * step * 0.5, 56), _stroke(const Color(0xFF1F2937), 5));
  }
  final body = guard ? const [Color(0xFF60A5FA), Color(0xFF1D4ED8)] : const [Color(0xFFF87171), Color(0xFFB91C1C)];
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 26, 20, 22), const Radius.circular(7)), _linear(const Rect.fromLTWH(22, 26, 20, 22), body));
  c.drawCircle(const Offset(32, 20), 9, _radial(const Offset(29, 17), 12, const [Color(0xFFFDE7C7), Color(0xFFE0A872)]));
  if (guard) {
    c.drawArc(const Rect.fromLTWH(22, 9, 20, 18), 3.3, 2.8, false, _stroke(const Color(0xFF94A3B8), 4));
    c.drawLine(const Offset(46, 12), const Offset(46, 46), _stroke(const Color(0xFFCBD5E1), 3));
  } else {
    c.drawPath(_poly(const [Offset(22, 16), Offset(16, 6), Offset(28, 13)]), _fill(const Color(0xFFE5E7EB)));
    c.drawPath(_poly(const [Offset(42, 16), Offset(48, 6), Offset(36, 13)]), _fill(const Color(0xFFE5E7EB)));
    c.drawLine(const Offset(46, 22), const Offset(54, 40), _stroke(const Color(0xFF78350F), 4));
    c.drawPath(_poly(const [Offset(50, 18), Offset(60, 24), Offset(52, 30)]), _fill(const Color(0xFFD1D5DB)));
  }
}

/// 0 wood, 1 stone, 2 food, 3 people, 4 guard, 5 raid.
void _islesIcon(Canvas c, int i) {
  const center = Offset(32, 32);
  switch (i) {
    case 0:
      for (final (o, a) in [(const Offset(26, 38), -0.4), (const Offset(38, 34), 0.3)]) {
        c.save();
        c.translate(o.dx, o.dy);
        c.rotate(a);
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-18, -6, 36, 12), const Radius.circular(6)), _fill(const Color(0xFFB07A44)));
        c.drawCircle(const Offset(18, 0), 6, _fill(const Color(0xFFE7C493)));
        c.restore();
      }
    case 1:
      c.drawPath(_poly(const [Offset(12, 44), Offset(20, 22), Offset(36, 14), Offset(52, 22), Offset(54, 42), Offset(40, 52), Offset(22, 52)]),
          _linear(const Rect.fromLTWH(12, 14, 42, 38), const [Color(0xFFE5E7EB), Color(0xFF6B7280)]));
    case 2:
      c.drawOval(Rect.fromCenter(center: center + const Offset(0, 4), width: 34, height: 40), _linear(const Rect.fromLTWH(15, 12, 34, 40), const [Color(0xFFFDE047), Color(0xFFEAB308)]));
      for (var k = 0; k < 4; k++) {
        c.drawLine(Offset(24.0 + k * 5, 16), Offset(24.0 + k * 5, 50), _stroke(const Color(0x55A16207), 2));
      }
      c.drawLine(const Offset(32, 12), const Offset(32, 4), _stroke(const Color(0xFF65A30D), 3));
    case 3:
      for (final (x, s) in [(22.0, 0.8), (40.0, 1.0)]) {
        c.drawCircle(Offset(x, 22 + (1 - s) * 10), 8 * s, _fill(const Color(0xFFFDE7C7)));
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 10 * s, 32 + (1 - s) * 8, 20 * s, 22 * s), const Radius.circular(6)), _fill(const Color(0xFF60A5FA)));
      }
    case 4:
      _islesUnit(c, 0);
    case 5:
      c.drawPath(_poly(const [Offset(32, 6), Offset(56, 54), Offset(8, 54)]), _fill(const Color(0xFFEF4444)));
      c.drawRect(const Rect.fromLTWH(29, 22, 6, 18), _fill(const Color(0xFFFFFFFF)));
      c.drawRect(const Rect.fromLTWH(29, 44, 6, 6), _fill(const Color(0xFFFFFFFF)));
  }
}

/// A calm, bright loop in F major for building.
List<double> _islesTheme() {
  const bpm = 96.0;
  const beat = 60 / bpm;
  const bars = 16;
  final out = List<double>.filled((bars * 4 * beat * _rate).round(), 0);
  const chords = [[65, 69, 72], [62, 65, 69], [58, 62, 65], [60, 64, 67]]; // F Dm Bb C
  final pluck = List<double>.filled(out.length, 0);
  for (var bar = 0; bar < bars; bar++) {
    final chord = chords[(bar ~/ 2) % 4];
    final t0 = bar * 4 * beat;
    for (final n in chord) {
      _synthNote(out, t0, 4 * beat, _hz(n - 12), voices: 3, detune: 0.007, bright: 1400, dark: 700, gain: 0.05, a: 0.5, d: 0.6, s: 0.8, r: 0.5);
    }
    for (var k = 0; k < 4; k++) {
      _synthNote(out, t0 + k * beat, beat * 0.8, _hz(chord[0] - 24 + (k == 2 ? 7 : 0)), voices: 2, detune: 0.004, bright: 700, dark: 200, gain: 0.2, a: 0.005, d: 0.2, s: 0.4, r: 0.1);
    }
    if (bar >= 2) {
      final pattern = [chord[0], chord[2], chord[1] + 12, chord[2], chord[0] + 12, chord[2], chord[1] + 12, chord[2] + 12];
      for (var k = 0; k < 8; k++) {
        _synthNote(pluck, t0 + k * beat / 2, beat / 2, _hz(pattern[k] + 12), voices: 1, bright: 3000, dark: 600, gain: 0.08, a: 0.002, d: 0.2, s: 0.0, r: 0.05);
      }
    }
    if (bar >= 4) {
      for (var k = 0; k < 4; k++) {
        if (k == 0) _kick(out, t0 + k * beat, gain: 0.4);
        _hat(out, t0 + k * beat + beat / 2, gain: 0.04);
      }
    }
  }
  _delay(pluck, beat * 0.75, 0.3, 0.45);
  for (var i = 0; i < out.length; i++) {
    out[i] += pluck[i];
  }
  return _master(out);
}

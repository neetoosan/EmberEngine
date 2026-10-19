part of 'paint_art_test.dart';

// Ember Pulse: a four-lane rhythm game. A synthwave horizon, glowing lanes,
// note gems in four colours, and "Neon Drift": the song made from the very
// lead line the charts come from (lib/templates/pulse_song.dart).

const _pulse = 'pulse';
const _laneColors = [Color(0xFF22D3EE), Color(0xFFA855F7), Color(0xFFF472B6), Color(0xFFFB923C)];

Future<void> _paintPulse() async {
  await _png(_pulse, 'bg.png', 960, 540, _pulseBackground);
  await _png(_pulse, 'lane.png', 128, 512, (c) {
    const r = Rect.fromLTWH(0, 0, 128, 512);
    c.drawRect(r, _linear(r, const [Color(0x00FFFFFF), Color(0x22FFFFFF), Color(0x00FFFFFF)], begin: Alignment.centerLeft, end: Alignment.centerRight));
    c.drawRect(r, _linear(r, const [Color(0x000B0420), Color(0x660B0420)]));
    for (final x in [2.0, 126.0]) {
      c.drawLine(Offset(x, 0), Offset(x, 512), _stroke(const Color(0x55FFFFFF), 2));
    }
  });
  await _sheet(_pulse, 'notes.png', 128, 64, 4, (c, i) {
    final color = _laneColors[i];
    final rr = RRect.fromRectAndRadius(const Rect.fromLTWH(14, 18, 100, 28), const Radius.circular(14));
    c.drawRRect(rr.inflate(6), _glow(color, 8));
    c.drawRRect(rr, _linear(rr.outerRect, [Color.lerp(color, const Color(0xFFFFFFFF), 0.6)!, color]));
    c.drawRRect(rr.deflate(7), _fill(const Color(0xCCFFFFFF)));
  });
  await _sheet(_pulse, 'receptors.png', 128, 64, 4, (c, i) {
    final color = _laneColors[i];
    final rr = RRect.fromRectAndRadius(const Rect.fromLTWH(14, 18, 100, 28), const Radius.circular(14));
    c.drawRRect(rr, _stroke(color, 4, blur: 3));
    c.drawRRect(rr, _stroke(const Color(0xCCFFFFFF), 2));
  });
  await _png(_pulse, 'hold.png', 64, 256, (c) {
    const r = Rect.fromLTWH(18, 0, 28, 256);
    c.drawRect(r.inflate(6), _glow(const Color(0x88FFFFFF), 6));
    c.drawRect(r, _linear(r, const [Color(0x55FFFFFF), Color(0xDDFFFFFF)]));
  });
  await _png(_pulse, 'flash.png', 256, 128, (c) {
    c.drawOval(const Rect.fromLTWH(16, 16, 224, 96), _stroke(const Color(0xFFFFFFFF), 8, blur: 5));
    _softDot(c, const Offset(128, 64), 70, const Color(0x66FFFFFF));
  });
  await _png(_pulse, 'panel.png', 840, 520, _glassPanel);

  _writeWav(_pulse, 'song.wav', _pulseSong());
  _writeWav(_pulse, 'tick.wav', _effect(0.08, (t) => _noise() * math.exp(-t * 90) * 0.4 + math.sin(2 * math.pi * 2400 * t) * math.exp(-t * 60) * 0.3, peak: 0.35));
  _writeWav(_pulse, 'miss.wav', _effect(0.25, (t) => ((180 * math.exp(-t * 4) * t) % 1 * 2 - 1) * math.exp(-t * 12) * 0.5, peak: 0.4));
  _writeWav(_pulse, 'cheer.wav', _effect(1.6, (t) {
    var v = 0.0;
    for (final (n, at) in [(69, 0.0), (72, 0.12), (76, 0.24), (81, 0.36)]) {
      if (t > at) v += math.sin(2 * math.pi * _hz(n) * t) * math.exp(-(t - at) * 3);
    }
    return v * 0.35;
  }, peak: 0.6));
}

void _pulseBackground(Canvas c) {
  const r = Rect.fromLTWH(0, 0, 960, 540);
  c.drawRect(r, _linear(r, const [Color(0xFF120424), Color(0xFF3B0A5C), Color(0xFF7A1F6E), Color(0xFF0A0418)], stops: const [0, 0.42, 0.58, 0.6]));
  // The sun, with stripes
  const sun = Offset(480, 300);
  c.save();
  c.clipRect(const Rect.fromLTWH(0, 0, 960, 322));
  c.drawCircle(sun, 150, _glow(const Color(0x88FB7185), 30));
  c.drawCircle(sun, 120, _linear(Rect.fromCircle(center: sun, radius: 120), const [Color(0xFFFDE68A), Color(0xFFF472B6), Color(0xFFA855F7)]));
  c.save();
  c.clipPath(Path()..addOval(Rect.fromCircle(center: sun, radius: 120)));
  for (var k = 0; k < 6; k++) {
    c.drawRect(Rect.fromLTWH(300, 250.0 + k * 13, 360, 3.0 + k), _fill(const Color(0xFF5B1677)));
  }
  c.restore();
  c.restore();
  // Stars
  final rng = math.Random(8);
  for (var k = 0; k < 90; k++) {
    c.drawCircle(Offset(rng.nextDouble() * 960, rng.nextDouble() * 280), 0.6 + rng.nextDouble() * 1.2, _fill(Color.fromRGBO(255, 255, 255, 0.3 + rng.nextDouble() * 0.6)));
  }
  // A perspective grid on the floor
  const horizon = 322.0;
  final grid = _stroke(const Color(0xAAF472B6), 1.6);
  for (var k = -14; k <= 14; k++) {
    c.drawLine(Offset(480 + k * 12.0, horizon), Offset(480 + k * 120.0, 540), grid);
  }
  for (var k = 0; k < 9; k++) {
    final y = horizon + math.pow(k / 8, 2) * 218;
    c.drawLine(Offset(0, y), Offset(960, y), _stroke(Color.fromRGBO(244, 114, 182, 0.3 + k * 0.06), 1.4));
  }
  c.drawLine(const Offset(0, horizon), const Offset(960, horizon), _stroke(const Color(0xAAF472B6), 6, blur: 6));
  c.drawLine(const Offset(0, horizon), const Offset(960, horizon), _stroke(const Color(0xFFFBCFE8), 1.5));
}

/// The song: drums, bass and pad under the lead line the charts are made from.
List<double> _pulseSong() {
  final beat = PulseSong.beatSeconds;
  final out = List<double>.filled((PulseSong.length * _rate).round(), 0);
  final lead = List<double>.filled(out.length, 0);
  const t0 = PulseSong.leadIn;
  for (var bar = 0; bar < PulseSong.bars; bar++) {
    final chord = PulseSong.chords[bar % 4];
    final b = t0 + bar * 4 * beat;
    final section = PulseSong.section(bar);
    for (final n in chord) {
      _synthNote(out, b, 4 * beat - 0.05, _hz(n - 12), voices: 4, detune: 0.01, bright: section == 'break' ? 900 : 1500, dark: 600, gain: 0.05, a: 0.3, d: 0.5, s: 0.8, r: 0.3);
    }
    for (var k = 0; k < 8; k++) {
      _synthNote(out, b + k * beat / 2, beat / 2 - 0.03, _hz(chord[0] - 24), voices: 2, detune: 0.005, bright: 900, dark: 220, gain: section == 'break' ? 0.12 : 0.28, a: 0.003, d: 0.12, s: 0.5, r: 0.04);
    }
    if (section != 'break') {
      for (var k = 0; k < 4; k++) {
        _kick(out, b + k * beat, gain: section == 'intro' ? 0.5 : 0.8);
        if (k == 1 || k == 3) _snare(out, b + k * beat, gain: section == 'intro' ? 0.15 : 0.35);
        _hat(out, b + k * beat + beat / 2, gain: 0.09);
        if (section == 'finale') _hat(out, b + k * beat + beat / 4 * 3, gain: 0.05, decay: 90);
      }
    } else {
      _kick(out, b, gain: 0.4);
    }
  }
  for (final n in PulseSong.lead()) {
    final len = n.length > 0 ? n.length * beat : beat * 0.45;
    _synthNote(lead, PulseSong.timeOf(n.beat), len, _hz(n.pitch), voices: 2, detune: 0.006, bright: 5000, dark: 1200, gain: 0.13, a: 0.002, d: 0.12, s: n.length > 0 ? 0.7 : 0.3, r: 0.08);
  }
  _delay(lead, beat * 0.75, 0.25, 0.35);
  for (var i = 0; i < out.length; i++) {
    out[i] += lead[i];
  }
  return _master(out);
}

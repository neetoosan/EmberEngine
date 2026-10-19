part of 'paint_art_test.dart';

// A small offline synthesizer for modern-sounding loops and effects:
// detuned saws through a low-pass filter, a sub bass, a delay, punchy drums.

const int _rate = 22050;

/// MIDI note number to frequency (A4 = 69 = 440 Hz).
double _hz(num note) => 440 * math.pow(2, (note - 69) / 12).toDouble();

/// One-pole low-pass filter state.
class _LowPass {
  double _y = 0;
  double process(double x, double cutoff) {
    final a = 1 - math.exp(-2 * math.pi * cutoff / _rate);
    return _y += a * (x - _y);
  }
}

/// A band-limited-ish saw (polyBLEP) oscillator.
double _saw(double phase, double dt) {
  var v = 2 * phase - 1;
  if (phase < dt) {
    final t = phase / dt;
    v -= t + t - t * t - 1;
  } else if (phase > 1 - dt) {
    final t = (phase - 1) / dt;
    v -= t * t + t + t + 1;
  }
  return v;
}

/// Mixes [voice] (a function of seconds since note start) into [out] at [start] seconds.
void _mix(List<double> out, double start, double length, double Function(double t) voice, {double gain = 1}) {
  final i0 = (start * _rate).round();
  final n = (length * _rate).round();
  for (var i = 0; i < n && i0 + i < out.length; i++) {
    if (i0 + i < 0) continue;
    out[i0 + i] += voice(i / _rate) * gain;
  }
}

double _adsr(double t, double length, {double a = 0.01, double d = 0.1, double s = 0.7, double r = 0.1}) {
  if (t < a) return t / a;
  if (t < a + d) return 1 - (1 - s) * (t - a) / d;
  if (t < length) return s;
  final x = 1 - (t - length) / r;
  return x <= 0 ? 0 : s * x;
}

/// A synth note: [voices] detuned saws, filter envelope from [bright] to [dark] Hz.
void _synthNote(List<double> out, double start, double length, double freq,
    {int voices = 3, double detune = 0.012, double bright = 3000, double dark = 600, double gain = 0.2, double a = 0.005, double d = 0.15, double s = 0.6, double r = 0.15}) {
  final phases = List<double>.generate(voices, (i) => (i * 0.37) % 1);
  final lp = _LowPass(), lp2 = _LowPass();
  _mix(out, start, length + r, (t) {
    var v = 0.0;
    for (var k = 0; k < voices; k++) {
      final f = freq * (1 + detune * (k - (voices - 1) / 2));
      final dt = f / _rate;
      phases[k] = (phases[k] + dt) % 1;
      v += _saw(phases[k], dt);
    }
    v /= voices;
    final env = _adsr(t, length, a: a, d: d, s: s, r: r);
    final cutoff = dark + (bright - dark) * math.exp(-t * 6);
    return lp2.process(lp.process(v, cutoff), cutoff) * env;
  }, gain: gain);
}

void _kick(List<double> out, double start, {double gain = 0.9}) {
  var phase = 0.0;
  _mix(out, start, 0.35, (t) {
    final f = 45 + 110 * math.exp(-t * 28);
    phase += f / _rate;
    final click = t < 0.004 ? (1 - t / 0.004) * 0.4 : 0.0;
    return math.sin(2 * math.pi * phase) * math.exp(-t * 9) + click;
  }, gain: gain);
}

final math.Random _noiseRng = math.Random(7);
double _noise() => _noiseRng.nextDouble() * 2 - 1;

void _snare(List<double> out, double start, {double gain = 0.45}) {
  final lp = _LowPass();
  var hp = 0.0;
  _mix(out, start, 0.3, (t) {
    final n = _noise();
    final body = lp.process(n, 5000);
    hp = n - body; // the bright part
    final tone = math.sin(2 * math.pi * 190 * t) * math.exp(-t * 30);
    return (body * 0.6 + hp * 0.5) * math.exp(-t * 14) + tone * 0.5;
  }, gain: gain);
}

void _hat(List<double> out, double start, {double gain = 0.12, double decay = 60}) {
  final lp = _LowPass();
  _mix(out, start, 0.12, (t) {
    final n = _noise();
    return (n - lp.process(n, 7000)) * math.exp(-t * decay);
  }, gain: gain);
}

/// Feedback delay (echo) over the whole buffer.
void _delay(List<double> out, double seconds, double feedback, double wet) {
  final d = (seconds * _rate).round();
  final echo = List<double>.filled(out.length, 0);
  for (var i = d; i < out.length; i++) {
    echo[i] = (out[i - d] + echo[i - d]) * feedback;
  }
  for (var i = 0; i < out.length; i++) {
    out[i] += echo[i] * wet;
  }
}

/// Soft-clips, normalises to [peak] and makes the loop seamless (short fades).
List<double> _master(List<double> out, {double peak = 0.85}) {
  var m = 0.0;
  for (var i = 0; i < out.length; i++) {
    out[i] = _tanh(out[i] * 1.2);
    m = math.max(m, out[i].abs());
  }
  final k = m == 0 ? 1.0 : peak / m;
  final fade = (0.004 * _rate).round();
  for (var i = 0; i < out.length; i++) {
    var g = k;
    if (i < fade) g *= i / fade;
    if (i > out.length - fade) g *= (out.length - i) / fade;
    out[i] *= g;
  }
  return out;
}

double _tanh(double x) {
  final e = math.exp(2 * x.clamp(-10, 10));
  return (e - 1) / (e + 1);
}

/// Mono 16-bit PCM WAV.
Uint8List _wav(List<double> samples) {
  final data = ByteData(44 + samples.length * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, _rate, Endian.little);
  data.setUint32(28, _rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

void _writeWav(String folder, String name, List<double> samples) {
  final out = Directory('assets/templates/$folder')..createSync(recursive: true);
  final f = File('${out.path}/$name')..writeAsBytesSync(_wav(samples));
  stdout.writeln('wrote ${f.path} (${f.lengthSync() ~/ 1024} KB)');
}

/// A one-shot effect of [seconds], made by [voice].
List<double> _effect(double seconds, double Function(double t) voice, {double peak = 0.8}) {
  final out = List<double>.filled((seconds * _rate).round(), 0);
  _mix(out, 0, seconds, voice);
  return _master(out, peak: peak);
}

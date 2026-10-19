/// "Neon Drift", the song of Ember Pulse. The art tool (tool/painted) makes
/// the audio from this lead line and the template makes the note charts from
/// it, so every note you hit is a note you hear.
class PulseNote {
  final double beat;
  final double length; // in beats (0 = a tap)
  final int pitch; // MIDI note
  final int lane; // 0-3, left to right
  const PulseNote(this.beat, this.length, this.pitch, this.lane);
}

class PulseSong {
  static const String title = 'Neon Drift';
  static const double bpm = 124;
  static const int bars = 32;
  static double get beatSeconds => 60 / bpm;

  /// A minor: Am F C G, one bar each.
  static const List<List<int>> chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]];

  /// Seconds of silence before the first beat (time to get ready).
  static const double leadIn = 2.0;

  /// The song's length in seconds, including the lead-in and a short tail.
  static double get length => leadIn + bars * 4 * beatSeconds + 2.0;

  static const List<int> _scale = [45, 47, 48, 50, 52, 53, 55, 57, 59, 60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81];

  /// Lane from pitch: higher notes to the right, wrapping every four steps of the scale.
  static int laneOf(int pitch) {
    var i = _scale.indexOf(pitch);
    if (i < 0) i = pitch % _scale.length;
    return i % 4;
  }

  static String section(int bar) => bar < 4 ? 'intro' : (bar < 12 ? 'verse' : (bar < 20 ? 'chorus' : (bar < 24 ? 'break' : 'finale')));

  /// The lead line: (beat from the first downbeat, length, pitch).
  static List<PulseNote> lead() {
    final out = <PulseNote>[];
    void add(double beat, int pitch, [double length = 0]) => out.add(PulseNote(beat, length, pitch, laneOf(pitch)));
    for (var bar = 0; bar < bars; bar++) {
      final chord = chords[bar % 4];
      final b0 = bar * 4.0;
      final up = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[0] + 24];
      switch (section(bar)) {
        case 'intro':
          for (var k = 0; k < 4; k++) {
            add(b0 + k, up[k % 3]);
          }
        case 'verse':
          final pattern = [0, 2, 1, 2, 3, 1, 2, 0];
          for (var k = 0; k < 8; k++) {
            if (bar % 2 == 1 && k == 7) continue; // a breath every other bar
            add(b0 + k * 0.5, up[pattern[k]]);
          }
        case 'chorus':
          add(b0, up[3], 1.5); // a held note on the downbeat, then a run
          final run = bar % 2 == 0 ? [2, 1, 0, 1] : [1, 2, 3, 2];
          for (var k = 0; k < 4; k++) {
            add(b0 + 2 + k * 0.5, up[run[k]]);
          }
        case 'finale':
          add(b0, up[3], 1.5); // a held note, then a fast run in sixteenths
          final run = bar % 2 == 0 ? [2, 1, 0, 1, 2, 3, 2, 1] : [1, 2, 3, 2, 1, 0, 1, 2];
          for (var k = 0; k < 8; k++) {
            add(b0 + 2 + k * 0.25, up[run[k]]);
          }
        case 'break':
          add(b0, up[bar % 3], 3);
      }
    }
    out.sort((a, b) => a.beat.compareTo(b.beat));
    return out;
  }

  /// Seconds from the start of the music to [beat].
  static double timeOf(double beat) => leadIn + beat * beatSeconds;

  /// A chart: one line per note, "seconds lane holdSeconds". Easy keeps the
  /// beats, Normal the eighths, Hard everything.
  static String chart(String difficulty) {
    final lines = <String>['# $title ($difficulty): time lane hold'];
    for (final n in lead()) {
      final onBeat = n.beat == n.beat.roundToDouble();
      final onEighth = (n.beat * 2) == (n.beat * 2).roundToDouble();
      if (difficulty == 'easy' && !onBeat) continue;
      if (difficulty == 'normal' && !onEighth) continue;
      final hold = difficulty == 'easy' && n.length < 2 ? 0.0 : n.length * beatSeconds;
      lines.add('${timeOf(n.beat).toStringAsFixed(3)} ${n.lane} ${hold.toStringAsFixed(3)}');
    }
    return '${lines.join('\n')}\n';
  }
}

// Generates the original pixel art used by the built-in game templates.
//
//   dart run tool/generate_template_art.dart
//
// Output: assets/templates/flappy/*.png and assets/templates/quest/*
// (committed, so this only needs to be re-run after changing the art below).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main() {
  void save(String folder, String name, _Img img) {
    final out = Directory('assets/templates/$folder')..createSync(recursive: true);
    File('${out.path}/$name').writeAsBytesSync(img.encodePng());
    stdout.writeln('wrote ${out.path}/$name (${img.w}x${img.h})');
  }

  save('flappy', 'bird.png', _birdSheet());
  save('flappy', 'pipe_body.png', _pipeBody());
  save('flappy', 'pipe_cap.png', _pipeCap());
  save('flappy', 'ground.png', _ground());
  save('flappy', 'cloud.png', _cloud());
  save('flappy', 'hills.png', _hills());

  // Ember Quest (Mario-style platformer)
  save('quest', 'tiles.png', _questTiles());
  save('quest', 'hero.png', _heroSheet(big: false));
  save('quest', 'hero_big.png', _heroSheet(big: true));
  save('quest', 'slime.png', _slimeSheet());
  save('quest', 'coin.png', _coinSheet());
  save('quest', 'berry.png', _berry());
  save('quest', 'flag.png', _flag());
  save('quest', 'pole.png', _pole());
  save('quest', 'bg_hills.png', _bgHills());
  save('quest', 'bg_clouds.png', _bgClouds());
  final music = File('assets/templates/quest/theme.wav')..writeAsBytesSync(_questTheme());
  stdout.writeln('wrote ${music.path} (${music.lengthSync() ~/ 1024} KB)');
}

// ---------------------------------------------------------------------------
// Ember Quest art (16px cells)

/// Builds an image from rows of palette characters ('.' = transparent).
_Img _grid(List<String> rows, Map<String, int> palette, {int width = 16}) {
  final img = _Img(width, rows.length);
  for (var y = 0; y < rows.length; y++) {
    final row = rows[y].padRight(width, '.').substring(0, width);
    for (var x = 0; x < width; x++) {
      final c = palette[row[x]];
      if (c != null) img.set(x, y, c);
    }
  }
  return img;
}

const _heroPalette = {
  'K': 0xFF1B1420, // outline
  'T': 0xFF0F766E, // hood (teal)
  't': 0xFF14B8A6, // hood highlight
  's': 0xFFF5C9A0, // skin
  'k': 0xFF1B1420, // eyes
  'x': 0xFFB91C1C, // dizzy eyes
  'Y': 0xFFFACC15, // scarf
  'O': 0xFFEA580C, // tunic
  'b': 0xFF7C2D12, // belt
  'd': 0xFF3F3F46, // boots
};

const _heroHead = [
  '................',
  '.....KKKKKK.....',
  '....KtTTTTTK....',
  '...KtTTTTTTTK...',
  '...KTssssssTK...',
  '...KsskssksTK...',
  '...KssssssssK...',
  '....KYYYYYYK....',
];

/// Frames: 0 idle, 1-3 run, 4 jump, 5 dead. Big = 16x24 (taller body).
_Img _heroSheet({required bool big}) {
  const body = [
    '...KOOOOOOOOK...',
    '..KsOOOOOOOOsK..',
    '..KsKbbbbbbKsK..',
    '...KOOOOOOOOK...',
  ];
  const bodyJump = [
    '...KOOOOOOOOKsK.',
    '..KsOOOOOOOOKsK.',
    '..KsKbbbbbbK.K..',
    '...KOOOOOOOOK...',
  ];
  const legs = <List<String>>[
    ['...KOOKKKKOOK...', '...KddK..KddK...', '..KdddK..KdddK..', '..KKKKK..KKKKK..'], // idle
    ['..KOOK....KOOK..', '.KddK......KddK.', 'KdddK......KdddK', 'KKKKK......KKKKK'], // run 1
    ['....KOOOOOOK....', '....KddddddK....', '...KdddddddK....', '...KKKKKKKKK....'], // run 2
    ['...KOOK..KOOK...', '..KddK....KddK..', '.KdddK....KdddK.', '.KKKKK....KKKKK.'], // run 3
    ['...KOOKKKKOOK...', '..KddK....KddK..', '.KddK......KdK..', '.KKK.......KK...'], // jump
    ['..KOOK....KOOK..', '..KddK....KddK..', '..KdddK..KdddK..', '..KKKKK..KKKKK..'], // dead
  ];
  final h = big ? 24 : 16;
  final sheet = _Img(16 * 6, h);
  for (var f = 0; f < 6; f++) {
    final head = f == 5 ? _heroHead.map((r) => r.replaceAll('k', 'x')).toList() : _heroHead;
    final torso = f == 4 || f == 5 ? bodyJump : body;
    // Big hero: every torso and leg row is doubled (taller body, same head)
    final rows = [
      ...head,
      for (final r in torso) ...(big ? [r, r] : [r]),
      ...legs[f],
    ];
    sheet.blit(_grid(rows, _heroPalette), f * 16, h - rows.length);
  }
  return sheet;
}

/// Frames: 0-1 walk (wobble), 2 squashed.
_Img _slimeSheet() {
  const pal = {'K': 0xFF2E1065, 'P': 0xFF8B5CF6, 'p': 0xFFA78BFA, 'W': 0xFFFFFFFF, 'k': 0xFF111111, 'M': 0xFF4C1D95};
  const a = [
    '................', '................', '................', '................',
    '......KKKK......', '....KKppPPKK....', '...KppPPPPPPK...', '..KPPWWPPWWPPK..',
    '..KPPWkPPWkPPK..', '.KPPPPPPPPPPPPK.', '.KPPPPMMMMPPPPK.', '.KPPPPPPPPPPPPK.',
    '.KPPPPPPPPPPPPK.', '..KPPPPPPPPPPK..', '...KKKKKKKKKK...', '................',
  ];
  const b = [
    '................', '................', '................', '................',
    '................', '.....KKKKKK.....', '...KKppPPPPKK...', '..KpPPWWPPWWPK..',
    '.KPPPWkPPWkPPPK.', '.KPPPPPPPPPPPPK.', 'KPPPPPMMMMPPPPPK', 'KPPPPPPPPPPPPPPK',
    'KPPPPPPPPPPPPPPK', '.KPPPPPPPPPPPPK.', '..KKKKKKKKKKKK..', '................',
  ];
  const squashed = [
    '................', '................', '................', '................',
    '................', '................', '................', '................',
    '................', '................', '................', '..KKKKKKKKKKKK..',
    '.KPPkkPPPPkkPPK.', 'KPPPPPMMMMPPPPPK', '.KKKKKKKKKKKKKK.', '................',
  ];
  final sheet = _Img(48, 16);
  sheet.blit(_grid(a, pal), 0, 0);
  sheet.blit(_grid(b, pal), 16, 0);
  sheet.blit(_grid(squashed, pal), 32, 0);
  return sheet;
}

/// Four spin frames.
_Img _coinSheet() {
  final sheet = _Img(64, 16);
  const widths = [5.5, 3.8, 1.2, 3.8];
  for (var f = 0; f < 4; f++) {
    final frame = _Img(16, 16);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final px = x + 0.5, py = y + 0.5;
        if (_inEllipse(px, py, 8, 8, widths[f], 6.5)) {
          final shine = px < 8 - widths[f] * 0.3;
          frame.set(x, y, shine ? 0xFFFEF08A : 0xFFFACC15);
        }
      }
    }
    if (f != 2) {
      for (var y = 5; y < 11; y++) {
        frame.set(8, y, 0xFFCA8A04); // engraved line
      }
    }
    frame.addOutline(0xFF713F12);
    sheet.blit(frame, f * 16, 0);
  }
  return sheet;
}

_Img _berry() {
  final img = _Img(16, 16);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      final px = x + 0.5, py = y + 0.5;
      if (_inEllipse(px, py, 8, 9.5, 5.6, 5.3)) {
        img.set(x, y, _inEllipse(px, py, 6.2, 7.6, 1.6, 1.4) ? 0xFFFFFFFF : 0xFFE11D48);
      }
    }
  }
  // Leaf and stem
  for (final (x, y) in [(8, 2), (8, 3), (9, 2), (10, 2), (10, 3), (11, 3), (9, 1)]) {
    img.set(x, y, 0xFF16A34A);
  }
  img.addOutline(0xFF4C0519);
  return img;
}

_Img _flag() {
  final img = _Img(16, 16);
  for (var y = 1; y < 12; y++) {
    final w = 12 - (y - 1).abs() * 0 - ((y - 6).abs());
    for (var x = 0; x < w; x++) {
      img.set(x, y, (x + y).isEven ? 0xFFEF4444 : 0xFFDC2626);
    }
  }
  // Ember emblem
  for (final (x, y) in [(3, 5), (4, 4), (4, 5), (4, 6), (5, 5), (5, 6)]) {
    img.set(x, y, 0xFFFACC15);
  }
  img.addOutline(0xFF450A0A);
  return img;
}

/// 4x16 pole segment (tiles vertically).
_Img _pole() {
  final img = _Img(4, 16);
  for (var y = 0; y < 16; y++) {
    img
      ..set(0, y, 0xFF14532D)
      ..set(1, y, 0xFF4ADE80)
      ..set(2, y, 0xFF22C55E)
      ..set(3, y, 0xFF14532D);
  }
  return img;
}

/// 8x2 cells of 16px. IDs (cell + 1): 1 grass, 2 dirt, 3 brick, 4 "?" (coin),
/// 5 used, 6 stone, 7 wood plank (one-way), 8 spikes, 9 bush, 10 grass tuft,
/// 11 flower, 12 "?" (power-up; same look as 4).
_Img _questTiles() {
  final sheet = _Img(128, 32);
  final rng = math.Random(11);
  void cell(int id, void Function(_Img c) draw) {
    final c = _Img(16, 16);
    draw(c);
    final i = id - 1;
    sheet.blit(c, (i % 8) * 16, (i ~/ 8) * 16);
  }

  void fill(_Img c, int color) {
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        c.set(x, y, color);
      }
    }
  }

  void dirt(_Img c, int fromRow) {
    for (var y = fromRow; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        c.set(x, y, rng.nextDouble() < 0.1 ? 0xFF92400E : 0xFFB45309);
      }
    }
  }

  cell(1, (c) {
    dirt(c, 5);
    for (var x = 0; x < 16; x++) {
      for (var y = 0; y < 5; y++) {
        c.set(x, y, y == 4 ? 0xFF3F6212 : (((x + y) ~/ 3).isEven ? 0xFF84CC16 : 0xFF65A30D));
      }
    }
  });
  cell(2, (c) => dirt(c, 0));
  cell(3, (c) {
    fill(c, 0xFFC2410C);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final mortarRow = y % 4 == 3;
        final offset = (y ~/ 4).isEven ? 0 : 4;
        final mortarCol = (x + offset) % 8 == 7;
        if (mortarRow || mortarCol) c.set(x, y, 0xFF431407);
        if (!mortarRow && !mortarCol && y % 4 == 0) c.set(x, y, 0xFFEA580C);
      }
    }
  });
  void questionBlock(_Img c) {
    fill(c, 0xFFF59E0B);
    for (var i = 0; i < 16; i++) {
      c
        ..set(i, 0, 0xFF78350F)
        ..set(i, 15, 0xFF78350F)
        ..set(0, i, 0xFF78350F)
        ..set(15, i, 0xFF78350F);
    }
    for (final (x, y) in [(2, 2), (13, 2), (2, 13), (13, 13)]) {
      c.set(x, y, 0xFF78350F);
    }
    const q = ['.KKKK.', 'KK..KK', '....KK', '...KK.', '..KK..', '......', '..KK..'];
    for (var y = 0; y < q.length; y++) {
      for (var x = 0; x < 6; x++) {
        if (q[y][x] == 'K') {
          c.set(5 + x, 4 + y, 0xFFFFFBEB);
          c.set(6 + x, 5 + y, 0xFF92400E);
        }
      }
    }
  }

  cell(4, questionBlock);
  cell(12, questionBlock);
  cell(5, (c) {
    fill(c, 0xFF92400E);
    for (var i = 0; i < 16; i++) {
      c
        ..set(i, 0, 0xFF451A03)
        ..set(i, 15, 0xFF451A03)
        ..set(0, i, 0xFF451A03)
        ..set(15, i, 0xFF451A03);
    }
    for (final (x, y) in [(2, 2), (13, 2), (2, 13), (13, 13)]) {
      c.set(x, y, 0xFF451A03);
    }
  });
  cell(6, (c) {
    fill(c, 0xFF9CA3AF);
    for (var i = 0; i < 16; i++) {
      c
        ..set(i, 0, 0xFFE5E7EB)
        ..set(0, i, 0xFFE5E7EB)
        ..set(i, 15, 0xFF4B5563)
        ..set(15, i, 0xFF4B5563);
    }
  });
  cell(7, (c) {
    for (var y = 0; y < 6; y++) {
      for (var x = 0; x < 16; x++) {
        c.set(x, y, y == 0 ? 0xFFFDE68A : (y == 5 ? 0xFF78350F : (x % 5 == 4 ? 0xFF92400E : 0xFFD97706)));
      }
    }
  });
  cell(8, (c) {
    for (var s = 0; s < 4; s++) {
      for (var y = 6; y < 16; y++) {
        final half = ((y - 6) * 2 / 10 * 2).floor();
        for (var x = 2 - half; x <= 1 + half; x++) {
          c.set(s * 4 + x.clamp(-2, 5), y, x == 2 - half ? 0xFFE5E7EB : 0xFF6B7280);
        }
      }
    }
  });
  cell(9, (c) {
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final px = x + 0.5, py = y + 0.5;
        if (_inEllipse(px, py, 5, 13, 5, 5) || _inEllipse(px, py, 11, 12, 5, 6) || _inEllipse(px, py, 8, 10, 4, 4)) {
          c.set(x, y, py < 10 ? 0xFF4ADE80 : 0xFF16A34A);
        }
      }
    }
    c.addOutline(0xFF14532D);
  });
  cell(10, (c) {
    for (final (x, h) in [(3, 4), (5, 6), (7, 3), (10, 5), (12, 4)]) {
      for (var y = 16 - h; y < 16; y++) {
        c.set(x, y, 0xFF22C55E);
      }
    }
  });
  cell(11, (c) {
    for (var y = 9; y < 16; y++) {
      c.set(8, y, 0xFF16A34A);
    }
    for (final (x, y) in [(7, 7), (9, 7), (8, 6), (8, 8), (7, 8), (9, 8)]) {
      c.set(x, y, 0xFFF472B6);
    }
    c.set(8, 7, 0xFFFACC15);
  });
  return sheet;
}

/// 160x64 distant hills (tiles sideways).
_Img _bgHills() {
  final img = _Img(160, 64);
  for (var x = 0; x < 160; x++) {
    final t = x / 160 * 2 * math.pi;
    final far = 22 + 8 * math.sin(t + 0.5) + 4 * math.sin(3 * t);
    final near = 38 + 6 * math.sin(2 * t + 2.0);
    for (var y = 0; y < 64; y++) {
      if (y >= near) {
        img.set(x, y, 0xFF4D9E5A);
      } else if (y >= far) {
        img.set(x, y, 0xFF8FC9A0);
      }
    }
  }
  return img;
}

/// 128x40 cloud band (tiles sideways).
_Img _bgClouds() {
  final img = _Img(128, 40);
  for (var y = 0; y < 40; y++) {
    for (var x = 0; x < 128; x++) {
      final px = x + 0.5, py = y + 0.5;
      final inside = _inEllipse(px, py, 20, 14, 12, 7) ||
          _inEllipse(px, py, 32, 11, 10, 8) ||
          _inEllipse(px, py, 84, 26, 14, 7) ||
          _inEllipse(px, py, 98, 23, 9, 7);
      if (inside) img.set(x, y, py > 16 && px < 50 || py > 29 ? 0xFFE0F2FE : 0xFFFFFFFF);
    }
  }
  return img;
}

// ---------------------------------------------------------------------------
// Ember Quest theme: an original 8-bar chiptune loop (square lead + triangle bass)

Uint8List _questTheme() {
  const rate = 22050;
  const bpm = 140.0;
  const beat = 60.0 / bpm;
  // (MIDI note, beats); 0 = rest. Original melody.
  const lead = [
    (76, 1.0), (79, 1.0), (81, 2.0), //
    (79, 1.0), (76, 1.0), (72, 2.0),
    (74, 1.0), (76, 1.0), (77, 1.0), (74, 1.0),
    (76, 3.0), (0, 1.0),
    (76, 1.0), (79, 1.0), (84, 2.0),
    (83, 1.0), (81, 1.0), (79, 2.0),
    (77, 1.0), (76, 1.0), (74, 1.0), (71, 1.0),
    (72, 3.0), (0, 1.0),
  ];
  // Bass roots per half bar (2 beats each), bouncing root / octave
  const bassRoots = [48, 48, 45, 45, 50, 50, 48, 48, 48, 48, 43, 43, 41, 43, 48, 48];

  final totalBeats = lead.fold<double>(0, (s, n) => s + n.$2);
  final total = (totalBeats * beat * rate).round();
  final samples = List<double>.filled(total, 0);
  double freq(int midi) => 440.0 * math.pow(2, (midi - 69) / 12).toDouble();

  void addNote(int midi, double startBeat, double beats, double amp, bool square) {
    if (midi <= 0) return;
    final f = freq(midi);
    final start = (startBeat * beat * rate).round();
    final len = (beats * beat * rate).round();
    for (var i = 0; i < len && start + i < total; i++) {
      final t = i / rate;
      final phase = (t * f) % 1.0;
      final wave = square ? (phase < 0.25 ? 1.0 : -1.0) : 4 * (phase - 0.5).abs() - 1; // pulse / triangle
      final attack = math.min(1.0, i / (rate * 0.005));
      final release = math.min(1.0, (len - i) / (rate * 0.03));
      final decay = square ? 0.75 + 0.25 * math.exp(-t * 6) : 1.0;
      samples[start + i] += wave * amp * attack * release * decay;
    }
  }

  var at = 0.0;
  for (final (note, beats) in lead) {
    addNote(note, at, beats * 0.92, 0.22, true);
    at += beats;
  }
  for (var i = 0; i < bassRoots.length; i++) {
    final root = bassRoots[i];
    addNote(root, i * 2.0, 0.9, 0.35, false);
    addNote(root + 12, i * 2.0 + 1, 0.9, 0.3, false);
  }

  // 16-bit mono WAV
  final data = ByteData(44 + total * 2);
  void ascii(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + total * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, total * 2, Endian.little);
  for (var i = 0; i < total; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32000).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Art

const _outline = 0xFF2A1A12;

/// Three 17x12 frames side by side: wing up, middle, down.
_Img _birdSheet() {
  const fw = 17, fh = 12;
  final sheet = _Img(fw * 3, fh);
  for (var f = 0; f < 3; f++) {
    final frame = _Img(fw, fh);
    final wingDy = [-1.6, 0.2, 1.8][f];
    for (var y = 0; y < fh; y++) {
      for (var x = 0; x < fw; x++) {
        final px = x + 0.5, py = y + 0.5;
        int? c;
        // Body
        if (_inEllipse(px, py, 7.8, 6.6, 6.2, 4.6)) {
          c = py > 7.6 ? 0xFFFDE68A : 0xFFF97316; // belly / body
        }
        // Flame tuft on the head
        if ((x == 7 || x == 8) && y == 1 || x == 8 && y == 0) c = 0xFFFACC15;
        // Eye
        if (_inEllipse(px, py, 11.2, 4.6, 2.3, 2.1)) c = 0xFFFFFFFF;
        if (x == 12 && (y == 4 || y == 5)) c = 0xFF111111;
        // Beak
        if (y == 6 && x >= 12 && x <= 15) c = 0xFFDC2626;
        if (y == 7 && x >= 12 && x <= 14) c = 0xFFB91C1C;
        // Wing
        if (_inEllipse(px, py, 4.6, 6.9 + wingDy, 3.4, 1.8)) c = 0xFFFED7AA;
        if (c != null) frame.set(x, y, c);
      }
    }
    frame.addOutline(_outline);
    sheet.blit(frame, f * fw, 0);
  }
  return sheet;
}

int _pipeColumn(int x, int w) {
  if (x == 0 || x == w - 1) return 0xFF1F3B14; // outline
  final t = x / (w - 1);
  if (t < 0.12) return 0xFF4A8F2B;
  if (t < 0.32) return 0xFFA7E07A; // highlight
  if (t < 0.72) return 0xFF6DBE45;
  return 0xFF4A8F2B; // shade
}

/// 26x8, uniform vertically so it can be stretched to any height.
_Img _pipeBody() {
  final img = _Img(26, 8);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 26; x++) {
      img.set(x, y, _pipeColumn(x, 26));
    }
  }
  return img;
}

/// 30x12 lip at the open end of each pipe.
_Img _pipeCap() {
  final img = _Img(30, 12);
  for (var y = 0; y < 12; y++) {
    for (var x = 0; x < 30; x++) {
      img.set(x, y, y == 0 || y == 11 ? 0xFF1F3B14 : _pipeColumn(x, 30));
    }
  }
  return img;
}

/// 16x32 tile: striped grass on top of sandy dirt. Tiles seamlessly sideways.
_Img _ground() {
  final img = _Img(16, 32);
  final rng = math.Random(7);
  for (var y = 0; y < 32; y++) {
    for (var x = 0; x < 16; x++) {
      int c;
      if (y == 0) {
        c = 0xFF2F4F1F;
      } else if (y < 5) {
        c = ((x + y) ~/ 4).isEven ? 0xFF8BD450 : 0xFF72BF3E; // diagonal stripes
      } else if (y < 7) {
        c = 0xFF4E8A2A;
      } else {
        c = rng.nextDouble() < 0.07 ? 0xFFC9C07A : 0xFFE3DA96;
      }
      img.set(x, y, c);
    }
  }
  return img;
}

_Img _cloud() {
  final img = _Img(32, 14);
  for (var y = 0; y < 14; y++) {
    for (var x = 0; x < 32; x++) {
      final px = x + 0.5, py = y + 0.5;
      final inside = _inEllipse(px, py, 9, 9, 7, 5) ||
          _inEllipse(px, py, 17, 6.5, 8, 6) ||
          _inEllipse(px, py, 25, 9, 6.5, 4.8) ||
          (py > 8 && py < 14 && px > 4 && px < 30);
      if (inside) img.set(x, y, py > 11 ? 0xFFDDF1FA : 0xFFFFFFFF);
    }
  }
  return img;
}

/// 72x24 rolling hills, drawn behind the pipes; tiles sideways.
_Img _hills() {
  final img = _Img(72, 24);
  for (var x = 0; x < 72; x++) {
    final t = x / 72 * 2 * math.pi;
    final top = 9 + 5 * math.sin(t) + 3 * math.sin(2 * t + 1.3);
    for (var y = 0; y < 24; y++) {
      if (y >= top) img.set(x, y, y - top < 2 ? 0xFF7CCB8E : 0xFF5DAE72);
    }
  }
  return img;
}

bool _inEllipse(double x, double y, double cx, double cy, double rx, double ry) {
  final dx = (x - cx) / rx, dy = (y - cy) / ry;
  return dx * dx + dy * dy <= 1.0;
}

// ---------------------------------------------------------------------------
// Minimal RGBA image + PNG encoder (no dependencies)

class _Img {
  final int w, h;
  final Uint32List px; // ARGB, 0 = transparent
  _Img(this.w, this.h) : px = Uint32List(w * h);

  void set(int x, int y, int argb) {
    if (x >= 0 && y >= 0 && x < w && y < h) px[y * w + x] = argb;
  }

  int get(int x, int y) => (x < 0 || y < 0 || x >= w || y >= h) ? 0 : px[y * w + x];

  void blit(_Img src, int ox, int oy) {
    for (var y = 0; y < src.h; y++) {
      for (var x = 0; x < src.w; x++) {
        final c = src.get(x, y);
        if (c != 0) set(ox + x, oy + y, c);
      }
    }
  }

  /// Draws [color] on every empty pixel that touches a filled one (4-neighbour).
  void addOutline(int color) {
    final edge = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (get(x, y) != 0) continue;
        if (get(x - 1, y) != 0 || get(x + 1, y) != 0 || get(x, y - 1) != 0 || get(x, y + 1) != 0) {
          edge.add(y * w + x);
        }
      }
    }
    for (final i in edge) {
      px[i] = color;
    }
  }

  Uint8List encodePng() {
    final raw = BytesBuilder();
    for (var y = 0; y < h; y++) {
      raw.addByte(0); // filter: none
      for (var x = 0; x < w; x++) {
        final c = px[y * w + x];
        raw.add([(c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, (c >> 24) & 0xFF]);
      }
    }
    final ihdr = ByteData(13)
      ..setUint32(0, w)
      ..setUint32(4, h)
      ..setUint8(8, 8) // bit depth
      ..setUint8(9, 6) // RGBA
      ..setUint8(10, 0)
      ..setUint8(11, 0)
      ..setUint8(12, 0);
    final out = BytesBuilder()
      ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      ..add(_chunk('IHDR', ihdr.buffer.asUint8List()))
      ..add(_chunk('IDAT', Uint8List.fromList(ZLibEncoder(level: 9).convert(raw.toBytes()))))
      ..add(_chunk('IEND', Uint8List(0)));
    return out.toBytes();
  }

  static Uint8List _chunk(String type, Uint8List data) {
    final typeBytes = type.codeUnits;
    final b = BytesBuilder();
    b.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
    b.add(typeBytes);
    b.add(data);
    b.add((ByteData(4)..setUint32(0, _crc([...typeBytes, ...data]))).buffer.asUint8List());
    return b.toBytes();
  }

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }
}

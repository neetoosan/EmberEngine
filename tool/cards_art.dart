part of 'generate_template_art.dart';

// ---------------------------------------------------------------------------
// Ember Solitaire: a full deck of pixel-art cards (drawn at 32 x 44, shown at
// twice the size), a card back, empty-pile frames, a felt table and music.

const int _cardW = 32, _cardH = 44;

void _saveCards(void Function(String folder, String name, _Img img) save) {
  save('solitaire', 'cards.png', _cardSheet());
  save('solitaire', 'table.png', _feltTable());
  save('solitaire', 'panel.png', _cardPanel());
  final music = File('assets/templates/solitaire/solitaire.wav')..writeAsBytesSync(_solitaireTheme());
  stdout.writeln('wrote ${music.path} (${music.lengthSync() ~/ 1024} KB)');
}

/// 3 x 5 pixel glyphs for ranks.
const Map<String, List<String>> _glyphs = {
  'A': ['.#.', '#.#', '###', '#.#', '#.#'],
  '2': ['##.', '..#', '.#.', '#..', '###'],
  '3': ['##.', '..#', '.#.', '..#', '##.'],
  '4': ['#.#', '#.#', '###', '..#', '..#'],
  '5': ['###', '#..', '##.', '..#', '##.'],
  '6': ['.##', '#..', '###', '#.#', '###'],
  '7': ['###', '..#', '.#.', '.#.', '.#.'],
  '8': ['###', '#.#', '###', '#.#', '###'],
  '9': ['###', '#.#', '###', '..#', '##.'],
  '1': ['.#', '##', '.#', '.#', '.#'],
  '0': ['###', '#.#', '#.#', '#.#', '###'],
  'J': ['..#', '..#', '..#', '#.#', '.#.'],
  'Q': ['.#.', '#.#', '#.#', '##.', '.##'],
  'K': ['#.#', '##.', '#..', '##.', '#.#'],
};

/// 5 x 5 suit icons: hearts, diamonds, clubs, spades.
const List<List<String>> _suitIcons = [
  ['#.#.#', '#####', '#####', '.###.', '..#..'],
  ['..#..', '.###.', '#####', '.###.', '..#..'],
  ['.###.', '..#..', '#####', '#.#.#', '..#..'],
  ['..#..', '.###.', '#####', '#.#.#', '..#..'],
];

/// Bigger 9 x 9 suit icons for the middle of number cards.
const List<List<String>> _bigSuits = [
  ['.##...##.', '####.####', '#########', '#########', '.#######.', '..#####..', '...###...', '....#....', '.........'],
  ['....#....', '...###...', '..#####..', '.#######.', '#########', '.#######.', '..#####..', '...###...', '....#....'],
  ['...###...', '..#####..', '..#####..', '.#.###.#.', '#########', '####.####', '.##.#.##.', '....#....', '...###...'],
  ['....#....', '...###...', '..#####..', '.#######.', '#########', '#########', '.##.#.##.', '....#....', '...###...'],
];

const int _red = 0xFFDC2626, _ink = 0xFF1F2937;

void _stamp(_Img img, List<String> rows, int ox, int oy, int color, {bool flip = false}) {
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      if (rows[y][x] != '#') continue;
      if (flip) {
        img.set(ox + rows[y].length - 1 - x, oy + rows.length - 1 - y, color);
      } else {
        img.set(ox + x, oy + y, color);
      }
    }
  }
}

/// A rounded white card with a thin border; [fill] for the card body.
void _cardBlank(_Img img, int ox, int oy, {int fill = 0xFFFDFCF7, int border = 0xFF94A3B8}) {
  for (var y = 0; y < _cardH; y++) {
    for (var x = 0; x < _cardW; x++) {
      final corner = (x == 0 || x == _cardW - 1) && (y == 0 || y == _cardH - 1);
      if (corner) continue;
      final edge = x == 0 || y == 0 || x == _cardW - 1 || y == _cardH - 1 ||
          ((x == 1 || x == _cardW - 2) && (y == 1 || y == _cardH - 2));
      img.set(ox + x, oy + y, edge ? border : fill);
    }
  }
}

void _cardFace(_Img img, int ox, int oy, int suit, int rank) {
  _cardBlank(img, ox, oy);
  final color = suit < 2 ? _red : _ink;
  final label = switch (rank) { 1 => 'A', 11 => 'J', 12 => 'Q', 13 => 'K', _ => '$rank' };
  // Corner index: rank over a small suit (top left, and upside down bottom right)
  var x = ox + 3;
  for (final ch in label.split('')) {
    _stamp(img, _glyphs[ch]!, x, oy + 3, color);
    x += _glyphs[ch]![0].length + 1;
  }
  _stamp(img, _suitIcons[suit], ox + 2, oy + 10, color);
  var bx = ox + _cardW - 4;
  for (final ch in label.split('').reversed) {
    bx -= _glyphs[ch]![0].length;
    _stamp(img, _glyphs[ch]!, bx, oy + _cardH - 8, color, flip: true);
    bx -= 1;
  }
  _stamp(img, _suitIcons[suit], ox + _cardW - 7, oy + _cardH - 15, color, flip: true);
  if (rank >= 11) {
    // Court cards: a coloured frame with the big letter and suit
    final frame = suit < 2 ? 0xFFFCA5A5 : 0xFFBFDBFE;
    for (var y = 9; y < _cardH - 9; y++) {
      for (var xx = 8; xx < _cardW - 8; xx++) {
        final edge = y == 9 || y == _cardH - 10 || xx == 8 || xx == _cardW - 9;
        img.set(ox + xx, oy + y, edge ? color : frame);
      }
    }
    final big = _glyphs[label]!;
    for (var y = 0; y < big.length; y++) {
      for (var xx = 0; xx < big[y].length; xx++) {
        if (big[y][xx] != '#') continue;
        for (var dy = 0; dy < 2; dy++) {
          for (var dx = 0; dx < 2; dx++) {
            img.set(ox + 13 + xx * 2 + dx, oy + 12 + y * 2 + dy, color);
          }
        }
      }
    }
    _stamp(img, _suitIcons[suit], ox + 14, oy + 24, color);
  } else {
    _stamp(img, _bigSuits[suit], ox + 12, oy + 18, color);
    if (rank == 1) {
      // The ace gets a gold ring around its suit
      for (var a = 0; a < 48; a++) {
        final t = a / 48 * 6.283;
        img.set(ox + 16 + (math.cos(t) * 8).round(), oy + 22 + (math.sin(t) * 8).round(), 0xFFF59E0B);
      }
    }
  }
}

void _cardBack(_Img img, int ox, int oy) {
  _cardBlank(img, ox, oy, fill: 0xFF9A3412, border: 0xFF431407);
  for (var y = 3; y < _cardH - 3; y++) {
    for (var x = 3; x < _cardW - 3; x++) {
      final lattice = (x + y) % 6 == 0 || (x - y + 60) % 6 == 0;
      final rim = x == 3 || y == 3 || x == _cardW - 4 || y == _cardH - 4;
      img.set(ox + x, oy + y, rim ? 0xFFFDBA74 : (lattice ? 0xFFEA580C : 0xFF7C2D12));
    }
  }
  // An ember in the middle
  _stamp(img, ['..#..', '.###.', '#####', '#####', '.###.'], ox + 14, oy + 19, 0xFFFDE68A);
}

/// An empty pile: a soft outline; [icon] 0 = none, 1 = recycle arrow, 2..5 = a suit for the foundations.
void _emptySlot(_Img img, int ox, int oy, int icon) {
  for (var y = 0; y < _cardH; y++) {
    for (var x = 0; x < _cardW; x++) {
      final edge = x == 0 || y == 0 || x == _cardW - 1 || y == _cardH - 1;
      if ((x == 0 || x == _cardW - 1) && (y == 0 || y == _cardH - 1)) continue;
      img.set(ox + x, oy + y, edge ? 0x99FFFFFF : 0x22000000);
    }
  }
  if (icon == 1) {
    for (var a = 0; a < 40; a++) {
      final t = 0.6 + a / 40 * 5.2;
      img.set(ox + 16 + (math.cos(t) * 7).round(), oy + 22 + (math.sin(t) * 7).round(), 0xAAFFFFFF);
    }
    _stamp(img, ['###', '.##', '..#'], ox + 20, oy + 13, 0xAAFFFFFF);
  }
}

/// cards.png: rows 0-3 = hearts, diamonds, clubs, spades (ranks A..K across),
/// row 4 = back, empty, empty with recycle arrow.
_Img _cardSheet() {
  final sheet = _Img(_cardW * 13, _cardH * 5);
  for (var s = 0; s < 4; s++) {
    for (var r = 1; r <= 13; r++) {
      _cardFace(sheet, (r - 1) * _cardW, s * _cardH, s, r);
    }
  }
  _cardBack(sheet, 0, 4 * _cardH);
  _emptySlot(sheet, _cardW, 4 * _cardH, 0);
  _emptySlot(sheet, _cardW * 2, 4 * _cardH, 1);
  return sheet;
}

/// Green felt with a soft lighter middle and a little grain.
_Img _feltTable() {
  const w = 320, h = 180;
  final img = _Img(w, h);
  final rnd = math.Random(3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = (x - w / 2) / (w / 2), dy = (y - h / 2) / (h / 2);
      final light = 1 - (dx * dx * 0.5 + dy * dy * 0.7).clamp(0.0, 1.0);
      final grain = rnd.nextInt(6);
      final g = (90 + light * 40 + grain).round(), r = (12 + light * 10 + grain ~/ 2).round(), b = (40 + light * 18 + grain ~/ 2).round();
      img.set(x, y, 0xFF000000 | r << 16 | g << 8 | b);
    }
  }
  return img;
}

_Img _cardPanel() {
  const w = 120, h = 80, r = 9;
  final img = _Img(w, h);
  bool inside(int x, int y, int inset) {
    final rr = r - inset;
    final cx = x < r ? r : (x >= w - r ? w - 1 - r : x);
    final cy = y < r ? r : (y >= h - r ? h - 1 - r : y);
    final dx = x - cx, dy = y - cy;
    return x >= inset && y >= inset && x < w - inset && y < h - inset && dx * dx + dy * dy <= rr * rr + rr;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!inside(x, y, 0)) continue;
      img.set(x, y, inside(x, y, 3) ? 0xEE0B2E1F : 0xFFFBBF24);
    }
  }
  return img;
}

/// A calm, swingy loop (F major, 96 bpm).
Uint8List _solitaireTheme() => _chiptune(
      bpm: 96,
      leadAmp: 0.12,
      lead: const [
        (69, 1.0), (72, 0.5), (74, 0.5), (77, 1.0), (76, 1.0), //
        (74, 0.5), (72, 0.5), (69, 1.0), (67, 2.0),
        (65, 1.0), (69, 0.5), (72, 0.5), (74, 1.0), (72, 1.0),
        (70, 0.5), (69, 0.5), (67, 1.0), (65, 2.0),
        (72, 1.0), (77, 1.0), (76, 0.5), (74, 0.5), (72, 1.0),
        (74, 1.0), (70, 1.0), (69, 2.0),
        (67, 0.5), (69, 0.5), (70, 1.0), (72, 1.0), (67, 1.0),
        (65, 4.0),
      ],
      bassRoots: const [41, 41, 46, 46, 41, 41, 48, 48, 38, 38, 46, 46, 48, 48, 41, 41],
    );

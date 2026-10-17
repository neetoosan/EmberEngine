part of 'generate_template_art.dart';

// ---------------------------------------------------------------------------
// Ember Gems (match-3): gems with a different shape per colour (readable
// without colour), special-gem overlays, board cells, ice, stars, music.

const int _gemCell = 20;

void _saveGems(void Function(String folder, String name, _Img img) save) {
  save('gems', 'gems.png', _gemSheet());
  save('gems', 'overlays.png', _gemOverlays());
  save('gems', 'cells.png', _gemCells());
  save('gems', 'background.png', _gemBackground());
  save('gems', 'star.png', _gemStars());
  save('gems', 'panel.png', _gemPanel());
  final music = File('assets/templates/gems/gems.wav')..writeAsBytesSync(_gemsTheme());
  stdout.writeln('wrote ${music.path} (${music.lengthSync() ~/ 1024} KB)');
}

/// Colours per gem: light, base, dark, outline.
const List<List<int>> _gemColors = [
  [0xFFFFB4B4, 0xFFEF4444, 0xFF991B1B, 0xFF450A0A], // 0 ruby (round)
  [0xFFFFE0A3, 0xFFF97316, 0xFFB45309, 0xFF431407], // 1 ember (drop)
  [0xFFFFF7B0, 0xFFFACC15, 0xFFA16207, 0xFF422006], // 2 topaz (diamond)
  [0xFFB7F7C8, 0xFF22C55E, 0xFF15803D, 0xFF052E16], // 3 emerald (square cut)
  [0xFFBFDBFE, 0xFF3B82F6, 0xFF1D4ED8, 0xFF172554], // 4 sapphire (triangle)
  [0xFFF0D0FF, 0xFFA855F7, 0xFF7E22CE, 0xFF2E1065], // 5 amethyst (hexagon)
];

/// True when (x, y), in -1..1 cell coordinates, is inside gem [kind].
bool _insideGem(int kind, double x, double y) {
  switch (kind) {
    case 0:
      return x * x + y * y <= 0.78;
    case 1: // drop: round bottom, point on top
      if (y > -0.05) return x * x + (y - 0.05) * (y - 0.05) * 1.1 <= 0.62;
      return x.abs() <= (y + 0.95) * 0.85 && y >= -0.95;
    case 2:
      return x.abs() + y.abs() <= 0.95;
    case 3: // square with cut corners
      return x.abs() <= 0.78 && y.abs() <= 0.78 && x.abs() + y.abs() <= 1.25;
    case 4: // triangle pointing up
      return y <= 0.75 && y >= -0.9 && x.abs() <= (y + 0.9) * 0.62;
    default: // hexagon
      return y.abs() <= 0.8 && x.abs() * 0.88 + y.abs() * 0.5 <= 0.82;
  }
}

/// One gem: shaded with light from the top left, a dark outline and a glint.
_Img _gem(int kind, {bool rainbow = false}) {
  const n = _gemCell;
  final img = _Img(n, n);
  final c = rainbow ? const [0xFFFFFFFF, 0xFFE5E7EB, 0xFF9CA3AF, 0xFF1F2937] : _gemColors[kind];
  const rainbowBands = [0xFFEF4444, 0xFFF97316, 0xFFFACC15, 0xFF22C55E, 0xFF3B82F6, 0xFFA855F7];
  for (var py = 0; py < n; py++) {
    for (var px = 0; px < n; px++) {
      final x = (px + 0.5) / n * 2 - 1, y = (py + 0.5) / n * 2 - 1;
      if (!_insideGem(rainbow ? 0 : kind, x, y)) continue;
      final light = -x * 0.55 - y * 0.75; // toward the top left
      int col;
      if (rainbow) {
        final band = ((math.atan2(y, x) / math.pi + 1) * 3).floor() % 6;
        col = light > 0.55 ? 0xFFFFFFFF : rainbowBands[band];
      } else {
        col = light > 0.5 ? c[0] : (light < -0.35 ? c[2] : c[1]);
      }
      // Facet line through the middle for the cut-gem look
      if (!rainbow && (kind == 2 || kind == 3) && (x - y).abs() < 0.07) col = c[0];
      img.set(px, py, col);
    }
  }
  img.addOutline(c[3]);
  // Glint
  img.set(6, 5, 0xFFFFFFFF);
  img.set(7, 5, 0xFFFFFFFF);
  img.set(6, 6, 0xFFFFFFFF);
  return img;
}

/// gems.png: 7 frames in a row (6 colours, then the rainbow "ember star").
_Img _gemSheet() {
  final sheet = _Img(_gemCell * 7, _gemCell);
  for (var k = 0; k < 6; k++) {
    sheet.blit(_gem(k), k * _gemCell, 0);
  }
  sheet.blit(_gem(0, rainbow: true), 6 * _gemCell, 0);
  return sheet;
}

/// overlays.png: 0 = row blast (horizontal arrows), 1 = column blast (vertical),
/// 2 = bomb ring, 3 = selection frame, 4 = hint sparkle.
_Img _gemOverlays() {
  const n = _gemCell;
  final sheet = _Img(n * 5, n);
  void arrows(int ox, bool horizontal) {
    for (var i = 2; i < n - 2; i++) {
      final a = horizontal ? (i, 9) : (9, i), b = horizontal ? (i, 10) : (10, i);
      sheet.set(ox + a.$1, a.$2, 0xFFFFFFFF);
      sheet.set(ox + b.$1, b.$2, 0xFFFFFFFF);
    }
    for (var k = 0; k < 4; k++) {
      // arrow heads at both ends
      for (final (p, q) in [(2 + k, 9 - k), (2 + k, 10 + k), (n - 3 - k, 9 - k), (n - 3 - k, 10 + k)]) {
        if (horizontal) {
          sheet.set(ox + p, q, 0xFFFFFFFF);
        } else {
          sheet.set(ox + q, p, 0xFFFFFFFF);
        }
      }
    }
  }

  arrows(0, true);
  arrows(n, false);
  // Bomb: a glowing ring
  for (var py = 0; py < n; py++) {
    for (var px = 0; px < n; px++) {
      final x = (px + 0.5) / n * 2 - 1, y = (py + 0.5) / n * 2 - 1;
      final d = math.sqrt(x * x + y * y);
      if (d > 0.82 && d < 0.98) sheet.set(n * 2 + px, py, 0xFFFFFFFF);
      if (d > 0.7 && d <= 0.82) sheet.set(n * 2 + px, py, 0xCCFDE68A);
    }
  }
  // Selection frame: bright corners
  for (var i = 0; i < 6; i++) {
    for (final (x, y) in [(i, 0), (0, i), (n - 1 - i, 0), (n - 1, i), (i, n - 1), (0, n - 1 - i), (n - 1 - i, n - 1), (n - 1, n - 1 - i)]) {
      sheet.set(n * 3 + x, y, 0xFFFFFFFF);
    }
  }
  // Hint sparkle: a small four-point star
  for (var i = -4; i <= 4; i++) {
    sheet.set(n * 4 + 10 + i, 10, i.abs() < 2 ? 0xFFFFFFFF : 0xCCFFF7B0);
    sheet.set(n * 4 + 10, 10 + i, i.abs() < 2 ? 0xFFFFFFFF : 0xCCFFF7B0);
  }
  return sheet;
}

/// cells.png: 0 / 1 = board cells (two shades), 2 = ice, 3 = cracked ice.
_Img _gemCells() {
  const n = _gemCell;
  final sheet = _Img(n * 4, n);
  for (var f = 0; f < 2; f++) {
    for (var py = 0; py < n; py++) {
      for (var px = 0; px < n; px++) {
        final edge = px == 0 || py == 0 || px == n - 1 || py == n - 1;
        sheet.set(f * n + px, py, edge ? 0xCC1E1B4B : (f == 0 ? 0xCC312E81 : 0xCC2E2A6E));
      }
    }
  }
  for (var f = 0; f < 2; f++) {
    for (var py = 0; py < n; py++) {
      for (var px = 0; px < n; px++) {
        final edge = px <= 1 || py <= 1 || px >= n - 2 || py >= n - 2;
        final shine = (px + py) % 9 == 0 && px > 2 && py > 2;
        sheet.set((2 + f) * n + px, py, edge ? 0xEEE0F2FE : (shine ? 0xCCFFFFFF : 0x88BAE6FD));
      }
    }
  }
  // Cracks on the second ice frame
  for (final (x, y) in [(4, 5), (5, 6), (6, 7), (7, 7), (8, 8), (9, 10), (10, 11), (11, 11), (12, 12), (14, 6), (13, 7), (12, 8), (11, 9), (8, 13), (7, 14), (6, 15)]) {
    sheet.set(3 * n + x, y, 0xFF0C4A6E);
  }
  return sheet;
}

/// A dusky purple sky with soft glowing dots (320 x 180, stretched to fill).
_Img _gemBackground() {
  const w = 320, h = 180;
  final img = _Img(w, h);
  int lerpColor(int a, int b, double t) {
    int ch(int s) => (((a >> s) & 0xFF) + ((((b >> s) & 0xFF) - ((a >> s) & 0xFF)) * t)).round();
    return 0xFF000000 | ch(16) << 16 | ch(8) << 8 | ch(0);
  }

  for (var y = 0; y < h; y++) {
    final c = lerpColor(0xFF1E1B4B, 0xFF4C1D95, y / h);
    for (var x = 0; x < w; x++) {
      img.set(x, y, c);
    }
  }
  final rnd = math.Random(7);
  for (var i = 0; i < 26; i++) {
    final cx = rnd.nextInt(w), cy = rnd.nextInt(h), r = 2 + rnd.nextInt(7);
    for (var y = -r; y <= r; y++) {
      for (var x = -r; x <= r; x++) {
        if (x * x + y * y > r * r) continue;
        final base = img.get(cx + x, cy + y);
        if (base != 0) img.set(cx + x, cy + y, lerpColor(base, 0xFFA78BFA, 0.18));
      }
    }
  }
  for (var i = 0; i < 70; i++) {
    img.set(rnd.nextInt(w), rnd.nextInt(h), 0xFFE9D5FF);
  }
  return img;
}

/// star.png: 0 = earned (gold), 1 = empty.
_Img _gemStars() {
  const n = 16;
  final sheet = _Img(n * 2, n);
  // A five-point star as a 10-corner polygon (point up)
  final pts = [
    for (var i = 0; i < 10; i++)
      (math.cos(-math.pi / 2 + i * math.pi / 5) * (i.isEven ? 0.98 : 0.42), math.sin(-math.pi / 2 + i * math.pi / 5) * (i.isEven ? 0.98 : 0.42) + 0.06),
  ];
  bool inStar(double x, double y) {
    var inside = false;
    for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      final (xi, yi) = pts[i];
      final (xj, yj) = pts[j];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }

  for (var f = 0; f < 2; f++) {
    for (var py = 0; py < n; py++) {
      for (var px = 0; px < n; px++) {
        final x = (px + 0.5) / n * 2 - 1, y = (py + 0.5) / n * 2 - 1;
        if (!inStar(x, y)) continue;
        sheet.set(f * n + px, py, f == 0 ? (y < 0 ? 0xFFFDE68A : 0xFFF59E0B) : 0xFF4B5563);
      }
    }
  }
  sheet.addOutline(0xFF1F1147);
  return sheet;
}

/// A rounded dark panel with a violet rim (level results, title card).
_Img _gemPanel() {
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
      img.set(x, y, inside(x, y, 3) ? 0xEE1E1B4B : 0xFFC084FC);
    }
  }
  return img;
}

/// A bright, bouncy major-key loop (C major, 120 bpm).
Uint8List _gemsTheme() => _chiptune(
      bpm: 120,
      leadAmp: 0.14,
      lead: const [
        (72, 0.5), (76, 0.5), (79, 0.5), (76, 0.5), (77, 1.0), (74, 1.0), //
        (72, 0.5), (74, 0.5), (76, 0.5), (79, 0.5), (81, 2.0),
        (79, 0.5), (77, 0.5), (76, 0.5), (74, 0.5), (72, 1.0), (69, 1.0),
        (71, 0.5), (72, 0.5), (74, 0.5), (71, 0.5), (72, 2.0),
        (76, 1.0), (79, 1.0), (84, 1.0), (83, 0.5), (81, 0.5),
        (79, 1.0), (77, 0.5), (76, 0.5), (74, 2.0),
        (72, 0.5), (74, 0.5), (76, 0.5), (77, 0.5), (79, 1.0), (76, 1.0),
        (74, 1.0), (71, 1.0), (72, 2.0),
      ],
      bassRoots: const [48, 48, 53, 53, 45, 45, 43, 48, 52, 52, 53, 50, 48, 45, 43, 48],
    );

part of 'generate_template_art.dart';

// ---------------------------------------------------------------------------
// Ember Siege art (physics slingshot game). Sprites are drawn at 2x in the game.

void _saveSiege(void Function(String folder, String name, _Img img) save) {
  for (final m in _SiegeMaterial.values) {
    save('siege', '${m.name}_post.png', _blockSheet(m, 10, 48));
    save('siege', '${m.name}_beam.png', _blockSheet(m, 48, 10));
    save('siege', '${m.name}_long.png', _blockSheet(m, 72, 10));
    save('siege', '${m.name}_block.png', _blockSheet(m, 20, 20));
  }
  save('siege', 'imp.png', _imp());
  save('siege', 'ember.png', _emberShot());
  save('siege', 'coal.png', _coalShot());
  save('siege', 'spark.png', _sparkShot());
  save('siege', 'keg.png', _keg());
  save('siege', 'slingshot.png', _slingshot());
  save('siege', 'sky.png', _siegeSky());
  save('siege', 'stars.png', _siegeStars());
  save('siege', 'mountains.png', _mountains());
  save('siege', 'pines.png', _pines());
  save('siege', 'tiles.png', _siegeTiles());
  save('siege', 'star.png', _starIcons());
  save('siege', 'shots.png', _shotIcons());
  save('siege', 'panel.png', _panel());
  final f = File('assets/templates/siege/siege.wav')..writeAsBytesSync(_siegeTheme());
  stdout.writeln('wrote ${f.path} (${f.lengthSync() ~/ 1024} KB)');
}

enum _SiegeMaterial { wood, ice, stone }

/// Small deterministic hash for texture noise.
int _hash(int x, int y, int seed) {
  var h = x * 374761393 + y * 668265263 + seed * 1442695041;
  h = (h ^ (h >> 13)) * 1274126177;
  return (h ^ (h >> 16)) & 0x7fffffff;
}

/// Three frames side by side: intact, cracked, badly cracked.
_Img _blockSheet(_SiegeMaterial m, int w, int h) {
  final sheet = _Img(w * 3, h);
  for (var f = 0; f < 3; f++) {
    final cell = _blockTexture(m, w, h);
    _cracks(cell, m, f, w + h * 7);
    sheet.blit(cell, f * w, 0);
  }
  return sheet;
}

_Img _blockTexture(_SiegeMaterial m, int w, int h) {
  final img = _Img(w, h);
  final horizontal = w >= h;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final edge = x == 0 || y == 0 || x == w - 1 || y == h - 1;
      final n = _hash(x, y, w * 31 + h) % 100;
      int c;
      switch (m) {
        case _SiegeMaterial.wood:
          const outline = 0xFF3B220E, base = 0xFFA0662F, dark = 0xFF7A4A1F, light = 0xFFC9894A;
          if (edge) {
            c = outline;
          } else {
            final along = horizontal ? x : y, across = horizontal ? y : x;
            final grain = (across % 4 == 2) && (_hash(along ~/ 5, across, 7) % 3 != 0);
            c = grain ? dark : (across == 1 ? light : base);
            if (n < 4) c = dark;
            // Nails near the ends
            final end = horizontal ? (x == 2 || x == w - 3) : (y == 2 || y == h - 3);
            final mid = horizontal ? (y == h ~/ 2) : (x == w ~/ 2);
            if (end && mid) c = 0xFFD6D3D1;
          }
        case _SiegeMaterial.ice:
          const outline = 0xFF2B6F91, base = 0xD89ADCF5, light = 0xF2E8FAFF, dark = 0xD86BBCE0;
          if (edge) {
            c = outline;
          } else if (x == 1 || y == 1) {
            c = light;
          } else if ((x + y) % 9 == 0 || (x + y) % 9 == 1 && n < 50) {
            c = light;
          } else {
            c = n < 12 ? dark : base;
          }
        case _SiegeMaterial.stone:
          const outline = 0xFF34373D, mortar = 0xFF5F646C;
          if (edge) {
            c = outline;
          } else {
            final row = (y - 1) ~/ 5;
            final off = row.isOdd ? 5 : 0;
            final isMortar = (y - 1) % 5 == 4 || (x - 1 + off) % 10 == 9;
            if (isMortar) {
              c = mortar;
            } else {
              final brick = _hash((x - 1 + off) ~/ 10, row, 3) % 3;
              c = [0xFF8A8F98, 0xFF9399A2, 0xFF7E838C][brick];
              if ((y - 1) % 5 == 0) c = 0xFFB4B9C1;
              if (n < 5) c = 0xFF6E737B;
            }
          }
      }
      img.set(x, y, c);
    }
  }
  return img;
}

/// Random-walk cracks from the middle: none on frame 0, more on later frames.
void _cracks(_Img img, _SiegeMaterial m, int frame, int seed) {
  if (frame == 0) return;
  final color = switch (m) {
    _SiegeMaterial.wood => 0xFF2A1708,
    _SiegeMaterial.ice => 0xFFF8FFFF,
    _SiegeMaterial.stone => 0xFF26282C,
  };
  final rng = math.Random(seed);
  final walks = frame == 1 ? 2 : 5;
  for (var k = 0; k < walks; k++) {
    var x = img.w / 2 + rng.nextInt(3) - 1, y = img.h / 2 + rng.nextInt(3) - 1;
    final a = rng.nextDouble() * math.pi * 2;
    var dx = math.cos(a), dy = math.sin(a);
    final steps = (math.max(img.w, img.h) * (frame == 1 ? 0.35 : 0.55)).round();
    for (var s = 0; s < steps; s++) {
      img.set(x.round(), y.round(), color);
      x += dx;
      y += dy;
      if (rng.nextDouble() < 0.3) {
        final turn = (rng.nextDouble() - 0.5) * 1.2;
        final ndx = dx * math.cos(turn) - dy * math.sin(turn);
        dy = dx * math.sin(turn) + dy * math.cos(turn);
        dx = ndx;
      }
    }
  }
}

/// Frost imp, 18x18: idle, blink, hurt.
_Img _imp() {
  final sheet = _Img(54, 18);
  for (var f = 0; f < 3; f++) {
    final img = _Img(18, 18);
    final body = f == 2 ? 0xFF93C5FD : 0xFF60A5FA;
    final belly = f == 2 ? 0xFFDBEAFE : 0xFFBFDBFE;
    for (var y = 0; y < 18; y++) {
      for (var x = 0; x < 18; x++) {
        final dx = (x - 8.5) / 7.2, dy = (y - 10.0) / 6.4;
        if (dx * dx + dy * dy <= 1) {
          final bx = (x - 8.5) / 4.6, by = (y - 12.5) / 3.2;
          img.set(x, y, bx * bx + by * by <= 1 ? belly : body);
        }
      }
    }
    // Ice horns
    for (final hx in [4, 13]) {
      img.set(hx, 2, 0xFFF8FAFC);
      img.set(hx, 3, 0xFFF8FAFC);
      img.set(hx + (hx < 9 ? 1 : -1), 3, 0xFFE2E8F0);
      img.set(hx + (hx < 9 ? 1 : -1), 4, 0xFFE2E8F0);
    }
    // Eyes
    for (final ex in [6, 11]) {
      if (f == 1) {
        img.set(ex - 1, 9, 0xFF1E1B4B);
        img.set(ex, 9, 0xFF1E1B4B);
      } else if (f == 2) {
        img.set(ex - 1, 8, 0xFF1E1B4B);
        img.set(ex, 9, 0xFF1E1B4B);
        img.set(ex - 1, 9, 0xFF1E1B4B);
        img.set(ex, 8, 0xFF1E1B4B);
      } else {
        img.set(ex - 1, 8, 0xFFF8FAFC);
        img.set(ex, 8, 0xFFF8FAFC);
        img.set(ex - 1, 9, 0xFFF8FAFC);
        img.set(ex, 9, 0xFF1E1B4B);
        img.set(ex - 1, 7, 0xFF1E3A8A); // angry brows
        img.set(ex + (ex < 9 ? 0 : -1), 7, 0xFF1E3A8A);
      }
    }
    // Grin with fangs
    for (var x = 7; x <= 10; x++) {
      img.set(x, 12, 0xFF1E1B4B);
    }
    img.set(7, 13, 0xFFF8FAFC);
    img.set(10, 13, 0xFFF8FAFC);
    img.addOutline(0xFF172554);
    sheet.blit(img, f * 18, 0);
  }
  return sheet;
}

/// Round shot with a radial gradient [colors] (centre to edge), 2 flicker frames.
_Img _roundShot(int size, List<int> colors, int outline, {bool face = false, int? Function(int x, int y, int f)? extra}) {
  final sheet = _Img(size * 2, size);
  final r = size / 2 - 1.2;
  for (var f = 0; f < 2; f++) {
    final img = _Img(size, size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final dx = x + 0.5 - size / 2 - 0.6, dy = y + 0.5 - size / 2 - 0.6;
        final d = math.sqrt(dx * dx + dy * dy) / r;
        if (d > 1) continue;
        final i = (d * colors.length + (f == 1 ? 0.35 : 0)).floor().clamp(0, colors.length - 1);
        img.set(x, y, extra?.call(x, y, f) ?? colors[i]);
      }
    }
    if (face) {
      final c = size ~/ 2;
      img.set(c - 2, c - 1, 0xFF3B0A0A);
      img.set(c + 1, c - 1, 0xFF3B0A0A);
      img.set(c - 3, c - 2, 0xFF3B0A0A); // determined brows
      img.set(c + 2, c - 2, 0xFF3B0A0A);
    }
    // Flame tips
    if (f == 0) {
      img.set(size ~/ 2 - 2, 0, colors[1]);
      img.set(size ~/ 2 + 1, 1, colors[1]);
    } else {
      img.set(size ~/ 2, 0, colors[1]);
      img.set(size ~/ 2 - 3, 1, colors[1]);
    }
    img.addOutline(outline);
    sheet.blit(img, f * size, 0);
  }
  return sheet;
}

_Img _emberShot() => _roundShot(14, const [0xFFFFF3B0, 0xFFFDBA4A, 0xFFF97316, 0xFFDC2626], 0xFF3B0A0A, face: true);

_Img _coalShot() => _roundShot(14, const [0xFF3F3F46, 0xFF27272A, 0xFF18181B], 0xFF09090B,
    extra: (x, y, f) => (_hash(x, y, 9) % 7 == 0 || (x + 2 * y) % 11 == 0) ? (f == 0 ? 0xFFF97316 : 0xFFFDBA4A) : null);

_Img _sparkShot() => _roundShot(12, const [0xFFFFFFFF, 0xFFFEF08A, 0xFFFACC15], 0xFF854D0E, face: true);

/// Powder keg, 18x22.
_Img _keg() {
  final img = _Img(18, 22);
  for (var y = 3; y < 22; y++) {
    for (var x = 0; x < 18; x++) {
      final bulge = math.sin((y - 3) / 18 * math.pi) * 2;
      if (x < 2 - bulge || x > 15 + bulge) continue;
      var c = (x < 5) ? 0xFF991B1B : (x > 12 ? 0xFF7F1D1D : 0xFFB91C1C);
      if (y == 6 || y == 7 || y == 17 || y == 18) c = 0xFF44403C; // iron bands
      img.set(x, y, c);
    }
  }
  // "!" label
  for (var y = 9; y <= 13; y++) {
    img.set(8, y, 0xFFFACC15);
    img.set(9, y, 0xFFFACC15);
  }
  img.set(8, 15, 0xFFFACC15);
  img.set(9, 15, 0xFFFACC15);
  // Fuse and spark
  img.set(9, 2, 0xFFD6D3D1);
  img.set(10, 1, 0xFFD6D3D1);
  img.set(11, 0, 0xFFFDBA4A);
  img.addOutline(0xFF1C0A0A);
  return img;
}

/// Wooden Y-shaped slingshot, 24x60.
_Img _slingshot() {
  final img = _Img(24, 60);
  const wood = 0xFF8B5A2B, light = 0xFFB07A42, strap = 0xFF3F2A1A;
  void thick(double x0, double y0, double x1, double y1, int w) {
    final steps = (math.max((x1 - x0).abs(), (y1 - y0).abs()) * 2).ceil();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t;
      for (var k = 0; k < w; k++) {
        img.set(x.round() + k, y.round(), k == 0 ? light : wood);
      }
    }
  }

  thick(10, 59, 10, 30, 4); // trunk
  thick(10, 31, 3, 18, 3); // left arm
  thick(3, 18, 3, 4, 3);
  thick(12, 31, 18, 18, 3); // right arm
  thick(18, 18, 18, 4, 3);
  for (final x in [3, 18]) {
    for (var y = 6; y <= 9; y++) {
      for (var k = 0; k < 3; k++) {
        img.set(x + k, y, strap);
      }
    }
  }
  // Grass tuft at the foot
  for (var x = 6; x <= 17; x++) {
    if (x % 2 == 0) img.set(x, 58, 0xFFE2E8F0);
  }
  img.addOutline(0xFF2A1708);
  return img;
}

/// Night-to-dusk sky gradient, 4x90 (stretched behind everything).
_Img _siegeSky() {
  final img = _Img(4, 90);
  const stops = [(0.0, 0xFF0B1026), (0.45, 0xFF27235C), (0.78, 0xFF6D3B7D), (1.0, 0xFFE07A5F)];
  int lerpColor(int a, int b, double t) {
    int ch(int s) => (((a >> s) & 0xFF) + ((((b >> s) & 0xFF) - ((a >> s) & 0xFF)) * t)).round();
    return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }

  for (var y = 0; y < 90; y++) {
    final t = y / 89;
    var c = stops.last.$2;
    for (var i = 0; i < stops.length - 1; i++) {
      if (t >= stops[i].$1 && t <= stops[i + 1].$1) {
        c = lerpColor(stops[i].$2, stops[i + 1].$2, (t - stops[i].$1) / (stops[i + 1].$1 - stops[i].$1));
        break;
      }
    }
    for (var x = 0; x < 4; x++) {
      img.set(x, y, c);
    }
  }
  return img;
}

_Img _siegeStars() {
  final img = _Img(160, 60);
  for (var y = 0; y < 60; y++) {
    for (var x = 0; x < 160; x++) {
      final n = _hash(x, y, 77) % 1000;
      if (n < 6) img.set(x, y, 0xFFF8FAFC);
      if (n >= 6 && n < 10) img.set(x, y, 0x99BFDBFE);
    }
  }
  return img;
}

/// Snowy mountain silhouettes, 160x45 (drawn at 4x, tiles sideways).
_Img _mountains() {
  final img = _Img(160, 45);
  for (var x = 0; x < 160; x++) {
    final t = x / 160 * math.pi * 2;
    final hFar = 26 + 9 * math.sin(t * 2 + 0.4) + 5 * math.sin(t * 5 + 1.1);
    final hNear = 16 + 8 * math.sin(t * 3 + 2.0) + 3 * math.sin(t * 7);
    for (var y = 0; y < 45; y++) {
      final fromBottom = 45 - y;
      if (fromBottom <= hNear) {
        img.set(x, y, fromBottom > hNear - 2.5 && hNear > 21 ? 0xFFCBD5E1 : 0xFF2E2A5A);
      } else if (fromBottom <= hFar) {
        img.set(x, y, fromBottom > hFar - 3.5 && hFar > 30 ? 0xFFE2E8F0 : 0xFF433E7A);
      }
    }
  }
  return img;
}

/// Row of snowy pines, 128x32 (tiles sideways).
_Img _pines() {
  final img = _Img(128, 32);
  for (var i = 0; i < 9; i++) {
    final cx = i * 14 + 4 + _hash(i, 0, 5) % 6;
    final height = 18 + _hash(i, 1, 5) % 12;
    for (var y = 0; y < height; y++) {
      final half = (y / height * 6 + 1).floor();
      final row = 32 - height + y;
      for (var x = cx - half; x <= cx + half; x++) {
        final snow = y % 6 == 0 && (x - cx).abs() < half;
        img.set(x % 128, row, snow ? 0xFFE2E8F0 : 0xFF1E2A3A);
      }
    }
    img.set(cx, 31, 0xFF3F2A1A);
  }
  for (var x = 0; x < 128; x++) {
    img.set(x, 31, 0xFF1E2A3A);
  }
  return img;
}

/// Ground tileset: 4 columns x 2 rows of 16px cells.
/// 1 snow-topped earth, 2 frozen earth, 3 deep earth, 4 castle stone,
/// 5 ice, 6 snow, 7 dark rock, 8 snowy stone.
_Img _siegeTiles() {
  final sheet = _Img(64, 32);
  void cell(int id, int Function(int x, int y) color) {
    final ox = ((id - 1) % 4) * 16, oy = ((id - 1) ~/ 4) * 16;
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        sheet.set(ox + x, oy + y, color(x, y));
      }
    }
  }

  int earth(int x, int y, int seed) {
    final n = _hash(x, y, seed) % 100;
    if (n < 6) return 0xFF7C6A58;
    if (n < 14) return 0xFF4A3A2E;
    return 0xFF5B4636;
  }

  cell(1, (x, y) {
    final edge = 4 + (_hash(x, 0, 2) % 2);
    if (y < edge) return y == 0 ? 0xFFF8FAFC : (y == edge - 1 ? 0xFFBFDBFE : 0xFFE2E8F0);
    return earth(x, y, 1);
  });
  cell(2, (x, y) => earth(x, y, 2));
  cell(3, (x, y) {
    final n = _hash(x, y, 3) % 100;
    return n < 8 ? 0xFF6B6B6B : (n < 20 ? 0xFF2E241C : 0xFF3F2F25);
  });
  cell(4, (x, y) {
    final row = y ~/ 5;
    final mortar = y % 5 == 4 || (x + (row.isOdd ? 4 : 0)) % 8 == 7;
    return mortar ? 0xFF4B5058 : (y % 5 == 0 ? 0xFF9CA3AF : 0xFF7E838C);
  });
  cell(5, (x, y) => (x + y) % 7 == 0 ? 0xFFE8FAFF : (x == 0 || y == 0 ? 0xFFBFE9FA : 0xFF8FD3F0));
  cell(6, (x, y) => _hash(x, y, 6) % 100 < 8 ? 0xFFBFDBFE : 0xFFF1F5F9);
  cell(7, (x, y) => _hash(x, y, 7) % 100 < 10 ? 0xFF52525B : 0xFF3F3F46);
  cell(8, (x, y) {
    if (y < 4) return y == 0 ? 0xFFF8FAFC : 0xFFE2E8F0;
    final mortar = y % 5 == 3 || (x + ((y ~/ 5).isOdd ? 4 : 0)) % 8 == 7;
    return mortar ? 0xFF4B5058 : 0xFF7E838C;
  });
  return sheet;
}

/// Star icons for results: filled, empty (16x16 each).
_Img _starIcons() {
  final sheet = _Img(32, 16);
  for (var f = 0; f < 2; f++) {
    final img = _Img(16, 16);
    final pts = <math.Point<double>>[];
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? 7.4 : 3.2;
      pts.add(math.Point(7.5 + r * math.cos(a), 8.2 + r * math.sin(a)));
    }
    bool inside(double x, double y) {
      var c = false;
      for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        if ((pts[i].y > y) != (pts[j].y > y) && x < (pts[j].x - pts[i].x) * (y - pts[i].y) / (pts[j].y - pts[i].y) + pts[i].x) c = !c;
      }
      return c;
    }

    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        if (!inside(x + 0.5, y + 0.5)) continue;
        img.set(x, y, f == 0 ? (y < 7 ? 0xFFFDE68A : 0xFFFACC15) : 0xFF475569);
      }
    }
    img.addOutline(f == 0 ? 0xFF78350F : 0xFF1E293B);
    sheet.blit(img, f * 16, 0);
  }
  return sheet;
}

/// HUD shot icons: ready ember, spent ash (12x12 each).
_Img _shotIcons() {
  final sheet = _Img(24, 12);
  for (var f = 0; f < 2; f++) {
    final img = _Img(12, 12);
    for (var y = 0; y < 12; y++) {
      for (var x = 0; x < 12; x++) {
        final dx = x - 5.5, dy = y - 6.0;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d > 4.6) continue;
        img.set(x, y, f == 0 ? (d < 2 ? 0xFFFFF3B0 : (d < 3.5 ? 0xFFF97316 : 0xFFDC2626)) : (d < 2.5 ? 0xFF6B7280 : 0xFF4B5563));
      }
    }
    img.set(5, 0, f == 0 ? 0xFFFDBA4A : 0xFF6B7280);
    img.addOutline(f == 0 ? 0xFF3B0A0A : 0xFF1F2937);
    sheet.blit(img, f * 12, 0);
  }
  return sheet;
}

/// Results panel background, 64x44 (stretched).
_Img _panel() {
  final img = _Img(64, 44);
  for (var y = 0; y < 44; y++) {
    for (var x = 0; x < 64; x++) {
      final edge = x < 2 || y < 2 || x > 61 || y > 41;
      final inner = x == 2 || y == 2 || x == 61 || y == 41;
      img.set(x, y, edge ? 0xFF7C2D12 : (inner ? 0xFFF59E0B : (y < 12 ? 0xF02A2350 : 0xF01E1B2E)));
    }
  }
  return img;
}

/// Ember Siege march, an original loop.
Uint8List _siegeTheme() => _chiptune(
      bpm: 126,
      leadAmp: 0.17,
      lead: const [
        (67, 0.5), (67, 0.5), (72, 1.0), (71, 0.5), (69, 0.5), (67, 1.0), //
        (64, 1.0), (65, 0.5), (67, 0.5), (69, 2.0),
        (69, 0.5), (69, 0.5), (74, 1.0), (72, 0.5), (71, 0.5), (69, 1.0),
        (67, 1.0), (71, 0.5), (74, 0.5), (72, 2.0),
        (76, 1.0), (74, 0.5), (72, 0.5), (71, 1.0), (69, 1.0),
        (67, 0.5), (69, 0.5), (71, 1.0), (72, 2.0),
        (74, 1.0), (72, 0.5), (71, 0.5), (69, 1.0), (71, 1.0),
        (67, 1.0), (62, 1.0), (67, 2.0),
      ],
      bassRoots: const [48, 48, 41, 43, 50, 50, 43, 48, 52, 50, 48, 43, 50, 43, 48, 48],
    );

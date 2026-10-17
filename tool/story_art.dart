part of 'generate_template_art.dart';

// ---------------------------------------------------------------------------
// The Last Ember (visual novel sample): backgrounds and two characters with
// four expressions each (neutral, happy, sad, surprised).

const int _bustW = 80, _bustH = 120;

void _saveStory(void Function(String folder, String name, _Img img) save) {
  save('story', 'forge.png', _storyForge());
  save('story', 'village.png', _storyVillage());
  save('story', 'hill.png', _storyHill());
  save('story', 'dawn.png', _storyDawn());
  save('story', 'mira.png', _bustSheet(_mira));
  save('story', 'kai.png', _bustSheet(_kai));
  final music = File('assets/templates/story/theme.wav')..writeAsBytesSync(_storyTheme());
  stdout.writeln('wrote ${music.path} (${music.lengthSync() ~/ 1024} KB)');
}

int _blend(int a, int b, double t) {
  int ch(int s) => (((a >> s) & 0xFF) + ((((b >> s) & 0xFF) - ((a >> s) & 0xFF)) * t.clamp(0.0, 1.0))).round();
  return 0xFF000000 | ch(16) << 16 | ch(8) << 8 | ch(0);
}

void _fillRect(_Img img, int x0, int y0, int w, int h, int c) {
  for (var y = y0; y < y0 + h; y++) {
    for (var x = x0; x < x0 + w; x++) {
      img.set(x, y, c);
    }
  }
}

void _disc(_Img img, double cx, double cy, double rx, double ry, int Function(double dx, double dy) color) {
  for (var y = (cy - ry).floor(); y <= (cy + ry).ceil(); y++) {
    for (var x = (cx - rx).floor(); x <= (cx + rx).ceil(); x++) {
      final dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry;
      if (dx * dx + dy * dy <= 1) img.set(x, y, color(dx, dy));
    }
  }
}

void _glow(_Img img, num cx, num cy, num r, int color, double strength) {
  for (var y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
    for (var x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
      final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / r;
      if (d >= 1) continue;
      final base = img.get(x, y);
      if (base == 0) continue;
      img.set(x, y, _blend(base, color, (1 - d) * (1 - d) * strength));
    }
  }
}

// --- Backgrounds (320 x 180)

_Img _storyForge() {
  const w = 320, h = 180;
  final img = _Img(w, h);
  final rnd = math.Random(11);
  // Brick wall
  for (var y = 0; y < 128; y++) {
    for (var x = 0; x < w; x++) {
      final row = y ~/ 8, offset = row.isEven ? 0 : 8;
      final mortar = y % 8 == 7 || (x + offset) % 16 == 15;
      final shade = rnd.nextInt(8);
      img.set(x, y, mortar ? 0xFF1C1210 : _blend(0xFF3B2320, 0xFF4A2B25, shade / 8));
    }
  }
  // Floor
  for (var y = 128; y < h; y++) {
    for (var x = 0; x < w; x++) {
      img.set(x, y, _blend(0xFF2A211E, 0xFF15100E, (y - 128) / 52.0 + (x % 23 == 0 ? 0.1 : 0)));
    }
  }
  // Furnace: a stone arch with a fire inside
  _fillRect(img, 120, 46, 80, 82, 0xFF4B4B52);
  _disc(img, 160, 86, 30, 30, (dx, dy) => dy < 0.55 ? _blend(0xFFFFE08A, 0xFF7C2D12, math.sqrt(dx * dx + dy * dy)) : 0xFF4B4B52);
  _fillRect(img, 130, 104, 60, 24, 0xFF2B1A12);
  for (var i = 0; i < 40; i++) {
    img.set(132 + rnd.nextInt(56), 108 + rnd.nextInt(18), rnd.nextBool() ? 0xFFF97316 : 0xFFFDE68A);
  }
  // Chimney hood
  for (var y = 30; y < 46; y++) {
    final inset = (46 - y) ~/ 2;
    _fillRect(img, 112 + inset, y, 96 - inset * 2, 1, 0xFF3A3A40);
  }
  _fillRect(img, 150, 0, 20, 30, 0xFF34343A);
  // Anvil
  _fillRect(img, 230, 120, 44, 8, 0xFF2D3036);
  _fillRect(img, 240, 128, 24, 10, 0xFF25282D);
  _fillRect(img, 234, 138, 36, 6, 0xFF2D3036);
  _fillRect(img, 222, 118, 14, 4, 0xFF2D3036);
  // Tools on the wall
  for (var i = 0; i < 4; i++) {
    final x = 30 + i * 18;
    _fillRect(img, x, 40, 2, 34, 0xFF6B4423);
    _fillRect(img, x - 3, 70, 8, 6, 0xFF71717A);
  }
  _fillRect(img, 24, 38, 72, 2, 0xFF5A3A1E);
  // Warm light from the fire
  _glow(img, 160, 96, 150, 0xFFF97316, 0.45);
  return img;
}

_Img _storyVillage() {
  const w = 320, h = 180;
  final img = _Img(w, h);
  for (var y = 0; y < h; y++) {
    final c = y < 100 ? _blend(0xFF2E1065, 0xFFF97316, y / 110.0) : 0xFF1F1A24;
    for (var x = 0; x < w; x++) {
      img.set(x, y, c);
    }
  }
  final rnd = math.Random(5);
  // Houses
  var x = 0;
  while (x < w) {
    final hw = 34 + rnd.nextInt(22), hh = 40 + rnd.nextInt(26);
    final top = 118 - hh;
    final wall = _blend(0xFF2A1F2E, 0xFF3B2A35, rnd.nextDouble());
    _fillRect(img, x, top, hw, hh + 20, wall);
    for (var r = 0; r < hw ~/ 2 + 4; r++) {
      _fillRect(img, x - 3 + r, top - r ~/ 1.4 + 0, hw + 6 - r * 2, 1, 0xFF241A22);
    }
    for (var wy = top + 10; wy < 112; wy += 16) {
      for (var wx = x + 6; wx < x + hw - 8; wx += 14) {
        if (rnd.nextInt(3) == 0) continue;
        _fillRect(img, wx, wy, 6, 8, 0xFFFBBF24);
        _glow(img, wx + 3, wy + 4, 10, 0xFFFBBF24, 0.35);
      }
    }
    x += hw + 4;
  }
  // Street
  for (var y = 132; y < h; y++) {
    for (var xx = 0; xx < w; xx++) {
      final stone = (xx + (y ~/ 6) * 5) % 12 == 0 || y % 6 == 0;
      img.set(xx, y, stone ? 0xFF15121A : _blend(0xFF2B2530, 0xFF1A1620, (y - 132) / 48.0));
    }
  }
  return img;
}

_Img _storyHill() {
  const w = 320, h = 180;
  final img = _Img(w, h);
  for (var y = 0; y < h; y++) {
    final c = _blend(0xFF050816, 0xFF1E1B4B, y / 140.0);
    for (var x = 0; x < w; x++) {
      img.set(x, y, c);
    }
  }
  final rnd = math.Random(9);
  for (var i = 0; i < 160; i++) {
    img.set(rnd.nextInt(w), rnd.nextInt(120), rnd.nextInt(4) == 0 ? 0xFFFFFFFF : 0xFF94A3B8);
  }
  _disc(img, 250, 36, 14, 14, (dx, dy) => dx + dy < -0.6 ? 0xFFFFFFFF : 0xFFE2E8F0);
  _glow(img, 250, 36, 50, 0xFF94A3B8, 0.3);
  // Hills
  for (var x = 0; x < w; x++) {
    final far = (118 + math.sin(x / 40) * 10 + math.sin(x / 13) * 3).round();
    final near = (140 + math.sin(x / 55 + 1) * 12).round();
    for (var y = far; y < h; y++) {
      img.set(x, y, y >= near ? 0xFF0B1220 : 0xFF141B2E);
    }
  }
  // Lanterns on the path
  for (final (lx, ly) in [(60, 146), (110, 150), (170, 154), (220, 150)]) {
    _fillRect(img, lx, ly - 12, 1, 12, 0xFF3F3F46);
    _fillRect(img, lx - 2, ly - 16, 5, 5, 0xFFFDBA74);
    _glow(img, lx, ly - 14, 18, 0xFFF97316, 0.5);
  }
  return img;
}

_Img _storyDawn() {
  const w = 320, h = 180;
  final img = _Img(w, h);
  for (var y = 0; y < h; y++) {
    final c = y < 60 ? _blend(0xFF60A5FA, 0xFFFDE68A, y / 60.0) : _blend(0xFFFDE68A, 0xFFF97316, (y - 60) / 60.0);
    for (var x = 0; x < w; x++) {
      img.set(x, y, c);
    }
  }
  _disc(img, 160, 120, 28, 28, (dx, dy) => 0xFFFFFBEB);
  _glow(img, 160, 116, 120, 0xFFFFFBEB, 0.5);
  for (var x = 0; x < w; x++) {
    final hill = (118 + math.sin(x / 30) * 8 + math.sin(x / 9) * 2).round();
    for (var y = hill; y < h; y++) {
      img.set(x, y, _blend(0xFF7C2D12, 0xFF3B0A0A, (y - hill) / 40.0));
    }
  }
  // The forge's chimney with a thin new smoke
  _fillRect(img, 70, 84, 26, 40, 0xFF451A03);
  _fillRect(img, 84, 64, 8, 22, 0xFF3B1503);
  for (var i = 0; i < 26; i++) {
    _disc(img, 88 + math.sin(i / 3) * 4 + i * 0.6, 60.0 - i * 2.2, 3 + i / 9, 3 + i / 9, (dx, dy) => 0xFFE7E5E4);
  }
  return img;
}

// --- Characters (80 x 120 per expression)

class _BustLook {
  final int skin, skinShade, hair, hairShade, eye, cloth, clothShade, accent;
  final void Function(_Img img, int ox, _BustLook look) hairBack, hairFront;
  final void Function(_Img img, int ox, _BustLook look) clothes;
  const _BustLook(this.skin, this.skinShade, this.hair, this.hairShade, this.eye, this.cloth, this.clothShade, this.accent,
      {required this.hairBack, required this.hairFront, required this.clothes});
}

final _mira = _BustLook(0xFFF5C9A6, 0xFFD9A07E, 0xFFE2622B, 0xFFA8401A, 0xFF7C4A1E, 0xFFEFE6D4, 0xFFC9BBA0, 0xFF7C4A2A,
    hairBack: (img, ox, l) {
      _disc(img, ox + 40.0, 47, 21, 23, (dx, dy) => dx > 0.4 ? l.hairShade : l.hair);
      _disc(img, ox + 40.0, 22, 9, 8, (dx, dy) => dx > 0.3 ? l.hairShade : l.hair); // bun
    },
    hairFront: (img, ox, l) {
      // Bangs and side locks
      for (var x = 22; x < 59; x++) {
        final fringe = 38 + ((x * 7) % 5) - ((x - 40).abs() ~/ 7);
        for (var y = 28; y < fringe; y++) {
          img.set(ox + x, y, x > 46 ? l.hairShade : l.hair);
        }
      }
      _fillRect(img, ox + 21, 38, 4, 30, l.hair);
      _fillRect(img, ox + 55, 38, 4, 30, l.hairShade);
    },
    clothes: (img, ox, l) {
      // Shirt and a leather apron
      for (var y = 84; y < _bustH; y++) {
        final half = 18 + (y - 84);
        _fillRect(img, ox + 40 - half, y, half * 2, 1, y < 92 ? l.cloth : l.clothShade);
      }
      for (var y = 92; y < _bustH; y++) {
        final half = 12 + (y - 92) ~/ 2;
        _fillRect(img, ox + 40 - half, y, half * 2, 1, l.accent);
      }
      _fillRect(img, ox + 28, 88, 2, 8, l.accent);
      _fillRect(img, ox + 50, 88, 2, 8, l.accent);
    });

final _kai = _BustLook(0xFFE8C2A0, 0xFFC99A78, 0xFFE5E7EB, 0xFF9CA3AF, 0xFF1D4ED8, 0xFF1E3A8A, 0xFF172554, 0xFF93C5FD,
    hairBack: (img, ox, l) {
      // A hood that falls onto the cloak: narrow at the top, wide at the shoulders
      for (var y = 22; y < 90; y++) {
        final t = (y - 22) / 68;
        final half = (14 + 16 * math.sqrt(t)).round();
        for (var x = 40 - half; x < 40 + half; x++) {
          img.set(ox + x, y, x > 40 + half * 0.35 ? l.clothShade : l.cloth);
        }
      }
      _disc(img, ox + 40.0, 47, 19, 21, (dx, dy) => dx > 0.4 ? l.hairShade : l.hair);
    },
    hairFront: (img, ox, l) {
      // Messy pale spikes
      for (var x = 23; x < 58; x++) {
        final spike = 37 + ((x * 5) % 6) - ((x - 40).abs() ~/ 6);
        for (var y = 27; y < spike; y++) {
          img.set(ox + x, y, x > 47 || y >= spike - 1 ? l.hairShade : l.hair);
        }
      }
    },
    clothes: (img, ox, l) {
      for (var y = 82; y < _bustH; y++) {
        final half = 20 + (y - 82);
        for (var x = 40 - half; x < 40 + half; x++) {
          // The cloak falls open in front, showing a darker tunic
          final open = (x - 40).abs() < (y - 82) ~/ 3 + 2;
          img.set(ox + x, y, open ? 0xFF0F172A : (x > 40 + half * 0.4 ? l.clothShade : l.cloth));
        }
      }
      // A silver clasp and the blue lantern-glow on the chest
      _disc(img, ox + 40.0, 92, 3, 3, (dx, dy) => 0xFFE5E7EB);
      _fillRect(img, ox + 30, 90, 20, 1, l.accent);
    });

void _face(_Img img, int ox, _BustLook l, int expression) {
  // 0 neutral, 1 happy, 2 sad, 3 surprised
  const ey = 52;
  for (final ex in [32, 48]) {
    switch (expression) {
      case 1: // closed, smiling eyes
        for (var i = -3; i <= 3; i++) {
          img.set(ox + ex + i, ey + (i.abs() <= 1 ? -1 : 0), 0xFF3B2416);
        }
      case 3: // wide open
        _fillRect(img, ox + ex - 3, ey - 3, 7, 7, 0xFFFFFFFF);
        _fillRect(img, ox + ex - 1, ey - 2, 3, 5, l.eye);
        img.set(ox + ex, ey - 1, 0xFFFFFFFF);
      default:
        _fillRect(img, ox + ex - 3, ey - 2, 7, 5, 0xFFFFFFFF);
        _fillRect(img, ox + ex - 1, ey - 2, 3, 5, l.eye);
        img.set(ox + ex, ey - 1, 0xFFFFFFFF);
        if (expression == 2) _fillRect(img, ox + ex - 3, ey - 2, 7, 2, l.skinShade); // heavy lids
    }
    // Brows
    for (var i = -3; i <= 3; i++) {
      final tilt = expression == 2 ? (ex < 40 ? -i : i) ~/ 2 : (expression == 3 ? -1 : 0);
      img.set(ox + ex + i, ey - 6 + tilt, l.hairShade);
    }
  }
  // Mouth
  const my = 64;
  switch (expression) {
    case 1:
      for (var i = -4; i <= 4; i++) {
        img.set(ox + 40 + i, my + (i.abs() < 3 ? 1 : 0), 0xFF9F3A2E);
      }
      _fillRect(img, ox + 25, 58, 4, 2, 0xFFF4A3A3); // blush
      _fillRect(img, ox + 51, 58, 4, 2, 0xFFF4A3A3);
    case 2:
      for (var i = -3; i <= 3; i++) {
        img.set(ox + 40 + i, my + (i.abs() < 2 ? 0 : 1), 0xFF9F3A2E);
      }
    case 3:
      _disc(img, ox + 40.0, my + 1.0, 2.5, 3, (dx, dy) => 0xFF6B1F1A);
    default:
      _fillRect(img, ox + 37, my, 6, 1, 0xFF9F3A2E);
  }
}

_Img _bust(_BustLook l, int expression) {
  final img = _Img(_bustW, _bustH);
  l.hairBack(img, 0, l);
  _fillRect(img, 34, 70, 12, 16, l.skinShade); // neck
  l.clothes(img, 0, l);
  _disc(img, 40, 52, 17, 20, (dx, dy) => dx > 0.55 ? l.skinShade : l.skin); // face
  _disc(img, 23, 54, 2.5, 4, (dx, dy) => l.skinShade); // ears
  _disc(img, 57, 54, 2.5, 4, (dx, dy) => l.skinShade);
  l.hairFront(img, 0, l);
  _face(img, 0, l, expression);
  img.addOutline(0xFF140C08);
  return img;
}

_Img _bustSheet(_BustLook l) {
  final sheet = _Img(_bustW * 4, _bustH);
  for (var e = 0; e < 4; e++) {
    sheet.blit(_bust(l, e), e * _bustW, 0);
  }
  return sheet;
}

/// A gentle, wistful loop (A minor, 84 bpm).
Uint8List _storyTheme() => _chiptune(
      bpm: 84,
      leadAmp: 0.11,
      lead: const [
        (69, 1.0), (72, 1.0), (76, 2.0), (74, 1.0), (72, 1.0), (71, 2.0), //
        (69, 1.0), (71, 1.0), (72, 1.0), (74, 1.0), (76, 4.0),
        (77, 1.0), (76, 1.0), (74, 2.0), (72, 1.0), (71, 1.0), (69, 2.0),
        (67, 1.0), (69, 1.0), (71, 1.0), (68, 1.0), (69, 4.0),
      ],
      bassRoots: const [45, 45, 41, 41, 48, 48, 43, 43, 45, 45, 41, 41, 40, 40, 45, 45],
    );

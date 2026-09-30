part of 'generate_template_art.dart';

// ---------------------------------------------------------------------------
// Ember Legends art (top-down action RPG, 16px cells)

void _saveLegends(void Function(String folder, String name, _Img img) save) {
  save('legends', 'tiles.png', _legendsTiles());
  save('legends', 'hero.png', _legendsHero());
  save('legends', 'slash.png', _slash());
  save('legends', 'slime.png', _legendsSlime());
  save('legends', 'bat.png', _bat());
  save('legends', 'skeleton.png', _skeleton());
  save('legends', 'arrow.png', _arrow());
  save('legends', 'golem.png', _golem());
  save('legends', 'fireball.png', _fireball());
  save('legends', 'elder.png', _villager(robe: 0xFF7C3AED, robeHi: 0xFFA78BFA, beard: true));
  save('legends', 'merchant.png', _villager(robe: 0xFF1D4ED8, robeHi: 0xFF60A5FA, beard: false));
  save('legends', 'heart.png', _hearts());
  save('legends', 'coin.png', _coinSheet());
  save('legends', 'potion.png', _potion());
  save('legends', 'crystal.png', _crystal());
  for (final (name, bytes) in [('theme.wav', _legendsTheme()), ('dungeon.wav', _dungeonTheme())]) {
    final f = File('assets/templates/legends/$name')..writeAsBytesSync(bytes);
    stdout.writeln('wrote ${f.path} (${f.lengthSync() ~/ 1024} KB)');
  }
}

const _legendsHeroPalette = {
  'K': 0xFF1B1420, // outline
  'h': 0xFF7C2D12, // hair
  'H': 0xFFB45309, // hair highlight
  's': 0xFFF5C9A0, // skin
  'e': 0xFF1B1420, // eyes
  'G': 0xFF15803D, // tunic
  'g': 0xFF22C55E, // tunic highlight
  'b': 0xFF78350F, // belt
  'B': 0xFF44403C, // boots
  'W': 0xFFE5E7EB, // blade
  'Y': 0xFFFACC15, // hilt
};

/// 4 columns (idle, walk 1, walk 2, attack) x 3 rows (down, up, side/right).
_Img _legendsHero() {
  const frontHead = [
    '................',
    '.....KKKKKK.....',
    '....KhHHHHhK....',
    '...KhHhhhhHhK...',
    '...KhsssssshK...',
    '...KsesssseSK...',
    '...KssssssssK...',
    '....KssssssK....',
  ];
  const backHead = [
    '................',
    '.....KKKKKK.....',
    '....KhHHHHhK....',
    '...KhHhhhhHhK...',
    '...KhhhhhhhhK...',
    '...KhHhhhhHhK...',
    '...KhhhhhhhhK...',
    '....KhhhhhhK....',
  ];
  const sideHead = [
    '................',
    '.....KKKKK......',
    '....KhHHHhK.....',
    '...KhHhhhhhK....',
    '...KhhhhsssK....',
    '...KhhhsseSK....',
    '...KhhssssssK...',
    '....KKssssKK....',
  ];
  const torso = ['...KGgGGGGgGK...', '..KsGGGGGGGGsK..', '..KsKbbbbbbKsK..', '...KGGGGGGGGK...'];
  const torsoAttackDown = ['...KGgGGGGgGK...', '..KsGGGGGGGGsKY.', '..KsKbbbbbbK.KW.', '...KGGGGGGGGK.W.'];
  const torsoAttackUp = ['...KGgGGGGgGKW..', '..KsGGGGGGGGsW..', '..KsKbbbbbbKYK..', '...KGGGGGGGGK...'];
  const sideTorso = ['.....KGGGGK.....', '....KGGGGsK.....', '....KbbbbbK.....', '.....KGGGGK.....'];
  const sideAttack = ['.....KGGGGK.....', '....KGGGGssYWWWW', '....KbbbbbK.....', '.....KGGGGK.....'];
  const legs = [
    ['...KGGKKKKGGK...', '...KBBK..KBBK...', '...KBBK..KBBK...', '...KKKK..KKKK...'],
    ['...KGGKKKKGGK...', '...KBBK...KBBK..', '...KBBK...KKK...', '...KKKK.........'],
    ['...KGGKKKKGGK...', '..KBBK...KBBK...', '...KKK...KBBK...', '.........KKKK...'],
  ];
  const sideLegs = [
    ['.....KGGGK......', '.....KBBK.......', '.....KBBBK......', '.....KKKKK......'],
    ['....KGGKGK......', '...KBBK.KBK.....', '...KBK..KBBK....', '...KK....KKK....'],
    ['.....KGGGK......', '......KBBK......', '......KBBBK.....', '......KKKKK.....'],
  ];

  final sheet = _Img(64, 48);
  void frame(int col, int row, List<String> rows) => sheet.blit(_grid(rows, _legendsHeroPalette), col * 16, row * 16);
  for (var f = 0; f < 3; f++) {
    frame(f, 0, [...frontHead, ...torso, ...legs[f]]);
    frame(f, 1, [...backHead, ...torso, ...legs[f]]);
    frame(f, 2, [...sideHead, ...sideTorso, ...sideLegs[f]]);
  }
  frame(3, 0, [...frontHead, ...torsoAttackDown, ...legs[0]]);
  frame(3, 1, [...backHead, ...torsoAttackUp, ...legs[0]]);
  frame(3, 2, [...sideHead, ...sideAttack, ...sideLegs[0]]);
  return sheet;
}

/// Sword arc pointing right (rotated in game to face the swing).
_Img _slash() {
  final img = _Img(16, 16);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      final px = x + 0.5, py = y + 0.5;
      final outer = _inEllipse(px, py, 4, 8, 11, 7.5);
      final inner = _inEllipse(px, py, 2.5, 8, 9.5, 5.5);
      if (outer && !inner && px > 6) img.set(x, y, px > 12 ? 0xFFFFFFFF : 0xCCE0F2FE);
    }
  }
  return img;
}

/// Frames: 0-1 wobble.
_Img _legendsSlime() {
  const pal = {'K': 0xFF14532D, 'P': 0xFF22C55E, 'p': 0xFF86EFAC, 'W': 0xFFFFFFFF, 'k': 0xFF111111, 'M': 0xFF166534};
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
  return _Img(32, 16)
    ..blit(_grid(a, pal), 0, 0)
    ..blit(_grid(b, pal), 16, 0);
}

/// Frames: 0 wings up, 1 wings down.
_Img _bat() {
  const pal = {'K': 0xFF1E1B4B, 'P': 0xFF4C1D95, 'p': 0xFF7C3AED, 'r': 0xFFF43F5E, 'W': 0xFFFFFFFF};
  const up = [
    '................', '.K............K.', '.KK..........KK.', '.KpK...KK...KpK.',
    '.KppK.KPPK.KppK.', '.KpppKPPPPKpppK.', '..KppPrPPrPppK..', '..KppPPPPPPppK..',
    '...KKPPWWPPKK...', '.....KPPPPK.....', '......KKKK......', '................',
    '................', '................', '................', '................',
  ];
  const down = [
    '................', '................', '................', '................',
    '.......KK.......', '......KPPK......', '....KKPrPrKK....', '..KKpPPPPPPpKK..',
    '.KppppPWWPpppK..', 'KpppKKPPPPKKpppK', 'KppK..KPPK..KppK', 'KpK....KK....KpK',
    '.K............K.', '................', '................', '................',
  ];
  return _Img(32, 16)
    ..blit(_grid(up, pal), 0, 0)
    ..blit(_grid(down, pal), 16, 0);
}

/// Frames: 0-1 walk, 2 draw bow.
_Img _skeleton() {
  const pal = {'K': 0xFF27272A, 'W': 0xFFF4F4F5, 'w': 0xFFD4D4D8, 'e': 0xFFDC2626, 'B': 0xFF92400E, 's': 0xFFE7E5E4};
  const head = [
    '................', '.....KKKKKK.....', '....KWWWWWWK....', '...KWWWWWWWWK...',
    '...KWKeWWKeWK...', '...KWWWWWWWWK...', '....KWKWKWKK....', '.....KKKKKK.....',
  ];
  const body = ['.....KwWWwK.....', '....KWKwwKWK....', '....KWKWWKWK....', '.....KwwwwK.....'];
  const bowBody = ['.....KwWWwK.B...', '....KWKwwKWWB...', '....KWKWWKWsB...', '.....KwwwwK.B...'];
  const legsA = ['.....KWKKWK.....', '.....KWK.KWK....', '....KWK...KWK...', '....KKK...KKK...'];
  const legsB = ['.....KWKKWK.....', '.....KWKKWK.....', '.....KWKKWK.....', '.....KKKKKK.....'];
  return _Img(48, 16)
    ..blit(_grid([...head, ...body, ...legsA], pal), 0, 0)
    ..blit(_grid([...head, ...body, ...legsB], pal), 16, 0)
    ..blit(_grid([...head, ...bowBody, ...legsB], pal), 32, 0);
}

/// Arrow pointing right.
_Img _arrow() {
  final img = _Img(16, 16);
  for (var x = 2; x < 12; x++) {
    img.set(x, 8, 0xFF92400E);
  }
  for (final (x, y) in [(12, 7), (12, 8), (12, 9), (13, 8), (11, 7), (11, 9), (14, 8)]) {
    img.set(x, y, 0xFFD4D4D8);
  }
  for (final (x, y) in [(1, 6), (2, 7), (1, 10), (2, 9), (3, 7), (3, 9)]) {
    img.set(x, y, 0xFFF4F4F5);
  }
  img.addOutline(0xFF27272A);
  return img;
}

/// The Ember Golem boss: 32x32 frames, 0-1 stomp, 2 glowing attack.
_Img _golem() {
  final sheet = _Img(96, 32);
  for (var f = 0; f < 3; f++) {
    final img = _Img(32, 32);
    final bob = f == 1 ? 1.0 : 0.0;
    final glow = f == 2;
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        final px = x + 0.5, py = y + 0.5;
        int? c;
        // Legs
        if ((_inEllipse(px, py, 10, 27.5 - bob, 4, 4) || _inEllipse(px, py, 22, 27.5 + bob, 4, 4))) c = 0xFF44403C;
        // Body and head
        if (_inEllipse(px, py, 16, 17 + bob * 0.5, 11, 9)) c = 0xFF57534E;
        if (_inEllipse(px, py, 16, 8 + bob * 0.5, 6.5, 5.5)) c = 0xFF78716C;
        // Arms
        if (_inEllipse(px, py, 4.5, 17 - (glow ? 4 : 0), 3.5, 6) || _inEllipse(px, py, 27.5, 17 - (glow ? 4 : 0), 3.5, 6)) c = 0xFF6B645E;
        if (c != null) {
          // Molten cracks
          final crack = ((x * 7 + y * 3) % 11 == 0 || (x + y * 5) % 13 == 0) && py > 10 && py < 25;
          if (crack) c = glow ? 0xFFFDE047 : 0xFFF97316;
          img.set(x, y, c);
        }
      }
    }
    // Eyes and core
    final eye = glow ? 0xFFFFFFFF : 0xFFFBBF24;
    for (final (x, y) in [(13, 8), (14, 8), (18, 8), (19, 8)]) {
      img.set(x, y + (bob * 0.5).round(), eye);
    }
    for (var y = 15; y < 20; y++) {
      for (var x = 14; x < 18; x++) {
        img.set(x, y + (bob * 0.5).round(), glow ? 0xFFFEF08A : 0xFFEA580C);
      }
    }
    img.addOutline(0xFF1C1917);
    sheet.blit(img, f * 32, 0);
  }
  return sheet;
}

_Img _fireball() {
  final img = _Img(16, 16);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      final px = x + 0.5, py = y + 0.5;
      if (_inEllipse(px, py, 9, 8, 5, 5)) {
        img.set(x, y, _inEllipse(px, py, 10, 7.5, 2.5, 2.5) ? 0xFFFEF08A : 0xFFF97316);
      } else if (_inEllipse(px, py, 6, 8, 5.5, 3) && px < 8) {
        img.set(x, y, 0xFFDC2626); // trailing flame
      }
    }
  }
  img.addOutline(0xFF7C2D12);
  return img;
}

/// Robed villager, frames 0-1 (idle sway).
_Img _villager({required int robe, required int robeHi, required bool beard}) {
  final pal = {'K': 0xFF1B1420, 's': 0xFFF5C9A0, 'e': 0xFF1B1420, 'R': robe, 'r': robeHi, 'W': 0xFFF4F4F5, 'b': 0xFF78350F, 'h': 0xFF52525B};
  final head = [
    '................',
    '.....KKKKKK.....',
    '....KrRRRRrK....',
    '...KRRRRRRRRK...',
    '...KRsssssssK...',
    '...KsesssesK....',
    beard ? '...KWWssssWWK...' : '...KssssssssK...',
    beard ? '....KWWWWWWK....' : '....KssssssK....',
  ];
  const bodyA = ['...KRRrRRrRRK...', '..KsRRRRRRRRsK..', '..KKRbbbbbbRKK..', '...KRRRRRRRRK...', '...KRRRRRRRRK...', '..KRRRRRRRRRRK..', '..KRRRRRRRRRRK..', '..KKKKKKKKKKKK..'];
  const bodyB = ['...KRRrRRrRRK...', '..KsRRRRRRRRsK..', '..KKRbbbbbbRKK..', '...KRRRRRRRRK...', '...KRRRRRRRRK...', '...KRRRRRRRRRK..', '..KRRRRRRRRRRK..', '..KKKKKKKKKKKK..'];
  return _Img(32, 16)
    ..blit(_grid([...head, ...bodyA], pal), 0, 0)
    ..blit(_grid([...head, ...bodyB], pal), 16, 0);
}

/// Frame 0 full heart, 1 empty heart.
_Img _hearts() {
  final sheet = _Img(32, 16);
  for (var f = 0; f < 2; f++) {
    final img = _Img(16, 16);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final px = x + 0.5, py = y + 0.5;
        final lobes = _inEllipse(px, py, 5, 6, 3.6, 3.4) || _inEllipse(px, py, 11, 6, 3.6, 3.4);
        final point = py >= 6 && (px - 8).abs() <= (14 - py) * 0.9;
        if (lobes || point) {
          final shine = _inEllipse(px, py, 4.5, 5, 1.2, 1.2);
          img.set(x, y, f == 0 ? (shine ? 0xFFFFFFFF : 0xFFEF4444) : 0xFF3F3F46);
        }
      }
    }
    img.addOutline(0xFF1B1420);
    sheet.blit(img, f * 16, 0);
  }
  return sheet;
}

_Img _potion() {
  const pal = {'K': 0xFF1B1420, 'c': 0xFFA16207, 'g': 0xFFE0F2FE, 'R': 0xFFDC2626, 'r': 0xFFF87171, 'W': 0xFFFFFFFF};
  const rows = [
    '................', '......KKKK......', '......KccK......', '.......KK.......',
    '......KggK......', '.....KggggK.....', '....KgRRRRgK....', '...KgRrWRRRgK...',
    '...KRRrRRRRRK...', '...KRRRRRRRRK...', '...KRRRRRRRRK...', '....KRRRRRRK....',
    '.....KKKKKK.....', '................', '................', '................',
  ];
  return _grid(rows, pal);
}

/// Save crystal: frames 0-1 (glow pulse).
_Img _crystal() {
  final sheet = _Img(32, 16);
  for (var f = 0; f < 2; f++) {
    final img = _Img(16, 16);
    for (var y = 1; y < 15; y++) {
      final half = y < 7 ? y * 0.75 : (15 - y) * 0.6;
      for (var x = 0; x < 16; x++) {
        final dx = (x + 0.5 - 8).abs();
        if (dx <= half) {
          final light = x < 8 ? (f == 0 ? 0xFF67E8F9 : 0xFFCFFAFE) : (f == 0 ? 0xFF0891B2 : 0xFF22D3EE);
          img.set(x, y, dx < 1 ? 0xFFFFFFFF : light);
        }
      }
    }
    img.addOutline(0xFF164E63);
    sheet.blit(img, f * 16, 0);
  }
  return sheet;
}

/// 8x2 cells. IDs (cell + 1):
/// 1 grass, 2 path, 3 water, 4 tree, 5 rock, 6 bush, 7 flower, 8 house wall,
/// 9 roof, 10 dungeon floor, 11 dungeon wall, 12 cave mouth, 13 bridge,
/// 14 fence, 15 torch wall, 16 house door.
_Img _legendsTiles() {
  final sheet = _Img(128, 32);
  final rng = math.Random(23);
  void cell(int id, void Function(_Img c) draw) {
    final c = _Img(16, 16);
    draw(c);
    final i = id - 1;
    sheet.blit(c, (i % 8) * 16, (i ~/ 8) * 16);
  }

  void each(_Img c, int Function(int x, int y) color) {
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        c.set(x, y, color(x, y));
      }
    }
  }

  int grass(int x, int y) {
    final r = rng.nextDouble();
    return r < 0.08 ? 0xFF4D7C0F : (r < 0.16 ? 0xFF84CC16 : 0xFF65A30D);
  }

  cell(1, (c) => each(c, grass));
  cell(2, (c) => each(c, (x, y) => rng.nextDouble() < 0.12 ? 0xFFA16207 : 0xFFCA8A04));
  cell(3, (c) => each(c, (x, y) => ((x + (y ~/ 4) * 3) % 8 < 2 && y % 4 == 1) ? 0xFF93C5FD : 0xFF2563EB));
  cell(4, (c) {
    each(c, grass);
    for (var y = 11; y < 16; y++) {
      for (var x = 6; x < 10; x++) {
        c.set(x, y, x == 6 ? 0xFF451A03 : 0xFF78350F);
      }
    }
    for (var y = 0; y < 13; y++) {
      for (var x = 0; x < 16; x++) {
        final px = x + 0.5, py = y + 0.5;
        if (_inEllipse(px, py, 8, 6.5, 7.5, 6.5)) {
          c.set(x, y, _inEllipse(px, py, 6, 4.5, 3.5, 3) ? 0xFF22C55E : (py > 9.5 ? 0xFF14532D : 0xFF15803D));
        }
      }
    }
  });
  cell(5, (c) {
    each(c, grass);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final px = x + 0.5, py = y + 0.5;
        if (_inEllipse(px, py, 8, 9.5, 6.5, 5.5)) {
          c.set(x, y, _inEllipse(px, py, 6.5, 7.5, 3, 2) ? 0xFFD6D3D1 : (py > 12 ? 0xFF57534E : 0xFFA8A29E));
        }
      }
    }
  });
  cell(6, (c) {
    each(c, grass);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final px = x + 0.5, py = y + 0.5;
        if (_inEllipse(px, py, 5, 10, 4.5, 4.5) || _inEllipse(px, py, 11, 10, 4.5, 4.5) || _inEllipse(px, py, 8, 7, 4.5, 4)) {
          c.set(x, y, py < 8 ? 0xFF4ADE80 : 0xFF16A34A);
        }
      }
    }
    for (final (x, y) in [(5, 9), (10, 7), (11, 11)]) {
      c.set(x, y, 0xFFE11D48); // berries
    }
  });
  cell(7, (c) {
    for (final (fx, fy, color) in [(4, 5, 0xFFF472B6), (11, 9, 0xFFFDE047), (6, 12, 0xFFFFFFFF)]) {
      c.set(fx, fy + 1, 0xFF15803D);
      c.set(fx, fy + 2, 0xFF15803D);
      for (final (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        c.set(fx + dx, fy + dy, color);
      }
      c.set(fx, fy, 0xFFF59E0B);
    }
  });
  cell(8, (c) => each(c, (x, y) => y % 4 == 3 ? 0xFF78350F : (x == 0 || x == 15 ? 0xFF92400E : 0xFFD97706)));
  cell(9, (c) => each(c, (x, y) {
        final shingle = (x + ((y ~/ 3).isEven ? 0 : 2)) % 4 == 0 || y % 3 == 2;
        return shingle ? 0xFF7F1D1D : (y < 3 ? 0xFFEF4444 : 0xFFB91C1C);
      }));
  cell(10, (c) => each(c, (x, y) => (x % 8 == 0 || y % 8 == 0) ? 0xFF292524 : (rng.nextDouble() < 0.1 ? 0xFF57534E : 0xFF44403C)));
  void wall(_Img c) => each(c, (x, y) {
        final mortarRow = y % 5 == 4;
        final offset = (y ~/ 5).isEven ? 0 : 4;
        final mortarCol = (x + offset) % 8 == 7;
        if (y < 2) return 0xFF78716C;
        return mortarRow || mortarCol ? 0xFF1C1917 : 0xFF57534E;
      });
  cell(11, wall);
  cell(12, (c) {
    each(c, grass);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final px = x + 0.5, py = y + 0.5;
        if (_inEllipse(px, py, 8, 12, 7.5, 10)) c.set(x, y, _inEllipse(px, py, 8, 13, 5.5, 8) ? 0xFF0C0A09 : 0xFF57534E);
      }
    }
  });
  cell(13, (c) => each(c, (x, y) => y % 4 == 3 ? 0xFF451A03 : (x == 0 || x == 15 ? 0xFF78350F : 0xFFB45309)));
  cell(14, (c) {
    each(c, grass);
    for (var x = 0; x < 16; x++) {
      c.set(x, 6, 0xFF92400E);
      c.set(x, 10, 0xFF92400E);
    }
    for (final px in [2, 13]) {
      for (var y = 3; y < 14; y++) {
        c.set(px, y, 0xFF78350F);
        c.set(px + 1, y, 0xFFB45309);
      }
    }
  });
  cell(15, (c) {
    wall(c);
    for (var y = 7; y < 13; y++) {
      c.set(7, y, 0xFF78350F);
      c.set(8, y, 0xFF78350F);
    }
    for (final (x, y, col) in [(7, 4, 0xFFF97316), (8, 4, 0xFFF97316), (7, 5, 0xFFFDE047), (8, 5, 0xFFFDE047), (7, 6, 0xFFF97316), (8, 6, 0xFFF97316), (8, 3, 0xFFEF4444)]) {
      c.set(x, y, col);
    }
  });
  cell(16, (c) {
    each(c, (x, y) => y % 4 == 3 ? 0xFF78350F : (x == 0 || x == 15 ? 0xFF92400E : 0xFFD97706));
    for (var y = 3; y < 16; y++) {
      for (var x = 4; x < 12; x++) {
        c.set(x, y, x == 4 || x == 11 || y == 3 ? 0xFF1C1917 : 0xFF451A03);
      }
    }
    c.set(10, 10, 0xFFFACC15);
  });
  return sheet;
}

// ---------------------------------------------------------------------------
// Ember Legends music: original loops

Uint8List _legendsTheme() => _chiptune(
      bpm: 132,
      lead: const [
        (62, 1.0), (65, 1.0), (69, 1.5), (67, 0.5), //
        (65, 1.0), (64, 1.0), (62, 2.0),
        (60, 1.0), (62, 1.0), (64, 1.0), (65, 1.0),
        (67, 3.0), (0, 1.0),
        (69, 1.0), (72, 1.0), (74, 1.5), (72, 0.5),
        (70, 1.0), (69, 1.0), (67, 2.0),
        (65, 1.0), (64, 1.0), (62, 1.0), (61, 1.0),
        (62, 3.0), (0, 1.0),
      ],
      bassRoots: const [38, 38, 34, 34, 36, 36, 43, 43, 41, 41, 34, 34, 36, 36, 38, 38],
    );

Uint8List _dungeonTheme() => _chiptune(
      bpm: 100,
      leadAmp: 0.16,
      lead: const [
        (57, 2.0), (60, 1.0), (59, 1.0), //
        (57, 2.0), (52, 2.0),
        (53, 2.0), (57, 1.0), (56, 1.0),
        (52, 3.0), (0, 1.0),
        (57, 2.0), (60, 1.0), (62, 1.0),
        (63, 2.0), (62, 2.0),
        (60, 1.0), (59, 1.0), (57, 1.0), (56, 1.0),
        (57, 3.0), (0, 1.0),
      ],
      bassRoots: const [33, 33, 33, 33, 29, 29, 28, 28, 33, 33, 30, 30, 29, 28, 33, 33],
    );

/// Square-wave lead over a bouncing triangle bass, as 16-bit mono WAV.
Uint8List _chiptune({
  required double bpm,
  required List<(int, double)> lead,
  required List<int> bassRoots,
  double leadAmp = 0.2,
}) {
  const rate = 22050;
  final beat = 60.0 / bpm;
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
      final wave = square ? (phase < 0.25 ? 1.0 : -1.0) : 4 * (phase - 0.5).abs() - 1;
      final attack = math.min(1.0, i / (rate * 0.005));
      final release = math.min(1.0, (len - i) / (rate * 0.03));
      final decay = square ? 0.75 + 0.25 * math.exp(-t * 6) : 1.0;
      samples[start + i] += wave * amp * attack * release * decay;
    }
  }

  var at = 0.0;
  for (final (note, beats) in lead) {
    addNote(note, at, beats * 0.92, leadAmp, true);
    at += beats;
  }
  final step = totalBeats / bassRoots.length;
  for (var i = 0; i < bassRoots.length; i++) {
    addNote(bassRoots[i], i * step, step * 0.45, 0.35, false);
    addNote(bassRoots[i] + 12, i * step + step / 2, step * 0.45, 0.3, false);
  }
  return _wav(samples, rate);
}

Uint8List _wav(List<double> samples, int rate) {
  final total = samples.length;
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

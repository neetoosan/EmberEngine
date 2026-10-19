part of 'paint_art_test.dart';

// Ember Nova: a neon side-scrolling shooter. Everything is painted at twice
// the size it is shown, and drawn with smooth scaling in the game.

const _nova = 'nova';

Future<void> _paintNova() async {
  await _png(_nova, 'ship.png', 192, 128, _novaShip);
  await _sheet(_nova, 'thruster.png', 128, 64, 2, _novaThruster);
  await _sheet(_nova, 'enemies.png', 160, 160, 4, _novaEnemy);
  await _png(_nova, 'cruiser.png', 320, 200, _novaCruiser);
  await _png(_nova, 'boss.png', 520, 400, _novaBoss);
  await _png(_nova, 'boss_core.png', 160, 160, (c) => _novaCore(c, const Offset(80, 80)));
  await _sheet(_nova, 'bullets.png', 64, 64, 8, _novaBullet);
  await _sheet(_nova, 'pickups.png', 96, 96, 4, _novaPickup);
  await _sheet(_nova, 'icons.png', 64, 64, 2, _novaIcon);
  await _png(_nova, 'ring.png', 256, 256, _novaRing);
  await _png(_nova, 'flare.png', 192, 192, _novaFlare);
  await _png(_nova, 'bg_space.png', 960, 540, _novaSpace);
  await _png(_nova, 'bg_nebula.png', 1280, 540, _novaNebula);
  await _png(_nova, 'bg_stars_far.png', 960, 540, (c) => _novaStars(c, 3, 220, 0.6, 1.4));
  await _png(_nova, 'bg_stars_near.png', 960, 540, (c) => _novaStars(c, 11, 60, 1.2, 2.6));
  await _png(_nova, 'bg_planet.png', 600, 600, _novaPlanet);
  await _png(_nova, 'panel.png', 840, 520, _glassPanel);

  _writeWav(_nova, 'nova.wav', _novaTheme(boss: false));
  _writeWav(_nova, 'nova_boss.wav', _novaTheme(boss: true));
  _writeWav(_nova, 'shot.wav', _effect(0.09, (t) {
    final f = 1800 * math.exp(-t * 30) + 500;
    return math.sin(2 * math.pi * f * t) * math.exp(-t * 40) * 0.6 + _noise() * math.exp(-t * 80) * 0.25;
  }, peak: 0.5));
  final boomLp = _LowPass();
  _writeWav(_nova, 'boom.wav', _effect(0.7, (t) {
    final body = boomLp.process(_noise(), 2400 * math.exp(-t * 5) + 120);
    return body * math.exp(-t * 5) * 1.6 + math.sin(2 * math.pi * (60 + 80 * math.exp(-t * 20)) * t) * math.exp(-t * 8);
  }));
  final bigLp = _LowPass();
  _writeWav(_nova, 'bigboom.wav', _effect(2.2, (t) {
    final body = bigLp.process(_noise(), 1800 * math.exp(-t * 2) + 80);
    final sub = math.sin(2 * math.pi * (38 + 70 * math.exp(-t * 6)) * t) * math.exp(-t * 2.2);
    return body * math.exp(-t * 1.8) * 1.8 + sub;
  }));
  _writeWav(_nova, 'power.wav', _effect(0.55, (t) {
    const notes = [72, 76, 79, 84];
    final step = (t / 0.08).floor().clamp(0, 3);
    final f = _hz(notes[step]);
    final local = t - step * 0.08;
    return (math.sin(2 * math.pi * f * t) + 0.5 * math.sin(4 * math.pi * f * t)) * math.exp(-local * 12) * math.exp(-t * 2);
  }, peak: 0.6));
  _writeWav(_nova, 'hurt.wav', _effect(0.6, (t) {
    final f = 420 * math.exp(-t * 3);
    final saw = (f * t) % 1 * 2 - 1;
    return (saw * 0.6 + _noise() * 0.3) * math.exp(-t * 5);
  }, peak: 0.7));
  final bombLp = _LowPass();
  _writeWav(_nova, 'bomb.wav', _effect(1.6, (t) {
    final sweep = bombLp.process(_noise(), 300 + 5000 * math.sin(math.pi * math.min(1, t / 0.5)));
    final sub = math.sin(2 * math.pi * (50 + 40 * math.exp(-t * 4)) * t) * math.exp(-t * 2);
    return sweep * math.exp(-t * 1.8) * 1.4 + sub;
  }));
}

// --- Player ship (faces right) ----------------------------------------------

void _novaShip(Canvas c) {
  const box = Rect.fromLTWH(0, 0, 192, 128);
  // Soft outer light so it reads against busy backgrounds
  final hull = [const Offset(186, 64), const Offset(128, 47), const Offset(76, 40), const Offset(34, 50), const Offset(22, 64)];
  final hullPath = _poly([...hull, ..._mirrorY(hull, 64).skip(1)]);
  c.drawPath(hullPath, _glow(const Color(0x5538BDF8), 10));

  // Wings, swept back
  final wing = [const Offset(118, 50), const Offset(62, 8), const Offset(38, 8), const Offset(54, 50)];
  for (final w in [wing, _mirrorY(wing, 64)]) {
    final path = _poly(w);
    c.drawPath(path, _linear(box, const [Color(0xFF60A5FA), Color(0xFF1E3A8A)], begin: Alignment.topRight, end: Alignment.bottomLeft));
    c.drawPath(path, _stroke(const Color(0xFF93C5FD), 1.5));
  }
  // Wing tips glow
  _softDot(c, const Offset(46, 10), 9, const Color(0xFFF97316));
  _softDot(c, const Offset(46, 118), 9, const Color(0xFFF97316));

  // Hull
  c.drawPath(hullPath, _linear(box, const [Color(0xFFF1F5F9), Color(0xFF94A3B8), Color(0xFF334155)], stops: const [0.2, 0.55, 1]));
  c.drawPath(hullPath, _stroke(const Color(0xFFE2E8F0), 1.5));
  // Ember stripe along the side
  c.drawPath(_poly(const [Offset(150, 60), Offset(70, 54), Offset(44, 58), Offset(44, 62), Offset(70, 60), Offset(150, 63)]), _fill(const Color(0xFFF97316)));
  // Engine block
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(16, 50, 26, 28), const Radius.circular(6)),
      _linear(const Rect.fromLTWH(16, 50, 26, 28), const [Color(0xFF475569), Color(0xFF0F172A)]));
  c.drawCircle(const Offset(20, 64), 9, _radial(const Offset(20, 64), 9, const [Color(0xFFFFFFFF), Color(0xFF67E8F9), Color(0x0067E8F9)]));

  // Glass cockpit
  final glass = Rect.fromCenter(center: const Offset(116, 64), width: 58, height: 22);
  c.drawOval(glass, _linear(glass, const [Color(0xFFA5F3FC), Color(0xFF0891B2), Color(0xFF164E63)]));
  c.drawOval(Rect.fromCenter(center: const Offset(124, 59), width: 26, height: 6), _fill(const Color(0xAAFFFFFF)));
  c.drawOval(glass, _stroke(const Color(0xFF0E7490), 1.5));
}

void _novaThruster(Canvas c, int i) {
  // Exhaust plume pointing left, drawn additively in the game
  final len = i == 0 ? 118.0 : 96.0;
  final plume = Path()
    ..moveTo(128, 32)
    ..quadraticBezierTo(128 - len * 0.35, 32 - 20, 128 - len, 32)
    ..quadraticBezierTo(128 - len * 0.35, 32 + 20, 128, 32)
    ..close();
  c.drawPath(plume, _glow(const Color(0xFF2563EB), 8));
  final inner = Path()
    ..moveTo(128, 32)
    ..quadraticBezierTo(128 - len * 0.3, 32 - 9, 128 - len * 0.7, 32)
    ..quadraticBezierTo(128 - len * 0.3, 32 + 9, 128, 32)
    ..close();
  c.drawPath(inner, _glow(const Color(0xFF67E8F9), 4));
  _softDot(c, const Offset(122, 32), 16, const Color(0xFFFFFFFF), core: 0.3);
}

// --- Enemies (face left) ----------------------------------------------------

void _novaEnemy(Canvas c, int i) {
  const center = Offset(80, 80);
  switch (i) {
    case 0: // Drone: a round eye with a glowing magenta rim
      c.drawCircle(center, 54, _glow(const Color(0x66EC4899), 12));
      for (final a in [90.0, 210.0, 330.0]) {
        final r = a * math.pi / 180;
        final tip = center + Offset(math.cos(r), math.sin(r)) * 70;
        final l = center + Offset(math.cos(r + 0.35), math.sin(r + 0.35)) * 40;
        final rr = center + Offset(math.cos(r - 0.35), math.sin(r - 0.35)) * 40;
        c.drawPath(_poly([l, tip, rr]), _linear(const Rect.fromLTWH(0, 0, 160, 160), const [Color(0xFF6D28D9), Color(0xFF2E1065)]));
      }
      c.drawCircle(center, 46, _linear(const Rect.fromLTWH(34, 34, 92, 92), const [Color(0xFF4C1D95), Color(0xFF1E1B4B)]));
      c.drawCircle(center, 46, _stroke(const Color(0xFFF472B6), 3));
      c.drawCircle(center, 30, _fill(const Color(0xFF0F0A1F)));
      _softDot(c, center, 26, const Color(0xFFFF4FA3), core: 0.2);
      c.drawCircle(center, 7, _fill(const Color(0xFFFFFFFF)));
    case 1: // Dart: a fast crimson arrow
      final body = _poly(const [Offset(10, 80), Offset(120, 26), Offset(98, 80), Offset(120, 134)]);
      c.drawPath(body, _glow(const Color(0x66FB7185), 10));
      c.drawPath(body, _linear(const Rect.fromLTWH(0, 20, 160, 120), const [Color(0xFFFDA4AF), Color(0xFFE11D48), Color(0xFF4C0519)], stops: const [0, 0.5, 1]));
      c.drawPath(body, _stroke(const Color(0xFFFECDD3), 2));
      c.drawPath(_poly(const [Offset(40, 80), Offset(96, 58), Offset(88, 80), Offset(96, 102)]), _fill(const Color(0xFF1F0510)));
      _softDot(c, const Offset(126, 80), 22, const Color(0xFFFB923C));
      _softDot(c, const Offset(58, 80), 12, const Color(0xFFFFE4E6));
    case 2: // Turret pod: a hexagon with an amber core and a barrel
      final hex = _poly([for (var k = 0; k < 6; k++) center + Offset(math.cos(k * math.pi / 3), math.sin(k * math.pi / 3)) * 58]);
      c.drawPath(hex, _glow(const Color(0x55F59E0B), 12));
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(6, 70, 60, 20), const Radius.circular(6)),
          _linear(const Rect.fromLTWH(6, 70, 60, 20), const [Color(0xFF94A3B8), Color(0xFF334155)]));
      c.drawPath(hex, _linear(const Rect.fromLTWH(22, 22, 116, 116), const [Color(0xFF64748B), Color(0xFF1E293B)]));
      c.drawPath(hex, _stroke(const Color(0xFFFBBF24), 3));
      c.drawCircle(center, 28, _fill(const Color(0xFF0F172A)));
      _softDot(c, center, 30, const Color(0xFFFBBF24), core: 0.25);
      c.drawCircle(center, 8, _fill(const Color(0xFFFFFBEB)));
    case 3: // Spinner: four violet blades around a core (the game spins it)
      c.drawCircle(center, 62, _glow(const Color(0x558B5CF6), 14));
      for (var k = 0; k < 4; k++) {
        final r = k * math.pi / 2;
        Offset at(double ang, double d) => center + Offset(math.cos(r + ang), math.sin(r + ang)) * d;
        final blade = _poly([at(-0.25, 20), at(0.0, 74), at(0.45, 46), at(0.3, 20)]);
        c.drawPath(blade, _linear(const Rect.fromLTWH(0, 0, 160, 160), const [Color(0xFFC4B5FD), Color(0xFF6D28D9)], begin: Alignment.topLeft, end: Alignment.bottomRight));
        c.drawPath(blade, _stroke(const Color(0xFFEDE9FE), 1.5));
      }
      c.drawCircle(center, 24, _fill(const Color(0xFF1E1B4B)));
      c.drawCircle(center, 24, _stroke(const Color(0xFFA78BFA), 3));
      _softDot(c, center, 20, const Color(0xFF22D3EE));
  }
}

void _novaCruiser(Canvas c) {
  const box = Rect.fromLTWH(0, 0, 320, 200);
  final top = [const Offset(14, 100), const Offset(70, 60), const Offset(190, 44), const Offset(250, 20), const Offset(300, 26), const Offset(282, 70), const Offset(306, 100)];
  final hull = _poly([...top, ..._mirrorY(top, 100).skip(1)]);
  c.drawPath(hull, _glow(const Color(0x55F43F5E), 14));
  c.drawPath(hull, _linear(box, const [Color(0xFF94A3B8), Color(0xFF334155), Color(0xFF0F172A)], stops: const [0, 0.5, 1]));
  c.drawPath(hull, _stroke(const Color(0xFFCBD5E1), 2));
  // Armour plates
  for (final r in [const Rect.fromLTWH(90, 70, 120, 18), const Rect.fromLTWH(90, 112, 120, 18)]) {
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), _linear(r, const [Color(0xFF475569), Color(0xFF1E293B)]));
  }
  // Glowing slit "eye" and engine lights
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 92, 90, 16), const Radius.circular(8)), _fill(const Color(0xFF1F0510)));
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(36, 95, 78, 10), const Radius.circular(5)), _glow(const Color(0xFFFF4D6D), 4));
  for (final y in [40.0, 160.0]) {
    _softDot(c, Offset(292, y), 18, const Color(0xFFFB923C));
  }
  for (var k = 0; k < 4; k++) {
    _softDot(c, Offset(140.0 + k * 22, 100), 6, const Color(0xFFFDE68A));
  }
}

void _novaBoss(Canvas c) {
  const box = Rect.fromLTWH(0, 0, 520, 400);
  const mid = 200.0;
  // Outer arms
  final arm = [const Offset(60, 150), const Offset(140, 40), const Offset(300, 14), const Offset(470, 30), const Offset(500, 90), const Offset(380, 120), const Offset(230, 150)];
  for (final a in [arm, _mirrorY(arm, mid)]) {
    final p = _poly(a);
    c.drawPath(p, _glow(const Color(0x44A855F7), 16));
    c.drawPath(p, _linear(box, const [Color(0xFF64748B), Color(0xFF1E293B)], begin: Alignment.topLeft, end: Alignment.bottomRight));
    c.drawPath(p, _stroke(const Color(0xFFC4B5FD), 2));
  }
  // Cannons through the arms
  for (final y in [84.0, 316.0]) {
    final r = Rect.fromLTWH(40, y - 14, 140, 28);
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)), _linear(r, const [Color(0xFFCBD5E1), Color(0xFF334155)]));
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)), _stroke(const Color(0xFFE2E8F0), 1.5));
    _softDot(c, Offset(44, y), 20, const Color(0xFFF472B6));
  }
  // Central body
  final body = _poly([const Offset(40, mid), const Offset(120, 110), const Offset(330, 92), const Offset(470, 140), const Offset(500, mid), const Offset(470, 260), const Offset(330, 308), const Offset(120, 290)]);
  c.drawPath(body, _glow(const Color(0x66EC4899), 18));
  c.drawPath(body, _linear(box, const [Color(0xFFE2E8F0), Color(0xFF64748B), Color(0xFF1E293B), Color(0xFF0F172A)], stops: const [0, 0.35, 0.7, 1]));
  c.drawPath(body, _stroke(const Color(0xFFF1F5F9), 2.5));
  // Panel lines
  for (final x in [200.0, 280.0, 360.0]) {
    c.drawLine(Offset(x, 110), Offset(x + 20, 290), _stroke(const Color(0x660F172A), 3));
  }
  // Core housing (the core itself is a separate glowing sprite)
  c.drawCircle(const Offset(170, mid), 74, _fill(const Color(0xFF0B0716)));
  c.drawCircle(const Offset(170, mid), 74, _stroke(const Color(0xFFF472B6), 4));
  c.drawCircle(const Offset(170, mid), 60, _stroke(const Color(0x88A855F7), 2));
  // Engine bank
  for (var k = 0; k < 3; k++) {
    _softDot(c, Offset(498, 150.0 + k * 50), 22, const Color(0xFF60A5FA));
  }
  for (var k = 0; k < 6; k++) {
    _softDot(c, Offset(250.0 + k * 34, mid), 6, const Color(0xFFFDE68A));
  }
}

void _novaCore(Canvas c, Offset at) {
  _softDot(c, at, 78, const Color(0xFFEC4899), core: 0.15);
  c.drawCircle(at, 34, _radial(at, 34, const [Color(0xFFFFFFFF), Color(0xFFF9A8D4), Color(0xFFDB2777)], stops: const [0, 0.4, 1]));
  for (var k = 0; k < 8; k++) {
    final r = k * math.pi / 4;
    c.drawLine(at + Offset(math.cos(r), math.sin(r)) * 40, at + Offset(math.cos(r), math.sin(r)) * 60, _stroke(const Color(0xAAFBCFE8), 3));
  }
}

// --- Bullets (additive) -------------------------------------------------------

void _novaBullet(Canvas c, int i) {
  const center = Offset(32, 32);
  void capsule(double w, double h, Color glow, Color core) {
    final r = Rect.fromCenter(center: center, width: w, height: h);
    c.drawRRect(RRect.fromRectAndRadius(r.inflate(5), Radius.circular(h)), _glow(glow, 6));
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(h / 2)), _fill(core));
  }

  void orb(double r, Color color) {
    _softDot(c, center, r * 2.4, color, core: 0.15);
    c.drawCircle(center, r, _fill(color));
    c.drawCircle(center, r * 0.62, _fill(const Color(0xFFFFFFFF)));
  }

  switch (i) {
    case 0:
      capsule(46, 9, const Color(0xFF22D3EE), const Color(0xFFE0FFFF)); // player laser
    case 1:
      capsule(30, 8, const Color(0xFFF97316), const Color(0xFFFFF7ED)); // player side shot
    case 2:
      orb(9, const Color(0xFFFF4FA3));
    case 3:
      orb(9, const Color(0xFFFFA62B));
    case 4:
      orb(9, const Color(0xFFA855F7));
    case 5: // "rice": long and thin, points where it flies
      final r = Rect.fromCenter(center: center, width: 30, height: 11);
      c.drawOval(r.inflate(6), _glow(const Color(0xFFFF4FA3), 6));
      c.drawOval(r, _fill(const Color(0xFFFF7AB8)));
      c.drawOval(r.deflate(3), _fill(const Color(0xFFFFFFFF)));
    case 6:
      orb(13, const Color(0xFFEF4444)); // big
    case 7: // star
      _softDot(c, center, 24, const Color(0xFF67E8F9));
      final star = _poly([for (var k = 0; k < 10; k++) center + Offset(math.cos(k * math.pi / 5 - math.pi / 2), math.sin(k * math.pi / 5 - math.pi / 2)) * (k.isEven ? 14 : 6)]);
      c.drawPath(star, _fill(const Color(0xFFFFFFFF)));
  }
}

// --- Pickups, icons, effects ----------------------------------------------------

void _novaPickup(Canvas c, int i) {
  const center = Offset(48, 48);
  final colors = const [Color(0xFF3B82F6), Color(0xFFF97316), Color(0xFF22D3EE), Color(0xFF34D399)];
  final color = colors[i];
  _softDot(c, center, 46, color.withValues(alpha: 0.7), core: 0.1);
  final hex = _poly([for (var k = 0; k < 6; k++) center + Offset(math.cos(k * math.pi / 3 + math.pi / 6), math.sin(k * math.pi / 3 + math.pi / 6)) * 30]);
  c.drawPath(hex, _linear(const Rect.fromLTWH(18, 18, 60, 60), [Color.lerp(color, const Color(0xFFFFFFFF), 0.5)!, color, Color.lerp(color, const Color(0xFF000000), 0.5)!]));
  c.drawPath(hex, _stroke(const Color(0xDDFFFFFF), 2.5));
  final white = _fill(const Color(0xFFFFFFFF));
  switch (i) {
    case 0: // power: double chevron
      for (final dy in [-6.0, 8.0]) {
        c.drawPath(_poly([Offset(36, 54 + dy), Offset(48, 42 + dy), Offset(60, 54 + dy), Offset(60, 60 + dy), Offset(48, 48 + dy), Offset(36, 60 + dy)]), white);
      }
    case 1: // bomb: a burst
      c.drawPath(_poly([for (var k = 0; k < 16; k++) center + Offset(math.cos(k * math.pi / 8), math.sin(k * math.pi / 8)) * (k.isEven ? 17 : 8)]), white);
    case 2: // shield: a ring
      c.drawCircle(center, 13, _stroke(const Color(0xFFFFFFFF), 5));
    case 3: // score crystal: a diamond
      c.drawPath(_poly(const [Offset(48, 30), Offset(62, 48), Offset(48, 66), Offset(34, 48)]), white);
  }
}

void _novaIcon(Canvas c, int i) {
  if (i == 0) {
    c.save();
    c.translate(2, 11);
    c.scale(60 / 192);
    _novaShip(c);
    c.restore();
  } else {
    const center = Offset(32, 32);
    _softDot(c, center, 30, const Color(0xFFF97316), core: 0.2);
    c.drawCircle(center, 13, _radial(center, 13, const [Color(0xFFFFF7ED), Color(0xFFF97316), Color(0xFF9A3412)]));
  }
}

void _novaRing(Canvas c) {
  const center = Offset(128, 128);
  c.drawCircle(center, 110, _stroke(const Color(0xFFFFFFFF), 10, blur: 6));
  c.drawCircle(center, 110, _stroke(const Color(0xFFFFFFFF), 3));
}

void _novaFlare(Canvas c) {
  const center = Offset(96, 96);
  _softDot(c, center, 92, const Color(0xFFFFFFFF), core: 0.08);
  for (final r in [0.0, math.pi / 2]) {
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(r);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 180, height: 7), _glow(const Color(0xCCFFFFFF), 3));
    c.restore();
  }
}

// --- Backgrounds --------------------------------------------------------------

void _novaSpace(Canvas c) {
  const r = Rect.fromLTWH(0, 0, 960, 540);
  c.drawRect(r, _linear(r, const [Color(0xFF060816), Color(0xFF0B1238), Color(0xFF1B0B33)], begin: Alignment.topLeft, end: Alignment.bottomRight));
  final rng = math.Random(4);
  const tints = [Color(0x30A855F7), Color(0x2822D3EE), Color(0x28EC4899), Color(0x203B82F6)];
  for (var k = 0; k < 14; k++) {
    final at = Offset(rng.nextDouble() * 960, rng.nextDouble() * 540);
    c.drawCircle(at, 90 + rng.nextDouble() * 200, _glow(tints[k % tints.length], 80));
  }
}

/// Draws [draw] at x, x - [width] and x + [width], so an image that repeats
/// sideways joins without a seam.
void _wrapped(Canvas c, double width, void Function(double dx) draw) {
  for (final dx in [0.0, -width, width]) {
    draw(dx);
  }
}

void _novaNebula(Canvas c) {
  // Wispy clouds that scroll and repeat sideways
  final rng = math.Random(9);
  const tints = [Color(0x26EC4899), Color(0x2422D3EE), Color(0x22A855F7)];
  for (var k = 0; k < 26; k++) {
    final x = rng.nextDouble() * 1280;
    final y = 60 + rng.nextDouble() * 420;
    final w = 200 + rng.nextDouble() * 360, h = 40 + rng.nextDouble() * 90;
    final paint = _glow(tints[k % tints.length], 36);
    _wrapped(c, 1280, (dx) => c.drawOval(Rect.fromCenter(center: Offset(x + dx, y), width: w, height: h), paint));
  }
}

void _novaStars(Canvas c, int seed, int count, double minR, double maxR) {
  final rng = math.Random(seed);
  const tints = [Color(0xFFFFFFFF), Color(0xFFBAE6FD), Color(0xFFFBCFE8), Color(0xFFFEF3C7)];
  for (var k = 0; k < count; k++) {
    final at = Offset(rng.nextDouble() * 960, rng.nextDouble() * 540);
    final r = minR + rng.nextDouble() * (maxR - minR);
    final color = tints[rng.nextInt(tints.length)];
    final alpha = 0.6 + rng.nextDouble() * 0.4;
    _wrapped(c, 960, (dx) {
      final p = at + Offset(dx, 0);
      if (r > 1.6) _softDot(c, p, r * 5, color.withValues(alpha: 0.35));
      c.drawCircle(p, r, _fill(color.withValues(alpha: alpha)));
    });
  }
}

void _novaPlanet(Canvas c) {
  const center = Offset(300, 300);
  // The ring passes behind the planet at the top and in front at the bottom
  void ring({required bool front}) {
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(-0.35);
    c.clipRect(front ? const Rect.fromLTRB(-300, 0, 300, 300) : const Rect.fromLTRB(-300, -300, 300, 0));
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 560, height: 120), _stroke(const Color(0x88F9A8D4), 10, blur: 2));
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 520, height: 104), _stroke(const Color(0x55FDE68A), 4));
    c.restore();
  }

  ring(front: false);
  // Atmosphere glow
  _softDot(c, center, 290, const Color(0x6638BDF8), core: 0.62);
  // Body, lit from the top left
  c.drawCircle(center, 200, _radial(center + const Offset(-70, -80), 330, const [Color(0xFF7DD3FC), Color(0xFF2563EB), Color(0xFF1E1B4B), Color(0xFF0B0716)], stops: const [0, 0.35, 0.75, 1]));
  // Cloud bands
  c.save();
  c.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: 200)));
  for (var k = 0; k < 6; k++) {
    final y = 160.0 + k * 50;
    c.drawOval(Rect.fromCenter(center: Offset(300, y), width: 460, height: 18), _glow(const Color(0x2EE0F2FE), 8));
  }
  // Night side
  c.drawCircle(center + const Offset(90, 90), 230, _glow(const Color(0x880B0716), 40));
  c.restore();
  ring(front: true);
}

/// A frosted-glass panel with a glowing cyan edge (menus and results).
void _glassPanel(Canvas c) {
  const r = Rect.fromLTWH(24, 24, 792, 472);
  final rr = RRect.fromRectAndRadius(r, const Radius.circular(36));
  c.drawRRect(rr, _glow(const Color(0x6622D3EE), 18));
  c.drawRRect(rr, _linear(r, const [Color(0xF0111A3A), Color(0xF00A0F24)]));
  c.drawRRect(rr.deflate(1), _stroke(const Color(0x33FFFFFF), 1));
  c.drawRRect(rr, _stroke(const Color(0xFF22D3EE), 2.5));
  c.drawLine(const Offset(80, 26), const Offset(760, 26), _stroke(const Color(0x88E0F2FE), 2, blur: 1.5));
}

// --- Music ---------------------------------------------------------------------

/// A synthwave loop: four-on-the-floor drums, sub bass, a pad, an echoing arp.
List<double> _novaTheme({required bool boss}) {
  final bpm = boss ? 132.0 : 112.0;
  final beat = 60 / bpm;
  const bars = 16;
  final out = List<double>.filled((bars * 4 * beat * _rate).round(), 0);
  // A minor: Am F C G (boss: Am Am F E, darker and tense)
  final chords = boss
      ? const [[57, 60, 64], [57, 60, 64], [53, 57, 60], [52, 56, 59]]
      : const [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]];
  final arp = List<double>.filled(out.length, 0);
  for (var bar = 0; bar < bars; bar++) {
    final chord = chords[(bar ~/ 2) % 4];
    final t0 = bar * 4 * beat;
    // Pad: the chord, swelling (from bar 2 on)
    if (bar >= 2) {
      for (final n in chord) {
        _synthNote(out, t0, 4 * beat - 0.05, _hz(n), voices: 4, detune: 0.01, bright: 1500, dark: 700, gain: 0.07, a: 0.4, d: 0.5, s: 0.8, r: 0.3);
      }
    }
    // Bass: eighth notes on the root
    for (var k = 0; k < 8; k++) {
      final root = chord[0] - 24;
      final note = (boss && k % 4 == 3) ? root + 12 : root;
      _synthNote(out, t0 + k * beat / 2, beat / 2 - 0.03, _hz(note), voices: 2, detune: 0.006, bright: 900, dark: 220, gain: 0.32, a: 0.003, d: 0.12, s: 0.5, r: 0.04);
    }
    // Arp: sixteenths over the chord, up an octave (from bar 4 on)
    if (bar >= 4) {
      final pattern = [chord[0], chord[1], chord[2], chord[1] + 12, chord[2] + 12, chord[1], chord[0] + 12, chord[2]];
      for (var k = 0; k < 16; k++) {
        _synthNote(arp, t0 + k * beat / 4, beat / 4 - 0.02, _hz(pattern[k % 8] + 12), voices: 2, detune: 0.008, bright: 4200, dark: 900, gain: 0.08, a: 0.002, d: 0.08, s: 0.3, r: 0.06);
      }
    }
    // Drums
    for (var k = 0; k < 4; k++) {
      _kick(out, t0 + k * beat, gain: 0.8);
      if (k == 1 || k == 3) _snare(out, t0 + k * beat, gain: bar < 2 ? 0 : 0.4);
      _hat(out, t0 + k * beat + beat / 2, gain: 0.1);
      if (boss || bar >= 8) _hat(out, t0 + k * beat + beat / 4 * 3, gain: 0.05, decay: 90);
    }
  }
  _delay(arp, beat * 0.75, 0.38, 0.6);
  for (var i = 0; i < out.length; i++) {
    out[i] += arp[i];
  }
  return _master(out);
}

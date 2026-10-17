part of 'generate_template_art.dart';

// ---------------------------------------------------------------------------
// Ember Arena (3D wave shooter): HUD images and music. The 3D world itself is
// built from the engine's mesh primitives, so it needs no textures.

void _saveArena(void Function(String folder, String name, _Img img) save) {
  save('arena', 'vignette.png', _arenaVignette());
  save('arena', 'panel.png', _arenaPanel());
  final music = File('assets/templates/arena/arena.wav')..writeAsBytesSync(_arenaTheme());
  stdout.writeln('wrote ${music.path} (${music.lengthSync() ~/ 1024} KB)');
}

/// Red edges, clear middle: flashed over the screen when the player is hurt.
_Img _arenaVignette() {
  const w = 320, h = 180;
  final img = _Img(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = (x + 0.5 - w / 2) / (w / 2), dy = (y + 0.5 - h / 2) / (h / 2);
      final d = math.sqrt(dx * dx * 0.8 + dy * dy * 1.1);
      final t = ((d - 0.55) / 0.6).clamp(0.0, 1.0);
      final a = (math.pow(t, 1.4) * 215).round();
      if (a > 0) img.set(x, y, a << 24 | 0xD01818);
    }
  }
  return img;
}

/// A dark rounded panel with a molten-orange rim (game over, wave banners).
_Img _arenaPanel() {
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
      if (!inside(x, y, 3)) {
        img.set(x, y, 0xFFF97316);
      } else {
        final shade = 0x11 + (y * 10 ~/ h);
        img.set(x, y, 0xEE000000 | (shade << 16) | (shade + 2) << 8 | (shade + 10));
      }
    }
  }
  return img;
}

/// A driving minor-key loop (E minor, 140 bpm).
Uint8List _arenaTheme() => _chiptune(
      bpm: 140,
      leadAmp: 0.15,
      lead: const [
        (64, 0.5), (0, 0.5), (64, 0.5), (67, 0.5), (71, 1.0), (69, 0.5), (67, 0.5), //
        (66, 0.5), (0, 0.5), (66, 0.5), (69, 0.5), (71, 2.0),
        (72, 0.5), (0, 0.5), (72, 0.5), (71, 0.5), (69, 1.0), (67, 0.5), (66, 0.5),
        (64, 0.5), (66, 0.5), (67, 0.5), (69, 0.5), (71, 2.0),
        (76, 1.0), (74, 0.5), (72, 0.5), (71, 1.0), (67, 1.0),
        (69, 0.5), (71, 0.5), (72, 1.0), (71, 2.0),
        (72, 1.0), (71, 0.5), (69, 0.5), (67, 1.0), (66, 1.0),
        (64, 1.0), (59, 1.0), (64, 2.0),
      ],
      bassRoots: const [40, 40, 38, 38, 36, 36, 35, 35, 40, 40, 36, 36, 33, 33, 35, 40],
    );

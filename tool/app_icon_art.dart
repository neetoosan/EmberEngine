part of 'generate_template_art.dart';

// ---------------------------------------------------------------------------
// Ember Engine app icon: a flame on a dark rounded tile, drawn smoothly
// (4x4 supersampling) at every size Windows, Android and the web need.

void _saveAppIcons() {
  void write(String path, Uint8List bytes) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    stdout.writeln('wrote $path');
  }

  // Windows: one .ico with PNG images inside (Vista and later)
  write('windows/runner/resources/app_icon.ico', _ico([for (final s in [16, 24, 32, 48, 64, 128, 256]) _appIcon(s)]));

  // Android launcher icons
  for (final (dir, size) in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]) {
    write('android/app/src/main/res/mipmap-$dir/ic_launcher.png', _appIcon(size).encodePng());
  }

  // Web: favicon, app icons, and maskable icons (full-bleed background, flame in the safe zone)
  write('web/favicon.png', _appIcon(32).encodePng());
  write('web/icons/Icon-192.png', _appIcon(192).encodePng());
  write('web/icons/Icon-512.png', _appIcon(512).encodePng());
  write('web/icons/Icon-maskable-192.png', _appIcon(192, maskable: true).encodePng());
  write('web/icons/Icon-maskable-512.png', _appIcon(512, maskable: true).encodePng());

  // A copy for docs, store pages and the README
  write('assets/branding/ember_icon_512.png', _appIcon(512).encodePng());
}

int _mix(int a, int b, double t) {
  t = t.clamp(0.0, 1.0);
  int ch(int s) => (((a >> s) & 0xFF) + ((((b >> s) & 0xFF) - ((a >> s) & 0xFF)) * t)).round();
  return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/// Inside test for a leaning teardrop flame: round base, pointed tip.
bool _inFlame(double x, double y, {required double baseX, required double baseY, required double r, required double tipX, required double tipY}) {
  final dx = x - baseX, dy = y - baseY;
  if (dx * dx + dy * dy <= r * r) return true;
  if (y < tipY || y > baseY) return false;
  final t = (y - tipY) / (baseY - tipY); // 0 at the tip, 1 at the base centre
  final centre = tipX + (baseX - tipX) * t;
  final half = r * math.pow(t, 0.75) * (1 + 0.08 * math.sin(t * math.pi * 2));
  return (x - centre).abs() <= half;
}

/// Colour of the icon at (u, v) in 0..1 (unit square), or 0 for transparent.
int _iconSample(double u, double v, bool maskable) {
  // Background tile: rounded square (or the full square for maskable icons)
  const radius = 0.22;
  if (!maskable) {
    final qx = (u - 0.5).abs() - (0.5 - radius), qy = (v - 0.5).abs() - (0.5 - radius);
    final outside = math.sqrt(math.pow(math.max(qx, 0), 2) + math.pow(math.max(qy, 0), 2));
    if (outside > radius) return 0;
  }
  var c = _mix(0xFF2A1810, 0xFF140C09, v); // warm dark gradient

  // Soft glow behind the flame
  final gd = math.sqrt(math.pow(u - 0.5, 2) + math.pow(v - 0.62, 2));
  c = _mix(c, 0xFF7C2D12, (1 - gd / 0.42) * 0.55);

  // Flames scale into the maskable safe zone (inner 80 %)
  final s = maskable ? 0.78 : 1.0;
  final fu = 0.5 + (u - 0.5) / s, fv = 0.55 + (v - 0.55) / s;
  if (_inFlame(fu, fv, baseX: 0.5, baseY: 0.64, r: 0.24, tipX: 0.56, tipY: 0.12)) {
    c = _mix(0xFFFB923C, 0xFFDC2626, (fv - 0.25) / 0.6); // outer flame: orange to red
  }
  if (_inFlame(fu, fv, baseX: 0.5, baseY: 0.70, r: 0.15, tipX: 0.46, tipY: 0.34)) {
    c = _mix(0xFFFEF08A, 0xFFF59E0B, (fv - 0.4) / 0.4); // inner flame: yellow
  }
  if (_inFlame(fu, fv, baseX: 0.5, baseY: 0.74, r: 0.07, tipX: 0.52, tipY: 0.56)) {
    c = 0xFFFFFBEB; // white-hot core
  }
  // Two floating sparks
  for (final (sx, sy, sr) in [(0.27, 0.30, 0.025), (0.74, 0.40, 0.02)]) {
    if (math.pow(fu - sx, 2) + math.pow(fv - sy, 2) <= sr * sr) c = 0xFFFDBA74;
  }
  return c;
}

_Img _appIcon(int size, {bool maskable = false}) {
  final img = _Img(size, size);
  const ss = 4;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var a = 0.0, r = 0.0, g = 0.0, b = 0.0;
      for (var sy = 0; sy < ss; sy++) {
        for (var sx = 0; sx < ss; sx++) {
          final c = _iconSample((x + (sx + 0.5) / ss) / size, (y + (sy + 0.5) / ss) / size, maskable);
          final ca = ((c >> 24) & 0xFF) / 255;
          a += ca;
          r += ((c >> 16) & 0xFF) * ca;
          g += ((c >> 8) & 0xFF) * ca;
          b += (c & 0xFF) * ca;
        }
      }
      if (a == 0) continue;
      final n = ss * ss;
      img.set(x, y, ((a / n * 255).round() << 24) | ((r / a).round() << 16) | ((g / a).round() << 8) | (b / a).round());
    }
  }
  return img;
}

/// A Windows .ico holding PNG-compressed images.
Uint8List _ico(List<_Img> images) {
  final pngs = [for (final i in images) i.encodePng()];
  final header = ByteData(6 + 16 * images.length)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little) // icon
    ..setUint16(4, images.length, Endian.little);
  var offset = header.lengthInBytes;
  for (var i = 0; i < images.length; i++) {
    final e = 6 + i * 16;
    header
      ..setUint8(e, images[i].w >= 256 ? 0 : images[i].w)
      ..setUint8(e + 1, images[i].h >= 256 ? 0 : images[i].h)
      ..setUint8(e + 2, 0)
      ..setUint8(e + 3, 0)
      ..setUint16(e + 4, 1, Endian.little) // colour planes
      ..setUint16(e + 6, 32, Endian.little) // bits per pixel
      ..setUint32(e + 8, pngs[i].length, Endian.little)
      ..setUint32(e + 12, offset, Endian.little);
    offset += pngs[i].length;
  }
  final out = BytesBuilder()..add(header.buffer.asUint8List());
  for (final p in pngs) {
    out.add(p);
  }
  return out.toBytes();
}

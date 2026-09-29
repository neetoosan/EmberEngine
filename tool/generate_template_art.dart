// Generates the original pixel art used by the built-in game templates.
//
//   dart run tool/generate_template_art.dart
//
// Output: assets/templates/flappy/*.png (committed, so this only needs to be
// re-run after changing the art below).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main() {
  final out = Directory('assets/templates/flappy')..createSync(recursive: true);
  void save(String name, _Img img) {
    File('${out.path}/$name').writeAsBytesSync(img.encodePng());
    stdout.writeln('wrote ${out.path}/$name (${img.w}x${img.h})');
  }

  save('bird.png', _birdSheet());
  save('pipe_body.png', _pipeBody());
  save('pipe_cap.png', _pipeCap());
  save('ground.png', _ground());
  save('cloud.png', _cloud());
  save('hills.png', _hills());
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

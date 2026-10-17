import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'project_manifest.dart';

/// A game's icon at every size the export targets need.
class GameIconSet {
  /// Square PNGs by pixel size.
  final Map<int, Uint8List> png;
  const GameIconSet(this.png);

  Uint8List operator [](int size) => png[size]!;

  /// Sizes inside the Windows .ico (Explorer, taskbar, title bar, Alt+Tab).
  static const List<int> windowsSizes = [16, 24, 32, 48, 64, 128, 256];

  /// Android launcher icons: (mipmap folder, size).
  static const List<(String, int)> androidSizes = [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)];

  /// Web: favicon and app icons.
  static const List<int> webSizes = [32, 192, 512];

  /// Windows MSIX package images (tiles, Start menu, taskbar).
  static const List<int> msixSizes = [16, 24, 32, 44, 48, 50, 88, 100, 150, 256, 300];

  static List<int> get allSizes => {...windowsSizes, for (final (_, s) in androidSizes) s, ...webSizes, ...msixSizes}.toList()..sort();

  /// A Windows .ico file holding the [windowsSizes] images (PNG-compressed, Vista and later).
  Uint8List toIco() => buildIco([for (final s in windowsSizes) png[s]!], windowsSizes);
}

/// Problems with a picked icon image, to show the user before export.
class IconCheck {
  final int width, height;
  const IconCheck(this.width, this.height);
  bool get isSquare => width == height;
  bool get bigEnough => width >= 256 && height >= 256;
  String? get warning {
    if (!isSquare) return 'The image is ${width}x$height; icons should be square, so it will be squeezed.';
    if (!bigEnough) return 'The image is ${width}x$height; use at least 256x256 (512x512 is best) so large icons stay sharp.';
    return null;
  }
}

class GameIcons {
  GameIcons._();

  static const String defaultIconAsset = 'assets/branding/ember_icon_512.png';

  /// The PNG bytes of [project]'s icon (its own image, or the Ember icon).
  /// [iconPath] previews another project-relative image instead.
  static Future<Uint8List> sourceFor(EmberProject project, {String? iconPath}) async {
    final rel = (iconPath ?? project.game.iconPath).trim();
    if (rel.isNotEmpty && project.path.isNotEmpty) {
      final file = File('${project.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');
      if (await file.exists()) return file.readAsBytes();
      throw FileSystemException('The game icon was not found (Project Settings → Icon)', file.path);
    }
    final data = await rootBundle.load(defaultIconAsset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// Width and height of an image file, for [IconCheck].
  static Future<IconCheck> inspect(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final check = IconCheck(frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return check;
  }

  /// Renders [source] (any image Flutter can decode) at [sizes], smoothly scaled.
  static Future<GameIconSet> render(Uint8List source, {List<int>? sizes}) async {
    final codec = await ui.instantiateImageCodec(source);
    final image = (await codec.getNextFrame()).image;
    final out = <int, Uint8List>{};
    try {
      for (final size in sizes ?? GameIconSet.allSizes) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
          Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true,
        );
        final scaled = await recorder.endRecording().toImage(size, size);
        final bytes = await scaled.toByteData(format: ui.ImageByteFormat.png);
        scaled.dispose();
        out[size] = bytes!.buffer.asUint8List();
      }
    } finally {
      image.dispose();
      codec.dispose();
    }
    return GameIconSet(out);
  }
}

/// A Windows .ico made of PNG images (each [pngs][i] is [sizes][i] pixels square).
Uint8List buildIco(List<Uint8List> pngs, List<int> sizes) {
  final header = ByteData(6 + 16 * pngs.length)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little) // type: icon
    ..setUint16(4, pngs.length, Endian.little);
  var offset = header.lengthInBytes;
  for (var i = 0; i < pngs.length; i++) {
    final e = 6 + i * 16;
    final s = sizes[i];
    header
      ..setUint8(e, s >= 256 ? 0 : s) // 0 means 256
      ..setUint8(e + 1, s >= 256 ? 0 : s)
      ..setUint16(e + 4, 1, Endian.little) // colour planes
      ..setUint16(e + 6, 32, Endian.little) // bits per pixel
      ..setUint32(e + 8, pngs[i].length, Endian.little)
      ..setUint32(e + 12, offset, Endian.little);
    offset += pngs[i].length;
  }
  final out = BytesBuilder(copy: false)..add(header.buffer.asUint8List());
  for (final p in pngs) {
    out.add(p);
  }
  return out.toBytes();
}

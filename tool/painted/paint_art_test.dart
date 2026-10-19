// Paints the smooth, modern art and music of the newer templates with
// Flutter's own canvas (anti-aliased shapes, gradients, soft glow).
//
//   flutter test tool/painted/paint_art_test.dart
//
// Output: assets/templates/{nova,bastion,depths,spire,isles,pulse,clash,kindred}/* (committed, so this only needs to be
// re-run after changing the art below). The older templates' pixel art comes
// from tool/generate_template_art.dart.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/templates/bastion_layout.dart';
import 'package:ember_engine/templates/pulse_song.dart';

part 'bastion_art.dart';
part 'clash_art.dart';
part 'depths_art.dart';
part 'isles_art.dart';
part 'kindred_art.dart';
part 'spire_art.dart';
part 'nova_art.dart';
part 'pulse_art.dart';
part 'synth.dart';

void main() {
  test('paint the template art', () async {
    final only = Platform.environment['ONLY'];
    if (only == null || only == 'nova') await _paintNova();
    if (only == null || only == 'bastion') await _paintBastion();
    if (only == null || only == 'depths') await _paintDepths();
    if (only == null || only == 'spire') await _paintSpire();
    if (only == null || only == 'isles') await _paintIsles();
    if (only == null || only == 'pulse') await _paintPulse();
    if (only == null || only == 'clash') await _paintClash();
    if (only == null || only == 'kindred') await _paintKindred();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

// ---------------------------------------------------------------------------
// Canvas helpers

/// Paints a [w] × [h] image and writes it to assets/templates/[folder]/[name].
Future<void> _png(String folder, String name, int w, int h, void Function(Canvas c) draw) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec));
  final img = await rec.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final out = Directory('assets/templates/$folder')..createSync(recursive: true);
  File('${out.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  stdout.writeln('wrote ${out.path}/$name (${w}x$h)');
}

/// A sprite sheet of [count] cells of [cw] × [ch] in [columns] columns; [draw]
/// paints cell [i] with its top-left at the origin (clipped to the cell).
Future<void> _sheet(String folder, String name, int cw, int ch, int count, void Function(Canvas c, int i) draw, {int? columns}) {
  final cols = columns ?? count;
  final rows = (count + cols - 1) ~/ cols;
  return _png(folder, name, cw * cols, ch * rows, (c) {
    for (var i = 0; i < count; i++) {
      c.save();
      c.translate((i % cols) * cw.toDouble(), (i ~/ cols) * ch.toDouble());
      c.clipRect(Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()));
      draw(c, i);
      c.restore();
    }
  });
}

Paint _fill(Color c) => Paint()..color = c;

Paint _glow(Color c, double blur) => Paint()
  ..color = c
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

Paint _stroke(Color c, double width, {double blur = 0}) {
  final p = Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
  return p;
}

Paint _linear(Rect r, List<Color> colors, {Alignment begin = Alignment.topCenter, Alignment end = Alignment.bottomCenter, List<double>? stops}) =>
    Paint()..shader = LinearGradient(begin: begin, end: end, colors: colors, stops: stops).createShader(r);

Paint _radial(Offset center, double radius, List<Color> colors, {List<double>? stops}) => Paint()
  ..shader = RadialGradient(colors: colors, stops: stops).createShader(Rect.fromCircle(center: center, radius: radius));

Path _poly(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final o in pts.skip(1)) {
    p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

/// [pts] mirrored top-to-bottom around y = [axis].
List<Offset> _mirrorY(List<Offset> pts, double axis) => [for (final p in pts.reversed) Offset(p.dx, 2 * axis - p.dy)];

/// A soft round glow (bright centre, fading edge), for light and shots.
void _softDot(Canvas c, Offset at, double r, Color color, {double core = 0.25}) {
  c.drawCircle(at, r, _radial(at, r, [color, color.withValues(alpha: color.a * 0.45), color.withValues(alpha: 0)], stops: [core, 0.55, 1]));
}

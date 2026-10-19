import 'dart:math' as math;
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/transform2d.dart';

enum LineStyle2D { line, dots }

/// Draws a line in the world: from this entity to [target] (slingshot bands,
/// ropes, tethers), or through [points] set by a script (aim trajectories).
class Line2DComponent extends EmberComponent {
  /// Entity to draw to (from this entity's centre to the target's centre).
  String target;

  /// World-space points (used when [target] is empty).
  List<vm.Vector2> points;

  Color color;

  /// Line thickness, or dot radius for [LineStyle2D.dots].
  double width;
  LineStyle2D style;

  /// Dots shrink and fade towards the end (trajectory previews).
  bool taper;

  /// A soft light around the line that adds up like light (lasers, lightning).
  bool glow;

  Line2DComponent({
    this.target = '',
    List<vm.Vector2>? points,
    this.color = const Color(0xFFFFFFFF),
    this.width = 3,
    this.style = LineStyle2D.line,
    this.taper = false,
    this.glow = false,
  }) : points = points ?? [];

  /// Shortest distance from ([x], [y]) to the line (infinite if it has no points).
  double distanceTo(double x, double y) {
    final pts = resolvedPoints();
    if (pts.isEmpty) return double.infinity;
    if (pts.length == 1) return math.sqrt((pts[0].x - x) * (pts[0].x - x) + (pts[0].y - y) * (pts[0].y - y));
    var best = double.infinity;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final dx = b.x - a.x, dy = b.y - a.y;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (((x - a.x) * dx + (y - a.y) * dy) / len2).clamp(0.0, 1.0);
      final px = a.x + dx * t - x, py = a.y + dy * t - y;
      best = math.min(best, math.sqrt(px * px + py * py));
    }
    return best;
  }

  static vm.Vector2 _centerOf(EmberEntity e) {
    final t = e.getComponent<Transform2DComponent>();
    if (t == null) return vm.Vector2.zero();
    final p = t.worldPosition;
    final s = t.worldScale;
    return vm.Vector2(p.x + (t.size.x / 2 - t.anchorOffset.x) * s.x, p.y + (t.size.y / 2 - t.anchorOffset.y) * s.y);
  }

  /// The world points to draw this frame.
  List<vm.Vector2> resolvedPoints() {
    final e = entity;
    if (target.isNotEmpty && e != null) {
      final other = e.scene?.findEntityByName(target);
      if (other == null || !other.enabled) return const [];
      return [_centerOf(e), _centerOf(other)];
    }
    return points;
  }

  void paint(Canvas canvas) {
    final pts = resolvedPoints();
    if (pts.isEmpty || width <= 0) return;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (style == LineStyle2D.dots) {
      for (var i = 0; i < pts.length; i++) {
        final f = taper && pts.length > 1 ? 1 - i / (pts.length - 1) * 0.6 : 1.0;
        paint.color = color.withValues(alpha: color.a * (taper ? 0.35 + 0.65 * f : 1));
        canvas.drawCircle(Offset(pts[i].x, pts[i].y), width * f, paint);
      }
      return;
    }
    if (pts.length < 2) return;
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(pts.first.x, pts.first.y);
    for (final p in pts.skip(1)) {
      path.lineTo(p.x, p.y);
    }
    if (glow) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width * 4
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = color.withValues(alpha: color.a * 0.55)
            ..blendMode = BlendMode.plus
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 2.5));
    }
    canvas.drawPath(path, paint);
  }

  @override
  String get displayName => 'Line 2D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'target',
          label: 'Draw To',
          type: InspectableType.string,
          getter: () => target,
          setter: (v) {
            target = v;
            notifyListeners();
          },
          tooltip: 'Entity name to draw a line to (empty: points set by a script)',
        ),
        InspectableProperty<Color>(
          name: 'color',
          label: 'Color',
          type: InspectableType.color,
          getter: () => color,
          setter: (v) {
            color = v;
            notifyListeners();
          },
        ),
        InspectableProperty<double>(
          name: 'width',
          label: 'Width',
          type: InspectableType.number,
          getter: () => width,
          setter: (v) {
            width = v < 0 ? 0 : v;
            notifyListeners();
          },
          step: 0.5,
          min: 0,
          tooltip: 'Thickness (or dot radius)',
        ),
        InspectableProperty<String>(
          name: 'style',
          label: 'Style',
          type: InspectableType.options,
          getter: () => style.name,
          setter: (v) {
            style = LineStyle2D.values.firstWhere((s) => s.name == v, orElse: () => LineStyle2D.line);
            notifyListeners();
          },
          options: LineStyle2D.values.map((s) => s.name).toList(),
        ),
        InspectableProperty<bool>(
          name: 'taper',
          label: 'Taper',
          type: InspectableType.boolean,
          getter: () => taper,
          setter: (v) {
            taper = v;
            notifyListeners();
          },
          tooltip: 'Dots shrink and fade towards the end',
        ),
        InspectableProperty<bool>(
          name: 'glow',
          label: 'Glow',
          type: InspectableType.boolean,
          getter: () => glow,
          setter: (v) {
            glow = v;
            notifyListeners();
          },
          tooltip: 'A soft light around the line (lasers, lightning)',
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'target': target,
        if (points.isNotEmpty) 'points': [for (final p in points) [p.x, p.y]],
        'color': color.toARGB32(),
        'width': width,
        'style': style.name,
        'taper': taper,
        if (glow) 'glow': true,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    target = json['target'] as String? ?? '';
    points = [
      for (final p in (json['points'] as List?) ?? const [])
        if (p is List && p.length == 2) vm.Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
    color = Color(json['color'] as int? ?? 0xFFFFFFFF);
    width = (json['width'] as num?)?.toDouble() ?? 3;
    style = LineStyle2D.values.firstWhere((s) => s.name == json['style'], orElse: () => LineStyle2D.line);
    taper = json['taper'] as bool? ?? false;
    glow = json['glow'] as bool? ?? false;
    notifyListeners();
  }

  @override
  Line2DComponent clone() => Line2DComponent()..fromJson(toJson());
}

void registerLine2D() {
  ComponentRegistry.register('Line 2D', (json) => Line2DComponent()..fromJson(json));
}

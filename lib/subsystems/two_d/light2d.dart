import 'dart:math' as math;
import 'dart:ui';
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/transform2d.dart';

/// A light in a dark 2D scene (torches, lanterns, glowing crystals). It only
/// shows when the Camera 2D has some Darkness: it cuts a soft round hole in
/// the dark, [radius] pixels wide, and can tint the area with [color].
/// [flicker] (0 .. 1) makes it waver like a flame.
class Light2DComponent extends EmberComponent {
  double radius;
  Color color;

  /// How much it lights: 1 removes the darkness at its centre.
  double intensity;

  /// 0 steady, 1 a lively flame.
  double flicker;

  /// Adds a coloured glow on top (off: it only removes darkness).
  bool tint;

  double _time = 0;
  final double _phase = math.Random().nextDouble() * 100;

  Light2DComponent({this.radius = 160, this.color = const Color(0xFFFFC27A), this.intensity = 1, this.flicker = 0, this.tint = true});

  @override
  void onUpdate(double dt) => _time += dt;

  /// The radius right now, with flicker.
  double get currentRadius {
    if (flicker <= 0) return radius;
    final t = _time + _phase;
    final wave = math.sin(t * 9.1) * 0.5 + math.sin(t * 23.7) * 0.3 + math.sin(t * 3.3) * 0.2;
    return radius * (1 + wave * 0.06 * flicker);
  }

  /// World centre of the light (the middle of the entity's box).
  Offset get center {
    final t = entity?.getComponent<Transform2DComponent>();
    if (t == null) return Offset.zero;
    final p = t.worldPosition;
    final s = t.worldScale;
    return Offset(p.x + (t.size.x / 2 - t.anchorOffset.x) * s.x, p.y + (t.size.y / 2 - t.anchorOffset.y) * s.y);
  }

  @override
  String get displayName => 'Light 2D';

  InspectableProperty<T> _prop<T>(String name, String label, InspectableType type, T Function() get, void Function(T) set,
          {String? tooltip, double? min, double? max, double step = 0.1}) =>
      InspectableProperty<T>(
          name: name,
          label: label,
          type: type,
          getter: get,
          setter: (v) {
            set(v);
            notifyListeners();
          },
          tooltip: tooltip,
          min: min,
          max: max,
          step: step);

  @override
  List<InspectableProperty> get inspectableProperties => [
        _prop<double>('radius', 'Radius', InspectableType.number, () => radius, (v) => radius = math.max(1, v), min: 1, step: 5),
        _prop<Color>('color', 'Color', InspectableType.color, () => color, (v) => color = v),
        _prop<double>('intensity', 'Intensity', InspectableType.number, () => intensity, (v) => intensity = v.clamp(0, 2).toDouble(), min: 0, max: 2, step: 0.05),
        _prop<double>('flicker', 'Flicker', InspectableType.number, () => flicker, (v) => flicker = v.clamp(0, 1).toDouble(),
            min: 0, max: 1, step: 0.05, tooltip: '0 steady, 1 a lively flame'),
        _prop<bool>('tint', 'Coloured Glow', InspectableType.boolean, () => tint, (v) => tint = v),
      ];

  @override
  Map<String, dynamic> toJson() => {'radius': radius, 'color': color.toARGB32(), 'intensity': intensity, 'flicker': flicker, 'tint': tint};

  @override
  void fromJson(Map<String, dynamic> json) {
    radius = (json['radius'] as num?)?.toDouble() ?? 160;
    color = Color(json['color'] as int? ?? 0xFFFFC27A);
    intensity = (json['intensity'] as num?)?.toDouble() ?? 1;
    flicker = (json['flicker'] as num?)?.toDouble() ?? 0;
    tint = json['tint'] as bool? ?? true;
    notifyListeners();
  }

  @override
  Light2DComponent clone() => Light2DComponent()..fromJson(toJson());

  /// Darkens [area] by [darkness] (in [darkColor]) except around the lights,
  /// then adds their coloured glow. Called by the 2D renderer in world space.
  static void paintDarkness(Canvas canvas, Rect area, double darkness, Color darkColor, Iterable<Light2DComponent> lights) {
    canvas.saveLayer(area, Paint());
    canvas.drawRect(area, Paint()..color = darkColor.withValues(alpha: darkness.clamp(0.0, 1.0)));
    final cut = Paint()..blendMode = BlendMode.dstOut;
    for (final l in lights) {
      final r = l.currentRadius;
      final c = l.center;
      if (!area.inflate(r).contains(c)) continue;
      cut.shader = Gradient.radial(c, r, [
        Color.fromRGBO(0, 0, 0, l.intensity.clamp(0.0, 1.0)),
        Color.fromRGBO(0, 0, 0, l.intensity.clamp(0.0, 1.0) * 0.55),
        const Color(0x00000000),
      ], const [0, 0.45, 1]);
      canvas.drawCircle(c, r, cut);
    }
    canvas.restore();
    final glow = Paint()..blendMode = BlendMode.plus;
    for (final l in lights) {
      if (!l.tint) continue;
      final r = l.currentRadius;
      final c = l.center;
      if (!area.inflate(r).contains(c)) continue;
      glow.shader = Gradient.radial(c, r * 0.8, [l.color.withValues(alpha: 0.22 * l.intensity.clamp(0.0, 1.0)), l.color.withValues(alpha: 0)]);
      canvas.drawCircle(c, r * 0.8, glow);
    }
  }
}

void registerLight2D() {
  ComponentRegistry.register('Light 2D', (json) => Light2DComponent()..fromJson(json));
}

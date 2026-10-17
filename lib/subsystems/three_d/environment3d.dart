import 'package:flutter/material.dart';
import '../../core/component.dart';
import '../../core/inspectable.dart';

/// Sky and distance fog for a 3D scene (one per scene; the first enabled one is used).
///
/// The sky is a gradient from [skyTop] down to [horizon] at the horizon line.
/// Fog blends surfaces toward [fogColor] between [fogStart] and [fogEnd]
/// metres from the camera, so distant walls fade into the air instead of
/// ending abruptly.
class Environment3DComponent extends EmberComponent {
  Color skyTop;
  Color horizon;
  Color ground;
  Color fogColor;
  bool fog;
  double fogStart;
  double fogEnd;

  /// How much fog at [fogEnd] and beyond (1 = surfaces disappear completely).
  double fogMax;

  Environment3DComponent({
    this.skyTop = const Color(0xFF0F172A),
    this.horizon = const Color(0xFF475569),
    this.ground = const Color(0xFF1E1B24),
    this.fogColor = const Color(0xFF334155),
    this.fog = true,
    this.fogStart = 12,
    this.fogEnd = 60,
    this.fogMax = 0.85,
  });

  @override
  String get displayName => 'Environment 3D';

  InspectableProperty<Color> _color(String name, String label, Color Function() get, void Function(Color) set) => InspectableProperty<Color>(
        name: name,
        label: label,
        type: InspectableType.color,
        getter: get,
        setter: (v) {
          set(v);
          notifyListeners();
        },
      );

  InspectableProperty<double> _number(String name, String label, double Function() get, void Function(double) set, {double min = 0, double max = 500, double step = 1}) =>
      InspectableProperty<double>(
        name: name,
        label: label,
        type: InspectableType.number,
        getter: get,
        setter: (v) {
          set(v);
          notifyListeners();
        },
        min: min,
        max: max,
        step: step,
      );

  @override
  List<InspectableProperty> get inspectableProperties => [
        _color('skyTop', 'Sky (top)', () => skyTop, (v) => skyTop = v),
        _color('horizon', 'Sky (horizon)', () => horizon, (v) => horizon = v),
        _color('ground', 'Below horizon', () => ground, (v) => ground = v),
        InspectableProperty<bool>(
          name: 'fog',
          label: 'Fog',
          type: InspectableType.boolean,
          getter: () => fog,
          setter: (v) {
            fog = v;
            notifyListeners();
          },
        ),
        _color('fogColor', 'Fog Color', () => fogColor, (v) => fogColor = v),
        _number('fogStart', 'Fog Start (m)', () => fogStart, (v) => fogStart = v),
        _number('fogEnd', 'Fog End (m)', () => fogEnd, (v) => fogEnd = v),
        _number('fogMax', 'Fog Amount', () => fogMax, (v) => fogMax = v.clamp(0.0, 1.0), max: 1, step: 0.05),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'skyTop': skyTop.toARGB32(),
        'horizon': horizon.toARGB32(),
        'ground': ground.toARGB32(),
        'fogColor': fogColor.toARGB32(),
        'fog': fog,
        'fogStart': fogStart,
        'fogEnd': fogEnd,
        'fogMax': fogMax,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    final d = Environment3DComponent();
    skyTop = Color(json['skyTop'] as int? ?? d.skyTop.toARGB32());
    horizon = Color(json['horizon'] as int? ?? d.horizon.toARGB32());
    ground = Color(json['ground'] as int? ?? d.ground.toARGB32());
    fogColor = Color(json['fogColor'] as int? ?? d.fogColor.toARGB32());
    fog = json['fog'] as bool? ?? true;
    fogStart = (json['fogStart'] as num?)?.toDouble() ?? d.fogStart;
    fogEnd = (json['fogEnd'] as num?)?.toDouble() ?? d.fogEnd;
    fogMax = (json['fogMax'] as num?)?.toDouble() ?? d.fogMax;
    notifyListeners();
  }

  @override
  Environment3DComponent clone() => Environment3DComponent()..fromJson(toJson());
}

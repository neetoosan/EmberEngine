import 'package:flutter/material.dart';
import '../../core/component.dart';
import '../../core/inspectable.dart';

/// Supported light source types in Ember Engine.
enum LightType {
  directional,
  point,
  ambient,
  spot,
}

/// 3D Light component that illuminates meshes in the scene.
class LightComponent extends EmberComponent {
  LightType _type;
  Color _color;
  double _intensity;
  double _range;

  LightComponent({
    this._type = LightType.directional,
    this._color = Colors.white,
    this._intensity = 1.0,
    this._range = 15.0,
  });

  LightType get type => _type;
  set type(LightType val) {
    _type = val;
    notifyListeners();
  }

  Color get color => _color;
  set color(Color val) {
    _color = val;
    notifyListeners();
  }

  double get intensity => _intensity;
  set intensity(double val) {
    _intensity = val.clamp(0.0, 100.0);
    notifyListeners();
  }

  double get range => _range;
  set range(double val) {
    _range = val.clamp(0.1, 1000.0);
    notifyListeners();
  }

  @override
  String get displayName => 'Light';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<LightType>(
          name: 'type',
          label: 'Light Type',
          type: InspectableType.options,
          getter: () => _type,
          setter: (val) => type = val,
          options: LightType.values.map((l) => l.name).toList(),
        ),
        InspectableProperty<Color>(
          name: 'color',
          label: 'Color',
          type: InspectableType.color,
          getter: () => _color,
          setter: (val) => color = val,
        ),
        InspectableProperty<double>(
          name: 'intensity',
          label: 'Intensity',
          type: InspectableType.number,
          getter: () => _intensity,
          setter: (val) => intensity = val,
          min: 0.0,
          max: 10.0,
          step: 0.1,
        ),
        InspectableProperty<double>(
          name: 'range',
          label: 'Range',
          type: InspectableType.number,
          getter: () => _range,
          setter: (val) => range = val,
          min: 1.0,
          max: 100.0,
          step: 1.0,
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': _type.name,
      'color': _color.toARGB32(),
      'intensity': _intensity,
      'range': _range,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    final tName = json['type'] as String? ?? 'directional';
    _type = LightType.values.firstWhere(
      (l) => l.name == tName,
      orElse: () => LightType.directional,
    );
    _color = Color(json['color'] as int? ?? Colors.white.toARGB32());
    _intensity = (json['intensity'] as num?)?.toDouble() ?? 1.0;
    _range = (json['range'] as num?)?.toDouble() ?? 15.0;
    notifyListeners();
  }

  @override
  LightComponent clone() {
    return LightComponent(
      type: _type,
      color: _color,
      intensity: _intensity,
      range: _range,
    );
  }
}

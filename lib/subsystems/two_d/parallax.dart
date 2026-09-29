import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';

/// Makes a 2D entity a background (or foreground) layer that moves at a
/// different speed than the camera, for depth.
///
/// [factorX] 1.0 = moves with the world (normal), 0.0 = fixed to the screen,
/// 0.3 = distant hills. [repeatX] tiles the sprite sideways to fill the view.
class ParallaxLayerComponent extends EmberComponent {
  double factorX;
  double factorY;
  bool repeatX;

  ParallaxLayerComponent({this.factorX = 0.5, this.factorY = 1.0, this.repeatX = true});

  @override
  String get displayName => 'Parallax Layer';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<double>(
          name: 'factorX',
          label: 'Horizontal Speed',
          type: InspectableType.number,
          getter: () => factorX,
          setter: (v) {
            factorX = v;
            notifyListeners();
          },
          step: 0.05,
          tooltip: '1 = moves with the world, 0 = stays on screen',
        ),
        InspectableProperty<double>(
          name: 'factorY',
          label: 'Vertical Speed',
          type: InspectableType.number,
          getter: () => factorY,
          setter: (v) {
            factorY = v;
            notifyListeners();
          },
          step: 0.05,
        ),
        InspectableProperty<bool>(
          name: 'repeatX',
          label: 'Repeat Sideways',
          type: InspectableType.boolean,
          getter: () => repeatX,
          setter: (v) {
            repeatX = v;
            notifyListeners();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {'factorX': factorX, 'factorY': factorY, 'repeatX': repeatX};

  @override
  void fromJson(Map<String, dynamic> json) {
    factorX = (json['factorX'] as num?)?.toDouble() ?? 0.5;
    factorY = (json['factorY'] as num?)?.toDouble() ?? 1.0;
    repeatX = json['repeatX'] as bool? ?? true;
    notifyListeners();
  }

  @override
  ParallaxLayerComponent clone() => ParallaxLayerComponent(factorX: factorX, factorY: factorY, repeatX: repeatX);
}

void registerParallax() {
  ComponentRegistry.register('Parallax Layer', (json) => ParallaxLayerComponent()..fromJson(json));
}

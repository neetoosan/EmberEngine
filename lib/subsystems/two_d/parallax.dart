import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';

/// Makes a 2D entity a background (or foreground) layer that moves at a
/// different speed than the camera, for depth.
///
/// [factorX] 1.0 = moves with the world (normal), 0.0 = fixed to the screen,
/// 0.3 = distant hills. [repeatX] / [repeatY] tile the sprite to fill the
/// view. [scrollX] / [scrollY] scroll it on their own while the game runs
/// (pixels per second), e.g. a starfield in a shooter.
class ParallaxLayerComponent extends EmberComponent {
  double factorX;
  double factorY;
  bool repeatX;
  bool repeatY;
  double scrollX;
  double scrollY;

  /// How far it has scrolled by itself so far.
  final vm.Vector2 scrolled = vm.Vector2.zero();

  ParallaxLayerComponent({this.factorX = 0.5, this.factorY = 1.0, this.repeatX = true, this.repeatY = false, this.scrollX = 0, this.scrollY = 0});

  @override
  void onUpdate(double dt) {
    scrolled.x += scrollX * dt;
    scrolled.y += scrollY * dt;
  }

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
        InspectableProperty<bool>(
          name: 'repeatY',
          label: 'Repeat Up/Down',
          type: InspectableType.boolean,
          getter: () => repeatY,
          setter: (v) {
            repeatY = v;
            notifyListeners();
          },
        ),
        InspectableProperty<double>(
          name: 'scrollX',
          label: 'Auto Scroll X',
          type: InspectableType.number,
          getter: () => scrollX,
          setter: (v) {
            scrollX = v;
            notifyListeners();
          },
          step: 5,
          tooltip: 'Pixels per second, while the game runs',
        ),
        InspectableProperty<double>(
          name: 'scrollY',
          label: 'Auto Scroll Y',
          type: InspectableType.number,
          getter: () => scrollY,
          setter: (v) {
            scrollY = v;
            notifyListeners();
          },
          step: 5,
          tooltip: 'Pixels per second, while the game runs',
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'factorX': factorX,
        'factorY': factorY,
        'repeatX': repeatX,
        if (repeatY) 'repeatY': true,
        if (scrollX != 0) 'scrollX': scrollX,
        if (scrollY != 0) 'scrollY': scrollY,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    factorX = (json['factorX'] as num?)?.toDouble() ?? 0.5;
    factorY = (json['factorY'] as num?)?.toDouble() ?? 1.0;
    repeatX = json['repeatX'] as bool? ?? true;
    repeatY = json['repeatY'] as bool? ?? false;
    scrollX = (json['scrollX'] as num?)?.toDouble() ?? 0;
    scrollY = (json['scrollY'] as num?)?.toDouble() ?? 0;
    notifyListeners();
  }

  @override
  ParallaxLayerComponent clone() =>
      ParallaxLayerComponent(factorX: factorX, factorY: factorY, repeatX: repeatX, repeatY: repeatY, scrollX: scrollX, scrollY: scrollY);
}

void registerParallax() {
  ComponentRegistry.register('Parallax Layer', (json) => ParallaxLayerComponent()..fromJson(json));
}

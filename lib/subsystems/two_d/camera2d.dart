import 'dart:math' as math;
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';

/// Where and how a 2D camera shows the world on screen.
class CameraView2D {
  /// Screen rectangle the game is drawn into (letterboxed inside the window).
  final Rect viewport;

  /// Screen pixels per world pixel.
  final double zoom;

  /// World point shown at the centre of [viewport].
  final vm.Vector2 center;

  const CameraView2D({required this.viewport, required this.zoom, required this.center});

  vm.Vector2 screenToWorld(Offset p) => vm.Vector2(
        center.x + (p.dx - viewport.center.dx) / zoom,
        center.y + (p.dy - viewport.center.dy) / zoom,
      );

  Offset worldToScreen(vm.Vector2 w) => Offset(
        viewport.center.dx + (w.x - center.x) * zoom,
        viewport.center.dy + (w.y - center.y) * zoom,
      );
}

/// 2D game camera. The entity's Transform 2D position is the point shown at
/// the centre of the screen.
///
/// - **Design size**: the game is authored for e.g. 288×512 and scaled to fit
///   any window, keeping its aspect ratio (bars fill the rest).
/// - **Follow**: tracks the entity named [followTarget], with [smoothing].
/// - **Bounds**: never shows outside [boundsMin]–[boundsMax] (level edges).
class Camera2DComponent extends EmberComponent {
  double designWidth;
  double designHeight;
  String followTarget;

  /// 0 = snap to the target, towards 1 = lazier follow.
  double smoothing;

  /// Keep the target this far from the centre (world pixels) before moving.
  vm.Vector2 deadZone;

  bool boundsEnabled;
  vm.Vector2 boundsMin;
  vm.Vector2 boundsMax;

  /// Fills the game area behind everything.
  Color backgroundColor;

  Camera2DComponent({
    this.designWidth = 640,
    this.designHeight = 360,
    this.followTarget = '',
    this.smoothing = 0.85,
    vm.Vector2? deadZone,
    this.boundsEnabled = false,
    vm.Vector2? boundsMin,
    vm.Vector2? boundsMax,
    this.backgroundColor = const Color(0xFF121316),
  })  : deadZone = deadZone ?? vm.Vector2.zero(),
        boundsMin = boundsMin ?? vm.Vector2.zero(),
        boundsMax = boundsMax ?? vm.Vector2(640, 360);

  /// The first enabled camera in [scene], if any.
  static Camera2DComponent? findIn(EmberScene scene) {
    for (final cam in scene.componentsOf<Camera2DComponent>()) {
      final e = cam.entity;
      if (e != null && e.enabled && cam.enabled && e.hasComponent<Transform2DComponent>()) return cam;
    }
    return null;
  }

  vm.Vector2 get position =>
      entity?.getComponent<Transform2DComponent>()?.worldPosition ?? vm.Vector2.zero();

  /// How this camera maps onto a window of [screen] size.
  CameraView2D viewFor(Size screen) {
    final hasDesign = designWidth > 0 && designHeight > 0;
    final zoom = hasDesign ? math.min(screen.width / designWidth, screen.height / designHeight) : 1.0;
    final w = hasDesign ? designWidth * zoom : screen.width;
    final h = hasDesign ? designHeight * zoom : screen.height;
    return CameraView2D(
      viewport: Rect.fromCenter(center: Offset(screen.width / 2, screen.height / 2), width: w, height: h),
      zoom: zoom,
      center: position,
    );
  }

  @override
  void onStart() => snapToTarget();

  @override
  void onUpdate(double dt) {
    final t = entity?.getComponent<Transform2DComponent>();
    final target = _targetPosition();
    if (t == null) return;
    var p = t.position.clone();
    if (target != null) {
      final desired = p.clone();
      final d = target - p;
      if (d.x.abs() > deadZone.x) desired.x = target.x - deadZone.x * d.x.sign;
      if (d.y.abs() > deadZone.y) desired.y = target.y - deadZone.y * d.y.sign;
      // Frame-rate independent exponential smoothing
      final k = smoothing <= 0 ? 1.0 : 1.0 - math.pow(smoothing.clamp(0.0, 0.999), dt * 60).toDouble();
      p += (desired - p) * k;
    }
    t.position = _clamp(p);
  }

  /// Jumps straight to the follow target (used when a level starts).
  void snapToTarget() {
    final t = entity?.getComponent<Transform2DComponent>();
    final target = _targetPosition();
    if (t != null && target != null) t.position = _clamp(target);
  }

  vm.Vector2? _targetPosition() {
    if (followTarget.isEmpty) return null;
    return entity?.scene?.findEntityByName(followTarget)?.getComponent<Transform2DComponent>()?.worldPosition;
  }

  vm.Vector2 _clamp(vm.Vector2 p) {
    if (!boundsEnabled) return p;
    final halfW = designWidth / 2;
    final halfH = designHeight / 2;
    double clampAxis(double v, double lo, double hi) => hi - lo < 0 ? (lo + hi) / 2 : v.clamp(lo, hi);
    return vm.Vector2(
      clampAxis(p.x, boundsMin.x + halfW, boundsMax.x - halfW),
      clampAxis(p.y, boundsMin.y + halfH, boundsMax.y - halfH),
    );
  }

  @override
  String get displayName => 'Camera 2D';

  InspectableProperty<double> _num(String name, String label, double Function() get, void Function(double) set,
          {double step = 1, double? min, double? max}) =>
      InspectableProperty<double>(
        name: name,
        label: label,
        type: InspectableType.number,
        getter: get,
        setter: (v) {
          set(v);
          notifyListeners();
        },
        step: step,
        min: min,
        max: max,
      );

  @override
  List<InspectableProperty> get inspectableProperties => [
        _num('designWidth', 'Design Width', () => designWidth, (v) => designWidth = v, min: 0),
        _num('designHeight', 'Design Height', () => designHeight, (v) => designHeight = v, min: 0),
        InspectableProperty<String>(
          name: 'followTarget',
          label: 'Follow Entity',
          type: InspectableType.string,
          getter: () => followTarget,
          setter: (v) {
            followTarget = v;
            notifyListeners();
          },
          tooltip: 'Name of the entity to follow (empty = fixed camera)',
        ),
        _num('smoothing', 'Smoothing', () => smoothing, (v) => smoothing = v.clamp(0.0, 0.99), step: 0.05, min: 0, max: 0.99),
        InspectableProperty<vm.Vector2>(
          name: 'deadZone',
          label: 'Dead Zone',
          type: InspectableType.vector2,
          getter: () => deadZone,
          setter: (v) {
            deadZone = v;
            notifyListeners();
          },
        ),
        InspectableProperty<bool>(
          name: 'boundsEnabled',
          label: 'Limit To Bounds',
          type: InspectableType.boolean,
          getter: () => boundsEnabled,
          setter: (v) {
            boundsEnabled = v;
            notifyListeners();
          },
        ),
        InspectableProperty<vm.Vector2>(
          name: 'boundsMin',
          label: 'Bounds Min',
          type: InspectableType.vector2,
          getter: () => boundsMin,
          setter: (v) {
            boundsMin = v;
            notifyListeners();
          },
        ),
        InspectableProperty<vm.Vector2>(
          name: 'boundsMax',
          label: 'Bounds Max',
          type: InspectableType.vector2,
          getter: () => boundsMax,
          setter: (v) {
            boundsMax = v;
            notifyListeners();
          },
        ),
        InspectableProperty<Color>(
          name: 'backgroundColor',
          label: 'Background',
          type: InspectableType.color,
          getter: () => backgroundColor,
          setter: (v) {
            backgroundColor = v;
            notifyListeners();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'designWidth': designWidth,
        'designHeight': designHeight,
        'followTarget': followTarget,
        'smoothing': smoothing,
        'deadZone': [deadZone.x, deadZone.y],
        'boundsEnabled': boundsEnabled,
        'boundsMin': [boundsMin.x, boundsMin.y],
        'boundsMax': [boundsMax.x, boundsMax.y],
        'backgroundColor': backgroundColor.toARGB32(),
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    vm.Vector2 v2(Object? raw, vm.Vector2 fallback) {
      if (raw is! List || raw.length < 2) return fallback;
      return vm.Vector2((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
    }

    designWidth = (json['designWidth'] as num?)?.toDouble() ?? 640;
    designHeight = (json['designHeight'] as num?)?.toDouble() ?? 360;
    followTarget = json['followTarget'] as String? ?? '';
    smoothing = (json['smoothing'] as num?)?.toDouble() ?? 0.85;
    deadZone = v2(json['deadZone'], vm.Vector2.zero());
    boundsEnabled = json['boundsEnabled'] as bool? ?? false;
    boundsMin = v2(json['boundsMin'], vm.Vector2.zero());
    boundsMax = v2(json['boundsMax'], vm.Vector2(640, 360));
    backgroundColor = Color(json['backgroundColor'] as int? ?? 0xFF121316);
    notifyListeners();
  }

  @override
  Camera2DComponent clone() => Camera2DComponent()..fromJson(toJson());
}

/// Registers the 2D camera for scene deserialization.
void registerCamera2D() {
  ComponentRegistry.register('Camera 2D', (json) => Camera2DComponent()..fromJson(json));
}

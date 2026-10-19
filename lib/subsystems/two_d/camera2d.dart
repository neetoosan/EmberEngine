import 'dart:math' as math;
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import 'camera_room.dart';

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

  /// 1 shows the design area at its size; 0.5 shows twice as much world
  /// (zoomed out), 2 shows half (zoomed in).
  double zoom;

  /// Darkens the edges of the view (0 = off, 1 = strong), for focus and mood.
  double vignette;

  /// Darkness over the world (0 = none, 1 = pitch black) that Light 2D
  /// components cut through: dungeons, night, caves.
  double darkness;
  Color darknessColor;

  /// With several follow targets ("Sol, Lume"), zoom between [minZoom] and
  /// [maxZoom] so all of them stay in view with [fitPadding] world pixels
  /// to spare: a shared screen for local co-op.
  bool fitTargets;
  double minZoom;
  double maxZoom;
  double fitPadding;

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
    this.zoom = 1,
    this.vignette = 0,
    this.darkness = 0,
    this.darknessColor = const Color(0xFF05060C),
    this.fitTargets = false,
    this.minZoom = 0.6,
    this.maxZoom = 1,
    this.fitPadding = 120,
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

  double get _zoom => zoom <= 0.01 ? 0.01 : zoom;

  /// World area the camera shows (design size divided by [zoom]).
  double get viewWidth => designWidth / _zoom;
  double get viewHeight => designHeight / _zoom;

  /// How this camera maps onto a window of [screen] size.
  CameraView2D viewFor(Size screen) {
    final hasDesign = designWidth > 0 && designHeight > 0;
    final fit = hasDesign ? math.min(screen.width / designWidth, screen.height / designHeight) : 1.0;
    final w = hasDesign ? designWidth * fit : screen.width;
    final h = hasDesign ? designHeight * fit : screen.height;
    return CameraView2D(
      viewport: Rect.fromCenter(center: Offset(screen.width / 2, screen.height / 2), width: w, height: h),
      zoom: fit * _zoom,
      center: position + _shakeOffset,
    );
  }

  // --- Screen shake ---

  double _shakeAmount = 0;
  double _shakeTime = 0;
  double _shakeDuration = 0;
  vm.Vector2 _shakeOffset = vm.Vector2.zero();
  final math.Random _rng = math.Random();

  /// Shakes the view by up to [amount] world pixels, fading out over [seconds].
  void shake(double amount, double seconds) {
    final remaining = _shakeTime < _shakeDuration ? _shakeAmount * (1 - _shakeTime / _shakeDuration) : 0.0;
    if (amount < remaining) return; // a stronger shake is still running
    _shakeAmount = amount;
    _shakeDuration = math.max(0.01, seconds);
    _shakeTime = 0;
  }

  // --- Screen flash ---

  Color _flashColor = const Color(0x00000000);
  double _flashTime = 0;
  double _flashDuration = 0;

  /// Fills the view with [color], fading out over [seconds] (hits, bombs, lightning).
  void flash(Color color, double seconds) {
    _flashColor = color;
    _flashDuration = math.max(0.01, seconds);
    _flashTime = 0;
  }

  /// The flash colour right now (transparent when there is none).
  Color get flashColor {
    if (_flashTime >= _flashDuration) return const Color(0x00000000);
    final left = 1 - _flashTime / _flashDuration;
    return _flashColor.withValues(alpha: _flashColor.a * left * left);
  }

  void _updateShake(double dt) {
    if (_flashTime < _flashDuration) _flashTime += dt;
    if (_shakeTime >= _shakeDuration) {
      _shakeOffset = vm.Vector2.zero();
      return;
    }
    _shakeTime += dt;
    final strength = _shakeAmount * (1 - (_shakeTime / _shakeDuration).clamp(0.0, 1.0));
    _shakeOffset = vm.Vector2((_rng.nextDouble() * 2 - 1) * strength, (_rng.nextDouble() * 2 - 1) * strength);
  }

  @override
  void onStart() => snapToTarget();

  @override
  void onUpdate(double dt) {
    _updateShake(dt);
    final t = entity?.getComponent<Transform2DComponent>();
    final target = _targetPosition();
    if (t == null) return;
    var p = t.position.clone();
    final k = smoothing <= 0 ? 1.0 : 1.0 - math.pow(smoothing.clamp(0.0, 0.999), dt * 60).toDouble();
    final fit = _fitZoom();
    if (fit != null) zoom += (fit - zoom) * k;
    if (target != null) {
      var desired = p.clone();
      final d = target - p;
      if (d.x.abs() > deadZone.x) desired.x = target.x - deadZone.x * d.x.sign;
      if (d.y.abs() > deadZone.y) desired.y = target.y - deadZone.y * d.y.sign;
      // Inside a Camera Room the view stays in the room (and glides to the next one)
      final scene = entity?.scene;
      final room = scene == null ? null : CameraRoom2DComponent.at(scene, Offset(target.x, target.y));
      if (room != null) {
        desired = _clampTo(desired, room.rect);
        if (!identical(room, _room)) {
          _room = room;
          final roomEntity = room.entity;
          if (roomEntity != null) {
            scene!.findEntityByName(targetNames.first)?.notifyScripts((s) => s.onMessage('onRoomEnter', [roomEntity]));
          }
        }
      }
      // Frame-rate independent exponential smoothing
      p += (desired - p) * k;
    }
    t.position = _clamp(p);
  }

  CameraRoom2DComponent? _room;

  /// The Camera Room the follow target is in (null if none).
  CameraRoom2DComponent? get room => _room;

  vm.Vector2 _clampTo(vm.Vector2 p, Rect r) {
    final halfW = viewWidth / 2, halfH = viewHeight / 2;
    double axis(double v, double lo, double hi) => hi < lo ? (lo + hi) / 2 : v.clamp(lo, hi);
    return vm.Vector2(axis(p.x, r.left + halfW, r.right - halfW), axis(p.y, r.top + halfH, r.bottom - halfH));
  }

  /// Jumps straight to the follow target (used when a level starts).
  void snapToTarget() {
    final t = entity?.getComponent<Transform2DComponent>();
    final target = _targetPosition();
    if (t == null || target == null) return;
    final fit = _fitZoom();
    if (fit != null) zoom = fit;
    final scene = entity?.scene;
    final room = scene == null ? null : CameraRoom2DComponent.at(scene, Offset(target.x, target.y));
    t.position = _clamp(room == null ? target : _clampTo(target, room.rect));
  }

  /// The names in [followTarget] ("Hero", or "Sol, Lume" for several).
  List<String> get targetNames => [for (final n in followTarget.split(',')) if (n.trim().isNotEmpty) n.trim()];

  /// Positions of the follow targets (only the enabled ones when there are several).
  List<vm.Vector2> _targets() {
    final scene = entity?.scene;
    if (scene == null) return const [];
    final names = targetNames;
    if (names.length == 1) {
      final p = scene.findEntityByName(names.first)?.getComponent<Transform2DComponent>()?.worldPosition;
      return p == null ? const [] : [p];
    }
    return [
      for (final n in names)
        if (scene.findEntityByName(n) case final e? when e.enabled)
          if (e.getComponent<Transform2DComponent>() case final t?) t.worldPosition,
    ];
  }

  /// The middle of the box around every target.
  vm.Vector2? _targetPosition() {
    final ps = _targets();
    if (ps.isEmpty) return null;
    if (ps.length == 1) return ps.first;
    final box = _box(ps);
    return vm.Vector2(box.center.dx, box.center.dy);
  }

  static Rect _box(List<vm.Vector2> ps) {
    var r = Rect.fromLTWH(ps.first.x, ps.first.y, 0, 0);
    for (final p in ps.skip(1)) {
      r = r.expandToInclude(Rect.fromLTWH(p.x, p.y, 0, 0));
    }
    return r;
  }

  /// The zoom that fits every target ([fitTargets]), or null when off.
  double? _fitZoom() {
    if (!fitTargets || designWidth <= 0 || designHeight <= 0) return null;
    final ps = _targets();
    if (ps.isEmpty) return null;
    final box = _box(ps);
    final lo = math.min(minZoom, maxZoom), hi = math.max(minZoom, maxZoom);
    final want = math.min(designWidth / (box.width + 2 * fitPadding), designHeight / (box.height + 2 * fitPadding));
    return want.clamp(lo, hi).toDouble();
  }

  /// The largest area the camera can show around its centre (at [minZoom]
  /// when fitting targets), less [margin]. Keeping players inside it means
  /// nobody walks off a shared screen.
  Rect reach({double margin = 0}) {
    final z = fitTargets ? math.max(0.01, math.min(minZoom, maxZoom)) : _zoom;
    final c = position;
    return Rect.fromCenter(center: Offset(c.x, c.y), width: math.max(0, designWidth / z - 2 * margin), height: math.max(0, designHeight / z - 2 * margin));
  }

  /// [p] moved inside [reach] (and the bounds, if set).
  vm.Vector2 keepInReach(vm.Vector2 p, {double margin = 0}) {
    var r = reach(margin: margin);
    if (boundsEnabled) {
      r = r.intersect(Rect.fromLTRB(boundsMin.x + margin, boundsMin.y + margin, boundsMax.x - margin, boundsMax.y - margin));
    }
    if (r.width < 0 || r.height < 0) return p;
    return vm.Vector2(p.x.clamp(r.left, r.right).toDouble(), p.y.clamp(r.top, r.bottom).toDouble());
  }

  vm.Vector2 _clamp(vm.Vector2 p) {
    if (!boundsEnabled) return p;
    final halfW = viewWidth / 2;
    final halfH = viewHeight / 2;
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
        _num('zoom', 'Zoom', () => zoom, (v) => zoom = v.clamp(0.05, 20).toDouble(), step: 0.05, min: 0.05, max: 20),
        _num('vignette', 'Vignette', () => vignette, (v) => vignette = v.clamp(0, 1).toDouble(), step: 0.05, min: 0, max: 1),
        _num('darkness', 'Darkness', () => darkness, (v) => darkness = v.clamp(0, 1).toDouble(), step: 0.05, min: 0, max: 1),
        InspectableProperty<Color>(
          name: 'darknessColor',
          label: 'Darkness Color',
          type: InspectableType.color,
          getter: () => darknessColor,
          setter: (v) {
            darknessColor = v;
            notifyListeners();
          },
        ),
        InspectableProperty<String>(
          name: 'followTarget',
          label: 'Follow Entity',
          type: InspectableType.string,
          getter: () => followTarget,
          setter: (v) {
            followTarget = v;
            notifyListeners();
          },
          tooltip: 'Name of the entity to follow (empty = fixed camera); several, comma-separated, for a shared screen',
        ),
        InspectableProperty<bool>(
          name: 'fitTargets',
          label: 'Zoom To Fit Targets',
          type: InspectableType.boolean,
          getter: () => fitTargets,
          setter: (v) {
            fitTargets = v;
            notifyListeners();
          },
          tooltip: 'Zoom out (down to Min Zoom) so every follow target stays in view',
        ),
        _num('minZoom', 'Min Zoom', () => minZoom, (v) => minZoom = v.clamp(0.05, 20).toDouble(), step: 0.05, min: 0.05, max: 20),
        _num('maxZoom', 'Max Zoom', () => maxZoom, (v) => maxZoom = v.clamp(0.05, 20).toDouble(), step: 0.05, min: 0.05, max: 20),
        _num('fitPadding', 'Fit Padding', () => fitPadding, (v) => fitPadding = v, min: 0),
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
        if (zoom != 1) 'zoom': zoom,
        if (vignette != 0) 'vignette': vignette,
        if (darkness != 0) 'darkness': darkness,
        if (darkness != 0) 'darknessColor': darknessColor.toARGB32(),
        if (fitTargets) ...{'fitTargets': true, 'minZoom': minZoom, 'maxZoom': maxZoom, 'fitPadding': fitPadding},
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
    zoom = (json['zoom'] as num?)?.toDouble() ?? 1;
    vignette = (json['vignette'] as num?)?.toDouble() ?? 0;
    darkness = (json['darkness'] as num?)?.toDouble() ?? 0;
    darknessColor = Color(json['darknessColor'] as int? ?? 0xFF05060C);
    fitTargets = json['fitTargets'] as bool? ?? false;
    minZoom = (json['minZoom'] as num?)?.toDouble() ?? 0.6;
    maxZoom = (json['maxZoom'] as num?)?.toDouble() ?? 1;
    fitPadding = (json['fitPadding'] as num?)?.toDouble() ?? 120;
    notifyListeners();
  }

  @override
  Camera2DComponent clone() => Camera2DComponent()..fromJson(toJson());
}

/// Registers the 2D camera for scene deserialization.
void registerCamera2D() {
  ComponentRegistry.register('Camera 2D', (json) => Camera2DComponent()..fromJson(json));
}

import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/transform2d.dart';
import 'line2d.dart';

/// Moves an entity along a path drawn with a Line 2D (on the entity named
/// [path]): tower-defense enemies, patrols, rails, moving platforms.
/// When it reaches the end it stops (or starts over with [loop]) and sends
/// `onPathEnd()` to its scripts. Scripts can slow it (`follower.slow(0.5, 2)`)
/// and read how far along it is (`follower.progress`, 0 .. 1).
class PathFollower2DComponent extends EmberComponent {
  String path;
  double speed;
  bool loop;

  /// Turn to face the way it is going (art drawn facing right).
  bool rotate;

  /// Pixels travelled along the path.
  double distance = 0;
  bool done = false;

  double _slowFactor = 1;
  double _slowTime = 0;

  List<vm.Vector2> _points = const [];
  List<double> _lengths = const []; // length up to each point
  int _pointsHash = 0;

  PathFollower2DComponent({this.path = 'Path', this.speed = 60, this.loop = false, this.rotate = false});

  /// Total length of the path in pixels (0 if there is none).
  double get length => _lengths.isEmpty ? 0 : _lengths.last;

  /// 0 at the start, 1 at the end.
  double get progress => length <= 0 ? 0 : (distance / length).clamp(0.0, 1.0);

  double get remaining => math.max(0, length - distance);

  /// Speed after slowing.
  double get currentSpeed => speed * (_slowTime > 0 ? _slowFactor : 1);

  /// Slows to [factor] of its speed for [seconds] (the strongest slow wins).
  void slow(double factor, double seconds) {
    final f = factor.clamp(0.0, 1.0);
    if (_slowTime <= 0 || f <= _slowFactor) {
      _slowFactor = f;
      _slowTime = math.max(_slowTime, seconds);
    } else {
      _slowTime = math.max(_slowTime, seconds * 0.5);
    }
  }

  bool get slowed => _slowTime > 0 && _slowFactor < 1;

  bool _refresh() {
    final scene = entity?.scene;
    final line = scene?.findEntityByName(path)?.getComponent<Line2DComponent>();
    final pts = line?.resolvedPoints() ?? const <vm.Vector2>[];
    final hash = Object.hashAll([for (final p in pts) ...[p.x, p.y]]);
    if (hash != _pointsHash || pts.length != _points.length) {
      _pointsHash = hash;
      _points = [for (final p in pts) p.clone()];
      final lengths = <double>[];
      var total = 0.0;
      for (var i = 0; i < _points.length; i++) {
        if (i > 0) total += _points[i].distanceTo(_points[i - 1]);
        lengths.add(total);
      }
      _lengths = lengths;
    }
    return _points.length >= 2;
  }

  /// The point [d] pixels along the path, and the direction there (radians).
  (vm.Vector2, double) pointAt(double d) {
    if (_points.length < 2) return (_points.isEmpty ? vm.Vector2.zero() : _points.first.clone(), 0);
    final at = d.clamp(0.0, length);
    var i = 1;
    while (i < _lengths.length - 1 && _lengths[i] < at) {
      i++;
    }
    final a = _points[i - 1], b = _points[i];
    final seg = _lengths[i] - _lengths[i - 1];
    final t = seg <= 0 ? 0.0 : (at - _lengths[i - 1]) / seg;
    return (a + (b - a) * t, math.atan2(b.y - a.y, b.x - a.x));
  }

  @override
  void onStart() {
    if (_refresh()) _place();
  }

  @override
  void onUpdate(double dt) {
    if (_slowTime > 0) _slowTime -= dt;
    if (done || !_refresh()) return;
    distance += currentSpeed * dt;
    if (distance >= length) {
      if (loop && length > 0) {
        distance %= length;
      } else {
        distance = length;
        done = true;
        _place();
        entity?.notifyScripts((s) => s.onMessage('onPathEnd', const []));
        return;
      }
    }
    _place();
  }

  void _place() {
    final t = entity?.getComponent<Transform2DComponent>();
    if (t == null) return;
    final (p, angle) = pointAt(distance);
    t.position = p;
    if (rotate) t.rotation = angle;
  }

  @override
  String get displayName => 'Path Follower 2D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'path',
          label: 'Path Entity',
          type: InspectableType.string,
          getter: () => path,
          setter: (v) {
            path = v;
            notifyListeners();
          },
          tooltip: 'Name of the entity whose Line 2D points form the path',
        ),
        InspectableProperty<double>(
          name: 'speed',
          label: 'Speed',
          type: InspectableType.number,
          getter: () => speed,
          setter: (v) {
            speed = v;
            notifyListeners();
          },
          min: 0,
          step: 5,
          tooltip: 'Pixels per second',
        ),
        InspectableProperty<bool>(
          name: 'loop',
          label: 'Loop',
          type: InspectableType.boolean,
          getter: () => loop,
          setter: (v) {
            loop = v;
            notifyListeners();
          },
        ),
        InspectableProperty<bool>(
          name: 'rotate',
          label: 'Face Direction',
          type: InspectableType.boolean,
          getter: () => rotate,
          setter: (v) {
            rotate = v;
            notifyListeners();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {'path': path, 'speed': speed, 'loop': loop, 'rotate': rotate};

  @override
  void fromJson(Map<String, dynamic> json) {
    path = json['path'] as String? ?? 'Path';
    speed = (json['speed'] as num?)?.toDouble() ?? 60;
    loop = json['loop'] as bool? ?? false;
    rotate = json['rotate'] as bool? ?? false;
    notifyListeners();
  }

  @override
  PathFollower2DComponent clone() => PathFollower2DComponent()..fromJson(toJson());
}

void registerPathFollower() {
  ComponentRegistry.register('Path Follower 2D', (json) => PathFollower2DComponent()..fromJson(json));
}

import 'dart:math' as math;

/// Easing curves for [EmberTween].
class Ease {
  static double linear(double t) => t;
  static double inQuad(double t) => t * t;
  static double outQuad(double t) => 1 - (1 - t) * (1 - t);
  static double inOutQuad(double t) => t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
  static double outBack(double t) {
    const c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
  }
}

class _Tween {
  final double duration;
  final void Function(double t) onUpdate;
  final double Function(double) ease;
  final void Function()? onComplete;
  final Object? owner;
  double elapsed = 0;
  double delay;
  _Tween(this.duration, this.onUpdate, this.ease, this.onComplete, this.owner, this.delay);
}

/// Time-based animations for anything (UI fades, pop-ups, camera shakes,
/// flashing). Runs on real time, so it keeps working while gameplay is paused
/// (`EmberEngine.timeScale = 0`). Cleared when the game stops or the scene changes.
///
/// ```dart
/// EmberTween.run(0.3, (t) => text.fontSize = 20 + 10 * t, ease: Ease.outBack);
/// ```
class EmberTween {
  static final List<_Tween> _active = [];

  static int get activeCount => _active.length;

  /// Calls [onUpdate] with progress 0..1 (eased) over [duration] seconds.
  /// Tweens with the same non-null [owner] replace each other.
  static void run(
    double duration,
    void Function(double t) onUpdate, {
    double Function(double) ease = Ease.linear,
    void Function()? onComplete,
    Object? owner,
    double delay = 0,
  }) {
    if (owner != null) _active.removeWhere((t) => identical(t.owner, owner));
    _active.add(_Tween(duration <= 0 ? 0.0001 : duration, onUpdate, ease, onComplete, owner, delay));
  }

  /// Runs [action] after [seconds].
  static void delay(double seconds, void Function() action) => run(0.0001, (_) {}, delay: seconds, onComplete: action);

  static void cancel(Object owner) => _active.removeWhere((t) => identical(t.owner, owner));

  static void clear() => _active.clear();

  /// Advances every tween (called by the engine each frame with real time).
  static void update(double dt) {
    if (_active.isEmpty) return;
    for (final t in List<_Tween>.from(_active)) {
      if (t.delay > 0) {
        t.delay -= dt;
        continue;
      }
      t.elapsed += dt;
      final p = (t.elapsed / t.duration).clamp(0.0, 1.0);
      t.onUpdate(t.ease(p));
      if (p >= 1) {
        _active.remove(t);
        t.onComplete?.call();
      }
    }
  }
}

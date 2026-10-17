import 'mouse_lock.dart';

/// Platforms without mouse capture: the pointer stays free.
MouseLockBackend createMouseLockBackend() => _NoMouseLock();

class _NoMouseLock implements MouseLockBackend {
  @override
  bool get supported => false;
  @override
  bool get locked => false;
  @override
  void lock() {}
  @override
  void unlock() {}
  @override
  (double, double) takeDelta() => (0.0, 0.0);
}

import 'mouse_lock_stub.dart'
    if (dart.library.js_interop) 'mouse_lock_web.dart'
    if (dart.library.ffi) 'mouse_lock_windows.dart';

/// What a platform provides for [MouseLock].
abstract class MouseLockBackend {
  bool get supported;
  bool get locked;
  void lock();
  void unlock();

  /// Mouse movement (logical pixels) since the last call, while locked.
  (double, double) takeDelta();
}

/// Mouse capture for first-person games: hides the pointer, keeps it inside
/// the game, and reports raw movement so you can keep turning without
/// hitting the edge of the screen.
///
/// Games ask for it with [wanted] (the FPS Player Controller and
/// `Input.lockMouse()` do); the viewport then captures the mouse on the next
/// click, as browsers require. Escape or switching windows releases it.
/// Windows and web; elsewhere the mouse simply stays free.
class MouseLock {
  MouseLock._();

  static final MouseLockBackend _backend = createMouseLockBackend();

  /// Test hook: replaces the platform backend.
  static MouseLockBackend? backendOverride;

  static MouseLockBackend get _b => backendOverride ?? _backend;

  /// The running game wants the mouse captured (on the next click in the game view).
  static bool wanted = false;

  static bool get supported => _b.supported;
  static bool get locked => _b.supported && _b.locked;

  static void lock() {
    if (_b.supported && !_b.locked) _b.lock();
  }

  static void unlock() {
    if (_b.supported && _b.locked) _b.unlock();
  }

  /// Movement since the last call while locked; (0, 0) otherwise.
  static (double, double) takeDelta() => locked ? _b.takeDelta() : (0.0, 0.0);

  /// Releases the mouse and forgets the request (the game stopped).
  static void reset() {
    wanted = false;
    unlock();
  }
}

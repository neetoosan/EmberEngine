import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'mouse_lock.dart';

/// Browsers: the Pointer Lock API. Movement comes from `mousemove` events
/// (`movementX/Y`), because the pointer position stops changing while locked.
MouseLockBackend createMouseLockBackend() => _WebMouseLock();

class _WebMouseLock implements MouseLockBackend {
  double _dx = 0, _dy = 0;
  bool _listening = false;

  void _listen() {
    if (_listening) return;
    _listening = true;
    web.document.addEventListener(
      'mousemove',
      ((web.MouseEvent e) {
        if (!locked) return;
        _dx += e.movementX;
        _dy += e.movementY;
      }).toJS,
    );
  }

  @override
  bool get supported => true;

  @override
  bool get locked => web.document.pointerLockElement != null;

  @override
  void lock() {
    _listen();
    _dx = _dy = 0;
    final target = web.document.querySelector('flutter-view') ?? web.document.body;
    try {
      target?.requestPointerLock().toDart.catchError((_) => null);
    } catch (_) {
      // Not allowed right now (no user gesture): the next click tries again
    }
  }

  @override
  void unlock() {
    try {
      web.document.exitPointerLock();
    } catch (_) {}
  }

  @override
  (double, double) takeDelta() {
    final d = (_dx, _dy);
    _dx = _dy = 0;
    return d;
  }
}

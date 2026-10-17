import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'mouse_lock.dart';

/// Desktop: on Windows the cursor is kept in the game window and moved back
/// to its centre every frame; the distance it travelled is the movement.
/// (Flutter hides the cursor through the viewport's mouse cursor.)
MouseLockBackend createMouseLockBackend() => Platform.isWindows ? _WindowsMouseLock() : _NoLock();

class _NoLock implements MouseLockBackend {
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

final class _Rect extends Struct {
  @Int32()
  external int left, top, right, bottom;
}

final class _Point extends Struct {
  @Int32()
  external int x, y;
}

class _WindowsMouseLock implements MouseLockBackend {
  late final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  late final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  late final _getForegroundWindow = _user32.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
  late final _getWindowThreadProcessId =
      _user32.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
  late final _getCurrentProcessId = _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');
  late final _getClientRect = _user32.lookupFunction<Int32 Function(IntPtr, Pointer<_Rect>), int Function(int, Pointer<_Rect>)>('GetClientRect');
  late final _clientToScreen = _user32.lookupFunction<Int32 Function(IntPtr, Pointer<_Point>), int Function(int, Pointer<_Point>)>('ClientToScreen');
  late final _clipCursor = _user32.lookupFunction<Int32 Function(Pointer<_Rect>), int Function(Pointer<_Rect>)>('ClipCursor');
  late final _getCursorPos = _user32.lookupFunction<Int32 Function(Pointer<_Point>), int Function(Pointer<_Point>)>('GetCursorPos');
  late final _setCursorPos = _user32.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('SetCursorPos');
  late final _getDpiForWindow = _user32.lookupFunction<Uint32 Function(IntPtr), int Function(int)>('GetDpiForWindow');

  int _hwnd = 0;
  int _cx = 0, _cy = 0;

  @override
  bool get supported => true;

  @override
  bool get locked => _hwnd != 0;

  /// Our window, if it is the one in front.
  int _ourForegroundWindow() {
    final hwnd = _getForegroundWindow();
    if (hwnd == 0) return 0;
    final pid = calloc<Uint32>();
    try {
      _getWindowThreadProcessId(hwnd, pid);
      return pid.value == _getCurrentProcessId() ? hwnd : 0;
    } finally {
      calloc.free(pid);
    }
  }

  /// Clips the cursor to the window's client area and remembers its centre.
  bool _clip(int hwnd) {
    final rect = calloc<_Rect>();
    final pt = calloc<_Point>();
    try {
      if (_getClientRect(hwnd, rect) == 0) return false;
      pt.ref
        ..x = 0
        ..y = 0;
      _clientToScreen(hwnd, pt);
      final w = rect.ref.right, h = rect.ref.bottom;
      if (w <= 0 || h <= 0) return false;
      rect.ref
        ..left = pt.ref.x
        ..top = pt.ref.y
        ..right = pt.ref.x + w
        ..bottom = pt.ref.y + h;
      _clipCursor(rect);
      _cx = pt.ref.x + w ~/ 2;
      _cy = pt.ref.y + h ~/ 2;
      return true;
    } finally {
      calloc.free(rect);
      calloc.free(pt);
    }
  }

  @override
  void lock() {
    final hwnd = _ourForegroundWindow();
    if (hwnd == 0 || !_clip(hwnd)) return;
    _hwnd = hwnd;
    _setCursorPos(_cx, _cy);
  }

  @override
  void unlock() {
    if (_hwnd == 0) return;
    _hwnd = 0;
    _clipCursor(nullptr);
  }

  @override
  (double, double) takeDelta() {
    final hwnd = _hwnd;
    if (hwnd == 0) return (0.0, 0.0);
    // Switched to another window (Alt+Tab): let the mouse go
    if (_ourForegroundWindow() != hwnd || !_clip(hwnd)) {
      unlock();
      return (0.0, 0.0);
    }
    final pt = calloc<_Point>();
    try {
      _getCursorPos(pt);
      final dx = pt.ref.x - _cx, dy = pt.ref.y - _cy;
      if (dx != 0 || dy != 0) _setCursorPos(_cx, _cy);
      // Physical to logical pixels, like Flutter's pointer deltas
      final dpi = _getDpiForWindow(hwnd);
      final scale = dpi > 0 ? dpi / 96.0 : 1.0;
      return (dx / scale, dy / scale);
    } finally {
      calloc.free(pt);
    }
  }
}

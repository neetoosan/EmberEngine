import 'package:flutter/foundation.dart';

/// Tile painting state shared by the Tile Palette and the 2D viewport.
///
/// While [enabled], left-drag in the 2D viewport paints [tileId] into the
/// selected (or first) tilemap, and right-drag erases.
class TileBrush extends ChangeNotifier {
  static final TileBrush instance = TileBrush._();
  TileBrush._();

  bool _enabled = false;
  int _tileId = 1;

  bool get enabled => _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
  }

  int get tileId => _tileId;
  set tileId(int value) {
    if (value == _tileId) return;
    _tileId = value < 0 ? 0 : value;
    notifyListeners();
  }
}

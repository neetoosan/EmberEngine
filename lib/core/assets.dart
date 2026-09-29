import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Loads and caches game assets (currently images) by their project-relative
/// path, e.g. `assets/sprites/bird.png`.
///
/// Lookup order:
///  1. `<root>/<path>` — the open project's folder in the editor, or the
///     exported game's folder in the player;
///  2. the engine's own bundled assets (built-in template art).
class EmberAssets extends ChangeNotifier {
  static final EmberAssets instance = EmberAssets._();
  EmberAssets._();

  /// Folder that project-relative paths resolve against.
  String? _root;
  String? get root => _root;
  set root(String? value) {
    if (value == _root) return;
    _root = value;
    clear();
  }

  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};
  final Set<String> _missing = {};

  /// The decoded image for [path] if it is loaded. Otherwise starts loading it
  /// in the background (listeners are notified when it arrives) and returns null.
  ui.Image? image(String path) {
    if (path.isEmpty) return null;
    final img = _images[path];
    if (img == null && !_missing.contains(path) && !_loading.contains(path)) {
      load(path);
    }
    return img;
  }

  /// True once [path] was looked up and does not exist anywhere.
  bool isMissing(String path) => _missing.contains(path);

  /// Loads and decodes [path]; returns null if it does not exist or is not an image.
  Future<ui.Image?> load(String path) async {
    final cached = _images[path];
    if (cached != null) return cached;
    _loading.add(path);
    try {
      final bytes = await readBytes(path);
      if (bytes == null) {
        _missing.add(path);
        return null;
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _images[path] = frame.image;
      notifyListeners();
      return frame.image;
    } catch (e) {
      _missing.add(path);
      debugPrint('Ember: could not load image "$path": $e');
      return null;
    } finally {
      _loading.remove(path);
    }
  }

  /// Raw bytes of an asset: project/game folder first, then the engine bundle.
  Future<Uint8List?> readBytes(String path) async {
    final file = resolveFile(path);
    if (file != null && await file.exists()) return file.readAsBytes();
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// The on-disk location of [path] under [root] (it may not exist yet).
  File? resolveFile(String path) {
    final r = _root;
    if (r == null || kIsWeb) return null;
    final sep = Platform.pathSeparator;
    return File('$r$sep${path.replaceAll('/', sep)}');
  }

  /// Forgets all cached images (e.g. when switching projects).
  void clear() {
    _images.clear();
    _missing.clear();
    notifyListeners();
  }

  /// Makes a changed or newly imported file load again.
  void invalidate(String path) {
    _images.remove(path);
    _missing.remove(path);
    notifyListeners();
  }
}

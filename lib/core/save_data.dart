import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Small persistent key/value store for game progress (best score, unlocked
/// levels, settings). Values are kept in memory and written to
/// `<app support>/EmberSaves/<game>.json` in the background.
///
/// ```dart
/// final best = SaveData.instance.getInt('best');
/// SaveData.instance.setInt('best', score);
/// ```
class SaveData {
  static final SaveData instance = SaveData._();
  SaveData._();

  final Map<String, Object?> _values = {};
  File? _file;
  Future<void> _pendingWrite = Future.value();

  /// Loads the save file for [gameName]. Until this completes (or if storage
  /// is unavailable, e.g. in tests or on the web) values live in memory only.
  Future<void> open(String gameName) async {
    _values.clear();
    _file = null;
    if (kIsWeb) return;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = await Directory('${base.path}${Platform.pathSeparator}EmberSaves').create(recursive: true);
      final safe = gameName.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '').trim();
      final file = File('${dir.path}${Platform.pathSeparator}${safe.isEmpty ? 'game' : safe}.json');
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) _values.addAll(decoded);
      }
      _file = file;
    } catch (_) {
      // Storage unavailable: keep working in memory.
    }
  }

  int getInt(String key, {int defaultValue = 0}) => (_values[key] as num?)?.toInt() ?? defaultValue;
  double getDouble(String key, {double defaultValue = 0}) => (_values[key] as num?)?.toDouble() ?? defaultValue;
  bool getBool(String key, {bool defaultValue = false}) => _values[key] as bool? ?? defaultValue;
  String getString(String key, {String defaultValue = ''}) => _values[key] as String? ?? defaultValue;

  void setInt(String key, int value) => _set(key, value);
  void setDouble(String key, double value) => _set(key, value);
  void setBool(String key, bool value) => _set(key, value);
  void setString(String key, String value) => _set(key, value);

  void _set(String key, Object value) {
    _values[key] = value;
    final file = _file;
    if (file == null) return;
    final snapshot = jsonEncode(_values);
    _pendingWrite = _pendingWrite
        .then((_) => file.writeAsString(snapshot, flush: true))
        .then((_) {}, onError: (Object _) {});
  }

  /// Completes when all pending writes have reached disk.
  Future<void> flush() => _pendingWrite;
}

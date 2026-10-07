import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  SharedPreferences? _prefs;
  String? _webKey;
  Future<void> _pendingWrite = Future.value();

  /// Loads the save file for [gameName]. Until this completes (or if storage
  /// is unavailable, e.g. in tests or on the web) values live in memory only.
  Future<void> open(String gameName) async {
    _values.clear();
    _file = null;
    _webKey = null;
    if (kIsWeb) {
      // Browsers: the save lives in the site's local storage
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'EmberSaves/$gameName';
        final stored = prefs.getString(key);
        if (stored != null) {
          final decoded = jsonDecode(stored);
          if (decoded is Map<String, dynamic>) _values.addAll(decoded);
        }
        _prefs = prefs;
        _webKey = key;
      } catch (_) {
        // Storage unavailable (private mode): keep working in memory.
      }
      return;
    }
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

  /// A JSON object stored under [key] (e.g. a whole save game), or null.
  Map<String, dynamic>? getMap(String key) {
    final v = _values[key];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  void setMap(String key, Map<String, dynamic> value) => _set(key, jsonDecode(jsonEncode(value)) as Object);

  bool has(String key) => _values.containsKey(key);

  void remove(String key) {
    if (_values.remove(key) == null) return;
    _write();
  }

  void setInt(String key, int value) => _set(key, value);
  void setDouble(String key, double value) => _set(key, value);
  void setBool(String key, bool value) => _set(key, value);
  void setString(String key, String value) => _set(key, value);

  void _set(String key, Object value) {
    _values[key] = value;
    _write();
  }

  void _write() {
    final prefs = _prefs, webKey = _webKey;
    if (prefs != null && webKey != null) {
      final snapshot = jsonEncode(_values);
      _pendingWrite = _pendingWrite.then((_) => prefs.setString(webKey, snapshot)).then((_) {}, onError: (Object _) {});
      return;
    }
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

/// Numbered save-game slots on top of [SaveData] (title-screen "Continue",
/// save points). Each slot holds any JSON map plus a `savedAt` timestamp.
///
/// ```dart
/// SaveSlots.save(1, {'level': 'Dungeon', 'hp': 5, 'inventory': inv.toJson()});
/// final game = SaveSlots.load(1);
/// ```
class SaveSlots {
  static String _key(int slot) => 'slot:$slot';

  static void save(int slot, Map<String, dynamic> data) =>
      SaveData.instance.setMap(_key(slot), {...data, 'savedAt': DateTime.now().toIso8601String()});

  static Map<String, dynamic>? load(int slot) => SaveData.instance.getMap(_key(slot));

  static bool exists(int slot) => SaveData.instance.has(_key(slot));

  static void delete(int slot) => SaveData.instance.remove(_key(slot));

  /// When the slot was last saved, or null if empty.
  static DateTime? savedAt(int slot) => DateTime.tryParse(load(slot)?['savedAt'] as String? ?? '');

  /// The most recently saved of slots 1..[count], or null if all are empty.
  static int? latest({int count = 3}) {
    int? best;
    DateTime? bestTime;
    for (var s = 1; s <= count; s++) {
      final t = savedAt(s);
      if (t != null && (bestTime == null || t.isAfter(bestTime))) {
        best = s;
        bestTime = t;
      }
    }
    return best;
  }
}

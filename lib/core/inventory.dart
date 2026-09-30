import 'package:flutter/foundation.dart';

/// A bag of stackable items (potions, keys, loot) plus gold.
///
/// Items are identified by name. Lives outside scenes, so it survives level
/// changes; save it with [toJson] into a save slot.
///
/// ```dart
/// inventory.add('Potion');
/// if (inventory.take('Key')) openDoor();
/// ```
class Inventory extends ChangeNotifier {
  final Map<String, int> _items = {};
  int gold = 0;

  /// Items in the order they were first picked up.
  Map<String, int> get items => Map.unmodifiable(_items);

  int count(String item) => _items[item] ?? 0;
  bool has(String item, [int amount = 1]) => count(item) >= amount;

  void add(String item, [int amount = 1]) {
    if (amount <= 0) return;
    _items[item] = count(item) + amount;
    notifyListeners();
  }

  /// Removes [amount] of [item] if there are enough. Returns true on success.
  bool take(String item, [int amount = 1]) {
    if (!has(item, amount)) return false;
    final left = count(item) - amount;
    if (left <= 0) {
      _items.remove(item);
    } else {
      _items[item] = left;
    }
    notifyListeners();
    return true;
  }

  void addGold(int amount) {
    gold = (gold + amount).clamp(0, 1 << 30);
    notifyListeners();
  }

  /// Spends [amount] gold if affordable. Returns true on success.
  bool spend(int amount) {
    if (gold < amount) return false;
    gold -= amount;
    notifyListeners();
    return true;
  }

  void clear() {
    _items.clear();
    gold = 0;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {'gold': gold, 'items': Map<String, int>.from(_items)};

  void fromJson(Map<String, dynamic>? json) {
    _items.clear();
    gold = (json?['gold'] as num?)?.toInt() ?? 0;
    final items = json?['items'];
    if (items is Map) {
      for (final e in items.entries) {
        final n = (e.value as num?)?.toInt() ?? 0;
        if (n > 0) _items[e.key.toString()] = n;
      }
    }
    notifyListeners();
  }
}

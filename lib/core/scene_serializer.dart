import 'dart:convert';
import 'entity.dart';
import 'scene.dart';

/// Scene and Prefab Serialization pipeline for Ember Engine.
///
/// Encodes scene trees, entity hierarchies, and attached component states
/// into versioned, human-readable JSON (.scene format) or compact binary representation.
class SceneSerializer {
  static const String formatVersion = '1.0.0';

  /// Serializes an entire EmberScene into a formatted JSON string.
  static String serializeScene(EmberScene scene, {bool pretty = true}) {
    final map = {
      'format': 'EmberScene',
      'version': formatVersion,
      'name': scene.name,
      'createdAt': DateTime.now().toIso8601String(),
      'entities': scene.rootEntities.map((e) => e.toJson()).toList(),
    };

    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(map);
    }
    return jsonEncode(map);
  }

  /// Alias for serializeScene.
  static String saveSceneToJson(EmberScene scene, {bool pretty = true}) => serializeScene(scene, pretty: pretty);

  /// Deserializes a JSON string into a new EmberScene instance.
  static EmberScene deserializeScene(String jsonString) {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Invalid scene JSON payload');
    }
    return deserializeSceneFromMap(decoded);
  }

  /// Deserializes a Map directly into a new EmberScene instance.
  static EmberScene deserializeSceneFromMap(Map<String, dynamic> map) {
    final scene = EmberScene(
      name: map['name'] as String? ?? 'Untitled Scene',
    );

    final rawEntities = map['entities'] as List<dynamic>? ?? [];
    for (final rawEnt in rawEntities) {
      if (rawEnt is Map<String, dynamic>) {
        final entity = EmberEntity.fromJson(rawEnt);
        scene.addEntity(entity);
      }
    }

    return scene;
  }

  /// Alias for deserializeScene.
  static EmberScene loadSceneFromJson(String jsonString) => deserializeScene(jsonString);

  /// Serializes a single entity as a reusable Prefab template (.prefab format).
  static String serializePrefab(EmberEntity entity, {bool pretty = true}) {
    final map = {
      'format': 'EmberPrefab',
      'version': formatVersion,
      'entity': entity.toJson(),
    };

    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(map);
    }
    return jsonEncode(map);
  }

  /// Instantiates an entity from a Prefab JSON string.
  /// If [scene] is provided, adds the instantiated entity to the scene.
  static EmberEntity instantiatePrefab(String prefabJson, {EmberScene? scene}) {
    final dynamic decoded = jsonDecode(prefabJson);
    if (decoded is! Map<String, dynamic> || !decoded.containsKey('entity')) {
      throw FormatException('Invalid prefab JSON payload');
    }

    final entity = EmberEntity.fromJson(decoded['entity'] as Map<String, dynamic>, generateNewIds: true);
    scene?.addEntity(entity);
    return entity;
  }
}

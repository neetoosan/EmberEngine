import 'package:flutter/foundation.dart';
import 'component.dart';
import 'game_script.dart';
import 'scene.dart';

/// Callback for component registry deserialization.
typedef ComponentFactory = EmberComponent Function(Map<String, dynamic> json);

/// Registry for component serialization/deserialization.
class ComponentRegistry {
  static final Map<String, ComponentFactory> _factories = {};

  static void register(String typeName, ComponentFactory factory) {
    _factories[typeName] = factory;
  }

  static EmberComponent? create(String typeName, Map<String, dynamic> json) {
    final factory = _factories[typeName];
    if (factory == null) return null;
    return factory(json);
  }

  static bool has(String typeName) => _factories.containsKey(typeName);
}

/// An Entity in the Ember Engine Entity-Component-System (ECS) architecture.
///
/// An entity represents any game object or scene node (Player, Camera, Light, Mesh, 2D Sprite).
/// It owns a collection of [EmberComponent]s and participates in a parent-child scene graph hierarchy.
class EmberEntity with ChangeNotifier {
  final String id;
  String name;
  bool _enabled;
  int layer;
  final Set<String> tags;

  EmberEntity? _parent;
  EmberScene? _scene;
  final List<EmberEntity> _children = [];
  final List<EmberComponent> _components = [];

  static int _idCounter = 0;

  /// Increments whenever any entity's structure changes (parent, components,
  /// destruction, scene membership, draw order). Caches of "all entities" or
  /// "all components of type T" are valid while this number is unchanged.
  static int structureVersion = 0;

  EmberEntity({
    String? id,
    this.name = 'Entity',
    this._enabled = true,
    this.layer = 0,
    Set<String>? tags,
  })  : id = id ?? 'entity_${++_idCounter}_${DateTime.now().millisecondsSinceEpoch}',
        tags = tags ?? <String>{};

  /// Whether this entity and its components are enabled.
  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  /// The parent entity in the hierarchy, or null if root.
  EmberEntity? get parent => _parent;

  /// The scene this entity lives in (resolved through its root ancestor),
  /// or null if it has not been added to a scene.
  EmberScene? get scene => _parent?.scene ?? _scene;

  /// Called by [EmberScene] when this entity becomes (or stops being) a root.
  void bindScene(EmberScene? scene) => _scene = scene;

  /// The list of child entities.
  List<EmberEntity> get children => List.unmodifiable(_children);

  /// The list of attached components.
  List<EmberComponent> get components => List.unmodifiable(_components);

  // --- Hierarchy Management ---

  /// Sets the parent entity, maintaining hierarchy consistency.
  void setParent(EmberEntity? newParent) {
    if (_parent == newParent) return;
    structureVersion++;
    _parent?._children.remove(this);
    _parent = newParent;
    if (newParent != null && !newParent._children.contains(this)) {
      newParent._children.add(this);
    }
    notifyListeners();
  }

  /// Adds a child entity.
  void addChild(EmberEntity child) {
    child.setParent(this);
  }

  /// Removes a child entity.
  void removeChild(EmberEntity child) {
    if (_children.contains(child)) {
      child.setParent(null);
    }
  }

  /// Finds a child entity by name.
  EmberEntity? findChild(String name, {bool recursive = true}) {
    for (final child in _children) {
      if (child.name == name) return child;
      if (recursive) {
        final found = child.findChild(name, recursive: true);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Collects all descendants in a depth-first list.
  List<EmberEntity> getAllDescendants() {
    final list = <EmberEntity>[];
    for (final child in _children) {
      list.add(child);
      list.addAll(child.getAllDescendants());
    }
    return list;
  }

  // --- Component Management ---

  /// Adds a component to this entity.
  T addComponent<T extends EmberComponent>(T component) {
    structureVersion++;
    component.attach(this);
    _components.add(component);
    component.addListener(notifyListeners);
    notifyListeners();
    return component;
  }

  /// Gets the first component of type [T], or null if not found.
  T? getComponent<T extends EmberComponent>() {
    for (final c in _components) {
      if (c is T) return c;
    }
    return null;
  }

  /// Gets all components of type [T].
  List<T> getComponents<T extends EmberComponent>() {
    final result = <T>[];
    for (final c in _components) {
      if (c is T) result.add(c);
    }
    return result;
  }

  /// Checks if this entity has a component of type [T].
  bool hasComponent<T extends EmberComponent>() {
    return getComponent<T>() != null;
  }

  /// Removes a component instance or returns false if not present.
  bool removeComponent(EmberComponent component) {
    if (_components.remove(component)) {
      structureVersion++;
      component.removeListener(notifyListeners);
      component.detach();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Removes all components of type [T].
  void removeComponentsOfType<T extends EmberComponent>() {
    final toRemove = getComponents<T>();
    for (final c in toRemove) {
      removeComponent(c);
    }
  }

  // --- Lifecycle Dispatch ---

  /// Runs the awake phase for all components and children.
  void awake() {
    for (final component in _components) {
      component.internalAwake();
    }
    for (final child in _children) {
      child.awake();
    }
  }

  /// Runs the start phase for all enabled components and children.
  void start() {
    if (!_enabled) return;
    for (final component in _components) {
      component.internalStart();
    }
    for (final child in _children) {
      child.start();
    }
  }

  /// Runs the variable frame update. Iterates snapshots so scripts may add or
  /// remove components/children (or destroy this entity) during the update.
  void update(double dt) {
    if (!_enabled) return;
    for (final component in List<EmberComponent>.from(_components)) {
      if (component.enabled && identical(component.entity, this)) {
        component.onUpdate(dt);
      }
    }
    for (final child in List<EmberEntity>.from(_children)) {
      if (identical(child.parent, this)) child.update(dt);
    }
  }

  /// Runs the fixed timestep update (e.g. 60Hz physics).
  void fixedUpdate(double fixedDt) {
    if (!_enabled) return;
    for (final component in List<EmberComponent>.from(_components)) {
      if (component.enabled && identical(component.entity, this)) {
        component.onFixedUpdate(fixedDt);
      }
    }
    for (final child in List<EmberEntity>.from(_children)) {
      if (identical(child.parent, this)) child.fixedUpdate(fixedDt);
    }
  }

  /// Sends a message to every script on this entity (see [GameScript]).
  void notifyScripts(void Function(GameScript script) message) {
    for (final c in List<EmberComponent>.from(_components)) {
      if (c is ScriptComponent && c.enabled) {
        final s = c.scriptInstance;
        if (s != null) message(s);
      }
    }
  }

  /// Destroys this entity, its components, and all child entities.
  void destroy() {
    structureVersion++;
    for (final component in List<EmberComponent>.from(_components)) {
      component.removeListener(notifyListeners);
      component.detach();
    }
    _components.clear();

    for (final child in List<EmberEntity>.from(_children)) {
      child.destroy();
    }
    _children.clear();

    _parent?._children.remove(this);
    _parent = null;
    notifyListeners();
  }

  // --- Serialization ---

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'enabled': _enabled,
      'layer': layer,
      'tags': tags.toList(),
      'components': _components
          .map((c) => {
                'type': c.displayName,
                'data': c.toJson(),
              })
          .toList(),
      'children': _children.map((child) => child.toJson()).toList(),
    };
  }

  factory EmberEntity.fromJson(Map<String, dynamic> json, {bool generateNewIds = false}) {
    final entity = EmberEntity(
      id: generateNewIds ? null : json['id'] as String?,
      name: json['name'] as String? ?? 'Entity',
      enabled: json['enabled'] as bool? ?? true,
      layer: json['layer'] as int? ?? 0,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toSet(),
    );

    final rawComponents = json['components'] as List<dynamic>? ?? [];
    for (final rawComp in rawComponents) {
      final compMap = rawComp as Map<String, dynamic>;
      final type = compMap['type'] as String;
      final data = compMap['data'] as Map<String, dynamic>;
      final component = ComponentRegistry.create(type, data);
      if (component != null) {
        entity.addComponent(component);
      }
    }

    final rawChildren = json['children'] as List<dynamic>? ?? [];
    for (final rawChild in rawChildren) {
      final child = EmberEntity.fromJson(rawChild as Map<String, dynamic>, generateNewIds: generateNewIds);
      entity.addChild(child);
    }

    return entity;
  }

  /// Creates a deep clone of this entity.
  EmberEntity clone({String? newId}) {
    final copy = EmberEntity(
      id: newId,
      name: '$name (Copy)',
      enabled: _enabled,
      layer: layer,
      tags: Set<String>.from(tags),
    );

    for (final comp in _components) {
      copy.addComponent(comp.clone());
    }

    for (final child in _children) {
      copy.addChild(child.clone());
    }

    return copy;
  }
}

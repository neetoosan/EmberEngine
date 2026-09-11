import 'package:flutter/foundation.dart';
import 'entity.dart';
import 'inspectable.dart';

/// Base class for all components in the Ember Engine ECS architecture.
///
/// Follows Unity-inspired lifecycle contracts:
/// - [onAwake]: Called once when the component or entity is created.
/// - [onStart]: Called before the first frame update.
/// - [onUpdate]: Called every render frame with delta time in seconds.
/// - [onFixedUpdate]: Called at a fixed timestep for physics calculations.
/// - [onDestroy]: Called when the component or its owning entity is removed.
abstract class EmberComponent with ChangeNotifier {
  EmberEntity? _entity;
  bool _enabled = true;
  bool _hasStarted = false;
  bool _hasAwoken = false;

  /// The entity that owns this component.
  EmberEntity? get entity => _entity;

  /// Whether this component is currently active and executing updates.
  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (_enabled) {
      onEnable();
    } else {
      onDisable();
    }
    notifyListeners();
  }

  /// Internal attachment hook called when component is added to an entity.
  @mustCallSuper
  void attach(EmberEntity entity) {
    _entity = entity;
  }

  /// Internal detachment hook called when component is removed from an entity.
  @mustCallSuper
  void detach() {
    if (_enabled) {
      onDisable();
    }
    onDestroy();
    _entity = null;
    _hasStarted = false;
    _hasAwoken = false;
  }

  /// Lifecycle: Called once upon component creation.
  @protected
  void onAwake() {}

  /// Lifecycle: Called before the first frame update.
  @protected
  void onStart() {}

  /// Lifecycle: Called every variable render frame with delta time in seconds.
  void onUpdate(double dt) {}

  /// Lifecycle: Called at fixed physics intervals with fixed delta time in seconds.
  void onFixedUpdate(double fixedDt) {}

  /// Lifecycle: Called when component is enabled.
  @protected
  void onEnable() {}

  /// Lifecycle: Called when component is disabled.
  @protected
  void onDisable() {}

  /// Lifecycle: Called when component is being destroyed.
  @mustCallSuper
  void onDestroy() {}

  /// Internal dispatcher for awake phase.
  void internalAwake() {
    if (!_hasAwoken) {
      _hasAwoken = true;
      onAwake();
    }
  }

  /// Internal dispatcher for start phase.
  void internalStart() {
    if (!_hasStarted && _enabled) {
      _hasStarted = true;
      onStart();
    }
  }

  /// Unique display name for this component in the Inspector.
  String get displayName => runtimeType.toString();

  /// List of properties exposed for dynamic inspection and editing in the Inspector.
  List<InspectableProperty> get inspectableProperties => const [];

  /// Serializes component state to JSON.
  Map<String, dynamic> toJson();

  /// Deserializes component state from JSON.
  void fromJson(Map<String, dynamic> json);

  /// Clones this component with current property values.
  EmberComponent clone();
}

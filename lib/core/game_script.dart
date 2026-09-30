import 'component.dart';
import 'entity.dart';
import 'inspectable.dart';
import 'scene.dart';
import '../subsystems/two_d/flame_components.dart' show TileHit;

export '../subsystems/two_d/flame_components.dart' show TileHit, TileKind;

/// User-facing gameplay script contract, mirroring Unity's MonoBehaviour.
abstract class GameScript {
  EmberEntity? _entity;

  EmberEntity? get entity => _entity;

  T? getComponent<T extends EmberComponent>() => _entity?.getComponent<T>();

  /// The scene this script's entity lives in.
  EmberScene? get scene => _entity?.scene;

  /// Adds [newEntity] to this scene (it starts running immediately).
  EmberEntity spawn(EmberEntity newEntity) {
    scene?.addEntity(newEntity);
    return newEntity;
  }

  /// Removes [target] (default: this script's entity) at the end of the frame.
  void destroy([EmberEntity? target]) {
    final e = target ?? _entity;
    if (e != null) scene?.destroyLater(e);
  }

  /// First entity in the scene with this name, or null.
  EmberEntity? find(String name) => scene?.findEntityByName(name);

  void onAwake() {}
  void onStart() {}
  void onUpdate(double dt) {}
  void onFixedUpdate(double fixedDt) {}
  void onDestroy() {}

  /// This entity's hitbox started overlapping [other]'s, and at least one of
  /// the two is a trigger (non-solid). Needs a Hitbox 2D on both entities.
  void onTriggerEnter(EmberEntity other) {}

  /// The trigger overlap with [other] ended.
  void onTriggerExit(EmberEntity other) {}

  /// Two solid hitboxes started touching.
  void onCollisionEnter(EmberEntity other) {}

  /// Two solid hitboxes stopped touching.
  void onCollisionExit(EmberEntity other) {}

  /// This character (Character Controller 2D) hit [tile] with its head while
  /// jumping — e.g. to break a brick or open a "?" block.
  void onHeadBump(TileHit tile) {}

  /// This character is touching a [TileKind.hazard] tile (spikes, lava).
  void onTileTouch(TileHit tile) {}

  /// This entity's Health component took [amount] damage from [source].
  void onDamaged(double amount, EmberEntity? source) {}

  /// This entity's Health component reached zero.
  void onDeath(EmberEntity? killer) {}

  /// This entity (or a projectile it fired) killed [victim] — e.g. to award XP.
  void onKill(EmberEntity victim) {}

  /// A UI Button with this action was clicked (sent to every script in the scene).
  void onUIAction(String action) {}

  /// [by] (usually the player) interacted with this entity (e.g. pressed E next to it).
  void onInteract(EmberEntity by) {}
}

/// Factory signature for instantiating custom GameScripts by name.
typedef ScriptFactory = GameScript Function();

/// A script with variables that can be set per entity in the Inspector
/// (Ember Script's top-level `var speed = 120;`).
abstract class ConfigurableScript {
  /// Editable variables and their current values.
  Map<String, Object?> get exposedFields;

  /// Per-entity values set in the Inspector (saved with the scene).
  Map<String, Object?> get overrides;
  set overrides(Map<String, Object?> value);

  void setField(String name, Object? value);
}

/// Global registry for user-defined game scripts.
class ScriptRegistry {
  static final Map<String, ScriptFactory> _registry = {};

  /// Scripts provided at runtime (Ember Script files), tried after compiled ones.
  static GameScript? Function(String name)? fallback;
  static List<String> Function()? extraScripts;

  static void register(String scriptName, ScriptFactory factory) {
    _registry[scriptName] = factory;
  }

  static GameScript? instantiate(String scriptName) {
    final factory = _registry[scriptName];
    if (factory != null) return factory();
    return fallback?.call(scriptName);
  }

  /// Compiled (built into the engine) script names.
  static List<String> get builtInScripts => _registry.keys.toList();

  static List<String> get availableScripts => [...?extraScripts?.call(), ..._registry.keys];
}

/// Component that attaches and runs a [GameScript] on an entity.
class ScriptComponent extends EmberComponent {
  String _scriptName;
  GameScript? _scriptInstance;

  /// Inspector values for the script's variables (Ember Script `var`s).
  final Map<String, Object?> vars = {};

  ScriptComponent({
    this._scriptName = '',
    Map<String, Object?>? vars,
  }) {
    if (vars != null) this.vars.addAll(vars);
    _instantiateScript();
  }

  String get scriptName => _scriptName;
  set scriptName(String name) {
    if (_scriptName == name) return;
    _scriptInstance?.onDestroy();
    _scriptName = name;
    vars.clear();
    _instantiateScript();
    notifyListeners();
  }

  /// The running script. Resolved lazily, so scripts loaded after the scene
  /// (e.g. a project's Ember Scripts) still attach.
  GameScript? get scriptInstance {
    if (_scriptInstance == null && _scriptName.isNotEmpty) _instantiateScript();
    return _scriptInstance;
  }

  void _instantiateScript() {
    if (_scriptName.isNotEmpty) {
      _scriptInstance = ScriptRegistry.instantiate(_scriptName);
      final s = _scriptInstance;
      if (s is ConfigurableScript) (s as ConfigurableScript).overrides = vars;
      if (entity != null) {
        _scriptInstance?._entity = entity;
      }
    } else {
      _scriptInstance = null;
    }
  }

  @override
  void attach(EmberEntity entity) {
    super.attach(entity);
    _scriptInstance?._entity = entity;
  }

  @override
  void detach() {
    _scriptInstance?._entity = null;
    super.detach();
  }

  @override
  void onAwake() {
    scriptInstance?._entity = entity;
    _scriptInstance?.onAwake();
  }

  @override
  void onStart() {
    _scriptInstance?.onStart();
  }

  @override
  void onUpdate(double dt) {
    _scriptInstance?.onUpdate(dt);
  }

  @override
  void onFixedUpdate(double fixedDt) {
    _scriptInstance?.onFixedUpdate(fixedDt);
  }

  @override
  void onDestroy() {
    _scriptInstance?.onDestroy();
    super.onDestroy();
  }

  @override
  String get displayName => 'Script Component';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'scriptName',
          label: 'Script',
          type: InspectableType.options,
          getter: () => _scriptName,
          setter: (val) => scriptName = val,
          options: ScriptRegistry.availableScripts,
          tooltip: 'Built-in scripts, or your .ember scripts from the Script workspace',
        ),
        ..._fieldProperties(),
      ];

  /// One Inspector row per script variable (`var speed = 120;`).
  List<InspectableProperty> _fieldProperties() {
    final s = scriptInstance;
    if (s is! ConfigurableScript) return const [];
    final config = s as ConfigurableScript;
    final out = <InspectableProperty>[];
    for (final e in config.exposedFields.entries) {
      final name = e.key;
      final label = _labelFor(name);
      void set(Object? v) {
        config.setField(name, v);
        notifyListeners();
      }

      final value = e.value;
      if (value is bool) {
        out.add(InspectableProperty<bool>(
            name: 'var:$name', label: label, type: InspectableType.boolean, getter: () => config.exposedFields[name] == true, setter: set));
      } else if (value is num) {
        out.add(InspectableProperty<double>(
          name: 'var:$name',
          label: label,
          type: InspectableType.number,
          getter: () => (config.exposedFields[name] as num? ?? 0).toDouble(),
          setter: set,
          step: value is int ? 1 : 0.1,
        ));
      } else {
        out.add(InspectableProperty<String>(
            name: 'var:$name', label: label, type: InspectableType.string, getter: () => '${config.exposedFields[name] ?? ''}', setter: set));
      }
    }
    return out;
  }

  /// `moveSpeed` -> `Move Speed`.
  static String _labelFor(String name) {
    final spaced = name.replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => ' ${m[1]}').replaceAll('_', ' ').trim();
    return spaced.isEmpty ? name : spaced[0].toUpperCase() + spaced.substring(1);
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'scriptName': _scriptName,
      if (vars.isNotEmpty) 'vars': Map<String, Object?>.of(vars),
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    _scriptName = json['scriptName'] as String? ?? '';
    vars
      ..clear()
      ..addAll((json['vars'] as Map?)?.cast<String, Object?>() ?? const {});
    _instantiateScript();
    notifyListeners();
  }

  @override
  ScriptComponent clone() {
    return ScriptComponent(scriptName: _scriptName, vars: Map.of(vars));
  }
}

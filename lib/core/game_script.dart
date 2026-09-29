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
}

/// Factory signature for instantiating custom GameScripts by name.
typedef ScriptFactory = GameScript Function();

/// Global registry for user-defined game scripts.
class ScriptRegistry {
  static final Map<String, ScriptFactory> _registry = {};

  static void register(String scriptName, ScriptFactory factory) {
    _registry[scriptName] = factory;
  }

  static GameScript? instantiate(String scriptName) {
    final factory = _registry[scriptName];
    if (factory == null) return null;
    return factory();
  }

  static List<String> get availableScripts => _registry.keys.toList();
}

/// Component that attaches and runs a [GameScript] on an entity.
class ScriptComponent extends EmberComponent {
  String _scriptName;
  GameScript? _scriptInstance;

  ScriptComponent({
    this._scriptName = '',
  }) {
    _instantiateScript();
  }

  String get scriptName => _scriptName;
  set scriptName(String name) {
    if (_scriptName == name) return;
    _scriptInstance?.onDestroy();
    _scriptName = name;
    _instantiateScript();
    notifyListeners();
  }

  GameScript? get scriptInstance => _scriptInstance;

  void _instantiateScript() {
    if (_scriptName.isNotEmpty) {
      _scriptInstance = ScriptRegistry.instantiate(_scriptName);
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
          tooltip: 'Select registered GameScript to run',
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'scriptName': _scriptName,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    _scriptName = json['scriptName'] as String? ?? '';
    _instantiateScript();
    notifyListeners();
  }

  @override
  ScriptComponent clone() {
    return ScriptComponent(scriptName: _scriptName);
  }
}

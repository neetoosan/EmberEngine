import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'event_bus.dart';
import 'input.dart';
import 'scene.dart';
import 'entity.dart';
import '../subsystems/audio/audio_system.dart';
import '../subsystems/physics/physics_world2d.dart';
import '../subsystems/physics/character_controller2d.dart';
import '../subsystems/physics/physics_world3d.dart';
import '../subsystems/three_d/camera3d.dart';

/// Performance & Power mode for battery / thermal management.
enum PowerMode {
  uncapped,
  performance60,
  batterySaver30,
}

/// Central controller and master loop for Ember Engine.
///
/// Coordinates scene lifecycle, play/pause/step simulations, metrics collection,
/// entity selection, physics world stepping, audio updates, and dimension mode switching.
class EmberEngine with ChangeNotifier {
  static final EmberEngine instance = EmberEngine._();
  EmberEngine._() {
    _init();
  }

  PlayState _playState = PlayState.stopped;
  EngineMode _mode = EngineMode.threeD;
  GizmoType _activeGizmo = GizmoType.translate;
  PowerMode _powerMode = PowerMode.performance60;

  late EmberScene _activeScene;
  Map<String, dynamic>? _savedSceneSnapshot;
  EmberEntity? _selectedEntity;

  // Performance metrics
  double _fps = 60.0;
  double _frameTimeMs = 16.6;
  int _frameCount = 0;
  double _fpsAccumulator = 0.0;

  // Fixed timestep physics accumulator
  final double fixedTimestep = 1.0 / 60.0; // 60Hz
  double _physicsAccumulator = 0.0;

  // Console logs
  final List<EngineLog> _logs = [];

  // Ticker for driving the game loop
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  void _init() {
    _activeScene = EmberScene.createDefault3DScene();
    _activeScene.addListener(_notifyUi);
    log('Ember Engine initialized in 3D Mode', severity: LogSeverity.info, source: 'Core');
  }

  // --- Getters ---

  PlayState get playState => _playState;
  EngineMode get mode => _mode;
  GizmoType get activeGizmo => _activeGizmo;
  PowerMode get powerMode => _powerMode;
  EmberScene get activeScene => _activeScene;
  EmberEntity? get selectedEntity => _selectedEntity;

  double get fps => _fps;
  double get frameTimeMs => _frameTimeMs;
  int get entityCount => _activeScene.allEntities.length;
  int get componentCount => _activeScene.allEntities.fold(0, (sum, e) => sum + e.components.length);
  List<EngineLog> get logs => List.unmodifiable(_logs);

  // --- Power & Battery Management ---

  void setPowerMode(PowerMode mode) {
    if (_powerMode == mode) return;
    _powerMode = mode;
    log('Power mode set to: ${mode.name}', source: 'Engine');
    notifyListeners();
  }

  // --- Engine Mode ---

  /// When true (a user project is open), switching 2D/3D only changes the
  /// viewport and never replaces the scene being edited with a starter scene.
  bool preserveSceneOnModeSwitch = false;

  void setMode(EngineMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    if (_playState == PlayState.stopped && !preserveSceneOnModeSwitch) {
      if (newMode == EngineMode.twoD) {
        loadScene(EmberScene.createDefault2DScene());
      } else {
        loadScene(EmberScene.createDefault3DScene());
      }
    }
    EmberEventBus.instance.emit(ModeChangedEvent(newMode));
    log('Switched to ${_mode == EngineMode.twoD ? "2D (Flame)" : "3D Native"} Mode', source: 'Engine');
    notifyListeners();
  }

  // --- Selection ---

  void selectEntity(EmberEntity? entity) {
    if (_selectedEntity == entity) return;
    _selectedEntity = entity;
    EmberEventBus.instance.emit(SelectionChangedEvent(entity));
    notifyListeners();
  }

  // --- Gizmo ---

  void setGizmo(GizmoType gizmo) {
    if (_activeGizmo == gizmo) return;
    _activeGizmo = gizmo;
    EmberEventBus.instance.emit(GizmoChangedEvent(gizmo));
    notifyListeners();
  }

  // --- Scene Management ---

  /// The scene as authored in the editor: while a simulation runs this is the
  /// snapshot taken at Play, so saving never captures mid-game state.
  EmberScene get editableScene {
    final snapshot = _savedSceneSnapshot;
    return snapshot != null ? EmberScene.fromJson(snapshot) : _activeScene;
  }

  void loadScene(EmberScene scene) {
    if (identical(scene, _activeScene)) return; // would otherwise destroy the scene being loaded
    _activeScene.removeListener(_notifyUi);
    _activeScene.destroy();
    _activeScene = scene;
    _selectedEntity = null;
    _activeScene.addListener(_notifyUi);
    notifyListeners();
  }

  // --- Simulation Controls ---

  void play() {
    if (_playState == PlayState.playing) return;

    if (_playState == PlayState.stopped) {
      // Save scene state for zero-loss restore upon Stop
      _savedSceneSnapshot = _activeScene.toJson();
      _runningSceneJson = _savedSceneSnapshot;
      Input.reset();
      _activeScene.awake();
      _activeScene.start();
      _activeScene.isRunning = true;
      _startTicker();
    }

    _playState = PlayState.playing;
    EmberEventBus.instance.emit(PlayStateChangedEvent(_playState));
    log('Scene started simulation', source: 'Runtime');
    notifyListeners();
  }

  void pause() {
    if (_playState != PlayState.playing) return;
    _playState = PlayState.paused;
    EmberEventBus.instance.emit(PlayStateChangedEvent(_playState));
    log('Scene simulation paused', source: 'Runtime');
    notifyListeners();
  }

  void step() {
    if (_playState == PlayState.stopped) {
      play();
      pause();
    }
    _simulate(fixedTimestep);
    tick(fixedTimestep);
    log('Stepped 1 frame (${(fixedTimestep * 1000).toStringAsFixed(1)}ms)', source: 'Runtime');
    notifyListeners();
  }

  void stop() {
    if (_playState == PlayState.stopped) return;

    _stopTicker();
    _playState = PlayState.stopped;
    _pendingSceneChange = null;
    _runningSceneJson = null;
    _activeScene.isRunning = false;
    AudioSystem.instance.stopAll();
    Input.reset();

    // Restore pre-simulation snapshot
    if (_savedSceneSnapshot != null) {
      loadScene(EmberScene.fromJson(_savedSceneSnapshot!));
      _savedSceneSnapshot = null;
    }

    EmberEventBus.instance.emit(PlayStateChangedEvent(_playState));
    log('Scene stopped and state restored', source: 'Runtime');
    notifyListeners();
  }

  // --- Ticker & Frame Loop ---

  void _startTicker() {
    _ticker ??= Ticker((elapsed) {
      if (_lastTick == Duration.zero) {
        _lastTick = elapsed;
        return;
      }
      final dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
      _lastTick = elapsed;

      // Throttle for battery saver mode (30 FPS max)
      if (_powerMode == PowerMode.batterySaver30 && dt < (1.0 / 32.0)) {
        return;
      }

      // Clamp delta to avoid spiral of death on lag spikes
      final clampedDt = dt.clamp(0.001, 0.1);
      tick(clampedDt);
    });
    _lastTick = Duration.zero;
    _ticker!.start();
  }

  void _stopTicker() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _lastTick = Duration.zero;
  }

  /// Master frame update.
  void tick(double dt) {
    // 1. Calculate FPS & timing metrics
    _frameTimeMs = dt * 1000.0;
    _fpsAccumulator += dt;
    _frameCount++;
    if (_fpsAccumulator >= 0.5) {
      _fps = _frameCount / _fpsAccumulator;
      _frameCount = 0;
      _fpsAccumulator = 0.0;
    }

    // 2-3. Physics + scripts
    if (_playState == PlayState.playing) {
      _simulate(dt);
    }

    // 4. Update audio system (ducking, spatial audio, voice cleanup)
    final listener = _findAudioListener();
    if (listener != null) {
      AudioSystem.instance.updateListenerFromEntity(listener);
    }
    AudioSystem.instance.update(dt);

    // 5. Flush frame input triggers
    Input.endFrame();

    // 6. Viewports redraw every frame; panels only get a throttled refresh.
    frame.value++;
    _uiThrottle += dt;
    if (_uiDirty && _uiThrottle >= uiRefreshInterval) _flushUi();
  }

  // --- Change notifications ---
  //
  // `EmberEngine` listeners (panels: hierarchy, inspector, top bar, console)
  // rebuild on every notification. While a game runs, scene changes happen
  // every frame, so they are coalesced to [uiRefreshInterval]. Viewports that
  // must redraw every frame listen to [frame] instead.

  /// Increments once per engine tick. Listen to this to redraw every frame.
  final ValueNotifier<int> frame = ValueNotifier<int>(0);

  /// Minimum seconds between panel refreshes while the game is running.
  double uiRefreshInterval = 0.2;

  bool _uiDirty = false;
  double _uiThrottle = 0;

  /// Notifies panels now while editing, or at most every [uiRefreshInterval]
  /// seconds while the game runs.
  void _notifyUi() {
    if (_playState == PlayState.stopped) {
      notifyListeners();
    } else {
      _uiDirty = true;
    }
  }

  void _flushUi() {
    _uiDirty = false;
    _uiThrottle = 0;
    notifyListeners();
  }

  /// One simulation frame: fixed-step physics, then the variable update.
  void _simulate(double dt) {
    _physicsAccumulator += dt;
    while (_physicsAccumulator >= fixedTimestep) {
      if (_mode == EngineMode.threeD) {
        PhysicsWorld3D.step(_activeScene, fixedTimestep);
      } else {
        PhysicsWorld2D.step(_activeScene, fixedTimestep);
      }
      _activeScene.fixedUpdate(fixedTimestep);
      _activeScene.flushDestroyed();
      _physicsAccumulator -= fixedTimestep;
    }
    _activeScene.update(dt);
    _activeScene.flushDestroyed();

    // Scene changes requested by scripts run here, never mid-iteration.
    final change = _pendingSceneChange;
    _pendingSceneChange = null;
    change?.call();
  }

  void Function()? _pendingSceneChange;

  /// Restarts the running game from the state it had when Play was pressed
  /// (e.g. after "Game Over"). Safe to call from scripts; applied after the frame.
  void restartScene() {
    final json = _runningSceneJson ?? _savedSceneSnapshot;
    if (json == null) return;
    _pendingSceneChange = () => _startRunningScene(EmberScene.fromJson(json));
  }

  /// Switches the running game to [scene] (e.g. the next level). Safe to call
  /// from scripts; applied after the frame. Stop still restores the scene the
  /// editor had open when Play was pressed.
  void switchScene(EmberScene scene) {
    final json = scene.toJson();
    _pendingSceneChange = () => _startRunningScene(scene, json: json);
  }

  /// The game's scenes by name (provided by the editor or the player), used
  /// by [loadLevel]. Values are scene JSON as saved in the project.
  Map<String, Map<String, dynamic>> Function()? sceneLibrary;

  /// Names of the scenes [loadLevel] can switch to.
  List<String> get levelNames => sceneLibrary?.call().keys.toList() ?? const [];

  /// Switches the running game to the project scene called [name]
  /// (e.g. `loadLevel('Level 2')`). Returns false if there is no such scene.
  bool loadLevel(String name) {
    final json = sceneLibrary?.call()[name];
    if (json == null) {
      log('No scene named "$name" to load', severity: LogSeverity.warning, source: 'Runtime');
      return false;
    }
    _pendingSceneChange = () => _startRunningScene(EmberScene.fromJson(json), json: json);
    return true;
  }

  /// JSON of the scene currently being played, for [restartScene].
  Map<String, dynamic>? _runningSceneJson;

  void _startRunningScene(EmberScene scene, {Map<String, dynamic>? json}) {
    if (json != null) _runningSceneJson = json;
    loadScene(scene);
    // Keep keys the player is still holding (e.g. Right after a respawn);
    // only drop this frame's one-shot presses.
    Input.endFrame();
    _physicsAccumulator = 0.0;
    _activeScene.awake();
    _activeScene.start();
    _activeScene.isRunning = true;
    log('Scene "${scene.name}" (re)started', source: 'Runtime');
  }

  /// The main camera in 3D, or the 2D player character, so sound pans relative to what the player sees.
  EmberEntity? _findAudioListener() {
    for (final cam in _activeScene.componentsOf<CameraComponent>()) {
      if (cam.isMainCamera && (cam.entity?.enabled ?? false)) return cam.entity;
    }
    EmberEntity? firstCharacter;
    for (final cc in _activeScene.componentsOf<CharacterController2DComponent>()) {
      final e = cc.entity;
      if (e == null || !e.enabled) continue;
      if (e.tags.contains('player')) return e;
      firstCharacter ??= e;
    }
    return firstCharacter;
  }

  // --- Logging ---

  void log(String message, {LogSeverity severity = LogSeverity.info, String? source}) {
    final entry = EngineLog(
      message: message,
      severity: severity,
      source: source,
    );
    _logs.add(entry);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    EmberEventBus.instance.emit(LogEvent(entry));
    _notifyUi();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}

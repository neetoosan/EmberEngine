import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'event_bus.dart';
import 'scene.dart';
import 'entity.dart';

/// Central controller and master loop for Ember Engine.
///
/// Coordinates scene lifecycle, play/pause/step simulations, metrics collection,
/// entity selection, and dimension mode switching (2D vs 3D).
class EmberEngine with ChangeNotifier {
  static final EmberEngine instance = EmberEngine._();
  EmberEngine._() {
    _init();
  }

  PlayState _playState = PlayState.stopped;
  EngineMode _mode = EngineMode.threeD;
  GizmoType _activeGizmo = GizmoType.translate;

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
    log('Ember Engine initialized in 3D Mode', severity: LogSeverity.info, source: 'Core');
  }

  // --- Getters ---

  PlayState get playState => _playState;
  EngineMode get mode => _mode;
  GizmoType get activeGizmo => _activeGizmo;
  EmberScene get activeScene => _activeScene;
  EmberEntity? get selectedEntity => _selectedEntity;

  double get fps => _fps;
  double get frameTimeMs => _frameTimeMs;
  int get entityCount => _activeScene.allEntities.length;
  int get componentCount => _activeScene.allEntities.fold(0, (sum, e) => sum + e.components.length);
  List<EngineLog> get logs => List.unmodifiable(_logs);

  // --- Engine Mode ---

  void setMode(EngineMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    if (_playState == PlayState.stopped) {
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

  void loadScene(EmberScene scene) {
    _activeScene.removeListener(notifyListeners);
    _activeScene.destroy();
    _activeScene = scene;
    _selectedEntity = null;
    _activeScene.addListener(notifyListeners);
    notifyListeners();
  }

  // --- Simulation Controls ---

  void play() {
    if (_playState == PlayState.playing) return;

    if (_playState == PlayState.stopped) {
      // Save scene state for zero-loss restore upon Stop
      _savedSceneSnapshot = _activeScene.toJson();
      _activeScene.awake();
      _activeScene.start();
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
    tick(fixedTimestep);
    log('Stepped 1 frame (${(fixedTimestep * 1000).toStringAsFixed(1)}ms)', source: 'Runtime');
    notifyListeners();
  }

  void stop() {
    if (_playState == PlayState.stopped) return;

    _stopTicker();
    _playState = PlayState.stopped;

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

    // 2. Fixed physics updates
    if (_playState == PlayState.playing) {
      _physicsAccumulator += dt;
      while (_physicsAccumulator >= fixedTimestep) {
        _activeScene.fixedUpdate(fixedTimestep);
        _physicsAccumulator -= fixedTimestep;
      }

      // 3. Variable frame update
      _activeScene.update(dt);
    }

    notifyListeners();
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
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}

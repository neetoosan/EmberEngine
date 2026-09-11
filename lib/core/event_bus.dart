import 'dart:async';
import 'entity.dart';
import 'component.dart';

/// Engine execution states.
enum PlayState {
  stopped,
  playing,
  paused,
}

/// Viewport dimension mode.
enum EngineMode {
  twoD,
  threeD,
}

/// Active 3D Gizmo tool.
enum GizmoType {
  translate,
  rotate,
  scale,
  none,
}

/// Log severity levels.
enum LogSeverity {
  info,
  warning,
  error,
}

/// Engine log message.
class EngineLog {
  final DateTime timestamp;
  final String message;
  final LogSeverity severity;
  final String? source;

  EngineLog({
    required this.message,
    this.severity = LogSeverity.info,
    this.source,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = (timestamp.millisecond ~/ 100).toString();
    return '$h:$m:$s.$ms';
  }
}

/// Event bus for decoupled editor and runtime communication in Ember Engine.
class EmberEventBus {
  static final EmberEventBus instance = EmberEventBus._();
  EmberEventBus._();

  final _controller = StreamController<dynamic>.broadcast();

  Stream<T> on<T>() {
    return _controller.stream.where((event) => event is T).cast<T>();
  }

  void emit(dynamic event) {
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}

// --- Specific Event Types ---

class SelectionChangedEvent {
  final EmberEntity? selectedEntity;
  SelectionChangedEvent(this.selectedEntity);
}

class ModeChangedEvent {
  final EngineMode mode;
  ModeChangedEvent(this.mode);
}

class PlayStateChangedEvent {
  final PlayState state;
  PlayStateChangedEvent(this.state);
}

class GizmoChangedEvent {
  final GizmoType gizmo;
  GizmoChangedEvent(this.gizmo);
}

class EntityCreatedEvent {
  final EmberEntity entity;
  EntityCreatedEvent(this.entity);
}

class EntityRemovedEvent {
  final EmberEntity entity;
  EntityRemovedEvent(this.entity);
}

class ComponentAddedEvent {
  final EmberEntity entity;
  final EmberComponent component;
  ComponentAddedEvent(this.entity, this.component);
}

class LogEvent {
  final EngineLog log;
  LogEvent(this.log);
}

import 'dart:ui' show Rect;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/game_script.dart';
import '../../core/inspectable.dart';
import '../../core/input.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import '../../core/tween.dart';
import '../ui/dialogue.dart';
import '../ui/ui_widgets.dart';
import 'flame_components.dart';

/// World rectangle of an entity: its Hitbox 2D if present, else its Transform 2D box.
Rect _bodyOf(EmberEntity e) {
  final t = e.getComponent<Transform2DComponent>();
  if (t == null) return Rect.zero;
  final min = t.worldPosition - t.anchorOffset;
  final h = e.getComponent<FlameHitbox2DComponent>();
  if (h != null) return Rect.fromLTWH(min.x + h.offset.x, min.y + h.offset.y, h.size.x, h.size.y);
  return Rect.fromLTWH(min.x, min.y, t.size.x * t.scale.x, t.size.y * t.scale.y);
}

EmberEntity? _player(EmberScene scene) {
  for (final e in scene.allEntities) {
    if (e.enabled && e.tags.contains('player')) return e;
  }
  return null;
}

/// A doorway, stair or cave mouth that takes the player (tag `player`) to
/// another scene. The player appears at the entity named [spawnAt] there.
///
/// Walk-in doors trigger on touch; with [requireInteract] the player must
/// press Interact (E) while touching it. A door the player starts on only
/// arms after they step off it, so arriving on a door never bounces back.
class DoorComponent extends EmberComponent {
  String targetLevel;
  String spawnAt;
  bool requireInteract;

  bool _armed = false;
  bool _started = false;

  DoorComponent({this.targetLevel = '', this.spawnAt = '', this.requireInteract = false});

  @override
  void onUpdate(double dt) {
    final self = entity;
    final scene = self?.scene;
    if (self == null || scene == null || targetLevel.isEmpty) return;
    final player = _player(scene);
    if (player == null) return;
    final touching = _bodyOf(self).overlaps(_bodyOf(player));
    if (!_started) {
      _started = true;
      _armed = !touching;
      return;
    }
    if (!touching) {
      _armed = true;
      return;
    }
    if (!_armed) return;
    if (requireInteract && !Input.isActionJustPressed(EngineAction.interact)) return;
    _armed = false;
    Doors.travel(targetLevel, spawnAt: spawnAt.isEmpty ? null : spawnAt);
  }

  @override
  String get displayName => 'Door';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'targetLevel',
          label: 'Go To Scene',
          type: InspectableType.options,
          getter: () => targetLevel,
          setter: (v) {
            targetLevel = v;
            notifyListeners();
          },
          options: EmberEngine.instance.levelNames,
        ),
        InspectableProperty<String>(
          name: 'spawnAt',
          label: 'Arrive At (entity name)',
          type: InspectableType.string,
          getter: () => spawnAt,
          setter: (v) {
            spawnAt = v;
            notifyListeners();
          },
        ),
        InspectableProperty<bool>(
          name: 'requireInteract',
          label: 'Needs Interact Key',
          type: InspectableType.boolean,
          getter: () => requireInteract,
          setter: (v) {
            requireInteract = v;
            notifyListeners();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {'targetLevel': targetLevel, 'spawnAt': spawnAt, 'requireInteract': requireInteract};

  @override
  void fromJson(Map<String, dynamic> json) {
    targetLevel = json['targetLevel'] as String? ?? '';
    spawnAt = json['spawnAt'] as String? ?? '';
    requireInteract = json['requireInteract'] as bool? ?? false;
    notifyListeners();
  }

  @override
  DoorComponent clone() => DoorComponent(targetLevel: targetLevel, spawnAt: spawnAt, requireInteract: requireInteract);
}

/// Scene travel with a short fade to black.
class Doors {
  static bool _travelling = false;

  /// Fades out, then loads [level] with the player placed at [spawnAt].
  /// The engine fades back in when the new scene starts.
  static void travel(String level, {String? spawnAt, double fade = 0.25}) {
    if (_travelling) return;
    _travelling = true;
    EmberTween.run(fade, (t) => UIRenderer.fade = t, onComplete: () {
      _travelling = false;
      if (!EmberEngine.instance.loadLevel(level, spawnAt: spawnAt)) UIRenderer.fade = 0;
    });
  }

  /// Cancels a pending travel (engine start/stop).
  static void reset() => _travelling = false;

  /// Moves [player] so its centre sits on the entity named [marker].
  /// Returns false if there is no such entity.
  static bool placeAt(EmberScene scene, EmberEntity player, String marker) {
    final target = scene.findByName(marker);
    final t = player.getComponent<Transform2DComponent>();
    if (target == null || t == null || identical(target, player)) return false;
    final to = _bodyOf(target).center;
    final from = _bodyOf(player).center;
    t.position = vm.Vector2(t.position.x + to.dx - from.dx, t.position.y + to.dy - from.dy);
    return true;
  }

  /// Places the scene's player at [EmberEngine.spawnPoint], if set.
  static void placePlayerAtSpawn(EmberScene scene) {
    final spawn = EmberEngine.instance.spawnPoint;
    final player = _player(scene);
    if (spawn != null && player != null) placeAt(scene, player, spawn);
  }
}

/// Talk-to / use helper for the player.
class Interaction {
  /// Interacts with the nearest entity within [range] pixels of [player]'s
  /// body that has a Dialogue component or a script: opens its dialogue and
  /// sends it `onInteract(player)`. Returns the entity, or null.
  static EmberEntity? interact(EmberScene scene, EmberEntity player, {double range = 24}) {
    if (DialogueSystem.instance.isOpen) return null;
    final reach = _bodyOf(player).inflate(range);
    EmberEntity? best;
    var bestDist = double.infinity;
    for (final e in scene.allEntities) {
      if (identical(e, player) || !e.enabled) continue;
      if (!e.hasComponent<DialogueComponent>() && !e.hasComponent<ScriptComponent>()) continue;
      final body = _bodyOf(e);
      if (!body.overlaps(reach)) continue;
      final d = (body.center - reach.center).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        best = e;
      }
    }
    if (best == null) return null;
    best.getComponent<DialogueComponent>()?.talk();
    best.notifyScripts((s) => s.onInteract(player));
    return best;
  }
}

void registerDoorComponent() {
  ComponentRegistry.register('Door', (json) => DoorComponent()..fromJson(json));
}

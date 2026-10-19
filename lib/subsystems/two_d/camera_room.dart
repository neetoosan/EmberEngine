import 'dart:ui';
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';

/// Marks an area (this entity's Transform 2D box) as a room for the Camera 2D:
/// while the camera's follow target is inside it, the camera stays inside the
/// room, and it glides over when the target walks into another room. The
/// target's scripts get `onRoomEnter(room)` (metroidvanias, Zelda-like screens).
class CameraRoom2DComponent extends EmberComponent {
  /// Shown on maps and passed to scripts (empty: the entity's name).
  String title;

  CameraRoom2DComponent({this.title = ''});

  String get displayTitle => title.isEmpty ? (entity?.name ?? '') : title;

  /// The room's area in the world.
  Rect get rect {
    final t = entity?.getComponent<Transform2DComponent>();
    if (t == null) return Rect.zero;
    final p = t.worldPosition - t.anchorOffset;
    return Rect.fromLTWH(p.x, p.y, t.size.x * t.worldScale.x, t.size.y * t.worldScale.y);
  }

  /// The room containing [point] in [scene] (the smallest if they overlap), or null.
  static CameraRoom2DComponent? at(EmberScene scene, Offset point) {
    CameraRoom2DComponent? best;
    var bestArea = double.infinity;
    for (final r in scene.componentsOf<CameraRoom2DComponent>()) {
      if (!r.enabled || !(r.entity?.enabled ?? false)) continue;
      final rect = r.rect;
      if (rect.contains(point) && rect.width * rect.height < bestArea) {
        best = r;
        bestArea = rect.width * rect.height;
      }
    }
    return best;
  }

  @override
  String get displayName => 'Camera Room 2D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'title',
          label: 'Room Name',
          type: InspectableType.string,
          getter: () => title,
          setter: (v) {
            title = v;
            notifyListeners();
          },
          tooltip: 'Shown to scripts in onRoomEnter (empty: the entity name)',
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {if (title.isNotEmpty) 'title': title};

  @override
  void fromJson(Map<String, dynamic> json) {
    title = json['title'] as String? ?? '';
    notifyListeners();
  }

  @override
  CameraRoom2DComponent clone() => CameraRoom2DComponent(title: title);
}

void registerCameraRoom() {
  ComponentRegistry.register('Camera Room 2D', (json) => CameraRoom2DComponent()..fromJson(json));
}

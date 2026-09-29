import 'package:vector_math/vector_math_64.dart';
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/transform3d.dart';
import '../../core/transform2d.dart';
import 'audio_system.dart';

/// Audio Source Component attached to an Entity.
///
/// Can emit spatialized 3D sounds, background music loops, or UI chimes.
class AudioSourceComponent extends EmberComponent {
  String clip;
  AudioCategory category;
  double volume;
  double pitch;
  bool playOnAwake;
  bool looping;
  bool is3D;
  double minDistance;
  double maxDistance;

  AudioVoice? _activeVoice;

  AudioSourceComponent({
    this.clip = 'laser',
    this.category = AudioCategory.sfx,
    this.volume = 1.0,
    this.pitch = 1.0,
    this.playOnAwake = false,
    this.looping = false,
    this.is3D = true,
    this.minDistance = 1.0,
    this.maxDistance = 30.0,
  });

  @override
  void onStart() {
    if (playOnAwake) {
      play();
    }
  }

  @override
  void onUpdate(double dt) {
    // Keep 3D position synchronized with entity transform
    if (_activeVoice != null && is3D) {
      final t3d = entity?.getComponent<Transform3DComponent>();
      if (t3d != null) {
        _activeVoice!.position = t3d.worldPosition;
      } else {
        final t2d = entity?.getComponent<Transform2DComponent>();
        if (t2d != null) {
          _activeVoice!.position = Vector3(t2d.worldPosition.x, t2d.worldPosition.y, 0.0);
        }
      }
    }
  }

  @override
  void onDestroy() {
    stop();
    super.onDestroy();
  }

  /// Triggers playback of this audio source.
  void play({String? overrideClip}) {
    final soundToPlay = overrideClip ?? clip;
    Vector3? pos;

    if (is3D) {
      final t3d = entity?.getComponent<Transform3DComponent>();
      if (t3d != null) {
        pos = t3d.worldPosition;
      } else {
        final t2d = entity?.getComponent<Transform2DComponent>();
        if (t2d != null) {
          pos = Vector3(t2d.worldPosition.x, t2d.worldPosition.y, 0.0);
        }
      }
    }

    _activeVoice = AudioSystem.instance.play(
      clip: soundToPlay,
      category: category,
      volume: volume,
      pitch: pitch,
      looping: looping,
      is3D: is3D,
      position: pos,
      minDistance: minDistance,
      maxDistance: maxDistance,
    );
  }

  /// Returns true if this audio source currently has an actively playing voice.
  bool get isPlaying => _activeVoice != null && _activeVoice!.isPlaying;

  /// Stops playback.
  void stop() {
    if (_activeVoice != null) {
      AudioSystem.instance.stop(_activeVoice!);
      _activeVoice = null;
    }
  }

  @override
  String get displayName => 'Audio Source';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'clip',
          label: 'Sound Clip',
          type: InspectableType.string,
          getter: () => clip,
          setter: (val) {
            clip = val;
            notifyListeners();
          },
          tooltip: 'Clip name or procedural sound effect (laser, jump, coin, explosion, hit)',
        ),
        InspectableProperty<AudioCategory>(
          name: 'category',
          label: 'Audio Category',
          type: InspectableType.options,
          getter: () => category,
          setter: (val) {
            category = val;
            notifyListeners();
          },
          options: AudioCategory.values.map((c) => c.name).toList(),
        ),
        InspectableProperty<double>(
          name: 'volume',
          label: 'Volume',
          type: InspectableType.number,
          getter: () => volume,
          setter: (val) {
            volume = val.clamp(0.0, 1.0);
            _activeVoice?.volume = volume;
            notifyListeners();
          },
          min: 0.0,
          max: 1.0,
          step: 0.05,
        ),
        InspectableProperty<double>(
          name: 'pitch',
          label: 'Pitch',
          type: InspectableType.number,
          getter: () => pitch,
          setter: (val) {
            pitch = val.clamp(0.1, 3.0);
            _activeVoice?.pitch = pitch;
            notifyListeners();
          },
          min: 0.1,
          max: 3.0,
          step: 0.05,
        ),
        InspectableProperty<bool>(
          name: 'playOnAwake',
          label: 'Play on Start',
          type: InspectableType.boolean,
          getter: () => playOnAwake,
          setter: (val) {
            playOnAwake = val;
            notifyListeners();
          },
        ),
        InspectableProperty<bool>(
          name: 'looping',
          label: 'Loop Audio',
          type: InspectableType.boolean,
          getter: () => looping,
          setter: (val) {
            looping = val;
            _activeVoice?.isLooping = looping;
            notifyListeners();
          },
        ),
        InspectableProperty<bool>(
          name: 'is3D',
          label: '3D Spatialized',
          type: InspectableType.boolean,
          getter: () => is3D,
          setter: (val) {
            is3D = val;
            notifyListeners();
          },
        ),
        InspectableProperty<double>(
          name: 'maxDistance',
          label: 'Max 3D Distance',
          type: InspectableType.number,
          getter: () => maxDistance,
          setter: (val) {
            maxDistance = val;
            notifyListeners();
          },
          min: 1.0,
          max: 200.0,
          step: 5.0,
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'clip': clip,
      'category': category.name,
      'volume': volume,
      'pitch': pitch,
      'playOnAwake': playOnAwake,
      'looping': looping,
      'is3D': is3D,
      'minDistance': minDistance,
      'maxDistance': maxDistance,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    clip = json['clip'] as String? ?? 'laser';
    final catName = json['category'] as String? ?? 'sfx';
    category = AudioCategory.values.firstWhere(
      (c) => c.name == catName,
      orElse: () => AudioCategory.sfx,
    );
    volume = (json['volume'] as num?)?.toDouble() ?? 1.0;
    pitch = (json['pitch'] as num?)?.toDouble() ?? 1.0;
    playOnAwake = json['playOnAwake'] as bool? ?? false;
    looping = json['looping'] as bool? ?? false;
    is3D = json['is3D'] as bool? ?? true;
    minDistance = (json['minDistance'] as num?)?.toDouble() ?? 1.0;
    maxDistance = (json['maxDistance'] as num?)?.toDouble() ?? 30.0;
    notifyListeners();
  }

  @override
  AudioSourceComponent clone() {
    return AudioSourceComponent(
      clip: clip,
      category: category,
      volume: volume,
      pitch: pitch,
      playOnAwake: playOnAwake,
      looping: looping,
      is3D: is3D,
      minDistance: minDistance,
      maxDistance: maxDistance,
    );
  }
}

/// Registers AudioSourceComponent in the global ComponentRegistry.
void registerAudioComponents() {
  ComponentRegistry.register('Audio Source', (json) {
    final comp = AudioSourceComponent();
    comp.fromJson(json);
    return comp;
  });
}

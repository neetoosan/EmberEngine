import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/transform3d.dart';
import '../../core/transform2d.dart';

/// Audio categories following industry standard mix hierarchy.
enum AudioCategory {
  master,
  voice,
  playerSfx,
  sfx,
  music,
  ambient,
  ui,
}

/// Active playing audio voice instance.
class AudioVoice {
  final int id;
  final String clip;
  final AudioCategory category;
  double volume;
  double pitch;
  bool isLooping;
  bool is3D;
  Vector3 position;
  double minDistance;
  double maxDistance;
  double playbackTime = 0.0;
  double duration = 1.0;
  bool isPlaying = true;
  double duckFactor = 1.0;

  AudioVoice({
    required this.id,
    required this.clip,
    required this.category,
    this.volume = 1.0,
    this.pitch = 1.0,
    this.isLooping = false,
    this.is3D = false,
    Vector3? position,
    this.minDistance = 1.0,
    this.maxDistance = 30.0,
    this.duration = 1.0,
  }) : position = position ?? Vector3.zero();
}

class _BusDuckState {
  final double factor;
  double remaining;

  _BusDuckState({required this.factor, required this.remaining});
}

/// Spatial audio evaluation result containing attenuated volume, stereo pan, and distance.
class SpatialAudioResult {
  final double volume;
  final double pan;
  final double distance;

  const SpatialAudioResult({
    required this.volume,
    required this.pan,
    required this.distance,
  });
}

/// Central Audio Engine and Mixer for Ember Engine.
///
/// Implements:
/// - Category Mix Hierarchy & Volume Master Channels
/// - Dynamic Ducking (Voice ducks Music/Ambient)
/// - 3D Spatial Audio calculations (Distance falloff, Pan)
/// - Procedural Audio Synthesizer fallback
class AudioSystem with ChangeNotifier {
  static final AudioSystem instance = AudioSystem._();
  AudioSystem._();

  static int _voiceIdCounter = 0;
  final List<AudioVoice> _activeVoices = [];

  // Master and Bus Volumes
  double _masterVolume = 1.0;
  bool _isMuted = false;

  final Map<AudioCategory, double> _busVolumes = {
    AudioCategory.voice: 1.0,      // 0 dB reference
    AudioCategory.playerSfx: 0.85,  // -3 dB
    AudioCategory.sfx: 0.70,        // -6 dB
    AudioCategory.music: 0.50,      // -10 dB
    AudioCategory.ambient: 0.35,    // -14 dB
    AudioCategory.ui: 0.80,         // -4 dB
  };

  final Map<AudioCategory, _BusDuckState> _duckStates = {};

  // Listener spatial state (camera in 3D or center in 2D)
  Vector3 listenerPosition = Vector3.zero();
  Vector3 listenerForward = Vector3(0, 0, -1);
  Vector3 listenerUp = Vector3(0, 1, 0);

  /// Plays voices on real hardware (see AudioOutput). Null = silent mixer only
  /// (tests, headless tools).
  AudioBackend? backend;

  AudioVoice? _music;

  /// The currently playing background music, if any.
  AudioVoice? get music => _music;

  /// Starts looping background music from an audio file (e.g.
  /// `assets/audio/theme.ogg`), replacing any music already playing.
  AudioVoice playMusic(String clip, {double volume = 1.0}) {
    if (_music != null && _music!.clip == clip && _music!.isPlaying) return _music!;
    stopMusic();
    return _music = play(clip: clip, category: AudioCategory.music, volume: volume, looping: true, duration: double.infinity);
  }

  void stopMusic() {
    final m = _music;
    _music = null;
    if (m != null) stop(m);
  }

  double get masterVolume => _masterVolume;
  set masterVolume(double val) {
    _masterVolume = val.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setMasterVolume(double val) => masterVolume = val;

  bool get isMuted => _isMuted;
  set isMuted(bool val) {
    _isMuted = val;
    notifyListeners();
  }

  List<AudioVoice> get activeVoices => List.unmodifiable(_activeVoices);

  double getBusVolume(AudioCategory category) {
    if (category == AudioCategory.master) return _masterVolume;
    return _busVolumes[category] ?? 1.0;
  }

  void setBusVolume(AudioCategory category, double volume) {
    if (category == AudioCategory.master) {
      _masterVolume = volume.clamp(0.0, 1.0);
    } else {
      _busVolumes[category] = volume.clamp(0.0, 1.0);
    }
    notifyListeners();
  }

  /// Ducks volume of a specific audio bus by [duckFactor] for [duration] seconds.
  void duckBus(AudioCategory category, {required double duckFactor, required double duration}) {
    _duckStates[category] = _BusDuckState(factor: duckFactor, remaining: duration);
    notifyListeners();
  }

  /// Calculates effective volume for a clip playing in a category.
  double getEffectiveVolume(AudioCategory category, [double clipVolume = 1.0]) {
    if (_isMuted) return 0.0;
    final bus = getBusVolume(category);
    final duck = _duckStates[category]?.factor ?? 1.0;
    return (_masterVolume * bus * clipVolume * duck).clamp(0.0, 1.0);
  }

  /// Sets listener world position and orientation.
  void setListenerPosition(Vector3 position, [Vector3? forward, Vector3? up]) {
    listenerPosition = position;
    if (forward != null && forward.length2 > 0) listenerForward = forward.normalized();
    if (up != null && up.length2 > 0) listenerUp = up.normalized();
  }

  /// Calculates spatial audio result (volume, pan, distance) for a world position.
  SpatialAudioResult calculateSpatialAudio(
    Vector3 position, {
    double minDistance = 1.0,
    double maxDistance = 30.0,
  }) {
    final dist = (position - listenerPosition).length;
    double vol = 1.0;
    if (dist > maxDistance) {
      vol = 0.0;
    } else if (dist > minDistance) {
      vol = minDistance / (minDistance + (dist - minDistance));
    }
    final pan = _calculatePan(position);
    return SpatialAudioResult(volume: vol.clamp(0.0, 1.0), pan: pan, distance: dist);
  }

  /// Plays a sound clip (one-shot or looping).
  AudioVoice play({
    required String clip,
    AudioCategory category = AudioCategory.sfx,
    double volume = 1.0,
    double pitch = 1.0,
    bool looping = false,
    bool is3D = false,
    Vector3? position,
    double minDistance = 1.0,
    double maxDistance = 30.0,
    double duration = 1.5,
  }) {
    final voice = AudioVoice(
      id: ++_voiceIdCounter,
      clip: clip,
      category: category,
      volume: volume,
      pitch: pitch,
      isLooping: looping,
      is3D: is3D,
      position: position,
      minDistance: minDistance,
      maxDistance: maxDistance,
      duration: duration,
    );

    _activeVoices.add(voice);

    // Hand the voice to the platform backend (procedural effect or audio file)
    final pan = is3D && position != null ? _calculatePan(position) : 0.0;
    final effectiveVol = calculateEffectiveVolume(voice);
    backend?.play(voice, effectiveVol, pan);

    EmberEngine.instance.log('Audio Play: "$clip" ($category, vol: ${(effectiveVol * 100).toInt()}%)', source: 'Audio');
    notifyListeners();
    return voice;
  }

  /// Plays a quick procedural sound effect (e.g. 'laser', 'jump', 'coin', 'explosion', 'hit', 'click').
  AudioVoice playProcedural(String effectName, {double volume = 1.0, double pitch = 1.0, Vector3? position}) {
    return play(
      clip: effectName,
      category: effectName == 'click' ? AudioCategory.ui : AudioCategory.sfx,
      volume: volume,
      pitch: pitch,
      is3D: position != null,
      position: position,
    );
  }

  /// Stops a specific playing voice.
  void stop(AudioVoice voice) {
    voice.isPlaying = false;
    _activeVoices.remove(voice);
    backend?.stop(voice);
    notifyListeners();
  }

  /// Stops all voices across all categories (including music).
  void stopAll() {
    for (final v in _activeVoices) {
      v.isPlaying = false;
    }
    _activeVoices.clear();
    _music = null;
    backend?.stopAll();
    notifyListeners();
  }

  /// Stops all voices in a specific category.
  void stopCategory(AudioCategory category) {
    for (final v in _activeVoices.where((v) => v.category == category).toList()) {
      stop(v);
    }
    if (category == AudioCategory.music) _music = null;
  }

  /// Master frame update: evaluates ducking, 3D attenuation, and voice lifetimes.
  void update(double dt) {
    // 0. Update bus duck states
    _duckStates.removeWhere((cat, state) {
      state.remaining -= dt;
      return state.remaining <= 0;
    });

    if (_activeVoices.isEmpty) return;

    // 1. Ducking calculation: Check if voice/high-priority is active
    final hasVoicePlaying = _activeVoices.any((v) => v.isPlaying && v.category == AudioCategory.voice);
    final duckTarget = hasVoicePlaying ? 0.35 : 1.0; // -9dB ducking on music/ambient

    // 2. Update active voices
    for (int i = _activeVoices.length - 1; i >= 0; i--) {
      final voice = _activeVoices[i];
      if (!voice.isPlaying) {
        _activeVoices.removeAt(i);
        continue;
      }

      // Smooth ducking interpolation
      if (voice.category == AudioCategory.music || voice.category == AudioCategory.ambient) {
        voice.duckFactor += (duckTarget - voice.duckFactor) * math.min(1.0, dt * 5.0);
      } else {
        voice.duckFactor = 1.0;
      }

      voice.playbackTime += dt * voice.pitch;
      if (voice.playbackTime >= voice.duration) {
        if (voice.isLooping) {
          voice.playbackTime = 0.0;
        } else {
          voice.isPlaying = false;
          _activeVoices.removeAt(i);
        }
      }
    }
  }

  /// Computes effective audible volume combining Master, Bus, Ducking, and 3D falloff.
  double calculateEffectiveVolume(AudioVoice voice) {
    if (_isMuted) return 0.0;

    final bus = _busVolumes[voice.category] ?? 1.0;
    double vol = _masterVolume * bus * voice.volume * voice.duckFactor;

    if (voice.is3D) {
      final dist = (voice.position - listenerPosition).length;
      if (dist > voice.maxDistance) return 0.0;
      if (dist > voice.minDistance) {
        // Inverse distance logarithmic rolloff
        final rolloff = voice.minDistance / (voice.minDistance + (dist - voice.minDistance));
        vol *= rolloff;
      }
    }

    return vol.clamp(0.0, 1.0);
  }

  /// Calculates stereo panning (-1.0 Left to +1.0 Right) relative to listener forward & up.
  double _calculatePan(Vector3 pos) {
    final toSource = (pos - listenerPosition);
    if (toSource.length2 == 0) return 0.0;
    final toSourceNorm = toSource.normalized();

    final right = listenerForward.cross(listenerUp).normalized();
    final dotRight = toSourceNorm.dot(right);
    return dotRight.clamp(-1.0, 1.0);
  }

  /// Synchronizes audio listener with an entity (typically active Camera).
  void updateListenerFromEntity(EmberEntity entity) {
    final t3d = entity.getComponent<Transform3DComponent>();
    if (t3d != null) {
      listenerPosition = t3d.worldPosition;
      listenerForward = t3d.forward;
      listenerUp = t3d.up;
      return;
    }

    final t2d = entity.getComponent<Transform2DComponent>();
    if (t2d != null) {
      listenerPosition = Vector3(t2d.worldPosition.x, t2d.worldPosition.y, 0.0);
      listenerForward = Vector3(0, 0, -1);
      listenerUp = Vector3(0, 1, 0);
    }
  }
}

/// Plays [AudioVoice]s on a real audio device.
abstract class AudioBackend {
  /// Starts [voice] (a procedural effect name or an `assets/...` audio file).
  void play(AudioVoice voice, double volume, double pan);
  void stop(AudioVoice voice);
  void stopAll();
}

/// Buffer containing synthesized raw PCM audio samples.
class AudioBuffer {
  final List<double> samples;
  final double duration;
  final int sampleRate;

  const AudioBuffer({
    required this.samples,
    required this.duration,
    this.sampleRate = 44100,
  });
}

/// Procedural Sound FX Synthesizer producing raw waveform PCM arrays without external assets.
class ProceduralAudioSynth {
  static const int defaultSampleRate = 44100;

  /// Synthesizes a sci-fi laser sound with frequency sweep.
  static AudioBuffer generateLaser({double duration = 0.2}) {
    final int numSamples = (defaultSampleRate * duration).toInt();
    final samples = List<double>.generate(numSamples, (i) {
      final t = i / defaultSampleRate;
      final freq = 880.0 * (1.0 - t / duration) + 110.0;
      final env = 1.0 - (t / duration);
      return (math.sin(2.0 * math.pi * freq * t) * env).clamp(-1.0, 1.0);
    });
    return AudioBuffer(samples: samples, duration: duration);
  }

  /// Synthesizes a platformer jump whoosh with pitch up-sweep.
  static AudioBuffer generateJump({double duration = 0.18}) {
    final int numSamples = (defaultSampleRate * duration).toInt();
    final samples = List<double>.generate(numSamples, (i) {
      final t = i / defaultSampleRate;
      final freq = 150.0 + 500.0 * (t / duration);
      final env = math.sin(math.pi * (t / duration));
      return (math.sin(2.0 * math.pi * freq * t) * env).clamp(-1.0, 1.0);
    });
    return AudioBuffer(samples: samples, duration: duration);
  }

  /// Synthesizes a low-rumble noise explosion.
  static AudioBuffer generateExplosion({double duration = 0.5}) {
    final int numSamples = (defaultSampleRate * duration).toInt();
    final rng = math.Random(42);
    final samples = List<double>.generate(numSamples, (i) {
      final t = i / defaultSampleRate;
      final noise = rng.nextDouble() * 2.0 - 1.0;
      final env = math.exp(-5.0 * (t / duration));
      return (noise * env).clamp(-1.0, 1.0);
    });
    return AudioBuffer(samples: samples, duration: duration);
  }

  /// Synthesizes a retro coin / pickup dual-tone chime.
  static AudioBuffer generateCoin({double duration = 0.25}) {
    final int numSamples = (defaultSampleRate * duration).toInt();
    final samples = List<double>.generate(numSamples, (i) {
      final t = i / defaultSampleRate;
      final freq = t < 0.08 ? 987.77 : 1318.51; // B5 then E6
      final env = 1.0 - (t / duration);
      return (math.sin(2.0 * math.pi * freq * t) * env).clamp(-1.0, 1.0);
    });
    return AudioBuffer(samples: samples, duration: duration);
  }

  /// Synthesizes a damage / impact punch sound.
  static AudioBuffer generateHit({double duration = 0.15}) {
    final int numSamples = (defaultSampleRate * duration).toInt();
    final rng = math.Random(1337);
    final samples = List<double>.generate(numSamples, (i) {
      final t = i / defaultSampleRate;
      final noise = rng.nextDouble() * 2.0 - 1.0;
      final freq = 200.0 * (1.0 - t / duration);
      final square = math.sin(2.0 * math.pi * freq * t) > 0 ? 0.5 : -0.5;
      final env = 1.0 - (t / duration);
      return ((noise * 0.5 + square * 0.5) * env).clamp(-1.0, 1.0);
    });
    return AudioBuffer(samples: samples, duration: duration);
  }

  /// Synthesizes a crisp UI click.
  static AudioBuffer generateClick({double duration = 0.04}) {
    final int numSamples = (defaultSampleRate * duration).toInt();
    final samples = List<double>.generate(numSamples, (i) {
      final t = i / defaultSampleRate;
      final freq = 2200.0;
      final env = math.exp(-40.0 * t);
      return (math.sin(2.0 * math.pi * freq * t) * env).clamp(-1.0, 1.0);
    });
    return AudioBuffer(samples: samples, duration: duration);
  }
}

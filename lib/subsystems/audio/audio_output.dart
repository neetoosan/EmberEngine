import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/assets.dart';
import 'audio_system.dart';

/// Plays [AudioSystem] voices through the device speakers.
///
/// - Procedural effects (`jump`, `laser`, `coin`, …) are synthesized to a WAV
///   once (cached in the temp folder, one file per effect and pitch step).
/// - Audio files (`assets/audio/theme.ogg`, WAV/MP3/OGG) play from the project
///   or exported game folder, falling back to the engine's bundled assets.
/// - Looping voices (music) keep playing until stopped.
///
/// Kept separate from the mixer so tests and headless tools never touch the
/// platform audio plugin — call [attach] from an app entry point.
class AudioOutput implements AudioBackend {
  static final AudioOutput instance = AudioOutput._();
  AudioOutput._();

  /// Size of the reusable player pool for one-shot sounds. When all are busy
  /// the oldest sound is cut and its player reused.
  static const int maxVoices = 8;

  bool _attached = false;
  bool _reportedError = false;
  Directory? _cacheDir;
  final Map<String, Future<String?>> _wavCache = {};

  /// One-shot players are created once and reused (creating/disposing a
  /// platform player per sound is expensive on Windows).
  final List<AudioPlayer> _pool = [];
  int _nextPooled = 0;

  /// Which voice each pooled player is currently playing.
  final Map<AudioPlayer, int> _poolOwner = {};

  /// Looping voices (music) get their own player, disposed when stopped.
  final Map<int, AudioPlayer> _dedicated = {};

  /// Starts routing [AudioSystem] playback to real audio output.
  void attach() {
    if (_attached || kIsWeb) return;
    _attached = true;
    AudioSystem.instance.backend = this;
  }

  static bool isFileClip(String clip) => clip.contains('/') || clip.contains('.');

  @override
  void play(AudioVoice voice, double volume, double pan) {
    if (volume <= 0.001 && !voice.isLooping) return;
    unawaited(_play(voice, volume, pan));
  }

  Future<void> _play(AudioVoice voice, double volume, double pan) async {
    try {
      final Source source;
      if (isFileClip(voice.clip)) {
        final file = EmberAssets.instance.resolveFile(voice.clip);
        source = file != null && await file.exists()
            ? DeviceFileSource(file.path)
            : AssetSource(voice.clip.startsWith('assets/') ? voice.clip.substring(7) : voice.clip);
      } else {
        // Pitch is baked into the WAV sample rate, quantised so the cache stays small.
        final pitchStep = (voice.pitch.clamp(0.5, 2.0) * 20).round() / 20;
        final path = await _wavCache.putIfAbsent('${voice.clip}@$pitchStep', () => _writeWav(voice.clip, pitchStep));
        if (path == null) return;
        source = DeviceFileSource(path);
      }
      if (!voice.isPlaying) return; // stopped while loading

      final AudioPlayer player;
      if (voice.isLooping) {
        player = AudioPlayer();
        _dedicated[voice.id] = player;
        await player.setReleaseMode(ReleaseMode.loop);
      } else {
        player = await _acquirePooled(voice.id);
      }

      await player.setVolume(volume.clamp(0.0, 1.0));
      try {
        await player.setBalance(pan.clamp(-1.0, 1.0));
        final rate = isFileClip(voice.clip) ? voice.pitch : 1.0;
        await player.setPlaybackRate(rate);
      } catch (_) {
        // Balance / rate are not supported on every platform.
      }
      await player.play(source);
    } catch (e) {
      if (!_reportedError) {
        _reportedError = true;
        debugPrint('Ember audio output unavailable: $e');
      }
    }
  }

  /// A pooled player for [voiceId]: a new one until the pool is full, then
  /// the players are reused round-robin (cutting the oldest sound).
  Future<AudioPlayer> _acquirePooled(int voiceId) async {
    final AudioPlayer player;
    if (_pool.length < maxVoices) {
      player = AudioPlayer();
      _pool.add(player);
      await player.setReleaseMode(ReleaseMode.stop);
      player.onPlayerComplete.listen((_) => _poolOwner.remove(player));
    } else {
      player = _pool[_nextPooled];
      _nextPooled = (_nextPooled + 1) % _pool.length;
      if (_poolOwner.containsKey(player)) await player.stop();
    }
    _poolOwner[player] = voiceId;
    return player;
  }

  @override
  void stop(AudioVoice voice) => _release(voice.id);

  @override
  void stopAll() {
    for (final id in [..._dedicated.keys, ..._poolOwner.values]) {
      _release(id);
    }
  }

  void _release(int voiceId) {
    final dedicated = _dedicated.remove(voiceId);
    if (dedicated != null) {
      unawaited(() async {
        try {
          await dedicated.stop();
          await dedicated.dispose();
        } catch (_) {}
      }());
      return;
    }
    for (final entry in _poolOwner.entries.toList()) {
      if (entry.value == voiceId) {
        _poolOwner.remove(entry.key);
        unawaited(entry.key.stop().catchError((Object _) {}));
      }
    }
  }

  Future<String?> _writeWav(String clip, double pitch) async {
    final buffer = synthesize(clip);
    if (buffer == null) return null;
    _cacheDir ??= await Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}ember_sfx',
    ).create(recursive: true);
    final file = File('${_cacheDir!.path}${Platform.pathSeparator}${clip}_${(pitch * 100).round()}.wav');
    await file.writeAsBytes(encodeWav(buffer.samples, (buffer.sampleRate * pitch).round()), flush: true);
    return file.path;
  }

  /// The procedural waveform for a clip name, or null for unknown clips.
  static AudioBuffer? synthesize(String clip) {
    switch (clip) {
      case 'laser':
        return ProceduralAudioSynth.generateLaser();
      case 'jump':
        return ProceduralAudioSynth.generateJump();
      case 'explosion':
        return ProceduralAudioSynth.generateExplosion();
      case 'coin':
        return ProceduralAudioSynth.generateCoin();
      case 'hit':
        return ProceduralAudioSynth.generateHit();
      case 'click':
        return ProceduralAudioSynth.generateClick();
    }
    return null;
  }

  /// Encodes mono samples in [-1, 1] as a 16-bit PCM WAV file.
  static Uint8List encodeWav(List<double> samples, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final dataSize = samples.length * 2;
    final bytes = ByteData(44 + dataSize);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little); // PCM chunk size
    bytes.setUint16(20, 1, Endian.little); // PCM format
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
    bytes.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}

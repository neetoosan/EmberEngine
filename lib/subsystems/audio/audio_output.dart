import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_system.dart';

/// Plays [AudioSystem] sounds through the device speakers.
///
/// The mixer ([AudioSystem]) decides *what* to play and how loud / where;
/// this class turns each procedural effect into a WAV file once (cached in the
/// temp folder, one file per effect and pitch step) and plays it with
/// `audioplayers`. Kept separate so tests and headless tools never touch the
/// platform audio plugin — call [attach] from an app entry point.
class AudioOutput {
  static final AudioOutput instance = AudioOutput._();
  AudioOutput._();

  /// Upper bound on simultaneously playing sounds; the oldest is cut first.
  static const int maxVoices = 12;

  bool _attached = false;
  bool _reportedError = false;
  Directory? _cacheDir;
  final Map<String, Future<String?>> _wavCache = {};
  final List<AudioPlayer> _voices = [];

  /// Starts routing [AudioSystem] playback to real audio output.
  void attach() {
    if (_attached || kIsWeb) return;
    _attached = true;
    AudioSystem.instance.onPlayProceduralSound = (clip, volume, pitch, pan) {
      unawaited(_play(clip, volume, pitch, pan));
    };
  }

  Future<void> _play(String clip, double volume, double pitch, double pan) async {
    if (volume <= 0.001) return;
    try {
      // Pitch is baked into the WAV sample rate, quantised so the cache stays small.
      final pitchStep = ((pitch.clamp(0.5, 2.0)) * 20).round() / 20;
      final path = await _wavCache.putIfAbsent('$clip@$pitchStep', () => _writeWav(clip, pitchStep));
      if (path == null) return;

      if (_voices.length >= maxVoices) {
        unawaited(_release(_voices.first));
      }
      final player = AudioPlayer();
      _voices.add(player);
      player.onPlayerComplete.listen((_) => _release(player));
      // Safety net in case a platform never reports completion.
      Timer(const Duration(seconds: 3), () => _release(player));

      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(volume.clamp(0.0, 1.0));
      try {
        await player.setBalance(pan.clamp(-1.0, 1.0));
      } catch (_) {
        // Stereo balance is not supported on every platform; play centred.
      }
      await player.play(DeviceFileSource(path));
    } catch (e) {
      if (!_reportedError) {
        _reportedError = true;
        debugPrint('Ember audio output unavailable: $e');
      }
    }
  }

  Future<void> _release(AudioPlayer player) async {
    if (!_voices.remove(player)) return;
    try {
      await player.dispose();
    } catch (_) {}
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

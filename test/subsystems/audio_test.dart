import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/subsystems/audio/audio_system.dart';
import 'package:ember_engine/subsystems/audio/audio_component.dart';

void main() {
  group('Audio System & Procedural Synthesizer Tests', () {
    late AudioSystem audio;

    setUp(() {
      audio = AudioSystem.instance;
      audio.setMasterVolume(1.0);
      audio.setBusVolume(AudioCategory.music, 0.8);
      audio.setBusVolume(AudioCategory.sfx, 1.0);
      audio.setBusVolume(AudioCategory.voice, 1.0);
    });

    test('Audio bus mix hierarchy calculates volume with category gain', () {
      expect(audio.getBusVolume(AudioCategory.master), equals(1.0));
      expect(audio.getBusVolume(AudioCategory.music), equals(0.8));

      // Effective volume
      final effectiveMusicVol = audio.getEffectiveVolume(AudioCategory.music, 0.5);
      expect(effectiveMusicVol, closeTo(0.4, 0.001)); // 0.5 * 0.8 * 1.0
    });

    test('Dynamic bus ducking reduces target category volume during duration', () {
      audio.duckBus(AudioCategory.music, duckFactor: 0.3, duration: 1.0);

      // Immediately ducked
      final duckedVol = audio.getEffectiveVolume(AudioCategory.music, 1.0);
      expect(duckedVol, closeTo(0.24, 0.01)); // 0.8 * 0.3 = 0.24

      // Advance time by 1.5s
      audio.update(1.5);
      final restoredVol = audio.getEffectiveVolume(AudioCategory.music, 1.0);
      expect(restoredVol, closeTo(0.8, 0.01)); // Fully restored
    });

    test('3D Spatial Audio distance falloff and stereo panning calculation', () {
      audio.setListenerPosition(Vector3(0, 0, 0), Vector3(0, 0, -1)); // Facing North

      // Sound 5 units directly to the right
      final rightSoundPos = Vector3(5, 0, 0);
      final panVolume = audio.calculateSpatialAudio(rightSoundPos, minDistance: 1.0, maxDistance: 20.0);

      expect(panVolume.volume, greaterThan(0.0));
      expect(panVolume.volume, lessThan(1.0));
      expect(panVolume.pan, greaterThan(0.5)); // Panned Right (> 0)

      // Sound 5 units to the left
      final leftSoundPos = Vector3(-5, 0, 0);
      final leftPanVolume = audio.calculateSpatialAudio(leftSoundPos, minDistance: 1.0, maxDistance: 20.0);
      expect(leftPanVolume.pan, lessThan(-0.5)); // Panned Left (< 0)
    });

    test('Procedural Sound Synthesizer generates correct PCM audio buffers', () {
      final laserSound = ProceduralAudioSynth.generateLaser();
      expect(laserSound.samples.isNotEmpty, isTrue);
      expect(laserSound.duration, greaterThan(0.05));

      final jumpSound = ProceduralAudioSynth.generateJump();
      expect(jumpSound.samples.isNotEmpty, isTrue);

      final explosionSound = ProceduralAudioSynth.generateExplosion();
      expect(explosionSound.samples.isNotEmpty, isTrue);

      final coinSound = ProceduralAudioSynth.generateCoin();
      expect(coinSound.samples.isNotEmpty, isTrue);
    });

    test('AudioSourceComponent plays clip and tracks active voice state', () {
      final source = AudioSourceComponent(clip: 'laser', volume: 0.7);
      source.play();
      expect(source.isPlaying, isTrue);

      source.stop();
      expect(source.isPlaying, isFalse);
    });
  });
}

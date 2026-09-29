import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/transform3d.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/subsystems/particles/particle_system.dart';

void main() {
  group('Particle Emitter Subsystem Tests', () {
    test('ParticleEmitter3D spawns, simulates physics, decays lifetime, and respects presets', () {
      final emitter = ParticleEmitter3DComponent(
        preset: ParticlePreset.emberFire,
        maxParticles: 100,
        emissionRate: 50.0,
      );

      final entity = EmberEntity(name: 'Campfire');
      entity.addComponent(Transform3DComponent(position: vm.Vector3(0, 0, 0)));
      entity.addComponent(emitter);

      // Simulate 0.5s
      for (int i = 0; i < 30; i++) {
        emitter.update(entity, 1.0 / 60.0);
      }

      expect(emitter.particles.isNotEmpty, isTrue);
      expect(emitter.particles.length, lessThanOrEqualTo(100));

      final firstP = emitter.particles.first;
      expect(firstP.age, greaterThan(0.0));
      expect(firstP.position.y, greaterThan(0.0)); // Fire rises

      // Burst triggering
      emitter.triggerBurst(25);
      expect(emitter.particles.length, greaterThanOrEqualTo(25));
    });

    test('ParticleEmitter2D spawns particles with gravity modifier and colors', () {
      final emitter = ParticleEmitter2DComponent(
        preset: ParticlePreset.sparkBurst,
        maxParticles: 50,
        emissionRate: 20.0,
      );

      final entity = EmberEntity(name: 'SparkEmitter');
      entity.addComponent(Transform2DComponent(position: vm.Vector2(200, 200)));
      entity.addComponent(emitter);

      emitter.triggerBurst(15);
      expect(emitter.particles.length, equals(15));

      emitter.update(entity, 0.1);
      expect(emitter.particles.first.age, greaterThan(0.0));
    });

    test('Particle Preset application sets color palettes and emission properties', () {
      final emitter = ParticleEmitter3DComponent();

      emitter.applyPreset(ParticlePreset.magicOrbs);
      expect(emitter.startColor, equals(const Color(0xFF8B5CF6))); // Purple
      expect(emitter.gravity.y, closeTo(0.0, 0.01));

      emitter.applyPreset(ParticlePreset.smokeTrail);
      expect(emitter.startColor, equals(const Color(0xFF64748B))); // Slate
    });
  });
}

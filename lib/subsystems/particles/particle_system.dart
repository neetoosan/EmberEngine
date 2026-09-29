import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/transform2d.dart';
import '../../core/transform3d.dart';

/// Preset visual styles for particle emitters.
enum ParticlePreset {
  emberFire,
  sparkBurst,
  smokeTrail,
  magicOrbs,
}

/// A single live 2D particle.
class Particle2D {
  vm.Vector2 position;
  vm.Vector2 velocity;
  Color color;
  double size;
  double initialSize;
  double life;
  double maxLife;

  Particle2D({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    required this.maxLife,
  })  : life = maxLife,
        initialSize = size;

  double get age => maxLife - life;
}

/// 2D Procedural Particle Emitter Component.
class ParticleEmitter2DComponent extends EmberComponent {
  ParticlePreset preset;
  int maxParticles;
  double spawnRate; // particles per second
  double particleLifetime;
  Color startColor;
  Color endColor;
  double startSize;
  double endSize;
  double speed;
  double gravity;

  final List<Particle2D> _particles = [];
  double _spawnAccumulator = 0.0;
  final math.Random _rng = math.Random();

  ParticleEmitter2DComponent({
    this.preset = ParticlePreset.emberFire,
    this.maxParticles = 60,
    double? spawnRate,
    double? emissionRate,
    this.particleLifetime = 1.2,
    this.startColor = const Color(0xFFFF5722), // Ember Orange
    this.endColor = const Color(0xFFFFD54F), // Amber
    this.startSize = 6.0,
    this.endSize = 1.5,
    this.speed = 80.0,
    this.gravity = -40.0, // Upward buoyant force by default
  }) : spawnRate = emissionRate ?? spawnRate ?? 25.0;

  double get emissionRate => spawnRate;
  set emissionRate(double val) => spawnRate = val;

  void applyPreset(ParticlePreset val) {
    preset = val;
    _applyPreset(val);
    notifyListeners();
  }

  List<Particle2D> get particles => List.unmodifiable(_particles);

  void triggerBurst(int count, [vm.Vector2? burstPosition]) => burst(count, burstPosition);

  void update(EmberEntity ent, double dt) {
    attach(ent);
    onUpdate(dt);
  }

  void _applyPreset(ParticlePreset p) {
    switch (p) {
      case ParticlePreset.emberFire:
        startColor = const Color(0xFFFF5722);
        endColor = const Color(0xFFFFD54F);
        startSize = 6.0;
        endSize = 1.0;
        speed = 70.0;
        gravity = -50.0;
        break;
      case ParticlePreset.sparkBurst:
        startColor = const Color(0xFF00F5D4);
        endColor = const Color(0xFF3B82F6);
        startSize = 4.0;
        endSize = 0.5;
        speed = 180.0;
        gravity = 200.0;
        break;
      case ParticlePreset.smokeTrail:
        startColor = const Color(0xFF64748B);
        endColor = const Color(0xFF1E293B);
        startSize = 3.0;
        endSize = 12.0;
        speed = 30.0;
        gravity = -20.0;
        break;
      case ParticlePreset.magicOrbs:
        startColor = const Color(0xFF8B5CF6);
        endColor = const Color(0xFFEC4899);
        startSize = 8.0;
        endSize = 2.0;
        speed = 40.0;
        gravity = 0.0;
        break;
    }
  }

  @override
  void onUpdate(double dt) {
    // 1. Update existing particles
    for (int i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        _particles.removeAt(i);
        continue;
      }

      // Physics integration
      p.velocity.y += gravity * dt;
      p.position += p.velocity * dt;

      // Color & Size Interpolation
      final t = 1.0 - (p.life / p.maxLife);
      p.color = Color.lerp(startColor, endColor, t) ?? startColor;
      p.size = startSize + (endSize - startSize) * t;
    }

    // 2. Spawn new particles
    if (enabled && _particles.length < maxParticles) {
      _spawnAccumulator += dt;
      final spawnInterval = 1.0 / spawnRate;

      final t2d = entity?.getComponent<Transform2DComponent>();
      final spawnPos = t2d != null ? t2d.worldPosition : vm.Vector2.zero();

      while (_spawnAccumulator >= spawnInterval && _particles.length < maxParticles) {
        _spawnAccumulator -= spawnInterval;
        final angle = _rng.nextDouble() * math.pi * 2;
        final speedVar = speed * (0.6 + _rng.nextDouble() * 0.8);
        final vx = math.cos(angle) * speedVar;
        final vy = math.sin(angle) * speedVar;

        _particles.add(Particle2D(
          position: vm.Vector2(spawnPos.x, spawnPos.y),
          velocity: vm.Vector2(vx, vy),
          color: startColor,
          size: startSize,
          maxLife: particleLifetime * (0.8 + _rng.nextDouble() * 0.4),
        ));
      }
    }
  }

  /// Spawns an immediate one-shot explosion burst of particles.
  void burst(int count, [vm.Vector2? burstPosition]) {
    final t2d = entity?.getComponent<Transform2DComponent>();
    final pos = burstPosition ?? (t2d != null ? t2d.worldPosition : vm.Vector2.zero());

    for (int i = 0; i < count && _particles.length < maxParticles * 2; i++) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final speedVar = speed * (1.2 + _rng.nextDouble() * 1.5);

      _particles.add(Particle2D(
        position: vm.Vector2(pos.x, pos.y),
        velocity: vm.Vector2(math.cos(angle) * speedVar, math.sin(angle) * speedVar),
        color: startColor,
        size: startSize * 1.2,
        maxLife: particleLifetime * (0.5 + _rng.nextDouble() * 0.5),
      ));
    }
  }

  @override
  String get displayName => 'Particle Emitter 2D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<ParticlePreset>(
          name: 'preset',
          label: 'Preset Style',
          type: InspectableType.options,
          getter: () => preset,
          setter: (val) => applyPreset(val),
          options: ParticlePreset.values.map((p) => p.name).toList(),
        ),
        InspectableProperty<int>(
          name: 'maxParticles',
          label: 'Max Particles',
          type: InspectableType.integer,
          getter: () => maxParticles,
          setter: (val) {
            maxParticles = val.clamp(1, 500);
            notifyListeners();
          },
          min: 5,
          max: 300,
        ),
        InspectableProperty<double>(
          name: 'spawnRate',
          label: 'Rate (/sec)',
          type: InspectableType.number,
          getter: () => spawnRate,
          setter: (val) {
            spawnRate = val.clamp(1.0, 200.0);
            notifyListeners();
          },
          min: 1.0,
          max: 100.0,
          step: 5.0,
        ),
        InspectableProperty<Color>(
          name: 'startColor',
          label: 'Start Color',
          type: InspectableType.color,
          getter: () => startColor,
          setter: (val) {
            startColor = val;
            notifyListeners();
          },
        ),
        InspectableProperty<Color>(
          name: 'endColor',
          label: 'End Color',
          type: InspectableType.color,
          getter: () => endColor,
          setter: (val) {
            endColor = val;
            notifyListeners();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'preset': preset.name,
      'maxParticles': maxParticles,
      'spawnRate': spawnRate,
      'particleLifetime': particleLifetime,
      'startColor': startColor.toARGB32(),
      'endColor': endColor.toARGB32(),
      'startSize': startSize,
      'endSize': endSize,
      'speed': speed,
      'gravity': gravity,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    final pName = json['preset'] as String? ?? 'emberFire';
    preset = ParticlePreset.values.firstWhere(
      (p) => p.name == pName,
      orElse: () => ParticlePreset.emberFire,
    );
    maxParticles = json['maxParticles'] as int? ?? 60;
    spawnRate = (json['spawnRate'] as num?)?.toDouble() ?? 25.0;
    particleLifetime = (json['particleLifetime'] as num?)?.toDouble() ?? 1.2;
    startColor = Color(json['startColor'] as int? ?? const Color(0xFFFF5722).toARGB32());
    endColor = Color(json['endColor'] as int? ?? const Color(0xFFFFD54F).toARGB32());
    startSize = (json['startSize'] as num?)?.toDouble() ?? 6.0;
    endSize = (json['endSize'] as num?)?.toDouble() ?? 1.5;
    speed = (json['speed'] as num?)?.toDouble() ?? 80.0;
    gravity = (json['gravity'] as num?)?.toDouble() ?? -40.0;
    notifyListeners();
  }

  @override
  ParticleEmitter2DComponent clone() {
    return ParticleEmitter2DComponent(
      preset: preset,
      maxParticles: maxParticles,
      spawnRate: spawnRate,
      particleLifetime: particleLifetime,
      startColor: startColor,
      endColor: endColor,
      startSize: startSize,
      endSize: endSize,
      speed: speed,
      gravity: gravity,
    );
  }
}

/// A single live 3D particle.
class Particle3D {
  vm.Vector3 position;
  vm.Vector3 velocity;
  Color color;
  double size;
  double life;
  double maxLife;

  Particle3D({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    required this.maxLife,
  }) : life = maxLife;

  double get age => maxLife - life;
}

/// 3D Procedural Particle Emitter Component.
class ParticleEmitter3DComponent extends EmberComponent {
  ParticlePreset preset;
  int maxParticles;
  double spawnRate;
  double particleLifetime;
  Color startColor;
  Color endColor;
  double size;
  double speed;
  vm.Vector3 gravity;

  final List<Particle3D> _particles = [];
  double _spawnAccumulator = 0.0;
  final math.Random _rng = math.Random();

  ParticleEmitter3DComponent({
    this.preset = ParticlePreset.emberFire,
    this.maxParticles = 80,
    double? spawnRate,
    double? emissionRate,
    this.particleLifetime = 1.0,
    this.startColor = const Color(0xFFFF6D00), // Ember Orange
    this.endColor = const Color(0xFFFFD600), // Yellow
    this.size = 0.15,
    this.speed = 2.5,
    vm.Vector3? gravity,
  })  : spawnRate = emissionRate ?? spawnRate ?? 30.0,
        gravity = gravity ?? vm.Vector3(0.0, 1.0, 0.0);

  double get emissionRate => spawnRate;
  set emissionRate(double val) => spawnRate = val;

  void applyPreset(ParticlePreset val) {
    preset = val;
    _applyPreset(val);
    notifyListeners();
  }

  List<Particle3D> get particles => List.unmodifiable(_particles);

  void triggerBurst(int count, [vm.Vector3? burstPosition]) => burst(count, burstPosition);

  void update(EmberEntity ent, double dt) {
    attach(ent);
    onUpdate(dt);
  }

  void _applyPreset(ParticlePreset p) {
    switch (p) {
      case ParticlePreset.emberFire:
        startColor = const Color(0xFFFF6D00);
        endColor = const Color(0xFFFFD600);
        size = 0.15;
        speed = 2.5;
        gravity = vm.Vector3(0.0, 1.2, 0.0);
        break;
      case ParticlePreset.sparkBurst:
        startColor = const Color(0xFF00F5D4);
        endColor = const Color(0xFF3B82F6);
        size = 0.1;
        speed = 5.0;
        gravity = vm.Vector3(0.0, -4.0, 0.0);
        break;
      case ParticlePreset.smokeTrail:
        startColor = const Color(0xFF64748B);
        endColor = const Color(0xFF1E293B);
        size = 0.25;
        speed = 1.0;
        gravity = vm.Vector3(0.0, 0.5, 0.0);
        break;
      case ParticlePreset.magicOrbs:
        startColor = const Color(0xFF8B5CF6);
        endColor = const Color(0xFFEC4899);
        size = 0.2;
        speed = 1.8;
        gravity = vm.Vector3(0.0, 0.0, 0.0);
        break;
    }
  }

  @override
  void onUpdate(double dt) {
    // 1. Update active 3D particles
    for (int i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        _particles.removeAt(i);
        continue;
      }

      p.velocity += gravity * dt;
      p.position += p.velocity * dt;

      final t = 1.0 - (p.life / p.maxLife);
      p.color = Color.lerp(startColor, endColor, t) ?? startColor;
    }

    // 2. Spawn new particles
    if (enabled && _particles.length < maxParticles) {
      _spawnAccumulator += dt;
      final spawnInterval = 1.0 / spawnRate;

      final t3d = entity?.getComponent<Transform3DComponent>();
      final origin = t3d != null ? t3d.worldPosition : vm.Vector3.zero();

      while (_spawnAccumulator >= spawnInterval && _particles.length < maxParticles) {
        _spawnAccumulator -= spawnInterval;

        final theta = _rng.nextDouble() * math.pi * 2;
        final phi = _rng.nextDouble() * (math.pi * 0.5); // Upward cone
        final spd = speed * (0.5 + _rng.nextDouble() * 0.8);

        final vx = math.sin(phi) * math.cos(theta) * spd;
        final vy = math.cos(phi) * spd;
        final vz = math.sin(phi) * math.sin(theta) * spd;

        _particles.add(Particle3D(
          position: vm.Vector3(origin.x, origin.y, origin.z),
          velocity: vm.Vector3(vx, vy, vz),
          color: startColor,
          size: size * (0.8 + _rng.nextDouble() * 0.4),
          maxLife: particleLifetime * (0.7 + _rng.nextDouble() * 0.5),
        ));
      }
    }
  }

  /// One-shot 3D spark/impact burst.
  void burst(int count, [vm.Vector3? burstPosition]) {
    final t3d = entity?.getComponent<Transform3DComponent>();
    final pos = burstPosition ?? (t3d != null ? t3d.worldPosition : vm.Vector3.zero());

    for (int i = 0; i < count && _particles.length < maxParticles * 2; i++) {
      final theta = _rng.nextDouble() * math.pi * 2;
      final phi = _rng.nextDouble() * math.pi;
      final spd = speed * (1.5 + _rng.nextDouble() * 1.5);

      _particles.add(Particle3D(
        position: vm.Vector3(pos.x, pos.y, pos.z),
        velocity: vm.Vector3(
          math.sin(phi) * math.cos(theta) * spd,
          math.cos(phi) * spd,
          math.sin(phi) * math.sin(theta) * spd,
        ),
        color: startColor,
        size: size * 1.2,
        maxLife: particleLifetime * 0.6,
      ));
    }
  }

  @override
  String get displayName => 'Particle Emitter 3D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<ParticlePreset>(
          name: 'preset',
          label: 'Preset Style',
          type: InspectableType.options,
          getter: () => preset,
          setter: (val) => applyPreset(val),
          options: ParticlePreset.values.map((p) => p.name).toList(),
        ),
        InspectableProperty<int>(
          name: 'maxParticles',
          label: 'Max Particles',
          type: InspectableType.integer,
          getter: () => maxParticles,
          setter: (val) {
            maxParticles = val.clamp(1, 500);
            notifyListeners();
          },
          min: 5,
          max: 500,
        ),
        InspectableProperty<Color>(
          name: 'startColor',
          label: 'Start Color',
          type: InspectableType.color,
          getter: () => startColor,
          setter: (val) {
            startColor = val;
            notifyListeners();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'preset': preset.name,
      'maxParticles': maxParticles,
      'spawnRate': spawnRate,
      'particleLifetime': particleLifetime,
      'startColor': startColor.toARGB32(),
      'endColor': endColor.toARGB32(),
      'size': size,
      'speed': speed,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    final pName = json['preset'] as String? ?? 'emberFire';
    preset = ParticlePreset.values.firstWhere(
      (p) => p.name == pName,
      orElse: () => ParticlePreset.emberFire,
    );
    maxParticles = json['maxParticles'] as int? ?? 80;
    spawnRate = (json['spawnRate'] as num?)?.toDouble() ?? 30.0;
    particleLifetime = (json['particleLifetime'] as num?)?.toDouble() ?? 1.0;
    startColor = Color(json['startColor'] as int? ?? const Color(0xFFFF6D00).toARGB32());
    endColor = Color(json['endColor'] as int? ?? const Color(0xFFFFD600).toARGB32());
    size = (json['size'] as num?)?.toDouble() ?? 0.15;
    speed = (json['speed'] as num?)?.toDouble() ?? 2.5;
    notifyListeners();
  }

  @override
  ParticleEmitter3DComponent clone() {
    return ParticleEmitter3DComponent(
      preset: preset,
      maxParticles: maxParticles,
      spawnRate: spawnRate,
      particleLifetime: particleLifetime,
      startColor: startColor,
      endColor: endColor,
      size: size,
      speed: speed,
    );
  }
}

/// Registers Particle components in ComponentRegistry.
void registerParticleComponents() {
  ComponentRegistry.register('Particle Emitter 2D', (json) {
    final comp = ParticleEmitter2DComponent();
    comp.fromJson(json);
    return comp;
  });

  ComponentRegistry.register('Particle Emitter 3D', (json) {
    final comp = ParticleEmitter3DComponent();
    comp.fromJson(json);
    return comp;
  });
}

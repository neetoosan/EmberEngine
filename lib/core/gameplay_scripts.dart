import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as vm;
import 'engine_loop.dart';
import 'game_script.dart';
import 'input.dart';
import 'transform2d.dart';
import 'transform3d.dart';
import '../subsystems/audio/audio_system.dart';
import '../subsystems/particles/particle_system.dart';
import '../subsystems/physics/character_controller2d.dart';
import '../subsystems/physics/character_controller3d.dart';
import '../subsystems/physics/physics_world3d.dart';
import '../subsystems/two_d/flame_components.dart';
import '../subsystems/two_d/sprite_animator.dart';

/// Standard First-Person Shooter (FPS) Player Character Script.
///
/// Implements:
/// - WASD Kinematic Capsule movement & Sprinting
/// - Mouse-Look rotation with pitch clamping (-89° to +89°)
/// - Hitscan Raycast shooting with impact spark particle bursts & sound
/// - Spatial audio footsteps
class FPSPlayerController extends GameScript {
  double mouseSensitivity = 0.15;
  double shootCooldown = 0.2;
  double _shootTimer = 0.0;
  double _footstepTimer = 0.0;

  double _pitch = 0.0;
  double _yaw = 0.0;

  @override
  void onStart() {
    // Ensure character controller is attached
    if (entity?.getComponent<CharacterController3DComponent>() == null) {
      entity?.addComponent(CharacterController3DComponent());
    }
    // Start looking the way the player was placed in the editor
    final t3d = entity?.getComponent<Transform3DComponent>();
    if (t3d != null) {
      _pitch = t3d.euler.x.clamp(-89.0, 89.0);
      _yaw = t3d.euler.y;
    }
  }

  @override
  void onUpdate(double dt) {
    final t3d = entity?.getComponent<Transform3DComponent>();
    final cc = entity?.getComponent<CharacterController3DComponent>();
    if (t3d == null || cc == null) return;

    _shootTimer = math.max(0.0, _shootTimer - dt);

    // 1. Mouse-look handling
    final mouseDelta = Input.mouseDelta;
    _yaw -= mouseDelta.x * mouseSensitivity;
    _pitch = (_pitch - mouseDelta.y * mouseSensitivity).clamp(-89.0, 89.0);
    t3d.euler = vm.Vector3(_pitch, _yaw, 0.0);

    // 2. WASD Direction calculation relative to player orientation
    final moveInput = Input.getMovementVector();
    final isSprinting = Input.isActionPressed('sprint');

    final forward = t3d.forward;
    final flatForward = vm.Vector3(forward.x, 0.0, forward.z).normalized();
    final right = t3d.right;
    final flatRight = vm.Vector3(right.x, 0.0, right.z).normalized();

    final worldMoveDir = flatForward * moveInput.y + flatRight * moveInput.x;
    cc.move(worldMoveDir, isSprinting, dt);

    // 3. Jump
    if (Input.isActionJustPressed('jump')) {
      if (cc.jump()) {
        AudioSystem.instance.playProcedural('jump', volume: 0.7, position: t3d.worldPosition);
      }
    }

    // 4. Footsteps Audio
    if (cc.isGrounded && worldMoveDir.length2 > 0.01) {
      _footstepTimer += dt * (isSprinting ? 2.2 : 1.4);
      if (_footstepTimer >= 1.0) {
        _footstepTimer = 0.0;
        AudioSystem.instance.playProcedural('click', volume: 0.3, pitch: 0.8 + math.Random().nextDouble() * 0.4, position: t3d.worldPosition);
      }
    }

    // 5. Hitscan Raycast Shooting
    final firePressed = Input.isActionJustPressed('fire') || Input.isMouseButtonJustPressed(0);
    if (firePressed && _shootTimer <= 0.0) {
      _shootTimer = shootCooldown;
      _fireHitscanWeapon(t3d, cc);
    }
  }

  void _fireHitscanWeapon(Transform3DComponent t3d, CharacterController3DComponent cc) {
    final rayOrigin = t3d.worldPosition + cc.eyeOffset;
    final rayDir = t3d.forward;

    AudioSystem.instance.playProcedural('laser', volume: 0.85, position: rayOrigin);

    final hit = PhysicsWorld3D.raycast(
      scene: EmberEngine.instance.activeScene,
      origin: rayOrigin,
      direction: rayDir,
      maxDistance: 80.0,
      ignoreEntity: entity,
    );

    if (hit != null) {
      EmberEngine.instance.log('Hitscan HIT: ${hit.entity.name} at dist ${hit.distance.toStringAsFixed(1)}m', source: 'Gameplay');

      // Play impact sound at hit point
      AudioSystem.instance.playProcedural('hit', volume: 0.9, position: hit.point);

      // Trigger spark particles at impact point
      final particleEmitter = hit.entity.getComponent<ParticleEmitter3DComponent>();
      if (particleEmitter != null) {
        particleEmitter.burst(20, hit.point);
      }
    }
  }
}

/// Standard 2D Platformer Character Controller Script.
///
/// Implements:
/// - Coyote Time & Jump Buffering
/// - Variable jump height
/// - Dynamic sprite flip on movement
/// - Jump audio & dust particles
class Platformer2DController extends GameScript {
  @override
  void onStart() {
    if (entity?.getComponent<CharacterController2DComponent>() == null) {
      entity?.addComponent(CharacterController2DComponent());
    }
  }

  @override
  void onUpdate(double dt) {
    final cc = entity?.getComponent<CharacterController2DComponent>();
    final sprite = entity?.getComponent<FlameSpriteComponent>();
    if (cc == null) return;

    final hInput = Input.getAxis('horizontal');
    // Space, W and Up arrow all jump in a platformer
    final isJumpPressed = Input.isActionPressed('jump') || Input.isActionPressed(EngineAction.moveForward);
    final isJumpJustPressed =
        Input.isActionJustPressed('jump') || Input.isActionJustPressed(EngineAction.moveForward);

    final wasGrounded = cc.isGrounded;
    cc.updateMovement(
      horizontalInput: hInput,
      isJumpPressed: isJumpPressed,
      isJumpJustPressed: isJumpJustPressed,
      dt: dt,
    );

    // Audio & Dust on jump initiation
    if (wasGrounded && !cc.isGrounded && cc.velocity.y < -50.0) {
      AudioSystem.instance.playProcedural('jump', volume: 0.75);
      final emitter = entity?.getComponent<ParticleEmitter2DComponent>();
      emitter?.burst(12);
    }

    // Flip sprite facing direction
    if (sprite != null) {
      if (hInput < -0.1) {
        sprite.flipX = true;
      } else if (hInput > 0.1) {
        sprite.flipX = false;
      }
    }

    // Drive idle / run / jump clips when a Sprite Animator is attached
    getComponent<SpriteAnimatorComponent>()
        ?.play(!cc.isGrounded ? 'jump' : (cc.velocity.x.abs() > 20 ? 'run' : 'idle'));
  }
}

/// Simple Rotator script that smoothly spins an object around chosen axes.
class ProceduralRotator extends GameScript {
  double speedX = 0.0;
  double speedY = 45.0; // degrees per second
  double speedZ = 0.0;

  @override
  void onUpdate(double dt) {
    final t3d = entity?.getComponent<Transform3DComponent>();
    if (t3d != null) {
      t3d.euler = vm.Vector3(
        t3d.euler.x + speedX * dt,
        t3d.euler.y + speedY * dt,
        t3d.euler.z + speedZ * dt,
      );
      return;
    }

    final t2d = entity?.getComponent<Transform2DComponent>();
    if (t2d != null) {
      t2d.rotationDegrees += speedY * dt;
    }
  }
}

/// Pickup that disappears when the player (any entity with a 2D or 3D
/// character controller) touches it, playing a coin sound and keeping score.
class Collectible extends GameScript {
  /// Extra reach (pixels in 2D, metres in 3D) added to the overlap test.
  double pickupMargin = 4.0;
  double _bob = 0.0;
  double? _baseY;

  @override
  void onUpdate(double dt) {
    final self = entity;
    final scene = self?.scene;
    if (self == null || scene == null || !self.enabled) return;

    // Gentle idle bob so pickups read as interactive
    _bob += dt * 4.0;
    final t2d = self.getComponent<Transform2DComponent>();
    final t3d = self.getComponent<Transform3DComponent>();
    if (t2d != null) {
      _baseY ??= t2d.position.y;
      t2d.position = vm.Vector2(t2d.position.x, _baseY! + math.sin(_bob) * 3.0);
    } else if (t3d != null) {
      t3d.euler = vm.Vector3(t3d.euler.x, t3d.euler.y + 90.0 * dt, t3d.euler.z);
    }

    for (final other in scene.allEntities) {
      if (identical(other, self) || !other.enabled) continue;
      if (t2d != null && other.hasComponent<CharacterController2DComponent>()) {
        final ot = other.getComponent<Transform2DComponent>();
        if (ot != null && _overlap2D(t2d, ot)) return _collect();
      } else if (t3d != null && other.hasComponent<CharacterController3DComponent>()) {
        final ot = other.getComponent<Transform3DComponent>();
        final cc = other.getComponent<CharacterController3DComponent>()!;
        if (ot != null && (ot.worldPosition - t3d.worldPosition).length < cc.radius + 0.6 + pickupMargin * 0.1) {
          return _collect();
        }
      }
    }
  }

  bool _overlap2D(Transform2DComponent a, Transform2DComponent b) {
    final aMin = a.worldPosition - a.anchorOffset;
    final bMin = b.worldPosition - b.anchorOffset;
    final m = pickupMargin;
    return aMin.x - m < bMin.x + b.size.x * b.scale.x &&
        aMin.x + a.size.x * a.scale.x + m > bMin.x &&
        aMin.y - m < bMin.y + b.size.y * b.scale.y &&
        aMin.y + a.size.y * a.scale.y + m > bMin.y;
  }

  void _collect() {
    final self = entity!;
    self.enabled = false;
    final remaining = self.scene?.allEntities
            .where((e) => e.enabled && e.getComponent<ScriptComponent>()?.scriptName == 'Collectible')
            .length ??
        0;
    final t3d = self.getComponent<Transform3DComponent>();
    AudioSystem.instance.playProcedural('coin', volume: 0.8, position: t3d?.worldPosition);
    EmberEngine.instance.log(
      remaining == 0 ? 'Collected ${self.name} — all pickups collected!' : 'Collected ${self.name} ($remaining left)',
      source: 'Gameplay',
    );
  }
}

/// Walking enemy: patrols left and right on a Character Controller 2D,
/// turning at walls and (optionally) at ledges. Tag it `enemy` so a player
/// script can recognise it; call [squash] when the player stomps it.
///
/// Uses a Sprite Animator's `walk` and `squashed` clips when present; the
/// sprite art is assumed to face left.
class PatrolWalker extends GameScript {
  int direction = -1;
  bool turnAtLedges = true;
  bool squashed = false;
  double _squashTime = 0;

  @override
  void onUpdate(double dt) {
    final cc = getComponent<CharacterController2DComponent>();
    final t = getComponent<Transform2DComponent>();
    if (cc == null || t == null) return;
    final animator = getComponent<SpriteAnimatorComponent>();

    if (squashed) {
      _squashTime += dt;
      if (_squashTime > 0.5) destroy();
      return;
    }

    cc.updateMovement(horizontalInput: direction.toDouble(), isJumpPressed: false, isJumpJustPressed: false, dt: dt);
    if (cc.hitWall) {
      direction = -direction;
    } else if (turnAtLedges && cc.isGrounded) {
      final left = t.worldPosition.x - t.anchorOffset.x;
      final width = t.size.x * t.scale.x;
      final frontX = direction > 0 ? left + width + 2 : left - 2;
      final feetY = t.worldPosition.y - t.anchorOffset.y + t.size.y * t.scale.y;
      // Turn back at ledges and in front of spikes/lava
      if (!cc.hasGroundAt(frontX, feetY + 4) || cc.hasHazardAt(frontX, feetY - 8)) direction = -direction;
    }

    getComponent<FlameSpriteComponent>()?.flipX = direction > 0;
    animator?.play('walk');

    // Fell out of the level (into a pit): clean up
    if (t.worldPosition.y > 5000) destroy();
  }

  /// Flattens the enemy: it stops, stops hurting the player and disappears shortly after.
  void squash() {
    if (squashed) return;
    squashed = true;
    getComponent<FlameHitbox2DComponent>()?.enabled = false;
    getComponent<SpriteAnimatorComponent>()?.play('squashed');
    AudioSystem.instance.playProcedural('hit', volume: 0.7, pitch: 1.3);
  }
}

/// Registers standard gameplay scripts into global ScriptRegistry.
void registerStandardGameplayScripts() {
  ScriptRegistry.register('FPS Player Controller', () => FPSPlayerController());
  ScriptRegistry.register('Platformer 2D Controller', () => Platformer2DController());
  ScriptRegistry.register('Procedural Rotator', () => ProceduralRotator());
  ScriptRegistry.register('Collectible', () => Collectible());
  ScriptRegistry.register('Patrol Walker', () => PatrolWalker());
}

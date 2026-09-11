import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/subsystems/two_d/flame_components.dart';
import 'package:ember_engine/subsystems/two_d/flame_game.dart';
import 'package:flame/game.dart' as flame;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ember Engine 2D Subsystem Tests', () {
    test('FlameSpriteComponent property mutation and serialization', () {
      final sprite = FlameSpriteComponent(
        assetPath: 'assets/sprites/hero.png',
        tint: Colors.cyan,
        flipX: true,
        opacity: 0.8,
      );

      expect(sprite.assetPath, 'assets/sprites/hero.png');
      expect(sprite.flipX, isTrue);
      expect(sprite.opacity, 0.8);

      final json = sprite.toJson();
      final restored = FlameSpriteComponent();
      restored.fromJson(json);

      expect(restored.assetPath, 'assets/sprites/hero.png');
      expect(restored.flipX, isTrue);
      expect(restored.opacity, 0.8);
    });

    test('FlameTileMapComponent grid operations', () {
      final tilemap = FlameTileMapComponent(columns: 8, rows: 8, tileSize: 16.0);
      expect(tilemap.columns, 8);
      expect(tilemap.rows, 8);
      expect(tilemap.tileSize, 16.0);

      tilemap.setTile(2, 3, 5);
      expect(tilemap.getTile(2, 3), 5);
      expect(tilemap.getTile(0, 0), 0);

      // Serialization
      final json = tilemap.toJson();
      final copy = FlameTileMapComponent();
      copy.fromJson(json);
      expect(copy.getTile(2, 3), 5);
    });

    test('FlameHitbox2DComponent dimensions and solid collider status', () {
      final hitbox = FlameHitbox2DComponent(
        shape: Hitbox2DShape.rectangle,
        size: vm.Vector2(40.0, 50.0),
        isSolid: true,
      );

      expect(hitbox.shape, Hitbox2DShape.rectangle);
      expect(hitbox.size.x, 40.0);
      expect(hitbox.isSolid, isTrue);
    });

    test('EmberFlameGame coordinate conversions and entity picking', () {
      final engine = EmberEngine.instance;
      final game = EmberFlameGame(engine: engine);
      game.onGameResize(flame.Vector2(800, 600));
      game.zoom = 1.0;
      game.panOffset = vm.Vector2.zero();

      // Screen center (400, 300) should be world (0, 0)
      final worldCenter = game.screenToWorld(const Offset(400, 300));
      expect(worldCenter.x, closeTo(0.0, 0.001));
      expect(worldCenter.y, closeTo(0.0, 0.001));

      // World (0, 0) should project to screen center (400, 300)
      final screenCenter = game.worldToScreen(vm.Vector2(0, 0));
      expect(screenCenter.dx, closeTo(400.0, 0.001));
      expect(screenCenter.dy, closeTo(300.0, 0.001));

      // Entity picking
      final target = EmberEntity(name: 'Pickable');
      target.addComponent(Transform2DComponent(
        position: vm.Vector2(0, 0),
        size: vm.Vector2(50, 50),
        anchor: EmberAnchor.center,
      ));
      engine.activeScene.addEntity(target);

      final picked = game.pickEntity(const Offset(400, 300));
      expect(picked, same(target));

      // Picking far outside should return null
      final miss = game.pickEntity(const Offset(50, 50));
      expect(miss, isNull);
    });
  });
}

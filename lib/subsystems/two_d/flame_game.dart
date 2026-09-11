import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/transform2d.dart';
import 'flame_components.dart';

/// Flame game implementation for Ember Engine's 2D subsystem.
///
/// Handles 2D entity synchronization, orthographic camera pan/zoom,
/// pixel grid visualizer, and 2D selection gizmos.
class EmberFlameGame extends FlameGame {
  final EmberEngine engine;

  // Camera viewport controls
  vm.Vector2 panOffset = vm.Vector2(0.0, 0.0);
  double zoom = 1.0;
  double gridSnap = 16.0;
  bool showGrid = true;
  bool showHitboxes = true;

  EmberFlameGame({required this.engine});

  @override
  Color backgroundColor() => const Color(0xFF121316);


  @override
  void render(Canvas canvas) {
    super.render(canvas);

    canvas.save();
    // Apply camera transformation: translate then zoom
    canvas.translate(size.x / 2 + panOffset.x, size.y / 2 + panOffset.y);
    canvas.scale(zoom, zoom);

    // 1. Draw pixel grid
    if (showGrid) {
      _drawGrid(canvas);
    }

    // 2. Draw 2D entities
    _drawEntities(canvas);

    // 3. Draw selection gizmo & bounding box
    _drawSelectionGizmo(canvas);

    canvas.restore();
  }

  void _drawGrid(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF1E2128)
      ..strokeWidth = 1.0 / zoom;

    final axisPaint = Paint()
      ..color = const Color(0xFF2D323E)
      ..strokeWidth = 2.0 / zoom;

    // View boundaries in world space
    final halfW = (size.x / 2) / zoom;
    final halfH = (size.y / 2) / zoom;
    final minX = -halfW - panOffset.x / zoom;
    final maxX = halfW - panOffset.x / zoom;
    final minY = -halfH - panOffset.y / zoom;
    final maxY = halfH - panOffset.y / zoom;

    final startX = (minX / gridSnap).floor() * gridSnap;
    final endX = (maxX / gridSnap).ceil() * gridSnap;
    final startY = (minY / gridSnap).floor() * gridSnap;
    final endY = (maxY / gridSnap).ceil() * gridSnap;

    // Grid lines
    for (double x = startX; x <= endX; x += gridSnap) {
      canvas.drawLine(Offset(x, minY), Offset(x, maxY), paint);
    }
    for (double y = startY; y <= endY; y += gridSnap) {
      canvas.drawLine(Offset(minX, y), Offset(maxX, y), paint);
    }

    // Origin axes
    canvas.drawLine(Offset(minX, 0), Offset(maxX, 0), axisPaint);
    canvas.drawLine(Offset(0, minY), Offset(0, maxY), axisPaint);
  }

  void _drawEntities(Canvas canvas) {
    final entities = engine.activeScene.allEntities;

    // Sort by z-index if Transform2DComponent is present
    final sorted = List<EmberEntity>.from(entities)
      ..sort((a, b) {
        final za = a.getComponent<Transform2DComponent>()?.zIndex ?? 0;
        final zb = b.getComponent<Transform2DComponent>()?.zIndex ?? 0;
        return za.compareTo(zb);
      });

    for (final entity in sorted) {
      if (!entity.enabled) continue;
      final t2d = entity.getComponent<Transform2DComponent>();
      if (t2d == null) continue;

      canvas.save();
      final pos = t2d.worldPosition;
      final rot = t2d.worldRotation;
      final scale = t2d.worldScale;
      final size = t2d.size;
      final anchorOffset = t2d.anchorOffset;

      canvas.translate(pos.x, pos.y);
      canvas.rotate(rot);
      canvas.scale(scale.x, scale.y);
      canvas.translate(-anchorOffset.x, -anchorOffset.y);

      // Draw TileMap if present
      final tilemap = entity.getComponent<FlameTileMapComponent>();
      if (tilemap != null) {
        _renderTileMap(canvas, tilemap);
      }

      // Draw Sprite or placeholder
      final sprite = entity.getComponent<FlameSpriteComponent>();
      if (sprite != null) {
        _renderSprite(canvas, sprite, size);
      } else if (tilemap == null) {
        _renderEntityPlaceholder(canvas, entity.name, size);
      }

      // Draw Hitbox outlines
      if (showHitboxes) {
        final hitbox = entity.getComponent<FlameHitbox2DComponent>();
        if (hitbox != null && hitbox.debugDraw) {
          _renderHitbox(canvas, hitbox, size);
        }
      }

      canvas.restore();
    }
  }

  void _renderTileMap(Canvas canvas, FlameTileMapComponent tilemap) {
    final tilePaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF282C37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int r = 0; r < tilemap.rows; r++) {
      for (int c = 0; c < tilemap.columns; c++) {
        final tid = tilemap.getTile(c, r);
        final rect = Rect.fromLTWH(
          c * tilemap.tileSize,
          r * tilemap.tileSize,
          tilemap.tileSize,
          tilemap.tileSize,
        );

        if (tid > 0) {
          // Palette color representation based on tile ID
          final hue = (tid * 45.0) % 360.0;
          tilePaint.color = HSLColor.fromAHSL(0.85, hue, 0.6, 0.45).toColor();
          canvas.drawRect(rect, tilePaint);
        }
        canvas.drawRect(rect, strokePaint);
      }
    }
  }

  void _renderSprite(Canvas canvas, FlameSpriteComponent sprite, vm.Vector2 size) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final paint = Paint()
      ..color = sprite.tint.withValues(alpha: sprite.opacity)
      ..style = PaintingStyle.fill;

    // Stylish placeholder with Flame accent gradient
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF00F5D4).withValues(alpha: sprite.opacity * 0.9),
        const Color(0xFF00B4D8).withValues(alpha: sprite.opacity * 0.7),
      ],
    );

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    paint.shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, paint);

    // Inner icon / pattern indicator
    final borderPaint = Paint()
      ..color = const Color(0xFF00F5D4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, borderPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: '2D',
        style: TextStyle(
          color: Color(0xFF121316),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset((size.x - textPainter.width) / 2, (size.y - textPainter.height) / 2),
    );
  }

  void _renderEntityPlaceholder(Canvas canvas, String name, vm.Vector2 size) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    final fillPaint = Paint()
      ..color = const Color(0xFF222630)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, fillPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF3B4252)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);
  }

  void _renderHitbox(Canvas canvas, FlameHitbox2DComponent hitbox, vm.Vector2 entitySize) {
    final paint = Paint()
      ..color = hitbox.isSolid ? const Color(0xFF22C55E) : const Color(0xFFEF4444)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (hitbox.shape == Hitbox2DShape.rectangle) {
      final rect = Rect.fromLTWH(
        hitbox.offset.x,
        hitbox.offset.y,
        hitbox.size.x,
        hitbox.size.y,
      );
      canvas.drawRect(rect, paint);
    } else {
      final radius = hitbox.size.x / 2;
      canvas.drawCircle(
        Offset(hitbox.offset.x + radius, hitbox.offset.y + radius),
        radius,
        paint,
      );
    }
  }

  void _drawSelectionGizmo(Canvas canvas) {
    final selected = engine.selectedEntity;
    if (selected == null) return;
    final t2d = selected.getComponent<Transform2DComponent>();
    if (t2d == null) return;

    final pos = t2d.worldPosition;
    final rot = t2d.worldRotation;
    final scale = t2d.worldScale;
    final size = t2d.size;
    final anchorOffset = t2d.anchorOffset;

    canvas.save();
    canvas.translate(pos.x, pos.y);
    canvas.rotate(rot);
    canvas.scale(scale.x, scale.y);
    canvas.translate(-anchorOffset.x, -anchorOffset.y);

    final boxRect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Bounding box outline (Flame Teal)
    final boxPaint = Paint()
      ..color = const Color(0xFF00F5D4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    canvas.drawRect(boxRect, boxPaint);

    // 4 Corner resize handles
    final handlePaint = Paint()
      ..color = const Color(0xFF00F5D4)
      ..style = PaintingStyle.fill;
    final handleStroke = Paint()
      ..color = const Color(0xFF121316)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / zoom;

    const handleSize = 6.0;
    final corners = [
      Offset.zero,
      Offset(size.x, 0),
      Offset(0, size.y),
      Offset(size.x, size.y),
    ];

    for (final c in corners) {
      final handleRect = Rect.fromCenter(
        center: c,
        width: handleSize / zoom,
        height: handleSize / zoom,
      );
      canvas.drawRect(handleRect, handlePaint);
      canvas.drawRect(handleRect, handleStroke);
    }

    canvas.restore();
  }

  // --- World to Screen & Screen to World conversions ---

  vm.Vector2 screenToWorld(Offset screenPos) {
    if (!hasLayout) return vm.Vector2.zero();
    final cx = size.x / 2 + panOffset.x;
    final cy = size.y / 2 + panOffset.y;
    final wx = (screenPos.dx - cx) / zoom;
    final wy = (screenPos.dy - cy) / zoom;
    return vm.Vector2(wx, wy);
  }

  Offset worldToScreen(vm.Vector2 worldPos) {
    if (!hasLayout) return Offset.zero;
    final cx = size.x / 2 + panOffset.x;
    final cy = size.y / 2 + panOffset.y;
    return Offset(cx + worldPos.x * zoom, cy + worldPos.y * zoom);
  }

  /// Attempts to pick an entity at screen coordinates.
  EmberEntity? pickEntity(Offset screenPos) {
    final world = screenToWorld(screenPos);
    final entities = engine.activeScene.allEntities;

    // Check in reverse order (topmost first)
    for (int i = entities.length - 1; i >= 0; i--) {
      final e = entities[i];
      if (!e.enabled) continue;
      final t2d = e.getComponent<Transform2DComponent>();
      if (t2d == null) continue;

      final pos = t2d.worldPosition;
      final size = t2d.size;
      final anchorOffset = t2d.anchorOffset;

      final minX = pos.x - anchorOffset.x;
      final minY = pos.y - anchorOffset.y;
      final maxX = minX + size.x * t2d.worldScale.x;
      final maxY = minY + size.y * t2d.worldScale.y;

      if (world.x >= minX && world.x <= maxX && world.y >= minY && world.y <= maxY) {
        return e;
      }
    }
    return null;
  }
}

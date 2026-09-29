import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/event_bus.dart';
import '../../core/transform2d.dart';
import '../../core/assets.dart';
import '../particles/particle_system.dart';
import '../ui/ui_text.dart';
import 'camera2d.dart';
import 'flame_components.dart';
import 'parallax.dart';

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


  /// The game camera's view while running (null in the editor view).
  CameraView2D? _gameView;

  /// Tile-brush outline under the cursor (world space), editor only.
  Rect? brushRect;

  /// True when the frame is being drawn through the scene's Camera 2D.
  bool get isGameView => _gameView != null;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final scene = engine.activeScene;
    final isRunning = engine.playState != PlayState.stopped;
    final camera = Camera2DComponent.findIn(scene);
    final screen = Size(size.x, size.y);

    if (isRunning && camera != null) {
      // Game view: letterboxed design area, seen through the scene camera
      final view = camera.viewFor(screen);
      _gameView = view;
      canvas.drawRect(Offset.zero & screen, Paint()..color = const Color(0xFF000000));
      canvas.save();
      canvas.clipRect(view.viewport);
      canvas.drawRect(view.viewport, Paint()..color = camera.backgroundColor);
      canvas.translate(view.viewport.center.dx, view.viewport.center.dy);
      canvas.scale(view.zoom, view.zoom);
      canvas.translate(-view.center.x, -view.center.y);
      _drawEntities(canvas, false);
      canvas.restore();
      UITextComponent.paintAll(canvas, view.viewport, view.zoom, scene);
      return;
    }
    _gameView = null;

    // Editor view (or a running scene without a Camera 2D)
    canvas.save();
    canvas.translate(size.x / 2 + panOffset.x, size.y / 2 + panOffset.y);
    canvas.scale(zoom, zoom);

    // Editor overlays (grid, hitboxes, selection) are hidden while the game runs
    if (showGrid && !isRunning) _drawGrid(canvas);
    if (camera != null && !isRunning) _drawCameraFrame(canvas, camera);
    _drawEntities(canvas, showHitboxes && !isRunning);
    if (!isRunning) _drawSelectionGizmo(canvas);
    final brush = brushRect;
    if (brush != null && !isRunning) {
      canvas.drawRect(
        brush,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / zoom
          ..color = const Color(0xFF00F5D4),
      );
    }
    canvas.restore();

    // UI text previews inside the camera frame (or the whole view without a camera)
    if (camera != null && camera.designWidth > 0 && camera.designHeight > 0) {
      final c = camera.position;
      final tl = worldToScreen(vm.Vector2(c.x - camera.designWidth / 2, c.y - camera.designHeight / 2));
      final br = worldToScreen(vm.Vector2(c.x + camera.designWidth / 2, c.y + camera.designHeight / 2));
      UITextComponent.paintAll(canvas, Rect.fromPoints(tl, br), zoom, scene);
    } else {
      UITextComponent.paintAll(canvas, Offset.zero & screen, 1.0, scene);
    }
  }

  /// Outline of what the game camera will show, so levels can be framed in the editor.
  void _drawCameraFrame(Canvas canvas, Camera2DComponent camera) {
    if (camera.designWidth <= 0 || camera.designHeight <= 0) return;
    final c = camera.position;
    final rect = Rect.fromCenter(center: Offset(c.x, c.y), width: camera.designWidth, height: camera.designHeight);
    canvas.drawRect(rect, Paint()..color = camera.backgroundColor.withValues(alpha: 0.35));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / zoom
        ..color = const Color(0xFFF59E0B),
    );
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

  void _drawEntities(Canvas canvas, bool drawHitboxes) {
    final entities = engine.activeScene.allEntities;

    // Sort by z-index if Transform2DComponent is present
    final sorted = List<EmberEntity>.from(entities)
      ..sort((a, b) {
        final za = a.getComponent<Transform2DComponent>()?.zIndex ?? 0;
        final zb = b.getComponent<Transform2DComponent>()?.zIndex ?? 0;
        return za.compareTo(zb);
      });

    // Visible world area; anything outside it is skipped (long levels stay fast)
    final worldClip = canvas.getLocalClipBounds();
    final camera = Camera2DComponent.findIn(engine.activeScene);

    for (final entity in sorted) {
      if (!entity.enabled) continue;
      final t2d = entity.getComponent<Transform2DComponent>();
      if (t2d == null) continue;

      var pos = t2d.worldPosition;
      final rot = t2d.worldRotation;
      final scale = t2d.worldScale;
      final size = t2d.size;
      final anchorOffset = t2d.anchorOffset;
      final tilemap = entity.getComponent<FlameTileMapComponent>();

      // Parallax layers move slower than the camera (depth), optionally tiling sideways
      final parallax = entity.getComponent<ParallaxLayerComponent>();
      final hasParallax = parallax != null && parallax.enabled;
      if (hasParallax && camera != null) {
        final c = camera.position;
        pos = pos + vm.Vector2(c.x * (1 - parallax.factorX), c.y * (1 - parallax.factorY));
      }
      final copyWidth = size.x * scale.x.abs();
      final repeat = hasParallax && parallax.repeatX && copyWidth > 0;

      if (tilemap == null && !repeat) {
        final ext = 2 * (size.x * scale.x.abs() + size.y * scale.y.abs()) + 1;
        if (!worldClip.overlaps(Rect.fromLTRB(pos.x - ext, pos.y - ext, pos.x + ext, pos.y + ext))) {
          _drawParticlesOf(canvas, entity);
          continue;
        }
      }

      final offsets = <double>[0];
      if (repeat) {
        offsets.clear();
        final first = ((worldClip.left - pos.x) / copyWidth).floor() - 1;
        final last = ((worldClip.right - pos.x) / copyWidth).ceil() + 1;
        for (var k = first; k <= last; k++) {
          offsets.add(k * copyWidth);
        }
      }

      for (final dx in offsets) {
        canvas.save();
        canvas.translate(pos.x + dx, pos.y);
        canvas.rotate(rot);
        canvas.scale(scale.x, scale.y);
        canvas.translate(-anchorOffset.x, -anchorOffset.y);

        // Draw TileMap if present (empty-cell outlines only while editing)
        if (tilemap != null) {
          _renderTileMap(canvas, tilemap, outlineEmpty: engine.playState == PlayState.stopped);
        }

        // Draw Sprite, or (in the editor only) a placeholder so invisible entities can be found
        final sprite = entity.getComponent<FlameSpriteComponent>();
        if (sprite != null) {
          _renderSprite(canvas, sprite, size);
        } else if (tilemap == null && engine.playState == PlayState.stopped && size.x > 0 && size.y > 0) {
          _renderEntityPlaceholder(canvas, entity.name, size);
        }

        // Draw Hitbox outlines
        if (drawHitboxes) {
          final hitbox = entity.getComponent<FlameHitbox2DComponent>();
          if (hitbox != null && hitbox.debugDraw) {
            _renderHitbox(canvas, hitbox, size);
          }
        }

        canvas.restore();
      }

      _drawParticlesOf(canvas, entity);
    }
  }

  /// 2D particles are simulated in world space, so they are drawn outside the
  /// entity's local transform.
  void _drawParticlesOf(Canvas canvas, EmberEntity entity) {
    final emitter = entity.getComponent<ParticleEmitter2DComponent>();
    if (emitter != null && emitter.enabled) {
      _renderParticles2D(canvas, emitter);
    }
  }

  void _renderParticles2D(Canvas canvas, ParticleEmitter2DComponent emitter) {
    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (final p in emitter.particles) {
      particlePaint.color = p.color;
      canvas.drawCircle(Offset(p.position.x, p.position.y), p.size, particlePaint);
    }
  }

  void _renderTileMap(Canvas canvas, FlameTileMapComponent tilemap, {required bool outlineEmpty}) {
    final ts = tilemap.tileSize;
    final tilePaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF282C37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final tileset = tilemap.tilesetPath.isEmpty ? null : EmberAssets.instance.image(tilemap.tilesetPath);
    final imagePaint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;

    // Only the cells inside the visible area are drawn
    final clip = canvas.getLocalClipBounds();
    final c0 = (clip.left / ts).floor().clamp(0, tilemap.columns);
    final c1 = (clip.right / ts).ceil().clamp(0, tilemap.columns);
    final r0 = (clip.top / ts).floor().clamp(0, tilemap.rows);
    final r1 = (clip.bottom / ts).ceil().clamp(0, tilemap.rows);

    for (int r = r0; r < r1; r++) {
      for (int c = c0; c < c1; c++) {
        final tid = tilemap.getTile(c, r);
        final rect = Rect.fromLTWH(c * ts, r * ts, ts, ts);

        if (tid > 0) {
          if (tileset != null) {
            final cell = tilemap.tilesetTileSize.toDouble();
            final i = tid - 1;
            final src = Rect.fromLTWH((i % tilemap.tilesetColumns) * cell, (i ~/ tilemap.tilesetColumns) * cell, cell, cell);
            canvas.drawImageRect(tileset, src, rect, imagePaint);
          } else {
            // Palette color representation based on tile ID
            final hue = (tid * 45.0) % 360.0;
            tilePaint.color = HSLColor.fromAHSL(0.85, hue, 0.6, 0.45).toColor();
            canvas.drawRect(rect, tilePaint);
          }
        }
        if ((tid > 0 && tileset == null) || outlineEmpty) canvas.drawRect(rect, strokePaint);
      }
    }
  }

  void _renderSprite(Canvas canvas, FlameSpriteComponent sprite, vm.Vector2 size) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Real image (or the current sprite-sheet cell) once it has loaded
    final image = EmberAssets.instance.image(sprite.assetPath);
    if (image != null) {
      final cols = sprite.columns < 1 ? 1 : sprite.columns;
      final rows = sprite.rows < 1 ? 1 : sprite.rows;
      final cellW = image.width / cols;
      final cellH = image.height / rows;
      final f = sprite.frame % (cols * rows);
      final src = Rect.fromLTWH((f % cols) * cellW, (f ~/ cols) * cellH, cellW, cellH);
      final isUntinted = sprite.tint.toARGB32() == 0xFFFFFFFF;
      final imagePaint = Paint()
        // No edge anti-aliasing: tiles placed side by side must not show seams
        ..isAntiAlias = false
        ..filterQuality = sprite.smooth ? FilterQuality.medium : FilterQuality.none
        ..color = Color.fromRGBO(255, 255, 255, sprite.opacity)
        ..colorFilter = isUntinted ? null : ColorFilter.mode(sprite.tint, BlendMode.modulate);
      canvas.save();
      if (sprite.flipX || sprite.flipY) {
        canvas.translate(sprite.flipX ? size.x : 0, sprite.flipY ? size.y : 0);
        canvas.scale(sprite.flipX ? -1 : 1, sprite.flipY ? -1 : 1);
      }
      canvas.drawImageRect(image, src, rect, imagePaint);
      canvas.restore();
      return;
    }

    final paint = Paint()
      ..color = sprite.tint.withValues(alpha: sprite.opacity)
      ..style = PaintingStyle.fill;

    // Stylish placeholder: Flame accent gradient, or the sprite's tint when one is set
    final isUntinted = sprite.tint.toARGB32() == 0xFFFFFFFF;
    final base = isUntinted ? const Color(0xFF00F5D4) : sprite.tint;
    final shade = isUntinted
        ? const Color(0xFF00B4D8)
        : Color.lerp(sprite.tint, const Color(0xFF000000), 0.35)!;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        base.withValues(alpha: sprite.opacity * 0.9),
        shade.withValues(alpha: sprite.opacity * 0.7),
      ],
    );

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    paint.shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, paint);

    // Inner icon / pattern indicator
    final borderPaint = Paint()
      ..color = base
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, borderPaint);

    if (size.x < 32 || size.y < 24) return;
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
    final view = _gameView;
    if (view != null) return view.screenToWorld(screenPos);
    final cx = size.x / 2 + panOffset.x;
    final cy = size.y / 2 + panOffset.y;
    final wx = (screenPos.dx - cx) / zoom;
    final wy = (screenPos.dy - cy) / zoom;
    return vm.Vector2(wx, wy);
  }

  Offset worldToScreen(vm.Vector2 worldPos) {
    if (!hasLayout) return Offset.zero;
    final view = _gameView;
    if (view != null) return view.worldToScreen(worldPos);
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

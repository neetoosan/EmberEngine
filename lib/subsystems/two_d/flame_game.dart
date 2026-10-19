import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/event_bus.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import '../../core/assets.dart';
import '../combat/combat.dart';
import '../particles/particle_system.dart';
import '../physics/rigid_body2d.dart';
import '../ui/ui_widgets.dart';
import 'bullet_pool.dart';
import 'camera2d.dart';
import 'flame_components.dart';
import 'light2d.dart';
import 'line2d.dart';
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

  /// Upper bound on sideways repeats of one parallax layer per frame.
  static const int _maxParallaxCopies = 64;

  /// Where screen UI was last laid out (for matching clicks to UI buttons).
  Rect uiView = Rect.zero;
  double uiScale = 1;

  void _paintUi(Canvas canvas, Rect view, double scale, EmberScene scene) {
    uiView = view;
    uiScale = scale;
    UIRenderer.paintAll(canvas, view, scale, scene);
  }

  Object? _preloaded;

  /// Starts loading every image the scene uses (hidden templates included),
  /// so spawned copies appear with their art straight away.
  void _preload(EmberScene scene) {
    if (identical(_preloaded, scene)) return;
    _preloaded = scene;
    final assets = EmberAssets.instance;
    for (final c in scene.componentsOf<FlameSpriteComponent>()) {
      assets.image(c.assetPath);
    }
    for (final c in scene.componentsOf<BulletPool2DComponent>()) {
      assets.image(c.image);
    }
    for (final c in scene.componentsOf<UIImageComponent>()) {
      assets.image(c.assetPath);
    }
    for (final c in scene.componentsOf<UIButtonComponent>()) {
      assets.image(c.icon);
    }
  }

  /// True when the frame is being drawn through the scene's Camera 2D.
  bool get isGameView => _gameView != null;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final scene = engine.activeScene;
    final isRunning = engine.playState != PlayState.stopped;
    final camera = Camera2DComponent.findIn(scene);
    final screen = Size(size.x, size.y);
    if (isRunning) _preload(scene);

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
      if (camera.darkness > 0) {
        // Lit things first, then the dark (cut by lights), then what glows on its own
        _drawEntities(canvas, false, emissive: false);
        Light2DComponent.paintDarkness(canvas, canvas.getLocalClipBounds(), camera.darkness, camera.darknessColor,
            [for (final l in scene.componentsOf<Light2DComponent>()) if (l.enabled && (l.entity?.enabled ?? false)) l]);
        _drawEntities(canvas, false, emissive: true);
      } else {
        _drawEntities(canvas, false);
      }
      _drawHealthBars(canvas, scene);
      canvas.restore();
      _drawScreenEffects(canvas, view.viewport, camera);
      // UI stays the same size whatever the camera zoom
      _paintUi(canvas, view.viewport, camera.designWidth > 0 ? view.viewport.width / camera.designWidth : 1.0, scene);
      return;
    }
    _gameView = null;

    // Editor view (or a running scene without a Camera 2D). Clip to the view:
    // culling and parallax repeats size themselves from the clip bounds.
    canvas.save();
    canvas.clipRect(Offset.zero & screen);
    canvas.translate(size.x / 2 + panOffset.x, size.y / 2 + panOffset.y);
    canvas.scale(zoom, zoom);

    // Editor overlays (grid, hitboxes, selection) are hidden while the game runs
    if (showGrid && !isRunning) _drawGrid(canvas);
    if (camera != null && !isRunning) _drawCameraFrame(canvas, camera);
    _drawEntities(canvas, showHitboxes && !isRunning);
    _drawHealthBars(canvas, scene);
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
      final tl = worldToScreen(vm.Vector2(c.x - camera.viewWidth / 2, c.y - camera.viewHeight / 2));
      final br = worldToScreen(vm.Vector2(c.x + camera.viewWidth / 2, c.y + camera.viewHeight / 2));
      // UI is laid out in design pixels, which the camera's zoom stretches over the frame
      _paintUi(canvas, Rect.fromPoints(tl, br), (br.dx - tl.dx) / camera.designWidth, scene);
    } else {
      _paintUi(canvas, Offset.zero & screen, 1.0, scene);
    }
  }

  /// Camera vignette and flash, over the world and under the UI.
  void _drawScreenEffects(Canvas canvas, Rect viewport, Camera2DComponent camera) {
    if (camera.vignette > 0) {
      canvas.drawRect(
          viewport,
          Paint()
            ..shader = RadialGradient(
              radius: 0.75,
              colors: [const Color(0x00000000), Color.fromRGBO(0, 0, 0, 0.85 * camera.vignette)],
              stops: const [0.55, 1],
            ).createShader(viewport));
    }
    final flash = camera.flashColor;
    if (flash.a > 0) canvas.drawRect(viewport, Paint()..color = flash);
  }

  /// Outline of what the game camera will show, so levels can be framed in the editor.
  void _drawCameraFrame(Canvas canvas, Camera2DComponent camera) {
    if (camera.designWidth <= 0 || camera.designHeight <= 0) return;
    final c = camera.position;
    final rect = Rect.fromCenter(center: Offset(c.x, c.y), width: camera.viewWidth, height: camera.viewHeight);
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

  // Draw order cache: re-sorted only when the scene structure or a z-index changes.
  Object? _sortedScene;
  int _sortedVersion = -1;
  List<EmberEntity> _sorted = const [];

  List<EmberEntity> _drawOrder() {
    final order = _baseDrawOrder();
    if (!_anyYSort) return order;
    // Y-sort: within a layer, entities lower on the screen are drawn in front
    double bottom(EmberEntity e) {
      final t = e.getComponent<Transform2DComponent>()!;
      return t.worldPosition.y - t.anchorOffset.y + t.size.y * t.worldScale.y;
    }

    final indexed = order.indexed.toList()
      ..sort((a, b) {
        final ta = a.$2.getComponent<Transform2DComponent>(), tb = b.$2.getComponent<Transform2DComponent>();
        final za = ta?.zIndex ?? 0, zb = tb?.zIndex ?? 0;
        if (za != zb) return za.compareTo(zb);
        if ((ta?.ySort ?? false) && (tb?.ySort ?? false)) {
          final d = bottom(a.$2).compareTo(bottom(b.$2));
          if (d != 0) return d;
        }
        return a.$1.compareTo(b.$1);
      });
    return [for (final (_, e) in indexed) e];
  }

  bool _anyYSort = false;

  /// The order entities are drawn in this frame (for tests and tools).
  @visibleForTesting
  List<EmberEntity> debugDrawOrder() => _drawOrder();

  List<EmberEntity> _baseDrawOrder() {
    final scene = engine.activeScene;
    if (identical(scene, _sortedScene) && _sortedVersion == EmberEntity.structureVersion) return _sorted;
    _sortedScene = scene;
    _sortedVersion = EmberEntity.structureVersion;
    // Stable sort by z-index (ties keep hierarchy order)
    final indexed = scene.allEntities.indexed.toList()
      ..sort((a, b) {
        final za = a.$2.getComponent<Transform2DComponent>()?.zIndex ?? 0;
        final zb = b.$2.getComponent<Transform2DComponent>()?.zIndex ?? 0;
        return za != zb ? za.compareTo(zb) : a.$1.compareTo(b.$1);
      });
    _anyYSort = scene.allEntities.any((e) => e.getComponent<Transform2DComponent>()?.ySort ?? false);
    return _sorted = [for (final (_, e) in indexed) e];
  }

  /// True for things that give off their own light: drawn above darkness.
  static bool _isEmissive(EmberEntity e) =>
      (e.getComponent<FlameSpriteComponent>()?.additive ?? false) ||
      (e.getComponent<ParticleEmitter2DComponent>()?.glow ?? false) ||
      (e.getComponent<BulletPool2DComponent>()?.additive ?? false) ||
      (e.getComponent<Line2DComponent>()?.glow ?? false);

  /// [emissive] null draws everything; true / false only glowing / other entities.
  void _drawEntities(Canvas canvas, bool drawHitboxes, {bool? emissive}) {
    final sorted = _drawOrder();

    // Visible world area; anything outside it is skipped (long levels stay fast)
    final worldClip = canvas.getLocalClipBounds();
    final camera = Camera2DComponent.findIn(engine.activeScene);

    for (final entity in sorted) {
      if (!entity.enabled) continue;
      if (emissive != null && _isEmissive(entity) != emissive) continue;
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
      if (hasParallax) pos = pos + parallax.scrolled;
      final copyWidth = size.x * scale.x.abs();
      final copyHeight = size.y * scale.y.abs();
      final repeatX = hasParallax && parallax.repeatX && copyWidth > 0;
      final repeatY = hasParallax && parallax.repeatY && copyHeight > 0;
      final repeat = repeatX || repeatY;

      if (tilemap == null && !repeat) {
        final ext = 2 * (size.x * scale.x.abs() + size.y * scale.y.abs()) + 1;
        if (!worldClip.overlaps(Rect.fromLTRB(pos.x - ext, pos.y - ext, pos.x + ext, pos.y + ext))) {
          _drawWorldSpaceOf(canvas, entity);
          continue;
        }
      }

      // Copies needed to fill the view along a repeating axis
      // (never an unbounded number, e.g. if the view is not clipped)
      List<double> copies(bool on, double lo, double hi, double at, double step) {
        if (!on) return const [0];
        final first = ((lo - at) / step).floor() - 1;
        final last = math.min(((hi - at) / step).ceil() + 1, first + _maxParallaxCopies);
        return [for (var k = first; k <= last; k++) k * step];
      }

      // A repeating whole-image layer is one rectangle filled with a repeating
      // image shader: no seams between copies, and one draw however many fit
      if (repeat && tilemap == null && rot == 0 && _drawTiledLayer(canvas, entity, pos, copyWidth, copyHeight, repeatX, repeatY, worldClip)) {
        _drawWorldSpaceOf(canvas, entity);
        continue;
      }

      final xs = copies(repeatX, worldClip.left, worldClip.right, pos.x, copyWidth);
      final ys = copies(repeatY, worldClip.top, worldClip.bottom, pos.y, copyHeight);
      for (final dy in ys) {
        for (final dx in xs) {
          canvas.save();
          canvas.translate(pos.x + dx, pos.y + dy);
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
            final body = entity.getComponent<RigidBody2DComponent>();
            if (body != null && body.enabled) _renderBodyOutline(canvas, body, t2d);
          }

          canvas.restore();
        }
      }

      _drawWorldSpaceOf(canvas, entity);
    }
  }

  /// Draws a repeating parallax layer as one shader-filled rectangle. Returns
  /// false when it can't (no plain image yet, a sheet frame, or a flip).
  bool _drawTiledLayer(Canvas canvas, EmberEntity entity, vm.Vector2 pos, double w, double h, bool repeatX, bool repeatY, Rect clip) {
    final sprite = entity.getComponent<FlameSpriteComponent>();
    if (sprite == null || sprite.frameCount != 1 || sprite.flipX || sprite.flipY || w <= 0 || h <= 0) return false;
    final image = EmberAssets.instance.image(sprite.assetPath);
    if (image == null) return false;
    final area = Rect.fromLTRB(
      repeatX ? clip.left : pos.x,
      repeatY ? clip.top : pos.y,
      repeatX ? clip.right : pos.x + w,
      repeatY ? clip.bottom : pos.y + h,
    );
    if (area.isEmpty) return true;
    final matrix = vm.Matrix4.identity()
      ..translateByDouble(pos.x, pos.y, 0, 1)
      ..scaleByDouble(w / image.width, h / image.height, 1, 1);
    final isUntinted = sprite.tint.toARGB32() == 0xFFFFFFFF;
    canvas.drawRect(
        area,
        Paint()
          ..shader = ImageShader(image, repeatX ? TileMode.repeated : TileMode.decal, repeatY ? TileMode.repeated : TileMode.decal, matrix.storage,
              filterQuality: sprite.smooth ? FilterQuality.medium : FilterQuality.none)
          ..color = Color.fromRGBO(255, 255, 255, sprite.opacity)
          ..blendMode = sprite.additive ? BlendMode.plus : BlendMode.srcOver
          ..colorFilter = isUntinted ? null : ColorFilter.mode(sprite.tint, BlendMode.modulate));
    return true;
  }

  /// 2D particles and lines live in world space, so they are drawn outside
  /// the entity's local transform.
  void _drawWorldSpaceOf(Canvas canvas, EmberEntity entity) {
    final emitter = entity.getComponent<ParticleEmitter2DComponent>();
    if (emitter != null && emitter.enabled) {
      _renderParticles2D(canvas, emitter);
    }
    final line = entity.getComponent<Line2DComponent>();
    if (line != null && line.enabled) line.paint(canvas);
    final bullets = entity.getComponent<BulletPool2DComponent>();
    if (bullets != null && bullets.enabled) bullets.paint(canvas);
  }

  /// Health bars above hurt entities, on top of everything in the world.
  void _drawHealthBars(Canvas canvas, EmberScene scene) {
    for (final health in scene.componentsOf<HealthComponent>()) {
      final entity = health.entity;
      if (entity == null || !entity.enabled || !health.showBar || health.isDead || health.health >= health.maxHealth) continue;
      _renderHealthBar(canvas, health, Combat.bodyOf(entity));
    }
  }

  /// A small rounded bar above [body]: green when healthy, through amber to red.
  void _renderHealthBar(Canvas canvas, HealthComponent health, Rect body) {
    final f = (health.health / health.maxHealth).clamp(0.0, 1.0);
    final w = body.width.clamp(24.0, 64.0);
    final back = Rect.fromCenter(center: Offset(body.center.dx, body.top - 7), width: w, height: 5);
    canvas.drawRRect(RRect.fromRectAndRadius(back.inflate(1), const Radius.circular(3)), Paint()..color = const Color(0xB0101318));
    final color = f > 0.5
        ? Color.lerp(const Color(0xFFFACC15), const Color(0xFF4ADE80), (f - 0.5) * 2)!
        : Color.lerp(const Color(0xFFEF4444), const Color(0xFFFACC15), f * 2)!;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(back.left, back.top, back.width * f, back.height), const Radius.circular(2.5)),
        Paint()..color = color);
  }

  /// Rigid body collider (editor): orange dynamic, grey static, blue kinematic, dashed-looking thin for sensors.
  void _renderBodyOutline(Canvas canvas, RigidBody2DComponent body, Transform2DComponent t) {
    final color = switch (body.bodyType) {
      RigidBodyType2D.dynamic => const Color(0xFFF97316),
      RigidBodyType2D.static => const Color(0xFF94A3B8),
      RigidBodyType2D.kinematic => const Color(0xFF38BDF8),
    };
    final paint = Paint()
      ..color = body.sensor ? color.withValues(alpha: 0.6) : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (body.sensor ? 1.0 : 1.5) / zoom;
    // In the entity's local (unscaled) space: the collider is centred on the box
    final dims = body.colliderDims(t);
    final s = t.worldScale;
    final w = s.x == 0 ? 0.0 : dims.x / s.x.abs(), h = s.y == 0 ? 0.0 : dims.y / s.y.abs();
    final center = Offset(t.size.x / 2, t.size.y / 2);
    if (body.shape == BodyShape2D.circle) {
      final r = (w < h ? w : h) / 2;
      canvas.drawCircle(center, r, paint);
      canvas.drawLine(center, center + Offset(r, 0), paint); // shows the rotation
    } else {
      canvas.drawRect(Rect.fromCenter(center: center, width: w, height: h), paint);
    }
  }

  /// A soft white dot (bright centre, fading edge) for glowing particles.
  static ui.Image? _softDot;
  static ui.Image get softDot => _softDot ??= () {
    final rec = ui.PictureRecorder();
    const r = 32.0;
    Canvas(rec).drawCircle(
      const Offset(r, r),
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFFFFF), Color(0xB0FFFFFF), Color(0x30FFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.25, 0.6, 1],
        ).createShader(Rect.fromCircle(center: const Offset(r, r), radius: r)),
    );
    return rec.endRecording().toImageSync(64, 64);
  }();

  void _renderParticles2D(Canvas canvas, ParticleEmitter2DComponent emitter) {
    if (emitter.glow) {
      final ps = emitter.particles;
      if (ps.isEmpty) return;
      final dot = softDot;
      final transforms = [
        for (final p in ps)
          RSTransform.fromComponents(rotation: 0, scale: p.size * 2.4 / 64, anchorX: 32, anchorY: 32, translateX: p.position.x, translateY: p.position.y),
      ];
      final rects = List.filled(ps.length, const Rect.fromLTWH(0, 0, 64, 64));
      canvas.drawAtlas(
        dot,
        transforms,
        rects,
        [for (final p in ps) p.color],
        BlendMode.modulate,
        null,
        Paint()
          ..blendMode = BlendMode.plus
          ..filterQuality = FilterQuality.medium,
      );
      return;
    }
    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (final p in emitter.particles) {
      particlePaint.color = p.color;
      canvas.drawCircle(Offset(p.position.x, p.position.y), p.size, particlePaint);
    }
  }

  /// Sheet cells are sampled this far (in texels) inside their edges. Without
  /// it, a screen pixel landing exactly on a tile edge can pick up the first
  /// texel of the neighbouring cell (a thin coloured seam across the level).
  static const double _texelInset = 0.02;

  void _renderTileMap(Canvas canvas, FlameTileMapComponent tilemap, {required bool outlineEmpty}) {
    if (tilemap.layout != 'square') {
      _renderShapedTileMap(canvas, tilemap, outlineEmpty: outlineEmpty);
      return;
    }
    final ts = tilemap.tileSize;
    final tilePaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF282C37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final tileset = tilemap.tilesetPath.isEmpty ? null : EmberAssets.instance.image(tilemap.tilesetPath);
    final imagePaint = Paint()
      ..isAntiAlias = false
      ..filterQuality = tilemap.smooth ? FilterQuality.medium : FilterQuality.none;
    // Smooth sampling blends with neighbouring cells unless it stays half a texel inside
    final inset = tilemap.smooth ? 0.6 : _texelInset;

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
            canvas.drawImageRect(tileset, src.deflate(inset), rect, imagePaint);
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

  /// Isometric or hex maps: each tile drawn with its image bottom on the
  /// cell's bottom, back to front so taller tiles overlap the ones behind.
  void _renderShapedTileMap(Canvas canvas, FlameTileMapComponent map, {required bool outlineEmpty}) {
    final ts = map.tileSize;
    final iso = map.layout == 'isometric';
    final cellW = iso ? ts * 2 : ts;
    final cellH = iso ? ts : ts * 1.1547005383792515;
    final tileset = map.tilesetPath.isEmpty ? null : EmberAssets.instance.image(map.tilesetPath);
    final paint = Paint()..filterQuality = map.smooth ? FilterQuality.medium : FilterQuality.none;
    final clip = canvas.getLocalClipBounds();
    final cols = map.columns, rows = map.rows;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF282C37);
    void draw(int c, int r) {
      final center = iso ? map.isoCenter(c, r, ts) : map.hexCenter(c, r, ts);
      final id = map.getTile(c, r);
      if (id <= 0) {
        if (outlineEmpty) canvas.drawPath(_cellShape(center, cellW, cellH, iso), outline);
        return;
      }
      if (tileset == null) {
        canvas.drawPath(_cellShape(center, cellW, cellH, iso), Paint()..color = HSLColor.fromAHSL(0.85, (id * 45.0) % 360, 0.6, 0.45).toColor());
        return;
      }
      final cw = map.tilesetTileSize.toDouble();
      final rowsInSet = map.tilesetRows > 0 ? map.tilesetRows : (tileset.height / cw).floor().clamp(1, 1 << 20);
      final rowH = tileset.height / rowsInSet;
      final i = id - 1;
      final src = Rect.fromLTWH((i % map.tilesetColumns) * cw, (i ~/ map.tilesetColumns) * rowH, cw, rowH);
      final destH = cellW * rowH / cw;
      final dst = Rect.fromLTWH(center.dx - cellW / 2, center.dy + cellH / 2 - destH, cellW, destH);
      if (!dst.overlaps(clip)) return;
      canvas.drawImageRect(tileset, src.deflate(map.smooth ? 0.6 : _texelInset), dst, paint);
    }

    if (iso) {
      for (var s = 0; s <= cols + rows - 2; s++) {
        for (var c = 0; c < cols; c++) {
          final r = s - c;
          if (r >= 0 && r < rows) draw(c, r);
        }
      }
    } else {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          draw(c, r);
        }
      }
    }
  }

  static Path _cellShape(Offset c, double w, double h, bool iso) {
    if (iso) {
      return Path()
        ..moveTo(c.dx, c.dy - h / 2)
        ..lineTo(c.dx + w / 2, c.dy)
        ..lineTo(c.dx, c.dy + h / 2)
        ..lineTo(c.dx - w / 2, c.dy)
        ..close();
    }
    final p = Path();
    for (var k = 0; k < 6; k++) {
      final a = math.pi / 3 * k - math.pi / 2;
      final pt = Offset(c.dx + math.cos(a) * h / 2, c.dy + math.sin(a) * h / 2);
      if (k == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    return p..close();
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
        ..blendMode = sprite.additive ? BlendMode.plus : BlendMode.srcOver
        ..colorFilter = isUntinted ? null : ColorFilter.mode(sprite.tint, BlendMode.modulate);
      canvas.save();
      if (sprite.flipX || sprite.flipY) {
        canvas.translate(sprite.flipX ? size.x : 0, sprite.flipY ? size.y : 0);
        canvas.scale(sprite.flipX ? -1 : 1, sprite.flipY ? -1 : 1);
      }
      final from = cols * rows > 1 ? src.deflate(_texelInset) : src;
      canvas.drawImageRect(image, from, rect, imagePaint);
      if (sprite.flash > 0) {
        // The sprite's shape in white, over it
        canvas.drawImageRect(
            image,
            from,
            rect,
            Paint()
              ..filterQuality = imagePaint.filterQuality
              ..colorFilter = ColorFilter.mode(Color.fromRGBO(255, 255, 255, (sprite.flash * 0.6 * sprite.opacity).clamp(0.0, 1.0)), BlendMode.srcIn));
      }
      canvas.restore();
      return;
    }
    // While the game runs, an image that is still loading draws nothing
    if (engine.playState != PlayState.stopped && sprite.assetPath.isNotEmpty && !EmberAssets.instance.isMissing(sprite.assetPath)) return;

    final paint = Paint()
      ..color = sprite.tint.withValues(alpha: sprite.opacity)
      ..style = PaintingStyle.fill;

    // Stylish placeholder: Flame accent gradient, or the sprite's tint when one is set
    final isUntinted = sprite.tint.toARGB32() == 0xFFFFFFFF;
    final base = isUntinted ? const Color(0xFF00F5D4) : sprite.tint;
    final shade = isUntinted ? const Color(0xFF00B4D8) : Color.lerp(sprite.tint, const Color(0xFF000000), 0.35)!;
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
        style: TextStyle(color: Color(0xFF121316), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, Offset((size.x - textPainter.width) / 2, (size.y - textPainter.height) / 2));
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
      final rect = Rect.fromLTWH(hitbox.offset.x, hitbox.offset.y, hitbox.size.x, hitbox.size.y);
      canvas.drawRect(rect, paint);
    } else {
      final radius = hitbox.size.x / 2;
      canvas.drawCircle(Offset(hitbox.offset.x + radius, hitbox.offset.y + radius), radius, paint);
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
    final corners = [Offset.zero, Offset(size.x, 0), Offset(0, size.y), Offset(size.x, size.y)];

    for (final c in corners) {
      final handleRect = Rect.fromCenter(center: c, width: handleSize / zoom, height: handleSize / zoom);
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

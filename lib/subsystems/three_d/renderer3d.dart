import 'dart:ui' show Vertices;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/transform3d.dart';
import '../particles/particle_system.dart';
import 'camera3d.dart';
import 'components3d.dart';
import 'lighting.dart';
import 'mesh.dart';

/// A light prepared once per frame (plain numbers for the vertex loop).
class _Light {
  final LightType type;
  final double r, g, b, intensity;
  final double dx, dy, dz; // direction toward the light (directional)
  final double px, py, pz, range; // position (point)
  const _Light(this.type, this.r, this.g, this.b, this.intensity, this.dx, this.dy, this.dz, this.px, this.py, this.pz, this.range);
}

/// Numbers from the last frame, for the stats overlay and benchmarks.
class RenderStats {
  int objects = 0;
  int culledObjects = 0;
  int triangles = 0;

  /// Milliseconds spent transforming + lighting, ordering, and issuing draws.
  double transformMs = 0, sortMs = 0, drawMs = 0;
}

/// Real-time 3D renderer on a Flutter Canvas.
///
/// The CPU transforms and lights vertices in flat typed arrays (no per-vertex
/// objects), skips objects outside the view, back-face culls, clips against
/// the near plane and orders triangles far-to-near with a bucket sort. The GPU
/// then rasterises everything in one batched `drawVertices` call, blending
/// per-vertex colours across smooth surfaces.
///
/// There is no depth buffer (Flutter's stable Canvas has none), so surfaces
/// that pass through each other can overlap imperfectly.
class Renderer3D {
  static final RenderStats stats = RenderStats();

  // Reusable buffers (grown as needed, never shrunk)
  static Float64List _clip = Float64List(4 * 1024);
  static Float64List _world = Float64List(3 * 1024);
  static Int32List _vertexColor = Int32List(1024);
  static Float32List _triPos = Float32List(6 * 4096);
  static Int32List _triColor = Int32List(3 * 4096);
  static Float64List _triDepth = Float64List(4096);
  static Uint8List _triWire = Uint8List(4096);
  static int _triCount = 0;
  static Int32List _order = Int32List(4096);
  static Float32List _batchPos = Float32List(6 * 4096);
  static Int32List _batchColor = Int32List(3 * 4096);

  static void _ensureVertices(int n) {
    if (_vertexColor.length >= n) return;
    final cap = math.max(n, _vertexColor.length * 2);
    _clip = Float64List(4 * cap);
    _world = Float64List(3 * cap);
    _vertexColor = Int32List(cap);
  }

  static void _ensureTriangles(int n) {
    if (_triDepth.length >= n) return;
    final cap = math.max(n, _triDepth.length * 2);
    _triPos = Float32List(6 * cap)..setRange(0, 6 * _triCount, _triPos);
    _triColor = Int32List(3 * cap)..setRange(0, 3 * _triCount, _triColor);
    _triDepth = Float64List(cap)..setRange(0, _triCount, _triDepth);
    _triWire = Uint8List(cap)..setRange(0, _triCount, _triWire);
  }

  static void _addTriangle(double x0, double y0, double x1, double y1, double x2, double y2, int c0, int c1, int c2, double depth, bool wire) {
    _ensureTriangles(_triCount + 1);
    final p = _triCount * 6, c = _triCount * 3;
    _triPos[p] = x0;
    _triPos[p + 1] = y0;
    _triPos[p + 2] = x1;
    _triPos[p + 3] = y1;
    _triPos[p + 4] = x2;
    _triPos[p + 5] = y2;
    _triColor[c] = c0;
    _triColor[c + 1] = c1;
    _triColor[c + 2] = c2;
    _triDepth[_triCount] = depth;
    _triWire[_triCount] = wire ? 1 : 0;
    _triCount++;
  }

  static void renderScene({
    required Canvas canvas,
    required Size size,
    required EmberEngine engine,
    required Vector3 cameraPosition,
    required Quaternion cameraRotation,
    CameraComponent? cameraComp,
    bool wireframeOverride = false,
    bool showGrid = true,
    bool showSelection = true,
  }) {
    if (size.width <= 0 || size.height <= 0) return;
    // Near-clipped floors project far outside the view; keep them off the panels around it
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final camera = cameraComp ?? CameraComponent();
    final aspect = size.width / size.height;
    final viewMatrix = camera.getViewMatrix(cameraPosition, cameraRotation);
    final projMatrix = camera.getProjectionMatrix(aspect);
    final viewProjMatrix = projMatrix * viewMatrix;

    // 1. Render 3D Ground Grid
    if (showGrid) {
      _renderGroundGrid(canvas, size, viewProjMatrix, cameraPosition);
    }

    // 2. Lights, prepared once per frame
    final lights = _prepareLights(engine);

    // 3. Transform, light and project every visible mesh into the triangle buffers
    final timer = Stopwatch()..start();
    _triCount = 0;
    stats
      ..objects = 0
      ..culledObjects = 0;
    final w = size.width, h = size.height;
    final camX = cameraPosition.x, camY = cameraPosition.y, camZ = cameraPosition.z;

    for (final mr in engine.activeScene.componentsOf<MeshRenderer3DComponent>()) {
      final entity = mr.entity;
      if (entity == null || !entity.enabled || !mr.enabled) continue;
      final t3d = entity.getComponent<Transform3DComponent>();
      if (t3d == null) continue;
      stats.objects++;

      final worldMatrix = t3d.worldMatrix;
      final mvpMatrix = viewProjMatrix * worldMatrix;
      final mesh = mr.mesh;
      if (_outsideView(mesh.bounds, mvpMatrix)) {
        stats.culledObjects++;
        continue;
      }

      final mat = mr.material;
      final wire = wireframeOverride || mat.wireframe;
      final isFloor = mr.primitiveType == MeshPrimitiveType.plane;
      final smooth = mesh.smoothShading;
      final m = worldMatrix.storage, p = mvpMatrix.storage;
      final base = mat.color;
      final baseR = base.r, baseG = base.g, baseB = base.b, alpha = base.a;
      final roughness = mat.roughness, metallic = mat.metallic;

      // Normal matrix (inverse transpose of the world rotation/scale)
      final nm = Matrix3.copy(worldMatrix.getRotation());
      if (nm.invert() == 0) nm.setIdentity();
      nm.transpose();
      final n = nm.storage;

      // Vertices: clip space, world space, and (smooth meshes) lit colour
      final pos = mesh.positionData, nor = mesh.normalData;
      final vCount = mesh.vertices.length;
      _ensureVertices(vCount);
      final clip = _clip, world = _world, vcol = _vertexColor;
      for (var i = 0; i < vCount; i++) {
        final x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2];
        clip[i * 4] = p[0] * x + p[4] * y + p[8] * z + p[12];
        clip[i * 4 + 1] = p[1] * x + p[5] * y + p[9] * z + p[13];
        clip[i * 4 + 2] = p[2] * x + p[6] * y + p[10] * z + p[14];
        clip[i * 4 + 3] = p[3] * x + p[7] * y + p[11] * z + p[15];
        final wx = m[0] * x + m[4] * y + m[8] * z + m[12];
        final wy = m[1] * x + m[5] * y + m[9] * z + m[13];
        final wz = m[2] * x + m[6] * y + m[10] * z + m[14];
        world[i * 3] = wx;
        world[i * 3 + 1] = wy;
        world[i * 3 + 2] = wz;
        vcol[i] = _unlit;
      }

      // Smooth meshes: light a vertex only when a visible triangle uses it
      int lit(int i) {
        final existing = vcol[i];
        if (existing != _unlit) return existing;
        final ox = nor[i * 3], oy = nor[i * 3 + 1], oz = nor[i * 3 + 2];
        var nx = n[0] * ox + n[3] * oy + n[6] * oz;
        var ny = n[1] * ox + n[4] * oy + n[7] * oz;
        var nz = n[2] * ox + n[5] * oy + n[8] * oz;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (len > 0) {
          nx /= len;
          ny /= len;
          nz /= len;
        }
        return vcol[i] = _shade(nx, ny, nz, world[i * 3], world[i * 3 + 1], world[i * 3 + 2], camX, camY, camZ, baseR, baseG, baseB,
            alpha, roughness, metallic, lights);
      }

      // Triangles
      final idx = mesh.indexData;
      final triCount = idx.length ~/ 3;
      // A floor is one flat surface: light it once so its triangles don't show seams
      int? floorColor;
      for (var t = 0; t < triCount; t++) {
        final a = idx[t * 3], b = idx[t * 3 + 1], c = idx[t * 3 + 2];
        final wa = clip[a * 4 + 3], wb = clip[b * 4 + 3], wc = clip[c * 4 + 3];

        int faceColor() => isFloor
            ? floorColor ??= _shadeFloor(world, idx, vCount, camX, camY, camZ, baseR, baseG, baseB, alpha, roughness, metallic, lights)
            : _faceColor(world, a, b, c, camX, camY, camZ, baseR, baseG, baseB, alpha, roughness, metallic, lights);

        if (wa <= _nearW || wb <= _nearW || wc <= _nearW) {
          // Slow path: clip against the near plane so large surfaces (floors,
          // walls) the camera stands inside still render. May become a quad.
          final poly = _clipNear([
            Vector4(clip[a * 4], clip[a * 4 + 1], clip[a * 4 + 2], wa),
            Vector4(clip[b * 4], clip[b * 4 + 1], clip[b * 4 + 2], wb),
            Vector4(clip[c * 4], clip[c * 4 + 1], clip[c * 4 + 2], wc),
          ]);
          if (poly.length < 3) continue;
          final screen = [for (final v in poly) _toScreen(v, size)];
          final cross = (screen[1].dx - screen[0].dx) * (screen[2].dy - screen[0].dy) -
              (screen[1].dy - screen[0].dy) * (screen[2].dx - screen[0].dx);
          if (cross >= 0) continue;
          final col = faceColor();
          final depth = isFloor ? double.maxFinite : poly.fold<double>(0, (s, v) => s + v.w) / poly.length;
          for (var i = 1; i < screen.length - 1; i++) {
            _addTriangle(screen[0].dx, screen[0].dy, screen[i].dx, screen[i].dy, screen[i + 1].dx, screen[i + 1].dy, col, col, col, depth, wire);
          }
          continue;
        }

        final x0 = (clip[a * 4] / wa + 1) * 0.5 * w, y0 = (1 - clip[a * 4 + 1] / wa) * 0.5 * h;
        final x1 = (clip[b * 4] / wb + 1) * 0.5 * w, y1 = (1 - clip[b * 4 + 1] / wb) * 0.5 * h;
        final x2 = (clip[c * 4] / wc + 1) * 0.5 * w, y2 = (1 - clip[c * 4 + 1] / wc) * 0.5 * h;
        // Back-face culling: meshes wind counter-clockwise around outward normals;
        // with screen y pointing down a camera-facing triangle has a negative cross product
        if ((x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0) >= 0) continue;
        // Flat planes are floors: always painted first so they never cover objects on them
        final depth = isFloor ? double.maxFinite : (wa + wb + wc) / 3;
        if (smooth) {
          _addTriangle(x0, y0, x1, y1, x2, y2, lit(a), lit(b), lit(c), depth, wire);
        } else {
          final col = faceColor();
          _addTriangle(x0, y0, x1, y1, x2, y2, col, col, col, depth, wire);
        }
      }
    }
    stats.triangles = _triCount;
    stats.transformMs = timer.elapsedMicroseconds / 1000;

    // 4. Far-to-near order (painter's algorithm) with a linear-time bucket sort
    timer.reset();
    final order = _sortFarToNear();
    stats.sortMs = timer.elapsedMicroseconds / 1000;
    timer.reset();

    // 5. Draw. Filled triangles go to the GPU in batches (one drawVertices per
    // run between wireframe triangles), keeping the sorted order.
    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final path = Path();
    final batchPaint = Paint();
    if (_batchPos.length < _triCount * 6) {
      _batchPos = Float32List(_triCount * 6);
      _batchColor = Int32List(_triCount * 3);
    }
    var batch = 0;
    void flushBatch() {
      if (batch == 0) return;
      canvas.drawVertices(
        Vertices.raw(
          VertexMode.triangles,
          Float32List.sublistView(_batchPos, 0, batch * 6),
          colors: Int32List.sublistView(_batchColor, 0, batch * 3),
        ),
        BlendMode.dst, // use the per-vertex colours as-is
        batchPaint,
      );
      batch = 0;
    }

    for (var k = 0; k < _triCount; k++) {
      final t = order[k];
      if (_triWire[t] == 1) {
        flushBatch();
        path
          ..reset()
          ..moveTo(_triPos[t * 6], _triPos[t * 6 + 1])
          ..lineTo(_triPos[t * 6 + 2], _triPos[t * 6 + 3])
          ..lineTo(_triPos[t * 6 + 4], _triPos[t * 6 + 5])
          ..close();
        wirePaint.color = Color(_triColor[t * 3]);
        canvas.drawPath(path, wirePaint);
      } else {
        _batchPos.setRange(batch * 6, batch * 6 + 6, _triPos, t * 6);
        _batchColor.setRange(batch * 3, batch * 3 + 3, _triColor, t * 3);
        batch++;
      }
    }
    flushBatch();
    stats.drawMs = timer.elapsedMicroseconds / 1000;

    // 6. Draw 3D Particles
    _renderParticles3D(canvas, engine, viewProjMatrix, size);

    // 7. Draw Selected Entity Highlight Outline
    if (showSelection) {
      _renderSelectionHighlight(canvas, engine.selectedEntity, viewProjMatrix, size);
    }
    canvas.restore();
  }

  static void _renderParticles3D(Canvas canvas, EmberEngine engine, Matrix4 viewProj, Size size) {
    final particlePaint = Paint()..style = PaintingStyle.fill;

    for (final entity in engine.activeScene.allEntities) {
      if (!entity.enabled) continue;
      final emitter = entity.getComponent<ParticleEmitter3DComponent>();
      if (emitter == null || !emitter.enabled) continue;

      for (final p in emitter.particles) {
        final screenPos = _projectPoint(p.position, viewProj, size);
        if (screenPos != null) {
          particlePaint.color = p.color;
          canvas.drawCircle(screenPos, p.size * 30.0, particlePaint);
        }
      }
    }
  }

  static List<_Light> _prepareLights(EmberEngine engine) {
    final out = <_Light>[];
    for (final light in engine.activeScene.componentsOf<LightComponent>()) {
      final e = light.entity;
      if (e == null || !e.enabled || !light.enabled) continue;
      final t = e.getComponent<Transform3DComponent>();
      var dx = 0.0, dy = 0.0, dz = 0.0, px = 0.0, py = 0.0, pz = 0.0;
      if (light.type == LightType.directional) {
        final dir = t != null ? -t.forward.normalized() : Vector3(0.5, 1.0, 0.5).normalized();
        dx = dir.x;
        dy = dir.y;
        dz = dir.z;
      } else if (light.type == LightType.point) {
        final p = t?.worldPosition ?? Vector3.zero();
        px = p.x;
        py = p.y;
        pz = p.z;
      }
      out.add(_Light(light.type, light.color.r, light.color.g, light.color.b, light.intensity, dx, dy, dz, px, py, pz, light.range));
    }
    return out;
  }

  /// Flat colour of triangle (a, b, c) from its face normal, lit at its centre.
  static int _faceColor(
    Float64List world, int a, int b, int c,
    double camX, double camY, double camZ,
    double baseR, double baseG, double baseB, double alpha,
    double roughness, double metallic,
    List<_Light> lights,
  ) {
    final ax = world[a * 3], ay = world[a * 3 + 1], az = world[a * 3 + 2];
    final e1x = world[b * 3] - ax, e1y = world[b * 3 + 1] - ay, e1z = world[b * 3 + 2] - az;
    final e2x = world[c * 3] - ax, e2y = world[c * 3 + 1] - ay, e2z = world[c * 3 + 2] - az;
    var nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len > 0) {
      nx /= len;
      ny /= len;
      nz /= len;
    }
    final cx = (ax + world[b * 3] + world[c * 3]) / 3;
    final cy = (ay + world[b * 3 + 1] + world[c * 3 + 1]) / 3;
    final cz = (az + world[b * 3 + 2] + world[c * 3 + 2]) / 3;
    return _shade(nx, ny, nz, cx, cy, cz, camX, camY, camZ, baseR, baseG, baseB, alpha, roughness, metallic, lights);
  }

  /// One colour for a whole flat mesh: the first triangle's normal, lit at the mesh centre.
  static int _shadeFloor(
    Float64List world, Int32List idx, int vCount,
    double camX, double camY, double camZ,
    double baseR, double baseG, double baseB, double alpha,
    double roughness, double metallic,
    List<_Light> lights,
  ) {
    final a = idx[0], b = idx[1], c = idx[2];
    final ax = world[a * 3], ay = world[a * 3 + 1], az = world[a * 3 + 2];
    final e1x = world[b * 3] - ax, e1y = world[b * 3 + 1] - ay, e1z = world[b * 3 + 2] - az;
    final e2x = world[c * 3] - ax, e2y = world[c * 3 + 1] - ay, e2z = world[c * 3 + 2] - az;
    var nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len > 0) {
      nx /= len;
      ny /= len;
      nz /= len;
    }
    var cx = 0.0, cy = 0.0, cz = 0.0;
    for (var i = 0; i < vCount; i++) {
      cx += world[i * 3];
      cy += world[i * 3 + 1];
      cz += world[i * 3 + 2];
    }
    return _shade(nx, ny, nz, cx / vCount, cy / vCount, cz / vCount, camX, camY, camZ, baseR, baseG, baseB, alpha, roughness,
        metallic, lights);
  }

  /// Marks a vertex not lit yet this frame (no real colour is fully transparent black with these bits).
  static const int _unlit = 0x00FF00FF;

  /// pow(d, shininess) for d in 0..1, tabulated per shininess (1025 steps).
  static final Map<double, Float64List> _powTables = {};

  static double _specPow(double d, double shininess) {
    final table = _powTables.putIfAbsent(shininess, () {
      final t = Float64List(1026);
      for (var i = 0; i <= 1025; i++) {
        t[i] = math.pow(math.min(1.0, i / 1024), shininess).toDouble();
      }
      return t;
    });
    final f = d * 1024;
    final i = f.toInt();
    return table[i] + (table[i + 1] - table[i]) * (f - i); // linear interpolation between steps
  }

  static final double _sunX = 0.5 / math.sqrt(0.5 * 0.5 + 1 + 0.8 * 0.8);
  static final double _sunY = 1.0 / math.sqrt(0.5 * 0.5 + 1 + 0.8 * 0.8);
  static final double _sunZ = 0.8 / math.sqrt(0.5 * 0.5 + 1 + 0.8 * 0.8);

  /// Blinn-Phong lighting of one point; returns ARGB.
  static int _shade(
    double nx, double ny, double nz,
    double px, double py, double pz,
    double camX, double camY, double camZ,
    double baseR, double baseG, double baseB, double alpha,
    double roughness, double metallic,
    List<_Light> lights,
  ) {
    var r = 0.25, g = 0.25, b = 0.25; // ambient base
    var vx = camX - px, vy = camY - py, vz = camZ - pz;
    final vl = math.sqrt(vx * vx + vy * vy + vz * vz);
    if (vl > 0) {
      vx /= vl;
      vy /= vl;
      vz /= vl;
    }
    final shininess = (1.0 - roughness) * 64.0 + 4.0;

    double specular(double lx, double ly, double lz) {
      var hx = lx + vx, hy = ly + vy, hz = lz + vz;
      final hl = math.sqrt(hx * hx + hy * hy + hz * hz);
      if (hl == 0) return 0;
      final d = (nx * hx + ny * hy + nz * hz) / hl;
      return d <= 0 ? 0 : _specPow(math.min(d, 1.0), shininess);
    }

    if (lights.isEmpty) {
      // Default sunlight when the scene has no lights
      final diff = math.max(0.0, nx * _sunX + ny * _sunY + nz * _sunZ);
      final spec = specular(_sunX, _sunY, _sunZ) * (0.3 + metallic * 0.5);
      r += diff * 0.75 + spec;
      g += diff * 0.75 + spec;
      b += diff * 0.75 + spec;
    } else {
      for (final l in lights) {
        switch (l.type) {
          case LightType.ambient:
            r += l.r * l.intensity;
            g += l.g * l.intensity;
            b += l.b * l.intensity;
          case LightType.directional:
            final diff = math.max(0.0, nx * l.dx + ny * l.dy + nz * l.dz) * l.intensity;
            final spec = specular(l.dx, l.dy, l.dz) * l.intensity * (0.2 + metallic * 0.6);
            r += l.r * diff + spec;
            g += l.g * diff + spec;
            b += l.b * diff + spec;
          case LightType.point:
            var lx = l.px - px, ly = l.py - py, lz = l.pz - pz;
            final dist = math.sqrt(lx * lx + ly * ly + lz * lz);
            if (dist > l.range || dist == 0) continue;
            lx /= dist;
            ly /= dist;
            lz /= dist;
            final atten = (1.0 - dist / l.range).clamp(0.0, 1.0);
            final diff = math.max(0.0, nx * lx + ny * ly + nz * lz) * l.intensity * atten;
            r += l.r * diff;
            g += l.g * diff;
            b += l.b * diff;
          default:
            break;
        }
      }
    }
    int ch(double v) => (v.clamp(0.0, 1.0) * 255).round();
    return ch(alpha) << 24 | ch(baseR * r) << 16 | ch(baseG * g) << 8 | ch(baseB * b);
  }

  /// True if the mesh's bounding box is entirely outside one side of the view.
  static bool _outsideView(AABB3D box, Matrix4 mvp) {
    final p = mvp.storage;
    var left = 0, right = 0, bottom = 0, top = 0, behind = 0;
    for (var i = 0; i < 8; i++) {
      final x = (i & 1) == 0 ? box.min.x : box.max.x;
      final y = (i & 2) == 0 ? box.min.y : box.max.y;
      final z = (i & 4) == 0 ? box.min.z : box.max.z;
      final cx = p[0] * x + p[4] * y + p[8] * z + p[12];
      final cy = p[1] * x + p[5] * y + p[9] * z + p[13];
      final cw = p[3] * x + p[7] * y + p[11] * z + p[15];
      if (cx < -cw) left++;
      if (cx > cw) right++;
      if (cy < -cw) bottom++;
      if (cy > cw) top++;
      if (cw <= _nearW) behind++;
    }
    return left == 8 || right == 8 || bottom == 8 || top == 8 || behind == 8;
  }

  /// Triangle indices far-to-near: floors first (in submission order), then
  /// the rest in 4096 depth buckets (linear time, stable within a bucket).
  static Int32List _sortFarToNear() {
    final n = _triCount;
    if (_order.length < n) _order = Int32List(math.max(n, _order.length * 2));
    final order = _order;
    var minD = double.infinity, maxD = double.negativeInfinity, floors = 0;
    for (var i = 0; i < n; i++) {
      final d = _triDepth[i];
      if (d == double.maxFinite) {
        floors++;
        continue;
      }
      if (d < minD) minD = d;
      if (d > maxD) maxD = d;
    }
    const buckets = 4096;
    final counts = Int32List(buckets + 1);
    final range = maxD - minD;
    int bucketOf(double d) => range <= 0 ? 0 : ((maxD - d) / range * (buckets - 1)).floor(); // 0 = farthest
    for (var i = 0; i < n; i++) {
      final d = _triDepth[i];
      if (d != double.maxFinite) counts[bucketOf(d) + 1]++;
    }
    for (var b = 0; b < buckets; b++) {
      counts[b + 1] += counts[b];
    }
    var floorAt = 0;
    for (var i = 0; i < n; i++) {
      final d = _triDepth[i];
      if (d == double.maxFinite) {
        order[floorAt++] = i;
      } else {
        order[floors + counts[bucketOf(d)]++] = i;
      }
    }
    return order;
  }

  static void _renderGroundGrid(Canvas canvas, Size size, Matrix4 viewProj, Vector3 camPos) {
    const gridExtents = 10.0;
    const gridSpacing = 1.0;

    final gridPaint = Paint()
      ..color = const Color(0xFF222630)
      ..strokeWidth = 1.0;

    final xAxisPaint = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.8) // Red X
      ..strokeWidth = 1.5;

    final zAxisPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.8) // Blue Z
      ..strokeWidth = 1.5;

    // Draw lines along X and Z
    for (double i = -gridExtents; i <= gridExtents; i += gridSpacing) {
      // Parallel to X axis (varies in X, constant Z)
      final p0 = _projectPoint(Vector3(-gridExtents, 0.0, i), viewProj, size);
      final p1 = _projectPoint(Vector3(gridExtents, 0.0, i), viewProj, size);
      if (p0 != null && p1 != null) {
        canvas.drawLine(p0, p1, (i.abs() < 0.001) ? xAxisPaint : gridPaint);
      }

      // Parallel to Z axis (varies in Z, constant X)
      final q0 = _projectPoint(Vector3(i, 0.0, -gridExtents), viewProj, size);
      final q1 = _projectPoint(Vector3(i, 0.0, gridExtents), viewProj, size);
      if (q0 != null && q1 != null) {
        canvas.drawLine(q0, q1, (i.abs() < 0.001) ? zAxisPaint : gridPaint);
      }
    }
  }

  static void _renderSelectionHighlight(Canvas canvas, EmberEntity? selected, Matrix4 viewProj, Size size) {
    if (selected == null) return;
    final t3d = selected.getComponent<Transform3DComponent>();
    final mr = selected.getComponent<MeshRenderer3DComponent>();
    if (t3d == null || mr == null) return;

    final bounds = mr.mesh.bounds;
    final worldMatrix = t3d.worldMatrix;

    // 8 Bounding box corners
    final corners = [
      Vector3(bounds.min.x, bounds.min.y, bounds.min.z),
      Vector3(bounds.max.x, bounds.min.y, bounds.min.z),
      Vector3(bounds.max.x, bounds.max.y, bounds.min.z),
      Vector3(bounds.min.x, bounds.max.y, bounds.min.z),
      Vector3(bounds.min.x, bounds.min.y, bounds.max.z),
      Vector3(bounds.max.x, bounds.min.y, bounds.max.z),
      Vector3(bounds.max.x, bounds.max.y, bounds.max.z),
      Vector3(bounds.min.x, bounds.max.y, bounds.max.z),
    ];

    final screenCorners = <Offset?>[];
    for (final c in corners) {
      final wPos4 = worldMatrix * Vector4(c.x, c.y, c.z, 1.0);
      final wPos = Vector3(wPos4.x, wPos4.y, wPos4.z);
      screenCorners.add(_projectPoint(wPos, viewProj, size));
    }

    final outlinePaint = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha: 0.85) // Ember Indigo
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Connect 12 edges
    final edges = [
      [0, 1], [1, 2], [2, 3], [3, 0],
      [4, 5], [5, 6], [6, 7], [7, 4],
      [0, 4], [1, 5], [2, 6], [3, 7],
    ];

    for (final edge in edges) {
      final pA = screenCorners[edge[0]];
      final pB = screenCorners[edge[1]];
      if (pA != null && pB != null) {
        canvas.drawLine(pA, pB, outlinePaint);
      }
    }
  }

  /// Minimum clip-space w kept after near-plane clipping.
  static const double _nearW = 0.05;

  static Offset _toScreen(Vector4 clip, Size size) {
    final invW = 1.0 / clip.w;
    return Offset(
      (clip.x * invW + 1.0) * 0.5 * size.width,
      (1.0 - clip.y * invW) * 0.5 * size.height,
    );
  }

  /// Sutherland–Hodgman clip of a convex clip-space polygon against w > [_nearW].
  static List<Vector4> _clipNear(List<Vector4> poly) {
    final out = <Vector4>[];
    for (int i = 0; i < poly.length; i++) {
      final cur = poly[i];
      final prev = poly[(i + poly.length - 1) % poly.length];
      final curIn = cur.w > _nearW;
      final prevIn = prev.w > _nearW;
      if (curIn != prevIn) {
        final t = (_nearW - prev.w) / (cur.w - prev.w);
        out.add(prev + (cur - prev) * t);
      }
      if (curIn) out.add(cur);
    }
    return out;
  }

  static Offset? _projectPoint(Vector3 point, Matrix4 viewProj, Size size) {
    final clip = viewProj * Vector4(point.x, point.y, point.z, 1.0);
    if (clip.w <= 0.05) return null;

    final invW = 1.0 / clip.w;
    final ndcX = clip.x * invW;
    final ndcY = clip.y * invW;

    final sx = (ndcX + 1.0) * 0.5 * size.width;
    final sy = (1.0 - ndcY) * 0.5 * size.height;

    return Offset(sx, sy);
  }
}

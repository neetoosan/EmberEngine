import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import '../combat/combat.dart';
import '../two_d/camera_room.dart';
import '../two_d/flame_components.dart';
import 'ui_widgets.dart';

/// A small map of a tilemap on the screen. Places are revealed as the
/// [target] explores them: the whole Camera Room it walks into, or the cells
/// within [revealRadius]. Entities with a tag in [markers] show as coloured
/// dots once seen (save points, items, bosses). Scripts can save what was
/// explored with `minimap.explored` and set it back later.
class UIMinimapComponent extends EmberComponent with UILayout {
  String tilemap;
  String target;
  double revealRadius;
  bool fog;
  Color wallColor;
  Color floorColor;
  Color backColor;
  Color playerColor;

  /// `tag:#RRGGBB` pairs separated by commas, e.g. `save:#22D3EE, item:#FBBF24`.
  String markers;

  Uint8List _seen = Uint8List(0);
  int _cols = 0, _rows = 0;
  int _seenRevision = 0;
  Picture? _cache;
  int _cacheKey = -1;
  double _blink = 0;

  UIMinimapComponent({
    this.tilemap = 'Map',
    this.target = 'Player',
    this.revealRadius = 6,
    this.fog = true,
    this.wallColor = const Color(0xFFE2E8F0),
    this.floorColor = const Color(0x332DD4BF),
    this.backColor = const Color(0xB0080B18),
    this.playerColor = const Color(0xFFF97316),
    this.markers = '',
    EmberAnchor anchor = EmberAnchor.topRight,
    vm.Vector2? offset,
    vm.Vector2? size,
  }) {
    this.anchor = anchor;
    this.offset = offset ?? vm.Vector2(-16, 16);
    this.size = size ?? vm.Vector2(200, 100);
  }

  FlameTileMapComponent? _map() => entity?.scene?.findEntityByName(tilemap)?.getComponent<FlameTileMapComponent>();

  void _ensure(FlameTileMapComponent m) {
    if (m.columns == _cols && m.rows == _rows) return;
    _cols = m.columns;
    _rows = m.rows;
    _seen = Uint8List(_cols * _rows);
    _seenRevision++;
  }

  /// Marks the cells under [area] (world space) as seen.
  void revealRect(Rect area) {
    final m = _map();
    if (m == null) return;
    _ensure(m);
    final cell = m.cellRect(0, 0);
    if (cell.width <= 0) return;
    final c0 = ((area.left - cell.left) / cell.width).floor().clamp(0, _cols - 1);
    final c1 = ((area.right - cell.left) / cell.width).ceil().clamp(1, _cols) - 1;
    final r0 = ((area.top - cell.top) / cell.height).floor().clamp(0, _rows - 1);
    final r1 = ((area.bottom - cell.top) / cell.height).ceil().clamp(1, _rows) - 1;
    var changed = false;
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        if (_seen[r * _cols + c] == 0) {
          _seen[r * _cols + c] = 1;
          changed = true;
        }
      }
    }
    if (changed) _seenRevision++;
  }

  void revealAll() {
    final m = _map();
    if (m == null) return;
    _ensure(m);
    _seen.fillRange(0, _seen.length, 1);
    _seenRevision++;
  }

  /// Share of the map seen so far, 0 .. 1.
  double get exploredFraction => _seen.isEmpty ? 0 : _seen.where((v) => v != 0).length / _seen.length;

  bool seenAt(int col, int row) => !fog || (col >= 0 && row >= 0 && col < _cols && row < _rows && _seen[row * _cols + col] != 0);

  /// What was explored, as short text for saving ("12x0,30x1,...").
  String get explored {
    if (_seen.isEmpty) return '';
    final out = StringBuffer();
    var run = 0, value = _seen[0];
    for (final v in _seen) {
      if (v == value) {
        run++;
      } else {
        out.write('${run}x$value,');
        run = 1;
        value = v;
      }
    }
    out.write('${run}x$value');
    return out.toString();
  }

  set explored(String data) {
    final m = _map();
    if (m == null) return;
    _ensure(m);
    var i = 0;
    for (final part in data.split(',')) {
      final bits = part.split('x');
      if (bits.length != 2) continue;
      final n = int.tryParse(bits[0]) ?? 0, v = int.tryParse(bits[1]) ?? 0;
      for (var k = 0; k < n && i < _seen.length; k++) {
        _seen[i++] = v;
      }
    }
    _seenRevision++;
  }

  Offset? _targetCenter() {
    final e = entity?.scene?.findEntityByName(target);
    if (e == null || !e.enabled) return null;
    return Combat.bodyOf(e).center;
  }

  @override
  void onUpdate(double dt) {
    _blink += dt;
    final scene = entity?.scene;
    final p = _targetCenter();
    if (scene == null || p == null || !fog) return;
    final room = CameraRoom2DComponent.at(scene, p);
    if (room != null) {
      revealRect(room.rect);
    } else {
      final m = _map();
      if (m == null) return;
      final cw = m.cellRect(0, 0).width;
      revealRect(Rect.fromCircle(center: p, radius: revealRadius * cw));
    }
  }

  void paint(Canvas canvas, Rect view, double scale, EmberScene scene) {
    final m = _map();
    if (m == null) return;
    _ensure(m);
    final r = layoutRect(view, scale);
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(8 * scale)), Paint()..color = backColor);
    final cell = math.min((r.width - 8 * scale) / m.columns, (r.height - 8 * scale) / m.rows);
    if (cell <= 0) return;
    final origin = Offset(r.center.dx - cell * m.columns / 2, r.center.dy - cell * m.rows / 2);

    // The tiles change rarely: draw them into a cached picture
    final key = Object.hash(_seenRevision, m.revision, fog);
    if (_cache == null || _cacheKey != key) {
      final rec = PictureRecorder();
      final c = Canvas(rec);
      final wall = Paint()..color = wallColor;
      final floor = Paint()..color = floorColor;
      for (var row = 0; row < m.rows; row++) {
        for (var col = 0; col < m.columns; col++) {
          if (!seenAt(col, row)) continue;
          final id = m.getTile(col, row);
          final solid = id > 0 && m.kindOf(id).blocks;
          c.drawRect(Rect.fromLTWH(col.toDouble(), row.toDouble(), 1.02, 1.02), solid ? wall : floor);
        }
      }
      _cache = rec.endRecording();
      _cacheKey = key;
    }
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(8 * scale)));
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(cell, cell);
    canvas.drawPicture(_cache!);
    canvas.restore();

    final grid = m.cellRect(0, 0);
    Offset toMap(Offset world) => origin + Offset((world.dx - grid.left) / grid.width * cell, (world.dy - grid.top) / grid.height * cell);
    bool seenWorld(Offset world) => seenAt(((world.dx - grid.left) / grid.width).floor(), ((world.dy - grid.top) / grid.height).floor());

    for (final entry in markers.split(',')) {
      final parts = entry.trim().split(':');
      if (parts.length != 2) continue;
      final hex = parts[1].trim().replaceAll('#', '');
      final color = Color(int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16) ?? 0xFFFFFFFF);
      final dot = Paint()..color = color;
      for (final e in scene.allEntities) {
        if (!e.enabled || !e.tags.contains(parts[0].trim()) || !e.hasComponent<Transform2DComponent>()) continue;
        final at = Combat.bodyOf(e).center;
        if (!seenWorld(at)) continue;
        canvas.drawCircle(toMap(at), math.max(2.0, cell * 0.9), dot);
      }
    }
    final p = _targetCenter();
    if (p != null && (_blink * 2.5) % 1 < 0.75) {
      canvas.drawCircle(toMap(p), math.max(2.5, cell * 1.1), Paint()..color = playerColor);
    }
  }

  @override
  String get displayName => 'UI Minimap';

  InspectableProperty<T> _prop<T>(String name, String label, InspectableType type, T Function() get, void Function(T) set,
          {String? tooltip, double? min, double step = 1}) =>
      InspectableProperty<T>(
          name: name,
          label: label,
          type: type,
          getter: get,
          setter: (v) {
            set(v);
            notifyListeners();
          },
          tooltip: tooltip,
          min: min,
          step: step);

  @override
  List<InspectableProperty> get inspectableProperties => [
        _prop<String>('tilemap', 'TileMap Entity', InspectableType.string, () => tilemap, (v) => tilemap = v),
        _prop<String>('target', 'Follow Entity', InspectableType.string, () => target, (v) => target = v, tooltip: 'Who explores (usually the player)'),
        _prop<bool>('fog', 'Fog (reveal as explored)', InspectableType.boolean, () => fog, (v) => fog = v),
        _prop<double>('revealRadius', 'Reveal Radius (cells)', InspectableType.number, () => revealRadius, (v) => revealRadius = v, min: 0,
            tooltip: 'Used outside Camera Rooms'),
        _prop<String>('markers', 'Markers', InspectableType.string, () => markers, (v) => markers = v,
            tooltip: 'tag:#RRGGBB pairs, e.g. save:#22D3EE, item:#FBBF24'),
        _prop<Color>('wallColor', 'Wall Color', InspectableType.color, () => wallColor, (v) => wallColor = v),
        _prop<Color>('floorColor', 'Open Color', InspectableType.color, () => floorColor, (v) => floorColor = v),
        _prop<Color>('playerColor', 'Player Color', InspectableType.color, () => playerColor, (v) => playerColor = v),
        ...layoutProperties,
      ];

  @override
  Map<String, dynamic> toJson() => {
        ...layoutJson(),
        'tilemap': tilemap,
        'target': target,
        'revealRadius': revealRadius,
        'fog': fog,
        'wallColor': wallColor.toARGB32(),
        'floorColor': floorColor.toARGB32(),
        'backColor': backColor.toARGB32(),
        'playerColor': playerColor.toARGB32(),
        'markers': markers,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    readLayout(json);
    tilemap = json['tilemap'] as String? ?? 'Map';
    target = json['target'] as String? ?? 'Player';
    revealRadius = (json['revealRadius'] as num?)?.toDouble() ?? 6;
    fog = json['fog'] as bool? ?? true;
    wallColor = Color(json['wallColor'] as int? ?? 0xFFE2E8F0);
    floorColor = Color(json['floorColor'] as int? ?? 0x332DD4BF);
    backColor = Color(json['backColor'] as int? ?? 0xB0080B18);
    playerColor = Color(json['playerColor'] as int? ?? 0xFFF97316);
    markers = json['markers'] as String? ?? '';
    notifyListeners();
  }

  @override
  UIMinimapComponent clone() => UIMinimapComponent()..fromJson(toJson());
}

void _paintMinimaps(Canvas canvas, Rect view, double scale, EmberScene scene) {
  for (final m in scene.componentsOf<UIMinimapComponent>()) {
    if (m.enabled && (m.entity?.enabled ?? false)) m.paint(canvas, view, scale, scene);
  }
}

void registerMinimap() {
  ComponentRegistry.register('UI Minimap', (json) => UIMinimapComponent()..fromJson(json));
  if (!UIRenderer.extraPainters.contains(_paintMinimaps)) UIRenderer.extraPainters.add(_paintMinimaps);
}

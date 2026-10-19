import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/transform2d.dart';

/// 2D Sprite component rendered in Flame or custom 2D canvas.
class FlameSpriteComponent extends EmberComponent {
  String _assetPath;
  Color _tint;
  bool _flipX;
  bool _flipY;
  double _opacity;

  /// Sprite-sheet layout: the image is split into [columns] × [rows] equal
  /// cells and [frame] (row-major, from 0) is drawn. 1 × 1 draws the whole image.
  int columns;
  int rows;
  int _frame;

  /// Smooth (bilinear) scaling; off keeps pixel art crisp.
  bool smooth;

  /// Adds its colours to what is behind it, like light: glows, lasers, fire.
  bool additive;

  /// A white flash over the sprite, 0 (none) .. 1 (fully white). Set by
  /// Health's white hit flash; not saved.
  double flash = 0;

  FlameSpriteComponent({
    this._assetPath = 'assets/sprites/default_character.png',
    this._tint = Colors.white,
    this._flipX = false,
    this._flipY = false,
    this._opacity = 1.0,
    this.columns = 1,
    this.rows = 1,
    this._frame = 0,
    this.smooth = false,
    this.additive = false,
  });

  int get frameCount => (columns < 1 ? 1 : columns) * (rows < 1 ? 1 : rows);

  int get frame => _frame;
  set frame(int val) {
    final f = val % frameCount;
    if (f == _frame) return;
    _frame = f;
    notifyListeners();
  }

  String get assetPath => _assetPath;
  set assetPath(String val) {
    _assetPath = val;
    notifyListeners();
  }

  Color get tint => _tint;
  set tint(Color val) {
    _tint = val;
    notifyListeners();
  }

  bool get flipX => _flipX;
  set flipX(bool val) {
    _flipX = val;
    notifyListeners();
  }

  bool get flipY => _flipY;
  set flipY(bool val) {
    _flipY = val;
    notifyListeners();
  }

  double get opacity => _opacity;
  set opacity(double val) {
    _opacity = val.clamp(0.0, 1.0);
    notifyListeners();
  }

  @override
  String get displayName => 'Flame Sprite';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'assetPath',
          label: 'Sprite Asset',
          type: InspectableType.string,
          getter: () => _assetPath,
          setter: (val) => assetPath = val,
          tooltip: 'Path to sprite texture image',
        ),
        InspectableProperty<Color>(
          name: 'tint',
          label: 'Tint Color',
          type: InspectableType.color,
          getter: () => _tint,
          setter: (val) => tint = val,
          tooltip: 'Multiplicative color tint',
        ),
        InspectableProperty<double>(
          name: 'opacity',
          label: 'Opacity',
          type: InspectableType.number,
          getter: () => _opacity,
          setter: (val) => opacity = val,
          min: 0.0,
          max: 1.0,
          step: 0.05,
          tooltip: 'Transparency factor (0.0 to 1.0)',
        ),
        InspectableProperty<bool>(
          name: 'flipX',
          label: 'Flip Horizontal',
          type: InspectableType.boolean,
          getter: () => _flipX,
          setter: (val) => flipX = val,
        ),
        InspectableProperty<bool>(
          name: 'flipY',
          label: 'Flip Vertical',
          type: InspectableType.boolean,
          getter: () => _flipY,
          setter: (val) => flipY = val,
        ),
        InspectableProperty<int>(
          name: 'columns',
          label: 'Sheet Columns',
          type: InspectableType.integer,
          getter: () => columns,
          setter: (val) {
            columns = val.clamp(1, 64);
            notifyListeners();
          },
          min: 1,
          max: 64,
          step: 1,
        ),
        InspectableProperty<int>(
          name: 'rows',
          label: 'Sheet Rows',
          type: InspectableType.integer,
          getter: () => rows,
          setter: (val) {
            rows = val.clamp(1, 64);
            notifyListeners();
          },
          min: 1,
          max: 64,
          step: 1,
        ),
        InspectableProperty<int>(
          name: 'frame',
          label: 'Frame',
          type: InspectableType.integer,
          getter: () => _frame,
          setter: (val) => frame = val,
          min: 0,
          step: 1,
        ),
        InspectableProperty<bool>(
          name: 'smooth',
          label: 'Smooth Scaling',
          type: InspectableType.boolean,
          getter: () => smooth,
          setter: (val) {
            smooth = val;
            notifyListeners();
          },
          tooltip: 'Off keeps pixel art crisp',
        ),
        InspectableProperty<bool>(
          name: 'additive',
          label: 'Glow (additive)',
          type: InspectableType.boolean,
          getter: () => additive,
          setter: (val) {
            additive = val;
            notifyListeners();
          },
          tooltip: 'Bright colours add up like light (glows, lasers, fire)',
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'assetPath': _assetPath,
      'tint': _tint.toARGB32(),
      'flipX': _flipX,
      'flipY': _flipY,
      'opacity': _opacity,
      'columns': columns,
      'rows': rows,
      'frame': _frame,
      'smooth': smooth,
      if (additive) 'additive': true,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    _assetPath = json['assetPath'] as String? ?? 'assets/sprites/default_character.png';
    _tint = Color(json['tint'] as int? ?? Colors.white.toARGB32());
    _flipX = json['flipX'] as bool? ?? false;
    _flipY = json['flipY'] as bool? ?? false;
    _opacity = (json['opacity'] as num?)?.toDouble() ?? 1.0;
    columns = (json['columns'] as num?)?.toInt() ?? 1;
    rows = (json['rows'] as num?)?.toInt() ?? 1;
    _frame = (json['frame'] as num?)?.toInt() ?? 0;
    smooth = json['smooth'] as bool? ?? false;
    additive = json['additive'] as bool? ?? false;
    notifyListeners();
  }

  @override
  FlameSpriteComponent clone() {
    return FlameSpriteComponent(
      assetPath: _assetPath,
      tint: _tint,
      flipX: _flipX,
      flipY: _flipY,
      opacity: _opacity,
      columns: columns,
      rows: rows,
      frame: _frame,
      smooth: smooth,
      additive: additive,
    );
  }
}

/// Supported collision shapes for 2D hitboxes.
enum Hitbox2DShape {
  rectangle,
  circle,
}

/// 2D Collision Hitbox component.
class FlameHitbox2DComponent extends EmberComponent {
  Hitbox2DShape _shape;
  vm.Vector2 _size;
  vm.Vector2 _offset;
  bool _isSolid;
  bool _debugDraw;

  FlameHitbox2DComponent({
    this._shape = Hitbox2DShape.rectangle,
    vm.Vector2? size,
    vm.Vector2? offset,
    this._isSolid = true,
    this._debugDraw = true,
  })  : _size = size ?? vm.Vector2(32.0, 32.0),
        _offset = offset ?? vm.Vector2.zero();

  Hitbox2DShape get shape => _shape;
  set shape(Hitbox2DShape val) {
    _shape = val;
    notifyListeners();
  }

  vm.Vector2 get size => _size;
  set size(vm.Vector2 val) {
    _size = val;
    notifyListeners();
  }

  vm.Vector2 get offset => _offset;
  set offset(vm.Vector2 val) {
    _offset = val;
    notifyListeners();
  }

  bool get isSolid => _isSolid;
  set isSolid(bool val) {
    _isSolid = val;
    notifyListeners();
  }

  bool get debugDraw => _debugDraw;
  set debugDraw(bool val) {
    _debugDraw = val;
    notifyListeners();
  }

  @override
  String get displayName => 'Flame Hitbox 2D';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<Hitbox2DShape>(
          name: 'shape',
          label: 'Hitbox Shape',
          type: InspectableType.options,
          getter: () => _shape,
          setter: (val) => shape = val,
          options: Hitbox2DShape.values.map((s) => s.name).toList(),
          tooltip: 'Shape of the collision bounding volume',
        ),
        InspectableProperty<vm.Vector2>(
          name: 'size',
          label: 'Dimensions',
          type: InspectableType.vector2,
          getter: () => _size,
          setter: (val) => size = val,
          step: 1.0,
          tooltip: 'Width and height of hitbox',
        ),
        InspectableProperty<vm.Vector2>(
          name: 'offset',
          label: 'Offset',
          type: InspectableType.vector2,
          getter: () => _offset,
          setter: (val) => offset = val,
          step: 1.0,
          tooltip: 'Offset from entity transform anchor',
        ),
        InspectableProperty<bool>(
          name: 'isSolid',
          label: 'Solid Collider',
          type: InspectableType.boolean,
          getter: () => _isSolid,
          setter: (val) => isSolid = val,
          tooltip: 'Blocks kinematic characters if true, otherwise trigger only',
        ),
        InspectableProperty<bool>(
          name: 'debugDraw',
          label: 'Draw Debug Outline',
          type: InspectableType.boolean,
          getter: () => _debugDraw,
          setter: (val) => debugDraw = val,
          tooltip: 'Renders green/red outline in viewport',
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'shape': _shape.name,
      'size': [_size.x, _size.y],
      'offset': [_offset.x, _offset.y],
      'isSolid': _isSolid,
      'debugDraw': _debugDraw,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    final sName = json['shape'] as String? ?? 'rectangle';
    _shape = Hitbox2DShape.values.firstWhere(
      (s) => s.name == sName,
      orElse: () => Hitbox2DShape.rectangle,
    );
    if (json.containsKey('size')) {
      final s = json['size'] as List<dynamic>;
      _size = vm.Vector2((s[0] as num).toDouble(), (s[1] as num).toDouble());
    }
    if (json.containsKey('offset')) {
      final o = json['offset'] as List<dynamic>;
      _offset = vm.Vector2((o[0] as num).toDouble(), (o[1] as num).toDouble());
    }
    _isSolid = json['isSolid'] as bool? ?? true;
    _debugDraw = json['debugDraw'] as bool? ?? true;
    notifyListeners();
  }

  @override
  FlameHitbox2DComponent clone() {
    return FlameHitbox2DComponent(
      shape: _shape,
      size: _size.clone(),
      offset: _offset.clone(),
      isSolid: _isSolid,
      debugDraw: _debugDraw,
    );
  }
}

/// How a tile behaves for characters. Tile ID 0 is always empty.
enum TileKind {
  /// Blocks from every side (ground, walls).
  solid,

  /// Drawn but not collidable (background decoration).
  decoration,

  /// Stand on it from above; jump up through it.
  oneWay,

  /// Not solid; characters touching it get `onTileTouch` (spikes, lava).
  hazard,

  /// Solid; scripts usually break it when bumped from below.
  breakable,

  /// Solid "?" block; scripts usually give a reward when bumped from below.
  question,

  /// Solid block that was already used (e.g. an emptied "?" block).
  usedBlock;

  bool get blocks => this != decoration && this != hazard && this != oneWay;
}

/// A tile found by a tilemap query.
class TileHit {
  final FlameTileMapComponent map;
  final int col;
  final int row;
  final int tileId;
  final TileKind kind;

  /// World-space rectangle of the tile.
  final Rect rect;

  const TileHit(this.map, this.col, this.row, this.tileId, this.kind, this.rect);

  /// Replaces this tile (0 removes it), e.g. to break a brick or empty a "?" block.
  void setTile(int id) => map.setTile(col, row, id);
}

/// 2D TileMap grid component.
///
/// Tiles are drawn from [tilesetPath] (an image cut into [tilesetColumns]
/// columns of [tilesetTileSize]-pixel cells; tile ID n uses cell n-1) or as
/// coloured blocks when no tileset is set. [tileKinds] gives each ID its
/// behaviour; IDs not listed are [TileKind.solid].
class FlameTileMapComponent extends EmberComponent {
  int _columns;
  int _rows;
  double _tileSize;
  late List<int> _tiles;

  String tilesetPath;
  int tilesetColumns;
  int tilesetTileSize;
  final Map<int, TileKind> tileKinds;

  /// Whether characters collide with this layer. Turn off for decoration
  /// layers (e.g. tree tops drawn above the player with a higher Z-Index).
  bool collision;

  /// Smooth (bilinear) scaling of the tileset, for painted tiles drawn
  /// smaller or larger than they were made. Off keeps pixel art crisp.
  bool smooth;

  /// "square" (the default), "isometric" (diamonds 2 × tile size wide and
  /// 1 × tall, for city builders and strategy) or "hex" (pointy-top hexagons
  /// tile size wide, odd rows shifted half a hex right). Tileset cells are
  /// drawn with their bottom on the bottom of the cell, so tall tiles (trees,
  /// walls) stick up; they are drawn back to front.
  String layout;

  /// Rows in the tileset image for isometric / hex maps, whose tile images
  /// need not be square (0: square cells).
  int tilesetRows = 0;

  /// Cells scripts marked as blocked for [findPath] (buildings, units). Not saved.
  final Set<int> blockedCells = {};

  FlameTileMapComponent({
    this._columns = 16,
    this._rows = 12,
    this._tileSize = 32.0,
    List<int>? tiles,
    this.tilesetPath = '',
    this.tilesetColumns = 8,
    this.tilesetTileSize = 16,
    Map<int, TileKind>? tileKinds,
    this.collision = true,
    this.smooth = false,
    this.layout = 'square',
  }) : tileKinds = tileKinds ?? {} {
    _tiles = tiles ?? List.filled(_columns * _rows, 0);
  }

  int get columns => _columns;
  set columns(int val) {
    if (val <= 0 || val == _columns) return;
    _resizeGrid(val, _rows);
    notifyListeners();
  }

  int get rows => _rows;
  set rows(int val) {
    if (val <= 0 || val == _rows) return;
    _resizeGrid(_columns, val);
    notifyListeners();
  }

  TileKind kindOf(int tileId) => tileKinds[tileId] ?? TileKind.solid;

  void setKind(int tileId, TileKind kind) {
    if (kind == TileKind.solid) {
      tileKinds.remove(tileId);
    } else {
      tileKinds[tileId] = kind;
    }
    notifyListeners();
  }

  /// World-space origin (top-left corner of cell 0,0) and tile size.
  (double, double, double) _worldGrid() {
    final t = entity?.getComponent<Transform2DComponent>();
    if (t == null) return (0, 0, _tileSize);
    final o = t.worldPosition - t.anchorOffset;
    return (o.x, o.y, _tileSize * t.worldScale.x);
  }

  /// Every non-empty tile whose rectangle overlaps [area] (world space).
  /// Only the cells under [area] are visited, so this is cheap on huge maps.
  List<TileHit> tilesIn(Rect area) {
    final (ox, oy, ts) = _worldGrid();
    if (ts <= 0) return const [];
    final c0 = ((area.left - ox) / ts).floor().clamp(0, _columns - 1);
    final c1 = ((area.right - ox) / ts).floor().clamp(0, _columns - 1);
    final r0 = ((area.top - oy) / ts).floor().clamp(0, _rows - 1);
    final r1 = ((area.bottom - oy) / ts).floor().clamp(0, _rows - 1);
    if (area.right < ox || area.bottom < oy || area.left > ox + _columns * ts || area.top > oy + _rows * ts) {
      return const [];
    }
    final hits = <TileHit>[];
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        final id = _tiles[r * _columns + c];
        if (id <= 0) continue;
        hits.add(TileHit(this, c, r, id, kindOf(id), Rect.fromLTWH(ox + c * ts, oy + r * ts, ts, ts)));
      }
    }
    return hits;
  }

  /// World-space rectangle of cell ([col], [row]).
  Rect cellRect(int col, int row) {
    final (ox, oy, ts) = _worldGrid();
    if (layout == 'isometric') {
      final c = isoCenter(col, row, ts);
      return Rect.fromCenter(center: Offset(ox + c.dx, oy + c.dy), width: ts * 2, height: ts);
    }
    if (layout == 'hex') {
      final c = hexCenter(col, row, ts);
      return Rect.fromCenter(center: Offset(ox + c.dx, oy + c.dy), width: ts, height: ts * _hexHeight);
    }
    return Rect.fromLTWH(ox + col * ts, oy + row * ts, ts, ts);
  }

  static const double _hexHeight = 1.1547005383792515; // 2 / sqrt(3)

  /// Centre of an isometric cell in local space ([ts] = tile size).
  Offset isoCenter(int col, int row, double ts) => Offset((col - row) * ts + _rows * ts, (col + row) * ts / 2 + ts / 2);

  /// Centre of a hex cell in local space.
  Offset hexCenter(int col, int row, double ts) => Offset(col * ts + ts / 2 + (row.isOdd ? ts / 2 : 0), row * ts * _hexHeight * 0.75 + ts * _hexHeight / 2);

  /// Size of the whole map in local space.
  Size get extent {
    final ts = _tileSize;
    if (layout == 'isometric') return Size((_columns + _rows) * ts, (_columns + _rows) * ts / 2);
    if (layout == 'hex') return Size(_columns * ts + ts / 2, (_rows - 1) * ts * _hexHeight * 0.75 + ts * _hexHeight);
    return Size(_columns * ts, _rows * ts);
  }

  /// Grid cell under a world position, or null if outside the map.
  (int, int)? cellAt(double worldX, double worldY) {
    final (ox, oy, ts) = _worldGrid();
    final x = worldX - ox, y = worldY - oy;
    int c, r;
    if (layout == 'isometric') {
      final u = (x - _rows * ts) / ts, v = y / (ts / 2);
      c = ((v + u) / 2).floor();
      r = ((v - u) / 2).floor();
    } else if (layout == 'hex') {
      // The nearest hex centre (hexes are exactly the cells nearest their centre)
      final guess = (y / (ts * _hexHeight * 0.75)).floor();
      var best = (-1, -1);
      var bestD = double.infinity;
      for (var rr = guess - 1; rr <= guess + 1; rr++) {
        final cc0 = ((x - (rr.isOdd ? ts / 2 : 0)) / ts).floor();
        for (var cc = cc0 - 1; cc <= cc0 + 1; cc++) {
          final p = hexCenter(cc, rr, ts);
          final d = (p.dx - x) * (p.dx - x) + (p.dy - y) * (p.dy - y);
          if (d < bestD) {
            bestD = d;
            best = (cc, rr);
          }
        }
      }
      (c, r) = best;
    } else {
      c = (x / ts).floor();
      r = (y / ts).floor();
    }
    if (c < 0 || r < 0 || c >= _columns || r >= _rows) return null;
    return (c, r);
  }

  /// Neighbouring cells: 4 on square and isometric maps, 6 on hex maps.
  List<(int, int)> neighbours(int col, int row) {
    final List<(int, int)> d;
    if (layout == 'hex') {
      d = row.isOdd ? const [(1, 0), (-1, 0), (0, -1), (1, -1), (0, 1), (1, 1)] : const [(1, 0), (-1, 0), (-1, -1), (0, -1), (-1, 1), (0, 1)];
    } else {
      d = const [(1, 0), (-1, 0), (0, 1), (0, -1)];
    }
    return [
      for (final (dc, dr) in d)
        if (col + dc >= 0 && row + dr >= 0 && col + dc < _columns && row + dr < _rows) (col + dc, row + dr),
    ];
  }

  bool isWalkable(int col, int row) {
    if (col < 0 || row < 0 || col >= _columns || row >= _rows) return false;
    if (blockedCells.contains(row * _columns + col)) return false;
    final id = _tiles[row * _columns + col];
    return id > 0 && !kindOf(id).blocks;
  }

  /// The shortest walk between two cells over walkable tiles (A*), from the
  /// first step to the goal, or null if there is none. Empty tiles (id 0) and
  /// solid tiles block, and so do [blockedCells].
  List<(int, int)>? findPath(int c0, int r0, int c1, int r1, {int maxExpanded = 8000}) {
    if (!isWalkable(c1, r1)) return null;
    if (c0 == c1 && r0 == r1) return const [];
    int key(int c, int r) => r * _columns + c;
    double h(int c, int r) => ((c - c1).abs() + (r - r1).abs()).toDouble();
    final g = <int, double>{key(c0, r0): 0};
    final from = <int, int>{};
    final open = <(double, int, int)>[(h(c0, r0), c0, r0)];
    final closed = <int>{};
    var expanded = 0;
    while (open.isNotEmpty) {
      var bi = 0;
      for (var i = 1; i < open.length; i++) {
        if (open[i].$1 < open[bi].$1) bi = i;
      }
      final (_, c, r) = open.removeAt(bi);
      final k = key(c, r);
      if (c == c1 && r == r1) break;
      if (!closed.add(k)) continue;
      if (++expanded > maxExpanded) return null;
      for (final (nc, nr) in neighbours(c, r)) {
        if (!isWalkable(nc, nr)) continue;
        final nk = key(nc, nr);
        final cost = g[k]! + 1;
        if (cost < (g[nk] ?? double.infinity)) {
          g[nk] = cost;
          from[nk] = k;
          open.add((cost + h(nc, nr), nc, nr));
        }
      }
    }
    final goal = key(c1, r1);
    if (!from.containsKey(goal)) return null;
    final out = <(int, int)>[];
    var cur = goal;
    while (cur != key(c0, r0)) {
      out.add((cur % _columns, cur ~/ _columns));
      cur = from[cur]!;
    }
    return out.reversed.toList();
  }

  double get tileSize => _tileSize;
  set tileSize(double val) {
    _tileSize = val.clamp(8.0, 128.0);
    notifyListeners();
  }

  List<int> get tiles => List.unmodifiable(_tiles);

  int getTile(int col, int row) {
    if (col < 0 || col >= _columns || row < 0 || row >= _rows) return 0;
    return _tiles[row * _columns + col];
  }

  /// Increments whenever tiles, size or tile kinds change (for caches such as pathfinding grids).
  int revision = 0;

  @override
  void notifyListeners() {
    revision++;
    super.notifyListeners();
  }

  void setTile(int col, int row, int tileId) {
    if (col < 0 || col >= _columns || row < 0 || row >= _rows) return;
    if (_tiles[row * _columns + col] == tileId) return;
    _tiles[row * _columns + col] = tileId;
    notifyListeners();
  }

  /// Replaces every tile at once ([tiles] is row by row, columns × rows long).
  void setTiles(List<int> tiles) {
    if (tiles.length != _columns * _rows) throw ArgumentError('expected ${_columns * _rows} tiles, got ${tiles.length}');
    _tiles = List<int>.of(tiles);
    notifyListeners();
  }

  /// Changes the grid size, keeping every tile at the same (column, row).
  void _resizeGrid(int newColumns, int newRows) {
    final newTiles = List.filled(newColumns * newRows, 0);
    for (int r = 0; r < newRows && r < _rows; r++) {
      for (int c = 0; c < newColumns && c < _columns; c++) {
        newTiles[r * newColumns + c] = _tiles[r * _columns + c];
      }
    }
    _columns = newColumns;
    _rows = newRows;
    _tiles = newTiles;
  }

  @override
  String get displayName => 'Flame TileMap';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<int>(
          name: 'columns',
          label: 'Grid Columns',
          type: InspectableType.integer,
          getter: () => _columns,
          setter: (val) => columns = val,
          min: 1,
          max: 128,
          step: 1,
        ),
        InspectableProperty<int>(
          name: 'rows',
          label: 'Grid Rows',
          type: InspectableType.integer,
          getter: () => _rows,
          setter: (val) => rows = val,
          min: 1,
          max: 128,
          step: 1,
        ),
        InspectableProperty<double>(
          name: 'tileSize',
          label: 'Tile Size (px)',
          type: InspectableType.number,
          getter: () => _tileSize,
          setter: (val) => tileSize = val,
          min: 8.0,
          max: 128.0,
          step: 8.0,
        ),
        InspectableProperty<String>(
          name: 'tilesetPath',
          label: 'Tileset Image',
          type: InspectableType.string,
          getter: () => tilesetPath,
          setter: (val) {
            tilesetPath = val;
            notifyListeners();
          },
          tooltip: 'assets/... image; tile ID n uses cell n-1',
        ),
        InspectableProperty<int>(
          name: 'tilesetColumns',
          label: 'Tileset Columns',
          type: InspectableType.integer,
          getter: () => tilesetColumns,
          setter: (val) {
            tilesetColumns = val.clamp(1, 256);
            notifyListeners();
          },
          min: 1,
          step: 1,
        ),
        InspectableProperty<int>(
          name: 'tilesetTileSize',
          label: 'Tileset Cell (px)',
          type: InspectableType.integer,
          getter: () => tilesetTileSize,
          setter: (val) {
            tilesetTileSize = val.clamp(1, 512);
            notifyListeners();
          },
          min: 1,
          step: 1,
        ),
        InspectableProperty<bool>(
          name: 'collision',
          label: 'Collision Layer',
          type: InspectableType.boolean,
          getter: () => collision,
          setter: (val) {
            collision = val;
            notifyListeners();
          },
          tooltip: 'Off for decoration layers characters walk through',
        ),
        InspectableProperty<bool>(
          name: 'smooth',
          label: 'Smooth Scaling',
          type: InspectableType.boolean,
          getter: () => smooth,
          setter: (val) {
            smooth = val;
            notifyListeners();
          },
          tooltip: 'For painted tiles; off keeps pixel art crisp',
        ),
        InspectableProperty<String>(
          name: 'layout',
          label: 'Layout',
          type: InspectableType.options,
          options: const ['square', 'isometric', 'hex'],
          getter: () => layout,
          setter: (val) {
            layout = val;
            notifyListeners();
          },
          tooltip: 'square, isometric (strategy, city builders) or hex',
        ),
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'collision': collision,
      if (smooth) 'smooth': true,
      if (layout != 'square') 'layout': layout,
      if (tilesetRows > 0) 'tilesetRows': tilesetRows,
      'columns': _columns,
      'rows': _rows,
      'tileSize': _tileSize,
      'tiles': _tiles,
      if (tilesetPath.isNotEmpty) 'tilesetPath': tilesetPath,
      'tilesetColumns': tilesetColumns,
      'tilesetTileSize': tilesetTileSize,
      if (tileKinds.isNotEmpty) 'tileKinds': {for (final e in tileKinds.entries) '${e.key}': e.value.name},
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    _columns = json['columns'] as int? ?? 16;
    _rows = json['rows'] as int? ?? 12;
    _tileSize = (json['tileSize'] as num?)?.toDouble() ?? 32.0;
    final rawTiles = json['tiles'] as List<dynamic>?;
    if (rawTiles != null && rawTiles.length == _columns * _rows) {
      _tiles = rawTiles.map((e) => (e as num).toInt()).toList();
    } else {
      _tiles = List.filled(_columns * _rows, 0);
    }
    collision = json['collision'] as bool? ?? true;
    smooth = json['smooth'] as bool? ?? false;
    layout = json['layout'] as String? ?? 'square';
    tilesetRows = (json['tilesetRows'] as num?)?.toInt() ?? 0;
    tilesetPath = json['tilesetPath'] as String? ?? '';
    tilesetColumns = (json['tilesetColumns'] as num?)?.toInt() ?? 8;
    tilesetTileSize = (json['tilesetTileSize'] as num?)?.toInt() ?? 16;
    tileKinds.clear();
    final kinds = json['tileKinds'];
    if (kinds is Map) {
      for (final e in kinds.entries) {
        final id = int.tryParse('${e.key}');
        final kind = TileKind.values.where((k) => k.name == e.value).firstOrNull;
        if (id != null && kind != null) tileKinds[id] = kind;
      }
    }
    notifyListeners();
  }

  @override
  FlameTileMapComponent clone() {
    return FlameTileMapComponent(
      columns: _columns,
      rows: _rows,
      tileSize: _tileSize,
      tiles: List<int>.from(_tiles),
      tilesetPath: tilesetPath,
      tilesetColumns: tilesetColumns,
      tilesetTileSize: tilesetTileSize,
      tileKinds: Map.of(tileKinds),
      collision: collision,
    );
  }
}

/// Register 2D Flame components into global ComponentRegistry.
void registerFlameComponents() {
  ComponentRegistry.register('Flame Sprite', (json) {
    final comp = FlameSpriteComponent();
    comp.fromJson(json);
    return comp;
  });

  ComponentRegistry.register('Flame Hitbox 2D', (json) {
    final comp = FlameHitbox2DComponent();
    comp.fromJson(json);
    return comp;
  });

  ComponentRegistry.register('Flame TileMap', (json) {
    final comp = FlameTileMapComponent();
    comp.fromJson(json);
    return comp;
  });
}

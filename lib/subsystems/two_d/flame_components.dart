import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';

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

/// 2D TileMap grid component.
class FlameTileMapComponent extends EmberComponent {
  int _columns;
  int _rows;
  double _tileSize;
  late List<int> _tiles;

  FlameTileMapComponent({
    this._columns = 16,
    this._rows = 12,
    this._tileSize = 32.0,
    List<int>? tiles,
  }) {
    _tiles = tiles ?? List.filled(_columns * _rows, 0);
  }

  int get columns => _columns;
  set columns(int val) {
    if (val <= 0) return;
    _columns = val;
    _resizeGrid();
    notifyListeners();
  }

  int get rows => _rows;
  set rows(int val) {
    if (val <= 0) return;
    _rows = val;
    _resizeGrid();
    notifyListeners();
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

  void setTile(int col, int row, int tileId) {
    if (col < 0 || col >= _columns || row < 0 || row >= _rows) return;
    _tiles[row * _columns + col] = tileId;
    notifyListeners();
  }

  void _resizeGrid() {
    final newTiles = List.filled(_columns * _rows, 0);
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _columns; c++) {
        if (c < _columns && r < _rows && (r * _columns + c) < _tiles.length) {
          newTiles[r * _columns + c] = _tiles[r * _columns + c];
        }
      }
    }
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
      ];

  @override
  Map<String, dynamic> toJson() {
    return {
      'columns': _columns,
      'rows': _rows,
      'tileSize': _tileSize,
      'tiles': _tiles,
    };
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    _columns = json['columns'] as int? ?? 16;
    _rows = json['rows'] as int? ?? 12;
    _tileSize = (json['tileSize'] as num?)?.toDouble() ?? 32.0;
    final rawTiles = json['tiles'] as List<dynamic>?;
    if (rawTiles != null) {
      _tiles = rawTiles.map((e) => (e as num).toInt()).toList();
    } else {
      _tiles = List.filled(_columns * _rows, 0);
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

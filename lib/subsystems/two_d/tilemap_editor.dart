import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/assets.dart';
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/transform2d.dart';
import '../../editor/tile_brush.dart';
import 'flame_components.dart';

/// The tilemap the brush paints into: the selected entity's, else the first in the scene.
EmberEntity? tilemapTarget(EmberEngine engine) {
  final selected = engine.selectedEntity;
  if (selected != null && selected.hasComponent<FlameTileMapComponent>()) return selected;
  for (final e in engine.activeScene.allEntities) {
    if (e.enabled && e.hasComponent<FlameTileMapComponent>() && e.hasComponent<Transform2DComponent>()) return e;
  }
  return null;
}

/// Colour used for tile [id] when a tilemap has no tileset (matches the 2D renderer).
Color tileFallbackColor(int id) => HSLColor.fromAHSL(0.85, (id * 45.0) % 360.0, 0.6, 0.45).toColor();

/// Tile Palette (bottom drawer): pick a tile, set what it does, and paint it
/// into the level with the mouse.
class TilemapPaletteWidget extends StatefulWidget {
  final EmberEngine engine;

  const TilemapPaletteWidget({super.key, required this.engine});

  @override
  State<TilemapPaletteWidget> createState() => _TilemapPaletteWidgetState();
}

class _TilemapPaletteWidgetState extends State<TilemapPaletteWidget> {
  static const _teal = Color(0xFF00F5D4);
  static const _card = Color(0xFF22242B);
  static const _muted = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([TileBrush.instance, EmberAssets.instance, widget.engine]),
      builder: (context, _) => _build(context),
    );
  }

  /// Chooses which tilemap (layer) to paint when a scene has several,
  /// e.g. a Ground layer and a solid Obstacles layer.
  Widget _layerPicker(EmberEntity current) {
    final layers = [
      for (final e in widget.engine.activeScene.allEntities)
        if (e.hasComponent<FlameTileMapComponent>() && e.hasComponent<Transform2DComponent>()) e,
    ];
    if (layers.length < 2) {
      return Text('"${current.name}"', style: const TextStyle(color: Colors.white, fontSize: 11));
    }
    return DropdownButton<EmberEntity>(
      value: layers.contains(current) ? current : null,
      isDense: true,
      dropdownColor: _card,
      underline: const SizedBox.shrink(),
      style: const TextStyle(color: Colors.white, fontSize: 11),
      items: [
        for (final e in layers)
          DropdownMenuItem(
            value: e,
            child: Text(e.getComponent<FlameTileMapComponent>()!.collision ? e.name : '${e.name} (walkable)'),
          ),
      ],
      onChanged: (e) => widget.engine.selectEntity(e),
    );
  }

  Widget _build(BuildContext context) {
    final brush = TileBrush.instance;
    final targetEntity = tilemapTarget(widget.engine);
    final map = targetEntity?.getComponent<FlameTileMapComponent>();
    final tileset = map == null || map.tilesetPath.isEmpty ? null : EmberAssets.instance.image(map.tilesetPath);
    final tileCount = tileset != null && map != null
        ? map.tilesetColumns * (tileset.height ~/ map.tilesetTileSize)
        : 8;

    return Container(
      color: const Color(0xFF18191E),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_view_rounded, size: 16, color: _teal),
              const SizedBox(width: 8),
              const Text('Tile Palette', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              if (map != null) ...[
                const Text('Layer', style: TextStyle(color: _muted, fontSize: 11)),
                const SizedBox(width: 6),
                _layerPicker(targetEntity!),
                const SizedBox(width: 8),
                Text(
                  '${map.columns}×${map.rows}${map.collision ? '' : '  (no collision)'}',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                const Spacer(),
                const Text('Paint', style: TextStyle(color: _muted, fontSize: 11)),
                Switch(
                  value: brush.enabled,
                  activeThumbColor: _teal,
                  onChanged: (v) => brush.enabled = v,
                ),
                const Text('left-drag paints · right-drag erases', style: TextStyle(color: _muted, fontSize: 10)),
              ] else ...[
                const Spacer(),
                TextButton.icon(
                  onPressed: _spawnTilemap,
                  icon: const Icon(Icons.add, size: 14, color: _teal),
                  label: const Text('Add Tilemap', style: TextStyle(color: _teal, fontSize: 11)),
                  style: TextButton.styleFrom(backgroundColor: _card),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: map == null
                ? const Center(child: Text('Add a tilemap to paint a level.', style: TextStyle(color: _muted, fontSize: 11)))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 44,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                          itemCount: tileCount + 1, // + eraser
                          itemBuilder: (context, index) => _swatch(index, map, tileset),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(width: 220, child: _tileDetails(map)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _swatch(int id, FlameTileMapComponent map, ui.Image? tileset) {
    final selected = TileBrush.instance.tileId == id;
    final Widget face;
    if (id == 0) {
      face = const Icon(Icons.cleaning_services_rounded, size: 16, color: Colors.white70);
    } else if (tileset != null) {
      face = CustomPaint(painter: _TileCellPainter(tileset, id, map.tilesetColumns, map.tilesetTileSize));
    } else {
      face = Container(color: tileFallbackColor(id));
    }
    return Tooltip(
      message: id == 0 ? 'Eraser' : 'Tile $id · ${map.kindOf(id).name}',
      child: GestureDetector(
        onTap: () {
          TileBrush.instance.tileId = id;
          TileBrush.instance.enabled = true;
        },
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: selected ? _teal : const Color(0xFF2C2E38), width: selected ? 2 : 1),
          ),
          child: face,
        ),
      ),
    );
  }

  Widget _tileDetails(FlameTileMapComponent map) {
    final id = TileBrush.instance.tileId;
    if (id == 0) {
      return const Text('Eraser: removes tiles.', style: TextStyle(color: _muted, fontSize: 11));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tile $id behaviour', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButton<TileKind>(
          value: map.kindOf(id),
          isDense: true,
          isExpanded: true,
          dropdownColor: _card,
          style: const TextStyle(color: Colors.white, fontSize: 11),
          items: [
            for (final k in TileKind.values) DropdownMenuItem(value: k, child: Text(_kindLabel(k))),
          ],
          onChanged: (k) {
            if (k != null) setState(() => map.setKind(id, k));
          },
        ),
        const SizedBox(height: 6),
        Text(_kindHelp(map.kindOf(id)), style: const TextStyle(color: _muted, fontSize: 10)),
      ],
    );
  }

  static String _kindLabel(TileKind k) => switch (k) {
        TileKind.solid => 'Solid',
        TileKind.decoration => 'Decoration (no collision)',
        TileKind.oneWay => 'One-way platform',
        TileKind.hazard => 'Hazard (spikes, lava)',
        TileKind.breakable => 'Breakable brick',
        TileKind.question => '"?" block',
        TileKind.usedBlock => 'Used block',
      };

  static String _kindHelp(TileKind k) => switch (k) {
        TileKind.solid => 'Blocks from every side.',
        TileKind.decoration => 'Drawn only; characters pass through.',
        TileKind.oneWay => 'Stand on it; jump up through it.',
        TileKind.hazard => 'Not solid. Scripts get onTileTouch.',
        TileKind.breakable => 'Solid. Scripts get onHeadBump to break it.',
        TileKind.question => 'Solid. Scripts get onHeadBump to give a reward.',
        TileKind.usedBlock => 'Solid; an emptied block.',
      };

  void _spawnTilemap() {
    final ent = EmberEntity(name: 'Tilemap');
    ent.addComponent(Transform2DComponent(size: vm.Vector2.zero()));
    ent.addComponent(FlameTileMapComponent(columns: 40, rows: 12));
    widget.engine.activeScene.addEntity(ent);
    widget.engine.selectEntity(ent);
    TileBrush.instance.enabled = true;
  }
}

class _TileCellPainter extends CustomPainter {
  final ui.Image image;
  final int id;
  final int columns;
  final int cell;

  _TileCellPainter(this.image, this.id, this.columns, this.cell);

  @override
  void paint(Canvas canvas, Size size) {
    final i = id - 1;
    final src = Rect.fromLTWH((i % columns) * cell.toDouble(), (i ~/ columns) * cell.toDouble(), cell.toDouble(), cell.toDouble());
    canvas.drawImageRect(image, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.none);
  }

  @override
  bool shouldRepaint(covariant _TileCellPainter old) => old.image != image || old.id != id;
}

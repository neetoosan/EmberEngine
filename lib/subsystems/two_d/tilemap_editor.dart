import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/transform2d.dart';
import 'flame_components.dart';

/// 2D Tilemap Palette and Spritesheet Slicer tool.
class TilemapPaletteWidget extends StatefulWidget {
  final EmberEngine engine;

  const TilemapPaletteWidget({super.key, required this.engine});

  @override
  State<TilemapPaletteWidget> createState() => _TilemapPaletteWidgetState();
}

class _TilemapPaletteWidgetState extends State<TilemapPaletteWidget> {
  int _selectedTileId = 1;
  final List<Color> _paletteColors = [
    const Color(0xFF334155), // 0: Empty/Erase
    const Color(0xFF00F5D4), // 1: Grass / Ground
    const Color(0xFF3B82F6), // 2: Water / Liquid
    const Color(0xFFF59E0B), // 3: Sand / Dirt
    const Color(0xFFEF4444), // 4: Lava / Hazard
    const Color(0xFF8B5CF6), // 5: Platform / Wall
    const Color(0xFF10B981), // 6: Forest
    const Color(0xFF64748B), // 7: Stone
  ];

  final List<String> _tileNames = [
    'Eraser',
    'Ground',
    'Water',
    'Dirt',
    'Hazard',
    'Platform',
    'Foliage',
    'Stone',
  ];

  @override
  Widget build(BuildContext context) {
    final selectedEntity = widget.engine.selectedEntity;
    final tilemap = selectedEntity?.getComponent<FlameTileMapComponent>();

    return Container(
      color: const Color(0xFF18191E),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toolbar Header
          Row(
            children: [
              const Icon(Icons.grid_view_rounded, size: 16, color: Color(0xFF00F5D4)),
              const SizedBox(width: 8),
              const Text(
                'Tilemap Palette & Slicer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (tilemap != null)
                Text(
                  'Grid: ${tilemap.columns}x${tilemap.rows} (${tilemap.tileSize.toInt()}px)',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                )
              else
                TextButton.icon(
                  onPressed: () {
                    final ent = EmberEntity(name: 'New Tilemap');
                    ent.addComponent(Transform2DComponent(size: vm.Vector2(512, 384)));
                    ent.addComponent(FlameTileMapComponent(columns: 16, rows: 12));
                    widget.engine.activeScene.addEntity(ent);
                    widget.engine.selectEntity(ent);
                  },
                  icon: const Icon(Icons.add, size: 14, color: Color(0xFF00F5D4)),
                  label: const Text(
                    'Spawn Tilemap',
                    style: TextStyle(color: Color(0xFF00F5D4), fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    backgroundColor: const Color(0xFF22242B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Palette Swatches
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: _paletteColors.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedTileId == index;
                final color = _paletteColors[index];

                return GestureDetector(
                  onTap: () => setState(() => _selectedTileId = index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF22242B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF00F5D4) : const Color(0xFF2C2E38),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: index == 0
                              ? const Icon(Icons.cleaning_services_rounded, size: 14, color: Colors.white70)
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _tileNames[index],
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Quick Hitbox Generator Toolbar
          const Divider(color: Color(0xFF2C2E38), height: 16),
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF00F5D4)),
              const SizedBox(width: 6),
              const Text(
                '2D Collision Hitbox:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  final entity = widget.engine.selectedEntity;
                  if (entity != null) {
                    entity.addComponent(FlameHitbox2DComponent(shape: Hitbox2DShape.rectangle));
                    widget.engine.log('Added Rectangle Hitbox to ${entity.name}', source: '2D Tooling');
                  }
                },
                icon: const Icon(Icons.check_box_outline_blank, size: 12),
                label: const Text('Add Box Hitbox', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22242B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  final entity = widget.engine.selectedEntity;
                  if (entity != null) {
                    entity.addComponent(FlameHitbox2DComponent(shape: Hitbox2DShape.circle));
                    widget.engine.log('Added Circle Hitbox to ${entity.name}', source: '2D Tooling');
                  }
                },
                icon: const Icon(Icons.radio_button_unchecked, size: 12),
                label: const Text('Add Circle Hitbox', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22242B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

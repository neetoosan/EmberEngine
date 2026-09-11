import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/event_bus.dart';
import '../../core/transform2d.dart';
import '../../core/transform3d.dart';
import '../../subsystems/three_d/camera3d.dart';
import '../../subsystems/three_d/components3d.dart';
import '../../subsystems/three_d/lighting.dart';
import '../../subsystems/three_d/material.dart';
import '../../subsystems/two_d/flame_components.dart';
import '../theme/ember_theme.dart';

/// 240px Left Shelf Hierarchy Panel.
///
/// Displays parent-child entity tree, search filtering, inline visibility toggles,
/// entity creation dropdown, and deletion.
class HierarchyPanel extends StatefulWidget {
  final EmberEngine engine;

  const HierarchyPanel({super.key, required this.engine});

  @override
  State<HierarchyPanel> createState() => _HierarchyPanelState();
}

class _HierarchyPanelState extends State<HierarchyPanel> {
  String _searchFilter = '';
  final Set<String> _collapsedEntityIds = {};

  @override
  Widget build(BuildContext context) {
    final mode = widget.engine.mode;
    final accentColor = mode == EngineMode.twoD ? EmberTheme.accentFlame : EmberTheme.accentEmber;
    final allEntities = widget.engine.activeScene.rootEntities;

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: EmberTheme.surfacePanel,
        border: Border(
          right: BorderSide(color: EmberTheme.borderMedium, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Panel Header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: EmberTheme.borderSubtle, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 14, color: EmberTheme.textSecondary),
                const SizedBox(width: 6),
                const Text('Hierarchy', style: EmberTheme.headerStyle),
                const Spacer(),
                // Add Entity Dropdown Button
                _buildAddEntityButton(accentColor),
              ],
            ),
          ),

          // 2. Search Filter Field
          Container(
            height: 28,
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: EmberTheme.surfaceCard,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: EmberTheme.borderSubtle),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 13, color: EmberTheme.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    style: const TextStyle(fontSize: 11, color: EmberTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Filter entities...',
                      hintStyle: TextStyle(fontSize: 11, color: EmberTheme.textMuted),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) => setState(() => _searchFilter = val.toLowerCase()),
                  ),
                ),
                if (_searchFilter.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _searchFilter = ''),
                    child: const Icon(Icons.close, size: 12, color: EmberTheme.textMuted),
                  ),
              ],
            ),
          ),

          // 3. Entity Tree List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: allEntities.map((e) => _buildEntityNode(e, 0, accentColor)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntityNode(EmberEntity entity, int depth, Color accentColor) {
    if (_searchFilter.isNotEmpty && !entity.name.toLowerCase().contains(_searchFilter)) {
      final matchesDescendant = entity.getAllDescendants().any((d) => d.name.toLowerCase().contains(_searchFilter));
      if (!matchesDescendant) return const SizedBox.shrink();
    }

    final isSelected = widget.engine.selectedEntity == entity;
    final hasChildren = entity.children.isNotEmpty;
    final isCollapsed = _collapsedEntityIds.contains(entity.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Entity Row
        InkWell(
          onTap: () => widget.engine.selectEntity(entity),
          child: Container(
            height: 26,
            padding: EdgeInsets.only(left: 8.0 + depth * 14.0, right: 6.0),
            decoration: BoxDecoration(
              color: isSelected ? accentColor.withValues(alpha: 0.15) : Colors.transparent,
              border: isSelected
                  ? Border(left: BorderSide(color: accentColor, width: 2))
                  : null,
            ),
            child: Row(
              children: [
                // Expand / Collapse toggle for parents
                if (hasChildren)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isCollapsed) {
                          _collapsedEntityIds.remove(entity.id);
                        } else {
                          _collapsedEntityIds.add(entity.id);
                        }
                      });
                    },
                    child: Icon(
                      isCollapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                      size: 16,
                      color: EmberTheme.textMuted,
                    ),
                  )
                else
                  const SizedBox(width: 16),

                // Component Icon
                Icon(_getEntityIcon(entity), size: 13, color: isSelected ? accentColor : EmberTheme.textSecondary),
                const SizedBox(width: 6),

                // Entity Name
                Expanded(
                  child: Text(
                    entity.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: entity.enabled ? EmberTheme.textPrimary : EmberTheme.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Inline Visibility Toggle
                GestureDetector(
                  onTap: () => entity.enabled = !entity.enabled,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      entity.enabled ? Icons.visibility : Icons.visibility_off,
                      size: 13,
                      color: entity.enabled ? EmberTheme.textMuted : EmberTheme.accentRed,
                    ),
                  ),
                ),

                // Inline Delete Button
                GestureDetector(
                  onTap: () => widget.engine.activeScene.removeEntity(entity),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.close, size: 13, color: EmberTheme.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Child Entities (if expanded)
        if (hasChildren && !isCollapsed)
          ...entity.children.map((child) => _buildEntityNode(child, depth + 1, accentColor)),
      ],
    );
  }

  IconData _getEntityIcon(EmberEntity entity) {
    if (entity.hasComponent<CameraComponent>()) return Icons.videocam_outlined;
    if (entity.hasComponent<LightComponent>()) return Icons.wb_sunny_outlined;
    if (entity.hasComponent<MeshRenderer3DComponent>()) return Icons.view_in_ar;
    if (entity.hasComponent<FlameSpriteComponent>()) return Icons.image_outlined;
    if (entity.hasComponent<FlameTileMapComponent>()) return Icons.grid_on;
    if (entity.hasComponent<FlameHitbox2DComponent>()) return Icons.shield_outlined;
    return Icons.folder_open;
  }

  Widget _buildAddEntityButton(Color accentColor) {
    return PopupMenuButton<String>(
      tooltip: 'Add Entity',
      color: EmberTheme.surfaceCard,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.add, size: 16, color: accentColor),
      onSelected: (type) => _spawnEntity(type),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'empty', child: Text('Empty Entity', style: TextStyle(fontSize: 11))),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(value: 'cube', child: Text('3D Cube', style: TextStyle(fontSize: 11))),
        const PopupMenuItem(value: 'sphere', child: Text('3D Sphere', style: TextStyle(fontSize: 11))),
        const PopupMenuItem(value: 'plane', child: Text('3D Plane', style: TextStyle(fontSize: 11))),
        const PopupMenuItem(value: 'light', child: Text('3D Light', style: TextStyle(fontSize: 11))),
        const PopupMenuItem(value: 'camera', child: Text('Camera', style: TextStyle(fontSize: 11))),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(value: 'sprite', child: Text('2D Sprite', style: TextStyle(fontSize: 11))),
        const PopupMenuItem(value: 'tilemap', child: Text('2D Tilemap', style: TextStyle(fontSize: 11))),
      ],
    );
  }

  void _spawnEntity(String type) {
    final is2D = widget.engine.mode == EngineMode.twoD;

    switch (type) {
      case 'empty':
        final e = EmberEntity(name: 'Empty Entity');
        if (is2D) {
          e.addComponent(Transform2DComponent());
        } else {
          e.addComponent(Transform3DComponent());
        }
        widget.engine.activeScene.addEntity(e);
        widget.engine.selectEntity(e);
        break;

      case 'cube':
        final e = EmberEntity(name: 'Cube');
        e.addComponent(Transform3DComponent(position: vm.Vector3(0, 1, 0)));
        e.addComponent(MeshRenderer3DComponent(primitiveType: MeshPrimitiveType.cube));
        widget.engine.activeScene.addEntity(e);
        widget.engine.selectEntity(e);
        break;

      case 'sphere':
        final e = EmberEntity(name: 'Sphere');
        e.addComponent(Transform3DComponent(position: vm.Vector3(0, 1, 0)));
        e.addComponent(MeshRenderer3DComponent(
          primitiveType: MeshPrimitiveType.sphere,
          material: Material3D(color: const Color(0xFF10B981)),
        ));
        widget.engine.activeScene.addEntity(e);
        widget.engine.selectEntity(e);
        break;

      case 'plane':
        final e = EmberEntity(name: 'Plane');
        e.addComponent(Transform3DComponent(position: vm.Vector3(0, 0, 0), scale: vm.Vector3(10, 0.1, 10)));
        e.addComponent(MeshRenderer3DComponent(
          primitiveType: MeshPrimitiveType.plane,
          material: Material3D(color: const Color(0xFF334155)),
        ));
        widget.engine.activeScene.addEntity(e);
        widget.engine.selectEntity(e);
        break;

      case 'light':
        final e = EmberEntity(name: 'Point Light');
        e.addComponent(Transform3DComponent(position: vm.Vector3(2, 4, 2)));
        e.addComponent(LightComponent(type: LightType.point, color: const Color(0xFFF59E0B), intensity: 2.0));
        widget.engine.activeScene.addEntity(e);
        widget.engine.selectEntity(e);
        break;

      case 'camera':
        final e = EmberEntity(name: 'Camera');
        e.addComponent(Transform3DComponent(position: vm.Vector3(0, 3, 6)));
        e.addComponent(CameraComponent());
        widget.engine.activeScene.addEntity(e);
        widget.engine.selectEntity(e);
        break;

      case 'sprite':
        final e = EmberEntity(name: 'Sprite Entity');
        e.addComponent(Transform2DComponent(position: vm.Vector2(200, 200), size: vm.Vector2(48, 48)));
        e.addComponent(FlameSpriteComponent());
        widget.engine.activeScene.addEntity(e);
        widget.engine.selectEntity(e);
        break;

      case 'tilemap':
        final e = EmberEntity(name: 'Tilemap');
        e.addComponent(Transform2DComponent(size: vm.Vector2(512, 384)));
        e.addComponent(FlameTileMapComponent(columns: 16, rows: 12));
        widget.engine.activeScene.addEntity(e);
        widget.engine.selectEntity(e);
        break;
    }
  }
}

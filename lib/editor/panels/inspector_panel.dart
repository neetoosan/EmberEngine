import 'package:flutter/material.dart';
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/transform2d.dart';
import '../../core/transform3d.dart';
import '../../subsystems/three_d/components3d.dart';
import '../../subsystems/three_d/lighting.dart';
import '../../subsystems/three_d/camera3d.dart';
import '../../subsystems/two_d/flame_components.dart';
import '../theme/ember_theme.dart';
import '../ui_primitives/anchor_selector.dart';
import '../ui_primitives/compact_accordion.dart';
import '../ui_primitives/scrubbable_field.dart';
import '../ui_primitives/vector2_field.dart';
import '../ui_primitives/vector3_field.dart';

/// 300px Right Shelf Inspector Panel.
///
/// Provides dynamic property editors for entities and components:
/// scrubbable vector fields, anchor matrix selector, color pickers, and component adder.
class InspectorPanel extends StatefulWidget {
  final EmberEngine engine;

  const InspectorPanel({super.key, required this.engine});

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  @override
  Widget build(BuildContext context) {
    final selected = widget.engine.selectedEntity;

    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: EmberTheme.surfacePanel,
        border: Border(
          left: BorderSide(color: EmberTheme.borderMedium, width: 1),
        ),
      ),
      child: selected == null ? _buildNoSelection() : _buildEntityInspector(selected),
    );
  }

  Widget _buildNoSelection() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 32, color: EmberTheme.textMuted),
          SizedBox(height: 8),
          Text(
            'No Entity Selected',
            style: TextStyle(color: EmberTheme.textMuted, fontSize: 12),
          ),
          SizedBox(height: 4),
          Text(
            'Click an object in Hierarchy or Viewport',
            style: TextStyle(color: EmberTheme.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildEntityInspector(EmberEntity entity) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Entity Header
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: EmberTheme.borderSubtle, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Enabled Checkbox
                  GestureDetector(
                    onTap: () => setState(() => entity.enabled = !entity.enabled),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: entity.enabled ? EmberTheme.accentGreen : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: entity.enabled ? EmberTheme.accentGreen : EmberTheme.textMuted,
                        ),
                      ),
                      child: entity.enabled
                          ? const Icon(Icons.check, size: 12, color: Colors.black)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Name Field
                  Expanded(
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: EmberTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: EmberTheme.borderSubtle),
                      ),
                      child: TextFormField(
                        initialValue: entity.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: EmberTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                        onChanged: (val) => entity.name = val,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Tag & Layer Readout
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Tag:', style: TextStyle(color: EmberTheme.textMuted, fontSize: 10)),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: EmberTheme.surfaceCard,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          entity.tags.isEmpty ? 'Untagged' : entity.tags.first,
                          style: const TextStyle(color: EmberTheme.textSecondary, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Layer:', style: TextStyle(color: EmberTheme.textMuted, fontSize: 10)),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: EmberTheme.surfaceCard,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'Default (${entity.layer})',
                          style: const TextStyle(color: EmberTheme.textSecondary, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Component Cards List
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              // Transform 3D Card
              if (entity.hasComponent<Transform3DComponent>())
                _buildTransform3DCard(entity.getComponent<Transform3DComponent>()!),

              // Transform 2D Card
              if (entity.hasComponent<Transform2DComponent>())
                _buildTransform2DCard(entity.getComponent<Transform2DComponent>()!),

              // Mesh Renderer 3D Card
              if (entity.hasComponent<MeshRenderer3DComponent>())
                _buildMeshRendererCard(entity.getComponent<MeshRenderer3DComponent>()!),

              // Flame Sprite Card
              if (entity.hasComponent<FlameSpriteComponent>())
                _buildFlameSpriteCard(entity.getComponent<FlameSpriteComponent>()!),

              // Light Card
              if (entity.hasComponent<LightComponent>())
                _buildLightCard(entity.getComponent<LightComponent>()!),

              // Camera Card
              if (entity.hasComponent<CameraComponent>())
                _buildCameraCard(entity.getComponent<CameraComponent>()!),

              // Hitbox 2D Card
              if (entity.hasComponent<FlameHitbox2DComponent>())
                _buildHitbox2DCard(entity.getComponent<FlameHitbox2DComponent>()!),

              // TileMap Card
              if (entity.hasComponent<FlameTileMapComponent>())
                _buildTileMapCard(entity.getComponent<FlameTileMapComponent>()!),

              const SizedBox(height: 12),

              // 3. Add Component Button
              _buildAddComponentButton(entity),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransform3DCard(Transform3DComponent t) {
    return CompactAccordion(
      title: 'Transform 3D',
      icon: Icons.open_with,
      isEnabled: t.enabled,
      onEnableChanged: (val) => t.enabled = val,
      child: Column(
        children: [
          Vector3Field(
            label: 'Position',
            value: t.position,
            step: 0.1,
            onChanged: (val) => t.position = val,
          ),
          const SizedBox(height: 8),
          Vector3Field(
            label: 'Rotation (deg)',
            value: t.euler,
            step: 1.0,
            onChanged: (val) => t.euler = val,
          ),
          const SizedBox(height: 8),
          Vector3Field(
            label: 'Scale',
            value: t.scale,
            step: 0.05,
            onChanged: (val) => t.scale = val,
          ),
        ],
      ),
    );
  }

  Widget _buildTransform2DCard(Transform2DComponent t) {
    return CompactAccordion(
      title: 'Transform 2D',
      icon: Icons.transform,
      isEnabled: t.enabled,
      onEnableChanged: (val) => t.enabled = val,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Vector2Field(
            label: 'Position (px)',
            value: t.position,
            step: 1.0,
            onChanged: (val) => t.position = val,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Angle (deg)', style: EmberTheme.headerStyle),
                    const SizedBox(height: 4),
                    ScrubbableField(
                      label: 'R',
                      value: t.rotationDegrees,
                      step: 1.0,
                      onChanged: (val) => t.rotationDegrees = val,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Z-Index', style: EmberTheme.headerStyle),
                    const SizedBox(height: 4),
                    ScrubbableField(
                      label: 'Z',
                      value: t.zIndex.toDouble(),
                      step: 1.0,
                      precision: 0,
                      onChanged: (val) => t.zIndex = val.toInt(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Vector2Field(
            label: 'Size (px)',
            value: t.size,
            step: 1.0,
            onChanged: (val) => t.size = val,
          ),
          const SizedBox(height: 8),
          Vector2Field(
            label: 'Scale',
            value: t.scale,
            step: 0.1,
            onChanged: (val) => t.scale = val,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Anchor:', style: EmberTheme.headerStyle),
              const Spacer(),
              FlameAnchorSelector(
                currentAnchor: t.anchor,
                onSelected: (val) => t.anchor = val,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeshRendererCard(MeshRenderer3DComponent mr) {
    final mat = mr.material;

    return CompactAccordion(
      title: 'Mesh Renderer 3D',
      icon: Icons.view_in_ar,
      isEnabled: mr.enabled,
      onEnableChanged: (val) => mr.enabled = val,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Primitive:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<MeshPrimitiveType>(
                  value: mr.primitiveType,
                  dropdownColor: EmberTheme.surfaceCard,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  isDense: true,
                  items: MeshPrimitiveType.values
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) mr.primitiveType = val;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Color Swatches
          Row(
            children: [
              const Text('Color:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
              const Spacer(),
              _buildColorPicker(mat.color, (newColor) {
                mr.material = (mat..color = newColor);
                setState(() {});
              }),
            ],
          ),
          const SizedBox(height: 8),

          // Roughness & Metallic
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Rough',
                  value: mat.roughness,
                  step: 0.05,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (val) {
                    mr.material = (mat..roughness = val);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Metal',
                  value: mat.metallic,
                  step: 0.05,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (val) {
                    mr.material = (mat..metallic = val);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Wireframe mode
          Row(
            children: [
              const Text('Wireframe:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
              const Spacer(),
              Switch(
                value: mat.wireframe,
                activeTrackColor: EmberTheme.accentEmber,
                onChanged: (val) {
                  mr.material = (mat..wireframe = val);
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlameSpriteCard(FlameSpriteComponent sprite) {
    return CompactAccordion(
      title: 'Flame Sprite',
      icon: Icons.image_outlined,
      isEnabled: sprite.enabled,
      onEnableChanged: (val) => sprite.enabled = val,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Tint:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
              const Spacer(),
              _buildColorPicker(sprite.tint, (col) => sprite.tint = col),
            ],
          ),
          const SizedBox(height: 8),
          ScrubbableField(
            label: 'Opacity',
            value: sprite.opacity,
            step: 0.05,
            min: 0.0,
            max: 1.0,
            onChanged: (val) => sprite.opacity = val,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Text('Flip X:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
                    Checkbox(
                      value: sprite.flipX,
                      activeColor: EmberTheme.accentFlame,
                      onChanged: (val) => sprite.flipX = val ?? false,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    const Text('Flip Y:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
                    Checkbox(
                      value: sprite.flipY,
                      activeColor: EmberTheme.accentFlame,
                      onChanged: (val) => sprite.flipY = val ?? false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLightCard(LightComponent light) {
    return CompactAccordion(
      title: 'Light Source',
      icon: Icons.wb_sunny_outlined,
      isEnabled: light.enabled,
      onEnableChanged: (val) => light.enabled = val,
      child: Column(
        children: [
          Row(
            children: [
              const Text('Type:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<LightType>(
                  value: light.type,
                  dropdownColor: EmberTheme.surfaceCard,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  isDense: true,
                  items: LightType.values
                      .map((l) => DropdownMenuItem(value: l, child: Text(l.name)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) light.type = val;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Color:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
              const Spacer(),
              _buildColorPicker(light.color, (col) => light.color = col),
            ],
          ),
          const SizedBox(height: 8),
          ScrubbableField(
            label: 'Intensity',
            value: light.intensity,
            step: 0.1,
            min: 0.0,
            max: 10.0,
            onChanged: (val) => light.intensity = val,
          ),
        ],
      ),
    );
  }

  Widget _buildCameraCard(CameraComponent cam) {
    return CompactAccordion(
      title: 'Camera',
      icon: Icons.videocam_outlined,
      isEnabled: cam.enabled,
      onEnableChanged: (val) => cam.enabled = val,
      child: Column(
        children: [
          ScrubbableField(
            label: 'FOV',
            value: cam.fov,
            step: 1.0,
            min: 15.0,
            max: 120.0,
            onChanged: (val) => cam.fov = val,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Near',
                  value: cam.near,
                  step: 0.05,
                  min: 0.01,
                  max: 10.0,
                  onChanged: (val) => cam.near = val,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Far',
                  value: cam.far,
                  step: 10.0,
                  min: 10.0,
                  max: 5000.0,
                  onChanged: (val) => cam.far = val,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHitbox2DCard(FlameHitbox2DComponent hitbox) {
    return CompactAccordion(
      title: 'Flame Hitbox 2D',
      icon: Icons.shield_outlined,
      isEnabled: hitbox.enabled,
      onEnableChanged: (val) => hitbox.enabled = val,
      child: Column(
        children: [
          Row(
            children: [
              const Text('Shape:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<Hitbox2DShape>(
                  value: hitbox.shape,
                  dropdownColor: EmberTheme.surfaceCard,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  isDense: true,
                  items: Hitbox2DShape.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) hitbox.shape = val;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Vector2Field(
            label: 'Hitbox Size',
            value: hitbox.size,
            step: 1.0,
            onChanged: (val) => hitbox.size = val,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Solid Collider:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
              const Spacer(),
              Switch(
                value: hitbox.isSolid,
                activeTrackColor: EmberTheme.accentGreen,
                onChanged: (val) => hitbox.isSolid = val,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTileMapCard(FlameTileMapComponent tilemap) {
    return CompactAccordion(
      title: 'Flame TileMap',
      icon: Icons.grid_on,
      isEnabled: tilemap.enabled,
      onEnableChanged: (val) => tilemap.enabled = val,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Cols',
                  value: tilemap.columns.toDouble(),
                  step: 1.0,
                  min: 1,
                  max: 64,
                  precision: 0,
                  onChanged: (val) => tilemap.columns = val.toInt(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Rows',
                  value: tilemap.rows.toDouble(),
                  step: 1.0,
                  min: 1,
                  max: 64,
                  precision: 0,
                  onChanged: (val) => tilemap.rows = val.toInt(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ScrubbableField(
            label: 'Tile Size',
            value: tilemap.tileSize,
            step: 8.0,
            min: 8.0,
            max: 128.0,
            onChanged: (val) => tilemap.tileSize = val,
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker(Color currentColor, ValueChanged<Color> onSelected) {
    final colors = [
      const Color(0xFF6366F1), // Ember Indigo
      const Color(0xFF00F5D4), // Flame Teal
      const Color(0xFFEF4444), // Red
      const Color(0xFF10B981), // Green
      const Color(0xFF3B82F6), // Blue
      const Color(0xFFF59E0B), // Amber
      const Color(0xFFE2E8F0), // White
      const Color(0xFF334155), // Dark Slate
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: colors.map((col) {
        final isSelected = col.toARGB32() == currentColor.toARGB32();
        return GestureDetector(
          onTap: () => onSelected(col),
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: col,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAddComponentButton(EmberEntity entity) {
    return PopupMenuButton<String>(
      tooltip: 'Add Component',
      color: EmberTheme.surfaceCard,
      onSelected: (compType) {
        switch (compType) {
          case 'MeshRenderer3D':
            entity.addComponent(MeshRenderer3DComponent());
            break;
          case 'Light':
            entity.addComponent(LightComponent());
            break;
          case 'Camera':
            entity.addComponent(CameraComponent());
            break;
          case 'FlameSprite':
            entity.addComponent(FlameSpriteComponent());
            break;
          case 'FlameHitbox':
            entity.addComponent(FlameHitbox2DComponent());
            break;
          case 'FlameTileMap':
            entity.addComponent(FlameTileMapComponent());
            break;
        }
        setState(() {});
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'MeshRenderer3D', child: Text('Mesh Renderer 3D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'Light', child: Text('Light Source', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'Camera', child: Text('Camera', style: TextStyle(fontSize: 11))),
        PopupMenuDivider(height: 1),
        PopupMenuItem(value: 'FlameSprite', child: Text('Flame Sprite 2D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'FlameHitbox', child: Text('Flame Hitbox 2D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'FlameTileMap', child: Text('Flame TileMap 2D', style: TextStyle(fontSize: 11))),
      ],
      child: Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: EmberTheme.surfaceCard,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: EmberTheme.borderSubtle),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 14, color: EmberTheme.accentEmber),
            SizedBox(width: 6),
            Text(
              'Add Component',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: EmberTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

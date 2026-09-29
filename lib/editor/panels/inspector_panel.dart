import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/assets.dart';
import '../../core/component.dart';
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/event_bus.dart';
import '../../core/game_script.dart';
import '../../core/transform2d.dart';
import '../../core/transform3d.dart';
import '../../subsystems/three_d/components3d.dart';
import '../../subsystems/three_d/lighting.dart';
import '../../subsystems/three_d/camera3d.dart';
import '../../subsystems/two_d/flame_components.dart';
import '../../subsystems/audio/audio_component.dart';
import '../../subsystems/audio/audio_system.dart';
import '../../subsystems/physics/character_controller3d.dart';
import '../../subsystems/physics/character_controller2d.dart';
import '../../subsystems/particles/particle_system.dart';
import '../../subsystems/two_d/camera2d.dart';
import '../../subsystems/ui/ui_text.dart';
import '../hub/project_assets.dart';
import '../theme/ember_theme.dart';
import 'property_card.dart';
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

              // Light Card
              if (entity.hasComponent<LightComponent>())
                _buildLightCard(entity.getComponent<LightComponent>()!),

              // Camera Card
              if (entity.hasComponent<CameraComponent>())
                _buildCameraCard(entity.getComponent<CameraComponent>()!),

              // RigidBody 3D Card
              if (entity.hasComponent<RigidBody3DComponent>())
                _buildRigidBody3DCard(entity.getComponent<RigidBody3DComponent>()!),

              // Collider 3D Card
              if (entity.hasComponent<Collider3DComponent>())
                _buildCollider3DCard(entity.getComponent<Collider3DComponent>()!),

              // Character Controller 3D Card
              if (entity.hasComponent<CharacterController3DComponent>())
                _buildCharacterController3DCard(entity.getComponent<CharacterController3DComponent>()!),

              // Particle Emitter 3D Card
              if (entity.hasComponent<ParticleEmitter3DComponent>())
                _buildParticleEmitter3DCard(entity.getComponent<ParticleEmitter3DComponent>()!),

              // Flame Sprite Card
              if (entity.hasComponent<FlameSpriteComponent>())
                _buildFlameSpriteCard(entity.getComponent<FlameSpriteComponent>()!),

              // Hitbox 2D Card
              if (entity.hasComponent<FlameHitbox2DComponent>())
                _buildHitbox2DCard(entity.getComponent<FlameHitbox2DComponent>()!),

              // TileMap Card
              if (entity.hasComponent<FlameTileMapComponent>())
                _buildTileMapCard(entity.getComponent<FlameTileMapComponent>()!),

              // Character Controller 2D Card
              if (entity.hasComponent<CharacterController2DComponent>())
                _buildCharacterController2DCard(entity.getComponent<CharacterController2DComponent>()!),

              // Particle Emitter 2D Card
              if (entity.hasComponent<ParticleEmitter2DComponent>())
                _buildParticleEmitter2DCard(entity.getComponent<ParticleEmitter2DComponent>()!),

              // Audio Source Card
              if (entity.hasComponent<AudioSourceComponent>())
                _buildAudioSourceCard(entity.getComponent<AudioSourceComponent>()!),

              // Script Cards (one per script)
              for (final script in entity.getComponents<ScriptComponent>())
                _buildScriptCard(script),

              // Every other component (Camera 2D, UI Text, …) gets a generated card
              for (final c in entity.components)
                if (!_hasCustomCard(c))
                  GenericComponentCard(component: c, onChanged: () => setState(() {})),

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
          _buildSpriteImagePicker(sprite),
          const SizedBox(height: 8),
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

  static const _importImageItem = '\u0000import';

  Widget _buildSpriteImagePicker(FlameSpriteComponent sprite) {
    final images = ProjectAssets.list(extensions: ProjectAssets.imageExtensions);
    final missing = EmberAssets.instance.isMissing(sprite.assetPath);
    return Row(
      children: [
        const Text('Image:', style: TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
        const SizedBox(width: 6),
        Expanded(
          child: Tooltip(
            message: sprite.assetPath,
            child: Text(
              sprite.assetPath.isEmpty ? '(none)' : sprite.assetPath.split('/').last,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: missing ? EmberTheme.accentRed : EmberTheme.textPrimary),
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Choose image',
          color: EmberTheme.surfaceCard,
          icon: const Icon(Icons.image_search, size: 16, color: EmberTheme.textSecondary),
          onSelected: (choice) async {
            if (choice == _importImageItem) {
              final picked = await FilePicker.pickFile(dialogTitle: 'Import image', type: FileType.image);
              final path = picked?.path;
              if (path == null) return;
              final rel = await ProjectAssets.importFile(path);
              if (rel == null) {
                widget.engine.log('Save the project first so images have a folder to go in.',
                    severity: LogSeverity.warning, source: 'Assets');
                return;
              }
              sprite.assetPath = rel;
            } else {
              sprite.assetPath = choice;
            }
            if (mounted) setState(() {});
          },
          itemBuilder: (_) => [
            for (final img in images)
              PopupMenuItem(value: img, child: Text(img, style: const TextStyle(fontSize: 11))),
            const PopupMenuItem(
              value: _importImageItem,
              child: Text('Import image…', style: TextStyle(fontSize: 11, color: EmberTheme.accentFlame)),
            ),
          ],
        ),
      ],
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

  Widget _buildRigidBody3DCard(RigidBody3DComponent rb) {
    return CompactAccordion(
      title: 'RigidBody 3D',
      icon: Icons.sports_basketball,
      isEnabled: rb.enabled,
      onEnableChanged: (val) => rb.enabled = val,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Mass (kg)',
                  value: rb.mass,
                  step: 0.1,
                  min: 0.01,
                  max: 1000.0,
                  onChanged: (val) => rb.mass = val,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Drag',
                  value: rb.drag,
                  step: 0.01,
                  min: 0.0,
                  max: 10.0,
                  onChanged: (val) => rb.drag = val,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Use Gravity:', style: TextStyle(fontSize: 10, color: EmberTheme.textMuted)),
              const Spacer(),
              Switch(
                value: rb.useGravity,
                activeTrackColor: EmberTheme.accentGreen,
                onChanged: (val) => setState(() => rb.useGravity = val),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Is Kinematic:', style: TextStyle(fontSize: 10, color: EmberTheme.textMuted)),
              const Spacer(),
              Switch(
                value: rb.isKinematic,
                activeTrackColor: EmberTheme.accentGreen,
                onChanged: (val) => setState(() => rb.isKinematic = val),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCollider3DCard(Collider3DComponent col) {
    return CompactAccordion(
      title: 'Collider 3D',
      icon: Icons.crop_free,
      isEnabled: col.enabled,
      onEnableChanged: (val) => col.enabled = val,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Shape:', style: TextStyle(fontSize: 11, color: EmberTheme.textMuted)),
              const Spacer(),
              DropdownButton<Collider3DType>(
                value: col.type,
                dropdownColor: EmberTheme.surfaceCard,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 11, color: EmberTheme.textPrimary),
                items: Collider3DType.values.map((s) {
                  return DropdownMenuItem(value: s, child: Text(s.name.toUpperCase()));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => col.type = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Vector3Field(
            label: 'Extents Size',
            value: col.size,
            step: 0.1,
            onChanged: (val) => col.size = val,
          ),
          const SizedBox(height: 6),
          Vector3Field(
            label: 'Center Offset',
            value: col.center,
            step: 0.1,
            onChanged: (val) => col.center = val,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Is Trigger:', style: TextStyle(fontSize: 10, color: EmberTheme.textMuted)),
              const Spacer(),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: col.isTrigger,
                  activeTrackColor: EmberTheme.accentGreen,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) => setState(() => col.isTrigger = val),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterController3DCard(CharacterController3DComponent cc) {
    return CompactAccordion(
      title: 'Character Controller 3D',
      icon: Icons.directions_walk,
      isEnabled: cc.enabled,
      onEnableChanged: (val) => cc.enabled = val,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cc.isGrounded ? EmberTheme.accentGreen.withValues(alpha: 0.2) : EmberTheme.accentEmber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: cc.isGrounded ? EmberTheme.accentGreen : EmberTheme.accentEmber,
                  ),
                ),
                child: Text(
                  cc.isGrounded ? 'Grounded' : 'Airborne',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: cc.isGrounded ? EmberTheme.accentGreen : EmberTheme.accentEmber,
                  ),
                ),
              ),
              const Spacer(),
              const Text('FPS / Kinematic', style: TextStyle(fontSize: 10, color: EmberTheme.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Walk Speed',
                  value: cc.walkSpeed,
                  step: 0.5,
                  min: 0.5,
                  max: 50.0,
                  onChanged: (val) => cc.walkSpeed = val,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Jump Force',
                  value: cc.jumpForce,
                  step: 0.5,
                  min: 0.0,
                  max: 30.0,
                  onChanged: (val) => cc.jumpForce = val,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Sprint Speed',
                  value: cc.sprintSpeed,
                  step: 0.5,
                  min: 1.0,
                  max: 50.0,
                  onChanged: (val) => cc.sprintSpeed = val,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Gravity',
                  value: cc.gravity,
                  step: 0.5,
                  min: 0.0,
                  max: 50.0,
                  onChanged: (val) => cc.gravity = val,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Height',
                  value: cc.height,
                  step: 0.1,
                  min: 0.5,
                  max: 4.0,
                  onChanged: (val) => cc.height = val,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Radius',
                  value: cc.radius,
                  step: 0.05,
                  min: 0.1,
                  max: 2.0,
                  onChanged: (val) => cc.radius = val,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterController2DCard(CharacterController2DComponent cc) {
    return CompactAccordion(
      title: 'Platformer Controller 2D',
      icon: Icons.run_circle_outlined,
      isEnabled: cc.enabled,
      onEnableChanged: (val) => cc.enabled = val,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cc.isGrounded ? EmberTheme.accentGreen.withValues(alpha: 0.2) : EmberTheme.accentEmber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: cc.isGrounded ? EmberTheme.accentGreen : EmberTheme.accentEmber,
                  ),
                ),
                child: Text(
                  cc.isGrounded ? 'Grounded' : 'Airborne',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: cc.isGrounded ? EmberTheme.accentGreen : EmberTheme.accentEmber,
                  ),
                ),
              ),
              const Spacer(),
              const Text('Coyote & Buffer Ready', style: TextStyle(fontSize: 10, color: EmberTheme.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Speed (px/s)',
                  value: cc.moveSpeed,
                  step: 10.0,
                  min: 50.0,
                  max: 1000.0,
                  onChanged: (val) => cc.moveSpeed = val,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Jump Force',
                  value: cc.jumpVelocity,
                  step: 20.0,
                  min: 100.0,
                  max: 1500.0,
                  onChanged: (val) => cc.jumpVelocity = val,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Coyote (s)',
                  value: cc.coyoteTimeDuration,
                  step: 0.02,
                  min: 0.0,
                  max: 0.5,
                  precision: 3,
                  onChanged: (val) => cc.coyoteTimeDuration = val,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Jump Buffer (s)',
                  value: cc.jumpBufferDuration,
                  step: 0.02,
                  min: 0.0,
                  max: 0.5,
                  precision: 3,
                  onChanged: (val) => cc.jumpBufferDuration = val,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParticleEmitter3DCard(ParticleEmitter3DComponent emitter) {
    return CompactAccordion(
      title: 'Particle Emitter 3D',
      icon: Icons.auto_awesome,
      isEnabled: emitter.enabled,
      onEnableChanged: (val) => emitter.enabled = val,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Preset:', style: TextStyle(fontSize: 11, color: EmberTheme.textMuted)),
              const Spacer(),
              DropdownButton<ParticlePreset>(
                value: emitter.preset,
                dropdownColor: EmberTheme.surfaceCard,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 11, color: EmberTheme.textPrimary),
                items: ParticlePreset.values.map((p) {
                  return DropdownMenuItem(value: p, child: Text(p.name));
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => emitter.applyPreset(val));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Max Count',
                  value: emitter.maxParticles.toDouble(),
                  step: 10,
                  min: 10,
                  max: 2000,
                  precision: 0,
                  onChanged: (val) => emitter.maxParticles = val.toInt(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Rate (/s)',
                  value: emitter.emissionRate,
                  step: 5.0,
                  min: 0.0,
                  max: 500.0,
                  onChanged: (val) => emitter.emissionRate = val,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 24,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: EmberTheme.accentEmber,
                padding: EdgeInsets.zero,
              ),
              onPressed: () => emitter.triggerBurst(30),
              icon: const Icon(Icons.flash_on, size: 12, color: Colors.black),
              label: const Text('Trigger Burst (30)', style: TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticleEmitter2DCard(ParticleEmitter2DComponent emitter) {
    return CompactAccordion(
      title: 'Particle Emitter 2D',
      icon: Icons.bubble_chart,
      isEnabled: emitter.enabled,
      onEnableChanged: (val) => emitter.enabled = val,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Preset:', style: TextStyle(fontSize: 11, color: EmberTheme.textMuted)),
              const Spacer(),
              DropdownButton<ParticlePreset>(
                value: emitter.preset,
                dropdownColor: EmberTheme.surfaceCard,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 11, color: EmberTheme.textPrimary),
                items: ParticlePreset.values.map((p) {
                  return DropdownMenuItem(value: p, child: Text(p.name));
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => emitter.applyPreset(val));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Max Count',
                  value: emitter.maxParticles.toDouble(),
                  step: 10,
                  min: 10,
                  max: 1000,
                  precision: 0,
                  onChanged: (val) => emitter.maxParticles = val.toInt(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Rate (/s)',
                  value: emitter.emissionRate,
                  step: 5.0,
                  min: 0.0,
                  max: 500.0,
                  onChanged: (val) => emitter.emissionRate = val,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 24,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: EmberTheme.accentFlame,
                padding: EdgeInsets.zero,
              ),
              onPressed: () => emitter.triggerBurst(25),
              icon: const Icon(Icons.flash_on, size: 12, color: Colors.black),
              label: const Text('Trigger 2D Burst', style: TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioSourceCard(AudioSourceComponent audio) {
    final sfxOptions = ['laser', 'jump', 'hit', 'explosion', 'coin', 'click'];

    return CompactAccordion(
      title: 'Audio Source',
      icon: Icons.volume_up,
      isEnabled: audio.enabled,
      onEnableChanged: (val) => audio.enabled = val,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Sound ID:', style: TextStyle(fontSize: 11, color: EmberTheme.textMuted)),
              const Spacer(),
              DropdownButton<String>(
                value: sfxOptions.contains(audio.clip) ? audio.clip : 'laser',
                dropdownColor: EmberTheme.surfaceCard,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 11, color: EmberTheme.textPrimary),
                items: sfxOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => audio.clip = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Mix Category:', style: TextStyle(fontSize: 11, color: EmberTheme.textMuted)),
              const Spacer(),
              DropdownButton<AudioCategory>(
                value: audio.category,
                dropdownColor: EmberTheme.surfaceCard,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 11, color: EmberTheme.textPrimary),
                items: AudioCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.name.toUpperCase()))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => audio.category = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ScrubbableField(
                  label: 'Volume',
                  value: audio.volume,
                  step: 0.05,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (val) => audio.volume = val,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScrubbableField(
                  label: 'Pitch',
                  value: audio.pitch,
                  step: 0.1,
                  min: 0.1,
                  max: 3.0,
                  onChanged: (val) => audio.pitch = val,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Spatial 3D:', style: TextStyle(fontSize: 10, color: EmberTheme.textMuted)),
              const Spacer(),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: audio.is3D,
                  activeTrackColor: EmberTheme.accentGreen,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) => setState(() => audio.is3D = val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 24,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: EmberTheme.surfaceCard,
                padding: EdgeInsets.zero,
              ),
              onPressed: () {
                AudioSystem.instance.play(clip: audio.clip, category: audio.category, volume: audio.volume, pitch: audio.pitch);
              },
              icon: const Icon(Icons.play_arrow, size: 14, color: EmberTheme.accentGreen),
              label: const Text('Preview Synthesizer Sound', style: TextStyle(fontSize: 10, color: EmberTheme.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }

  static bool _hasCustomCard(EmberComponent c) =>
      c is Transform3DComponent ||
      c is Transform2DComponent ||
      c is MeshRenderer3DComponent ||
      c is LightComponent ||
      c is CameraComponent ||
      c is RigidBody3DComponent ||
      c is Collider3DComponent ||
      c is CharacterController3DComponent ||
      c is ParticleEmitter3DComponent ||
      c is FlameSpriteComponent ||
      c is FlameHitbox2DComponent ||
      c is FlameTileMapComponent ||
      c is CharacterController2DComponent ||
      c is ParticleEmitter2DComponent ||
      c is AudioSourceComponent ||
      c is ScriptComponent;

  Widget _buildScriptCard(ScriptComponent script) {
    // Names come from the registry, so user scripts in lib/game appear too.
    final scriptPresets = ScriptRegistry.availableScripts..sort();
    if (scriptPresets.isEmpty) scriptPresets.add('');

    return CompactAccordion(
      title: 'Script Component',
      icon: Icons.code,
      isEnabled: script.enabled,
      onEnableChanged: (val) => script.enabled = val,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Script:', style: TextStyle(fontSize: 11, color: EmberTheme.textMuted)),
              const Spacer(),
              DropdownButton<String>(
                value: scriptPresets.contains(script.scriptName) ? script.scriptName : null,
                hint: const Text('Choose script', style: TextStyle(fontSize: 11)),
                dropdownColor: EmberTheme.surfaceCard,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 11, color: EmberTheme.textPrimary),
                items: scriptPresets.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => script.scriptName = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            script.scriptInstance == null
                ? 'Script "${script.scriptName}" is not registered (see lib/game/game_scripts.dart)'
                : 'Runs: ${script.scriptName}',
            style: TextStyle(
              fontSize: 10,
              color: script.scriptInstance == null ? EmberTheme.accentRed : EmberTheme.textSecondary,
            ),
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
          case 'RigidBody3D':
            entity.addComponent(RigidBody3DComponent());
            break;
          case 'Collider3D':
            entity.addComponent(Collider3DComponent());
            break;
          case 'CharacterController3D':
            entity.addComponent(CharacterController3DComponent());
            break;
          case 'ParticleEmitter3D':
            entity.addComponent(ParticleEmitter3DComponent());
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
          case 'CharacterController2D':
            entity.addComponent(CharacterController2DComponent());
            break;
          case 'ParticleEmitter2D':
            entity.addComponent(ParticleEmitter2DComponent());
            break;
          case 'AudioSource':
            entity.addComponent(AudioSourceComponent());
            break;
          case 'Script':
            entity.addComponent(ScriptComponent(scriptName: 'Procedural Rotator'));
            break;
          case 'Camera2D':
            if (!entity.hasComponent<Transform2DComponent>()) entity.addComponent(Transform2DComponent());
            entity.addComponent(Camera2DComponent());
            break;
          case 'UIText':
            entity.addComponent(UITextComponent());
            break;
        }
        setState(() {});
      },
      itemBuilder: (context) => const [
        PopupMenuItem(enabled: false, child: Text('--- 3D Subsystems ---', style: TextStyle(fontSize: 10, color: EmberTheme.textMuted))),
        PopupMenuItem(value: 'MeshRenderer3D', child: Text('Mesh Renderer 3D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'Light', child: Text('Light Source', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'Camera', child: Text('Camera', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'RigidBody3D', child: Text('RigidBody 3D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'Collider3D', child: Text('Collider 3D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'CharacterController3D', child: Text('FPS Character Controller 3D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'ParticleEmitter3D', child: Text('Particle Emitter 3D', style: TextStyle(fontSize: 11))),
        PopupMenuDivider(height: 1),
        PopupMenuItem(enabled: false, child: Text('--- 2D Subsystems ---', style: TextStyle(fontSize: 10, color: EmberTheme.textMuted))),
        PopupMenuItem(value: 'FlameSprite', child: Text('Flame Sprite 2D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'FlameHitbox', child: Text('Flame Hitbox 2D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'FlameTileMap', child: Text('Flame TileMap 2D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'CharacterController2D', child: Text('Platformer Controller 2D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'ParticleEmitter2D', child: Text('Particle Emitter 2D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'Camera2D', child: Text('Camera 2D', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'UIText', child: Text('UI Text (on-screen)', style: TextStyle(fontSize: 11))),
        PopupMenuDivider(height: 1),
        PopupMenuItem(enabled: false, child: Text('--- Core Subsystems ---', style: TextStyle(fontSize: 10, color: EmberTheme.textMuted))),
        PopupMenuItem(value: 'AudioSource', child: Text('Audio Source', style: TextStyle(fontSize: 11))),
        PopupMenuItem(value: 'Script', child: Text('Gameplay Script', style: TextStyle(fontSize: 11))),
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

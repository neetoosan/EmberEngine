import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/event_bus.dart';
import '../../core/transform2d.dart';
import '../../core/transform3d.dart';
import '../../subsystems/three_d/components3d.dart';
import '../../subsystems/three_d/material.dart';
import '../../subsystems/two_d/flame_components.dart';
import '../../subsystems/two_d/tilemap_editor.dart';
import '../theme/ember_theme.dart';

/// Bottom Drawer containing Console Logger, Asset Browser, and Tilemap Palette.
///
/// Can be expanded (~200px) or collapsed into a 28px status footer bar (toggle with ~).
class BottomDrawer extends StatefulWidget {
  final EmberEngine engine;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const BottomDrawer({
    super.key,
    required this.engine,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  State<BottomDrawer> createState() => _BottomDrawerState();
}

class _BottomDrawerState extends State<BottomDrawer> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  LogSeverity? _severityFilter;
  String _searchFilter = '';
  final TextEditingController _cmdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cmdController.dispose();
    super.dispose();
  }

  void _runCommand(String cmd) {
    final trimmed = cmd.trim().toLowerCase();
    _cmdController.clear();
    if (trimmed.isEmpty) return;

    widget.engine.log('> $trimmed', severity: LogSeverity.info, source: 'CLI');

    if (trimmed == 'clear') {
      widget.engine.clearLogs();
    } else if (trimmed == 'play') {
      widget.engine.play();
    } else if (trimmed == 'pause') {
      widget.engine.pause();
    } else if (trimmed == 'stop') {
      widget.engine.stop();
    } else if (trimmed == 'mode 2d') {
      widget.engine.setMode(EngineMode.twoD);
    } else if (trimmed == 'mode 3d') {
      widget.engine.setMode(EngineMode.threeD);
    } else if (trimmed.startsWith('spawn cube')) {
      final e = EmberEntity(name: 'Console Cube');
      e.addComponent(Transform3DComponent(position: vm.Vector3(0, 2, 0)));
      e.addComponent(MeshRenderer3DComponent(primitiveType: MeshPrimitiveType.cube));
      widget.engine.activeScene.addEntity(e);
      widget.engine.selectEntity(e);
      widget.engine.log('Spawned Cube at (0, 2, 0)', source: 'CLI');
    } else if (trimmed.startsWith('spawn sphere')) {
      final e = EmberEntity(name: 'Console Sphere');
      e.addComponent(Transform3DComponent(position: vm.Vector3(0, 2, 0)));
      e.addComponent(MeshRenderer3DComponent(
        primitiveType: MeshPrimitiveType.sphere,
        material: Material3D(color: const Color(0xFF10B981)),
      ));
      widget.engine.activeScene.addEntity(e);
      widget.engine.selectEntity(e);
      widget.engine.log('Spawned Sphere at (0, 2, 0)', source: 'CLI');
    } else if (trimmed == 'help') {
      widget.engine.log(
        'Commands: play, pause, stop, mode 2d, mode 3d, spawn cube, spawn sphere, clear, help',
        source: 'CLI',
      );
    } else {
      widget.engine.log('Unknown command: "$trimmed". Type "help" for list.', severity: LogSeverity.warning, source: 'CLI');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isExpanded) {
      return _buildCollapsedFooter();
    }

    return Container(
      height: 200,
      decoration: const BoxDecoration(
        color: EmberTheme.surfacePanel,
        border: Border(
          top: BorderSide(color: EmberTheme.borderMedium, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Drawer Header Tab Bar
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: EmberTheme.borderSubtle, width: 1)),
            ),
            child: Row(
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: Colors.white,
                  unselectedLabelColor: EmberTheme.textMuted,
                  labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  indicatorColor: EmberTheme.accentEmber,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabAlignment: TabAlignment.start,
                  tabs: const [
                    Tab(child: Row(children: [Icon(Icons.terminal, size: 13), SizedBox(width: 4), Text('Console')])),
                    Tab(child: Row(children: [Icon(Icons.folder_outlined, size: 13), SizedBox(width: 4), Text('Asset Browser')])),
                    Tab(child: Row(children: [Icon(Icons.grid_view_rounded, size: 13), SizedBox(width: 4), Text('Tilemap Palette')])),
                  ],
                ),
                const Spacer(),
                // Collapse button
                Tooltip(
                  message: 'Collapse Drawer (~)',
                  child: InkWell(
                    onTap: widget.onToggleExpand,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.keyboard_arrow_down, size: 16, color: EmberTheme.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tab Content Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildConsoleTab(),
                _buildAssetBrowserTab(),
                TilemapPaletteWidget(engine: widget.engine),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedFooter() {
    final latestLog = widget.engine.logs.isNotEmpty ? widget.engine.logs.last : null;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: EmberTheme.surfacePanel,
        border: Border(
          top: BorderSide(color: EmberTheme.borderMedium, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Expand Button
          InkWell(
            onTap: widget.onToggleExpand,
            child: const Row(
              children: [
                Icon(Icons.terminal, size: 13, color: EmberTheme.textSecondary),
                SizedBox(width: 4),
                Text(
                  'Console & Assets',
                  style: TextStyle(color: EmberTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                ),
                SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_up, size: 14, color: EmberTheme.textMuted),
              ],
            ),
          ),

          const SizedBox(width: 16),
          Container(width: 1, height: 14, color: EmberTheme.borderSubtle),
          const SizedBox(width: 16),

          // Latest log entry snippet
          if (latestLog != null) ...[
            Icon(
              latestLog.severity == LogSeverity.error
                  ? Icons.error_outline
                  : latestLog.severity == LogSeverity.warning
                      ? Icons.warning_amber_outlined
                      : Icons.info_outline,
              size: 13,
              color: latestLog.severity == LogSeverity.error
                  ? EmberTheme.accentRed
                  : latestLog.severity == LogSeverity.warning
                      ? EmberTheme.accentAmber
                      : EmberTheme.accentBlue,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${latestLog.formattedTime} [${latestLog.source ?? "Core"}]: ${latestLog.message}',
                style: EmberTheme.codeStyle.copyWith(fontSize: 10, color: EmberTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConsoleTab() {
    final logs = widget.engine.logs.where((l) {
      if (_severityFilter != null && l.severity != _severityFilter) return false;
      if (_searchFilter.isNotEmpty && !l.message.toLowerCase().contains(_searchFilter)) return false;
      return true;
    }).toList();

    return Column(
      children: [
        // Console Toolbar
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: EmberTheme.surfaceCard,
          child: Row(
            children: [
              _buildFilterBtn('All', null),
              const SizedBox(width: 4),
              _buildFilterBtn('Info', LogSeverity.info),
              const SizedBox(width: 4),
              _buildFilterBtn('Warn', LogSeverity.warning),
              const SizedBox(width: 4),
              _buildFilterBtn('Error', LogSeverity.error),
              const SizedBox(width: 12),
              // Search input
              Expanded(
                child: SizedBox(
                  height: 20,
                  child: TextField(
                    style: const TextStyle(fontSize: 10, color: EmberTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Filter logs...',
                      hintStyle: TextStyle(fontSize: 10, color: EmberTheme.textMuted),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 4),
                    ),
                    onChanged: (val) => setState(() => _searchFilter = val.toLowerCase()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Clear logs button
              Tooltip(
                message: 'Clear Console',
                child: InkWell(
                  onTap: () => widget.engine.clearLogs(),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.block, size: 13, color: EmberTheme.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Logs Output Area
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[logs.length - 1 - index];
              Color textColor = EmberTheme.textPrimary;
              Color iconColor = EmberTheme.accentBlue;
              IconData icon = Icons.info_outline;

              if (log.severity == LogSeverity.error) {
                textColor = EmberTheme.accentRed;
                iconColor = EmberTheme.accentRed;
                icon = Icons.error_outline;
              } else if (log.severity == LogSeverity.warning) {
                textColor = EmberTheme.accentAmber;
                iconColor = EmberTheme.accentAmber;
                icon = Icons.warning_amber_outlined;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.formattedTime,
                      style: EmberTheme.codeStyle.copyWith(color: EmberTheme.textMuted, fontSize: 10),
                    ),
                    const SizedBox(width: 6),
                    Icon(icon, size: 12, color: iconColor),
                    const SizedBox(width: 6),
                    if (log.source != null) ...[
                      Text(
                        '[${log.source}]',
                        style: EmberTheme.codeStyle.copyWith(
                          color: EmberTheme.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        log.message,
                        style: EmberTheme.codeStyle.copyWith(color: textColor, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // CLI Command Runner Input
        Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            color: EmberTheme.surfaceCard,
            border: Border(top: BorderSide(color: EmberTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              const Text('>', style: TextStyle(color: EmberTheme.accentEmber, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _cmdController,
                  style: EmberTheme.codeStyle.copyWith(fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: 'Enter engine CLI command (e.g. spawn cube, mode 2d, play, help)...',
                    hintStyle: TextStyle(fontSize: 10, color: EmberTheme.textMuted),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: _runCommand,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBtn(String label, LogSeverity? severity) {
    final isSelected = _severityFilter == severity;
    return InkWell(
      onTap: () => setState(() => _severityFilter = severity),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? EmberTheme.borderHighlight : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : EmberTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildAssetBrowserTab() {
    final assets = [
      {'name': 'hero_player.png', 'type': 'sprite', 'size': '64 KB'},
      {'name': 'tilemap_dungeon.png', 'type': 'tiles', 'size': '256 KB'},
      {'name': 'sci_fi_crate.glb', 'type': 'mesh', 'size': '1.2 MB'},
      {'name': 'environment_sky.hdr', 'type': 'texture', 'size': '4.5 MB'},
      {'name': 'laser_blast.wav', 'type': 'audio', 'size': '180 KB'},
      {'name': 'player_controller.dart', 'type': 'script', 'size': '4 KB'},
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.1,
        ),
        itemCount: assets.length,
        itemBuilder: (context, index) {
          final asset = assets[index];
          IconData icon = Icons.insert_drive_file;
          Color color = EmberTheme.textSecondary;

          if (asset['type'] == 'sprite' || asset['type'] == 'tiles') {
            icon = Icons.image;
            color = EmberTheme.accentFlame;
          } else if (asset['type'] == 'mesh') {
            icon = Icons.view_in_ar;
            color = EmberTheme.accentEmber;
          } else if (asset['type'] == 'audio') {
            icon = Icons.audiotrack;
            color = EmberTheme.accentAmber;
          } else if (asset['type'] == 'script') {
            icon = Icons.code;
            color = EmberTheme.accentGreen;
          }

          return InkWell(
            onDoubleTap: () => _instantiateAsset(asset),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: EmberTheme.surfaceCard,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: EmberTheme.borderSubtle),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: color),
                  const SizedBox(height: 4),
                  Text(
                    asset['name']!,
                    style: const TextStyle(fontSize: 10, color: EmberTheme.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    asset['size']!,
                    style: const TextStyle(fontSize: 8, color: EmberTheme.textMuted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _instantiateAsset(Map<String, String> asset) {
    final name = asset['name']!;
    final type = asset['type']!;

    if (type == 'sprite') {
      final ent = EmberEntity(name: name);
      ent.addComponent(Transform2DComponent(size: vm.Vector2(48, 48)));
      ent.addComponent(FlameSpriteComponent(assetPath: 'assets/sprites/$name'));
      widget.engine.activeScene.addEntity(ent);
      widget.engine.selectEntity(ent);
      widget.engine.log('Instantiated Sprite: $name', source: 'AssetBrowser');
    } else if (type == 'mesh') {
      final ent = EmberEntity(name: name);
      ent.addComponent(Transform3DComponent(position: vm.Vector3(0, 1, 0)));
      ent.addComponent(MeshRenderer3DComponent(primitiveType: MeshPrimitiveType.cube));
      widget.engine.activeScene.addEntity(ent);
      widget.engine.selectEntity(ent);
      widget.engine.log('Instantiated Mesh: $name', source: 'AssetBrowser');
    }
  }
}

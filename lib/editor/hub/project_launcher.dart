import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme/ember_theme.dart';
import 'project_manifest.dart';
import 'project_storage.dart';
import 'template_manifest.dart';
import 'project_package.dart';

/// Full-screen Startup Hub / Project Launcher for Ember Engine.
class ProjectLauncherScreen extends StatefulWidget {
  final void Function(EmberProject project) onOpenProject;

  const ProjectLauncherScreen({
    super.key,
    required this.onOpenProject,
  });

  @override
  State<ProjectLauncherScreen> createState() => _ProjectLauncherScreenState();
}

class _ProjectLauncherScreenState extends State<ProjectLauncherScreen> {
  int _selectedNavIndex = 0; // 0: Templates, 1: Recent, 2: Open/Import, 3: About
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openNewProjectWizard([ProjectTemplate? initialTemplate]) {
    showDialog(
      context: context,
      builder: (ctx) => _NewProjectWizardDialog(
        initialTemplate: initialTemplate ?? TemplateCatalog.templates.first,
        // The editor gives the new project a folder on disk and records it in recents.
        onCreate: widget.onOpenProject,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _openFromDisk(String path) async {
    try {
      final project = await ProjectStorage.load(path);
      widget.onOpenProject(project);
    } catch (e) {
      if (mounted) _showError('Could not open project at $path: $e');
    }
  }

  Future<void> _browseForProject() async {
    if (!ProjectStorage.isSupported) {
      _showError('Opening project folders is not available in the web build.');
      return;
    }
    String? initial;
    try {
      initial = (await ProjectStorage.defaultProjectsRoot()).path;
    } catch (_) {}
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: 'Open Ember project folder (contains ${ProjectStorage.manifestFileName})',
      initialDirectory: initial,
    );
    if (picked != null) await _openFromDisk(picked);
  }

  void _openImportPackageDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EmberTheme.panelBg,
        title: const Row(
          children: [
            Icon(Icons.archive_outlined, color: EmberTheme.emberOrange, size: 20),
            SizedBox(width: 8),
            Text('Import .emberpkg Package', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste the JSON content of an exported .emberpkg bundle to restore the project and its scenes:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white),
                decoration: InputDecoration(
                  hintText: '{\n  "signature": "EMBER_ENGINE_PROJECT_PACKAGE", ...\n}',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: EmberTheme.canvasBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.emberOrange),
            onPressed: () {
              final raw = textController.text.trim();
              if (raw.isEmpty) return;
              try {
                final project = ProjectPackageManager.importFromPackageString(raw);
                // Always import into a fresh folder; never overwrite the original project.
                project.path = 'imported/${ProjectStorage.slug(project.name)}';
                Navigator.of(ctx).pop();
                widget.onOpenProject(project);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to import package: $e'), backgroundColor: Colors.redAccent),
                );
              }
            },
            icon: const Icon(Icons.file_download_done_rounded, size: 16),
            label: const Text('Import & Launch'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmberTheme.canvasBg,
      body: Row(
        children: [
          // Left Navigation Sidebar
          _buildSidebar(),

          // Main Content View
          Expanded(
            child: Column(
              children: [
                _buildTopHeader(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedNavIndex,
                    children: [
                      _buildTemplatesView(),
                      _buildRecentProjectsView(),
                      _buildOpenImportView(),
                      _buildAboutView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: EmberTheme.panelBg,
        border: Border(right: BorderSide(color: EmberTheme.borderMuted)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: EmberTheme.emberOrange.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: EmberTheme.emberOrange, width: 1.5),
                  ),
                  child: const Icon(Icons.local_fire_department_rounded, color: EmberTheme.emberOrange, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMBER',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 2.0,
                      ),
                    ),
                    Text(
                      'GAME ENGINE',
                      style: TextStyle(
                        color: EmberTheme.emberOrange,
                        fontSize: 9,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(color: EmberTheme.borderMuted, height: 1),
          const SizedBox(height: 12),

          // Navigation Links
          _buildNavItem(0, 'Project Templates', Icons.dashboard_customize_rounded),
          _buildNavItem(1, 'Recent Projects', Icons.history_rounded),
          _buildNavItem(2, 'Open & Import', Icons.folder_open_rounded),
          _buildNavItem(3, 'Engine Info', Icons.info_outline_rounded),

          const Spacer(),

          // Quick Action: New Project
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: EmberTheme.emberOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => _openNewProjectWizard(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Project', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Text(
              'v1.0.0 • Pure Dart & Flutter ECS',
              style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String label, IconData icon) {
    final isSelected = _selectedNavIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedNavIndex = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? EmberTheme.emberOrange.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: EmberTheme.emberOrange.withAlpha(80)) : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? EmberTheme.emberOrange : Colors.white60,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: const BoxDecoration(
        color: EmberTheme.panelBg,
        border: Border(bottom: BorderSide(color: EmberTheme.borderMuted)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getTitleForTab(),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                _getSubtitleForTab(),
                style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          // Search Field (active for Recents & Templates)
          if (_selectedNavIndex == 0 || _selectedNavIndex == 1)
            SizedBox(
              width: 260,
              height: 36,
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search projects or templates...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                  prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14, color: Colors.white54),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: EmberTheme.canvasBg,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getTitleForTab() {
    switch (_selectedNavIndex) {
      case 0:
        return 'Starter Templates';
      case 1:
        return 'Recent Projects';
      case 2:
        return 'Open & Import Projects';
      case 3:
      default:
        return 'Ember Engine Overview';
    }
  }

  String _getSubtitleForTab() {
    switch (_selectedNavIndex) {
      case 0:
        return 'Jumpstart your game with ready-to-play 2D, 3D, and VFX architectures';
      case 1:
        return 'Quickly resume work on your local Ember game projects';
      case 2:
        return 'Load existing project folders or unpack portable .emberpkg archives';
      case 3:
      default:
        return 'Architecture, Subsystems, ECS Foundation & Performance Specs';
    }
  }

  // --- Views ---

  Widget _buildTemplatesView() {
    final query = _searchQuery.toLowerCase();
    final templates = TemplateCatalog.templates.where((t) {
      if (query.isEmpty) return true;
      return t.title.toLowerCase().contains(query) ||
          t.description.toLowerCase().contains(query) ||
          t.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: GridView.builder(
        itemCount: templates.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 18,
          mainAxisSpacing: 18,
          childAspectRatio: 1.5,
        ),
        itemBuilder: (ctx, idx) {
          final t = templates[idx];
          return _buildTemplateCard(t);
        },
      ),
    );
  }

  Widget _buildTemplateCard(ProjectTemplate t) {
    return Container(
      decoration: BoxDecoration(
        color: EmberTheme.panelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EmberTheme.borderMuted),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openNewProjectWizard(t),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: t.accentColor.withAlpha(40),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(t.icon, color: t.accentColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.subtitle,
                            style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: EmberTheme.canvasBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: EmberTheme.borderMuted),
                      ),
                      child: Text(
                        t.defaultPipeline.shortCode,
                        style: TextStyle(
                          color: t.accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  t.description,
                  style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 11, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: t.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: EmberTheme.canvasBg,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(tag, style: const TextStyle(color: Colors.white60, fontSize: 9)),
                    );
                  }).toList(),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${t.features.length} core features bundled',
                      style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 10),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => _openNewProjectWizard(t),
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: const Text('Create Project', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentProjectsView() {
    final recents = RecentProjectsManager.instance.search(_searchQuery);

    if (recents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_rounded, size: 48, color: Colors.white.withAlpha(60)),
            const SizedBox(height: 12),
            const Text('No recent projects found', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.emberOrange),
              onPressed: () => _openNewProjectWizard(),
              child: const Text('Create New Project'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: recents.length,
      itemBuilder: (ctx, idx) {
        final item = recents[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: EmberTheme.panelBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EmberTheme.borderMuted),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: EmberTheme.canvasBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: EmberTheme.borderMuted),
              ),
              child: Center(
                child: Text(
                  item.renderPipeline.shortCode,
                  style: const TextStyle(color: EmberTheme.emberOrange, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
            title: Row(
              children: [
                Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: EmberTheme.canvasBg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(item.templateName, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(item.path, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 11)),
                if (item.previewSnippet != null) ...[
                  const SizedBox(height: 2),
                  Text(item.previewSnippet!, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: item.isPinned ? 'Unpin project' : 'Pin project',
                  icon: Icon(
                    item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 16,
                    color: item.isPinned ? EmberTheme.emberOrange : Colors.white38,
                  ),
                  onPressed: () {
                    setState(() {
                      RecentProjectsManager.instance.togglePin(item.id);
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Remove from recents',
                  icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                  onPressed: () {
                    setState(() {
                      RecentProjectsManager.instance.removeRecent(item.id);
                    });
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EmberTheme.surfaceBg,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: EmberTheme.borderMuted),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () => _openFromDisk(item.path),
                  child: const Text('Open Project', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOpenImportView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Open or Import Project Packages', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            'Ember Engine projects can be restored from disk folders or imported as single-file portable packages.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildImportCard(
                  title: 'Import .emberpkg Package',
                  subtitle: 'Restore a complete single-file project archive (Scenes, Scripts, and Assets)',
                  icon: Icons.inventory_2_rounded,
                  accentColor: EmberTheme.emberOrange,
                  buttonLabel: 'Import Package JSON',
                  onTap: _openImportPackageDialog,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildImportCard(
                  title: 'Open Existing Project Folder',
                  subtitle: 'Browse your local filesystem for a folder containing ${ProjectStorage.manifestFileName}',
                  icon: Icons.folder_open_rounded,
                  accentColor: const Color(0xFF3B82F6),
                  buttonLabel: 'Browse Folder',
                  onTap: _browseForProject,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImportCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: EmberTheme.panelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EmberTheme.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 11, height: 1.4)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: onTap,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(buttonLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: EmberTheme.panelBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: EmberTheme.borderMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.local_fire_department_rounded, color: EmberTheme.emberOrange, size: 28),
                SizedBox(width: 12),
                Text('Ember Game Engine', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Spacer(),
                Chip(
                  backgroundColor: EmberTheme.canvasBg,
                  label: Text('Pure Flutter & Dart Engine', style: TextStyle(color: Colors.white70, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'A modern, lightweight 2D/3D Game Engine and integrated authoring workstation built on Flutter. '
              'Features unified Entity-Component-System (ECS) architecture, Flame 2D tilemaps, 3D viewport with '
              'procedural primitives and lighting, spatial audio, dual particle emitters, interactive gizmos, '
              'and in-engine visual scripting.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 20),
            const Divider(color: EmberTheme.borderMuted),
            const SizedBox(height: 16),
            const Text('Subsystems Status:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildStatusItem('ECS Core Engine', 'Active (Entity, Component, SceneSerializer, EventBus, InputManager)'),
            _buildStatusItem('2D Viewport & Physics', 'Active (FlameSprite, TileMap, Hitbox, CharacterController2D)'),
            _buildStatusItem('3D Viewport & Physics', 'Active (MeshRenderer3D, Camera3D, Lighting, CharacterController3D)'),
            _buildStatusItem('VFX & Particles', 'Active (ParticleEmitter2D & ParticleEmitter3D with GPU presets)'),
            _buildStatusItem('Audio Subsystem', 'Active (Procedural SFX Synthesizer & Spatial AudioSource)'),
            _buildStatusItem('Scripting & Compiler', 'Active (GameScript, Visual Code Bridge & Ember Doctor)'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 8),
          Text('$title: ', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          Expanded(child: Text(desc, style: const TextStyle(color: Colors.white60, fontSize: 11))),
        ],
      ),
    );
  }
}

/// Modal Wizard Dialog for creating a new project.
class _NewProjectWizardDialog extends StatefulWidget {
  final ProjectTemplate initialTemplate;
  final void Function(EmberProject project) onCreate;

  const _NewProjectWizardDialog({
    required this.initialTemplate,
    required this.onCreate,
  });

  @override
  State<_NewProjectWizardDialog> createState() => _NewProjectWizardDialogState();
}

class _NewProjectWizardDialogState extends State<_NewProjectWizardDialog> {
  late ProjectTemplate _selectedTemplate;
  late TextEditingController _nameController;
  late TextEditingController _authorController;
  late RenderPipelineMode _selectedPipeline;

  @override
  void initState() {
    super.initState();
    _selectedTemplate = widget.initialTemplate;
    _nameController = TextEditingController(text: 'My ${_selectedTemplate.title}');
    _authorController = TextEditingController(text: 'Ember Developer');
    _selectedPipeline = _selectedTemplate.defaultPipeline;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: EmberTheme.panelBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Row(
        children: [
          Icon(_selectedTemplate.icon, color: _selectedTemplate.accentColor, size: 22),
          const SizedBox(width: 10),
          const Text('New Ember Project Wizard', style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Template Selector Carousel
              const Text('Select Starter Template:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: TemplateCatalog.templates.length,
                  itemBuilder: (ctx, idx) {
                    final t = TemplateCatalog.templates[idx];
                    final isSelected = t.type == _selectedTemplate.type;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedTemplate = t;
                          _selectedPipeline = t.defaultPipeline;
                          _nameController.text = 'My ${t.title}';
                        });
                      },
                      child: Container(
                        width: 135,
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected ? t.accentColor.withAlpha(40) : EmberTheme.canvasBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isSelected ? t.accentColor : EmberTheme.borderMuted, width: isSelected ? 1.5 : 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(t.icon, size: 18, color: isSelected ? t.accentColor : Colors.white60),
                            const Spacer(),
                            Text(
                              t.title,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 18),

              // Project Name
              const Text('Project Name', style: TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: EmberTheme.canvasBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 14),

              // Author
              const Text('Author', style: TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: _authorController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: EmberTheme.canvasBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 14),

              // Render Pipeline Mode
              const Text('Render Pipeline Mode', style: TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: EmberTheme.canvasBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<RenderPipelineMode>(
                    value: _selectedPipeline,
                    dropdownColor: EmberTheme.panelBg,
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    items: RenderPipelineMode.values.map((p) {
                      return DropdownMenuItem(
                        value: p,
                        child: Text(p.label),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedPipeline = val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedTemplate.accentColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final proj = _selectedTemplate.createProject(
              name: _nameController.text.trim(),
              author: _authorController.text.trim(),
              overridePipeline: _selectedPipeline,
            );
            Navigator.of(context).pop();
            widget.onCreate(proj);
          },
          icon: const Icon(Icons.rocket_launch_rounded, size: 16),
          label: const Text('Create & Launch Editor'),
        ),
      ],
    );
  }
}

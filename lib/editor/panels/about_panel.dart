import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/crash_reporter.dart';
import '../../core/version.dart';
import '../theme/ember_theme.dart';

/// Version, what the engine includes (and doesn't yet), open-source licences,
/// logs and a problem report. Used on the Hub's About page and in the
/// editor's About dialog.
class AboutEmberContent extends StatelessWidget {
  const AboutEmberContent({super.key});

  /// What exists today. Keep every line true.
  static const List<(String, String)> features = [
    ('Editor', 'Scenes, hierarchy, inspector, undo/redo, tile painting, autosave and crash recovery'),
    ('2D', 'Sprites and sprite sheets, animator, tilemaps, parallax, Camera 2D with zoom and shake, particles, Line 2D'),
    ('Physics', 'Rigid bodies (Box2D: stacking, joints, impacts, explosions), platformer and top-down controllers'),
    ('Gameplay', 'Health and combat, monster AI with pathfinding, doors and levels, dialogue, UI buttons, bars and text, saving'),
    ('Scripting', 'Ember Script: a Dart-like language with live reload, autocomplete, error markers and an API reference'),
    ('Audio', 'Sound effects and music, built-in procedural sounds, 2D/3D positional panning'),
    ('3D (basic)', 'Primitive meshes, lights, materials, first-person controller; objects are depth-sorted, no shadows'),
    ('Export', 'Windows, web and Android (APK)'),
  ];

  static const List<String> notYet = [
    'macOS, Linux and iOS export',
    'Shadows and a true 3D depth buffer',
    'Gamepad input',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.local_fire_department_rounded, color: EmberTheme.emberOrange, size: 28),
            const SizedBox(width: 12),
            Text(EmberVersion.productName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Text('Version ${EmberVersion.version}', key: const ValueKey('about-version'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'A 2D-first game engine and editor built with Flutter. Make a game in the editor, script it in Ember Script, '
          'and export it as a Windows program, a web page or an Android app.',
          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 6),
        const Text(EmberVersion.copyright, key: ValueKey('about-copyright'), style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 16),
        const Text("What's included", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final (title, desc) in features) _row(Icons.check_circle_rounded, Colors.greenAccent, title, desc),
        const SizedBox(height: 10),
        const Text('Not available yet', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final item in notYet) _row(Icons.schedule_rounded, Colors.white38, item, ''),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('about-licenses'),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: EmberVersion.productName,
                applicationVersion: EmberVersion.version,
                applicationLegalese: '${EmberVersion.copyright}\nBuilt with Flutter, Flame, forge2d and other open-source packages listed here.',
              ),
              icon: const Icon(Icons.gavel_rounded, size: 15),
              label: const Text('Open-source licences', style: TextStyle(fontSize: 12)),
            ),
            if (!kIsWeb && CrashReporter.logDirectory != null)
              OutlinedButton.icon(
                onPressed: CrashReporter.openLogFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 15),
                label: const Text('Open log folder', style: TextStyle(fontSize: 12)),
              ),
            OutlinedButton.icon(
              key: const ValueKey('about-report'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: CrashReporter.problemReport()));
                if (context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('Problem report copied: paste it into your support message. It contains no project files.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: const Text('Copy problem report', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _row(IconData icon, Color color, String title, String desc) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: desc.isEmpty ? title : '$title: ', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  if (desc.isNotEmpty) TextSpan(text: desc, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ]),
              ),
            ),
          ],
        ),
      );
}

/// The About dialog (editor top bar / command palette).
class AboutEmberDialog {
  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EmberTheme.panelBg,
        content: const SizedBox(width: 560, child: SingleChildScrollView(child: AboutEmberContent())),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }
}

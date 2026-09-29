import 'dart:io';
import 'package:flutter/material.dart';
import 'core/scene.dart';
import 'editor/ember_editor_app.dart';
import 'editor/hub/project_manifest.dart';
import 'editor/hub/project_storage.dart';
import 'game/game_scripts.dart';
import 'subsystems/audio/audio_output.dart';

/// Full Workstation Editor entry point for Ember Engine.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAllSubsystems();
  registerGameScripts();
  AudioOutput.instance.attach();

  // Remember recently opened projects across sessions.
  if (ProjectStorage.isSupported) {
    try {
      final root = await ProjectStorage.defaultProjectsRoot();
      await RecentProjectsManager.instance.attachStorage(
        File('${root.path}${Platform.pathSeparator}recent_projects.json'),
      );
    } catch (e) {
      debugPrint('Ember: recent projects will not be saved ($e)');
    }
  }

  runApp(const EmberEditorApp());
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/assets.dart';
import 'core/crash_reporter.dart';
import 'core/engine_loop.dart';
import 'core/save_data.dart';
import 'core/event_bus.dart';
import 'core/gamepad.dart';
import 'core/input.dart';
import 'core/scene.dart';
import 'editor/hub/project_manifest.dart';
import 'editor/hub/project_package.dart';
import 'editor/mobile/virtual_joystick.dart';
import 'editor/panels/viewport_container.dart';
import 'game/game_scripts.dart';
import 'scripting/script_library.dart';
import 'subsystems/audio/audio_output.dart';

/// Standalone Game Runtime Player Entry Point for Ember Engine.
///
/// Runs the game viewport full-screen with no editor panels, gizmos or
/// inspector. The game to run is found, in order, at:
///  1. the path given as the first command-line argument,
///  2. `game.emberpkg.json` next to the executable (what "Export Game" writes),
///  3. otherwise the built-in demo scene.
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // A script or asset problem must never close the player's game
  await CrashReporter.install(appName: 'game');
  registerAllSubsystems();
  registerGameScripts();
  // Real audio output is attached here (not in the widget) so widget tests stay silent
  AudioOutput.instance.attach();
  final project = _loadGame(args) ?? await loadBundledGame();
  // Saved progress is loaded before the first scene starts, so its scripts see it.
  // Keyed by project name (not display title) so renaming the game keeps saves.
  await SaveData.instance.open(project?.name ?? 'Ember Demo');
  // Right-click belongs to the game (strategy games), not the browser menu
  if (kIsWeb) BrowserContextMenu.disableContextMenu();
  GamepadInput.instance.start();
  runApp(EmberPlayerApp(project: project));
}

/// Where web and Android exports put the game inside the player's bundle.
const String bundledGameKey = 'assets/game/$emberGameFileName';

/// The game packed into the player's own bundle (web / Android exports), with
/// its images and sounds embedded. Null when there is none.
Future<EmberProject?> loadBundledGame() async {
  try {
    final data = await rootBundle.load(bundledGameKey);
    final text = utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    final (project, files) = ProjectPackageManager.importWithFiles(text);
    EmberAssets.instance.root = null;
    EmberAssets.instance.embedded
      ..clear()
      ..addAll(files);
    return project;
  } catch (_) {
    return null; // no bundled game: show the built-in demo
  }
}

EmberProject? _loadGame(List<String> args) {
  if (kIsWeb) return null;
  final candidates = [
    if (args.isNotEmpty) args.first,
    '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}$emberGameFileName',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final (project, files) = ProjectPackageManager.importWithFiles(file.readAsStringSync());
      // Images and other files are exported next to the game file (or embedded in it).
      EmberAssets.instance.root = file.parent.path;
      EmberAssets.instance.embedded
        ..clear()
        ..addAll(files);
      return project;
    } catch (e) {
      debugPrint('Ember Player: could not load $path: $e');
    }
  }
  return null;
}

class EmberPlayerApp extends StatefulWidget {
  final EmberScene? initialScene;
  final EmberProject? project;

  const EmberPlayerApp({super.key, this.initialScene, this.project});

  @override
  State<EmberPlayerApp> createState() => _EmberPlayerAppState();
}

class _EmberPlayerAppState extends State<EmberPlayerApp> {
  final EmberEngine _engine = EmberEngine.instance;
  final FocusNode _focusNode = FocusNode();
  bool _showTouchControls = false;

  @override
  void initState() {
    super.initState();
    registerAllSubsystems();
    Input.bindHardwareKeyboard();

    final project = widget.project;
    if (project != null) {
      // The game's Ember Scripts, before any scene starts
      EmberScripts.instance.loadAll(project.scripts);
      // Every level of the game, captured before play so loadLevel always starts fresh
      final levels = {for (final e in project.scenes.entries) e.key: e.value.toJson()};
      _engine.sceneLibrary = () => levels;
      _engine.setMode(project.renderPipeline == RenderPipelineMode.twoD ? EngineMode.twoD : EngineMode.threeD);
      _engine.loadScene(project.activeScene);
    } else if (widget.initialScene != null) {
      _engine.loadScene(widget.initialScene!);
    }

    // Touch controls by default on phones and tablets
    _showTouchControls = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    // Auto-start simulation in player runtime
    _engine.play();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _engine.stop();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    // Gameplay keys reach Input through the hardware keyboard binding; only player chrome here.
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f1) {
      setState(() => _showTouchControls = !_showTouchControls);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.project?.gameTitle ?? 'Ember Game',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121316),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF121316),
        body: KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: Stack(
            // Fill the window: the overlay may be zero-sized, which would otherwise collapse the stack.
            fit: StackFit.expand,
            children: [
              // 1. Fullscreen Viewport Canvas
              Positioned.fill(
                child: ViewportContainer(engine: _engine),
              ),

              // 2. Touch Overlay (F1 toggles on desktop)
              VirtualJoystickOverlay(isVisible: _showTouchControls),
            ],
          ),
        ),
      ),
    );
  }
}

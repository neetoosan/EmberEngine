import 'package:flutter/material.dart';
import '../theme/ember_theme.dart';
import '../hub/project_manifest.dart';

/// In-Engine Multi-Tab Script Editor & Visual Code Bridge.
class ScriptEditorPanel extends StatefulWidget {
  final EmberProject? project;
  final VoidCallback? onSave;

  const ScriptEditorPanel({
    super.key,
    this.project,
    this.onSave,
  });

  @override
  State<ScriptEditorPanel> createState() => _ScriptEditorPanelState();
}

class _ScriptEditorPanelState extends State<ScriptEditorPanel> {
  // Tabs: filename -> content
  final Map<String, String> _openFiles = {};
  String _activeTab = '';
  late DartSyntaxTextController _codeController;
  bool _isVisualBridgeMode = false;
  String _syntaxStatus = 'Syntax Valid (Dart 3.x)';
  bool _hasSyntaxError = false;

  // Visual script parameters
  final Map<String, dynamic> _visualBehaviorParams = {
    'behaviorType': 'PlayerController',
    'moveSpeed': 240.0,
    'jumpForce': 480.0,
    'enableAudio': true,
    'audioClip': 'laser',
    'enableSparks': true,
    'gravityModifier': 980.0,
    'patrolRange': 120.0,
  };

  @override
  void initState() {
    super.initState();
    _codeController = DartSyntaxTextController();
    _codeController.addListener(_onCodeChanged);
    _initializeProjectScripts();
  }

  @override
  void didUpdateWidget(covariant ScriptEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.project != oldWidget.project) {
      _initializeProjectScripts();
    }
  }

  void _initializeProjectScripts() {
    _openFiles.clear();
    if (widget.project != null && widget.project!.scripts.isNotEmpty) {
      _openFiles.addAll(widget.project!.scripts);
      _activeTab = _openFiles.keys.first;
      _codeController.text = _openFiles[_activeTab]!;
    } else {
      // Default sample script
      const defaultName = 'gameplay_controller.dart';
      final defaultCode = _generateSampleScript();
      _openFiles[defaultName] = defaultCode;
      _activeTab = defaultName;
      _codeController.text = defaultCode;
    }
  }

  void _onCodeChanged() {
    if (_activeTab.isNotEmpty) {
      _openFiles[_activeTab] = _codeController.text;
      widget.project?.scripts[_activeTab] = _codeController.text;
    }
    _validateSyntax(_codeController.text);
  }

  void _validateSyntax(String code) {
    // Lightweight static syntax checks
    int openBraces = 0;
    int openParens = 0;
    for (int i = 0; i < code.length; i++) {
      if (code[i] == '{') openBraces++;
      if (code[i] == '}') openBraces--;
      if (code[i] == '(') openParens++;
      if (code[i] == ')') openParens--;
    }

    setState(() {
      if (openBraces != 0) {
        _syntaxStatus = 'Unmatched curly braces {$openBraces}';
        _hasSyntaxError = true;
      } else if (openParens != 0) {
        _syntaxStatus = 'Unmatched parentheses ($openParens)';
        _hasSyntaxError = true;
      } else {
        _syntaxStatus = 'Syntax Valid (Dart 3.x)';
        _hasSyntaxError = false;
      }
    });
  }

  void _insertSnippet(String snippet) {
    final text = _codeController.text;
    final selection = _codeController.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;

    final newText = text.replaceRange(start, end, snippet);
    _codeController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + snippet.length),
    );
  }

  void _createNewScriptTab() {
    final textCtrl = TextEditingController(text: 'new_script_${_openFiles.length + 1}.dart');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EmberTheme.panelBg,
        title: const Text('Create New Dart Script', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: textCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Script Filename',
            labelStyle: TextStyle(color: Colors.white60),
            filled: true,
            fillColor: EmberTheme.canvasBg,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: EmberTheme.emberOrange),
            onPressed: () {
              final name = textCtrl.text.trim();
              if (name.isNotEmpty) {
                final scaffold = _generateCustomScriptScaffold(name.replaceAll('.dart', ''));
                setState(() {
                  _openFiles[name] = scaffold;
                  _activeTab = name;
                  _codeController.text = scaffold;
                  widget.project?.scripts[name] = scaffold;
                });
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Create Script'),
          ),
        ],
      ),
    );
  }

  void _generateDartFromVisualBridge() {
    final behavior = _visualBehaviorParams['behaviorType'] as String;
    final speed = _visualBehaviorParams['moveSpeed'] as double;
    final jump = _visualBehaviorParams['jumpForce'] as double;
    final clip = _visualBehaviorParams['audioClip'] as String;

    final generatedDart = '''
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/subsystems/audio/audio_system.dart';
import 'package:ember_engine/subsystems/physics/character_controller2d.dart';
import 'package:ember_engine/subsystems/particles/particle_system.dart';

/// Generated Static Dart Script: $behavior
class Generated$behavior extends GameScript {
  double moveSpeed = $speed;
  double jumpVelocity = $jump;
  String soundClip = '$clip';

  late CharacterController2DComponent controller;
  ParticleEmitter2DComponent? particles;

  @override
  void onStart() {
    controller = getComponent<CharacterController2DComponent>()!;
    particles = getComponent<ParticleEmitter2DComponent>();
  }

  @override
  void onUpdate(double dt) {
    final moveX = Input.getAxis('Horizontal');
    final jumpJustPressed = Input.isActionJustPressed(EngineAction.jump);
    final jumpHeld = Input.isActionPressed(EngineAction.jump);

    if (jumpJustPressed && controller.canJump) {
      AudioSystem.instance.play(clip: soundClip);
      particles?.triggerBurst(16);
    }

    controller.updateMovement(
      horizontalInput: moveX,
      isJumpPressed: jumpHeld,
      isJumpJustPressed: jumpJustPressed,
      dt: dt,
    );
  }
}
''';

    final filename = '${behavior.toLowerCase()}_generated.dart';
    setState(() {
      _openFiles[filename] = generatedDart;
      _activeTab = filename;
      _codeController.text = generatedDart;
      _isVisualBridgeMode = false;
      widget.project?.scripts[filename] = generatedDart;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully generated static Dart script: $filename'),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EmberTheme.panelBg,
      child: Column(
        children: [
          // Top Toolbar
          _buildToolbar(),

          // File Tabs Bar
          _buildTabsBar(),

          // Main Editor or Visual Bridge Body
          Expanded(
            child: _isVisualBridgeMode ? _buildVisualBridgeView() : _buildCodeEditorView(),
          ),

          // Bottom Status Bar
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: EmberTheme.surfaceBg,
        border: Border(bottom: BorderSide(color: EmberTheme.borderMuted)),
      ),
      child: Row(
        children: [
          // View Mode Switcher
          Container(
            height: 26,
            decoration: BoxDecoration(
              color: EmberTheme.canvasBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: EmberTheme.borderMuted),
            ),
            child: Row(
              children: [
                _buildModeTab('Code View', !_isVisualBridgeMode, () {
                  setState(() => _isVisualBridgeMode = false);
                }),
                _buildModeTab('Visual Logic Bridge', _isVisualBridgeMode, () {
                  setState(() => _isVisualBridgeMode = true);
                }),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const VerticalDivider(color: EmberTheme.borderMuted, indent: 8, endIndent: 8),
          const SizedBox(width: 8),

          // Snippet Scaffolding Buttons
          if (!_isVisualBridgeMode) ...[
            _buildSnippetBtn('+ onStart()', () {
              _insertSnippet('\n  @override\n  void onStart() {\n    // Setup component bindings\n  }\n');
            }),
            _buildSnippetBtn('+ onUpdate(dt)', () {
              _insertSnippet('\n  @override\n  void onUpdate(double dt) {\n    // Frame logic\n  }\n');
            }),
            _buildSnippetBtn('+ Trigger Audio', () {
              _insertSnippet("AudioSystem.instance.play(clip: 'laser');");
            }),
            _buildSnippetBtn('+ Burst Particles', () {
              _insertSnippet("getComponent<ParticleEmitter2DComponent>()?.triggerBurst(20);");
            }),
            _buildSnippetBtn('+ Check Input', () {
              _insertSnippet("if (Input.isActionJustPressed(EngineAction.jump)) {\n      // Action\n    }");
            }),
          ] else ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: EmberTheme.emberOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(60, 26),
              ),
              onPressed: _generateDartFromVisualBridge,
              icon: const Icon(Icons.code_rounded, size: 14),
              label: const Text('Generate Static .dart Class', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],

          const Spacer(),

          // New Script Button
          IconButton(
            tooltip: 'Create New Script File',
            icon: const Icon(Icons.add_circle_outline_rounded, size: 16, color: Colors.white70),
            onPressed: _createNewScriptTab,
          ),
          IconButton(
            tooltip: 'Save All Scripts',
            icon: const Icon(Icons.save_outlined, size: 16, color: Colors.white70),
            onPressed: () {
              widget.onSave?.call();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All project scripts saved!'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        color: isSelected ? EmberTheme.emberOrange.withAlpha(40) : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? EmberTheme.emberOrange : Colors.white60,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSnippetBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: EmberTheme.canvasBg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: EmberTheme.borderMuted),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ),
      ),
    );
  }

  Widget _buildTabsBar() {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: EmberTheme.panelBg,
        border: Border(bottom: BorderSide(color: EmberTheme.borderMuted)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _openFiles.keys.map((filename) {
          final isSelected = filename == _activeTab;
          return InkWell(
            onTap: () {
              setState(() {
                _activeTab = filename;
                _codeController.text = _openFiles[filename]!;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected ? EmberTheme.canvasBg : Colors.transparent,
                border: Border(
                  right: const BorderSide(color: EmberTheme.borderMuted),
                  top: isSelected ? const BorderSide(color: EmberTheme.emberOrange, width: 2) : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.code_rounded, size: 14, color: EmberTheme.emberOrange),
                  const SizedBox(width: 6),
                  Text(
                    filename,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white60,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_openFiles.length > 1)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _openFiles.remove(filename);
                          if (_activeTab == filename) {
                            _activeTab = _openFiles.keys.first;
                            _codeController.text = _openFiles[_activeTab]!;
                          }
                        });
                      },
                      child: const Icon(Icons.close, size: 12, color: Colors.white38),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCodeEditorView() {
    return Container(
      color: EmberTheme.canvasBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line Numbers Gutter
          _buildLineNumbersGutter(),

          // Syntax Highlighted Editable Field
          Expanded(
            child: TextField(
              controller: _codeController,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
                color: Colors.white,
              ),
              cursorColor: EmberTheme.emberOrange,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineNumbersGutter() {
    final lineCount = '\n'.allMatches(_codeController.text).length + 1;
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: EmberTheme.panelBg,
        border: Border(right: BorderSide(color: EmberTheme.borderMuted)),
      ),
      child: ListView.builder(
        itemCount: lineCount,
        itemBuilder: (ctx, idx) {
          return SizedBox(
            height: 18,
            child: Text(
              '${idx + 1}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.white.withAlpha(80),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVisualBridgeView() {
    return Container(
      color: EmberTheme.canvasBg,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.schema_rounded, color: EmberTheme.emberOrange, size: 20),
                SizedBox(width: 8),
                Text(
                  'Visual Gameplay Script Bridge',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Visually configure component logic, movement kinematics, audio responses, and particle triggers, '
              'then generate clean, production-ready static Dart code.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // Behavior Preset Selector
            _buildVisualCard(
              title: 'Behavior Archetype',
              child: DropdownButton<String>(
                value: _visualBehaviorParams['behaviorType'],
                dropdownColor: EmberTheme.panelBg,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'PlayerController', child: Text('Player Controller (WASD + Jump)')),
                  DropdownMenuItem(value: 'PatrolAI', child: Text('Patrol AI (Horizontal Roaming)')),
                  DropdownMenuItem(value: 'CoinCollector', child: Text('Trigger Zone & Collector')),
                  DropdownMenuItem(value: 'TurretSpawner', child: Text('Periodic Spawner & Projectile')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _visualBehaviorParams['behaviorType'] = val);
                },
              ),
            ),

            const SizedBox(height: 16),

            // Kinematics Controls
            _buildVisualCard(
              title: 'Movement Kinematics',
              child: Column(
                children: [
                  _buildSlider(
                    label: 'Move Speed',
                    value: _visualBehaviorParams['moveSpeed'],
                    min: 50.0,
                    max: 800.0,
                    onChanged: (v) => setState(() => _visualBehaviorParams['moveSpeed'] = v),
                  ),
                  _buildSlider(
                    label: 'Jump Force',
                    value: _visualBehaviorParams['jumpForce'],
                    min: 100.0,
                    max: 1000.0,
                    onChanged: (v) => setState(() => _visualBehaviorParams['jumpForce'] = v),
                  ),
                  _buildSlider(
                    label: 'Gravity',
                    value: _visualBehaviorParams['gravityModifier'],
                    min: 200.0,
                    max: 2000.0,
                    onChanged: (v) => setState(() => _visualBehaviorParams['gravityModifier'] = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Audio & VFX Reactions
            _buildVisualCard(
              title: 'Sensory & Audio Reactions',
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Trigger Jump Sound Effect', style: TextStyle(color: Colors.white, fontSize: 12)),
                    value: _visualBehaviorParams['enableAudio'],
                    activeThumbColor: EmberTheme.emberOrange,
                    onChanged: (v) => setState(() => _visualBehaviorParams['enableAudio'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('Emit Particle Bursts on Jump/Landing', style: TextStyle(color: Colors.white, fontSize: 12)),
                    value: _visualBehaviorParams['enableSparks'],
                    activeThumbColor: EmberTheme.emberOrange,
                    onChanged: (v) => setState(() => _visualBehaviorParams['enableSparks'] = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualCard({required String title, required Widget child}) {
    return Material(
      color: EmberTheme.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: EmberTheme.borderMuted),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              activeColor: EmberTheme.emberOrange,
              inactiveColor: EmberTheme.canvasBg,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              value.toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: EmberTheme.surfaceBg,
        border: Border(top: BorderSide(color: EmberTheme.borderMuted)),
      ),
      child: Row(
        children: [
          Icon(
            _hasSyntaxError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 13,
            color: _hasSyntaxError ? Colors.redAccent : Colors.greenAccent,
          ),
          const SizedBox(width: 6),
          Text(
            _syntaxStatus,
            style: TextStyle(
              color: _hasSyntaxError ? Colors.redAccent : Colors.greenAccent,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text('File: $_activeTab', style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(width: 16),
          const Text('UTF-8 • Dart', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }

  String _generateSampleScript() {
    return '''
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';
import 'package:ember_engine/subsystems/audio/audio_system.dart';
import 'package:ember_engine/subsystems/particles/particle_system.dart';

/// Interactive Gameplay Controller
class GameplayController extends GameScript {
  @override
  void onStart() {
    // Initialized when engine enters play mode
  }

  @override
  void onUpdate(double dt) {
    if (Input.isActionJustPressed(EngineAction.fire)) {
      AudioSystem.instance.play(clip: 'laser');
      getComponent<ParticleEmitter2DComponent>()?.triggerBurst(20);
    }
  }
}
''';
  }

  String _generateCustomScriptScaffold(String className) {
    return '''
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/input.dart';

class $className extends GameScript {
  @override
  void onStart() {
    // Called when game starts
  }

  @override
  void onUpdate(double dt) {
    // Game loop logic
  }
}
''';
  }
}

/// Custom syntax highlighting TextEditingController for Dart.
class DartSyntaxTextController extends TextEditingController {
  static final RegExp _keywords = RegExp(
    r'\b(class|extends|implements|void|return|if|else|for|while|final|late|override|import|super|new|this|true|false|null|static|enum|const|get|set|async|await)\b',
  );

  static final RegExp _types = RegExp(
    r'\b(int|double|String|bool|List|Map|Set|Vector2|Vector3|Color|EmberComponent|GameScript|Transform2DComponent|Transform3DComponent|CharacterController2DComponent|CharacterController3DComponent|AudioSourceComponent|ParticleEmitter2DComponent|ParticleEmitter3DComponent|Input|EngineAction)\b',
  );

  static final RegExp _strings = RegExp(r"'[^']*'|" r'"[^"]*"');
  static final RegExp _comments = RegExp(r'//.*');

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final List<TextSpan> children = [];
    final text = value.text;

    final baseStyle = style ?? const TextStyle(color: Colors.white);

    // Pattern matching tokenizer
    text.splitMapJoin(
      RegExp(r'(\/\/.*)|(' r"'[^']*'|" r'"[^"]*")|(\b(class|extends|implements|void|return|if|else|for|while|final|late|override|import|super|new|this|true|false|null|static|enum|const|get|set|async|await)\b)|(\b(int|double|String|bool|List|Map|Set|Vector2|Vector3|Color|EmberComponent|GameScript|Transform2DComponent|Transform3DComponent|CharacterController2DComponent|CharacterController3DComponent|AudioSourceComponent|ParticleEmitter2DComponent|ParticleEmitter3DComponent|Input|EngineAction)\b)'),
      onMatch: (m) {
        final matched = m.group(0)!;
        Color color = Colors.white;
        FontWeight weight = FontWeight.normal;

        if (_comments.hasMatch(matched)) {
          color = const Color(0xFF64748B); // Muted comment slate
        } else if (_strings.hasMatch(matched)) {
          color = const Color(0xFFFBBF24); // Amber strings
        } else if (_keywords.hasMatch(matched)) {
          color = const Color(0xFFFF5722); // Ember Orange keywords
          weight = FontWeight.bold;
        } else if (_types.hasMatch(matched)) {
          color = const Color(0xFF38BDF8); // Sky blue types
          weight = FontWeight.w600;
        }

        children.add(TextSpan(text: matched, style: baseStyle.copyWith(color: color, fontWeight: weight)));
        return matched;
      },
      onNonMatch: (nonMatch) {
        children.add(TextSpan(text: nonMatch, style: baseStyle));
        return nonMatch;
      },
    );

    return TextSpan(style: style, children: children);
  }
}

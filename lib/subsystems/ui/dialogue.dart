import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/input.dart';

class DialogueLine {
  final String speaker;
  final String text;
  const DialogueLine(this.speaker, this.text);
}

/// Pauses game time while a dialogue is open. Set by the engine.
typedef TimeScaleHook = void Function(double scale);

/// Shows conversations in a box at the bottom of the screen with a
/// typewriter effect. Space / Enter / E / click reveals the line, then
/// advances. Game time is paused while it is open.
///
/// ```dart
/// DialogueSystem.instance.start(DialogueSystem.parse('Elder: Beware the caves!'));
/// ```
class DialogueSystem {
  static final DialogueSystem instance = DialogueSystem._();
  DialogueSystem._();

  /// Characters revealed per second.
  double speed = 45;

  /// Set by the engine: pauses / resumes game time.
  TimeScaleHook? setTimeScale;

  List<DialogueLine> _lines = const [];
  int _index = 0;
  double _shown = 0;
  bool _openedThisFrame = false;
  void Function()? _onFinished;

  bool get isOpen => _lines.isNotEmpty;
  DialogueLine? get current => isOpen ? _lines[_index] : null;
  String get visibleText => current == null ? '' : current!.text.substring(0, math.min(current!.text.length, _shown.floor()));
  bool get lineComplete => current == null || _shown >= current!.text.length;

  /// Parses `Speaker: text` lines (one per line; lines without a speaker
  /// continue with the previous one).
  static List<DialogueLine> parse(String script) {
    final out = <DialogueLine>[];
    var speaker = '';
    for (final raw in script.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final m = RegExp(r'^([^:]{1,24}):\s*(.+)$').firstMatch(line);
      if (m != null) {
        speaker = m.group(1)!.trim();
        out.add(DialogueLine(speaker, m.group(2)!.trim()));
      } else {
        out.add(DialogueLine(speaker, line));
      }
    }
    return out;
  }

  void start(List<DialogueLine> lines, {void Function()? onFinished}) {
    if (lines.isEmpty) return;
    _lines = lines;
    _index = 0;
    _shown = 0;
    _openedThisFrame = true;
    _onFinished = onFinished;
    setTimeScale?.call(0);
  }

  /// Reveals the current line, or moves to the next one / closes.
  void advance() {
    if (!isOpen) return;
    if (!lineComplete) {
      _shown = current!.text.length.toDouble();
      return;
    }
    _index++;
    _shown = 0;
    if (_index >= _lines.length) {
      final done = _onFinished;
      close();
      done?.call();
    }
  }

  void close() {
    final wasOpen = isOpen;
    _lines = const [];
    _index = 0;
    _onFinished = null;
    if (wasOpen) setTimeScale?.call(1);
  }

  /// Real-time update from the engine: typewriter + advance input.
  void update(double dt) {
    if (!isOpen) return;
    _shown += dt * speed;
    if (_openedThisFrame) {
      _openedThisFrame = false; // the key that opened it must not skip the first line
      return;
    }
    if (Input.isActionJustPressed(EngineAction.jump) ||
        Input.isActionJustPressed(EngineAction.interact) ||
        Input.isKeyJustPressed(LogicalKeyboardKey.enter) ||
        Input.isMouseButtonJustPressed(0)) {
      advance();
    }
  }

  /// Draws the box inside [view] (screen pixels); [scale] = design→screen.
  void paint(Canvas canvas, Rect view, double scale) {
    final line = current;
    if (line == null) return;
    final margin = 12 * scale;
    final h = 86 * scale;
    final box = Rect.fromLTWH(view.left + margin, view.bottom - h - margin, view.width - margin * 2, h);
    final rrect = RRect.fromRectAndRadius(box, Radius.circular(8 * scale));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xE6101218));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale
        ..color = const Color(0xFFF59E0B),
    );
    var y = box.top + 10 * scale;
    if (line.speaker.isNotEmpty) {
      final name = TextPainter(
        text: TextSpan(
          text: line.speaker,
          style: TextStyle(color: const Color(0xFFF59E0B), fontSize: 14 * scale, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: box.width - 24 * scale);
      name.paint(canvas, Offset(box.left + 14 * scale, y));
      y += name.height + 4 * scale;
    }
    final body = TextPainter(
      text: TextSpan(text: visibleText, style: TextStyle(color: Colors.white, fontSize: 14 * scale, height: 1.25)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: box.width - 28 * scale);
    body.paint(canvas, Offset(box.left + 14 * scale, y));
    if (lineComplete) {
      final more = TextPainter(
        text: TextSpan(text: '▼', style: TextStyle(color: const Color(0xFFF59E0B), fontSize: 11 * scale)),
        textDirection: TextDirection.ltr,
      )..layout();
      more.paint(canvas, Offset(box.right - 20 * scale, box.bottom - 18 * scale));
    }
  }
}

/// Lines a character says when the player interacts with it.
class DialogueComponent extends EmberComponent {
  String lines;

  DialogueComponent({this.lines = 'Villager: Hello there!'});

  /// Opens this character's dialogue.
  void talk({void Function()? onFinished}) =>
      DialogueSystem.instance.start(DialogueSystem.parse(lines), onFinished: onFinished);

  @override
  String get displayName => 'Dialogue';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'lines',
          label: 'Lines (Name: text, one per line)',
          type: InspectableType.string,
          multiline: true,
          getter: () => lines,
          setter: (v) {
            lines = v;
            notifyListeners();
          },
          describe: (v) {
            final parsed = DialogueSystem.parse(v);
            final speakers = {for (final l in parsed) if (l.speaker.isNotEmpty) l.speaker};
            return '${parsed.length} line${parsed.length == 1 ? '' : 's'}'
                '${speakers.isEmpty ? '' : ' · ${speakers.join(', ')}'} · plays when the player presses E nearby';
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {'lines': lines};

  @override
  void fromJson(Map<String, dynamic> json) {
    lines = json['lines'] as String? ?? '';
    notifyListeners();
  }

  @override
  DialogueComponent clone() => DialogueComponent(lines: lines);
}

void registerDialogueComponent() {
  ComponentRegistry.register('Dialogue', (json) => DialogueComponent()..fromJson(json));
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/assets.dart';
import '../../core/component.dart';
import '../../core/engine_loop.dart';
import '../../core/entity.dart' show ComponentRegistry;
import '../../core/event_bus.dart' show LogSeverity;
import '../../core/inspectable.dart';
import '../../core/input.dart';
import '../../core/save_data.dart';
import '../../core/scene.dart';
import '../../scripting/script_library.dart';
import '../audio/audio_system.dart';
import '../ui/ui_widgets.dart';
import 'story_script.dart';

/// A character on stage.
class _Actor {
  final String id;
  String? expression;
  String position;
  double alpha = 0;
  bool leaving = false;
  _Actor(this.id, this.expression, this.position);
}

class _Line {
  final String name;
  final int color;
  final String text; // with *stress* markers, variables filled in
  final bool narration;
  const _Line(this.name, this.color, this.text, this.narration);

  String get plain => text.replaceAll('*', '');
}

/// Plays a story written in the Ember story language ([StoryScript]): a
/// visual novel screen with backgrounds, characters and their expressions, a
/// dialogue box with a typewriter, choices, a history log, Auto and Skip, and
/// save / load slots. The story is a `.story` file kept with the project's
/// scripts (edited in the Script workspace, applied while playing).
///
/// Click, Space or Enter continues; hold Ctrl to skip. Scripts receive
/// `onStoryEvent(name)` for `event` lines and can read variables with
/// `story.variable("trust")`.
class StoryPlayerComponent extends EmberComponent {
  String storyFile;
  String startLabel;

  /// Scene to return to from the menu or after the end ('' restarts this one).
  String titleScene;

  /// Prefix of the save keys (so several stories in a project keep separate saves).
  String saveKey;

  /// Typewriter speed (characters per second).
  double textSpeed;

  /// Auto mode: seconds to wait after a line is shown.
  double autoDelay;

  StoryPlayerComponent({
    this.storyFile = 'story.story',
    this.startLabel = 'start',
    this.titleScene = '',
    this.saveKey = 'story',
    this.textSpeed = 45,
    this.autoDelay = 1.6,
  });

  /// Set by the title screen (`Game.data["storyLoad"] = "auto"`) to continue a
  /// save, or "menu" to start on the load screen.
  static const String loadRequest = 'storyLoad';

  static const List<String> slots = ['1', '2', '3'];

  StoryProgram? _program;
  int _revision = -1;
  String _source = '';
  int _index = 0;
  final Map<String, Object?> vars = {};
  String background = '';
  String _previousBackground = '';
  double _bgFade = 1;
  double _blackout = 0;
  final List<_Actor> _stage = [];
  String music = '';
  _Line? _line;
  double _shown = 0;
  List<StoryChoice> _choices = [];
  double _wait = 0;
  String? _ending;
  bool ended = false;
  final List<_Line> _backlog = [];
  bool auto = false;
  bool skip = false;
  double _autoTimer = 0;
  double _skipTimer = 0;
  String overlay = ''; // '', log, save, load
  String _flash = '';
  double _flashTime = 0;
  double _time = 0;

  // Last paint: design size and screen mapping, and clickable areas (design units)
  Rect _view = Rect.zero;
  double _scale = 1;
  Size _design = const Size(960, 540);
  final List<(Rect, String)> _hits = [];

  StoryProgram? get program => _program;
  String get speaker => _line?.name ?? '';
  String get text => _line?.plain ?? '';
  List<String> get choices => [for (final c in _choices) c.text];

  /// The lines shown so far (newest last), as "Name: text".
  List<String> get history => [for (final l in _backlog) l.name.isEmpty ? l.plain : '${l.name}: ${l.plain}'];
  bool get lineComplete => _line == null || _shown >= _line!.plain.length;
  List<String> get onStage => [for (final a in _stage) if (!a.leaving) a.id];
  String? expressionOf(String id) => _stage.where((a) => a.id == id && !a.leaving).firstOrNull?.expression;
  String? get ending => _ending;

  /// The label the story is in (for saves and scripts).
  String get label {
    var best = '';
    var bestAt = -1;
    for (final e in _program?.labels.entries ?? const <MapEntry<String, int>>[]) {
      if (e.value <= _index && e.value > bestAt) {
        best = e.key;
        bestAt = e.value;
      }
    }
    return best;
  }

  // --- Running

  @override
  void onStart() {
    _reload(force: true);
    // The title can ask to continue a save ("auto", "1"-"3") or to open the load screen ("menu")
    final request = EmberScripts.instance.gameData.remove(loadRequest);
    if (request is String && hasSave(request)) {
      load(request);
    } else {
      restart();
      if (request == 'menu') overlay = 'load';
    }
  }

  /// Starts the story from the beginning.
  void restart() {
    final p = _program;
    if (p == null) return;
    vars
      ..clear()
      ..addAll(p.initialVars);
    _stage.clear();
    background = '';
    _backlog.clear();
    ended = false;
    _ending = null;
    jump(startLabel);
  }

  void _reload({bool force = false}) {
    final lib = EmberScripts.instance;
    if (!force && lib.textRevision == _revision) return;
    _revision = lib.textRevision;
    final source = lib.text(storyFile) ?? '';
    if (!force && source == _source) return;
    _source = source;
    final p = StoryScript.parse(source);
    _program = p;
    if (!p.ok) {
      EmberEngine.instance.log('$storyFile ${p.errors.first}', severity: LogSeverity.warning, source: 'Story');
    }
    if (!force) _index = math.min(_index, p.commands.length);
  }

  void jump(String target) {
    final at = _program?.labels[target];
    if (at == null) {
      EmberEngine.instance.log('Story: no label "$target"', severity: LogSeverity.warning, source: 'Story');
      _finish('');
      return;
    }
    _index = at;
    _run();
  }

  /// Runs commands until one waits for the player (a line, a choice, a wait or the end).
  void _run() {
    final p = _program;
    if (p == null) return;
    _choices = [];
    for (var guard = 0; guard < 5000; guard++) {
      if (_index >= p.commands.length) {
        _finish('');
        return;
      }
      final c = p.commands[_index];
      if (_exec(c, p)) return;
      _index++;
    }
  }

  /// Runs one command; true when it waits.
  bool _exec(StoryCommand c, StoryProgram p) {
    switch (c.kind) {
      case 'say':
        final id = c.arg('id');
        final ch = id == null ? null : p.characters[id];
        if (ch != null && c.arg('expression') != null) {
          final actor = _stage.where((a) => a.id == id && !a.leaving).firstOrNull;
          actor?.expression = c.arg('expression');
        }
        final name = ch?.name ?? c.arg('name') ?? '';
        _line = _Line(name, ch?.color ?? 0xFFE5E7EB, _fill(c.arg('text') ?? ''), name.isEmpty);
        _shown = skip ? 1e9 : 0; // 1e9: the whole line at once
        _autoTimer = 0;
        _backlog.add(_line!);
        if (_backlog.length > 200) _backlog.removeAt(0);
        save('auto', quiet: true);
        return true;
      case 'scene':
        final name = c.arg('name') ?? '';
        if (name != background) {
          _previousBackground = background;
          background = name;
          _bgFade = c.arg('transition') == 'cut' || skip ? 1 : 0;
        }
        _stage.clear();
      case 'show':
        final id = c.arg('id')!;
        final existing = _stage.where((a) => a.id == id && !a.leaving).firstOrNull;
        if (existing != null) {
          existing.expression = c.arg('expression') ?? existing.expression;
          existing.position = c.arg('position') ?? existing.position;
        } else {
          _stage.removeWhere((a) => a.id == id);
          _stage.add(_Actor(id, c.arg('expression'), c.arg('position') ?? 'center')..alpha = skip ? 1 : 0);
        }
      case 'hide':
        for (final a in _stage) {
          if (a.id == c.arg('id')) a.leaving = true;
        }
      case 'music':
        final path = c.arg('path') ?? 'stop';
        if (path == 'stop') {
          music = '';
          AudioSystem.instance.stopMusic();
        } else if (path != music) {
          music = path;
          AudioSystem.instance.playMusic(path, volume: double.tryParse(c.arg('volume') ?? '') ?? 0.5);
        }
      case 'sound':
        final name = c.arg('name') ?? '';
        final volume = double.tryParse(c.arg('volume') ?? '') ?? 0.8;
        if (!skip) {
          if (name.contains('.')) {
            AudioSystem.instance.play(clip: name, volume: volume);
          } else {
            AudioSystem.instance.playProcedural(name, volume: volume);
          }
        }
      case 'set':
        try {
          StoryExpr.assign(c.arg('assign')!, vars);
        } catch (e) {
          EmberEngine.instance.log('Story line ${c.line}: $e', severity: LogSeverity.warning, source: 'Story');
        }
      case 'jump':
        final at = p.labels[c.arg('target')];
        if (at == null) {
          _finish('');
          return true;
        }
        _index = at - 1; // the loop steps onto the label
      case 'if':
        if (_test(c.arg('condition')!, c.line)) {
          final at = p.labels[c.arg('target')];
          if (at != null) _index = at - 1;
        }
      case 'choice':
        _choices = [for (final o in c.choices) if (o.condition == null || _test(o.condition!, c.line)) o];
        if (_choices.isEmpty) return false;
        skip = false; // choices always stop Skip
        save('auto', quiet: true);
        return true;
      case 'wait':
        _wait = skip ? 0 : double.tryParse(c.arg('seconds') ?? '') ?? 1;
        return _wait > 0;
      case 'event':
        final name = c.arg('name') ?? '';
        final scene = entity?.scene;
        if (scene != null) {
          for (final e in scene.allEntities) {
            e.notifyScripts((s) => s.onMessage('onStoryEvent', [name]));
          }
        }
      case 'end':
        _finish(c.arg('ending') ?? '');
        return true;
    }
    return false;
  }

  bool _test(String condition, int line) {
    try {
      return StoryExpr.truthy(StoryExpr.eval(condition, vars));
    } catch (e) {
      EmberEngine.instance.log('Story line $line: $e', severity: LogSeverity.warning, source: 'Story');
      return false;
    }
  }

  /// Fills `{variable}` with its value.
  String _fill(String text) => text.replaceAllMapped(RegExp(r'\{([A-Za-z_]\w*)\}'), (m) => StoryExpr.format(vars[m.group(1)]));

  void _finish(String endingName) {
    ended = true;
    _ending = endingName;
    _line = null;
    _choices = [];
    skip = false;
    auto = false;
    SaveData.instance.remove('${saveKey}_auto');
    final seen = '${saveKey}_endings';
    if (endingName.isNotEmpty) {
      final list = (SaveData.instance.getMap(seen)?['names'] as List?)?.cast<Object?>() ?? [];
      if (!list.contains(endingName)) SaveData.instance.setMap(seen, {'names': [...list, endingName]});
    }
  }

  /// Continues after the current line (or picks nothing when a choice is open).
  void advance() {
    if (ended) {
      _leave();
      return;
    }
    if (_choices.isNotEmpty || _wait > 0) return;
    if (!lineComplete) {
      _shown = 1e9;
      return;
    }
    _line = null;
    _index++;
    _run();
  }

  /// Picks option [i] of the open choice.
  void choose(int i) {
    if (i < 0 || i >= _choices.length) return;
    final o = _choices[i];
    if (o.effect != null) {
      try {
        StoryExpr.assign(o.effect!, vars);
      } catch (e) {
        EmberEngine.instance.log('Story: $e', severity: LogSeverity.warning, source: 'Story');
      }
    }
    _backlog.add(_Line('', 0xFFFDE68A, '> ${o.text}', true));
    AudioSystem.instance.playProcedural('click', volume: 0.4, pitch: 1.2);
    _choices = [];
    jump(o.target);
  }

  void _leave() {
    final engine = EmberEngine.instance;
    if (titleScene.isNotEmpty && engine.loadLevel(titleScene)) return;
    restart();
  }

  // --- Saving

  String _slotKey(String slot) => '${saveKey}_$slot';
  bool hasSave(String slot) => SaveData.instance.has(_slotKey(slot));
  Map<String, dynamic>? saveInfo(String slot) => SaveData.instance.getMap(_slotKey(slot));

  void save(String slot, {bool quiet = false}) {
    if (ended) return;
    final preview = _line == null ? (_choices.isEmpty ? '' : 'Choice: ${_choices.map((c) => c.text).join(' / ')}') : '${_line!.name.isEmpty ? '' : '${_line!.name}: '}${_line!.plain}';
    SaveData.instance.setMap(_slotKey(slot), {
      'index': _index,
      'vars': {for (final e in vars.entries) if (e.value is num || e.value is String || e.value is bool) e.key: e.value},
      'background': background,
      'stage': [for (final a in _stage) if (!a.leaving) {'id': a.id, 'expression': a.expression, 'position': a.position}],
      'music': music,
      'label': label,
      'preview': preview.length > 90 ? '${preview.substring(0, 88)}…' : preview,
      'savedAt': DateTime.now().toIso8601String(),
    });
    if (!quiet) _toast('Saved in slot $slot');
  }

  void load(String slot) {
    final data = saveInfo(slot);
    final p = _program;
    if (data == null || p == null) return;
    vars
      ..clear()
      ..addAll(p.initialVars)
      ..addAll((data['vars'] as Map?)?.cast<String, Object?>() ?? const {});
    background = data['background'] as String? ?? '';
    _bgFade = 1;
    _stage
      ..clear()
      ..addAll([
        for (final a in (data['stage'] as List?) ?? const [])
          _Actor(a['id'] as String, a['expression'] as String?, a['position'] as String? ?? 'center')..alpha = 1,
      ]);
    final m = data['music'] as String? ?? '';
    if (m.isNotEmpty && m != music) AudioSystem.instance.playMusic(m, volume: 0.5);
    music = m;
    ended = false;
    _ending = null;
    overlay = '';
    _index = ((data['index'] as num?)?.toInt() ?? 0).clamp(0, p.commands.length);
    _run();
    if (slot != 'auto') _toast('Loaded slot $slot');
  }

  void _toast(String message) {
    _flash = message;
    _flashTime = 1.6;
  }

  // --- Frame update and input

  @override
  void onUpdate(double dt) {
    _reload();
    _time += dt;
    if (_bgFade < 1) _bgFade = math.min(1, _bgFade + dt / 0.5);
    for (final a in _stage) {
      a.alpha = a.leaving ? math.max(0, a.alpha - dt / 0.25) : math.min(1, a.alpha + dt / 0.25);
    }
    _stage.removeWhere((a) => a.leaving && a.alpha <= 0);
    if (_flashTime > 0) _flashTime -= dt;
    _blackout = math.max(0, _blackout - dt * 2);

    final ctrl = Input.isKeyPressed(LogicalKeyboardKey.controlLeft) || Input.isKeyPressed(LogicalKeyboardKey.controlRight);
    final skipping = (skip || ctrl) && overlay.isEmpty;
    if (_line != null) _shown += dt * (skipping ? 2000 : textSpeed);

    if (_wait > 0) {
      _wait -= dt;
      if (_wait <= 0) {
        _wait = 0;
        _index++;
        _run();
      }
    }

    _input();

    if (overlay.isNotEmpty || ended) return;
    if (skipping && _choices.isEmpty && _line != null) {
      _skipTimer += dt;
      if (_skipTimer > 0.06) {
        _skipTimer = 0;
        _shown = 1e9;
        advance();
      }
    } else if (auto && lineComplete && _line != null && _choices.isEmpty) {
      _autoTimer += dt;
      if (_autoTimer > autoDelay + _line!.plain.length * 0.02) advance();
    }
  }

  void _input() {
    final click = Input.isMouseButtonJustPressed(0);
    final key = Input.isKeyJustPressed(LogicalKeyboardKey.space) || Input.isKeyJustPressed(LogicalKeyboardKey.enter);
    if (overlay.isEmpty && _choices.isNotEmpty) {
      const digits = [
        LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
      ];
      for (var i = 0; i < _choices.length && i < digits.length; i++) {
        if (Input.isKeyJustPressed(digits[i])) {
          choose(i);
          return;
        }
      }
    }
    if (!click && !key) return;
    if (click) {
      final m = Input.mousePosition;
      final p = Offset((m.x - _view.left) / _scale, (m.y - _view.top) / _scale);
      for (final (rect, action) in _hits.reversed) {
        if (rect.contains(p)) {
          _action(action);
          return;
        }
      }
    }
    if (overlay.isNotEmpty) {
      overlay = '';
      return;
    }
    if (_choices.isNotEmpty) {
      return;
    }
    advance();
  }

  void _action(String action) {
    if (action.startsWith('choice:')) {
      choose(int.parse(action.substring(7)));
    } else if (action.startsWith('save:')) {
      save(action.substring(5));
    } else if (action.startsWith('load:')) {
      if (hasSave(action.substring(5))) load(action.substring(5));
    } else {
      switch (action) {
        case 'next':
          advance();
        case 'log':
          overlay = overlay == 'log' ? '' : 'log';
        case 'auto':
          auto = !auto;
          skip = false;
        case 'skip':
          skip = !skip;
          auto = false;
        case 'saveMenu':
          overlay = 'save';
        case 'loadMenu':
          overlay = 'load';
        case 'menu':
          _leave();
        case 'close':
          overlay = '';
        case 'end':
          _leave();
      }
    }
  }

  // --- Painting

  /// Paints every Story Player of [scene] (before the scene's own UI).
  static void paintAll(Canvas canvas, Rect view, double scale, EmberScene scene) {
    for (final s in scene.componentsOf<StoryPlayerComponent>()) {
      if (s.enabled && (s.entity?.activeInHierarchy ?? false)) s.paint(canvas, view, scale);
    }
  }

  void paint(Canvas canvas, Rect view, double scale) {
    _view = view;
    _scale = scale <= 0 ? 1 : scale;
    final w = view.width / _scale, h = view.height / _scale;
    _design = Size(w, h);
    _hits.clear();
    canvas.save();
    canvas.clipRect(view);
    canvas.translate(view.left, view.top);
    canvas.scale(_scale);
    final p = _program;
    _paintBackground(canvas, p);
    _paintStage(canvas, p);
    if (_line != null && overlay.isEmpty) _paintBox(canvas);
    if (_choices.isNotEmpty && overlay.isEmpty) _paintChoices(canvas);
    if (!ended && overlay.isEmpty) _paintQuickMenu(canvas);
    if (overlay == 'log') _paintLog(canvas);
    if (overlay == 'save' || overlay == 'load') _paintSlots(canvas);
    if (ended) _paintEnd(canvas);
    if (_flashTime > 0) _paintToast(canvas);
    if (p != null && !p.ok) _paintErrors(canvas, p);
    if (_blackout > 0) canvas.drawRect(Offset.zero & _design, Paint()..color = Color.fromRGBO(0, 0, 0, _blackout.clamp(0.0, 1.0)));
    canvas.restore();
  }

  void _paintBackground(Canvas canvas, StoryProgram? p) {
    final rect = Offset.zero & _design;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0B0B12));
    void drawBg(String name, double alpha) {
      final path = p?.backgrounds[name];
      final img = path == null ? null : EmberAssets.instance.image(path);
      if (img == null || alpha <= 0) return;
      final s = math.max(rect.width / img.width, rect.height / img.height);
      final dst = Rect.fromCenter(center: rect.center, width: img.width * s, height: img.height * s);
      final paint = Paint()
        ..filterQuality = FilterQuality.none
        ..color = Color.fromRGBO(255, 255, 255, alpha);
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, paint);
    }

    if (_bgFade < 1) drawBg(_previousBackground, 1);
    drawBg(background, Curves.easeInOut.transform(_bgFade));
  }

  void _paintStage(Canvas canvas, StoryProgram? p) {
    if (p == null) return;
    final speakingName = _line?.name;
    for (final a in _stage) {
      final ch = p.characters[a.id];
      if (ch == null) continue;
      final img = EmberAssets.instance.image(ch.image);
      if (img == null) continue;
      final frames = math.max(1, ch.expressions.length);
      final fw = img.width / frames, fh = img.height.toDouble();
      final height = _design.height * 0.8;
      final width = height * fw / fh;
      final x = _design.width * switch (a.position) { 'left' => 0.24, 'right' => 0.76, _ => 0.5 };
      final rise = (1 - a.alpha) * 14;
      final dst = Rect.fromLTWH(x - width / 2, _design.height - height + rise, width, height);
      final frame = ch.frameOf(a.expression);
      final dim = speakingName != null && speakingName.isNotEmpty && speakingName != ch.name && overlay.isEmpty;
      final paint = Paint()
        ..filterQuality = FilterQuality.none
        ..color = Color.fromRGBO(255, 255, 255, a.alpha)
        ..colorFilter = dim ? const ColorFilter.matrix([0.62, 0, 0, 0, 0, 0, 0.62, 0, 0, 0, 0, 0, 0.7, 0, 0, 0, 0, 0, 1, 0]) : null;
      canvas.drawImageRect(img, Rect.fromLTWH(frame * fw, 0, fw, fh), dst, paint);
    }
  }

  Rect get _boxRect => Rect.fromLTWH(_design.width * 0.06, _design.height * 0.69, _design.width * 0.88, _design.height * 0.27);

  void _paintBox(Canvas canvas) {
    final line = _line!;
    final box = _boxRect;
    final accent = Color(line.narration ? 0xFF64748B : line.color);
    final rrect = RRect.fromRectAndRadius(box, const Radius.circular(12));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xE6101320));
    canvas.drawRRect(rrect, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = accent);
    if (!line.narration) {
      final name = _painter(line.name, 17, const Color(0xFF111827), bold: true);
      final plate = RRect.fromRectAndRadius(Rect.fromLTWH(box.left + 20, box.top - 17, name.width + 28, 32), const Radius.circular(8));
      canvas.drawRRect(plate, Paint()..color = accent);
      name.paint(canvas, Offset(plate.left + 14, plate.top + (32 - name.height) / 2));
    }
    final shown = math.min(line.plain.length, _shown.floor());
    final body = TextPainter(
      text: TextSpan(children: _spans(line.text, shown, line.narration)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: box.width - 52);
    body.paint(canvas, Offset(box.left + 26, box.top + 24));
    if (lineComplete && _choices.isEmpty && (_time * 2).floor().isEven) {
      final more = _painter('▼', 12, accent);
      more.paint(canvas, Offset(box.right - 26, box.bottom - 22));
    }
    _hits.add((box, 'next'));
  }

  /// The visible part of [text]: [shown] characters, with *stressed* words highlighted.
  List<InlineSpan> _spans(String text, int shown, bool narration) {
    final base = TextStyle(
        color: narration ? const Color(0xFFCBD5E1) : Colors.white, fontSize: 18, height: 1.38, fontStyle: narration ? FontStyle.italic : FontStyle.normal);
    final stress = base.copyWith(color: const Color(0xFFFDE68A), fontWeight: FontWeight.w800);
    final out = <InlineSpan>[];
    var left = shown;
    var stressed = false;
    for (final part in text.split('*')) {
      if (left <= 0) break;
      final piece = part.length <= left ? part : part.substring(0, left);
      left -= piece.length;
      if (piece.isNotEmpty) out.add(TextSpan(text: piece, style: stressed ? stress : base));
      stressed = !stressed;
    }
    return out;
  }

  void _paintChoices(Canvas canvas) {
    final hover = _mouseDesign();
    final width = _design.width * 0.54;
    const height = 46.0, gap = 12.0;
    final total = _choices.length * height + (_choices.length - 1) * gap;
    var y = _design.height * 0.42 - total / 2;
    for (var i = 0; i < _choices.length; i++) {
      final rect = Rect.fromLTWH((_design.width - width) / 2, y, width, height);
      final over = hover != null && rect.contains(hover);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      canvas.drawRRect(rrect, Paint()..color = over ? const Color(0xF2FDE68A) : const Color(0xE61E1B2E));
      canvas.drawRRect(rrect, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFDE68A));
      final t = _painter(_choices[i].text, 17, over ? const Color(0xFF1F2937) : Colors.white, bold: true, maxWidth: width - 30);
      t.paint(canvas, Offset(rect.center.dx - t.width / 2, rect.center.dy - t.height / 2));
      _hits.add((rect, 'choice:$i'));
      y += height + gap;
    }
  }

  void _paintQuickMenu(Canvas canvas) {
    final box = _boxRect;
    final items = [('Log', 'log', false), ('Auto', 'auto', auto), ('Skip', 'skip', skip), ('Save', 'saveMenu', false), ('Load', 'loadMenu', false), ('Menu', 'menu', false)];
    var x = box.right;
    final y = box.top - 30;
    for (final (label, action, on) in items.reversed) {
      final t = _painter(label, 12, on ? const Color(0xFF111827) : const Color(0xFFE5E7EB), bold: true);
      final rect = Rect.fromLTWH(x - t.width - 18, y, t.width + 18, 22);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(11));
      canvas.drawRRect(rrect, Paint()..color = on ? const Color(0xFFFDE68A) : const Color(0xB3101320));
      t.paint(canvas, Offset(rect.left + 9, rect.top + (22 - t.height) / 2));
      _hits.add((rect, action));
      x = rect.left - 6;
    }
  }

  void _dim(Canvas canvas, [double alpha = 0.82]) =>
      canvas.drawRect(Offset.zero & _design, Paint()..color = Color.fromRGBO(5, 6, 12, alpha));

  Rect _pill(Canvas canvas, String label, Offset center, String action) {
    final t = _painter(label, 14, const Color(0xFF111827), bold: true);
    final rect = Rect.fromCenter(center: center, width: t.width + 34, height: 32);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), Paint()..color = const Color(0xFFFDE68A));
    t.paint(canvas, Offset(rect.center.dx - t.width / 2, rect.center.dy - t.height / 2));
    _hits.add((rect, action));
    return rect;
  }

  void _paintLog(Canvas canvas) {
    _dim(canvas);
    _painter('History', 26, const Color(0xFFFDE68A), bold: true).paint(canvas, Offset(_design.width * 0.08, 24));
    var y = _design.height - 70;
    for (final line in _backlog.reversed) {
      final t = TextPainter(
        text: TextSpan(children: [
          if (line.name.isNotEmpty) TextSpan(text: '${line.name}  ', style: TextStyle(color: Color(line.color), fontSize: 15, fontWeight: FontWeight.w800)),
          TextSpan(text: line.plain, style: TextStyle(color: line.narration ? const Color(0xFFCBD5E1) : Colors.white, fontSize: 15, height: 1.3)),
        ]),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _design.width * 0.84);
      y -= t.height + 10;
      if (y < 70) break;
      t.paint(canvas, Offset(_design.width * 0.08, y));
    }
    _pill(canvas, 'Close', Offset(_design.width / 2, _design.height - 36), 'close');
  }

  void _paintSlots(Canvas canvas) {
    _dim(canvas);
    final saving = overlay == 'save';
    final title = _painter(saving ? 'Save the story' : 'Load a story', 26, const Color(0xFFFDE68A), bold: true);
    title.paint(canvas, Offset(_design.width / 2 - title.width / 2, 40));
    final cardW = _design.width * 0.26, cardH = _design.height * 0.44, gap = _design.width * 0.03;
    var x = (_design.width - cardW * 3 - gap * 2) / 2;
    for (final slot in [...slots]) {
      final rect = Rect.fromLTWH(x, _design.height * 0.24, cardW, cardH);
      final info = saveInfo(slot);
      final usable = saving || info != null;
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(rrect, Paint()..color = usable ? const Color(0xF21E1B2E) : const Color(0xB31E1B2E));
      canvas.drawRRect(rrect, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = usable ? const Color(0xFFFDE68A) : const Color(0xFF475569));
      _painter('Slot $slot', 18, const Color(0xFFFDE68A), bold: true).paint(canvas, Offset(rect.left + 16, rect.top + 14));
      if (info == null) {
        _painter('Empty', 15, const Color(0xFF94A3B8)).paint(canvas, Offset(rect.left + 16, rect.top + 48));
      } else {
        final when = DateTime.tryParse(info['savedAt'] as String? ?? '');
        final date = when == null ? '' : '${when.day}/${when.month} ${when.hour}:${when.minute.toString().padLeft(2, '0')}';
        _painter('${info['label'] ?? ''}  ·  $date', 13, const Color(0xFFCBD5E1)).paint(canvas, Offset(rect.left + 16, rect.top + 46));
        _painter('${info['preview'] ?? ''}', 14, Colors.white, maxWidth: cardW - 32).paint(canvas, Offset(rect.left + 16, rect.top + 74));
      }
      if (usable) _hits.add((rect, '${saving ? 'save' : 'load'}:$slot'));
      x += cardW + gap;
    }
    _pill(canvas, 'Back', Offset(_design.width / 2, _design.height - 44), 'close');
  }

  void _paintEnd(Canvas canvas) {
    _dim(canvas, 0.72);
    final the = _painter('THE END', 54, const Color(0xFFFDE68A), bold: true);
    the.paint(canvas, Offset(_design.width / 2 - the.width / 2, _design.height * 0.32));
    if ((_ending ?? '').isNotEmpty) {
      final e = _painter(_ending!, 20, Colors.white);
      e.paint(canvas, Offset(_design.width / 2 - e.width / 2, _design.height * 0.32 + the.height + 10));
    }
    _pill(canvas, titleScene.isEmpty ? 'Play again' : 'Back to the title', Offset(_design.width / 2, _design.height * 0.68), 'end');
  }

  void _paintToast(Canvas canvas) {
    final t = _painter(_flash, 15, const Color(0xFF111827), bold: true);
    final rect = Rect.fromCenter(center: Offset(_design.width / 2, 34), width: t.width + 32, height: 32);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), Paint()..color = Color.fromRGBO(253, 230, 138, _flashTime.clamp(0.0, 1.0)));
    t.paint(canvas, Offset(rect.center.dx - t.width / 2, rect.center.dy - t.height / 2));
  }

  void _paintErrors(Canvas canvas, StoryProgram p) {
    final t = _painter('$storyFile ${p.errors.first}${p.errors.length > 1 ? '  (+${p.errors.length - 1} more)' : ''}', 13, Colors.white,
        maxWidth: _design.width - 40);
    canvas.drawRect(Rect.fromLTWH(0, 0, _design.width, t.height + 16), Paint()..color = const Color(0xE6B91C1C));
    t.paint(canvas, const Offset(20, 8));
  }

  Offset? _mouseDesign() {
    final m = Input.mousePosition;
    if (_scale <= 0) return null;
    return Offset((m.x - _view.left) / _scale, (m.y - _view.top) / _scale);
  }

  static TextPainter _painter(String text, double size, Color color, {bool bold = false, double maxWidth = double.infinity}) =>
      TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);

  // --- Component plumbing

  @override
  String get displayName => 'Story Player';

  @override
  List<InspectableProperty> get inspectableProperties => [
        _s('storyFile', 'Story File', () => storyFile, (v) => storyFile = v, 'A .story file in the Script workspace'),
        _s('startLabel', 'Start Label', () => startLabel, (v) => startLabel = v, 'Where a new story begins'),
        _s('titleScene', 'Title Scene', () => titleScene, (v) => titleScene = v, 'Scene for Menu and after the end (empty: start again)'),
        _s('saveKey', 'Save Name', () => saveKey, (v) => saveKey = v, 'Keeps saves of different stories apart'),
        InspectableProperty<double>(
          name: 'textSpeed',
          label: 'Text Speed (letters/s)',
          type: InspectableType.number,
          getter: () => textSpeed,
          setter: (v) => textSpeed = v,
          min: 5,
          max: 400,
          step: 5,
        ),
        InspectableProperty<double>(
          name: 'autoDelay',
          label: 'Auto Delay (s)',
          type: InspectableType.number,
          getter: () => autoDelay,
          setter: (v) => autoDelay = v,
          min: 0.2,
          max: 10,
          step: 0.1,
        ),
      ];

  InspectableProperty<String> _s(String name, String label, String Function() get, void Function(String) set, String tip) =>
      InspectableProperty<String>(name: name, label: label, type: InspectableType.string, getter: get, setter: set, tooltip: tip);

  @override
  Map<String, dynamic> toJson() => {
        'storyFile': storyFile,
        'startLabel': startLabel,
        'titleScene': titleScene,
        'saveKey': saveKey,
        'textSpeed': textSpeed,
        'autoDelay': autoDelay,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    storyFile = json['storyFile'] as String? ?? 'story.story';
    startLabel = json['startLabel'] as String? ?? 'start';
    titleScene = json['titleScene'] as String? ?? '';
    saveKey = json['saveKey'] as String? ?? 'story';
    textSpeed = (json['textSpeed'] as num?)?.toDouble() ?? 45;
    autoDelay = (json['autoDelay'] as num?)?.toDouble() ?? 1.6;
  }

  @override
  StoryPlayerComponent clone() => StoryPlayerComponent()..fromJson(toJson());
}

/// Registers the Story Player and its UI paint hook.
void registerStoryComponents() {
  ComponentRegistry.register('Story Player', (json) => StoryPlayerComponent()..fromJson(json));
  UIRenderer.beforeUI = StoryPlayerComponent.paintAll;
}


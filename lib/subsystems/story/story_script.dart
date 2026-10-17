/// The Ember story language: a small text format for visual novels and
/// dialogue-heavy games, read by the Story Player component.
///
/// ```text
/// # Comments start with #
/// @title The Last Ember
/// @background forge  assets/templates/story/forge.png
/// @character mira "Mira" #F59E0B assets/templates/story/mira.png neutral happy sad surprised
/// @var trust = 0
///
/// label start:
/// scene forge fade              # change the background (fade or cut)
/// music assets/templates/story/theme.wav 0.4
/// show mira happy left          # left, center or right; the expression is optional
/// mira: The fire is almost out.
/// mira sad: Without it the forge goes cold.   # speak with an expression
/// "Stranger": Can I help?       # someone without a character
/// The wind howls outside.       # narration (no speaker)
/// set trust = trust + 1         # also +=, -=
/// if trust >= 2 jump friends
/// choice:
///   * Help her -> help
///   * Leave [if trust < 1] -> leave       # only when the condition holds
///   * Say nothing {trust -= 1} -> quiet   # changes a variable when picked
/// jump next
/// hide mira
/// sound coin 0.6
/// wait 1.5
/// event lightning               # calls onStoryEvent("lightning") in scripts
/// end Good ending               # the end (with an optional ending name)
/// ```
///
/// Text can show variables with `{trust}` and stress words with `*stars*`.
library;

/// A problem found while reading a story, with its line (1-based).
class StoryError {
  final int line;
  final String message;
  const StoryError(this.line, this.message);
  @override
  String toString() => 'line $line: $message';
}

class StoryCharacter {
  final String id;
  final String name;
  final int color; // ARGB
  final String image;
  final List<String> expressions;
  const StoryCharacter(this.id, this.name, this.color, this.image, this.expressions);

  /// Sprite-sheet frame for [expression] (0 when unknown or none).
  int frameOf(String? expression) {
    if (expression == null) return 0;
    final i = expressions.indexOf(expression);
    return i < 0 ? 0 : i;
  }
}

class StoryChoice {
  final String text;
  final String? condition;
  final String? effect;
  final String target;
  const StoryChoice(this.text, this.target, {this.condition, this.effect});
}

/// One instruction. [kind]: say, scene, show, hide, music, sound, set, jump,
/// if, choice, wait, event, end.
class StoryCommand {
  final String kind;
  final int line;
  final Map<String, Object?> args;
  final List<StoryChoice> choices;
  const StoryCommand(this.kind, this.line, [this.args = const {}, this.choices = const []]);

  String? arg(String key) => args[key] as String?;
}

class StoryProgram {
  String title = '';
  final Map<String, String> backgrounds = {};
  final Map<String, StoryCharacter> characters = {};
  final Map<String, Object?> initialVars = {};
  final Map<String, int> labels = {};
  final List<StoryCommand> commands = [];
  final List<StoryError> errors = [];

  bool get ok => errors.isEmpty;
}

class StoryScript {
  StoryScript._();

  static const positions = ['left', 'center', 'right'];

  static StoryProgram parse(String source) {
    final p = StoryProgram();
    final lines = source.split('\n');
    final pendingJumps = <(String, int)>[];
    StoryCommand? openChoice;
    for (var n = 0; n < lines.length; n++) {
      final lineNo = n + 1;
      var raw = lines[n].replaceAll('\r', '');
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      // Choice options belong to the choice above them
      if (trimmed.startsWith('*') || trimmed.startsWith('-')) {
        if (openChoice == null) {
          p.errors.add(StoryError(lineNo, 'an option ("* ...") must follow a "choice:" line'));
          continue;
        }
        final option = _option(trimmed.substring(1).trim(), lineNo, p);
        if (option != null) {
          openChoice.choices.add(option);
          pendingJumps.add((option.target, lineNo));
        }
        continue;
      }
      if (openChoice != null && openChoice.choices.isEmpty) {
        p.errors.add(StoryError(openChoice.line, 'this choice has no options'));
      }
      openChoice = null;

      if (trimmed.startsWith('@')) {
        _directive(trimmed, lineNo, p);
        continue;
      }
      final labelMatch = RegExp(r'^(?:label\s+([A-Za-z_]\w*)\s*:|==+\s*([A-Za-z_]\w*)\s*=*)$').firstMatch(trimmed);
      if (labelMatch != null) {
        final name = labelMatch.group(1) ?? labelMatch.group(2)!;
        if (p.labels.containsKey(name)) p.errors.add(StoryError(lineNo, 'label "$name" is defined twice'));
        p.labels[name] = p.commands.length;
        continue;
      }
      final word = trimmed.split(RegExp(r'\s+')).first;
      final rest = trimmed.substring(word.length).trim();
      switch (word) {
        case 'scene':
          final parts = rest.split(RegExp(r'\s+'));
          if (rest.isEmpty) {
            p.errors.add(StoryError(lineNo, 'scene needs a background name'));
          } else if (!p.backgrounds.containsKey(parts[0]) && parts[0] != 'black') {
            p.errors.add(StoryError(lineNo, 'no background "${parts[0]}" (add "@background ${parts[0]} path/to/image.png")'));
          }
          p.commands.add(StoryCommand('scene', lineNo, {'name': parts.isEmpty ? '' : parts[0], 'transition': parts.length > 1 ? parts[1] : 'fade'}));
        case 'show':
          final parts = rest.split(RegExp(r'\s+'));
          final c = p.characters[parts.isEmpty ? '' : parts[0]];
          if (c == null) {
            p.errors.add(StoryError(lineNo, 'show: no character "${parts.isEmpty ? '' : parts[0]}"'));
            continue;
          }
          String? expression;
          var position = 'center';
          for (final part in parts.skip(1)) {
            if (positions.contains(part)) {
              position = part;
            } else if (c.expressions.contains(part)) {
              expression = part;
            } else {
              p.errors.add(StoryError(lineNo, '"$part" is not an expression of ${c.id} (${c.expressions.join(', ')}) or a position (left, center, right)'));
            }
          }
          p.commands.add(StoryCommand('show', lineNo, {'id': c.id, 'expression': expression, 'position': position}));
        case 'hide':
          if (!p.characters.containsKey(rest)) p.errors.add(StoryError(lineNo, 'hide: no character "$rest"'));
          p.commands.add(StoryCommand('hide', lineNo, {'id': rest}));
        case 'music':
          final parts = rest.split(RegExp(r'\s+'));
          p.commands.add(StoryCommand('music', lineNo, {'path': parts.isEmpty ? 'stop' : parts[0], 'volume': parts.length > 1 ? parts[1] : '0.5'}));
        case 'sound':
          final parts = rest.split(RegExp(r'\s+'));
          p.commands.add(StoryCommand('sound', lineNo, {'name': parts.isEmpty ? '' : parts[0], 'volume': parts.length > 1 ? parts[1] : '0.8'}));
        case 'set':
          if (!RegExp(r'^[A-Za-z_]\w*\s*(=|\+=|-=)').hasMatch(rest)) {
            p.errors.add(StoryError(lineNo, 'set needs "name = value" (or += / -=)'));
            continue;
          }
          final err = StoryExpr.checkAssignment(rest);
          if (err != null) p.errors.add(StoryError(lineNo, err));
          p.commands.add(StoryCommand('set', lineNo, {'assign': rest}));
        case 'jump':
          pendingJumps.add((rest, lineNo));
          p.commands.add(StoryCommand('jump', lineNo, {'target': rest}));
        case 'if':
          final m = RegExp(r'^(.+?)\s+jump\s+([A-Za-z_]\w*)$').firstMatch(rest);
          if (m == null) {
            p.errors.add(StoryError(lineNo, 'write "if <condition> jump <label>"'));
            continue;
          }
          final err = StoryExpr.check(m.group(1)!);
          if (err != null) p.errors.add(StoryError(lineNo, err));
          pendingJumps.add((m.group(2)!, lineNo));
          p.commands.add(StoryCommand('if', lineNo, {'condition': m.group(1)!.trim(), 'target': m.group(2)!}));
        case 'choice':
        case 'choice:':
          openChoice = StoryCommand('choice', lineNo, const {}, []);
          p.commands.add(openChoice);
        case 'wait':
          final s = double.tryParse(rest);
          if (s == null) p.errors.add(StoryError(lineNo, 'wait needs seconds, e.g. "wait 1.5"'));
          p.commands.add(StoryCommand('wait', lineNo, {'seconds': '${s ?? 1}'}));
        case 'event':
          p.commands.add(StoryCommand('event', lineNo, {'name': rest}));
        case 'end':
          p.commands.add(StoryCommand('end', lineNo, {'ending': rest}));
        default:
          p.commands.add(_say(trimmed, lineNo, p));
      }
    }
    if (openChoice != null && openChoice.choices.isEmpty) p.errors.add(StoryError(openChoice.line, 'this choice has no options'));
    for (final (target, line) in pendingJumps) {
      if (!p.labels.containsKey(target)) p.errors.add(StoryError(line, 'no label "$target"'));
    }
    p.errors.sort((a, b) => a.line.compareTo(b.line));
    return p;
  }

  static void _directive(String line, int lineNo, StoryProgram p) {
    final word = line.split(RegExp(r'\s+')).first;
    final rest = line.substring(word.length).trim();
    switch (word) {
      case '@title':
        p.title = rest;
      case '@background':
        final parts = rest.split(RegExp(r'\s+'));
        if (parts.length < 2) {
          p.errors.add(StoryError(lineNo, 'write "@background name path/to/image.png"'));
          return;
        }
        p.backgrounds[parts[0]] = parts[1];
      case '@character':
        final m = RegExp(r'^([A-Za-z_]\w*)\s+"([^"]+)"\s+#([0-9A-Fa-f]{6})\s+(\S+)((?:\s+[A-Za-z_]\w*)*)$').firstMatch(rest);
        if (m == null) {
          p.errors.add(StoryError(lineNo, 'write "@character id \\"Name\\" #RRGGBB path/to/sheet.png expression1 expression2 ..."'));
          return;
        }
        final expressions = m.group(5)!.trim().isEmpty ? <String>['neutral'] : m.group(5)!.trim().split(RegExp(r'\s+'));
        p.characters[m.group(1)!] = StoryCharacter(m.group(1)!, m.group(2)!, 0xFF000000 | int.parse(m.group(3)!, radix: 16), m.group(4)!, expressions);
      case '@var':
        final m = RegExp(r'^([A-Za-z_]\w*)\s*=\s*(.+)$').firstMatch(rest);
        if (m == null) {
          p.errors.add(StoryError(lineNo, 'write "@var name = value"'));
          return;
        }
        try {
          p.initialVars[m.group(1)!] = StoryExpr.eval(m.group(2)!, const {});
        } catch (e) {
          p.errors.add(StoryError(lineNo, '$e'));
        }
      default:
        p.errors.add(StoryError(lineNo, 'unknown "$word" (use @title, @background, @character or @var)'));
    }
  }

  static StoryChoice? _option(String text, int lineNo, StoryProgram p) {
    final m = RegExp(r'^(.+?)(?:\s*\[if\s+(.+?)\])?(?:\s*\{(.+?)\})?\s*->\s*([A-Za-z_]\w*)\s*$').firstMatch(text);
    if (m == null) {
      p.errors.add(StoryError(lineNo, 'write "* Option text -> label" (optionally [if condition] and {name = value} before the arrow)'));
      return null;
    }
    final condition = m.group(2), effect = m.group(3);
    if (condition != null) {
      final err = StoryExpr.check(condition);
      if (err != null) p.errors.add(StoryError(lineNo, err));
    }
    if (effect != null) {
      final err = StoryExpr.checkAssignment(effect);
      if (err != null) p.errors.add(StoryError(lineNo, err));
    }
    return StoryChoice(m.group(1)!.trim(), m.group(4)!, condition: condition, effect: effect);
  }

  /// `id: text`, `id expression: text`, `"Name": text`, or narration.
  static StoryCommand _say(String line, int lineNo, StoryProgram p) {
    final quoted = RegExp(r'^"([^"]+)"\s*:\s*(.*)$').firstMatch(line);
    if (quoted != null) return StoryCommand('say', lineNo, {'name': quoted.group(1), 'text': quoted.group(2)});
    final m = RegExp(r'^([A-Za-z_]\w*)(?:\s+([A-Za-z_]\w*))?\s*:\s*(.*)$').firstMatch(line);
    if (m != null) {
      final c = p.characters[m.group(1)!];
      if (c != null) {
        final expression = m.group(2);
        if (expression != null && !c.expressions.contains(expression)) {
          p.errors.add(StoryError(lineNo, '"$expression" is not an expression of ${c.id} (${c.expressions.join(', ')})'));
        }
        return StoryCommand('say', lineNo, {'id': c.id, 'expression': expression, 'text': m.group(3)});
      }
    }
    return StoryCommand('say', lineNo, {'text': line});
  }
}

/// Values and conditions in stories: numbers, "strings", true/false,
/// variables, + - * / %, == != < > <= >=, and / or / not (or && || !), (...).
class StoryExpr {
  StoryExpr._();

  static Object? eval(String source, Map<String, Object?> vars) => _ExprParser(source, vars).parse();

  static bool truthy(Object? v) => v == true || (v is num && v != 0) || (v is String && v.isNotEmpty);

  /// Applies `name = value`, `name += value` or `name -= value` to [vars].
  static void assign(String source, Map<String, Object?> vars) {
    final m = RegExp(r'^\s*([A-Za-z_]\w*)\s*(=|\+=|-=)\s*(.+)$').firstMatch(source);
    if (m == null) throw FormatException('write "name = value"');
    final name = m.group(1)!, op = m.group(2)!;
    final value = eval(m.group(3)!, vars);
    if (op == '=') {
      vars[name] = value;
    } else {
      final old = vars[name] ?? 0;
      if (old is! num || value is! num) throw FormatException('$op needs numbers');
      vars[name] = op == '+=' ? old + value : old - value;
    }
  }

  /// A message if [source] is not a valid expression, else null.
  static String? check(String source) {
    try {
      _ExprParser(source, const {}, dryRun: true).parse();
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  static String? checkAssignment(String source) {
    final m = RegExp(r'^\s*([A-Za-z_]\w*)\s*(=|\+=|-=)\s*(.+)$').firstMatch(source);
    if (m == null) return 'write "name = value" (or += / -=)';
    return check(m.group(3)!);
  }

  static String format(Object? v) {
    if (v is double && v == v.roundToDouble()) return v.toInt().toString();
    return '${v ?? ''}';
  }
}

class _ExprParser {
  final String src;
  final Map<String, Object?> vars;
  final bool dryRun;
  int i = 0;
  _ExprParser(this.src, this.vars, {this.dryRun = false});

  Object? parse() {
    final v = _or();
    _space();
    if (i < src.length) throw FormatException('unexpected "${src.substring(i)}" in "$src"');
    return v;
  }

  void _space() {
    while (i < src.length && (src[i] == ' ' || src[i] == '\t')) {
      i++;
    }
  }

  bool _take(String token) {
    _space();
    if (src.startsWith(token, i)) {
      // whole words only for and/or/not
      if (RegExp(r'^[a-z]+$').hasMatch(token) && i + token.length < src.length && RegExp(r'\w').hasMatch(src[i + token.length])) return false;
      i += token.length;
      return true;
    }
    return false;
  }

  Object? _or() {
    var l = _and();
    while (_take('||') || _take('or')) {
      final r = _and();
      l = StoryExpr.truthy(l) || StoryExpr.truthy(r);
    }
    return l;
  }

  Object? _and() {
    var l = _not();
    while (_take('&&') || _take('and')) {
      final r = _not();
      l = StoryExpr.truthy(l) && StoryExpr.truthy(r);
    }
    return l;
  }

  Object? _not() {
    if (_take('!') || _take('not')) return !StoryExpr.truthy(_not());
    return _compare();
  }

  Object? _compare() {
    final l = _sum();
    for (final op in ['==', '!=', '<=', '>=', '<', '>']) {
      if (_take(op)) {
        final r = _sum();
        if (dryRun) return false;
        switch (op) {
          case '==':
            return l == r || (l is num && r is num && l == r);
          case '!=':
            return !(l == r || (l is num && r is num && l == r));
        }
        if (l is! num || r is! num) throw FormatException('$op needs numbers');
        return switch (op) { '<=' => l <= r, '>=' => l >= r, '<' => l < r, _ => l > r };
      }
    }
    return l;
  }

  Object? _sum() {
    var l = _product();
    while (true) {
      if (_take('+')) {
        final r = _product();
        if (dryRun) continue;
        l = l is String || r is String ? '${StoryExpr.format(l)}${StoryExpr.format(r)}' : _num(l) + _num(r);
      } else if (_take('-')) {
        final r = _product();
        if (!dryRun) l = _num(l) - _num(r);
      } else {
        return l;
      }
    }
  }

  Object? _product() {
    var l = _unary();
    while (true) {
      if (_take('*')) {
        final r = _unary();
        if (!dryRun) l = _num(l) * _num(r);
      } else if (_take('/')) {
        final r = _unary();
        if (!dryRun) l = _num(l) / _num(r);
      } else if (_take('%')) {
        final r = _unary();
        if (!dryRun) l = _num(l) % _num(r);
      } else {
        return l;
      }
    }
  }

  Object? _unary() {
    if (_take('-')) {
      final v = _unary();
      return dryRun ? 0 : -_num(v);
    }
    return _atom();
  }

  Object? _atom() {
    _space();
    if (i >= src.length) throw FormatException('a value is missing in "$src"');
    final c = src[i];
    if (c == '(') {
      i++;
      final v = _or();
      if (!_take(')')) throw FormatException('a ")" is missing in "$src"');
      return v;
    }
    if (c == '"') {
      final end = src.indexOf('"', i + 1);
      if (end < 0) throw FormatException('a closing quote is missing in "$src"');
      final s = src.substring(i + 1, end);
      i = end + 1;
      return s;
    }
    final num = RegExp(r'^\d+(\.\d+)?').firstMatch(src.substring(i));
    if (num != null) {
      i += num.group(0)!.length;
      return num.group(1) == null ? int.parse(num.group(0)!) : double.parse(num.group(0)!);
    }
    final id = RegExp(r'^[A-Za-z_]\w*').firstMatch(src.substring(i));
    if (id != null) {
      i += id.group(0)!.length;
      final name = id.group(0)!;
      if (name == 'true') return true;
      if (name == 'false') return false;
      return vars[name] ?? 0;
    }
    throw FormatException('unexpected "$c" in "$src"');
  }

  num _num(Object? v) {
    if (v is num) return v;
    if (v is bool) return v ? 1 : 0;
    throw FormatException('"${StoryExpr.format(v)}" is not a number');
  }
}

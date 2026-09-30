import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../scripting/api.dart';
import '../theme/ember_theme.dart';

// ---------------------------------------------------------------------------
// Syntax highlighting

const _keywords = {
  'var', 'final', 'const', 'if', 'else', 'while', 'do', 'for', 'in', 'break', 'continue', 'return', 'true', 'false',
  'null', 'void', 'int', 'double', 'String', 'bool', 'List', 'Map', 'num', 'dynamic',
};

class CodeColors {
  static const text = Color(0xFFE2E8F0);
  static const keyword = Color(0xFFFF7A45);
  static const string = Color(0xFFFBBF24);
  static const number = Color(0xFFA78BFA);
  static const comment = Color(0xFF64748B);
  static const api = Color(0xFF38BDF8);
  static const callback = Color(0xFF4ADE80);
  static const gutter = Color(0xFF475569);
  static const errorLine = Color(0x33EF4444);
}

final _tokenPattern = RegExp(
  r'(//[^\n]*|/\*[\s\S]*?(\*/|$))' // 1 comment
  r"""|('(?:[^'\\\n]|\\.)*'?|"(?:[^"\\\n]|\\.)*"?)""" // 3 string
  r'|(\b\d+(?:\.\d+)?\b|\b0x[0-9a-fA-F]+\b)' // 4 number
  r'|([A-Za-z_]\w*)', // 5 identifier
);

/// A TextEditingController that colours Ember Script.
class EmberCodeController extends TextEditingController {
  EmberCodeController({super.text});

  static final Set<String> _apiNames = {
    for (final e in ScriptApi.globals) e.name,
    'self', 'Input', 'Game',
  };
  static final Set<String> _callbackNames = {for (final e in ScriptApi.callbacks) e.name};

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final base = style ?? const TextStyle(color: CodeColors.text);
    final spans = <TextSpan>[];
    var last = 0;
    final src = text;
    for (final m in _tokenPattern.allMatches(src)) {
      if (m.start > last) spans.add(TextSpan(text: src.substring(last, m.start)));
      final t = m.group(0)!;
      Color? color;
      FontWeight? weight;
      if (m.group(1) != null) {
        color = CodeColors.comment;
      } else if (m.group(3) != null) {
        color = CodeColors.string;
      } else if (m.group(4) != null) {
        color = CodeColors.number;
      } else if (_keywords.contains(t)) {
        color = CodeColors.keyword;
        weight = FontWeight.w600;
      } else if (_callbackNames.contains(t)) {
        color = CodeColors.callback;
      } else if (_apiNames.contains(t)) {
        color = CodeColors.api;
      }
      spans.add(TextSpan(text: t, style: color == null ? null : TextStyle(color: color, fontWeight: weight)));
      last = m.end;
    }
    if (last < src.length) spans.add(TextSpan(text: src.substring(last)));
    return TextSpan(style: base, children: spans);
  }
}

// ---------------------------------------------------------------------------
// Autocomplete

class Suggestion {
  final String label;
  final String insert;
  final String detail;
  final String kind; // var, function, api, member, keyword, event
  const Suggestion(this.label, this.insert, this.detail, this.kind);
}

/// Suggestions for the word being typed at [caret] in [text].
/// Returns the prefix length to replace and the candidates.
(int, List<Suggestion>) suggestionsAt(String text, int caret, {bool force = false}) {
  if (caret < 0 || caret > text.length) return (0, const []);
  var start = caret;
  while (start > 0 && RegExp(r'\w').hasMatch(text[start - 1])) {
    start--;
  }
  final prefix = text.substring(start, caret);
  final afterDot = start > 0 && text[start - 1] == '.';
  if (!force && !afterDot && prefix.isEmpty) return (0, const []);
  if (!force && !afterDot && prefix.length < 2) return (0, const []);
  // Not inside a comment or string on this line
  final lineStart = text.lastIndexOf('\n', math.max(0, caret - 1)) + 1;
  final before = text.substring(lineStart, start);
  if (before.contains('//') || "'".allMatches(before).length.isOdd || '"'.allMatches(before).length.isOdd) {
    return (0, const []);
  }

  final out = <Suggestion>[];
  if (afterDot) {
    var o = start - 1;
    var end = o;
    while (o > 0 && RegExp(r'\w').hasMatch(text[o - 1])) {
      o--;
    }
    final owner = text.substring(o, end);
    final owners = switch (owner) {
      'Input' => ['Input'],
      'Game' => ['Game'],
      'self' || 'other' || 'target' || 'player' || 'enemy' || 'e' || 'killer' || 'victim' || 'source' || 'by' => ['Entity'],
      'health' || 'sprite' || 'mover' || 'controller' || 'animator' || 'particles' || 'text' || 'ai' || 'hitbox' => ['Component'],
      'position' || 'center' || 'move' || 'velocity' || 'dir' || 'direction' => ['Vec2'],
      'tile' => ['Tile'],
      _ => ['Entity', 'Vec2', 'List', 'Text'],
    };
    final seen = <String>{};
    for (final ow in owners) {
      for (final e in ScriptApi.members(ow)) {
        if (e.name.startsWith('(') || !seen.add(e.name)) continue;
        out.add(Suggestion(e.signature, e.insertText, e.doc, 'member'));
      }
    }
  } else {
    // This file's own variables and functions
    final seen = <String>{};
    for (final m in RegExp(r'^\s*(?:var|final|const|int|double|String|bool|List|Map)\s+(\w+)', multiLine: true).allMatches(text)) {
      if (seen.add(m.group(1)!)) out.add(Suggestion(m.group(1)!, m.group(1)!, 'variable in this script', 'var'));
    }
    for (final m in RegExp(r'^\s*(?:void\s+|\w+\s+)?(\w+)\s*\(([^)]*)\)\s*(?:\{|=>)', multiLine: true).allMatches(text)) {
      final n = m.group(1)!;
      if (_keywords.contains(n) || n == 'if' || n == 'for' || n == 'while') continue;
      if (seen.add(n)) out.add(Suggestion('$n(${m.group(2)})', '$n(', 'function in this script', 'function'));
    }
    final atLineStart = before.trim().isEmpty;
    for (final e in ScriptApi.callbacks) {
      if (!atLineStart || text.contains(RegExp('\\b${e.name}\\s*\\('))) continue;
      final params = RegExp(r'\((.*)\)').firstMatch(e.signature)?.group(1) ?? '';
      out.add(Suggestion('void ${e.signature}', 'void ${e.name}($params) {\n  \n}', e.doc, 'event'));
    }
    for (final e in ScriptApi.globals) {
      if (e.name.startsWith('(')) continue;
      out.add(Suggestion(e.signature, e.insertText, e.doc, 'api'));
    }
    for (final k in const ['var', 'final', 'if', 'else', 'for', 'while', 'return', 'true', 'false', 'null', 'void', 'break', 'continue']) {
      out.add(Suggestion(k, k, 'keyword', 'keyword'));
    }
  }
  final p = prefix.toLowerCase();
  final starts = out.where((s) => _name(s).toLowerCase().startsWith(p)).toList();
  final contains = out.where((s) => !_name(s).toLowerCase().startsWith(p) && _name(s).toLowerCase().contains(p)).toList();
  final result = [...starts, ...contains].where((s) => _name(s) != prefix).take(40).toList();
  return (prefix.length, result);
}

String _name(Suggestion s) {
  final l = s.label.startsWith('void ') ? s.label.substring(5) : s.label;
  return RegExp(r'^\w+').firstMatch(l)?.group(0) ?? l;
}

// ---------------------------------------------------------------------------
// Editor widget

class ScriptCodeEditor extends StatefulWidget {
  final EmberCodeController controller;
  final FocusNode focusNode;

  /// 1-based line to mark as an error (0 = none) and its message.
  final int errorLine;
  final String? errorMessage;
  final VoidCallback? onSave;
  final VoidCallback? onFind;

  const ScriptCodeEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    this.errorLine = 0,
    this.errorMessage,
    this.onSave,
    this.onFind,
  });

  @override
  State<ScriptCodeEditor> createState() => ScriptCodeEditorState();
}

class ScriptCodeEditorState extends State<ScriptCodeEditor> {
  static const double fontSize = 13;
  static const double lineHeight = 1.55;
  static const double pad = 10;
  static const TextStyle codeStyle = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: ['Cascadia Mono', 'Courier New', 'monospace'],
    fontSize: fontSize,
    height: lineHeight,
    color: CodeColors.text,
  );
  static const StrutStyle strut = StrutStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: ['Cascadia Mono', 'Courier New', 'monospace'],
    fontSize: fontSize,
    height: lineHeight,
    forceStrutHeight: true,
  );

  final ScrollController _v = ScrollController();
  final ScrollController _h = ScrollController();
  late double _charW;
  double get _lineH => fontSize * lineHeight;

  List<Suggestion> _suggestions = const [];
  int _prefixLen = 0;
  int _selected = 0;
  bool _suppressSuggest = false;

  @override
  void initState() {
    super.initState();
    final tp = TextPainter(text: const TextSpan(text: 'MMMMMMMMMM', style: codeStyle), textDirection: TextDirection.ltr)..layout();
    _charW = tp.width / 10;
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant ScriptCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _closeSuggestions();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _v.dispose();
    _h.dispose();
    super.dispose();
  }

  String? _lastText;

  void _onChanged() {
    final text = widget.controller.text;
    final textChanged = text != _lastText;
    _lastText = text;
    if (!textChanged) {
      // Cursor moved without typing: close the popup
      if (_suggestions.isNotEmpty) _closeSuggestions();
      setState(() {});
      return;
    }
    if (_suppressSuggest) {
      _suppressSuggest = false;
      setState(() {});
      return;
    }
    _updateSuggestions();
  }

  void _updateSuggestions({bool force = false}) {
    final sel = widget.controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return _closeSuggestions();
    final (len, list) = suggestionsAt(widget.controller.text, sel.baseOffset, force: force);
    setState(() {
      _prefixLen = len;
      _suggestions = list;
      _selected = 0;
    });
  }

  void _closeSuggestions() {
    if (_suggestions.isEmpty) return;
    setState(() => _suggestions = const []);
  }

  void _accept(Suggestion s) {
    final c = widget.controller;
    final caret = c.selection.baseOffset;
    final start = caret - _prefixLen;
    var insert = s.insert;
    // Indent multi-line snippets (events) to the current line
    final lineStart = c.text.lastIndexOf('\n', math.max(0, start - 1)) + 1;
    final indent = RegExp(r'^[ \t]*').firstMatch(c.text.substring(lineStart))!.group(0)!;
    insert = insert.replaceAll('\n', '\n$indent');
    var cursor = start + insert.length;
    if (s.kind == 'event') cursor = start + insert.indexOf('\n$indent  ') + 1 + indent.length + 2;
    _suppressSuggest = true;
    c.value = TextEditingValue(
      text: c.text.replaceRange(start, caret, insert),
      selection: TextSelection.collapsed(offset: cursor),
    );
    setState(() => _suggestions = const []);
  }

  /// Replaces the selection (or inserts at the cursor) with [text].
  void insertText(String text) {
    final c = widget.controller;
    final sel = c.selection.isValid ? c.selection : TextSelection.collapsed(offset: c.text.length);
    _suppressSuggest = true;
    c.value = TextEditingValue(
      text: c.text.replaceRange(sel.start, sel.end, text),
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
    widget.focusNode.requestFocus();
  }

  /// Moves the cursor to [line] (1-based) and scrolls it into view.
  void goToLine(int line, {int column = 1}) {
    final c = widget.controller;
    final lines = c.text.split('\n');
    final l = line.clamp(1, lines.length);
    var offset = 0;
    for (var i = 0; i < l - 1; i++) {
      offset += lines[i].length + 1;
    }
    offset += (column - 1).clamp(0, lines[l - 1].length);
    c.selection = TextSelection.collapsed(offset: offset);
    widget.focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_v.hasClients) return;
      final target = (l - 1) * _lineH - _v.position.viewportDimension / 3;
      _v.animateTo(target.clamp(0, _v.position.maxScrollExtent), duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  /// Selects [start, end) and scrolls to it (find).
  void select(int start, int end) {
    final c = widget.controller;
    c.selection = TextSelection(baseOffset: start, extentOffset: end);
    final line = '\n'.allMatches(c.text.substring(0, start)).length;
    if (_v.hasClients) {
      final target = line * _lineH - _v.position.viewportDimension / 3;
      _v.jumpTo(target.clamp(0, _v.position.maxScrollExtent));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (_suggestions.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _selected = (_selected + 1) % _suggestions.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _selected = (_selected - 1 + _suggestions.length) % _suggestions.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
        _accept(_suggestions[_selected]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _closeSuggestions();
        return KeyEventResult.handled;
      }
    }

    if (ctrl && key == LogicalKeyboardKey.space) {
      _updateSuggestions(force: true);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyS) {
      widget.onSave?.call();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyF) {
      widget.onFind?.call();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.slash) {
      _toggleComment();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      shift ? _outdent() : insertText('  ');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && !ctrl) {
      _newlineWithIndent();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _newlineWithIndent() {
    final c = widget.controller;
    final sel = c.selection;
    if (!sel.isValid) return;
    final text = c.text;
    final lineStart = text.lastIndexOf('\n', math.max(0, sel.start - 1)) + 1;
    final line = text.substring(lineStart, sel.start);
    var indent = RegExp(r'^[ \t]*').firstMatch(line)!.group(0)!;
    final trimmed = line.trimRight();
    final opens = trimmed.endsWith('{') || trimmed.endsWith('(') || trimmed.endsWith('[');
    final closesNext = sel.end < text.length && '})]'.contains(text[sel.end]);
    String insert;
    int cursor;
    if (opens) {
      final inner = '$indent  ';
      insert = closesNext ? '\n$inner\n$indent' : '\n$inner';
      cursor = sel.start + 1 + inner.length;
    } else {
      insert = '\n$indent';
      cursor = sel.start + insert.length;
    }
    _suppressSuggest = true;
    c.value = TextEditingValue(text: text.replaceRange(sel.start, sel.end, insert), selection: TextSelection.collapsed(offset: cursor));
    indent = '';
  }

  (int, int) _selectedLines() {
    final c = widget.controller;
    final sel = c.selection;
    final text = c.text;
    final start = text.lastIndexOf('\n', math.max(0, sel.start - 1)) + 1;
    var end = text.indexOf('\n', sel.end);
    if (end < 0) end = text.length;
    return (start, end);
  }

  void _toggleComment() {
    final c = widget.controller;
    final (start, end) = _selectedLines();
    final lines = c.text.substring(start, end).split('\n');
    final allCommented = lines.where((l) => l.trim().isNotEmpty).every((l) => l.trimLeft().startsWith('//'));
    final changed = lines.map((l) {
      if (l.trim().isEmpty) return l;
      if (allCommented) return l.replaceFirst(RegExp(r'// ?'), '');
      final ind = RegExp(r'^[ \t]*').firstMatch(l)!.group(0)!;
      return '$ind// ${l.substring(ind.length)}';
    }).join('\n');
    _suppressSuggest = true;
    c.value = TextEditingValue(
      text: c.text.replaceRange(start, end, changed),
      selection: TextSelection(baseOffset: start, extentOffset: start + changed.length),
    );
  }

  void _outdent() {
    final c = widget.controller;
    final (start, end) = _selectedLines();
    final changed = c.text.substring(start, end).split('\n').map((l) => l.startsWith('  ') ? l.substring(2) : l.trimLeft()).join('\n');
    _suppressSuggest = true;
    c.value = TextEditingValue(
      text: c.text.replaceRange(start, end, changed),
      selection: TextSelection(baseOffset: start, extentOffset: start + changed.length),
    );
  }

  (int, int) _caretLineCol() {
    final c = widget.controller;
    final off = c.selection.isValid ? c.selection.baseOffset.clamp(0, c.text.length) : 0;
    final before = c.text.substring(0, off);
    final line = '\n'.allMatches(before).length;
    final col = off - (before.lastIndexOf('\n') + 1);
    return (line, col);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final lines = text.split('\n');
    final longest = lines.fold<int>(0, (m, l) => math.max(m, l.length));
    final gutterW = math.max(3, '${lines.length}'.length) * _charW + 24;

    return LayoutBuilder(builder: (context, box) {
      final contentW = math.max(box.maxWidth - gutterW, longest * _charW + pad * 2 + 40);
      final contentH = math.max(box.maxHeight, lines.length * _lineH + pad * 2 + box.maxHeight / 2);
      final (cLine, cCol) = _caretLineCol();

      return Stack(
        children: [
          Scrollbar(
            controller: _v,
            child: SingleChildScrollView(
              controller: _v,
              child: SizedBox(
                height: contentH,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _gutter(lines.length, gutterW),
                    Expanded(
                      child: Scrollbar(
                        controller: _h,
                        child: SingleChildScrollView(
                          controller: _h,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: contentW,
                            height: contentH,
                            child: Stack(
                              children: [
                                if (widget.errorLine > 0)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: pad + (widget.errorLine - 1) * _lineH,
                                    height: _lineH,
                                    child: const ColoredBox(color: CodeColors.errorLine),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: pad + cLine * _lineH,
                                  height: _lineH,
                                  child: const ColoredBox(color: Color(0x0DFFFFFF)),
                                ),
                                Focus(
                                  onKeyEvent: _onKey,
                                  skipTraversal: true,
                                  canRequestFocus: false,
                                  child: TextField(
                                    key: const ValueKey('code-editor-field'),
                                    controller: widget.controller,
                                    focusNode: widget.focusNode,
                                    maxLines: null,
                                    minLines: 1,
                                    keyboardType: TextInputType.multiline,
                                    style: codeStyle,
                                    strutStyle: strut,
                                    cursorColor: EmberTheme.accentEmber,
                                    scrollPhysics: const NeverScrollableScrollPhysics(),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                      contentPadding: EdgeInsets.all(pad),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_suggestions.isNotEmpty) _popup(gutterW, cLine, cCol, box),
        ],
      );
    });
  }

  Widget _gutter(int count, double width) {
    final (caretLine, _) = _caretLineCol();
    return Container(
      width: width,
      padding: const EdgeInsets.only(top: pad, right: 10),
      color: const Color(0xFF14161B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= count; i++)
            SizedBox(
              height: _lineH,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (i == widget.errorLine)
                    Tooltip(
                      message: widget.errorMessage ?? 'Error',
                      child: const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.error, size: 12, color: Colors.redAccent),
                      ),
                    ),
                  Text(
                    '$i',
                    style: codeStyle.copyWith(
                      color: i == widget.errorLine
                          ? Colors.redAccent
                          : (i - 1 == caretLine ? const Color(0xFFCBD5E1) : CodeColors.gutter),
                      fontSize: 12,
                    ),
                    strutStyle: strut,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _popup(double gutterW, int line, int col, BoxConstraints box) {
    final vOff = _v.hasClients ? _v.offset : 0.0;
    final hOff = _h.hasClients ? _h.offset : 0.0;
    const w = 380.0, maxH = 230.0;
    var left = gutterW + pad + (col - _prefixLen) * _charW - hOff;
    var top = pad + (line + 1) * _lineH - vOff + 2;
    left = left.clamp(0, math.max(0, box.maxWidth - w)).toDouble();
    if (top + maxH > box.maxHeight) top = math.max(0, top - maxH - _lineH - 4);
    final selected = _suggestions[_selected.clamp(0, _suggestions.length - 1)];
    return Positioned(
      left: left,
      top: top,
      width: w,
      child: Material(
        elevation: 8,
        color: const Color(0xFF1E2129),
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, i) {
                    final s = _suggestions[i];
                    final isSel = i == _selected;
                    return InkWell(
                      onTap: () => _accept(s),
                      child: Container(
                        color: isSel ? EmberTheme.accentEmber.withValues(alpha: 0.18) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        child: Row(
                          children: [
                            _kindIcon(s.kind),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(s.label,
                                  overflow: TextOverflow.ellipsis, style: codeStyle.copyWith(fontSize: 12, height: 1.3)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF2C303A)))),
                child: Text(selected.detail, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: EmberTheme.textSecondary, fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _kindIcon(String kind) {
    final (icon, color) = switch (kind) {
      'var' => (Icons.data_object, CodeColors.number),
      'function' => (Icons.functions, CodeColors.callback),
      'event' => (Icons.bolt, CodeColors.callback),
      'member' => (Icons.label_outline, CodeColors.api),
      'keyword' => (Icons.code, CodeColors.keyword),
      _ => (Icons.extension_outlined, CodeColors.api),
    };
    return Icon(icon, size: 13, color: color);
  }
}

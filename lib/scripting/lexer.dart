/// Ember Script tokenizer.
library;

enum T {
  // Literals and names
  number, string, identifier,
  // Keywords
  kVar, kFinal, kConst, kIf, kElse, kWhile, kDo, kFor, kIn, kBreak, kContinue, kReturn, kTrue, kFalse, kNull, kVoid,
  // Punctuation
  lParen, rParen, lBrace, rBrace, lBracket, rBracket, comma, dot, questionDot, semicolon, colon, question, arrow,
  // Operators
  plus, minus, star, slash, tildeSlash, percent, bang,
  eq, eqEq, bangEq, lt, ltEq, gt, gtEq, andAnd, orOr, questionQuestion,
  plusEq, minusEq, starEq, slashEq, percentEq, questionQuestionEq, plusPlus, minusMinus,
  eof,
}

const _keywords = {
  'var': T.kVar, 'final': T.kFinal, 'const': T.kConst, 'if': T.kIf, 'else': T.kElse, 'while': T.kWhile,
  'do': T.kDo, 'for': T.kFor, 'in': T.kIn, 'break': T.kBreak, 'continue': T.kContinue, 'return': T.kReturn,
  'true': T.kTrue, 'false': T.kFalse, 'null': T.kNull, 'void': T.kVoid,
};

/// A `${...}` or `$name` part of a string, kept as source for the parser.
class InterpolationSource {
  final String code;
  final int line, column;
  const InterpolationSource(this.code, this.line, this.column);
}

class Token {
  final T type;
  final String lexeme;

  /// Numbers: num. Strings: List of String / InterpolationSource parts.
  final Object? value;
  final int line, column, offset;
  const Token(this.type, this.lexeme, this.value, this.line, this.column, this.offset);

  @override
  String toString() => '$type "$lexeme" @$line:$column';
}

/// A problem in a script, with a 1-based source position.
class ScriptError implements Exception {
  final String message;
  final int line, column;
  String file;
  ScriptError(this.message, this.line, this.column, {this.file = ''});

  String get location => '${file.isEmpty ? '' : '$file:'}$line${column > 0 ? ':$column' : ''}';

  @override
  String toString() => '$location  $message';
}

class Lexer {
  final String src;
  final int lineOffset, columnOffset;
  int _pos = 0, _line = 1, _col = 1;
  final List<Token> _tokens = [];

  Lexer(this.src, {this.lineOffset = 0, this.columnOffset = 0});

  List<Token> tokenize() {
    while (true) {
      _skipSpaceAndComments();
      if (_pos >= src.length) break;
      _scanToken();
    }
    _tokens.add(Token(T.eof, '', null, _l, _c, _pos));
    return _tokens;
  }

  int get _l => _line + lineOffset;
  int get _c => _line == 1 ? _col + columnOffset : _col;

  String get _ch => src[_pos];
  String _peek([int ahead = 1]) => _pos + ahead < src.length ? src[_pos + ahead] : '';

  void _advance() {
    if (src[_pos] == '\n') {
      _line++;
      _col = 1;
    } else {
      _col++;
    }
    _pos++;
  }

  ScriptError _error(String msg) => ScriptError(msg, _l, _c);

  void _skipSpaceAndComments() {
    while (_pos < src.length) {
      final c = _ch;
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        _advance();
      } else if (c == '/' && _peek() == '/') {
        while (_pos < src.length && _ch != '\n') {
          _advance();
        }
      } else if (c == '/' && _peek() == '*') {
        final startL = _l, startC = _c;
        _advance();
        _advance();
        while (_pos < src.length && !(_ch == '*' && _peek() == '/')) {
          _advance();
        }
        if (_pos >= src.length) throw ScriptError('Unclosed /* comment', startL, startC);
        _advance();
        _advance();
      } else {
        break;
      }
    }
  }

  void _add(T type, int start, int line, int col, [Object? value]) =>
      _tokens.add(Token(type, src.substring(start, _pos), value, line, col, start));

  static bool _isDigit(String c) => c.isNotEmpty && c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  static bool _isIdStart(String c) {
    if (c.isEmpty) return false;
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == '_' || c == r'$';
  }

  static bool _isIdPart(String c) => _isIdStart(c) || _isDigit(c);

  void _scanToken() {
    final start = _pos, line = _l, col = _c;
    final c = _ch;

    if (_isDigit(c) || (c == '.' && _isDigit(_peek()))) return _number(start, line, col);
    if (c == "'" || c == '"') return _string(start, line, col, raw: false);
    if (c == 'r' && (_peek() == "'" || _peek() == '"')) {
      _advance();
      return _string(start, line, col, raw: true);
    }
    if (_isIdStart(c) && c != r'$') {
      while (_pos < src.length && _isIdPart(_ch) && _ch != r'$') {
        _advance();
      }
      final word = src.substring(start, _pos);
      _add(_keywords[word] ?? T.identifier, start, line, col);
      return;
    }

    bool match(String s) {
      if (src.startsWith(s, _pos)) {
        for (var i = 0; i < s.length; i++) {
          _advance();
        }
        return true;
      }
      return false;
    }

    // Longest operators first
    const ops = <String, T>{
      '??=': T.questionQuestionEq, '~/': T.tildeSlash, '?.': T.questionDot, '??': T.questionQuestion,
      '=>': T.arrow, '==': T.eqEq, '!=': T.bangEq, '<=': T.ltEq, '>=': T.gtEq, '&&': T.andAnd, '||': T.orOr,
      '+=': T.plusEq, '-=': T.minusEq, '*=': T.starEq, '/=': T.slashEq, '%=': T.percentEq, '++': T.plusPlus,
      '--': T.minusMinus, '(': T.lParen, ')': T.rParen, '{': T.lBrace, '}': T.rBrace, '[': T.lBracket,
      ']': T.rBracket, ',': T.comma, '.': T.dot, ';': T.semicolon, ':': T.colon, '?': T.question, '+': T.plus,
      '-': T.minus, '*': T.star, '/': T.slash, '%': T.percent, '!': T.bang, '=': T.eq, '<': T.lt, '>': T.gt,
    };
    for (final e in ops.entries) {
      if (match(e.key)) {
        _add(e.value, start, line, col);
        return;
      }
    }
    throw _error('Unexpected character "$c"');
  }

  void _number(int start, int line, int col) {
    if (_ch == '0' && (_peek() == 'x' || _peek() == 'X')) {
      _advance();
      _advance();
      while (_pos < src.length && RegExp(r'[0-9a-fA-F_]').hasMatch(_ch)) {
        _advance();
      }
      final text = src.substring(start + 2, _pos).replaceAll('_', '');
      final v = int.tryParse(text, radix: 16);
      if (v == null) throw ScriptError('Bad hex number', line, col);
      _add(T.number, start, line, col, v);
      return;
    }
    var isDouble = false;
    while (_pos < src.length && (_isDigit(_ch) || _ch == '_')) {
      _advance();
    }
    if (_pos < src.length && _ch == '.' && _isDigit(_peek())) {
      isDouble = true;
      _advance();
      while (_pos < src.length && _isDigit(_ch)) {
        _advance();
      }
    }
    if (_pos < src.length && (_ch == 'e' || _ch == 'E')) {
      final save = (_pos, _line, _col);
      _advance();
      if (_pos < src.length && (_ch == '+' || _ch == '-')) _advance();
      if (_pos < src.length && _isDigit(_ch)) {
        isDouble = true;
        while (_pos < src.length && _isDigit(_ch)) {
          _advance();
        }
      } else {
        _pos = save.$1;
        _line = save.$2;
        _col = save.$3;
      }
    }
    final text = src.substring(start, _pos).replaceAll('_', '');
    _add(T.number, start, line, col, isDouble ? double.parse(text) : int.parse(text));
  }

  void _string(int start, int line, int col, {required bool raw}) {
    final quote = _ch;
    final triple = _peek() == quote && _peek(2) == quote;
    for (var i = 0; i < (triple ? 3 : 1); i++) {
      _advance();
    }
    final parts = <Object>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isNotEmpty) {
        parts.add(buf.toString());
        buf.clear();
      }
    }

    while (true) {
      if (_pos >= src.length) throw ScriptError('Unclosed string', line, col);
      final c = _ch;
      if (triple ? (c == quote && _peek() == quote && _peek(2) == quote) : c == quote) {
        for (var i = 0; i < (triple ? 3 : 1); i++) {
          _advance();
        }
        break;
      }
      if (!triple && c == '\n') throw ScriptError('Unclosed string (strings end on the same line)', line, col);
      if (c == r'\' && !raw) {
        _advance();
        if (_pos >= src.length) throw ScriptError('Unclosed string', line, col);
        final e = _ch;
        _advance();
        switch (e) {
          case 'n':
            buf.write('\n');
          case 't':
            buf.write('\t');
          case 'r':
            buf.write('\r');
          case '0':
            buf.write('\x00');
          case 'u':
            final hex = StringBuffer();
            if (_pos < src.length && _ch == '{') {
              _advance();
              while (_pos < src.length && _ch != '}') {
                hex.write(_ch);
                _advance();
              }
              if (_pos < src.length) _advance();
            } else {
              for (var i = 0; i < 4 && _pos < src.length; i++) {
                hex.write(_ch);
                _advance();
              }
            }
            final code = int.tryParse(hex.toString(), radix: 16);
            if (code == null) throw _error('Bad \\u escape');
            buf.write(String.fromCharCode(code));
          default:
            buf.write(e);
        }
        continue;
      }
      if (c == r'$' && !raw) {
        final iLine = _l, iCol = _c;
        _advance();
        if (_pos < src.length && _ch == '{') {
          _advance();
          final codeStart = _pos, codeLine = _l, codeCol = _c;
          var depth = 1;
          String? inString;
          while (_pos < src.length) {
            final d = _ch;
            if (inString != null) {
              if (d == r'\') _advance();
              if (d == inString) inString = null;
            } else if (d == "'" || d == '"') {
              inString = d;
            } else if (d == '{') {
              depth++;
            } else if (d == '}') {
              depth--;
              if (depth == 0) break;
            }
            _advance();
          }
          if (_pos >= src.length) throw ScriptError(r'Unclosed ${ in string', iLine, iCol);
          flush();
          parts.add(InterpolationSource(src.substring(codeStart, _pos), codeLine, codeCol));
          _advance(); // }
        } else if (_pos < src.length && _isIdStart(_ch) && _ch != r'$') {
          final nameStart = _pos, nLine = _l, nCol = _c;
          while (_pos < src.length && _isIdPart(_ch) && _ch != r'$') {
            _advance();
          }
          flush();
          parts.add(InterpolationSource(src.substring(nameStart, _pos), nLine, nCol));
        } else {
          buf.write(r'$');
        }
        continue;
      }
      buf.write(c);
      _advance();
    }
    flush();
    _add(T.string, start, line, col, parts);
  }
}

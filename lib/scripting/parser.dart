/// Ember Script parser: tokens -> [Program].
library;

import 'ast.dart';
import 'lexer.dart';

class Parser {
  final List<Token> _t;
  final String file;
  int _i = 0;

  Parser(this._t, {this.file = ''});

  /// Parses a whole script file.
  static Program parseProgram(String source, {String file = ''}) {
    try {
      return Parser(Lexer(source).tokenize(), file: file)._program();
    } on ScriptError catch (e) {
      e.file = file;
      rethrow;
    }
  }

  /// Parses a single expression (used for string interpolation and the console).
  static Expr parseExpression(String source, {int lineOffset = 0, int columnOffset = 0, String file = ''}) {
    final p = Parser(Lexer(source, lineOffset: lineOffset, columnOffset: columnOffset).tokenize(), file: file);
    final e = p._expression();
    if (!p._check(T.eof)) throw p._error(p._peek, 'Unexpected "${p._peek.lexeme}"');
    return e;
  }

  // --- Token helpers ---

  Token get _peek => _t[_i];
  Token _peekAt(int n) => _t[(_i + n).clamp(0, _t.length - 1)];
  Token get _previous => _t[_i - 1];
  bool _check(T type) => _peek.type == type;
  bool _checkAt(int n, T type) => _peekAt(n).type == type;

  Token _advance() {
    if (!_check(T.eof)) _i++;
    return _previous;
  }

  bool _match(T type) {
    if (!_check(type)) return false;
    _advance();
    return true;
  }

  ScriptError _error(Token at, String message) => ScriptError(message, at.line, at.column, file: file);

  Token _expect(T type, String what) {
    if (_check(type)) return _advance();
    if (type == T.semicolon && _i > 0) {
      // Point just after the previous token: that is where the ';' is missing
      final p = _previous;
      throw ScriptError("Missing ';' after \"${p.lexeme}\"", p.line, p.column + p.lexeme.length, file: file);
    }
    final got = _check(T.eof) ? 'end of file' : '"${_peek.lexeme}"';
    throw _error(_peek, 'Expected $what but found $got');
  }

  String _identifier(String what) => _expect(T.identifier, what).lexeme;

  // --- Types (parsed and ignored: Ember Script is dynamically typed) ---

  /// Skips a type like `int`, `double?`, `List<Vec2>`, `Map<String, int>`.
  bool _skipType() {
    final save = _i;
    if (_match(T.kVoid)) return true;
    if (!_match(T.identifier)) return false;
    if (_check(T.lt)) {
      _advance();
      var ok = true;
      do {
        if (!_skipType()) {
          ok = false;
          break;
        }
      } while (_match(T.comma));
      if (!ok || !_match(T.gt)) {
        _i = save;
        return false;
      }
    }
    _match(T.question);
    return true;
  }

  /// Looks ahead: is this `Type name ...` (a typed declaration)?
  bool _looksLikeTypedDeclaration() {
    final save = _i;
    try {
      if (!_skipType()) return false;
      if (!_check(T.identifier)) return false;
      final next = _peekAt(1).type;
      return next == T.eq || next == T.semicolon || next == T.comma || next == T.lParen || next == T.kIn;
    } finally {
      _i = save;
    }
  }

  /// Looks ahead from a `(`: does the matching `)` precede `{` or `=>`?
  bool _parenStartsFunction(int from) {
    var depth = 0;
    for (var j = from; j < _t.length; j++) {
      final type = _t[j].type;
      if (type == T.lParen) depth++;
      if (type == T.rParen) {
        depth--;
        if (depth == 0) {
          final next = _t[(j + 1).clamp(0, _t.length - 1)].type;
          return next == T.lBrace || next == T.arrow;
        }
      }
      if (type == T.eof) return false;
    }
    return false;
  }

  // --- Program ---

  Program _program() {
    final fields = <FieldDecl>[];
    final functions = <String, FunctionDecl>{};
    while (!_check(T.eof)) {
      final start = _peek;
      if (_check(T.kVar) || _check(T.kFinal) || _check(T.kConst)) {
        final isFinal = !_check(T.kVar);
        _advance();
        String? typeName;
        if (_check(T.identifier) && _looksLikeTypedDeclaration()) {
          typeName = _peek.lexeme;
          _skipType();
        }
        fields.addAll(_fieldList(isFinal, typeName));
        continue;
      }
      if (_check(T.identifier) && _checkAt(1, T.lParen) && _parenStartsFunction(_i + 1)) {
        final f = _function(_identifier('a function name'));
        if (functions.containsKey(f.name)) throw _error(start, 'Function "${f.name}" is defined twice');
        functions[f.name] = f;
        continue;
      }
      if (_looksLikeTypedDeclaration()) {
        final typeName = _peek.lexeme;
        _skipType();
        if (_checkAt(1, T.lParen)) {
          final f = _function(_identifier('a function name'));
          if (functions.containsKey(f.name)) throw _error(start, 'Function "${f.name}" is defined twice');
          functions[f.name] = f;
        } else {
          fields.addAll(_fieldList(false, typeName == 'void' ? null : typeName));
        }
        continue;
      }
      throw _error(start,
          'Only variables (var speed = 100;) and functions (void onUpdate(dt) { ... }) can be at the top of a script. '
          'Put statements inside a function such as onStart().');
    }
    final seen = <String>{};
    for (final f in fields) {
      if (!seen.add(f.name)) throw ScriptError('Variable "${f.name}" is declared twice', f.line, f.column, file: file);
      if (functions.containsKey(f.name)) {
        throw ScriptError('"${f.name}" is both a variable and a function', f.line, f.column, file: file);
      }
    }
    return Program(file, fields, functions);
  }

  List<FieldDecl> _fieldList(bool isFinal, String? typeName) {
    final out = <FieldDecl>[];
    do {
      final name = _expect(T.identifier, 'a variable name');
      Expr? init;
      if (_match(T.eq)) init = _expression();
      out.add(FieldDecl(name.lexeme, init, isFinal, typeName, '', name.line, name.column));
    } while (_match(T.comma));
    _expect(T.semicolon, "';'");
    return out;
  }

  FunctionDecl _function(String name) {
    final at = _previous;
    final params = _params();
    final body = _functionBody();
    return FunctionDecl(name, params, body, at.line, at.column);
  }

  List<Param> _params() {
    _expect(T.lParen, "'('");
    final params = <Param>[];
    var mode = 0; // 0 positional, 1 [optional], 2 {named}
    while (!_check(T.rParen)) {
      if (mode == 0 && _match(T.lBracket)) {
        mode = 1;
        continue;
      }
      if (mode == 0 && _match(T.lBrace)) {
        mode = 2;
        continue;
      }
      if ((mode == 1 && _match(T.rBracket)) || (mode == 2 && _match(T.rBrace))) {
        mode = 3;
        continue;
      }
      if (_check(T.identifier) && _peek.lexeme == 'required' && _checkAt(1, T.identifier)) _advance();
      if (_check(T.kFinal) || _check(T.kVar)) _advance();
      if (_looksLikeParamType()) _skipType();
      final name = _identifier('a parameter name');
      Expr? def;
      if (_match(T.eq) || (mode == 2 && _match(T.colon))) def = _expression();
      params.add(Param(name, defaultValue: def, optional: mode == 1, named: mode == 2));
      if (!_match(T.comma)) {
        if (mode == 1) _expect(T.rBracket, "']'");
        if (mode == 2) _expect(T.rBrace, "'}'");
        break;
      }
    }
    _expect(T.rParen, "')'");
    return params;
  }

  bool _looksLikeParamType() {
    final save = _i;
    try {
      return _skipType() && _check(T.identifier);
    } finally {
      _i = save;
    }
  }

  List<Stmt> _functionBody() {
    if (_match(T.arrow)) {
      final at = _previous;
      final e = _expression();
      _expect(T.semicolon, "';'");
      return [ReturnStmt(e, at.line, at.column)];
    }
    _expect(T.lBrace, "'{' to start the function body");
    return _blockBody();
  }

  List<Stmt> _blockBody() {
    final body = <Stmt>[];
    while (!_check(T.rBrace)) {
      if (_check(T.eof)) throw _error(_peek, "Missing '}' — a block is not closed");
      body.add(_statement());
    }
    _expect(T.rBrace, "'}'");
    return body;
  }

  // --- Statements ---

  Stmt _statement() {
    final at = _peek;
    switch (at.type) {
      case T.lBrace:
        _advance();
        return BlockStmt(_blockBody(), at.line, at.column);
      case T.kVar || T.kFinal || T.kConst:
        return _varStatement();
      case T.kIf:
        _advance();
        _expect(T.lParen, "'(' after if");
        final cond = _expression();
        _expect(T.rParen, "')'");
        final then = _statement();
        final otherwise = _match(T.kElse) ? _statement() : null;
        return IfStmt(cond, then, otherwise, at.line, at.column);
      case T.kWhile:
        _advance();
        _expect(T.lParen, "'(' after while");
        final cond = _expression();
        _expect(T.rParen, "')'");
        return WhileStmt(cond, _statement(), false, at.line, at.column);
      case T.kDo:
        _advance();
        final body = _statement();
        _expect(T.kWhile, "'while' after do { ... }");
        _expect(T.lParen, "'('");
        final cond = _expression();
        _expect(T.rParen, "')'");
        _expect(T.semicolon, "';'");
        return WhileStmt(cond, body, true, at.line, at.column);
      case T.kFor:
        return _forStatement();
      case T.kBreak:
        _advance();
        _expect(T.semicolon, "';'");
        return BreakStmt(at.line, at.column);
      case T.kContinue:
        _advance();
        _expect(T.semicolon, "';'");
        return ContinueStmt(at.line, at.column);
      case T.kReturn:
        _advance();
        Expr? value;
        if (!_check(T.semicolon)) value = _expression();
        _expect(T.semicolon, "';'");
        return ReturnStmt(value, at.line, at.column);
      default:
        break;
    }
    // Local function: name(...) { or Type name(...) {
    if (_check(T.identifier) && _checkAt(1, T.lParen) && _parenStartsFunction(_i + 1)) {
      final name = _identifier('a function name');
      return FunctionStmt(_function(name), at.line, at.column);
    }
    if ((_check(T.identifier) || _check(T.kVoid)) && _looksLikeTypedDeclaration()) {
      _skipType();
      if (_checkAt(1, T.lParen)) {
        final name = _identifier('a function name');
        return FunctionStmt(_function(name), at.line, at.column);
      }
      return _varList(false, at);
    }
    final e = _expression();
    _expect(T.semicolon, "';'");
    return ExprStmt(e, at.line, at.column);
  }

  Stmt _varStatement() {
    final at = _advance();
    final isFinal = at.type != T.kVar;
    if (_check(T.identifier) && _looksLikeTypedDeclaration()) _skipType();
    return _varList(isFinal, at);
  }

  Stmt _varList(bool isFinal, Token at, {bool requireSemicolon = true}) {
    final decls = <Stmt>[];
    do {
      final name = _expect(T.identifier, 'a variable name');
      Expr? init;
      if (_match(T.eq)) init = _expression();
      decls.add(VarStmt(name.lexeme, init, isFinal, name.line, name.column));
    } while (_match(T.comma));
    if (requireSemicolon) _expect(T.semicolon, "';'");
    // Several declarations share the enclosing scope, so they are not a block
    return decls.length == 1 ? decls.first : _MultiVar(decls, at.line, at.column);
  }

  Stmt _forStatement() {
    final at = _advance();
    _expect(T.lParen, "'(' after for");
    // for (var x in list) / for (final Type x in list) / for (x in list)
    final save = _i;
    if (_check(T.kVar) || _check(T.kFinal)) _advance();
    if (_check(T.identifier) && _looksLikeTypedDeclaration()) _skipType();
    if (_check(T.identifier) && _checkAt(1, T.kIn)) {
      final name = _identifier('a loop variable');
      _advance(); // in
      final iterable = _expression();
      _expect(T.rParen, "')'");
      return ForInStmt(name, iterable, _statement(), at.line, at.column);
    }
    _i = save;

    Stmt? init;
    if (_match(T.semicolon)) {
      init = null;
    } else if (_check(T.kVar) || _check(T.kFinal)) {
      final kw = _advance();
      if (_check(T.identifier) && _looksLikeTypedDeclaration()) _skipType();
      init = _varList(kw.type != T.kVar, kw);
    } else if (_looksLikeTypedDeclaration()) {
      _skipType();
      init = _varList(false, _peek);
    } else {
      final e = _expression();
      _expect(T.semicolon, "';'");
      init = ExprStmt(e, at.line, at.column);
    }
    final cond = _check(T.semicolon) ? null : _expression();
    _expect(T.semicolon, "';'");
    final updates = <Expr>[];
    if (!_check(T.rParen)) {
      do {
        updates.add(_expression());
      } while (_match(T.comma));
    }
    _expect(T.rParen, "')'");
    return ForStmt(init, cond, updates, _statement(), at.line, at.column);
  }

  // --- Expressions ---

  Expr _expression() => _assignment();

  static const _assignOps = {
    T.eq: '', T.plusEq: '+', T.minusEq: '-', T.starEq: '*', T.slashEq: '/', T.percentEq: '%',
    T.questionQuestionEq: '??',
  };

  Expr _assignment() {
    final left = _conditional();
    final op = _assignOps[_peek.type];
    if (op != null) {
      final at = _advance();
      if (left is! NameExpr && left is! MemberExpr && left is! IndexExpr) {
        throw _error(at, 'Can only assign to a variable, a property (a.b) or an element (a[i])');
      }
      final value = _assignment();
      return AssignExpr(left, op, value, at.line, at.column);
    }
    return left;
  }

  Expr _conditional() {
    final cond = _ifNull();
    if (_check(T.question)) {
      final at = _advance();
      final then = _assignment();
      _expect(T.colon, "':' in a ? b : c");
      final otherwise = _assignment();
      return ConditionalExpr(cond, then, otherwise, at.line, at.column);
    }
    return cond;
  }

  Expr _ifNull() {
    var e = _or();
    while (_check(T.questionQuestion)) {
      final at = _advance();
      e = LogicalExpr('??', e, _or(), at.line, at.column);
    }
    return e;
  }

  Expr _or() {
    var e = _and();
    while (_check(T.orOr)) {
      final at = _advance();
      e = LogicalExpr('||', e, _and(), at.line, at.column);
    }
    return e;
  }

  Expr _and() {
    var e = _equality();
    while (_check(T.andAnd)) {
      final at = _advance();
      e = LogicalExpr('&&', e, _equality(), at.line, at.column);
    }
    return e;
  }

  Expr _binaryLevel(Expr Function() next, Map<T, String> ops) {
    var e = next();
    while (ops.containsKey(_peek.type)) {
      final at = _advance();
      e = BinaryExpr(ops[at.type]!, e, next(), at.line, at.column);
    }
    return e;
  }

  Expr _equality() => _binaryLevel(_relational, const {T.eqEq: '==', T.bangEq: '!='});
  Expr _relational() => _binaryLevel(_additive, const {T.lt: '<', T.ltEq: '<=', T.gt: '>', T.gtEq: '>='});
  Expr _additive() => _binaryLevel(_multiplicative, const {T.plus: '+', T.minus: '-'});
  Expr _multiplicative() =>
      _binaryLevel(_unary, const {T.star: '*', T.slash: '/', T.tildeSlash: '~/', T.percent: '%'});

  Expr _unary() {
    final at = _peek;
    if (_match(T.minus)) return UnaryExpr('-', _unary(), at.line, at.column);
    if (_match(T.bang)) return UnaryExpr('!', _unary(), at.line, at.column);
    if (_match(T.plusPlus) || _match(T.minusMinus)) {
      final target = _unary();
      _checkTarget(target, at);
      return UpdateExpr(target, at.type == T.plusPlus ? 1 : -1, true, at.line, at.column);
    }
    return _postfix();
  }

  void _checkTarget(Expr target, Token at) {
    if (target is! NameExpr && target is! MemberExpr && target is! IndexExpr) {
      throw _error(at, '++ and -- need a variable, property or element');
    }
  }

  Expr _postfix() {
    var e = _primary();
    while (true) {
      final at = _peek;
      if (_match(T.dot) || _match(T.questionDot)) {
        final name = _expect(T.identifier, 'a property name after "."');
        e = MemberExpr(e, name.lexeme, at.type == T.questionDot, name.line, name.column);
      } else if (_match(T.lParen)) {
        final args = <Expr>[];
        final named = <String, Expr>{};
        while (!_check(T.rParen)) {
          if (_check(T.identifier) && _checkAt(1, T.colon)) {
            final n = _advance().lexeme;
            _advance();
            named[n] = _expression();
          } else {
            if (named.isNotEmpty) throw _error(_peek, 'Positional arguments must come before named ones');
            args.add(_expression());
          }
          if (!_match(T.comma)) break;
        }
        _expect(T.rParen, "')' to close the call");
        e = CallExpr(e, args, named, at.line, at.column);
      } else if (_match(T.lBracket)) {
        final index = _expression();
        _expect(T.rBracket, "']'");
        e = IndexExpr(e, index, at.line, at.column);
      } else if (_check(T.plusPlus) || _check(T.minusMinus)) {
        _checkTarget(e, at);
        _advance();
        e = UpdateExpr(e, at.type == T.plusPlus ? 1 : -1, false, at.line, at.column);
      } else {
        return e;
      }
    }
  }

  Expr _primary() {
    final at = _peek;
    switch (at.type) {
      case T.number:
        _advance();
        return LiteralExpr(at.value, at.line, at.column);
      case T.string:
        return _stringLiteral();
      case T.kTrue:
        _advance();
        return LiteralExpr(true, at.line, at.column);
      case T.kFalse:
        _advance();
        return LiteralExpr(false, at.line, at.column);
      case T.kNull:
        _advance();
        return LiteralExpr(null, at.line, at.column);
      case T.identifier:
        _advance();
        return NameExpr(at.lexeme, at.line, at.column);
      case T.lParen:
        if (_parenStartsFunction(_i)) {
          final params = _params();
          final body = _functionBody0();
          return FunctionExpr(FunctionDecl('', params, body, at.line, at.column), at.line, at.column);
        }
        _advance();
        final e = _expression();
        _expect(T.rParen, "')'");
        return e;
      case T.lBracket:
        _advance();
        final items = <Expr>[];
        while (!_check(T.rBracket)) {
          items.add(_expression());
          if (!_match(T.comma)) break;
        }
        _expect(T.rBracket, "']' to close the list");
        return ListExpr(items, at.line, at.column);
      case T.lBrace:
        _advance();
        final entries = <(Expr, Expr)>[];
        while (!_check(T.rBrace)) {
          final k = _expression();
          _expect(T.colon, "':' between a map key and value");
          entries.add((k, _expression()));
          if (!_match(T.comma)) break;
        }
        _expect(T.rBrace, "'}' to close the map");
        return MapExpr(entries, at.line, at.column);
      case T.eof:
        throw _error(at, 'Unexpected end of file — something is not finished');
      default:
        throw _error(at, 'Unexpected "${at.lexeme}"');
    }
  }

  /// Lambda body: `=> expr` (no ';' — the enclosing expression continues) or a block.
  List<Stmt> _functionBody0() {
    if (_match(T.arrow)) {
      final at = _previous;
      return [ReturnStmt(_assignment(), at.line, at.column)];
    }
    _expect(T.lBrace, "'{'");
    return _blockBody();
  }

  Expr _stringLiteral() {
    final first = _peek;
    final parts = <Object>[];
    while (_check(T.string)) {
      final tok = _advance();
      for (final p in tok.value as List<Object>) {
        if (p is InterpolationSource) {
          parts.add(Parser.parseExpression(p.code, lineOffset: p.line - 1, columnOffset: p.column - 1, file: file));
        } else {
          parts.add(p);
        }
      }
    }
    if (parts.every((p) => p is String)) return LiteralExpr(parts.join(), first.line, first.column);
    return InterpolationExpr(parts, first.line, first.column);
  }
}

/// `var a = 1, b = 2;` — declarations in the current scope.
class _MultiVar extends BlockStmt {
  const _MultiVar(super.body, super.line, super.column);
}

bool isMultiVar(Stmt s) => s is _MultiVar;

/// Ember Script syntax tree.
library;

abstract class Node {
  final int line, column;
  const Node(this.line, this.column);
}

// ---------------------------------------------------------------------------
// Expressions

abstract class Expr extends Node {
  const Expr(super.line, super.column);
}

class LiteralExpr extends Expr {
  final Object? value;
  const LiteralExpr(this.value, super.line, super.column);
}

/// 'Hello $name, you have ${hp} hp' — parts are Strings or Exprs.
class InterpolationExpr extends Expr {
  final List<Object> parts;
  const InterpolationExpr(this.parts, super.line, super.column);
}

class ListExpr extends Expr {
  final List<Expr> items;
  const ListExpr(this.items, super.line, super.column);
}

class MapExpr extends Expr {
  final List<(Expr, Expr)> entries;
  const MapExpr(this.entries, super.line, super.column);
}

class NameExpr extends Expr {
  final String name;
  const NameExpr(this.name, super.line, super.column);
}

class MemberExpr extends Expr {
  final Expr object;
  final String name;
  final bool nullSafe;
  const MemberExpr(this.object, this.name, this.nullSafe, super.line, super.column);
}

class IndexExpr extends Expr {
  final Expr object, index;
  const IndexExpr(this.object, this.index, super.line, super.column);
}

class CallExpr extends Expr {
  final Expr callee;
  final List<Expr> args;
  final Map<String, Expr> named;
  const CallExpr(this.callee, this.args, this.named, super.line, super.column);
}

class UnaryExpr extends Expr {
  final String op; // - !
  final Expr operand;
  const UnaryExpr(this.op, this.operand, super.line, super.column);
}

class BinaryExpr extends Expr {
  final String op; // + - * / ~/ % == != < <= > >=
  final Expr left, right;
  const BinaryExpr(this.op, this.left, this.right, super.line, super.column);
}

class LogicalExpr extends Expr {
  final String op; // && || ??
  final Expr left, right;
  const LogicalExpr(this.op, this.left, this.right, super.line, super.column);
}

class ConditionalExpr extends Expr {
  final Expr condition, then, otherwise;
  const ConditionalExpr(this.condition, this.then, this.otherwise, super.line, super.column);
}

/// `target op= value` where op is '' for plain assignment, or + - * / % ??.
class AssignExpr extends Expr {
  final Expr target;
  final String op;
  final Expr value;
  const AssignExpr(this.target, this.op, this.value, super.line, super.column);
}

/// ++x / x++ / --x / x--.
class UpdateExpr extends Expr {
  final Expr target;
  final int delta;
  final bool prefix;
  const UpdateExpr(this.target, this.delta, this.prefix, super.line, super.column);
}

class FunctionExpr extends Expr {
  final FunctionDecl function;
  const FunctionExpr(this.function, super.line, super.column);
}

// ---------------------------------------------------------------------------
// Statements

abstract class Stmt extends Node {
  const Stmt(super.line, super.column);
}

class ExprStmt extends Stmt {
  final Expr expr;
  const ExprStmt(this.expr, super.line, super.column);
}

class VarStmt extends Stmt {
  final String name;
  final Expr? init;
  final bool isFinal;
  const VarStmt(this.name, this.init, this.isFinal, super.line, super.column);
}

class BlockStmt extends Stmt {
  final List<Stmt> body;
  const BlockStmt(this.body, super.line, super.column);
}

class IfStmt extends Stmt {
  final Expr condition;
  final Stmt then;
  final Stmt? otherwise;
  const IfStmt(this.condition, this.then, this.otherwise, super.line, super.column);
}

class WhileStmt extends Stmt {
  final Expr condition;
  final Stmt body;
  final bool doWhile;
  const WhileStmt(this.condition, this.body, this.doWhile, super.line, super.column);
}

class ForStmt extends Stmt {
  final Stmt? init;
  final Expr? condition;
  final List<Expr> updates;
  final Stmt body;
  const ForStmt(this.init, this.condition, this.updates, this.body, super.line, super.column);
}

class ForInStmt extends Stmt {
  final String name;
  final Expr iterable;
  final Stmt body;
  const ForInStmt(this.name, this.iterable, this.body, super.line, super.column);
}

class BreakStmt extends Stmt {
  const BreakStmt(super.line, super.column);
}

class ContinueStmt extends Stmt {
  const ContinueStmt(super.line, super.column);
}

class ReturnStmt extends Stmt {
  final Expr? value;
  const ReturnStmt(this.value, super.line, super.column);
}

class FunctionStmt extends Stmt {
  final FunctionDecl function;
  const FunctionStmt(this.function, super.line, super.column);
}

// ---------------------------------------------------------------------------
// Declarations

class Param {
  final String name;
  final Expr? defaultValue;

  /// Declared inside `[...]` or `{...}`: may be left out by the caller.
  final bool optional;
  final bool named;
  const Param(this.name, {this.defaultValue, this.optional = false, this.named = false});
}

class FunctionDecl {
  final String name; // '' for lambdas
  final List<Param> params;
  final List<Stmt> body; // an arrow body is a single ReturnStmt
  final int line, column;
  const FunctionDecl(this.name, this.params, this.body, this.line, this.column);

  int get requiredCount => params.where((p) => !p.optional && !p.named).length;
  int get positionalCount => params.where((p) => !p.named).length;
}

/// A top-level `var` in a script: one per entity, editable in the Inspector
/// when initialised with a plain number, string or bool.
class FieldDecl {
  final String name;
  final Expr? init;
  final bool isFinal;
  final String? typeName;
  final String doc;
  final int line, column;
  const FieldDecl(this.name, this.init, this.isFinal, this.typeName, this.doc, this.line, this.column);

  /// The literal default value, when the field is Inspector-editable.
  Object? get literalDefault {
    final i = init;
    if (i is LiteralExpr && (i.value is num || i.value is bool || i.value is String)) return i.value;
    if (i is InterpolationExpr && i.parts.every((p) => p is String)) return i.parts.join();
    if (i is UnaryExpr && i.op == '-' && i.operand is LiteralExpr && (i.operand as LiteralExpr).value is num) {
      return -((i.operand as LiteralExpr).value as num);
    }
    return null;
  }

  bool get exposed => !isFinal && !name.startsWith('_') && literalDefault != null;
}

class Program {
  final String file;
  final List<FieldDecl> fields;
  final Map<String, FunctionDecl> functions;
  const Program(this.file, this.fields, this.functions);
}

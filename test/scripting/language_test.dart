import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/scripting/interpreter.dart';
import 'package:ember_engine/scripting/lexer.dart';
import 'package:ember_engine/scripting/parser.dart';

/// Runs `main()` of [source] and returns its result (and what it printed).
(Object?, List<String>) run(String source, {String entry = 'main', List<Object?> args = const []}) {
  final program = Parser.parseProgram(source, file: 'test.ember');
  final out = <String>[];
  final interp = Interpreter()..onPrint = out.add;
  final instance = ScriptInstance(program);
  Interpreter.globals['print'] = NativeFunction('print', (a, _) {
    out.add(a.map(Interpreter.stringify).join(' '));
    return null;
  });
  interp.initialize(instance);
  return (interp.callIfDefined(instance, entry, args), out);
}

Object? eval(String body) => run('main() { $body }').$1;

Matcher throwsScript(String containing, {int? line}) => throwsA(isA<ScriptError>()
    .having((e) => e.message, 'message', contains(containing))
    .having((e) => line == null || e.line == line, 'line $line', isTrue));

void main() {
  group('values and operators', () {
    test('arithmetic follows Dart', () {
      expect(eval('return 1 + 2 * 3;'), 7);
      expect(eval('return 7 / 2;'), 3.5);
      expect(eval('return 7 ~/ 2;'), 3);
      expect(eval('return -7 % 3;'), 2);
      expect(eval('return (1 + 2) * 3;'), 9);
      expect(eval('return 2 > 1 && !(3 < 2) || false;'), true);
      expect(eval('return null ?? 5;'), 5);
      expect(eval('return 1 == 1.0;'), true);
      expect(eval('return 0xFF;'), 255);
      expect(eval('return 1.5e2;'), 150.0);
    });

    test('strings, interpolation and methods', () {
      expect(eval(r"var n = 'Ember'; var hp = 3; return 'Hi $n, ${hp * 2} hp';"), 'Hi Ember, 6 hp');
      expect(eval("return 'a' + 1;"), 'a1');
      expect(eval("return 'abc'.toUpperCase().length;"), 3);
      expect(eval("return 'a,b,c'.split(',').join('-');"), 'a-b-c');
      expect(eval("return '7'.padLeft(3, '0');"), '007');
      expect(eval(r"return 'price: \$5';"), r'price: $5');
      expect(eval("return 'ab' 'cd';"), 'abcd');
      expect(eval("return 2.5.toStringAsFixed(2);"), '2.50');
      expect(eval("return 10.0.toString();"), '10.0');
    });

    test('lists and maps', () {
      expect(eval('var l = [3, 1, 2]; l.sort(); l.add(9); return l;'), [1, 2, 3, 9]);
      expect(eval('return [1, 2, 3].map((x) => x * 2).where((x) => x > 2);'), [4, 6]);
      expect(eval('var m = {"a": 1}; m["b"] = 2; return m.keys;'), ['a', 'b']);
      expect(eval('return [1, 2, 3].fold(0, (s, x) => s + x);'), 6);
      expect(eval('var l = [1, 2]; l[0] += 5; return l[0];'), 6);
      expect(eval('return [5, 6].firstWhere((x) => x > 9, orElse: () => -1);'), -1);
    });
  });

  group('control flow', () {
    test('if / else, loops, break and continue', () {
      expect(eval('var s = 0; for (var i = 0; i < 10; i++) { if (i == 5) break; if (i.isOdd) continue; s += i; } return s;'), 6);
      expect(eval('var s = 0; for (var x in [1, 2, 3]) s += x; return s;'), 6);
      expect(eval('var i = 0; while (i < 4) i++; return i;'), 4);
      expect(eval('var i = 0; do { i += 3; } while (i < 5); return i;'), 6);
      expect(eval('var k = ""; for (final key in {"a": 1, "b": 2}) k += key; return k;'), 'ab');
      expect(eval('var x = 3; if (x > 5) { return "big"; } else if (x > 2) { return "mid"; } else { return "small"; }'), 'mid');
      expect(eval('return 3 > 2 ? "yes" : "no";'), 'yes');
    });

    test('typed declarations are accepted and ignored', () {
      expect(eval('int a = 2; double b = 1.5; String? c; List<int> d = [1]; return a + b + d.length;'), 4.5);
      expect(run('int twice(int x) => x * 2; main() => twice(21);').$1, 42);
      expect(run('void main() { final Map<String, int> m = {"a": 1}; print(m); }').$2, ['{a: 1}']);
    });
  });

  group('functions and state', () {
    test('top-level variables keep state between calls; functions, closures, recursion', () {
      const src = '''
        var count = 0;
        var names = [];
        int fib(n) => n < 2 ? n : fib(n - 1) + fib(n - 2);
        makeCounter() { var c = 0; return () => ++c; }
        tick(label, [times = 1]) { count += times; names.add(label); }
        greet({name = "you", punct = "!"}) => "hi \$name\$punct";
        main() {
          tick("a");
          tick("b", 2);
          final next = makeCounter();
          next(); next();
          return [count, names, fib(10), next(), greet(name: "Ember")];
        }
      ''';
      expect(run(src).$1, [3, ['a', 'b'], 55, 3, 'hi Ember!']);
    });

    test('callbacks receive only the arguments they declare', () {
      expect(run('onUpdate() => "ok";', entry: 'onUpdate', args: [0.016]).$1, 'ok');
      expect(run('onUpdate(dt) => dt;', entry: 'onUpdate', args: [0.5, 'extra']).$1, 0.5);
    });
  });

  group('errors point at the problem', () {
    test('syntax errors', () {
      expect(() => Parser.parseProgram('main() {\n  var x = 1\n  x++;\n}'), throwsScript("Missing ';'", line: 2));
      expect(() => Parser.parseProgram('main() {\n  if (true) {\n'), throwsScript("Missing '}'"));
      expect(() => Parser.parseProgram('print("hi");'), throwsScript('Only variables'));
      expect(() => Parser.parseProgram("main() { var s = 'oops; }"), throwsScript('Unclosed string'));
      expect(() => Parser.parseProgram('var a = 1;\nvar a = 2;'), throwsScript('declared twice', line: 2));
    });

    test('runtime errors', () {
      expect(() => eval('return missingThing;'), throwsScript('Unknown name "missingThing"'));
      expect(() => run('var speed = 1;\nmain() {\n  return sped;\n}'), throwsScript('did you mean "speed"', line: 3));
      expect(() => eval('final a = 1; a = 2;'), throwsScript('is final'));
      expect(() => eval('return [1][5];'), throwsScript('outside the list'));
      expect(() => eval('return 1 / 0;'), throwsScript('Division by zero'));
      expect(() => eval('if (3) {}'), throwsScript('true or false'));
      expect(() => eval('var x; return x.length;'), throwsScript('of null'));
      expect(() => eval('return "a".nope;'), throwsScript('has no "nope"'));
      expect(() => run('f(a) => a; main() => f();'), throwsScript('expects 1 argument, got 0'));
      expect(() => eval('undeclared = 3;'), throwsScript('declare it first'));
    });

    test('endless loops and runaway recursion are stopped', () {
      Interpreter.budgetPerCall = 100000;
      addTearDown(() => Interpreter.budgetPerCall = 3000000);
      expect(() => eval('while (true) {}'), throwsScript('endless loop'));
      expect(() => run('f() => f(); main() => f();'), throwsScript('Too many nested calls'));
    });
  });
}

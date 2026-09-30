import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/entity.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/game_script.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/core/transform2d.dart';
import 'package:ember_engine/editor/ember_editor_app.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/editor/script/code_editor.dart';
import 'package:ember_engine/editor/script/script_workspace.dart';
import 'package:ember_engine/scripting/parser.dart';
import 'package:ember_engine/scripting/script_library.dart';
import 'package:ember_engine/scripting/templates.dart';

EmberEngine get engine => EmberEngine.instance;

Future<void> pumpWorkspace(WidgetTester tester, EmberProject project) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: ScriptWorkspace(engine: engine, project: project)),
  ));
  await tester.pump();
}

ScriptWorkspaceState workspace(WidgetTester tester) => tester.state<ScriptWorkspaceState>(find.byType(ScriptWorkspace));
TextField codeField(WidgetTester tester) => tester.widget<TextField>(find.byKey(const ValueKey('code-editor-field')));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerAllSubsystems();
    engine.stop();
    engine.preserveSceneOnModeSwitch = false;
    engine.setMode(EngineMode.twoD);
    EmberScripts.instance.loadAll({});
  });

  test('every starter template compiles', () {
    for (final t in scriptTemplates) {
      expect(() => Parser.parseProgram(t.source, file: '${t.id}.ember'), returnsNormally, reason: t.title);
    }
  });

  testWidgets('syntax highlighting colours keywords, strings, comments, API and events', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final c = EmberCodeController(text: '// hi\nvar s = "text";\nvoid onUpdate(dt) { playSound("coin"); self.x = 3; }');
    final span = c.buildTextSpan(context: tester.element(find.byType(SizedBox)), withComposing: false);
    Color? colorOf(String token) =>
        (span.children!.firstWhere((s) => (s as TextSpan).text == token) as TextSpan).style?.color;
    expect(colorOf('// hi'), CodeColors.comment);
    expect(colorOf('var'), CodeColors.keyword);
    expect(colorOf('"text"'), CodeColors.string);
    expect(colorOf('onUpdate'), CodeColors.callback);
    expect(colorOf('playSound'), CodeColors.api);
    expect(colorOf('self'), CodeColors.api);
    expect(colorOf('3'), CodeColors.number);
  });

  test('autocomplete: members after a dot, API, own variables and event snippets', () {
    List<String> labels(String text, [int? caret]) =>
        suggestionsAt(text, caret ?? text.length).$2.map((s) => s.label.split('(').first).toList();
    expect(labels('self.hea'), contains('health'));
    expect(labels('Input.'), containsAll(['key', 'pressed', 'move', 'axis']));
    expect(labels('Input.pr').first, 'pressed', reason: 'prefix matches rank before substring matches');
    expect(labels('var jumpPower = 3;\nvoid onUpdate(dt) { jum'), contains('jumpPower'));
    expect(labels('pla'), containsAll(['playSound', 'playMusic']));
    expect(labels('onUp'), contains('void onUpdate'));
    expect(labels('var x = "pla'), isEmpty, reason: 'not inside strings');
    expect(labels('// pla'), isEmpty, reason: 'not inside comments');
    final (len, list) = suggestionsAt('onUp', 4);
    expect(len, 4);
    expect(list.firstWhere((s) => s.label.contains('onUpdate')).insert, contains('void onUpdate(dt) {'));
  });

  testWidgets('create a script from a template, see live errors, fix them, and attach it', (tester) async {
    final project = EmberProject(id: 'p', name: 'Scripts');
    final scene = EmberScene()..addEntity(EmberEntity(name: 'Hero')..addComponent(Transform2DComponent(position: Vector2.zero())));
    engine.loadScene(scene);
    await pumpWorkspace(tester, project);
    expect(find.text('New Script'), findsWidgets, reason: 'empty state offers to create one');

    workspace(tester).createScript('Player Movement', scriptTemplates.firstWhere((t) => t.id == 'topdown'));
    await tester.pump();
    expect(project.scripts.keys, ['player_movement.ember']);
    expect(find.text('player_movement.ember'), findsWidgets);
    expect(EmberScripts.instance.program('player_movement.ember'), isNotNull);

    // Break it: the status bar shows the line and the program is not replaced
    await tester.enterText(find.byKey(const ValueKey('code-editor-field')), 'void onUpdate(dt) {\n  var x = ;\n}');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Line 2:'), findsOneWidget);
    expect(EmberScripts.instance.program('player_movement.ember')!.fields, isNotEmpty, reason: 'old code kept');

    // Fix it: goes live
    await tester.enterText(find.byKey(const ValueKey('code-editor-field')), 'var speed = 5;\nvoid onUpdate(dt) { self.x += speed; }');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No problems'), findsOneWidget);
    expect(EmberScripts.instance.program('player_movement.ember')!.fields.single.name, 'speed');

    // Attach to the selected entity, then Play runs it
    final hero = engine.activeScene.findByName('Hero')!;
    engine.selectEntity(hero);
    await tester.tap(find.byKey(const ValueKey('attach-script')));
    await tester.pump();
    expect(hero.getComponent<ScriptComponent>()!.scriptName, 'player_movement.ember');
    engine.step();
    engine.step();
    expect(hero.getComponent<Transform2DComponent>()!.position.x, greaterThan(0));
    engine.stop();
  });

  testWidgets('editor keys: Tab indents, Enter keeps indentation, Ctrl+/ comments', (tester) async {
    final project = EmberProject(id: 'p', name: 'Keys')..scripts['a.ember'] = 'void onStart() {';
    EmberScripts.instance.loadAll(project.scripts);
    await pumpWorkspace(tester, project);
    await tester.tap(find.byKey(const ValueKey('code-editor-field')));
    await tester.pump();
    final c = codeField(tester).controller!;
    c.selection = TextSelection.collapsed(offset: c.text.length);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.text, 'void onStart() {\n  ');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, 'void onStart() {\n    ');
    c.selection = const TextSelection.collapsed(offset: 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.text.startsWith('// void onStart()'), isTrue);
  });

  testWidgets('full editor: Ctrl+2 opens the Script workspace; typing never triggers editor shortcuts', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final project = TemplateCatalog.getByType(ProjectTemplateType.platformer2d).createProject(name: 'Script Test');
    project.scripts['spin.ember'] = 'var turns = 0;\nvoid onUpdate(dt) { turns++; }';
    await tester.pumpWidget(EmberEditorApp(initialProject: project, startInLauncher: false));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byType(ScriptWorkspace), findsOneWidget, reason: 'Ctrl+2 works even with the 2D viewport on screen');
    final ws = workspace(tester);
    ws.openFile('spin.ember');
    await tester.pump();

    // Typing "3" and Tab in the code must not switch to 3D or zen mode
    await tester.tap(find.byKey(const ValueKey('code-editor-field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(engine.mode, EngineMode.twoD);

    // Back to the scene: attach via the Inspector's script picker, then "Edit script" jumps back
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final e = EmberEntity(name: 'Spinner')
      ..addComponent(Transform2DComponent())
      ..addComponent(ScriptComponent(scriptName: 'spin.ember'));
    engine.activeScene.addEntity(e);
    engine.selectEntity(e);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Script · spin.ember'), findsOneWidget);
    expect(find.text('Turns'), findsWidgets, reason: 'script variable in the Inspector');
    await tester.tap(find.byKey(const ValueKey('edit-script')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ScriptCodeEditor).hitTestable(), findsOneWidget);
  });
}

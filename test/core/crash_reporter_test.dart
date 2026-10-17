import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/crash_reporter.dart';
import 'package:ember_engine/core/engine_loop.dart';
import 'package:ember_engine/core/event_bus.dart';
import 'package:ember_engine/core/version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('errors and engine warnings go to a dated log file; uncaught errors are handled', () async {
    final previousOnError = FlutterError.onError;
    final previousBuilder = ErrorWidget.builder;
    final previousPlatform = PlatformDispatcher.instance.onError;
    final dir = await Directory.systemTemp.createTemp('ember_logs');
    addTearDown(() async {
      FlutterError.onError = previousOnError;
      ErrorWidget.builder = previousBuilder;
      PlatformDispatcher.instance.onError = previousPlatform;
      await CrashReporter.close();
      await dir.delete(recursive: true);
    });

    await CrashReporter.install(appName: 'test', logDir: dir);
    expect(PlatformDispatcher.instance.onError!(StateError('async boom'), StackTrace.current), isTrue,
        reason: 'reported as handled, so the app keeps running');
    FlutterError.onError!(FlutterErrorDetails(exception: Exception('panel boom'), stack: StackTrace.current));
    EmberEngine.instance.log('Missing image hero.png', severity: LogSeverity.warning, source: 'Assets');
    EmberEngine.instance.log('Just info', source: 'Assets');
    await Future<void>.delayed(Duration.zero); // log events are delivered asynchronously
    await CrashReporter.flush();

    final log = await CrashReporter.logFileFor(DateTime.now()).readAsString();
    expect(log, contains(EmberVersion.displayName));
    expect(log, contains('async boom'));
    expect(log, contains('panel boom'));
    expect(log, contains('Missing image hero.png'));
    expect(log, isNot(contains('Just info')), reason: 'only warnings and errors are logged');

    final report = CrashReporter.problemReport();
    expect(report, contains(EmberVersion.displayName));
    expect(report, contains('panel boom'));
    expect(report, contains(dir.path));
  });

  testWidgets('a widget that fails to build shows a calm message instead of a red screen', (tester) async {
    await tester.pumpWidget(MaterialApp(home: CrashReporter.errorWidget(FlutterErrorDetails(exception: Exception('inspector exploded')))));
    expect(find.text('Something went wrong here'), findsOneWidget);
    expect(find.textContaining('inspector exploded'), findsOneWidget);
    expect(find.textContaining('Your work is safe'), findsOneWidget);
  });

  test('the version constant matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(line, EmberVersion.full);
  });

  test('the publisher in the Windows and macOS app info matches the constant', () {
    final rc = File('windows/runner/Runner.rc').readAsStringSync();
    expect(rc, contains('"CompanyName", "${EmberVersion.publisher}"'));
    expect(rc, contains('Copyright (C) 2026 ${EmberVersion.publisher}.'));
    expect(File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync(), contains(EmberVersion.copyright));
  });
}

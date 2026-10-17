import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/core/scene.dart';
import 'package:ember_engine/editor/doctor.dart';
import 'package:ember_engine/editor/hub/android_signing.dart';
import 'package:ember_engine/editor/hub/game_exporter.dart';
import 'package:ember_engine/editor/hub/game_icons.dart';
import 'package:ember_engine/editor/hub/project_manifest.dart';
import 'package:ember_engine/editor/hub/project_package.dart';
import 'package:ember_engine/editor/hub/project_storage.dart';
import 'package:ember_engine/editor/hub/template_manifest.dart';
import 'package:ember_engine/editor/hub/windows_branding.dart';
import 'package:ember_engine/editor/hub/windows_msix.dart';
import 'package:ember_engine/editor/hub/zip_writer.dart';
import 'package:ember_engine/editor/panels/export_dialog.dart';
import 'package:ember_engine/editor/panels/project_settings_dialog.dart';
import 'package:ember_engine/editor/project_session.dart';

/// Width and height from a PNG header.
(int, int) pngSize(Uint8List png) {
  final d = ByteData.sublistView(png);
  return (d.getUint32(16), d.getUint32(20));
}

/// The raw bytes of a resource inside an executable (Windows).
Uint8List? readResource(File exe, int type, int id) {
  final k32 = DynamicLibrary.open('kernel32.dll');
  final load = k32.lookupFunction<IntPtr Function(Pointer<Utf16>, IntPtr, Uint32), int Function(Pointer<Utf16>, int, int)>('LoadLibraryExW');
  final find = k32.lookupFunction<IntPtr Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>), int Function(int, Pointer<Utf16>, Pointer<Utf16>)>('FindResourceW');
  final size = k32.lookupFunction<Uint32 Function(IntPtr, IntPtr), int Function(int, int)>('SizeofResource');
  final loadRes = k32.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('LoadResource');
  final lock = k32.lookupFunction<Pointer<Uint8> Function(IntPtr), Pointer<Uint8> Function(int)>('LockResource');
  final free = k32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('FreeLibrary');
  final path = exe.absolute.path.toNativeUtf16();
  final module = load(path, 0, 0x2); // LOAD_LIBRARY_AS_DATAFILE
  calloc.free(path);
  if (module == 0) return null;
  try {
    final res = find(module, Pointer.fromAddress(id), Pointer.fromAddress(type));
    if (res == 0) return null;
    final n = size(module, res);
    return Uint8List.fromList(lock(loadRes(module, res)).asTypedList(n));
  } finally {
    free(module);
  }
}

/// A distinctive test icon: a red square with a white circle, 300x300.
Future<Uint8List> testIconPng(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 300), Paint()..color = const Color(0xFFE11D48));
    canvas.drawCircle(const Offset(150, 150), 90, Paint()..color = const Color(0xFFFFFFFF));
    final image = await recorder.endRecording().toImage(300, 300);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    registerAllSubsystems();
    tmp = await Directory.systemTemp.createTemp('ember_publish_test');
  });
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  EmberProject siege(String path) => TemplateCatalog.getByType(ProjectTemplateType.siege).createProject(name: 'Siege Test', author: 'Ada')
    ..path = path
    ..version = '2.1.0'
    ..game = GameSettings(displayName: 'Frost Breaker', publisher: 'Ember Studio', buildNumber: 7, appId: 'com.emberstudio.frostbreaker');

  test('game settings are saved with the project, in packages, and count as unsaved changes', () async {
    final project = siege('${tmp.path}${Platform.pathSeparator}p');
    await ProjectStorage.save(project);
    final loaded = await ProjectStorage.load(project.path);
    expect(loaded.gameTitle, 'Frost Breaker');
    expect(loaded.publisherName, 'Ember Studio');
    expect(loaded.game.buildNumber, 7);
    expect(loaded.game.appId, 'com.emberstudio.frostbreaker');
    expect(loaded.version, '2.1.0');
    final packaged = ProjectPackageManager.importFromPackageString(ProjectPackageManager.exportToPackageString(project));
    expect(packaged.gameTitle, 'Frost Breaker');

    final before = jsonEncode(ProjectSession.contentOf(project));
    project.game.publisher = 'Someone Else';
    expect(jsonEncode(ProjectSession.contentOf(project)), isNot(before), reason: 'editing settings shows the unsaved dot');

    // Empty settings fall back to the project's own name and author
    final plain = EmberProject(id: 'x', name: 'Plain Game', author: 'Bo');
    expect(plain.gameTitle, 'Plain Game');
    expect(plain.publisherName, 'Bo');
  });

  test('version and app id rules', () {
    for (final ok in ['1', '1.0', '1.0.0', '12.3.456']) {
      expect(GameSettings.isValidVersion(ok), isTrue, reason: ok);
    }
    for (final bad in ['', 'v1', '1.0.0.0', '1..0', '1.0-beta']) {
      expect(GameSettings.isValidVersion(bad), isFalse, reason: bad);
    }
    expect(GameSettings.isValidAppId('com.studio.game'), isTrue);
    expect(GameSettings.isValidAppId('com.studio.my_game2'), isTrue);
    for (final bad in ['game', 'com.1studio.game', 'com..game', 'com.studio.game!', 'com studio.game']) {
      expect(GameSettings.isValidAppId(bad), isFalse, reason: bad);
    }
    expect(GameExporter.androidVersionName(EmberProject(id: 'x', name: 'g', version: '2.1')), '2.1.0');
  });

  testWidgets('icons are rendered at every size and packed into a Windows .ico', (tester) async {
    final source = await testIconPng(tester);
    final icons = (await tester.runAsync(() => GameIcons.render(source)))!;
    for (final s in GameIconSet.allSizes) {
      expect(pngSize(icons[s]), (s, s), reason: '$s px');
    }
    final ico = icons.toIco();
    final images = WindowsBranding.parseIco(ico);
    expect(images.length, GameIconSet.windowsSizes.length);
    expect(images.last.width, 0, reason: '256 px is stored as 0 in .ico entries');
    expect(pngSize(images.first.data), (16, 16));

    final check = (await tester.runAsync(() => GameIcons.inspect(source)))!;
    expect(check.warning, isNull, reason: '300x300 square is fine');
    expect(const IconCheck(512, 300).warning, contains('square'));
    expect(const IconCheck(64, 64).warning, contains('256'));
  });

  test('zip files hold every file with the right paths and open with Windows/tar', () async {
    final src = Directory('${tmp.path}/src');
    await File('${src.path}/index.html').create(recursive: true);
    await File('${src.path}/index.html').writeAsString('<html>hi</html>' * 50);
    await File('${src.path}/assets/a b/über.png').create(recursive: true);
    await File('${src.path}/assets/a b/über.png').writeAsBytes(List<int>.generate(5000, (i) => i * 7 % 256));
    await File('${src.path}/play-locally.ps1').writeAsString('# helper');
    final zip = await ZipWriter.zipFolder(src, File('${tmp.path}/out.zip'), exclude: {'play-locally.ps1'});

    final out = await Directory('${tmp.path}/unzipped').create();
    final r = await Process.run('tar', ['-xf', zip.path, '-C', out.path]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(await File('${out.path}/index.html').readAsString(), '<html>hi</html>' * 50);
    expect(await File('${out.path}/assets/a b/über.png').readAsBytes(), List<int>.generate(5000, (i) => i * 7 % 256));
    expect(File('${out.path}/play-locally.ps1').existsSync(), isFalse, reason: 'excluded');
    expect(ZipWriter.crc32(utf8.encode('123456789')), 0xCBF43926, reason: 'standard CRC-32 check value');
  }, skip: Process.runSync('tar', ['--version']).exitCode != 0 ? 'tar not available' : false);

  testWidgets('a Windows export carries the game name, publisher, version and icon in its .exe', (tester) async {
    final runtime = GameExporter.findPlayerRuntime()!;
    final project = siege('${tmp.path}${Platform.pathSeparator}p');
    final png = await testIconPng(tester);
    final icons = (await tester.runAsync(() => GameIcons.render(png)))!;
    final exe = (await tester.runAsync(() => GameExporter.export(project: project, runtime: runtime, outputParent: '${tmp.path}/out', icons: icons)))!;
    expect(exe, endsWith('Frost Breaker.exe'));
    expect(WindowsBranding.readVersionString(File(exe), 'ProductName'), 'Frost Breaker');
    expect(WindowsBranding.readVersionString(File(exe), 'CompanyName'), 'Ember Studio');
    expect(WindowsBranding.readVersionString(File(exe), 'FileVersion'), '2.1.0.7');
    expect(WindowsBranding.readVersionString(File(exe), 'OriginalFilename'), 'Frost Breaker.exe');
    final group = readResource(File(exe), 14, WindowsBranding.iconGroupId);
    expect(group, WindowsBranding.groupIconDirectory(WindowsBranding.parseIco(icons.toIco())), reason: 'the icon group is the game icon');
    final first = readResource(File(exe), 3, 1)!;
    expect(pngSize(first), (16, 16), reason: 'icon images are the game icon PNGs');
    for (final dll in ['msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll']) {
      expect(File('${File(exe).parent.path}/$dll').existsSync(), isTrue, reason: '$dll bundled');
    }

    final zip = (await tester.runAsync(() => GameExporter.zipGameFolder(File(exe).parent.path)))!;
    final listing = Process.runSync('tar', ['-tf', zip]).stdout as String;
    expect(listing, contains('Frost Breaker/Frost Breaker.exe'));
    expect(listing, contains('Frost Breaker/data/app.so'));
  }, skip: !Platform.isWindows || GameExporter.findPlayerRuntime() == null); // needs Windows and the built player runtime

  test('the installer script installs per user with shortcuts, from the exported folder', () {
    final project = siege('x');
    final iss = GameExporter.installerScript(project, r'C:\Exports\Frost Breaker', iconPath: r'C:\Exports\Frost Breaker Setup.ico');
    expect(iss, contains('AppName=Frost Breaker'));
    expect(iss, contains('AppVersion=2.1.0'));
    expect(iss, contains('AppPublisher=Ember Studio'));
    expect(iss, contains('AppId=com_emberstudio_frostbreaker'));
    expect(iss, contains('PrivilegesRequired=lowest'));
    expect(iss, contains(r'Source: "C:\Exports\Frost Breaker\*"'));
    expect(iss, contains(r'Filename: "{app}\Frost Breaker.exe"'));
    expect(iss, contains(r'SetupIconFile=C:\Exports\Frost Breaker Setup.ico'));
  });

  testWidgets('a web export uses the game name and icon, and the itch.io zip has index.html at its root', (tester) async {
    // Synchronous file calls: async I/O never completes under testWidgets' fake clock
    final runtime = Directory('${tmp.path}/web_runtime')..createSync();
    File('${runtime.path}/index.html')
        .writeAsStringSync('<html><head><base href="/"><meta name="description" content="Made with Ember Engine"><title>Ember Engine</title></head></html>');
    File('${runtime.path}/favicon.png').writeAsBytesSync([1, 2, 3]);
    File('${runtime.path}/manifest.json').writeAsStringSync('{"name": "Ember Engine"}');
    final project = siege('${tmp.path}${Platform.pathSeparator}p');
    final png = await testIconPng(tester);
    final icons = (await tester.runAsync(() => GameIcons.render(png)))!;
    final folder = (await tester.runAsync(() => GameExporter.exportWeb(project: project, runtime: runtime, outputParent: '${tmp.path}/out', icons: icons)))!;
    expect(folder, endsWith('Frost Breaker-web'));
    final index = File('$folder/index.html').readAsStringSync();
    expect(index, contains('<title>Frost Breaker</title>'));
    expect(index, contains('Frost Breaker (made with Ember Engine)'));
    expect(pngSize(File('$folder/favicon.png').readAsBytesSync()), (32, 32));
    expect(pngSize(File('$folder/icons/Icon-512.png').readAsBytesSync()), (512, 512));

    final zip = (await tester.runAsync(() => GameExporter.zipWebForItch(folder)))!;
    final listing = (Process.runSync('tar', ['-tf', zip]).stdout as String).split(RegExp(r'\r?\n'));
    expect(listing, contains('index.html'), reason: 'itch.io needs index.html at the top of the zip');
    expect(listing, isNot(contains('play-locally.ps1')));
  });

  test('Android builds get the game id, name and (when chosen) the signing key', () {
    final project = siege('x');
    const key = AndroidSigningKey(r'C:\Keys\frost.p12', 'upload');
    final env = GameExporter.androidEnvironment(project, key: key, password: 'secret!');
    expect(env['EMBER_APP_ID'], 'com.emberstudio.frostbreaker');
    expect(env['EMBER_APP_NAME'], 'Frost Breaker');
    expect(env['EMBER_KEYSTORE'], r'C:\Keys\frost.p12');
    expect(env['EMBER_KEY_ALIAS'], 'upload');
    expect(env['EMBER_KEYSTORE_PASSWORD'], 'secret!');
    final debug = GameExporter.androidEnvironment(project..game.appId = '');
    expect(debug.containsKey('EMBER_KEYSTORE'), isFalse, reason: 'no key: debug-signed');
    expect(debug['EMBER_APP_ID'], 'com.embergames.frost_breaker', reason: 'made from the game name');
  });

  test('creating an upload key with keytool; checking its password; remembering which key a project uses', () async {
    AndroidSigning.settingsFileOverride = File('${tmp.path}/signing.json');
    addTearDown(() => AndroidSigning.settingsFileOverride = null);
    final key = await AndroidSigning.createKey(
        keystorePath: '${tmp.path}${Platform.pathSeparator}keys${Platform.pathSeparator}frost.p12', alias: 'upload', password: 'correct horse', name: 'Ember Studio', countryCode: 'ng');
    expect(File(key.keystorePath).existsSync(), isTrue);
    expect(await AndroidSigning.verify(key, 'correct horse'), isTrue);
    expect(await AndroidSigning.verify(key, 'wrong password'), isFalse);
    expect(await AndroidSigning.fingerprint(key, 'correct horse'), matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
    await expectLater(
        AndroidSigning.createKey(keystorePath: key.keystorePath, alias: 'upload', password: 'another pw', name: 'X'), throwsStateError,
        reason: 'never overwrites an existing key');

    await AndroidSigning.setKeyForProject('proj_1', key);
    expect((await AndroidSigning.keyForProject('proj_1'))!.keystorePath, key.keystorePath);
    expect(await AndroidSigning.keyForProject('proj_2'), isNull);
  }, skip: AndroidSigning.findKeytool() == null ? 'keytool not installed' : false);

  testWidgets('Project Settings validates the version and app id and saves into the project', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final project = EmberProject(id: 'p1', name: 'My Game', author: 'Ada');
    var saved = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (ctx) => TextButton(onPressed: () async => saved = await ProjectSettingsDialog.show(ctx, project), child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200))); // icon preview loads
    await tester.pump();

    await tester.enterText(find.byKey(const ValueKey('settings-name')), 'Sky Pirates');
    await tester.enterText(find.byKey(const ValueKey('settings-version')), 'v2');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('settings-save'))).onPressed, isNull, reason: 'bad version');
    await tester.enterText(find.byKey(const ValueKey('settings-version')), '2.0.1');
    await tester.enterText(find.byKey(const ValueKey('settings-appid')), 'not an id');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('settings-save'))).onPressed, isNull, reason: 'bad app id');
    await tester.enterText(find.byKey(const ValueKey('settings-appid')), 'com.ada.skypirates');
    await tester.enterText(find.byKey(const ValueKey('settings-build')), '12');
    await tester.enterText(find.byKey(const ValueKey('settings-publisher')), 'Ada Games');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-save')));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(project.gameTitle, 'Sky Pirates');
    expect(project.version, '2.0.1');
    expect(project.game.buildNumber, 12);
    expect(project.game.appId, 'com.ada.skypirates');
    expect(project.publisherName, 'Ada Games');
  });

  test('MSIX identity: package name, publisher and four-part version from Project Settings', () {
    final p = siege('');
    expect(WindowsMsix.identityName(p), 'com.emberstudio.frostbreaker');
    expect(WindowsMsix.publisher(p), 'CN=Ember Studio');
    expect(WindowsMsix.version(p), '2.1.0.0', reason: 'the Store needs four numbers ending in 0');
    expect(WindowsMsix.version(EmberProject(id: 'x', name: 'g', version: '3')), '3.0.0.0');
    expect(WindowsMsix.defaultIdentityName('com.ada.sky_pirates'), 'com.ada.sky-pirates', reason: 'MSIX names have no underscores');
    expect(WindowsMsix.defaultPublisher('Ada, "Games" Ltd', 'Sky'), 'CN=Ada Games Ltd');

    p.game
      ..msixName = 'AdaGames.FrostBreaker'
      ..msixPublisher = 'CN=1A2B3C4D-0000-1111-2222-333344445555';
    expect(WindowsMsix.identityName(p), 'AdaGames.FrostBreaker');
    expect(WindowsMsix.publisher(p), 'CN=1A2B3C4D-0000-1111-2222-333344445555');
    final back = GameSettings.fromJson(jsonDecode(jsonEncode(p.game.toJson())));
    expect((back.msixName, back.msixPublisher), ('AdaGames.FrostBreaker', 'CN=1A2B3C4D-0000-1111-2222-333344445555'));

    expect(GameSettings.isValidMsixName('AdaGames.FrostBreaker'), isTrue);
    for (final bad in ['ab', 'my game', 'game_1', 'game.']) {
      expect(GameSettings.isValidMsixName(bad), isFalse, reason: bad);
    }
    expect(GameSettings.isValidMsixPublisher('CN=My Studio'), isTrue);
    expect(GameSettings.isValidMsixPublisher('CN=My Studio, O=My Studio, C=NG'), isTrue);
    for (final bad in ['My Studio', 'CN=', 'cn=x']) {
      expect(GameSettings.isValidMsixPublisher(bad), isFalse, reason: bad);
    }

    final xml = WindowsMsix.manifest(p..game.displayName = 'Frost & Fire', executable: 'Frost Fire.exe');
    expect(xml, contains('<Identity Name="AdaGames.FrostBreaker" Version="2.1.0.0"'));
    expect(xml, contains('Publisher="CN=1A2B3C4D-0000-1111-2222-333344445555"'));
    expect(xml, contains('<DisplayName>Frost &amp; Fire</DisplayName>'), reason: 'names are XML-escaped');
    expect(xml, contains('Executable="Frost Fire.exe" EntryPoint="Windows.FullTrustApplication"'));
    expect(xml, contains('<rescap:Capability Name="runFullTrust" />'));
    expect(WindowsMsix.manifest(p, executable: 'a.exe', publisherOverride: 'CN=From Cert'), contains('Publisher="CN=From Cert"'));

    for (final scaled in [true, false]) {
      for (final size in WindowsMsix.imageFiles(scaled: scaled).values) {
        expect(GameIconSet.msixSizes, contains(size), reason: 'every MSIX image size is rendered');
      }
    }
  });

  testWidgets('an MSIX is packed from the exported game and signed with a (test) certificate', (tester) async {
    final png = await testIconPng(tester);
    await tester.runAsync(() async {
      final p = siege('');
      final icons = await GameIcons.render(png);
      final game = Directory('${tmp.path}\\game\\Frost Breaker')..createSync(recursive: true);
      File('${game.path}\\Frost Breaker.exe').writeAsBytesSync(List.filled(64, 0));
      File('${game.path}\\$emberGameFileName').writeAsStringSync('{}');

      final unsigned = await WindowsMsix.build(project: p, gameFolder: game.path, outputParent: '${tmp.path}\\store', icons: icons);
      expect(File(unsigned).existsSync(), isTrue);
      expect(unsigned, endsWith('Frost Breaker.msix'));

      final (cert, cer) = await WindowsMsix.createTestCertificate(pfxPath: '${tmp.path}\\keys\\test.pfx', password: 'cert pass 1', subject: 'CN=Ember Test Studio');
      expect(File(cer).existsSync(), isTrue);
      expect(await WindowsMsix.certificateSubject(cert), 'CN=Ember Test Studio');
      await expectLater(WindowsMsix.certificateSubject(MsixCertificate(cert.pfxPath, 'wrong')), throwsStateError);
      await expectLater(WindowsMsix.createTestCertificate(pfxPath: cert.pfxPath, password: 'x123456', subject: 'CN=X'), throwsStateError,
          reason: 'never replaces an existing certificate');

      final signed = await WindowsMsix.build(project: p, gameFolder: game.path, outputParent: '${tmp.path}\\signed', icons: icons, certificate: cert);
      final r = await Process.run('powershell.exe', ['-NoProfile', '-Command', '(Get-AuthenticodeSignature -LiteralPath \'$signed\').SignerCertificate.Subject']);
      expect('${r.stdout}'.trim(), 'CN=Ember Test Studio', reason: 'signed, and the package publisher follows the certificate');

      final left = await Process.run('powershell.exe', ['-NoProfile', '-Command', "@(Get-ChildItem Cert:\\CurrentUser\\My | Where-Object Subject -eq 'CN=Ember Test Studio').Count"]);
      expect('${left.stdout}'.trim(), '0', reason: 'the certificate is not left in the user\'s certificate store');
    });
  }, skip: WindowsMsix.findMakeAppx() == null, timeout: const Timeout(Duration(minutes: 3))); // needs the Windows SDK

  test('Doctor checks the game identity and icon', () async {
    Future<List<DiagnosticReportItem>> run(EmberProject p, {IconCheck? icon}) => ProjectDoctor.run(
          DoctorInput.fromContent(ProjectSession.contentOf(p)),
          checkExports: false,
          assetExists: (_) async => true,
          inspectIcon: (_) async => icon,
        );
    DiagnosticReportItem find(List<DiagnosticReportItem> items, String title) => items.firstWhere((i) => i.title == title);

    final p = siege('');
    var items = await run(p);
    expect(find(items, 'Game identity').status, HealthStatus.passed);
    expect(find(items, 'Game identity').details, allOf(contains('Frost Breaker'), contains('2.1.0'), contains('com.emberstudio.frostbreaker'), contains('Ember Studio')));
    expect(find(items, 'Game icon').status, HealthStatus.info, reason: 'no icon picked: the Ember icon is used');

    p.version = '2.1-beta';
    p.game
      ..appId = 'frostbreaker'
      ..iconPath = 'assets/icon/icon.png';
    items = await run(p, icon: const IconCheck(300, 200));
    final identity = find(items, 'Game identity');
    expect(identity.status, HealthStatus.failed);
    expect(identity.details, allOf(contains('2.1-beta'), contains('frostbreaker')));
    expect(find(items, 'Game icon').status, HealthStatus.warning);
    expect(find(items, 'Game icon').details, contains('square'));

    items = await run(p);
    expect(find(items, 'Game icon').status, HealthStatus.failed, reason: 'the picked icon file is missing');
    items = await run(p, icon: const IconCheck(512, 512));
    expect(find(items, 'Game icon').status, HealthStatus.passed);
  });

  testWidgets('the Windows export offers a game folder (.exe) or an MSIX package', (tester) async {
    final p = siege('');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExportGameDialog(prepareProject: () async => p, project: p))));
    await tester.pump();
    expect(find.text('Export for Windows'), findsOneWidget);
    expect(find.textContaining('Installer (Setup.exe)', findRichText: true), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('export-win-msix')));
    await tester.pump();
    expect(find.text('Build MSIX'), findsOneWidget);
    expect(find.textContaining('Installer (Setup.exe)', findRichText: true), findsNothing);
    if (WindowsMsix.findMakeAppx() != null) {
      expect(find.textContaining('Package com.emberstudio.frostbreaker · CN=Ember Studio · version 2.1.0.0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('export-msix-signed')));
      await tester.pump();
      expect(find.textContaining('Create a test certificate', findRichText: true), findsOneWidget);
    } else {
      expect(find.textContaining('MSIX needs the Windows SDK'), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('export-win-exe')));
    await tester.pump();
    expect(find.text('Export for Windows'), findsOneWidget);
  });
}

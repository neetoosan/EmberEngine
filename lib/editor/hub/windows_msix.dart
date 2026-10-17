import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'game_exporter.dart';
import 'game_icons.dart';
import 'project_manifest.dart';

/// A code-signing certificate (.pfx) and its password.
class MsixCertificate {
  final String pfxPath;
  final String password;
  const MsixCertificate(this.pfxPath, this.password);
}

/// Packs an exported Windows game as an MSIX: the format of the Microsoft
/// Store and of clean installs / uninstalls through Windows' own app list.
///
/// Uses the Windows SDK tools (MakeAppx, MakePri, SignTool). Store uploads
/// are left unsigned (the Store signs them); anything else needs a
/// certificate whose subject is the package's publisher.
class WindowsMsix {
  WindowsMsix._();

  static const _secure = FlutterSecureStorage();

  /// Test hook: where the "which certificate does each project use" file lives.
  static File? settingsFileOverride;

  // --- Windows SDK tools ---

  /// The newest Windows SDK `bin/<version>/x64` folder that has MakeAppx, or null.
  static Directory? findSdkBin() {
    if (!Platform.isWindows) return null;
    final env = Platform.environment;
    for (final base in [env['ProgramFiles(x86)'], env['ProgramFiles']]) {
      if (base == null) continue;
      final bin = Directory('$base\\Windows Kits\\10\\bin');
      if (!bin.existsSync()) continue;
      final versions = bin
          .listSync()
          .whereType<Directory>()
          .where((d) => File('${d.path}\\x64\\makeappx.exe').existsSync())
          .toList()
        ..sort((a, b) => _compareVersions(b.path.split('\\').last, a.path.split('\\').last));
      if (versions.isNotEmpty) return Directory('${versions.first.path}\\x64');
    }
    return null;
  }

  static int _compareVersions(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 4; i++) {
      final d = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  static String? _tool(String exe) {
    final bin = findSdkBin();
    if (bin == null) return null;
    final f = File('${bin.path}\\$exe');
    return f.existsSync() ? f.path : null;
  }

  static String? findMakeAppx() => _tool('makeappx.exe');
  static String? findMakePri() => _tool('makepri.exe');
  static String? findSignTool() => _tool('signtool.exe');

  // --- Identity ---

  /// Package name: Project Settings, else the Android-style app id.
  static String identityName(EmberProject project) => project.game.msixName.trim().isNotEmpty
      ? project.game.msixName.trim()
      : defaultIdentityName(project.game.appId.isNotEmpty ? project.game.appId : GameExporter.androidAppId(project.gameTitle));

  /// The package name made from an Android-style app id.
  static String defaultIdentityName(String appId) {
    final name = appId.replaceAll('_', '-');
    return name.length > 50 ? name.substring(0, 50) : name;
  }

  /// Publisher: Project Settings, else `CN=<publisher name>`.
  static String publisher(EmberProject project) => project.game.msixPublisher.trim().isNotEmpty
      ? project.game.msixPublisher.trim()
      : defaultPublisher(project.publisherName, project.gameTitle);

  /// `CN=<publisher name>`, without characters a certificate subject cannot hold.
  static String defaultPublisher(String publisherName, String gameTitle) {
    final name = publisherName.replaceAll(RegExp(r'[,=+<>#;"\\]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return 'CN=${name.isEmpty ? GameExporter.safeName(gameTitle) : name}';
  }

  /// MSIX versions have four numbers; the Store requires the last one to be 0.
  static String version(EmberProject project) {
    final parts = (GameSettings.isValidVersion(project.version) ? project.version : '1.0.0').split('.');
    while (parts.length < 3) {
      parts.add('0');
    }
    return [...parts.take(3), '0'].join('.');
  }

  static String _xml(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');

  /// The package's AppxManifest.xml.
  static String manifest(EmberProject project, {required String executable, String? publisherOverride}) {
    final title = _xml(project.gameTitle);
    final description = _xml(project.description.trim().isEmpty ? project.gameTitle : project.description.trim());
    return '''<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap rescap">
  <Identity Name="${_xml(identityName(project))}" Version="${version(project)}"
            Publisher="${_xml(publisherOverride ?? publisher(project))}" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$title</DisplayName>
    <PublisherDisplayName>${_xml(project.publisherName.trim().isEmpty ? project.gameTitle : project.publisherName.trim())}</PublisherDisplayName>
    <Logo>Images\\StoreLogo.png</Logo>
    <Description>$description</Description>
  </Properties>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="${_xml(executable)}" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="$title" Description="$description" BackgroundColor="transparent"
                          Square150x150Logo="Images\\Square150x150Logo.png" Square44x44Logo="Images\\Square44x44Logo.png">
        <uap:DefaultTile ShortName="${_xml(project.gameTitle.length > 40 ? project.gameTitle.substring(0, 40) : project.gameTitle)}" />
      </uap:VisualElements>
    </Application>
  </Applications>
</Package>
''';
  }

  /// Icon files in Images/ (name to pixel size). With MakePri, scaled and
  /// taskbar ("targetsize") variants are added so icons stay sharp.
  static Map<String, int> imageFiles({required bool scaled}) {
    if (!scaled) return {'StoreLogo.png': 50, 'Square44x44Logo.png': 44, 'Square150x150Logo.png': 150};
    return {
      'StoreLogo.scale-100.png': 50,
      'StoreLogo.scale-200.png': 100,
      'Square150x150Logo.scale-100.png': 150,
      'Square150x150Logo.scale-200.png': 300,
      'Square44x44Logo.scale-100.png': 44,
      'Square44x44Logo.scale-200.png': 88,
      for (final s in [16, 24, 32, 48, 256]) ...{
        'Square44x44Logo.targetsize-$s.png': s,
        'Square44x44Logo.targetsize-${s}_altform-unplated.png': s,
      },
    };
  }

  // --- Building ---

  /// Packs the exported game in [gameFolder] (from [GameExporter.export]) into
  /// `<outputParent>/<Game>.msix`, signed with [certificate] if given. Returns its path.
  static Future<String> build({
    required EmberProject project,
    required String gameFolder,
    required String outputParent,
    required GameIconSet icons,
    MsixCertificate? certificate,
    void Function(String line)? onLog,
  }) async {
    final makeAppx = findMakeAppx();
    if (makeAppx == null) throw StateError('MSIX needs the Windows SDK (MakeAppx.exe). Install it with Visual Studio or from developer.microsoft.com/windows/downloads/windows-sdk.');
    final makePri = findMakePri();
    final signTool = findSignTool();
    if (certificate != null && signTool == null) throw StateError('Signing needs SignTool.exe from the Windows SDK.');

    final safe = GameExporter.safeName(project.gameTitle);
    final exe = '$safe.exe';
    if (!File('$gameFolder\\$exe').existsSync()) throw StateError('The exported game has no $exe.');

    String? publisherOverride;
    if (certificate != null) {
      publisherOverride = await certificateSubject(certificate);
      if (project.game.msixPublisher.trim().isNotEmpty && project.game.msixPublisher.trim() != publisherOverride) {
        onLog?.call('Note: the certificate is for "$publisherOverride", so the package uses that publisher instead of "${project.game.msixPublisher}".');
      }
    }

    final work = await Directory.systemTemp.createTemp('ember_msix');
    try {
      final staging = Directory('${work.path}\\package');
      await _copy(Directory(gameFolder), staging);
      await File('${staging.path}\\AppxManifest.xml')
          .writeAsString(manifest(project, executable: exe, publisherOverride: publisherOverride), flush: true);
      final images = imageFiles(scaled: makePri != null);
      await Directory('${staging.path}\\Images').create();
      for (final e in images.entries) {
        await File('${staging.path}\\Images\\${e.key}').writeAsBytes(icons[e.value]);
      }
      if (makePri != null) {
        final config = '${work.path}\\priconfig.xml';
        await _run(makePri, ['createconfig', '/cf', config, '/dq', 'en-US', '/pv', '10.0.0', '/o'], onLog);
        await _run(makePri, ['new', '/pr', staging.path, '/cf', config, '/mn', '${staging.path}\\AppxManifest.xml', '/of', '${staging.path}\\resources.pri', '/o'], onLog);
      }
      await Directory(outputParent).create(recursive: true);
      final out = '$outputParent\\$safe.msix';
      await _run(makeAppx, ['pack', '/o', '/d', staging.path, '/p', out], onLog);
      onLog?.call('Packed $out (${identityName(project)} ${version(project)})');
      if (certificate != null) {
        await _run(signTool!, ['sign', '/fd', 'SHA256', '/f', certificate.pfxPath, '/p', certificate.password, out], onLog, hide: certificate.password);
        onLog?.call('Signed for $publisherOverride');
      } else {
        onLog?.call('Unsigned: upload it to Partner Center (the Microsoft Store signs it). To install it yourself, sign it with a certificate.');
      }
      return out;
    } finally {
      await work.delete(recursive: true);
    }
  }

  static Future<void> _copy(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is Directory) {
        await _copy(e, Directory('${to.path}\\$name'));
      } else if (e is File) {
        await e.copy('${to.path}\\$name');
      }
    }
  }

  static Future<void> _run(String exe, List<String> args, void Function(String line)? onLog, {String? hide}) async {
    final r = await Process.run(exe, args);
    final output = '${r.stdout}\n${r.stderr}'.trim();
    if (r.exitCode != 0) {
      final shown = hide == null ? output : output.replaceAll(hide, '***');
      throw StateError('${exe.split('\\').last} failed (exit ${r.exitCode}):\n${shown.length > 3000 ? shown.substring(shown.length - 3000) : shown}');
    }
  }

  // --- Certificates ---

  /// The subject (e.g. "CN=My Studio") of [certificate]; the package publisher must equal it.
  static Future<String> certificateSubject(MsixCertificate certificate) async {
    final r = await _powershell(
      r'$c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($env:EMBER_PFX, $env:EMBER_PFX_PASSWORD); $c.Subject',
      {'EMBER_PFX': certificate.pfxPath, 'EMBER_PFX_PASSWORD': certificate.password},
    );
    if (r.exitCode != 0 || '${r.stdout}'.trim().isEmpty) {
      throw StateError('Could not open the certificate ${certificate.pfxPath} (wrong password?)');
    }
    return '${r.stdout}'.trim();
  }

  /// Creates a self-signed code-signing certificate for testing an MSIX on
  /// your own PCs. Writes [pfxPath] (private, for signing) and a .cer next to
  /// it (public, which a PC must trust before it installs the package).
  static Future<(MsixCertificate, String)> createTestCertificate({
    required String pfxPath,
    required String password,
    required String subject,
  }) async {
    if (!GameSettings.isValidMsixPublisher(subject)) throw ArgumentError('"$subject" is not a certificate subject like CN=My Studio.');
    final cer = pfxPath.replaceAll(RegExp(r'\.pfx$', caseSensitive: false), '.cer');
    await File(pfxPath).parent.create(recursive: true);
    if (File(pfxPath).existsSync()) throw StateError('$pfxPath already exists; choose another name so an existing certificate is not replaced.');
    final r = await _powershell(r'''
$ErrorActionPreference = 'Stop'
$c = New-SelfSignedCertificate -Type Custom -Subject $env:EMBER_SUBJECT -KeyUsage DigitalSignature -FriendlyName 'Ember test certificate' `
  -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(3) `
  -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
try {
  $pw = ConvertTo-SecureString -String $env:EMBER_PFX_PASSWORD -Force -AsPlainText
  Export-PfxCertificate -Cert $c -FilePath $env:EMBER_PFX -Password $pw | Out-Null
  Export-Certificate -Cert $c -FilePath $env:EMBER_CER | Out-Null
} finally {
  Remove-Item -Path ('Cert:\CurrentUser\My\' + $c.Thumbprint)
}
''', {'EMBER_SUBJECT': subject, 'EMBER_PFX': pfxPath, 'EMBER_CER': cer, 'EMBER_PFX_PASSWORD': password});
    if (r.exitCode != 0 || !File(pfxPath).existsSync()) {
      throw StateError('Could not create the certificate: ${'${r.stderr}'.trim()}');
    }
    return (MsixCertificate(pfxPath, password), cer);
  }

  static Future<ProcessResult> _powershell(String script, Map<String, String> env) =>
      Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script], environment: env);

  // --- Which certificate each project uses (outside the project folder) ---

  static Future<File> _settingsFile() async {
    final override = settingsFileOverride;
    if (override != null) return override;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}windows_signing.json');
  }

  static Future<Map<String, dynamic>> _readSettings() async {
    try {
      final f = await _settingsFile();
      if (!await f.exists()) return {};
      return (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static Future<String?> certificateForProject(String projectId) async {
    final v = (await _readSettings())[projectId];
    return v is String ? v : null;
  }

  static Future<void> setCertificateForProject(String projectId, String? pfxPath) async {
    final all = await _readSettings();
    if (pfxPath == null) {
      all.remove(projectId);
    } else {
      all[projectId] = pfxPath;
    }
    final f = await _settingsFile();
    await f.parent.create(recursive: true);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(all));
  }

  static String _secretName(String pfxPath) => 'ember.windows.pfx:${pfxPath.toLowerCase()}';

  static Future<String?> rememberedPassword(String pfxPath) async {
    try {
      return await _secure.read(key: _secretName(pfxPath));
    } catch (_) {
      return null;
    }
  }

  static Future<bool> rememberPassword(String pfxPath, String? password) async {
    try {
      if (password == null) {
        await _secure.delete(key: _secretName(pfxPath));
      } else {
        await _secure.write(key: _secretName(pfxPath), value: password);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

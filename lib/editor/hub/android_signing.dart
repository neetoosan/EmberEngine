import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// A keystore file and the key inside it that signs a game's Android builds.
class AndroidSigningKey {
  final String keystorePath;
  final String alias;
  const AndroidSigningKey(this.keystorePath, this.alias);

  Map<String, dynamic> toJson() => {'keystore': keystorePath, 'alias': alias};
  static AndroidSigningKey? fromJson(Object? json) {
    if (json is! Map || json['keystore'] is! String || json['alias'] is! String) return null;
    return AndroidSigningKey(json['keystore'] as String, json['alias'] as String);
  }
}

/// Creates and remembers Android signing keys (needed to publish on Google
/// Play). The key file stays wherever the user saved it; the editor only
/// remembers its path per project, and keeps the password in the operating
/// system's secure store (Windows Credential Manager) if asked to.
class AndroidSigning {
  AndroidSigning._();

  static const _secure = FlutterSecureStorage();

  /// Test hook: where the "which key does each project use" file lives.
  static File? settingsFileOverride;

  /// The JDK's keytool: from JAVA_HOME, Android Studio's bundled JDK, or PATH.
  static String? findKeytool() {
    final exe = Platform.isWindows ? 'keytool.exe' : 'keytool';
    final env = Platform.environment;
    final candidates = [
      if (env['JAVA_HOME'] != null) '${env['JAVA_HOME']}${Platform.pathSeparator}bin${Platform.pathSeparator}$exe',
      if (Platform.isWindows) r'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
      if (Platform.isMacOS) '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool',
      if (Platform.isLinux) '/opt/android-studio/jbr/bin/keytool',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    for (final dir in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
      final f = File('$dir${Platform.pathSeparator}$exe');
      if (dir.isNotEmpty && f.existsSync()) return f.path;
    }
    return null;
  }

  /// Creates a new upload key (RSA 2048, valid ~27 years, PKCS12: one password
  /// for the file and the key). [name] and [organization] go into the
  /// certificate; Google Play does not show them to players.
  static Future<AndroidSigningKey> createKey({
    required String keystorePath,
    required String alias,
    required String password,
    required String name,
    String organization = '',
    String countryCode = '',
  }) async {
    final keytool = findKeytool() ?? (throw StateError('keytool was not found: install Android Studio (it includes a JDK) or set JAVA_HOME.'));
    if (password.length < 6) throw ArgumentError('The password needs at least 6 characters.');
    if (File(keystorePath).existsSync()) throw StateError('$keystorePath already exists; choose another file name.');
    String clean(String s) => s.replaceAll(RegExp(r'[,=+<>#;"\\]'), ' ').trim();
    final dname = [
      'CN=${clean(name).isEmpty ? 'Game Developer' : clean(name)}',
      if (clean(organization).isNotEmpty) 'O=${clean(organization)}',
      if (RegExp(r'^[A-Za-z]{2}$').hasMatch(countryCode)) 'C=${countryCode.toUpperCase()}',
    ].join(', ');
    await File(keystorePath).parent.create(recursive: true);
    final result = await Process.run(keytool, [
      '-genkeypair', '-noprompt',
      '-keystore', keystorePath,
      '-storetype', 'PKCS12',
      '-alias', alias,
      '-keyalg', 'RSA',
      '-keysize', '2048',
      '-validity', '10000',
      '-storepass', password,
      '-keypass', password,
      '-dname', dname,
    ]);
    if (result.exitCode != 0 || !File(keystorePath).existsSync()) {
      throw StateError('Creating the key failed: ${'${result.stderr}${result.stdout}'.trim()}');
    }
    return AndroidSigningKey(keystorePath, alias);
  }

  /// True when [password] opens [key] (checked with keytool).
  static Future<bool> verify(AndroidSigningKey key, String password) async {
    final keytool = findKeytool();
    if (keytool == null || !File(key.keystorePath).existsSync()) return false;
    final r = await Process.run(keytool, ['-list', '-keystore', key.keystorePath, '-storepass', password, '-alias', key.alias]);
    return r.exitCode == 0;
  }

  /// The SHA-256 fingerprint of [key]'s certificate (what Google Play shows for your upload key).
  static Future<String?> fingerprint(AndroidSigningKey key, String password) async {
    final keytool = findKeytool();
    if (keytool == null) return null;
    final r = await Process.run(keytool, ['-list', '-v', '-keystore', key.keystorePath, '-storepass', password, '-alias', key.alias]);
    final m = RegExp(r'SHA256:\s*([0-9A-F:]+)').firstMatch('${r.stdout}');
    return m?.group(1);
  }

  /// Environment for the Gradle build (read in android/app/build.gradle.kts).
  static Map<String, String> gradleEnvironment(AndroidSigningKey key, String password) => {
        'EMBER_KEYSTORE': key.keystorePath,
        'EMBER_KEYSTORE_PASSWORD': password,
        'EMBER_KEY_ALIAS': key.alias,
        'EMBER_KEY_PASSWORD': password,
      };

  // --- Which key each project uses (outside the project folder, so sharing a project never shares a key) ---

  static Future<File> _settingsFile() async {
    final override = settingsFileOverride;
    if (override != null) return override;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}android_signing.json');
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

  static Future<AndroidSigningKey?> keyForProject(String projectId) async => AndroidSigningKey.fromJson((await _readSettings())[projectId]);

  static Future<void> setKeyForProject(String projectId, AndroidSigningKey? key) async {
    final all = await _readSettings();
    if (key == null) {
      all.remove(projectId);
    } else {
      all[projectId] = key.toJson();
    }
    final f = await _settingsFile();
    await f.parent.create(recursive: true);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(all));
  }

  // --- Passwords in the system's secure store ---

  static String _secretName(AndroidSigningKey key) => 'ember.android.keystore:${key.keystorePath.toLowerCase()}:${key.alias}';

  static Future<String?> rememberedPassword(AndroidSigningKey key) async {
    try {
      return await _secure.read(key: _secretName(key));
    } catch (_) {
      return null; // no secure store on this system: ask each time
    }
  }

  static Future<bool> rememberPassword(AndroidSigningKey key, String? password) async {
    try {
      if (password == null) {
        await _secure.delete(key: _secretName(key));
      } else {
        await _secure.write(key: _secretName(key), value: password);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

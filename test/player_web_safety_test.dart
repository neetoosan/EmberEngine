import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Every library the player (lib/main_player.dart) imports, followed through
/// relative and package:ember_engine imports.
Set<String> playerImports() {
  final seen = <String>{};
  final pending = ['lib/main_player.dart'];
  final directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
  while (pending.isNotEmpty) {
    final path = File(pending.removeLast()).absolute.path;
    if (!seen.add(path)) continue;
    final source = File(path).readAsStringSync();
    for (final m in directive.allMatches(source)) {
      final uri = m.group(1)!;
      if (uri.startsWith('dart:') || (uri.startsWith('package:') && !uri.startsWith('package:ember_engine/'))) {
        seen.add(uri);
        continue;
      }
      final target = uri.startsWith('package:ember_engine/')
          ? 'lib/${uri.substring('package:ember_engine/'.length)}'
          : File(path).parent.uri.resolve(uri).toFilePath();
      if (File(target).existsSync()) pending.add(target);
    }
  }
  return seen;
}

void main() {
  test('the game player stays web-safe: no dart:ffi or desktop-only exporter code', () {
    final imports = playerImports();
    expect(imports, isNot(contains('dart:ffi')), reason: 'dart:ffi breaks the web build of exported games');
    for (final desktopOnly in ['game_exporter.dart', 'windows_branding.dart', 'android_signing.dart']) {
      expect(imports.where((p) => p.endsWith(desktopOnly)), isEmpty, reason: '$desktopOnly must not be in the player');
    }
  });
}

/// The one place the engine's version is defined. Keep it equal to the
/// `version:` line in pubspec.yaml (a test checks this); Windows file
/// properties and Android version codes are built from pubspec.
class EmberVersion {
  EmberVersion._();

  static const String productName = 'Ember Engine';
  /// Who makes Ember. Keep it equal to CompanyName/LegalCopyright in
  /// windows/runner/Runner.rc and PRODUCT_COPYRIGHT in macos AppInfo.xcconfig.
  static const String publisher = 'Neetoosan Studio';
  static const String copyright = 'Copyright © 2026 $publisher. All rights reserved.';
  static const String version = '1.0.0';
  static const int build = 1;

  static String get displayName => '$productName $version';
  static String get full => '$version+$build';
}

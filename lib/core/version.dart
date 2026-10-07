/// The one place the engine's version is defined. Keep it equal to the
/// `version:` line in pubspec.yaml (a test checks this); Windows file
/// properties and Android version codes are built from pubspec.
class EmberVersion {
  EmberVersion._();

  static const String productName = 'Ember Engine';
  static const String version = '1.0.0';
  static const int build = 1;

  static String get displayName => '$productName $version';
  static String get full => '$version+$build';
}

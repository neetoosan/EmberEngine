import 'dart:async';
import 'dart:io';
import 'package:ember_engine/editor/hub/project_storage.dart';

/// Runs before every test file: projects created by tests (e.g. pressing
/// "Create & Launch Editor") go to a temporary folder, never the user's Documents.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ProjectStorage.projectsRootOverride = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}ember_test_projects');
  await testMain();
}

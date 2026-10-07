import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'event_bus.dart';
import 'version.dart';

/// Catches errors anywhere in the app so one broken panel or script never
/// takes the whole editor (or an exported game) down, and keeps a log file
/// per day for support: `<app support>/logs/<app>-YYYY-MM-DD.log`.
class CrashReporter {
  CrashReporter._();

  static String _appName = 'ember';
  static Directory? _logDir;
  static IOSink? _sink;
  static String? _sinkPath;

  /// Errors caught since start (newest last), for the About / report screen.
  static final List<String> recentErrors = [];

  /// Log files older than this many days are deleted at start.
  static const int keepDays = 14;

  static Directory? get logDirectory => _logDir;

  /// Installs the handlers. [logToFile] is off on the web and in tests.
  static Future<void> install({required String appName, bool logToFile = !kIsWeb, Directory? logDir}) async {
    _appName = appName;
    if (logToFile) {
      try {
        _logDir = logDir ?? Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}logs');
        await _logDir!.create(recursive: true);
        _deleteOldLogs();
      } catch (_) {
        _logDir = null; // logging is best effort
      }
    }

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record('Flutter error', details.exception, details.stack, context: details.context?.toDescription());
      if (kDebugMode) previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record('Uncaught error', error, stack);
      return true; // handled: keep running
    };
    ErrorWidget.builder = errorWidget;

    // Engine warnings and errors (scripts, assets, export) go to the log too
    EmberEventBus.instance.on<LogEvent>().listen((e) {
      final entry = e.log;
      if (entry.severity == LogSeverity.warning || entry.severity == LogSeverity.error) {
        writeLine('[${entry.severity.name}] ${entry.source ?? 'Engine'}: ${entry.message}');
      }
    });
    writeLine('--- ${EmberVersion.displayName} started (${systemSummary()}) ---');
  }

  /// Records a caught error in [recentErrors] and the log file.
  static void record(String kind, Object error, StackTrace? stack, {String? context}) {
    final text = '$kind${context == null ? '' : ' ($context)'}: $error';
    recentErrors.add(text);
    if (recentErrors.length > 50) recentErrors.removeAt(0);
    writeLine('[crash] $text\n${stack ?? ''}');
    debugPrint('Ember: $text');
  }

  /// Appends a timestamped line to today's log file (no-op without file logging).
  static void writeLine(String line) {
    final dir = _logDir;
    if (dir == null) return;
    try {
      final path = logFileFor(DateTime.now()).path;
      if (_sinkPath != path) {
        _sink?.close();
        _sink = File(path).openWrite(mode: FileMode.append);
        _sinkPath = path;
      }
      _sink!.writeln('${DateTime.now().toIso8601String()}  $line');
    } catch (_) {}
  }

  /// Writes buffered log lines to disk (e.g. before showing the log folder).
  static Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  /// Closes the log file (it reopens on the next line written).
  static Future<void> close() async {
    final sink = _sink;
    _sink = null;
    _sinkPath = null;
    try {
      await sink?.close();
    } catch (_) {}
  }

  static File logFileFor(DateTime day) {
    final d = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return File('${_logDir!.path}${Platform.pathSeparator}$_appName-$d.log');
  }

  static void _deleteOldLogs() {
    final cutoff = DateTime.now().subtract(const Duration(days: keepDays));
    try {
      for (final f in _logDir!.listSync().whereType<File>()) {
        if (f.path.endsWith('.log') && f.lastModifiedSync().isBefore(cutoff)) f.deleteSync();
      }
    } catch (_) {}
  }

  /// One line describing the machine, for logs and problem reports.
  static String systemSummary() {
    if (kIsWeb) return 'web';
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}; Dart ${Platform.version.split(' ').first}; '
        '${Platform.numberOfProcessors} CPUs; locale ${Platform.localeName}';
  }

  /// Text to paste into a support request: version, system, recent errors. No project content.
  static String problemReport() {
    final b = StringBuffer()
      ..writeln(EmberVersion.displayName)
      ..writeln(systemSummary());
    if (recentErrors.isEmpty) {
      b.writeln('No errors caught this session.');
    } else {
      b.writeln('Recent errors:');
      for (final e in recentErrors.reversed.take(10)) {
        b.writeln('- $e');
      }
    }
    if (_logDir != null) b.writeln('Log folder: ${_logDir!.path}');
    return b.toString();
  }

  /// Opens [logDirectory] in the system file browser.
  static Future<bool> openLogFolder() async {
    final dir = _logDir;
    if (dir == null || kIsWeb) return false;
    await flush();
    try {
      final (cmd, args) = Platform.isWindows
          ? ('explorer', [dir.path])
          : Platform.isMacOS
              ? ('open', [dir.path])
              : ('xdg-open', [dir.path]);
      await Process.start(cmd, args, mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Shown instead of a widget that failed to build: a calm message, not a red screen.
  static Widget errorWidget(FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF1B1E26),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 22),
              const SizedBox(height: 6),
              const Text('Something went wrong here', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '${details.exceptionAsString().split('\n').first}\nYour work is safe. The details are in the log (Ctrl+K → About).',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

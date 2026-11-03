import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Logs all file operations for recovery and audit.
class ActionLogService {
  static ActionLogService? _instance;
  factory ActionLogService() => _instance ??= ActionLogService._();
  ActionLogService._();

  final List<ActionLogEntry> _recentActions = [];
  List<ActionLogEntry> get recentActions => List.unmodifiable(_recentActions);

  /// Log a file operation.
  Future<void> log(ActionLogEntry entry) async {
    _recentActions.insert(0, entry);
    if (_recentActions.length > 200) _recentActions.removeLast();

    // Persist to disk
    try {
      final file = await _logFile();
      final line = '${entry.timestamp.toIso8601String()}'
          '\t${entry.actionType}'
          '\t${entry.fileCount}'
          '\t${entry.destinationPath ?? '-'}'
          '\t${entry.copied}'
          '\t${entry.skipped}'
          '\t${entry.errors.length}'
          '\t${entry.summary}\n';
      await file.writeAsString(line, mode: FileMode.append);
    } catch (_) {}
  }

  /// Log a crate creation.
  Future<void> logCrateCreation({
    required String crateName,
    required String destinationPath,
    required int copied,
    required int skipped,
    required List<String> errors,
    required List<String> missingTracks,
    required String mode, // 'copy', 'alias', 'virtual'
  }) async {
    await log(ActionLogEntry(
      timestamp: DateTime.now(),
      actionType: 'crate_creation',
      summary: 'Created crate "$crateName" ($mode): $copied copied, $skipped skipped, ${missingTracks.length} missing',
      fileCount: copied + skipped,
      destinationPath: destinationPath,
      copied: copied,
      skipped: skipped,
      errors: errors,
      metadata: {'crateName': crateName, 'mode': mode, 'missing': missingTracks.length},
    ));
  }

  /// Log an export operation.
  Future<void> logExport({
    required String format,
    required String exportPath,
    required int trackCount,
  }) async {
    await log(ActionLogEntry(
      timestamp: DateTime.now(),
      actionType: 'export',
      summary: 'Exported $trackCount tracks as $format to $exportPath',
      fileCount: trackCount,
      destinationPath: exportPath,
      copied: trackCount,
      skipped: 0,
      errors: [],
      metadata: {'format': format},
    ));
  }

  /// Log a duplicate cleanup.
  Future<void> logDuplicateCleanup({
    required int moved,
    required int skipped,
    required String destination, // 'trash' or folder path
    required List<String> errors,
  }) async {
    await log(ActionLogEntry(
      timestamp: DateTime.now(),
      actionType: 'duplicate_cleanup',
      summary: 'Duplicate cleanup: $moved moved to $destination, $skipped skipped',
      fileCount: moved + skipped,
      destinationPath: destination,
      copied: 0,
      skipped: skipped,
      errors: errors,
      metadata: {'moved': moved},
    ));
  }

  /// Get the log file path.
  Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory(p.join(dir.path, 'VibeRadar', 'Logs'));
    await logDir.create(recursive: true);
    return File(p.join(logDir.path, 'action_log.tsv'));
  }

  /// Open the log file in the default text editor.
  Future<void> openLogFile() async {
    final file = await _logFile();
    if (file.existsSync()) {
      await Process.run('open', [file.path]);
    }
  }

  /// Get log file path for display.
  Future<String> getLogFilePath() async {
    final file = await _logFile();
    return file.path;
  }
}

class ActionLogEntry {
  final DateTime timestamp;
  final String actionType;
  final String summary;
  final int fileCount;
  final String? destinationPath;
  final int copied;
  final int skipped;
  final List<String> errors;
  final Map<String, dynamic> metadata;

  const ActionLogEntry({
    required this.timestamp,
    required this.actionType,
    required this.summary,
    required this.fileCount,
    this.destinationPath,
    required this.copied,
    required this.skipped,
    required this.errors,
    this.metadata = const {},
  });

  String get timeFormatted {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

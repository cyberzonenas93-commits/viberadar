import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/hot_cue.dart';
import 'dj_root_detection_service.dart';

/// Result of a cue-write operation.
class VdjCueWriteResult {
  const VdjCueWriteResult({
    required this.success,
    required this.trackPath,
    required this.cuesWritten,
    this.backupPath,
    this.errorMessage,
  });

  final bool   success;
  final String trackPath;
  final int    cuesWritten;
  final String? backupPath;
  final String? errorMessage;
}

/// Safely writes hot cue points into VirtualDJ's database.xml.
///
/// SAFETY GUARANTEES:
///   1. Always backs up database.xml before any modification.
///   2. Parses existing XML preserving all unrelated entries.
///   3. Only adds/updates <Poi> elements; never removes existing cues.
///   4. Writes atomically (temp file → rename).
///   5. Validates vdjRoot before any I/O.
///   6. Never modifies the original audio files.
///
/// SERATO: intentionally not implemented here — Serato metadata writing
/// requires fixture-validated binary format analysis.
class VirtualDjCueWriter {
  VirtualDjCueWriter({DjRootDetectionService? detection})
      : _detection = detection ?? DjRootDetectionService();

  final DjRootDetectionService _detection;

  static const _dbFilename  = 'database.xml';
  static const _backupSuffix = '.viberadar-backup';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Write [cues] for the track at [localFilePath] into VirtualDJ's database.
  ///
  /// [vdjRoot] must be a validated VirtualDJ root directory.
  /// Returns a [VdjCueWriteResult] describing the outcome.
  ///
  /// DOES NOT write to disk if [dryRun] is true — useful for preview.
  Future<VdjCueWriteResult> writeCues({
    required String vdjRoot,
    required String localFilePath,
    required List<HotCue> cues,
    bool dryRun = false,
  }) async {
    if (!_detection.validateVirtualDjRoot(vdjRoot)) {
      return VdjCueWriteResult(
        success: false, trackPath: localFilePath, cuesWritten: 0,
        errorMessage: 'Invalid VirtualDJ root: $vdjRoot',
      );
    }
    final pathError = _validateTrackPath(localFilePath);
    if (pathError != null) {
      return VdjCueWriteResult(
        success: false, trackPath: localFilePath, cuesWritten: 0,
        errorMessage: pathError,
      );
    }
    if (cues.isEmpty) {
      return VdjCueWriteResult(
        success: true, trackPath: localFilePath, cuesWritten: 0,
      );
    }

    final dbFile = File(p.join(vdjRoot, _dbFilename));
    String originalXml;
    if (await dbFile.exists()) {
      originalXml = await dbFile.readAsString();
    } else {
      originalXml = _emptyDatabase();
    }

    // Merge cues into XML
    final mergedXml = _mergeCuesIntoXml(originalXml, localFilePath, cues);

    if (dryRun) {
      return VdjCueWriteResult(
        success: true, trackPath: localFilePath, cuesWritten: cues.length,
      );
    }

    // Backup original database
    String? backupPath;
    if (await dbFile.exists()) {
      backupPath = '${dbFile.path}$_backupSuffix';
      await dbFile.copy(backupPath);
    }

    // Atomic write: temp → rename
    final tmpFile = File('${dbFile.path}.tmp');
    try {
      await tmpFile.writeAsString(mergedXml, flush: true);
      await tmpFile.rename(dbFile.path);
    } catch (e) {
      // Restore backup if write failed
      if (backupPath != null && await File(backupPath).exists()) {
        await File(backupPath).copy(dbFile.path);
      }
      await tmpFile.delete().catchError((_) => File(''));
      return VdjCueWriteResult(
        success: false, trackPath: localFilePath, cuesWritten: 0,
        errorMessage: 'Write failed: $e',
      );
    }

    return VdjCueWriteResult(
      success: true, trackPath: localFilePath,
      cuesWritten: cues.length, backupPath: backupPath,
    );
  }

  // ── XML manipulation ───────────────────────────────────────────────────────

  String _mergeCuesIntoXml(
      String xml, String filePath, List<HotCue> cues) {
    final escaped = _escAttr(filePath);
    // Pattern to find our Song entry (filepath match)
    final songPattern = RegExp(
      r'<Song\s[^>]*Filepath="' + RegExp.escape(escaped) + r'"[^>]*>',
      caseSensitive: false,
    );

    final match = songPattern.firstMatch(xml);
    if (match != null) {
      // Song entry exists — find its closing tag and inject cues before it
      final startIdx = match.start;
      final closeTag = '</Song>';
      final closeIdx = xml.indexOf(closeTag, startIdx);
      if (closeIdx == -1) return xml; // malformed — skip

      // Build the Poi elements
      final poisXml = _buildPoisXml(cues);

      // Remove any existing Poi entries for our cue slots, then append
      final songBlock = xml.substring(startIdx, closeIdx);
      final cleanBlock = _removeOurPoiSlots(songBlock, cues.map((c) => c.cueIndex).toSet());
      return xml.substring(0, startIdx) +
             cleanBlock +
             poisXml +
             closeTag +
             xml.substring(closeIdx + closeTag.length);
    } else {
      // Song entry not found — inject a new one before </VirtualDJ_Database>
      final closeDb = '</VirtualDJ_Database>';
      final dbCloseIdx = xml.lastIndexOf(closeDb);
      if (dbCloseIdx == -1) return xml; // unrecognised format

      final songBlock = _buildNewSongEntry(filePath, cues);
      return xml.substring(0, dbCloseIdx) + songBlock + closeDb;
    }
  }

  String _buildPoisXml(List<HotCue> cues) {
    final buf = StringBuffer();
    for (final c in cues) {
      buf.writeln(
        '    <Poi Pos="${c.timeSeconds.toStringAsFixed(3)}" '
        'Type="cue" '
        'Name="${_escAttr(c.label)}" '
        'Num="${c.cueIndex}" '
        'Comment="${_escAttr(c.notes ?? c.cueType.label)}" />',
      );
    }
    return buf.toString();
  }

  String _buildNewSongEntry(String filePath, List<HotCue> cues) {
    final buf = StringBuffer();
    buf.writeln('  <Song Filepath="${_escAttr(filePath)}" Flag="0">');
    buf.write(_buildPoisXml(cues));
    buf.writeln('  </Song>');
    return buf.toString();
  }

  /// Remove only the <Poi> elements for cue slot numbers we are about to write.
  String _removeOurPoiSlots(String songBlock, Set<int> slots) {
    var result = songBlock;
    for (final slot in slots) {
      final pattern = RegExp(
        r'\s*<Poi[^>]*\sNum="' + slot.toString() + r'"[^/]*/>\s*',
      );
      result = result.replaceAll(pattern, '\n');
    }
    return result;
  }

  String _emptyDatabase() =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<VirtualDJ_Database Version="8.5">\n'
      '</VirtualDJ_Database>\n';

  String _escAttr(String v) => v
      .replaceAll('&',  '&amp;')
      .replaceAll('"',  '&quot;')
      .replaceAll("'",  '&apos;')
      .replaceAll('<',  '&lt;')
      .replaceAll('>',  '&gt;');

  // ── Batch write ────────────────────────────────────────────────────────────

  /// Write cues for multiple tracks in a single database.xml edit cycle.
  /// More efficient than calling [writeCues] per-track as it only backs up once.
  Future<List<VdjCueWriteResult>> writeBatch({
    required String vdjRoot,
    required Map<String, List<HotCue>> cuesByFilePath,
    bool dryRun = false,
  }) async {
    if (!_detection.validateVirtualDjRoot(vdjRoot)) {
      return cuesByFilePath.keys.map((p) => VdjCueWriteResult(
        success: false, trackPath: p, cuesWritten: 0,
        errorMessage: 'Invalid VirtualDJ root',
      )).toList();
    }

    // Pre-validate all track paths so we never write a partial batch with
    // some valid + some garbage entries.
    final pathErrors = <String, String>{};
    for (final trackPath in cuesByFilePath.keys) {
      final err = _validateTrackPath(trackPath);
      if (err != null) pathErrors[trackPath] = err;
    }
    if (pathErrors.isNotEmpty) {
      return cuesByFilePath.keys.map((trackPath) {
        final err = pathErrors[trackPath];
        return VdjCueWriteResult(
          success: err == null,
          trackPath: trackPath,
          cuesWritten: 0,
          errorMessage: err ?? 'Batch aborted — other tracks had invalid paths',
        );
      }).toList();
    }

    final dbFile = File(p.join(vdjRoot, _dbFilename));
    String xml = await dbFile.exists() ? await dbFile.readAsString() : _emptyDatabase();

    String? backupPath;
    if (!dryRun && await dbFile.exists()) {
      backupPath = '${dbFile.path}$_backupSuffix';
      await dbFile.copy(backupPath);
    }

    final results = <VdjCueWriteResult>[];
    for (final entry in cuesByFilePath.entries) {
      if (entry.value.isEmpty) {
        results.add(VdjCueWriteResult(
          success: true, trackPath: entry.key, cuesWritten: 0));
        continue;
      }
      xml = _mergeCuesIntoXml(xml, entry.key, entry.value);
      results.add(VdjCueWriteResult(
        success: true, trackPath: entry.key,
        cuesWritten: entry.value.length, backupPath: backupPath));
    }

    if (!dryRun) {
      final tmp = File('${dbFile.path}.tmp');
      try {
        await tmp.writeAsString(xml, flush: true);
        await tmp.rename(dbFile.path);
      } catch (e) {
        if (backupPath != null) await File(backupPath).copy(dbFile.path);
        await tmp.delete().catchError((_) => File(''));
        return cuesByFilePath.keys.map((fp) => VdjCueWriteResult(
          success: false, trackPath: fp, cuesWritten: 0,
          errorMessage: 'Batch write failed: $e')).toList();
      }
    }
    return results;
  }

  // ── Validation helper (public for UI) ──────────────────────────────────────
  bool validateRoot(String path) => _detection.validateVirtualDjRoot(path);

  /// Returns `null` when [trackPath] is acceptable, or a reason string if
  /// it should be rejected. Guards against empty paths, relative paths,
  /// and `..` traversal components.
  ///
  /// We intentionally DO NOT require the file to exist on disk — VirtualDJ
  /// itself tolerates references to temporarily-offline drives, and we want
  /// the cue database to stay valid when the user plugs the drive back in.
  String? _validateTrackPath(String trackPath) {
    if (trackPath.isEmpty) return 'Track path is empty';
    if (!p.isAbsolute(trackPath)) {
      return 'Track path must be absolute: $trackPath';
    }
    final normalised = p.normalize(trackPath);
    if (normalised.split(p.separator).contains('..')) {
      return 'Track path contains unresolved .. component: $trackPath';
    }
    return null;
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/hot_cue.dart';

/// Exports cue suggestions to portable formats (JSON manifest, CSV).
///
/// These exports are read-only and do NOT modify audio files or DJ databases.
/// They can be used for backup, sharing, or future import workflows.
class CueExportService {

  // ── JSON manifest ──────────────────────────────────────────────────────────

  /// Export [results] to a JSON manifest file at [destinationDir].
  /// Returns the path of the written file.
  Future<String> exportJsonManifest(
    List<CueGenerationResult> results,
    String destinationDir, {
    String filename = 'viberadar_cues.json',
  }) async {
    final outPath = p.join(destinationDir, filename);
    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'version': '1.0',
      'trackCount': results.length,
      'tracks': results.map((r) => r.toJson()).toList(),
    };
    await File(outPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    return outPath;
  }

  // ── CSV export ─────────────────────────────────────────────────────────────

  /// Export [results] to a CSV file at [destinationDir].
  Future<String> exportCsv(
    List<CueGenerationResult> results,
    String destinationDir, {
    String filename = 'viberadar_cues.csv',
  }) async {
    final buf = StringBuffer();
    buf.writeln('Track Title,Artist,Cue Index,Cue Type,Label,Time (s),Time (mm:ss.d),Confidence,Source,Notes');
    for (final r in results) {
      for (final c in r.cues) {
        buf.writeln([
          _csvCell(r.trackTitle),
          _csvCell(r.trackArtist),
          c.cueIndex,
          _csvCell(c.cueType.label),
          _csvCell(c.label),
          c.timeSeconds.toStringAsFixed(3),
          _csvCell(c.timestampFormatted),
          c.confidence.toStringAsFixed(2),
          _csvCell(c.source.label),
          _csvCell(c.notes ?? ''),
        ].join(','));
      }
    }
    final outPath = p.join(destinationDir, filename);
    await File(outPath).writeAsString(buf.toString());
    return outPath;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _csvCell(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}

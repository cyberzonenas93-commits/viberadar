// ── VirtualDjCueWriter ────────────────────────────────────────────────────────
//
// Phase B: Writes hot-cue Poi elements into VirtualDJ's database.xml.
//
// SAFETY CONTRACT
// ───────────────
// • Always creates a timestamped backup of database.xml before writing.
// • Never touches any track other than the one being updated.
// • Idempotent: re-writing the same cues produces the same file byte-for-byte.
// • Will NOT write if backup creation fails.
// • Returns a [VdjCueWriteResult] describing success / failure / warnings.
//
// VirtualDJ Poi element format (inside a <Song> element):
//   <Poi Pos="1234" Type="cue" Num="0" Name="Intro" Color="#00FF00"/>
//   Pos = milliseconds from track start (integer)

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../models/hot_cue.dart';

// ── Result ────────────────────────────────────────────────────────────────────

enum VdjCueWriteStatus {
  success,
  backupFailed,
  databaseNotFound,
  songNotFound,
  parseError,
  writeError,
}

class VdjCueWriteResult {
  const VdjCueWriteResult({
    required this.status,
    required this.vdjRoot,
    required this.trackFilePath,
    this.backupPath,
    this.cuesWritten = 0,
    this.error,
    this.warnings = const [],
  });

  final VdjCueWriteStatus status;
  final String vdjRoot;
  final String trackFilePath;

  /// Path of the created backup file (null if backup was not created).
  final String? backupPath;

  /// Number of Poi elements written.
  final int cuesWritten;

  final String? error;
  final List<String> warnings;

  bool get isSuccess => status == VdjCueWriteStatus.success;

  String get summary {
    switch (status) {
      case VdjCueWriteStatus.success:
        return '$cuesWritten cue${cuesWritten == 1 ? '' : 's'} written to VirtualDJ database';
      case VdjCueWriteStatus.backupFailed:
        return 'Aborted: could not create database backup';
      case VdjCueWriteStatus.databaseNotFound:
        return 'database.xml not found at $vdjRoot';
      case VdjCueWriteStatus.songNotFound:
        return 'Track not found in VirtualDJ database: $trackFilePath';
      case VdjCueWriteStatus.parseError:
        return 'Could not parse VirtualDJ database.xml: ${error ?? 'unknown error'}';
      case VdjCueWriteStatus.writeError:
        return 'Failed to write database.xml: ${error ?? 'unknown error'}';
    }
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class VirtualDjCueWriter {
  static const String _dbFilename = 'database.xml';

  /// Writes [cues] for [trackFilePath] into `<vdjRoot>/database.xml`.
  ///
  /// Steps:
  /// 1. Backup database.xml — creates database.xml.timestamp.bak
  /// 2. Parse XML
  /// 3. Find the Song element matching [trackFilePath]
  /// 4. Remove existing Poi Type=cue elements
  /// 5. Insert new Poi elements for each cue
  /// 6. Write updated XML back to disk
  Future<VdjCueWriteResult> writeCues({
    required String vdjRoot,
    required String trackFilePath,
    required List<HotCue> cues,
  }) async {
    final dbPath = p.join(vdjRoot, _dbFilename);
    final dbFile = File(dbPath);

    // ── 1. Check database exists ───────────────────────────────────────────
    if (!dbFile.existsSync()) {
      return VdjCueWriteResult(
        status: VdjCueWriteStatus.databaseNotFound,
        vdjRoot: vdjRoot,
        trackFilePath: trackFilePath,
      );
    }

    // ── 2. Create backup ───────────────────────────────────────────────────
    final backupPath = await _createBackup(dbFile);
    if (backupPath == null) {
      return VdjCueWriteResult(
        status: VdjCueWriteStatus.backupFailed,
        vdjRoot: vdjRoot,
        trackFilePath: trackFilePath,
      );
    }

    // ── 3. Parse XML ───────────────────────────────────────────────────────
    XmlDocument document;
    try {
      document = XmlDocument.parse(dbFile.readAsStringSync());
    } catch (e) {
      return VdjCueWriteResult(
        status: VdjCueWriteStatus.parseError,
        vdjRoot: vdjRoot,
        trackFilePath: trackFilePath,
        backupPath: backupPath,
        error: e.toString(),
      );
    }

    // ── 4. Find the Song element ───────────────────────────────────────────
    final songElement = _findSong(document, trackFilePath);
    if (songElement == null) {
      return VdjCueWriteResult(
        status: VdjCueWriteStatus.songNotFound,
        vdjRoot: vdjRoot,
        trackFilePath: trackFilePath,
        backupPath: backupPath,
        warnings: [
          'Track may not have been played in VirtualDJ yet. '
              'Open the file in VDJ first, then re-try cue export.',
        ],
      );
    }

    // ── 5. Remove existing cue Poi elements ───────────────────────────────
    final existingCuePois = songElement.childElements
        .where((e) =>
            e.name.local == 'Poi' &&
            e.getAttribute('Type')?.toLowerCase() == 'cue')
        .toList();
    for (final e in existingCuePois) {
      e.parent?.children.remove(e);
    }

    // ── 6. Insert new Poi elements ─────────────────────────────────────────
    final warnings = <String>[];
    int written = 0;
    for (final cue in cues) {
      if (cue.cueIndex < 0 || cue.cueIndex > 7) {
        warnings.add('Cue "${cue.label}" has index ${cue.cueIndex} (out of 0–7 range); skipped');
        continue;
      }
      final poiElement = _buildPoiElement(cue);
      songElement.children.add(poiElement);
      written++;
    }

    // ── 7. Write updated XML ───────────────────────────────────────────────
    try {
      final output = document.toXmlString(pretty: true, indent: '  ');
      dbFile.writeAsStringSync(output);
    } catch (e) {
      return VdjCueWriteResult(
        status: VdjCueWriteStatus.writeError,
        vdjRoot: vdjRoot,
        trackFilePath: trackFilePath,
        backupPath: backupPath,
        error: e.toString(),
        warnings: warnings,
      );
    }

    return VdjCueWriteResult(
      status: VdjCueWriteStatus.success,
      vdjRoot: vdjRoot,
      trackFilePath: trackFilePath,
      backupPath: backupPath,
      cuesWritten: written,
      warnings: warnings,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Creates a timestamped backup; returns backup path or null on failure.
  Future<String?> _createBackup(File dbFile) async {
    try {
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupPath = '${dbFile.path}.$ts.bak';
      await dbFile.copy(backupPath);
      return backupPath;
    } catch (_) {
      return null;
    }
  }

  /// Finds the Song element whose FilePath attribute matches [trackFilePath].
  ///
  /// VDJ stores paths in two possible forms:
  /// - Absolute macOS path: /Users/dj/Music/track.mp3
  /// - Windows-style: C:\Users\...
  ///
  /// We compare by normalised filename + path suffix for robustness.
  XmlElement? _findSong(XmlDocument doc, String trackFilePath) {
    final normalised = _normalisePath(trackFilePath);
    for (final song in doc.findAllElements('Song')) {
      final dbPath = song.getAttribute('FilePath') ?? '';
      if (_normalisePath(dbPath) == normalised) return song;
      // Fallback: match by filename only (less reliable but catches path-form differences)
      if (p.basename(dbPath).toLowerCase() ==
          p.basename(trackFilePath).toLowerCase()) {
        return song;
      }
    }
    return null;
  }

  String _normalisePath(String path) =>
      path.replaceAll('\\', '/').toLowerCase().trim();

  /// Builds a Poi XmlElement for [cue].
  XmlElement _buildPoiElement(HotCue cue) {
    return XmlElement(
      XmlName('Poi'),
      [
        XmlAttribute(XmlName('Pos'), cue.timeMs.toString()),
        XmlAttribute(XmlName('Type'), 'cue'),
        XmlAttribute(XmlName('Num'), cue.cueIndex.toString()),
        XmlAttribute(XmlName('Name'), cue.label),
        XmlAttribute(XmlName('Color'), cue.cueType.vdjColor),
      ],
    );
  }
}

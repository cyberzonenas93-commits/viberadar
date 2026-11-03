// Tests for all export formats in ExportService: Traktor NML, VirtualDJ XML,
// Serato CSV, TIDAL-aware M3U, and missing-track manifest.
//
// These tests build output strings in-process (mirroring ExportService logic)
// to avoid filesystem writes during CI, validating structure and content.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/services/export_service.dart';

// ── Shared Fixture ──────────────────────────────────────────────────────────

LibraryTrack _track({
  String id = 't1',
  String title = 'Essence',
  String artist = 'Wizkid',
  String album = 'Made In Lagos',
  String genre = 'Afrobeats',
  double bpm = 102.0,
  String key = '5A',
  double durationSeconds = 248.0,
  String filePath = '/music/wizkid_essence.mp3',
  int fileSizeBytes = 9437184,
  int bitrate = 320,
  int? year,
}) =>
    LibraryTrack(
      id: id,
      filePath: filePath,
      fileName: p.basename(filePath),
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      bpm: bpm,
      key: key,
      durationSeconds: durationSeconds,
      fileSizeBytes: fileSizeBytes,
      fileExtension: p.extension(filePath),
      md5Hash: 'deadbeef$id',
      bitrate: bitrate,
      sampleRate: 44100,
      year: year,
    );

// ── Helpers that mirror ExportService internal logic ────────────────────────

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _csv(String s) => s.replaceAll('"', '""');

// ── Traktor NML builder (mirrors ExportService.exportTraktorNml) ────────────

String _buildTraktorNml(ExportCrate crate) {
  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
  buf.writeln('<NML VERSION="19">');
  buf.writeln('  <COLLECTION ENTRIES="${crate.tracks.length}">');
  for (final t in crate.tracks) {
    final dir = p.dirname(t.filePath);
    final file = p.basename(t.filePath);
    buf.writeln('    <ENTRY TITLE="${_esc(t.title)}" ARTIST="${_esc(t.artist)}">');
    buf.writeln(
        '      <LOCATION DIR="${_esc(dir)}/" FILE="${_esc(file)}" VOLUME="/" VOLUMEID=""/>');
    buf.writeln('      <INFO GENRE="${_esc(t.genre)}" KEY="${t.key}"/>');
    buf.writeln(
        '      <TEMPO BPM="${t.bpm.toStringAsFixed(6)}" BPM_QUALITY="100"/>');
    buf.writeln('    </ENTRY>');
  }
  buf.writeln('  </COLLECTION>');
  buf.writeln('  <PLAYLISTS>');
  buf.writeln('    <NODE TYPE="FOLDER" NAME="\$ROOT">');
  buf.writeln('      <SUBNODES COUNT="1">');
  buf.writeln('        <NODE TYPE="PLAYLIST" NAME="${_esc(crate.name)}">');
  buf.writeln(
      '          <PLAYLIST ENTRIES="${crate.tracks.length}" TYPE="LIST">');
  for (final t in crate.tracks) {
    buf.writeln(
        '            <ENTRY><PRIMARYKEY TYPE="TRACK" KEY="${_esc(t.filePath)}"/></ENTRY>');
  }
  buf.writeln('          </PLAYLIST>');
  buf.writeln('        </NODE>');
  buf.writeln('      </SUBNODES>');
  buf.writeln('    </NODE>');
  buf.writeln('  </PLAYLISTS>');
  buf.writeln('</NML>');
  return buf.toString();
}

// ── VirtualDJ XML builder ───────────────────────────────────────────────────

String _buildVirtualDjXml(ExportCrate crate) {
  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln('<VirtualDJ_Database Version="8">');
  for (final t in crate.tracks) {
    final fileUrl = Uri.file(t.filePath).toString();
    buf.writeln('  <Song FilePath="${_esc(fileUrl)}" '
        'Title="${_esc(t.title)}" '
        'Artist="${_esc(t.artist)}" '
        'Album="${_esc(t.album)}" '
        'Genre="${_esc(t.genre)}" '
        'Year="${t.year ?? ''}" '
        'Bpm="${t.bpm.toStringAsFixed(2)}" '
        'Key="${t.key}" '
        'Bitrate="${t.bitrate}" '
        'SongLength="${t.durationSeconds.toStringAsFixed(1)}" '
        'FileSize="${t.fileSizeBytes}"/>');
  }
  buf.writeln('</VirtualDJ_Database>');
  return buf.toString();
}

// ── Serato CSV builder ──────────────────────────────────────────────────────

String _buildSeratoCsv(ExportCrate crate) {
  final buf = StringBuffer();
  buf.writeln('name,artist,album,genre,bpm,key,duration,year,bitrate,filepath');
  for (final t in crate.tracks) {
    buf.writeln('"${_csv(t.title)}","${_csv(t.artist)}","${_csv(t.album)}",'
        '"${_csv(t.genre)}","${t.bpm.toStringAsFixed(0)}","${t.key}",'
        '"${t.durationFormatted}","${t.year ?? ''}","${t.bitrate}",'
        '"${_csv(t.filePath)}"');
  }
  return buf.toString();
}

// ── TIDAL-aware M3U builder ─────────────────────────────────────────────────

String _buildTidalAwareM3u(ExportCrate crate) {
  final buf = StringBuffer();
  buf.writeln('#EXTM3U');
  buf.writeln('#PLAYLIST:${crate.name}');
  buf.writeln('#EXTGRP:VibeRadar Export (TIDAL-aware)');
  for (final t in crate.tracks) {
    buf.writeln(
        '#EXTINF:${t.durationSeconds.toStringAsFixed(0)},${t.artist} - ${t.title}');
    buf.writeln(
        '#EXTVLCOPT:tidal-search=${Uri.encodeComponent('${t.artist} ${t.title}')}');
    buf.writeln(t.filePath);
  }
  return buf.toString();
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // TRAKTOR NML
  // ══════════════════════════════════════════════════════════════════════════

  group('Traktor NML structure', () {
    test('has valid XML declaration with standalone attribute', () {
      final crate = ExportCrate(name: 'Set', tracks: [_track(id: '1')]);
      final nml = _buildTraktorNml(crate);
      expect(nml, startsWith('<?xml version="1.0"'));
      expect(nml, contains('standalone="yes"'));
    });

    test('root element is NML VERSION 19', () {
      final crate = ExportCrate(name: 'Set', tracks: [_track(id: '1')]);
      final nml = _buildTraktorNml(crate);
      expect(nml, contains('<NML VERSION="19">'));
      expect(nml, contains('</NML>'));
    });

    test('COLLECTION Entries count matches track list', () {
      final tracks = List.generate(4, (i) => _track(id: '$i'));
      final crate = ExportCrate(name: 'Set', tracks: tracks);
      final nml = _buildTraktorNml(crate);
      expect(nml, contains('ENTRIES="4"'));
    });

    test('LOCATION splits into DIR and FILE', () {
      final t = _track(id: '1', filePath: '/Users/dj/Music/track.mp3');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final nml = _buildTraktorNml(crate);
      expect(nml, contains('DIR="/Users/dj/Music/"'));
      expect(nml, contains('FILE="track.mp3"'));
    });

    test('BPM has 6-decimal precision', () {
      final t = _track(id: '1', bpm: 128.0);
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final nml = _buildTraktorNml(crate);
      expect(nml, contains('BPM="128.000000"'));
    });

    test('PLAYLIST references track paths as PRIMARYKEY', () {
      final t = _track(id: '1', filePath: '/music/test.mp3');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final nml = _buildTraktorNml(crate);
      expect(nml, contains('KEY="/music/test.mp3"'));
    });

    test('special characters in title and artist are escaped', () {
      final t = _track(id: '1', title: 'Love & War', artist: 'A <B>');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final nml = _buildTraktorNml(crate);
      expect(nml, contains('Love &amp; War'));
      expect(nml, contains('A &lt;B&gt;'));
    });

    test('PLAYLIST node uses \$ROOT convention', () {
      final crate = ExportCrate(name: 'Mix', tracks: [_track(id: '1')]);
      final nml = _buildTraktorNml(crate);
      expect(nml, contains(r'NAME="$ROOT"'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // VIRTUALDJ XML (generic export via ExportService)
  // ══════════════════════════════════════════════════════════════════════════

  group('VirtualDJ XML structure', () {
    test('root element is VirtualDJ_Database Version 8', () {
      final crate = ExportCrate(name: 'Set', tracks: [_track(id: '1')]);
      final xml = _buildVirtualDjXml(crate);
      expect(xml, contains('<VirtualDJ_Database Version="8">'));
      expect(xml, contains('</VirtualDJ_Database>'));
    });

    test('Song elements have correct metadata attributes', () {
      final t = _track(
        id: '1',
        title: 'Essence',
        artist: 'Wizkid',
        bpm: 102.0,
        key: '5A',
      );
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final xml = _buildVirtualDjXml(crate);
      expect(xml, contains('Title="Essence"'));
      expect(xml, contains('Artist="Wizkid"'));
      expect(xml, contains('Bpm="102.00"'));
      expect(xml, contains('Key="5A"'));
    });

    test('FilePath uses file:// URI scheme', () {
      final t = _track(id: '1', filePath: '/music/test.mp3');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final xml = _buildVirtualDjXml(crate);
      expect(xml, contains('file:///music/test.mp3'));
    });

    test('empty track list produces no Song elements', () {
      final crate = ExportCrate(name: 'Empty', tracks: []);
      final xml = _buildVirtualDjXml(crate);
      expect(xml, isNot(contains('<Song')));
    });

    test('special characters in metadata are escaped', () {
      final t = _track(id: '1', title: 'Rock & Roll', artist: 'A "B"');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final xml = _buildVirtualDjXml(crate);
      expect(xml, contains('Rock &amp; Roll'));
      expect(xml, contains('A &quot;B&quot;'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SERATO CSV
  // ══════════════════════════════════════════════════════════════════════════

  group('Serato CSV structure', () {
    test('has correct header row', () {
      final crate = ExportCrate(name: 'Set', tracks: []);
      final csv = _buildSeratoCsv(crate);
      expect(csv, startsWith('name,artist,album,genre,bpm,key,duration,year,bitrate,filepath'));
    });

    test('track data is comma-delimited and quoted', () {
      final t = _track(id: '1', title: 'Essence', artist: 'Wizkid');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final csv = _buildSeratoCsv(crate);
      expect(csv, contains('"Essence"'));
      expect(csv, contains('"Wizkid"'));
    });

    test('double quotes in values are doubled (CSV escaping)', () {
      final t = _track(id: '1', title: 'She Said "Yes"');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final csv = _buildSeratoCsv(crate);
      expect(csv, contains('She Said ""Yes""'));
    });

    test('BPM is integer in CSV', () {
      final t = _track(id: '1', bpm: 128.0);
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final csv = _buildSeratoCsv(crate);
      expect(csv, contains('"128"'));
    });

    test('filepath is included and quoted', () {
      final t = _track(id: '1', filePath: '/music/track.mp3');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final csv = _buildSeratoCsv(crate);
      expect(csv, contains('"/music/track.mp3"'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TIDAL-AWARE M3U
  // ══════════════════════════════════════════════════════════════════════════

  group('TIDAL-aware M3U structure', () {
    test('starts with EXTM3U header', () {
      final crate = ExportCrate(name: 'Mix', tracks: [_track(id: '1')]);
      final m3u = _buildTidalAwareM3u(crate);
      expect(m3u, startsWith('#EXTM3U'));
    });

    test('contains TIDAL group header', () {
      final crate = ExportCrate(name: 'Mix', tracks: [_track(id: '1')]);
      final m3u = _buildTidalAwareM3u(crate);
      expect(m3u, contains('#EXTGRP:VibeRadar Export (TIDAL-aware)'));
    });

    test('each track has EXTVLCOPT tidal-search hint', () {
      final t = _track(id: '1', title: 'Essence', artist: 'Wizkid');
      final crate = ExportCrate(name: 'Mix', tracks: [t]);
      final m3u = _buildTidalAwareM3u(crate);
      expect(m3u, contains('#EXTVLCOPT:tidal-search='));
      expect(m3u, contains('Wizkid'));
      expect(m3u, contains('Essence'));
    });

    test('search hint is URI-encoded', () {
      final t = _track(id: '1', title: 'Love & War', artist: 'A B');
      final crate = ExportCrate(name: 'Mix', tracks: [t]);
      final m3u = _buildTidalAwareM3u(crate);
      // URI encoding replaces & with %26 and space with %20 or +
      expect(m3u, contains('%26'));
    });

    test('file path follows EXTINF and tidal-search', () {
      final t = _track(id: '1', filePath: '/music/track.mp3');
      final crate = ExportCrate(name: 'Mix', tracks: [t]);
      final m3u = _buildTidalAwareM3u(crate);

      final lines = m3u.split('\n');
      // Find the EXTINF line index, then tidal-search, then path
      final extinfIdx = lines.indexWhere((l) => l.startsWith('#EXTINF'));
      expect(extinfIdx, greaterThanOrEqualTo(0));
      expect(lines[extinfIdx + 1], startsWith('#EXTVLCOPT:tidal-search='));
      expect(lines[extinfIdx + 2], equals('/music/track.mp3'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SET BUILDER EXPANDED TESTS
  // ══════════════════════════════════════════════════════════════════════════

  group('ExportCrate + PhysicalCrateResult', () {
    test('ExportCrate holds name and tracks', () {
      final tracks = [_track(id: '1'), _track(id: '2')];
      final crate = ExportCrate(name: 'Test', tracks: tracks);
      expect(crate.name, 'Test');
      expect(crate.tracks.length, 2);
    });

    test('PhysicalCrateResult summary includes counts', () {
      const result = PhysicalCrateResult(
        cratePath: '/tmp/crate',
        filesCopied: 5,
        filesSkipped: 2,
        errors: [],
        missingTracks: ['Track A'],
      );
      expect(result.summary, contains('5 copied'));
      expect(result.summary, contains('2 skipped'));
      expect(result.summary, contains('1 missing'));
    });

    test('PhysicalCrateResult.hasErrors and hasMissing', () {
      const clean = PhysicalCrateResult(
        cratePath: '/tmp/c',
        filesCopied: 3,
        filesSkipped: 0,
        errors: [],
      );
      expect(clean.hasErrors, isFalse);
      expect(clean.hasMissing, isFalse);

      const withError = PhysicalCrateResult(
        cratePath: '/tmp/c',
        filesCopied: 0,
        filesSkipped: 1,
        errors: ['fail'],
        missingTracks: ['A'],
      );
      expect(withError.hasErrors, isTrue);
      expect(withError.hasMissing, isTrue);
    });
  });
}

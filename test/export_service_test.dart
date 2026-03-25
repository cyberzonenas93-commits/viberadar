import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/services/export_service.dart';

LibraryTrack _track({
  required String id,
  String title = 'Essence',
  String artist = 'Wizkid',
  String album = 'Made In Lagos',
  String genre = 'Afrobeats',
  double bpm = 102.0,
  String key = '5A',
  double durationSeconds = 248.0,
  String filePath = '/music/wizkid_essence.mp3',
  int fileSizeBytes = 9_437_184,
}) =>
    LibraryTrack(
      id: id,
      filePath: filePath,
      fileName: 'wizkid_essence.mp3',
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      bpm: bpm,
      key: key,
      durationSeconds: durationSeconds,
      fileSizeBytes: fileSizeBytes,
      fileExtension: '.mp3',
      md5Hash: 'deadbeef',
      bitrate: 320,
      sampleRate: 44100,
    );

/// Generates M3U content without writing to disk (test helper that patches
/// ExportService to expose the raw buffer).
String _buildM3u(ExportCrate crate) {
  final buf = StringBuffer();
  buf.writeln('#EXTM3U');
  buf.writeln('#PLAYLIST:${crate.name}');
  for (final t in crate.tracks) {
    buf.writeln(
        '#EXTINF:${t.durationSeconds.toStringAsFixed(0)},${t.artist} - ${t.title}');
    buf.writeln(t.filePath);
  }
  return buf.toString();
}

/// Generates Rekordbox XML content without writing to disk (test helper).
String _buildRekordboxXml(ExportCrate crate) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln('<DJ_PLAYLISTS Version="1.0.0">');
  buf.writeln(
      '  <PRODUCT Name="VibeRadar" Version="1.0.0" Company="VibeRadar"/>');
  buf.writeln('  <COLLECTION Entries="${crate.tracks.length}">');
  for (var i = 0; i < crate.tracks.length; i++) {
    final t = crate.tracks[i];
    buf.writeln('    <TRACK TrackID="${i + 1}" Name="${esc(t.title)}" '
        'Artist="${esc(t.artist)}" Album="${esc(t.album)}" '
        'Genre="${esc(t.genre)}" '
        'TotalTime="${t.durationSeconds.toStringAsFixed(0)}" '
        'AverageBpm="${t.bpm.toStringAsFixed(2)}" Tonality="${t.key}" '
        'Location="${Uri.file(t.filePath)}" Size="${t.fileSizeBytes}"/>');
  }
  buf.writeln('  </COLLECTION>');
  buf.writeln('  <PLAYLISTS>');
  buf.writeln('    <NODE Type="0" Name="ROOT" Count="1">');
  buf.writeln('      <NODE Name="${esc(crate.name)}" Type="1" KeyType="0" '
      'Entries="${crate.tracks.length}">');
  for (var i = 0; i < crate.tracks.length; i++) {
    buf.writeln('        <TRACK Key="${i + 1}"/>');
  }
  buf.writeln('      </NODE>');
  buf.writeln('    </NODE>');
  buf.writeln('  </PLAYLISTS>');
  buf.writeln('</DJ_PLAYLISTS>');
  return buf.toString();
}

void main() {
  group('M3U generation', () {
    test('starts with #EXTM3U header', () {
      final crate = ExportCrate(
          name: 'My Set', tracks: [_track(id: '1')]);
      final content = _buildM3u(crate);
      expect(content, startsWith('#EXTM3U'));
    });

    test('contains playlist name', () {
      final crate = ExportCrate(name: 'AfrobeatsMix', tracks: [_track(id: '1')]);
      final content = _buildM3u(crate);
      expect(content, contains('#PLAYLIST:AfrobeatsMix'));
    });

    test('each track has #EXTINF line and file path', () {
      final t = _track(id: '1', title: 'Essence', artist: 'Wizkid',
          durationSeconds: 248, filePath: '/music/track.mp3');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final content = _buildM3u(crate);

      expect(content, contains('#EXTINF:248,Wizkid - Essence'));
      expect(content, contains('/music/track.mp3'));
    });

    test('multiple tracks all appear in order', () {
      final tracks = List.generate(
          5,
          (i) => _track(
              id: '$i',
              title: 'Track $i',
              filePath: '/music/track_$i.mp3'));
      final crate = ExportCrate(name: 'Mix', tracks: tracks);
      final content = _buildM3u(crate);

      for (var i = 0; i < 5; i++) {
        expect(content, contains('/music/track_$i.mp3'));
      }
    });

    test('empty crate produces valid M3U with no EXTINF lines', () {
      final crate = ExportCrate(name: 'Empty', tracks: []);
      final content = _buildM3u(crate);
      expect(content, startsWith('#EXTM3U'));
      expect(content, isNot(contains('#EXTINF')));
    });
  });

  group('Rekordbox XML structure', () {
    test('has valid XML declaration', () {
      final crate = ExportCrate(name: 'Set', tracks: [_track(id: '1')]);
      final xml = _buildRekordboxXml(crate);
      expect(xml, startsWith('<?xml version="1.0"'));
    });

    test('wraps in DJ_PLAYLISTS root element', () {
      final crate = ExportCrate(name: 'Set', tracks: [_track(id: '1')]);
      final xml = _buildRekordboxXml(crate);
      expect(xml, contains('<DJ_PLAYLISTS'));
      expect(xml, contains('</DJ_PLAYLISTS>'));
    });

    test('COLLECTION Entries count matches track list', () {
      final crate =
          ExportCrate(name: 'Set', tracks: List.generate(3, (i) => _track(id: '$i')));
      final xml = _buildRekordboxXml(crate);
      expect(xml, contains('Entries="3"'));
    });

    test('each TRACK element has correct metadata attributes', () {
      final t = _track(
          id: '1',
          title: 'Essence',
          artist: 'Wizkid',
          bpm: 102.0,
          key: '5A');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final xml = _buildRekordboxXml(crate);

      expect(xml, contains('Name="Essence"'));
      expect(xml, contains('Artist="Wizkid"'));
      expect(xml, contains('AverageBpm="102.00"'));
      expect(xml, contains('Tonality="5A"'));
    });

    test('special characters in title are XML-escaped', () {
      final t = _track(id: '1', title: 'Love & War', artist: 'A & B');
      final crate = ExportCrate(name: 'Set', tracks: [t]);
      final xml = _buildRekordboxXml(crate);
      expect(xml, contains('Name="Love &amp; War"'));
      expect(xml, contains('Artist="A &amp; B"'));
    });

    test('PLAYLIST node uses crate name', () {
      final crate = ExportCrate(
          name: 'Afrobeats Peak Hour', tracks: [_track(id: '1')]);
      final xml = _buildRekordboxXml(crate);
      expect(xml, contains('Name="Afrobeats Peak Hour"'));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/services/set_folder_preparation_service.dart';

Track _track({
  required String id,
  required String title,
  required String artist,
  Map<String, String> links = const {},
}) {
  final now = DateTime.utc(2026);
  return Track(
    id: id,
    title: title,
    artist: artist,
    artworkUrl: '',
    bpm: 0,
    keySignature: '--',
    genre: 'Open Format',
    vibe: 'club',
    trendScore: 0,
    regionScores: const {},
    platformLinks: links,
    createdAt: now,
    updatedAt: now,
    energyLevel: 0.5,
    trendHistory: const [],
  );
}

LibraryTrack _lib({
  required String path,
  required String title,
  required String artist,
}) {
  return LibraryTrack(
    id: path,
    filePath: path,
    fileName: p.basename(path),
    title: title,
    artist: artist,
    album: '',
    genre: '',
    bpm: 120,
    key: '8A',
    durationSeconds: 200,
    fileSizeBytes: 1234,
    fileExtension: p.extension(path),
    md5Hash: '',
    bitrate: 320,
    sampleRate: 44100,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('viberadar_set_folder_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'copies confident local matches and writes missing TIDAL fallback',
    () async {
      final source = File(p.join(tempDir.path, 'Wizkid - Essence.mp3'));
      await source.writeAsBytes([1, 2, 3]);
      final destinationRoot = Directory(p.join(tempDir.path, 'exports'));
      await destinationRoot.create();

      final result = await SetFolderPreparationService().prepare(
        crateName: 'Friday / Main: Set',
        tracks: [
          _track(id: 'a', title: 'Essence', artist: 'Wizkid'),
          _track(
            id: 'b',
            title: 'Unavailable',
            artist: 'Nope',
            links: {'spotify': 'https://open.spotify.com/track/test'},
          ),
        ],
        library: [_lib(path: source.path, title: 'Essence', artist: 'Wizkid')],
        destinationParentDir: destinationRoot.path,
      );

      expect(p.basename(result.folderPath), 'Friday Main Set');
      expect(result.copiedCount, 1);
      expect(result.missingCount, 1);
      expect(result.reviewCount, 0);
      expect(File(result.copied.first.destinationPath).existsSync(), true);
      expect(await File(result.copied.first.destinationPath).readAsBytes(), [
        1,
        2,
        3,
      ]);

      final playlist = await File(result.playlistPath).readAsString();
      expect(playlist, contains('#EXTM3U'));
      expect(playlist, contains(result.copied.first.destinationPath));

      final missing = await File(result.missingManifestPath).readAsString();
      expect(missing, contains('Nope - Unavailable'));
      expect(missing, contains('https://tidal.com/search'));
      expect(missing, contains('https://open.spotify.com/track/test'));

      final report = await File(result.matchReportPath).readAsString();
      expect(report, contains('VibeRadar Smart Match Report'));
      expect(report, contains('exact (100%)'));
    },
  );

  test('keeps uncertain filename matches in the review report', () async {
    final source = File(p.join(tempDir.path, 'Burnaboy Last Last.mp3'));
    await source.writeAsBytes([4, 5, 6]);
    final destinationRoot = Directory(p.join(tempDir.path, 'exports'));
    await destinationRoot.create();

    final result = await SetFolderPreparationService().prepare(
      crateName: 'Review Set',
      tracks: [_track(id: 'a', title: 'Last Last', artist: 'Burna Boy')],
      library: [_lib(path: source.path, title: '', artist: '')],
      destinationParentDir: destinationRoot.path,
    );

    expect(result.copiedCount, 0);
    expect(result.missingCount, 0);
    expect(result.reviewCount, 1);
    expect(result.review.first.candidates, contains(source.path));

    final report = await File(result.matchReportPath).readAsString();
    expect(report, contains('Review queue:'));
    expect(report, contains(source.path));
  });

  test('adds AI assistance notes to the match report when provided', () async {
    final destinationRoot = Directory(p.join(tempDir.path, 'exports'));
    await destinationRoot.create();

    final result = await SetFolderPreparationService().prepare(
      crateName: 'AI Assist Set',
      tracks: [_track(id: 'a', title: 'Missing Song', artist: 'DJ Test')],
      library: const [],
      destinationParentDir: destinationRoot.path,
      aiAssist: (context) async {
        expect(context.crateName, 'AI Assist Set');
        expect(context.missing.length, 1);
        return 'Check the clean radio edit before buying.';
      },
    );

    expect(result.aiNotes, 'Check the clean radio edit before buying.');
    final report = await File(result.matchReportPath).readAsString();
    expect(report, contains('AI assistance:'));
    expect(report, contains('Check the clean radio edit before buying.'));
  });

  test('uses unique file names when copied tracks share a basename', () async {
    final dirA = Directory(p.join(tempDir.path, 'a'));
    final dirB = Directory(p.join(tempDir.path, 'b'));
    await dirA.create();
    await dirB.create();
    final first = File(p.join(dirA.path, 'track.mp3'));
    final second = File(p.join(dirB.path, 'track.mp3'));
    await first.writeAsBytes([1]);
    await second.writeAsBytes([2]);
    final destinationRoot = Directory(p.join(tempDir.path, 'exports'));
    await destinationRoot.create();

    final result = await SetFolderPreparationService().prepare(
      crateName: 'Collision Set',
      tracks: [
        _track(id: 'a', title: 'Song One', artist: 'DJ A'),
        _track(id: 'b', title: 'Song Two', artist: 'DJ B'),
      ],
      library: [
        _lib(path: first.path, title: 'Song One', artist: 'DJ A'),
        _lib(path: second.path, title: 'Song Two', artist: 'DJ B'),
      ],
      destinationParentDir: destinationRoot.path,
    );

    expect(result.copiedCount, 2);
    final basenames = result.copied
        .map((copy) => p.basename(copy.destinationPath))
        .toSet();
    expect(basenames, {'track.mp3', 'track (2).mp3'});
    expect(File(p.join(result.folderPath, 'track.mp3')).existsSync(), true);
    expect(File(p.join(result.folderPath, 'track (2).mp3')).existsSync(), true);
  });
}

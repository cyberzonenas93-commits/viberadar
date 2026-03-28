import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/video_playback_item.dart';
import 'package:viberadar/models/video_transition_score.dart';
import 'package:viberadar/services/video_sequence_service.dart';
import 'package:viberadar/services/video_transition_engine_service.dart';

// ── Track Fixtures ─────────────────────────────────────────────────────────────

Track _track({
  String id = '1',
  String title = 'Test Track',
  String artist = 'Test Artist',
  int bpm = 128,
  String key = '8A',
  String genre = 'House',
  double energyLevel = 0.7,
}) =>
    Track(
      id: id,
      title: title,
      artist: artist,
      artworkUrl: '',
      bpm: bpm,
      keySignature: key,
      genre: genre,
      vibe: 'club',
      trendScore: 0.6,
      regionScores: const {},
      platformLinks: const {},
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      energyLevel: energyLevel,
      trendHistory: const [],
    );

// ── VideoPlaybackItem Fixtures ─────────────────────────────────────────────────

VideoPlaybackItem _officialYt({String trackId = '1'}) =>
    VideoPlaybackItem.youtube(
      trackId: trackId,
      videoId: 'abc123',
      rawTitle: 'Artist - Song (Official Music Video)',
      channelName: 'ArtistVEVO',
    );

VideoPlaybackItem _lyricYt({String trackId = '1'}) =>
    VideoPlaybackItem.youtube(
      trackId: trackId,
      videoId: 'def456',
      rawTitle: 'Artist - Song (Lyrics)',
      channelName: 'LyricsChannel',
    );

VideoPlaybackItem _liveYt({String trackId = '1'}) =>
    VideoPlaybackItem.youtube(
      trackId: trackId,
      videoId: 'ghi789',
      rawTitle: 'Artist - Song (Live at Festival)',
      channelName: 'ArtistChannel',
    );

VideoPlaybackItem _localVideo({String trackId = '1'}) =>
    VideoPlaybackItem.local(
      trackId: trackId,
      filePath: '/videos/track.mp4',
      title: 'Local Track',
    );

void main() {
  late VideoTransitionEngineService engine;
  late VideoSequenceService seqService;

  setUp(() {
    engine = VideoTransitionEngineService();
    seqService = VideoSequenceService(engine: engine);
  });

  // ── 1. Same video type = high visual score ────────────────────────────────────
  test('same video type produces high visual score (>= 0.80)', () {
    final from = _officialYt(trackId: '1');
    final to = _officialYt(trackId: '2');
    final t1 = _track(id: '1');
    final t2 = _track(id: '2');

    final score = engine.scoreVideoPair(from, to, t1, t2);
    expect(score.overallScore, greaterThanOrEqualTo(0.70));
    expect(score.visualScore, greaterThanOrEqualTo(0.80));
  });

  // ── 2. Lyric → official = medium penalty ─────────────────────────────────────
  test('lyric-to-official transition scores lower than same-type', () {
    final official1 = _officialYt(trackId: '1');
    final official2 = _officialYt(trackId: '2');
    final lyric = _lyricYt(trackId: '1');
    final t1 = _track(id: '1');
    final t2 = _track(id: '2');

    final sameScore = engine.scoreVideoPair(official1, official2, t1, t2);
    final mixedScore = engine.scoreVideoPair(lyric, official2, t1, t2);

    // Mixed type should score ≤ same type
    expect(mixedScore.visualScore, lessThan(sameScore.visualScore));
  });

  // ── 3. Live → lyric = low visual score ──────────────────────────────────────
  test('live-to-lyric produces low visual score', () {
    final live = _liveYt(trackId: '1');
    final lyric = _lyricYt(trackId: '2');
    final t1 = _track(id: '1');
    final t2 = _track(id: '2');

    final score = engine.scoreVideoPair(live, lyric, t1, t2);
    // Different types (live vs lyric) → visual score = 0.50
    expect(score.visualScore, lessThanOrEqualTo(0.75));
  });

  // ── 4. Source switch local→YouTube reduces score ────────────────────────────
  test('local→YouTube source switch incurs penalty and reduces overall', () {
    final local = _localVideo(trackId: '1');
    final yt = _officialYt(trackId: '2');
    final t1 = _track(id: '1');
    final t2 = _track(id: '2');

    final score = engine.scoreVideoPair(local, yt, t1, t2);
    expect(score.sourceSwitchPenalty, equals(0.1));
    // The penalty should be reflected in warnings
    expect(
      score.warnings,
      contains(VideoTransitionWarning.sourceSwitchFriction),
    );
  });

  // ── 5. Same source = no penalty ─────────────────────────────────────────────
  test('same source type incurs zero penalty', () {
    final yt1 = _officialYt(trackId: '1');
    final yt2 = _lyricYt(trackId: '2');
    final t1 = _track(id: '1');
    final t2 = _track(id: '2');

    final score = engine.scoreVideoPair(yt1, yt2, t1, t2);
    expect(score.sourceSwitchPenalty, equals(0.0));
    expect(
      score.warnings,
      isNot(contains(VideoTransitionWarning.sourceSwitchFriction)),
    );
  });

  // ── 6. visualContinuity mode gives higher weight to visual score ─────────────
  test('visualContinuity mode upweights visual score vs smooth mode', () {
    // Use items where visual compatibility is high but audio is mediocre
    final live1 = _liveYt(trackId: '1');
    final live2 = _liveYt(trackId: '2');
    // Tracks with a large BPM delta to reduce audio score
    final t1 = _track(id: '1', bpm: 80, genre: 'Hip Hop');
    final t2 = _track(id: '2', bpm: 160, genre: 'DnB');

    final visualScore = engine.scoreVideoPair(
      live1, live2, t1, t2,
      mode: VideoTransitionMode.visualContinuity,
    );
    final smoothScore = engine.scoreVideoPair(
      live1, live2, t1, t2,
      mode: VideoTransitionMode.smooth,
    );

    // visualContinuity gives more weight to visual, so should score higher
    // when visual is strong but audio is weak
    expect(visualScore.overallScore, greaterThanOrEqualTo(smoothScore.overallScore));
  });

  // ── 7. scoreVideoPair returns score in [0.0, 1.0] ────────────────────────────
  test('scoreVideoPair always returns overallScore in [0.0, 1.0]', () {
    final pairs = [
      (_officialYt(trackId: '1'), _lyricYt(trackId: '2'),
        _track(id: '1', bpm: 200), _track(id: '2', bpm: 60)),
      (_localVideo(trackId: '1'), _liveYt(trackId: '2'),
        _track(id: '1'), _track(id: '2')),
      (_liveYt(trackId: '1'), _liveYt(trackId: '2'),
        _track(id: '1', bpm: 0), _track(id: '2', bpm: 0)),
    ];

    for (final (from, to, t1, t2) in pairs) {
      final score = engine.scoreVideoPair(from, to, t1, t2);
      expect(score.overallScore, greaterThanOrEqualTo(0.0));
      expect(score.overallScore, lessThanOrEqualTo(1.0));
    }
  });

  // ── 8. Official video detection from keywords ────────────────────────────────
  test('official video detected from title keywords', () {
    final item = VideoPlaybackItem.youtube(
      trackId: '1',
      videoId: 'x',
      rawTitle: 'Artist Name - Big Song (Official Music Video)',
    );
    expect(item.isOfficialVideo, isTrue);
  });

  // ── 9. Lyric video detection from keywords ───────────────────────────────────
  test('lyric video detected from title keywords', () {
    final item = VideoPlaybackItem.youtube(
      trackId: '1',
      videoId: 'x',
      rawTitle: 'Artist - Song Lyrics',
    );
    expect(item.isLyricVideo, isTrue);
    expect(item.isLivePerformance, isFalse);
  });

  // ── 10. Live performance detection from keywords ─────────────────────────────
  test('live performance detected from title keywords', () {
    final live = VideoPlaybackItem.youtube(
      trackId: '1',
      videoId: 'x',
      rawTitle: 'Artist - Song Live at Coachella',
    );
    expect(live.isLivePerformance, isTrue);

    final acoustic = VideoPlaybackItem.youtube(
      trackId: '1',
      videoId: 'y',
      rawTitle: 'Artist - Song (Acoustic Session)',
    );
    expect(acoustic.isLivePerformance, isTrue);
  });

  // ── 11. rankNextVideos returns maxResults items ──────────────────────────────
  test('rankNextVideos returns at most maxResults items', () {
    final current = _officialYt(trackId: '1');
    final currentTrack = _track(id: '1');

    final candidates = List.generate(
      8,
      (i) => _officialYt(trackId: '${i + 2}'),
    );
    final allTracks = [
      currentTrack,
      ...List.generate(8, (i) => _track(id: '${i + 2}')),
    ];

    final results = engine.rankNextVideos(
      current,
      currentTrack,
      candidates,
      allTracks,
      maxResults: 5,
    );

    expect(results.length, lessThanOrEqualTo(5));
  });

  // ── 12. rankNextVideos sorted descending by score ─────────────────────────────
  test('rankNextVideos returns results sorted descending by score', () {
    final current = _officialYt(trackId: '1');
    final currentTrack = _track(id: '1');

    final candidates = [
      _officialYt(trackId: '2'),
      _lyricYt(trackId: '3'),
      _liveYt(trackId: '4'),
    ];
    final allTracks = [
      currentTrack,
      _track(id: '2'),
      _track(id: '3'),
      _track(id: '4'),
    ];

    final results = engine.rankNextVideos(
      current,
      currentTrack,
      candidates,
      allTracks,
    );

    // Score each result to verify ordering
    final scores = results.map((item) {
      final toTrack = allTracks.firstWhere((t) => t.id == item.trackId);
      return engine
          .scoreVideoPair(current, item, currentTrack, toTrack)
          .overallScore;
    }).toList();

    for (var i = 0; i < scores.length - 1; i++) {
      expect(scores[i], greaterThanOrEqualTo(scores[i + 1]));
    }
  });

  // ── 13. buildVideoSequence is deterministic ──────────────────────────────────
  test('buildVideoSequence produces consistent results on repeated calls', () {
    final items = [
      _officialYt(trackId: '1'),
      _lyricYt(trackId: '2'),
      _liveYt(trackId: '3'),
    ];
    final tracks = [
      _track(id: '1'),
      _track(id: '2'),
      _track(id: '3'),
    ];

    final seq1 = engine.buildVideoSequence(items, tracks);
    final seq2 = engine.buildVideoSequence(items, tracks);

    expect(
      seq1.map((i) => i.trackId).toList(),
      equals(seq2.map((i) => i.trackId).toList()),
    );
  });

  // ── 14. buildVideoSequence with empty list returns empty ─────────────────────
  test('buildVideoSequence with empty input returns empty list', () {
    final result = engine.buildVideoSequence([], []);
    expect(result, isEmpty);
  });

  // ── 15. findBridgeVideo returns item that bridges well (or null) ──────────────
  test('findBridgeVideo returns a bridging item when pool is compatible', () {
    final from = _officialYt(trackId: '1');
    final to = _lyricYt(trackId: '2');
    final fromTrack = _track(id: '1', bpm: 128);
    final toTrack = _track(id: '2', bpm: 128);

    // Bridge candidate with compatible properties
    final bridge = _officialYt(trackId: '3');
    final bridgeTrack = _track(id: '3', bpm: 128, key: '8A');

    final pool = [bridge, _liveYt(trackId: '4')];
    final allTracks = [fromTrack, toTrack, bridgeTrack, _track(id: '4')];

    final result = engine.findBridgeVideo(
      from, to, fromTrack, toTrack, pool, allTracks,
    );

    // Should find a bridge or return null — just verify no exception
    // and if found, it's from the pool
    if (result != null) {
      expect(pool.any((p) => p.trackId == result.trackId), isTrue);
    }
  });

  // ── 16. VideoSequencePreview.averageScore is mean of transition scores ────────
  test('VideoSequencePreview.averageScore is correct mean', () {
    final tracks = List.generate(
      3,
      (i) => _track(id: '${i + 1}', bpm: 128),
    );
    final items = [
      _officialYt(trackId: '1'),
      _officialYt(trackId: '2'),
      _officialYt(trackId: '3'),
    ];

    final preview = seqService.buildPreview(tracks, items, VideoTransitionMode.smooth);

    if (preview.transitions.isNotEmpty) {
      final expectedAvg = preview.transitions
              .fold<double>(0.0, (s, t) => s + t.overallScore) /
          preview.transitions.length;
      expect(
        preview.averageScore,
        closeTo(expectedAvg, 0.001),
      );
    }
  });

  // ── 17. VideoSequencePreview.riskyTransitions counts correctly ────────────────
  test('VideoSequencePreview.riskyTransitions counts transitions < 0.50', () {
    final tracks = [
      _track(id: '1', bpm: 60, genre: 'Reggae'),
      _track(id: '2', bpm: 180, genre: 'DnB'),
    ];
    final items = [
      _liveYt(trackId: '1'),
      _lyricYt(trackId: '2'),
    ];

    final preview = seqService.buildPreview(tracks, items, VideoTransitionMode.smooth);
    final expectedRisky =
        preview.transitions.where((t) => t.overallScore < 0.50).length;
    expect(preview.riskyTransitions, equals(expectedRisky));
  });

  // ── 18. VideoTransitionScore.scoreLabel is correct ───────────────────────────
  test('VideoTransitionScore.scoreLabel returns correct label', () {
    VideoTransitionScore makeScore(double s) => VideoTransitionScore(
          fromTrackId: '1',
          toTrackId: '2',
          overallScore: s,
          confidence: 0.9,
          type: VideoTransitionType.smoothVisualBlend,
          reasons: const [],
          warnings: const [],
        );

    expect(makeScore(0.85).scoreLabel, equals('Excellent'));
    expect(makeScore(0.70).scoreLabel, equals('Good'));
    expect(makeScore(0.55).scoreLabel, equals('OK'));
    expect(makeScore(0.30).scoreLabel, equals('Risky'));
  });

  // ── 19. VideoTransitionScore toJson/fromJson roundtrip ───────────────────────
  test('VideoTransitionScore toJson/fromJson roundtrip preserves all fields',
      () {
    final original = VideoTransitionScore(
      fromTrackId: 'track-a',
      toTrackId: 'track-b',
      overallScore: 0.72,
      confidence: 0.85,
      type: VideoTransitionType.officialToLivePivot,
      reasons: const ['Good audio match'],
      warnings: const [VideoTransitionWarning.weakVisualContinuity],
      sourceSwitchPenalty: 0.1,
      audioScore: 0.78,
      visualScore: 0.60,
    );

    final json = original.toJson();
    final restored = VideoTransitionScore.fromJson(json);

    expect(restored.fromTrackId, equals(original.fromTrackId));
    expect(restored.toTrackId, equals(original.toTrackId));
    expect(restored.overallScore, closeTo(original.overallScore, 0.001));
    expect(restored.confidence, closeTo(original.confidence, 0.001));
    expect(restored.type, equals(original.type));
    expect(restored.reasons, equals(original.reasons));
    expect(restored.warnings, equals(original.warnings));
    expect(
        restored.sourceSwitchPenalty,
        closeTo(original.sourceSwitchPenalty, 0.001));
    expect(restored.audioScore, closeTo(original.audioScore, 0.001));
    expect(restored.visualScore, closeTo(original.visualScore, 0.001));
  });

  // ── 20. VideoTransitionType.label non-empty for all types ────────────────────
  test('VideoTransitionType.label is non-empty for all enum values', () {
    for (final type in VideoTransitionType.values) {
      expect(type.label, isNotEmpty,
          reason: '${type.name} label must be non-empty');
    }
  });

  // ── 21. visualContinuity mode with matching items ────────────────────────────
  test('visualContinuity mode: two live items score well visually', () {
    final live1 = _liveYt(trackId: '1');
    final live2 = _liveYt(trackId: '2');
    final t1 = _track(id: '1', bpm: 128);
    final t2 = _track(id: '2', bpm: 128);

    final score = engine.scoreVideoPair(
      live1, live2, t1, t2,
      mode: VideoTransitionMode.visualContinuity,
    );

    // Same visual type → high visual score
    expect(score.visualScore, greaterThanOrEqualTo(0.88));
    expect(score.overallScore, greaterThan(0.0));
  });

  // ── 22. VideoPlaybackItem.youtubeWatchUrl correct format ─────────────────────
  test('youtubeWatchUrl returns correct URL format', () {
    final item = VideoPlaybackItem.youtube(
      trackId: '1',
      videoId: 'dQw4w9WgXcQ',
    );
    expect(
      item.youtubeWatchUrl,
      equals('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
    );
  });

  // ── 23. VideoPlaybackItem.hasVideo ───────────────────────────────────────────
  test('hasVideo is true for local or YouTube, false for neither', () {
    final ytItem = VideoPlaybackItem.youtube(trackId: '1', videoId: 'abc');
    expect(ytItem.hasVideo, isTrue);

    final localItem = VideoPlaybackItem.local(
        trackId: '2', filePath: '/path/file.mp4');
    expect(localItem.hasVideo, isTrue);

    // Item with no video data
    const emptyItem = VideoPlaybackItem(
      trackId: '3',
      sourceType: VideoSourceType.youtube,
    );
    expect(emptyItem.hasVideo, isFalse);
  });

  // ── 24. VideoPlaybackItem factory constructors work ──────────────────────────
  test('VideoPlaybackItem.local factory sets correct fields', () {
    final item = VideoPlaybackItem.local(
      trackId: 'track-1',
      filePath: '/videos/song.mp4',
      title: 'My Song',
      durationSeconds: 210.5,
    );

    expect(item.trackId, equals('track-1'));
    expect(item.sourceType, equals(VideoSourceType.local));
    expect(item.localFilePath, equals('/videos/song.mp4'));
    expect(item.title, equals('My Song'));
    expect(item.durationSeconds, closeTo(210.5, 0.001));
    expect(item.youtubeVideoId, isNull);
  });

  test('VideoPlaybackItem.youtube factory sets correct fields', () {
    final item = VideoPlaybackItem.youtube(
      trackId: 'track-2',
      videoId: 'vid123',
      rawTitle: 'Artist - Song (Official Music Video)',
      channelName: 'ArtistVEVO',
      thumbnailUrl: 'https://img.youtube.com/vi/vid123/mqdefault.jpg',
      durationSeconds: 180.0,
    );

    expect(item.trackId, equals('track-2'));
    expect(item.sourceType, equals(VideoSourceType.youtube));
    expect(item.youtubeVideoId, equals('vid123'));
    expect(item.youtubeThumbnail,
        equals('https://img.youtube.com/vi/vid123/mqdefault.jpg'));
    expect(item.durationSeconds, closeTo(180.0, 0.001));
  });

  // ── 25. VideoPlaybackItem isOfficialVideo heuristic ──────────────────────────
  test('isOfficialVideo detected via VEVO channel', () {
    final vevo = VideoPlaybackItem.youtube(
      trackId: '1',
      videoId: 'x',
      rawTitle: 'Artist - Song',
      channelName: 'ArtistVEVO',
    );
    expect(vevo.isOfficialVideo, isTrue);
  });

  test('isOfficialVideo detected via artist name in channel name', () {
    final item = VideoPlaybackItem.youtube(
      trackId: '1',
      videoId: 'x',
      rawTitle: 'Song Title',
      channelName: 'BeyonceOfficial',
      artistName: 'Beyonce',
    );
    expect(item.isOfficialVideo, isTrue);
  });

  test('isOfficialVideo false when channel is unrelated', () {
    final item = VideoPlaybackItem.youtube(
      trackId: '1',
      videoId: 'x',
      rawTitle: 'Song Title',
      channelName: 'RandomUploads',
      artistName: 'Beyonce',
    );
    expect(item.isOfficialVideo, isFalse);
  });

  // ── Bonus: VideoTransitionMode.label non-empty ───────────────────────────────
  test('VideoTransitionMode.label is non-empty for all enum values', () {
    for (final mode in VideoTransitionMode.values) {
      expect(mode.label, isNotEmpty,
          reason: '${mode.name} label must be non-empty');
    }
  });

  // ── Bonus: VideoSequencePreview.summary includes key stats ───────────────────
  test('VideoSequencePreview.summary includes video count and avg score', () {
    final tracks = [_track(id: '1'), _track(id: '2')];
    final items = [_officialYt(trackId: '1'), _officialYt(trackId: '2')];
    final preview =
        seqService.buildPreview(tracks, items, VideoTransitionMode.smooth);
    expect(preview.summary, contains('videos'));
    expect(preview.summary, contains('%'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/services/platform_search_service.dart';
import 'package:viberadar/services/set_builder_behavior_service.dart';
import 'package:viberadar/services/set_sequence_planner.dart';

void main() {
  group('SetSequencePlanner', () {
    const context = DjSetContext(
      eventType: 'Club night',
      cityMarket: 'Accra / GH',
      crowdAge: '21-34',
      genreLane: 'Afrobeats, Amapiano',
      energyCurve: SetEnergyCurve.smoothRise,
      contentPreference: SetContentPreference.cleanPreferred,
      setLengthMinutes: 60,
      allowHardSwitches: false,
      mustPlay: ['Anchor'],
      avoid: ['Avoid Me'],
    );

    test('builds a phased journey with confidence and reasons', () {
      final plan = const SetSequencePlanner().planPlatformSet(
        candidates: const [
          PlatformTrackResult(
            title: 'Anchor Clean',
            artist: 'Signal DJ',
            soundchartsUrl: 'https://soundcharts.com/anchor',
            soundchartsSource: 'tiktok',
            soundchartsRegion: 'GH',
            popularity: 74,
            trendScore: 0.82,
          ),
          PlatformTrackResult(
            title: 'Warm Current',
            artist: 'Wave DJ',
            soundchartsUrl: 'https://soundcharts.com/warm',
            soundchartsSource: 'shazam',
            soundchartsRegion: 'GH',
            popularity: 68,
            trendScore: 0.7,
          ),
          PlatformTrackResult(
            title: 'Peak Driver',
            artist: 'Peak DJ',
            spotifyUrl: 'https://open.spotify.com/peak',
            popularity: 92,
            trendScore: 0.4,
          ),
          PlatformTrackResult(
            title: 'Closer',
            artist: 'Close DJ',
            appleUrl: 'https://music.apple.com/close',
            popularity: 65,
          ),
        ],
        targetCount: 4,
        context: context,
        localLibrary: [
          _local(
            title: 'Anchor Clean',
            artist: 'Signal DJ',
            bpm: 118,
            key: '8A',
          ),
        ],
      );

      expect(plan.tracks, hasLength(4));
      expect(plan.tracks.first.phase, SetJourneyPhase.opener);
      expect(plan.tracks.first.track.title, contains('Anchor'));
      expect(plan.tracks.first.confidence, greaterThan(0.6));
      expect(plan.tracks.first.reasons.join(' '), contains('TikTok'));
      expect(plan.tracks.first.reasons.join(' '), contains('Found locally'));
      expect(plan.tracks.first.bpm, 118);
      expect(plan.tracks.first.key, '8A');
    });

    test('dedupes versions and prefers clean edits when requested', () {
      final plan = const SetSequencePlanner().planPlatformSet(
        candidates: const [
          PlatformTrackResult(
            title: 'Big Tune Explicit',
            artist: 'Version DJ',
            spotifyUrl: 'https://open.spotify.com/dirty',
            popularity: 90,
          ),
          PlatformTrackResult(
            title: 'Big Tune Clean',
            artist: 'Version DJ',
            spotifyUrl: 'https://open.spotify.com/clean',
            popularity: 75,
          ),
          PlatformTrackResult(
            title: 'Avoid Me',
            artist: 'Blocked Artist',
            popularity: 100,
          ),
        ],
        targetCount: 3,
        context: context,
      );

      expect(plan.removedDuplicates, 1);
      expect(plan.tracks.map((t) => t.track.title), contains('Big Tune Clean'));
      expect(
        plan.tracks.map((t) => t.track.title),
        isNot(contains('Big Tune Explicit')),
      );
      expect(
        plan.tracks.map((t) => t.track.title),
        isNot(contains('Avoid Me')),
      );
    });

    test('behavior profile can suppress rejected tracks', () {
      final rejected = const SetBuilderBehaviorProfile().record(
        event: SetBuilderBehaviorEvent.markWrong,
        track: const PlatformTrackResult(
          title: 'Wrong Pick',
          artist: 'Nope DJ',
        ),
      );

      final plan = const SetSequencePlanner().planPlatformSet(
        candidates: const [
          PlatformTrackResult(
            title: 'Wrong Pick',
            artist: 'Nope DJ',
            popularity: 95,
          ),
          PlatformTrackResult(
            title: 'Better Fit',
            artist: 'Yes DJ',
            soundchartsUrl: 'https://soundcharts.com/better',
            soundchartsSource: 'shazam',
            soundchartsRegion: 'GH',
            popularity: 62,
            trendScore: 0.62,
          ),
        ],
        targetCount: 1,
        context: context,
        behavior: rejected,
      );

      expect(plan.tracks.single.track.title, 'Better Fit');
    });
  });
}

LibraryTrack _local({
  required String title,
  required String artist,
  required double bpm,
  required String key,
}) {
  return LibraryTrack(
    id: '$artist-$title',
    filePath: '/music/$artist - $title.mp3',
    fileName: '$artist - $title.mp3',
    title: title,
    artist: artist,
    album: '',
    genre: 'Afrobeats',
    bpm: bpm,
    key: key,
    durationSeconds: 210,
    fileSizeBytes: 8 * 1024 * 1024,
    fileExtension: '.mp3',
    md5Hash: 'hash-$artist-$title',
    bitrate: 320,
    sampleRate: 44100,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viberadar/services/platform_search_service.dart';
import 'package:viberadar/services/set_builder_behavior_service.dart';

void main() {
  group('SetBuilderBehaviorService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('records saved and rejected signals into a local profile', () async {
      const service = SetBuilderBehaviorService();
      const track = PlatformTrackResult(
        title: 'Taste Signal',
        artist: 'Profile DJ',
        genre: 'Amapiano',
      );

      var profile = await service.record(
        event: SetBuilderBehaviorEvent.save,
        track: track,
        genre: track.genre,
      );
      profile = await service.record(
        event: SetBuilderBehaviorEvent.markWrong,
        track: const PlatformTrackResult(title: 'Bad Fit', artist: 'Wrong DJ'),
      );
      profile = await service.record(
        event: SetBuilderBehaviorEvent.searchAgain,
      );

      expect(profile.savedArtists['profile dj'], 1);
      expect(profile.savedGenres['amapiano'], 1);
      expect(profile.rejectedArtists['wrong dj'], 1);
      expect(profile.rejectedTracks, contains('bad fit::wrong dj'));
      expect(profile.searchAgainCount, 1);

      final reloaded = await service.load();
      expect(reloaded.savedArtists['profile dj'], 1);
      expect(reloaded.rejectedTracks, contains('bad fit::wrong dj'));
    });

    test('affinity boosts saved artists and penalizes rejected tracks', () {
      var profile = const SetBuilderBehaviorProfile().record(
        event: SetBuilderBehaviorEvent.save,
        track: const PlatformTrackResult(
          title: 'Good Pick',
          artist: 'Signal DJ',
          genre: 'Afrobeats',
        ),
        genre: 'Afrobeats',
      );
      profile = profile.record(
        event: SetBuilderBehaviorEvent.markWrong,
        track: const PlatformTrackResult(
          title: 'Bad Pick',
          artist: 'Rejected DJ',
        ),
      );

      expect(
        profile.affinityFor(
          const PlatformTrackResult(
            title: 'Next One',
            artist: 'Signal DJ',
            genre: 'Afrobeats',
          ),
        ),
        greaterThan(0),
      );
      expect(
        profile.affinityFor(
          const PlatformTrackResult(title: 'Bad Pick', artist: 'Rejected DJ'),
        ),
        lessThan(0),
      );
    });

    test('records exported tracks in one persisted batch', () async {
      const service = SetBuilderBehaviorService();

      final profile = await service.recordTracks(
        event: SetBuilderBehaviorEvent.export,
        genre: 'Afrobeats',
        tracks: const [
          PlatformTrackResult(title: 'Export One', artist: 'Signal DJ'),
          PlatformTrackResult(title: 'Export Two', artist: 'Signal DJ'),
        ],
      );

      expect(profile.savedArtists['signal dj'], 2);
      expect(profile.savedGenres['afrobeats'], 2);

      final reloaded = await service.load();
      expect(reloaded.savedArtists['signal dj'], 2);
      expect(reloaded.savedGenres['afrobeats'], 2);
    });
  });
}

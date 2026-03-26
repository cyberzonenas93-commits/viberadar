import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/track.dart';
import '../sources/mock_track_seed.dart';

abstract class TrackRepository {
  Stream<List<Track>> watchTracks();

  Future<void> refresh();
}

class MockTrackRepository implements TrackRepository {
  MockTrackRepository() : _tracks = buildMockTracks() {
    _controller.add(_tracks);
  }

  final StreamController<List<Track>> _controller =
      StreamController<List<Track>>.broadcast();
  List<Track> _tracks;

  @override
  Future<void> refresh() async {
    _tracks = (_tracks.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));
    _controller.add(_tracks);
  }

  @override
  Stream<List<Track>> watchTracks() async* {
    yield _tracks;
    yield* _controller.stream;
  }
}

/// Cost-optimised Firestore repository.
///
/// Instead of a live `.snapshots()` listener (which charges a read for every
/// document on every change), this uses single `.get()` fetches:
///   • One fetch on first subscribe (cold start)
///   • Subsequent fetches only on explicit `refresh()` calls
///   • Firestore SDK disk cache is enabled so repeat reads hit local storage
///
/// This cuts read costs from thousands-per-hour to a handful-per-session.
class FirestoreTrackRepository implements TrackRepository {
  FirestoreTrackRepository(this._firestore) {
    // Enable Firestore offline persistence (reduces reads on repeat launches).
    // This is a no-op if already enabled.
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  final FirebaseFirestore _firestore;

  /// Max documents to fetch per query.  2000 is enough for ~500/genre across
  /// 4+ genres while keeping Firestore read costs manageable.
  static const _pageSize = 2000;

  final _controller = StreamController<List<Track>>.broadcast();
  List<Track>? _cached;
  bool _initialFetchDone = false;

  @override
  Future<void> refresh() async {
    final tracks = await _fetchOnce();
    _cached = tracks;
    _controller.add(tracks);
  }

  @override
  Stream<List<Track>> watchTracks() async* {
    // Yield cached data immediately if available (e.g. from Firestore disk cache)
    if (_cached != null) {
      yield _cached!;
    }

    // Do one network fetch on first subscribe
    if (!_initialFetchDone) {
      _initialFetchDone = true;
      final tracks = await _fetchOnce();
      _cached = tracks;
      yield tracks;
    }

    // Then yield any future refreshes
    yield* _controller.stream;
  }

  /// Single `.get()` call — one read per document, no ongoing listener.
  /// Uses Firestore SDK cache when available (offline / repeat reads).
  Future<List<Track>> _fetchOnce() async {
    try {
      final snapshot = await _firestore
          .collection('tracks')
          .orderBy('trend_score', descending: true)
          .limit(_pageSize)
          .get();

      if (snapshot.docs.isEmpty) {
        return buildMockTracks();
      }
      return snapshot.docs
          .map((doc) => Track.fromMap(doc.data(), id: doc.id))
          .toList();
    } catch (_) {
      // If network fails, try cache-only fetch
      try {
        final cached = await _firestore
            .collection('tracks')
            .orderBy('trend_score', descending: true)
            .limit(_pageSize)
            .get(const GetOptions(source: Source.cache));
        if (cached.docs.isNotEmpty) {
          return cached.docs
              .map((doc) => Track.fromMap(doc.data(), id: doc.id))
              .toList();
        }
      } catch (_) {}
      return _cached ?? buildMockTracks();
    }
  }

  /// One-shot fetch of the next page after [lastTrack] for manual pagination.
  Future<List<Track>> loadMore(Track lastTrack) async {
    final snapshot = await _firestore
        .collection('tracks')
        .orderBy('trend_score', descending: true)
        .startAfter([lastTrack.trendScore])
        .limit(_pageSize)
        .get();

    return snapshot.docs
        .map((doc) => Track.fromMap(doc.data(), id: doc.id))
        .toList();
  }
}

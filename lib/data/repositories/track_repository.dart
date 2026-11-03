import 'dart:async';
import 'dart:developer' as developer;

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

class EmptyTrackRepository implements TrackRepository {
  const EmptyTrackRepository();

  @override
  Future<void> refresh() async {}

  @override
  Stream<List<Track>> watchTracks() => Stream.value(const <Track>[]);
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
  Future<List<Track>>? _fetchInFlight;

  @override
  Future<void> refresh() async {
    final tracks = await _fetchFreshOnce();
    _cached = tracks;
    _controller.add(tracks);
  }

  @override
  Stream<List<Track>> watchTracks() async* {
    // Yield memory cache immediately for same-session subscribers.
    if (_cached != null) {
      yield _cached!;
    } else {
      final cached = await _fetchFromDiskCache();
      if (cached.isNotEmpty) {
        _cached = cached;
        yield cached;
      }
    }

    // Do one server fetch on first subscribe, shared across all listeners.
    if (!_initialFetchDone) {
      _initialFetchDone = true;
      scheduleMicrotask(() => unawaited(refresh()));
    }

    // Then yield the first server refresh and any later explicit refreshes.
    yield* _controller.stream;
  }

  Future<List<Track>> _fetchFreshOnce() {
    final inFlight = _fetchInFlight;
    if (inFlight != null) return inFlight;

    final fetch = _fetchOnce().whenComplete(() => _fetchInFlight = null);
    _fetchInFlight = fetch;
    return fetch;
  }

  Future<List<Track>> _fetchFromDiskCache() async {
    try {
      final cached = await _firestore
          .collection('tracks')
          .orderBy('trend_score', descending: true)
          .limit(_pageSize)
          .get(const GetOptions(source: Source.cache));

      if (cached.docs.isEmpty) return const <Track>[];

      return cached.docs
          .map((doc) => Track.fromMap(doc.data(), id: doc.id))
          .toList();
    } catch (_) {
      return const <Track>[];
    }
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

      if (snapshot.docs.isEmpty) return const <Track>[];

      return snapshot.docs
          .map((doc) => Track.fromMap(doc.data(), id: doc.id))
          .toList();
    } catch (error, stackTrace) {
      // Network/permission/index error — log it (don't swallow silently) and
      // fall back to the Firestore disk cache, then to the last good result.
      developer.log(
        'Firestore tracks fetch failed; falling back to cache.',
        name: 'TrackRepository',
        error: error,
        stackTrace: stackTrace,
      );
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
      } catch (cacheError) {
        developer.log(
          'Firestore cache-only fetch also failed.',
          name: 'TrackRepository',
          error: cacheError,
        );
      }
      return _cached ?? const <Track>[];
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

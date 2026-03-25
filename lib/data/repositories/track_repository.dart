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

class FirestoreTrackRepository implements TrackRepository {
  FirestoreTrackRepository(this._firestore);

  final FirebaseFirestore _firestore;
  static const _pageSize = 500;

  @override
  Future<void> refresh() async {}

  /// Returns a real-time stream backed by Firestore .snapshots().
  ///
  /// • Falls back to mock data only while Firestore is truly empty (i.e.
  ///   ingestion hasn't run yet).
  /// • Once Firestore has data the stream emits live updates automatically
  ///   whenever the Cloud Function writes new documents.
  @override
  Stream<List<Track>> watchTracks() {
    return _firestore
        .collection('tracks')
        .orderBy('trend_score', descending: true)
        .limit(_pageSize)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            // Ingestion hasn't populated Firestore yet — show mock data
            // so the UI isn't blank on first launch.
            return buildMockTracks();
          }
          return snapshot.docs
              .map((doc) => Track.fromMap(doc.data(), id: doc.id))
              .toList();
        });
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

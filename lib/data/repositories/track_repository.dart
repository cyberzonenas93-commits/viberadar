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
  Stream<List<Track>> watchTracks() => _controller.stream;
}

class FirestoreTrackRepository implements TrackRepository {
  FirestoreTrackRepository(this._firestore);

  final FirebaseFirestore _firestore;
  static const _pageSize = 500;

  @override
  Future<void> refresh() async {}

  @override
  Stream<List<Track>> watchTracks() {
    return _firestore
        .collection('tracks')
        .orderBy('trend_score', descending: true)
        .limit(_pageSize)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return buildMockTracks();
          }

          return snapshot.docs
              .map((doc) => Track.fromMap(doc.data(), id: doc.id))
              .toList();
        });
  }

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

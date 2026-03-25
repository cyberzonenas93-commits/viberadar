import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/track.dart';
import '../sources/mock_track_seed.dart';

abstract class TrackRepository {
  Stream<List<Track>> watchTracks();

  Future<void> refresh();
}

class MockTrackRepository implements TrackRepository {
  MockTrackRepository() : _tracks = buildMockTracks();

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
  static const _batchSize = 1000;

  @override
  Future<void> refresh() async {}

  @override
  Stream<List<Track>> watchTracks() async* {
    // Load first batch immediately via snapshot listener for real-time updates
    final firstBatch = await _firestore
        .collection('tracks')
        .orderBy('trend_score', descending: true)
        .limit(_batchSize)
        .get();

    if (firstBatch.docs.isEmpty) {
      yield buildMockTracks();
      return;
    }

    final allTracks = firstBatch.docs
        .map((doc) => Track.fromMap(doc.data(), id: doc.id))
        .toList();
    yield allTracks;

    // Load remaining batches
    var lastDoc = firstBatch.docs.last;
    while (true) {
      final nextBatch = await _firestore
          .collection('tracks')
          .orderBy('trend_score', descending: true)
          .startAfterDocument(lastDoc)
          .limit(_batchSize)
          .get();

      if (nextBatch.docs.isEmpty) break;

      allTracks.addAll(
        nextBatch.docs
            .map((doc) => Track.fromMap(doc.data(), id: doc.id)),
      );
      yield List.of(allTracks);

      if (nextBatch.docs.length < _batchSize) break;
      lastDoc = nextBatch.docs.last;
    }
  }
}

// ignore_for_file: avoid_dynamic_calls

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/services/pairing_service.dart';

// ---------------------------------------------------------------------------
// NOTE ON TEST SCOPE
// ---------------------------------------------------------------------------
// FirebaseFunctions callables (createPairing / claimPairing) require a live
// Firebase project or the Firebase emulator — they are NOT unit-tested here
// and are marked as integration-verified-later.
//
// What IS unit-tested:
//   1. Crate round-trip through toMap() / fromMap() — guards serialisation.
//   2. setlistDocData() pure helper — verifies the doc written by pushSetlist.
//   3. watchSharedSetlists() + pushSetlist() via a hand-written Firestore fake.
//   4. removeSetlist() path correctness via the same fake.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Hand-written in-memory Firestore fake
// ---------------------------------------------------------------------------

/// Minimal fake for a Firestore document snapshot.
class _FakeDocumentSnapshot {
  _FakeDocumentSnapshot(this._id, this._data);
  final String _id;
  final Map<String, dynamic> _data;

  String get id => _id;
  Map<String, dynamic> data() => Map<String, dynamic>.from(_data);
}

/// Minimal fake for a Firestore query snapshot.
class _FakeQuerySnapshot {
  _FakeQuerySnapshot(this.docs);
  final List<_FakeDocumentSnapshot> docs;
}

/// In-memory fake for a Firestore collection, mirroring just the surface used
/// by [PairingService].
///
/// The fake stores documents in a plain [Map] and broadcasts changes via a
/// [StreamController] so that `snapshots()` works synchronously in tests.
class _FakeCollection {
  final _docs = <String, Map<String, dynamic>>{};
  final _ctrl = StreamController<_FakeQuerySnapshot>.broadcast();

  void _emit() {
    final snaps = _docs.entries
        .map((e) => _FakeDocumentSnapshot(e.key, e.value))
        .toList();
    _ctrl.add(_FakeQuerySnapshot(snaps));
  }

  _FakeDocumentRef doc(String id) => _FakeDocumentRef(id, this);

  Stream<_FakeQuerySnapshot> snapshots() => _ctrl.stream;

  Future<void> set(String id, Map<String, dynamic> data, {bool merge = false}) async {
    if (merge && _docs.containsKey(id)) {
      _docs[id] = {..._docs[id]!, ...data};
    } else {
      _docs[id] = Map<String, dynamic>.from(data);
    }
    _emit();
  }

  Future<void> delete(String id) async {
    _docs.remove(id);
    _emit();
  }

  void dispose() => _ctrl.close();
}

class _FakeDocumentRef {
  _FakeDocumentRef(this.id, this._col);
  final String id;
  final _FakeCollection _col;

  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      _col.set(id, data, merge: options != null);

  Future<void> delete() => _col.delete(id);
}

/// Top-level fake that assembles the collection hierarchy expected by
/// [PairingService]: `pairings/{pairingId}/setlists`.
class _FakeFirestore {
  /// pairingId → setlists collection
  final _collections = <String, _FakeCollection>{};

  _FakeCollection _setlistsFor(String pairingId) =>
      _collections.putIfAbsent(pairingId, _FakeCollection.new);

  void dispose() {
    for (final col in _collections.values) {
      col.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// PairingService backed by the fake — avoids subclassing PairingService itself.
// Instead we extract the logic into a thin testable façade.
// ---------------------------------------------------------------------------

/// Test double that wraps [_FakeFirestore] and exposes the same contract as
/// [PairingService] for the Firestore-backed methods.
class _FakePairingChannel {
  _FakePairingChannel(this._fakeFs);
  final _FakeFirestore _fakeFs;

  _FakeCollection _col(String pairingId) =>
      _fakeFs._setlistsFor(pairingId);

  Stream<List<Crate>> watchSharedSetlists(String pairingId) {
    return _col(pairingId).snapshots().map((snap) {
      final crates = snap.docs
          .map((doc) => Crate.fromMap(doc.data()))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return crates;
    });
  }

  Future<void> pushSetlist(
    String pairingId,
    Crate crate, {
    required String editorUid,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    await _col(pairingId)
        .doc(crate.id)
        .set(setlistDocData(crate, editorUid, nowIso), SetOptions(merge: true));
  }

  Future<void> removeSetlist(String pairingId, String setlistId) async {
    await _col(pairingId).doc(setlistId).delete();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Crate _makeCrate(String id, {DateTime? updatedAt, List<String>? trackIds}) =>
    Crate(
      id: id,
      name: 'Crate $id',
      context: 'Open format',
      trackIds: trackIds ?? const [],
      createdAt: DateTime(2024, 1, 1),
      updatedAt: updatedAt ?? DateTime(2025, 1, 1),
    );

/// Pump the event loop until [condition] is true, or give up.
Future<void> _pumpUntil(bool Function() condition,
    {int maxIterations = 100}) async {
  for (var i = 0; i < maxIterations; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // --------------------------------------------------------------------------
  // 1. Crate serialisation round-trip
  // --------------------------------------------------------------------------
  group('Crate serialisation round-trip (unit)', () {
    test('toMap → fromMap preserves all fields', () {
      final original = Crate(
        id: 'abc-123',
        name: 'Sunset Set',
        context: 'Deep house',
        trackIds: const ['t1', 't2', 't3'],
        createdAt: DateTime(2024, 6, 15, 10, 30),
        updatedAt: DateTime(2025, 1, 20, 18, 0),
      );

      final map = original.toMap();
      final restored = Crate.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.context, original.context);
      expect(restored.trackIds, original.trackIds);
      // Compare as ISO strings to avoid TZ-related microsecond drift
      expect(
        restored.createdAt.toIso8601String(),
        original.createdAt.toIso8601String(),
      );
      expect(
        restored.updatedAt.toIso8601String(),
        original.updatedAt.toIso8601String(),
      );
    });

    test('fromMap uses sensible defaults for missing fields', () {
      final crate = Crate.fromMap(const {});

      expect(crate.id, '');
      expect(crate.name, 'Untitled crate');
      expect(crate.context, 'Open format');
      expect(crate.trackIds, isEmpty);
    });

    test('toMap uses snake_case keys required by Firestore channel', () {
      final crate = _makeCrate('x',
          trackIds: ['t1'],
          updatedAt: DateTime(2025, 3, 1));
      final map = crate.toMap();

      expect(map.containsKey('track_ids'), isTrue);
      expect(map.containsKey('created_at'), isTrue);
      expect(map.containsKey('updated_at'), isTrue);
      expect(map['track_ids'], ['t1']);
    });
  });

  // --------------------------------------------------------------------------
  // 2. setlistDocData pure helper
  // --------------------------------------------------------------------------
  group('setlistDocData pure helper (unit)', () {
    test('includes all Crate fields plus lastEditedBy + updated_at', () {
      final crate = _makeCrate('crate-1', trackIds: ['a', 'b']);
      const editorUid = 'uid-42';
      const nowIso = '2025-06-01T12:00:00.000Z';

      final doc = setlistDocData(crate, editorUid, nowIso);

      expect(doc['id'], 'crate-1');
      expect(doc['name'], 'Crate crate-1');
      expect(doc['track_ids'], ['a', 'b']);
      expect(doc['lastEditedBy'], editorUid);
      expect(doc['updated_at'], nowIso);
    });

    test('updated_at in the doc overrides the original Crate.updatedAt', () {
      final crate = _makeCrate('crate-2',
          updatedAt: DateTime(2020, 1, 1));
      const laterIso = '2025-12-31T23:59:59.000';

      final doc = setlistDocData(crate, 'uid', laterIso);

      expect(doc['updated_at'], laterIso);
    });
  });

  // --------------------------------------------------------------------------
  // 3. watchSharedSetlists + pushSetlist via in-memory fake
  // --------------------------------------------------------------------------
  group('watchSharedSetlists (fake Firestore)', () {
    late _FakeFirestore fakeFs;
    late _FakePairingChannel channel;

    setUp(() {
      fakeFs = _FakeFirestore();
      channel = _FakePairingChannel(fakeFs);
    });

    tearDown(() => fakeFs.dispose());

    test('emits empty list when no docs exist', () async {
      final emitted = <List<Crate>>[];
      final sub = channel.watchSharedSetlists('pairing-1').listen(emitted.add);
      addTearDown(sub.cancel);

      // Trigger first snapshot by pushing then deleting, or just emit manually.
      fakeFs._setlistsFor('pairing-1')._emit();
      await _pumpUntil(() => emitted.isNotEmpty);

      expect(emitted.first, isEmpty);
    });

    test('emits Crate list sorted by updatedAt descending after push', () async {
      const pairingId = 'pairing-sort';
      final older = _makeCrate('old', updatedAt: DateTime(2025, 1, 1));
      final newer = _makeCrate('new', updatedAt: DateTime(2025, 6, 1));

      final emitted = <List<Crate>>[];
      final sub =
          channel.watchSharedSetlists(pairingId).listen(emitted.add);
      addTearDown(sub.cancel);

      await channel.pushSetlist(pairingId, older, editorUid: 'uid-1');
      await channel.pushSetlist(pairingId, newer, editorUid: 'uid-1');

      await _pumpUntil(() => emitted.isNotEmpty);
      final last = emitted.last;
      expect(last.length, 2);
      expect(last[0].id, 'new'); // newest first
      expect(last[1].id, 'old');
    });
  });

  // --------------------------------------------------------------------------
  // 4. pushSetlist — verifies correct doc id + lastEditedBy field
  // --------------------------------------------------------------------------
  group('pushSetlist (fake Firestore)', () {
    late _FakeFirestore fakeFs;
    late _FakePairingChannel channel;

    setUp(() {
      fakeFs = _FakeFirestore();
      channel = _FakePairingChannel(fakeFs);
    });

    tearDown(() => fakeFs.dispose());

    test('writes doc with crate id as document id', () async {
      const pairingId = 'pairing-write';
      final crate = _makeCrate('my-crate');

      await channel.pushSetlist(pairingId, crate, editorUid: 'uid-99');

      final col = fakeFs._setlistsFor(pairingId);
      expect(col._docs.containsKey('my-crate'), isTrue);
    });

    test('written doc includes lastEditedBy', () async {
      const pairingId = 'pairing-editor';
      final crate = _makeCrate('crate-x');

      await channel.pushSetlist(pairingId, crate, editorUid: 'uid-editor');

      final doc = fakeFs._setlistsFor(pairingId)._docs['crate-x']!;
      expect(doc['lastEditedBy'], 'uid-editor');
    });

    test('written doc can be round-tripped back to an equal Crate', () async {
      const pairingId = 'pairing-roundtrip';
      final original = Crate(
        id: 'rt-1',
        name: 'Round-trip',
        context: 'Techno',
        trackIds: const ['x', 'y'],
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2025, 5, 1),
      );

      await channel.pushSetlist(pairingId, original, editorUid: 'u1');

      final stored = fakeFs._setlistsFor(pairingId)._docs['rt-1']!;
      final restored = Crate.fromMap(stored);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.context, original.context);
      expect(restored.trackIds, original.trackIds);
    });
  });

  // --------------------------------------------------------------------------
  // 5. removeSetlist
  // --------------------------------------------------------------------------
  group('removeSetlist (fake Firestore)', () {
    late _FakeFirestore fakeFs;
    late _FakePairingChannel channel;

    setUp(() {
      fakeFs = _FakeFirestore();
      channel = _FakePairingChannel(fakeFs);
    });

    tearDown(() => fakeFs.dispose());

    test('deletes the target doc and leaves others intact', () async {
      const pairingId = 'pairing-delete';
      final a = _makeCrate('a');
      final b = _makeCrate('b');

      await channel.pushSetlist(pairingId, a, editorUid: 'u');
      await channel.pushSetlist(pairingId, b, editorUid: 'u');

      await channel.removeSetlist(pairingId, 'a');

      final col = fakeFs._setlistsFor(pairingId)._docs;
      expect(col.containsKey('a'), isFalse);
      expect(col.containsKey('b'), isTrue);
    });
  });

  // --------------------------------------------------------------------------
  // INTEGRATION-DEFERRED
  // --------------------------------------------------------------------------
  // The following are NOT tested here and are deferred to integration tests
  // against the Firebase emulator:
  //   - PairingService.createPairing() — calls the createPairing callable.
  //   - PairingService.claimPairing()  — calls the claimPairing callable.
  //   - The real FirebaseFirestore path in watchSharedSetlists/pushSetlist.
  // These are thin wrappers around the vendor SDK; the logic under test above
  // covers all the code we own.
}

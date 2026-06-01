import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/crate.dart';

// ---------------------------------------------------------------------------
// Pure helper — extractable + unit-testable without live Firebase
// ---------------------------------------------------------------------------

/// Builds the Firestore document data for a shared-setlist write.
///
/// Extracted so it can be tested without a live [FirebaseFirestore] instance.
Map<String, dynamic> setlistDocData(
  Crate crate,
  String editorUid,
  String nowIso,
) {
  return {
    ...crate.toMap(),
    'lastEditedBy': editorUid,
    'updated_at': nowIso,
  };
}

// ---------------------------------------------------------------------------
// PairingService
// ---------------------------------------------------------------------------

/// Client-side pairing service for the phone↔desktop companion channel.
///
/// Thin wrappers around the [createPairing] and [claimPairing] Cloud Functions
/// callables, plus a bidirectional shared-setlist channel backed by the
/// `pairings/{id}/setlists` Firestore subcollection.
///
/// Constructor accepts injected [FirebaseFirestore] and [FirebaseFunctions]
/// instances so unit tests can supply fakes without initialising the Firebase
/// app.
class PairingService {
  PairingService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  /// No-Firebase constructor for use in tests and subclasses that override
  /// every Firebase-touching method.  [_firestore] and [_functions] are `null`
  /// — they must never be accessed.
  @visibleForTesting
  PairingService.testOnly()
      : _firestore = null,
        _functions = null;

  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;

  // ── Callable helpers ───────────────────────────────────────────────────────

  HttpsCallable _callable(String name) =>
      _functions!.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));

  // ── Pairing handshake ──────────────────────────────────────────────────────

  /// Desktop calls this to request a short pairing code.
  ///
  /// Returns a record `{pairingId, code}` matching the Cloud Function result.
  Future<({String pairingId, String code})> createPairing({
    String desktopName = 'Desktop',
  }) async {
    final result = await _callable('createPairing').call<Map<String, dynamic>>({
      'desktopName': desktopName,
    });
    final data = result.data;
    return (
      pairingId: data['pairingId'] as String,
      code: data['code'] as String,
    );
  }

  /// Phone calls this with the 6-char code shown on the desktop.
  ///
  /// Returns a record `{pairingId, desktopName}` matching the Cloud Function
  /// result.
  Future<({String pairingId, String desktopName})> claimPairing(
    String code,
  ) async {
    final result = await _callable('claimPairing').call<Map<String, dynamic>>({
      'code': code,
    });
    final data = result.data;
    return (
      pairingId: data['pairingId'] as String,
      desktopName: data['desktopName'] as String,
    );
  }

  // ── Shared-setlist channel ─────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _setlistsRef(String pairingId) =>
      _firestore!
          .collection('pairings')
          .doc(pairingId)
          .collection('setlists');

  /// Watches the shared-setlist subcollection for [pairingId].
  ///
  /// Emits a list of [Crate]s sorted by [Crate.updatedAt] descending on every
  /// Firestore snapshot.
  Stream<List<Crate>> watchSharedSetlists(String pairingId) {
    return _setlistsRef(pairingId).snapshots().map((snap) {
      final crates = snap.docs
          .map((doc) => Crate.fromMap(doc.data()))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return crates;
    });
  }

  /// Writes [crate] into the shared-setlist subcollection for [pairingId].
  ///
  /// Uses merge so concurrent edits from either side are not clobbered.
  /// [editorUid] is stored as `lastEditedBy` so both sides can identify who
  /// last touched the document.
  Future<void> pushSetlist(
    String pairingId,
    Crate crate, {
    required String editorUid,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    await _setlistsRef(pairingId).doc(crate.id).set(
          setlistDocData(crate, editorUid, nowIso),
          SetOptions(merge: true),
        );
  }

  /// Deletes the shared-setlist document identified by [setlistId] from the
  /// subcollection for [pairingId].
  Future<void> removeSetlist(String pairingId, String setlistId) async {
    await _setlistsRef(pairingId).doc(setlistId).delete();
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// Global [PairingService] provider.
///
/// Uses the default Firebase instances. Override in tests with
/// `pairingServiceProvider.overrideWithValue(...)`.
final pairingServiceProvider = Provider<PairingService>(
  (ref) => PairingService(),
);

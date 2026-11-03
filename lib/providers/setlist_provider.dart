import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/crate.dart';
import '../models/crate_track.dart';
import '../models/session_state.dart';
import '../models/track.dart';
import '../services/crate_export_planner.dart';
import '../services/pairing_service.dart';
import 'app_state.dart';
import 'paired_computer_provider.dart';
import 'repositories.dart';

/// All of the signed-in user's setlists (Crates), newest first.
final setlistsProvider = Provider<List<Crate>>((ref) {
  final crates = ref.watch(userProfileProvider).value?.savedCrates ?? const [];
  return [...crates]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});

final setlistActionsProvider = Provider<SetlistActions>(
  (ref) => SetlistActions(ref),
);

/// Appends [incoming] to [existing], skipping entries whose stableKey already
/// appears. Pure — exposed for unit testing.
List<CrateTrack> mergeTracks(
  List<CrateTrack> existing,
  List<CrateTrack> incoming,
) {
  final seen = existing.map((t) => t.stableKey).toSet();
  final out = [...existing];
  for (final t in incoming) {
    if (seen.add(t.stableKey)) out.add(t);
  }
  return out;
}

class SetlistActions {
  SetlistActions(this._ref);
  final Ref _ref;

  Future<void> save(Crate crate) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null || !session.isAuthenticated) return;
    final saved = crate.copyWith(updatedAt: DateTime.now());
    await _ref
        .read(userRepositoryProvider)
        .saveCrate(
          userId: session.userId,
          fallbackName: session.displayName,
          crate: saved,
        );
    await _pushToPairedComputer(saved, session);
  }

  Future<void> _pushToPairedComputer(Crate crate, SessionState session) async {
    if (session.isDemo == true) return;
    final paired = _ref.read(pairedComputerProvider);
    if (paired == null) return;
    try {
      await _ref
          .read(pairingServiceProvider)
          .pushSetlist(paired.pairingId, crate, editorUid: session.userId);
    } catch (_) {
      // Account persistence is authoritative. Pairing is a convenience bridge
      // for pickup on a specific computer and may be offline or revoked.
    }
  }

  Future<void> create(String name) {
    final now = DateTime.now();
    return save(
      Crate(
        id: const Uuid().v4(),
        name: name,
        context: 'Custom setlist',
        tracks: const [],
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> createWithTrack(String name, String trackId) {
    final now = DateTime.now();
    return save(
      Crate(
        id: const Uuid().v4(),
        name: name,
        context: 'Custom setlist',
        tracks: [CrateTrack.reference(trackId)],
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Creates a setlist seeded with [track], captured as a self-contained rich
  /// entry (title/artist/bpm/links) so it survives the track decaying out of the
  /// live feed and is exportable on the desktop. Prefer this over
  /// [createWithTrack] wherever the full [Track] is in hand.
  Future<void> createWithResolvedTrack(String name, Track track) {
    final now = DateTime.now();
    return save(
      Crate(
        id: const Uuid().v4(),
        name: name,
        context: 'Custom setlist',
        tracks: [crateTrackFromTrack(track)],
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Appends a library track (by id, resolved from the tracks stream).
  Future<void> addTrack(Crate setlist, String trackId) =>
      addTracks(setlist, [CrateTrack.reference(trackId)]);

  /// Appends [track] as a self-contained rich entry. Prefer over [addTrack]
  /// wherever the full [Track] is available (keeps the crate decay-proof and
  /// exportable).
  Future<void> addResolvedTrack(Crate setlist, Track track) =>
      addTracks(setlist, [crateTrackFromTrack(track)]);

  /// Appends rich entries (e.g. AI-resolved songs), de-duplicated by stableKey.
  Future<void> addTracks(Crate setlist, List<CrateTrack> tracks) {
    final merged = mergeTracks(setlist.tracks, tracks);
    if (merged.length == setlist.tracks.length) return Future.value();
    return save(setlist.copyWith(tracks: merged));
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/crate.dart';
import 'app_state.dart';
import 'repositories.dart';

/// All of the signed-in user's setlists (Crates), newest first.
final setlistsProvider = Provider<List<Crate>>((ref) {
  final crates = ref.watch(userProfileProvider).value?.savedCrates ?? const [];
  return [...crates]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});

final setlistActionsProvider =
    Provider<SetlistActions>((ref) => SetlistActions(ref));

class SetlistActions {
  SetlistActions(this._ref);
  final Ref _ref;

  Future<void> save(Crate crate) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null || !session.isAuthenticated) return;
    await _ref.read(userRepositoryProvider).saveCrate(
          userId: session.userId,
          fallbackName: session.displayName,
          crate: crate.copyWith(updatedAt: DateTime.now()),
        );
  }

  Future<void> create(String name) {
    final now = DateTime.now();
    return save(Crate(
      id: const Uuid().v4(),
      name: name,
      context: 'Open format',
      trackIds: const [],
      createdAt: now,
      updatedAt: now,
    ));
  }
}

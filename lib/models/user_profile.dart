import 'crate.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.preferredRegion,
    required this.watchlist,
    required this.savedCrates,
  });

  factory UserProfile.empty({
    required String id,
    required String displayName,
    String preferredRegion = 'US',
  }) {
    return UserProfile(
      id: id,
      displayName: displayName,
      preferredRegion: preferredRegion,
      watchlist: const <String>{},
      savedCrates: const <Crate>[],
    );
  }

  final String id;
  final String displayName;
  final String preferredRegion;
  final Set<String> watchlist;
  final List<Crate> savedCrates;

  UserProfile copyWith({
    String? displayName,
    String? preferredRegion,
    Set<String>? watchlist,
    List<Crate>? savedCrates,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      preferredRegion: preferredRegion ?? this.preferredRegion,
      watchlist: watchlist ?? this.watchlist,
      savedCrates: savedCrates ?? this.savedCrates,
    );
  }

  factory UserProfile.fromMap(
    String id,
    Map<String, dynamic>? map, {
    required String fallbackName,
  }) {
    if (map == null) {
      return UserProfile.empty(id: id, displayName: fallbackName);
    }

    return UserProfile(
      id: id,
      displayName: map['display_name'] as String? ?? fallbackName,
      preferredRegion:
          (map['preferences'] as Map?)?['region'] as String? ?? 'US',
      watchlist: Set<String>.from(map['watchlist'] as List? ?? const []),
      savedCrates: (map['saved_crates'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Crate.fromMap(Map<String, dynamic>.from(item.cast())))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'display_name': displayName,
      'preferences': {'region': preferredRegion},
      'watchlist': watchlist.toList(),
      'saved_crates': savedCrates.map((crate) => crate.toMap()).toList(),
    };
  }
}

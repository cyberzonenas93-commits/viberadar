import 'crate_track.dart';

class Crate {
  const Crate({
    required this.id,
    required this.name,
    required this.context,
    required this.tracks,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String context;
  final List<CrateTrack> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Legacy read-only view used by exporters/desktop that still think in ids.
  List<String> get trackIds => tracks.map((t) => t.stableKey).toList();

  Crate copyWith({
    String? name,
    String? context,
    List<CrateTrack>? tracks,
    DateTime? updatedAt,
  }) {
    return Crate(
      id: id,
      name: name ?? this.name,
      context: context ?? this.context,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'context': context,
      'tracks': tracks.map((t) => t.toMap()).toList(),
      // Mirror for any unmodified legacy/desktop reader.
      'track_ids': tracks.map((t) => t.stableKey).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Crate.fromMap(Map<String, dynamic> map) {
    final rich = map['tracks'] as List?;
    final List<CrateTrack> tracks;
    if (rich != null && rich.isNotEmpty) {
      tracks = rich
          .map((e) => CrateTrack.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      tracks = List<String>.from(
        map['track_ids'] as List? ?? const [],
      ).map(CrateTrack.reference).toList();
    }
    final rawContext = map['context'] as String? ?? 'Custom setlist';
    final context = rawContext.trim().toLowerCase() == 'open format'
        ? 'Custom setlist'
        : rawContext;
    return Crate(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Untitled crate',
      context: context,
      tracks: tracks,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

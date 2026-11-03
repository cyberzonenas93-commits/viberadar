class Crate {
  const Crate({
    required this.id,
    required this.name,
    required this.context,
    required this.trackIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String context;
  final List<String> trackIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'context': context,
      'track_ids': trackIds,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Crate.fromMap(Map<String, dynamic> map) {
    return Crate(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Untitled crate',
      context: map['context'] as String? ?? 'Open format',
      trackIds: List<String>.from(map['track_ids'] as List? ?? const []),
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

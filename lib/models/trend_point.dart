class TrendPoint {
  const TrendPoint({required this.label, required this.score});

  final String label;
  final double score;

  factory TrendPoint.fromMap(Map<String, dynamic> map) {
    return TrendPoint(
      label: map['label'] as String? ?? '',
      score: (map['score'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {'label': label, 'score': score};
  }
}

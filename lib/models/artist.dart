class Artist {
  const Artist({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.genres,
    required this.country,
    required this.bio,
    required this.trendScore,
    required this.monthlyListeners,
    required this.verified,
    required this.topTrackIds,
  });

  final String id;
  final String name;
  final String imageUrl;
  final String country;
  final String bio;
  final List<String> genres;
  final double trendScore;
  final int monthlyListeners;
  final bool verified;
  final List<String> topTrackIds;

  String get initials =>
      name.split(' ').map((w) => w[0]).take(2).join().toUpperCase();
}

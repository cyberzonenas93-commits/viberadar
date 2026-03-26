import 'package:cloud_firestore/cloud_firestore.dart';

class SocialProfile {
  const SocialProfile({
    required this.userId,
    required this.displayName,
    this.bio = '',
    this.photoUrl = '',
    this.genres = const [],
    this.location = '',
    this.socialLinks = const {},
    this.uploadCount = 0,
    this.followerCount = 0,
    this.followingCount = 0,
    this.createdAt,
    this.updatedAt,
    this.role = 'DJ',
  });

  final String userId;
  final String displayName;
  final String bio;
  final String photoUrl;
  final List<String> genres;
  final String location;
  final Map<String, String> socialLinks;
  final int uploadCount;
  final int followerCount;
  final int followingCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String role; // DJ, MC, Producer, Artist

  factory SocialProfile.empty() => SocialProfile(userId: '', displayName: 'Anonymous');

  SocialProfile copyWith({
    String? displayName, String? bio, String? photoUrl,
    List<String>? genres, String? location, Map<String, String>? socialLinks,
    int? uploadCount, int? followerCount, int? followingCount, String? role,
  }) => SocialProfile(
    userId: userId,
    displayName: displayName ?? this.displayName,
    bio: bio ?? this.bio,
    photoUrl: photoUrl ?? this.photoUrl,
    genres: genres ?? this.genres,
    location: location ?? this.location,
    socialLinks: socialLinks ?? this.socialLinks,
    uploadCount: uploadCount ?? this.uploadCount,
    followerCount: followerCount ?? this.followerCount,
    followingCount: followingCount ?? this.followingCount,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    role: role ?? this.role,
  );

  factory SocialProfile.fromMap(Map<String, dynamic> map, {String? id}) => SocialProfile(
    userId: id ?? map['userId'] as String? ?? '',
    displayName: map['displayName'] as String? ?? 'Anonymous',
    bio: map['bio'] as String? ?? '',
    photoUrl: map['photoUrl'] as String? ?? '',
    genres: (map['genres'] as List?)?.cast<String>() ?? const [],
    location: map['location'] as String? ?? '',
    socialLinks: Map<String, String>.from(map['socialLinks'] as Map? ?? {}),
    uploadCount: (map['uploadCount'] as num?)?.toInt() ?? 0,
    followerCount: (map['followerCount'] as num?)?.toInt() ?? 0,
    followingCount: (map['followingCount'] as num?)?.toInt() ?? 0,
    createdAt: _parseDate(map['createdAt']),
    updatedAt: _parseDate(map['updatedAt']),
    role: map['role'] as String? ?? 'DJ',
  );

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'displayName': displayName,
    'bio': bio,
    'photoUrl': photoUrl,
    'genres': genres,
    'location': location,
    'socialLinks': socialLinks,
    'uploadCount': uploadCount,
    'followerCount': followerCount,
    'followingCount': followingCount,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'role': role,
  };

  static DateTime? _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}

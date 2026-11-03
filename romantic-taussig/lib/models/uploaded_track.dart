import 'package:cloud_firestore/cloud_firestore.dart';

class UploadedTrack {
  const UploadedTrack({
    required this.id,
    required this.title,
    required this.artistName,
    required this.audioUrl,
    this.artworkUrl = '',
    this.genre = '',
    this.bpm = 0,
    this.keySignature = '',
    required this.uploadedBy,
    required this.uploaderName,
    required this.uploadedAt,
    this.likeCount = 0,
    this.playCount = 0,
    this.featured = false,
    this.durationSeconds = 0,
    this.tags = const [],
    this.uploaderPhotoUrl = '',
  });

  final String id;
  final String title;
  final String artistName;
  final String audioUrl;
  final String artworkUrl;
  final String genre;
  final int bpm;
  final String keySignature;
  final String uploadedBy;
  final String uploaderName;
  final DateTime uploadedAt;
  final int likeCount;
  final int playCount;
  final bool featured;
  final double durationSeconds;
  final List<String> tags;
  final String uploaderPhotoUrl;

  factory UploadedTrack.fromMap(Map<String, dynamic> map, {String? id}) => UploadedTrack(
    id: id ?? map['id'] as String? ?? '',
    title: map['title'] as String? ?? 'Untitled',
    artistName: map['artistName'] as String? ?? 'Unknown',
    audioUrl: map['audioUrl'] as String? ?? '',
    artworkUrl: map['artworkUrl'] as String? ?? '',
    genre: map['genre'] as String? ?? '',
    bpm: (map['bpm'] as num?)?.toInt() ?? 0,
    keySignature: map['keySignature'] as String? ?? '',
    uploadedBy: map['uploadedBy'] as String? ?? '',
    uploaderName: map['uploaderName'] as String? ?? '',
    uploadedAt: _parseDate(map['uploadedAt']),
    likeCount: (map['likeCount'] as num?)?.toInt() ?? 0,
    playCount: (map['playCount'] as num?)?.toInt() ?? 0,
    featured: map['featured'] as bool? ?? false,
    durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 0,
    tags: (map['tags'] as List?)?.cast<String>() ?? const [],
    uploaderPhotoUrl: map['uploaderPhotoUrl'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'artistName': artistName,
    'audioUrl': audioUrl,
    'artworkUrl': artworkUrl,
    'genre': genre,
    'bpm': bpm,
    'keySignature': keySignature,
    'uploadedBy': uploadedBy,
    'uploaderName': uploaderName,
    'uploadedAt': uploadedAt,
    'likeCount': likeCount,
    'playCount': playCount,
    'featured': featured,
    'durationSeconds': durationSeconds,
    'tags': tags,
    'uploaderPhotoUrl': uploaderPhotoUrl,
  };

  String get durationFormatted {
    final m = (durationSeconds / 60).floor();
    final s = (durationSeconds % 60).floor();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(uploadedAt);
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  static DateTime _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.now();
  }
}

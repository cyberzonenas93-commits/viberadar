import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/social_profile.dart';
import '../models/uploaded_track.dart';
import 'app_state.dart';

final _db = FirebaseFirestore.instance;
final _storage = FirebaseStorage.instance;
final _functions = FirebaseFunctions.instance;

// ── Social Profile ──────────────────────────────────────────────────────────

final myProfileProvider = StreamProvider<SocialProfile>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null || !session.isAuthenticated) {
    return Stream.value(SocialProfile.empty());
  }
  return _db
      .collection('social_profiles')
      .doc(session.userId)
      .snapshots()
      .map(
        (snap) => snap.exists
            ? SocialProfile.fromMap(snap.data()!, id: snap.id)
            : SocialProfile(
                userId: session.userId,
                displayName: session.displayName,
              ),
      );
});

final profileProvider = StreamProvider.family<SocialProfile, String>((
  ref,
  userId,
) {
  return _db
      .collection('social_profiles')
      .doc(userId)
      .snapshots()
      .map(
        (snap) => snap.exists
            ? SocialProfile.fromMap(snap.data()!, id: snap.id)
            : SocialProfile(userId: userId, displayName: 'Unknown'),
      );
});

Future<void> updateProfile(SocialProfile profile) async {
  await _db
      .collection('social_profiles')
      .doc(profile.userId)
      .set(profile.toMap(), SetOptions(merge: true));
}

Future<List<SocialProfile>> searchProfiles(
  String query, {
  int limit = 30,
}) async {
  // Firestore doesn't support full-text search, so we use prefix matching on displayName
  final snap = await _db
      .collection('social_profiles')
      .orderBy('displayName')
      .startAt([query.toUpperCase()])
      .endAt(['${query.toLowerCase()}\uf8ff'])
      .limit(limit)
      .get();
  return snap.docs
      .map((d) => SocialProfile.fromMap(d.data(), id: d.id))
      .toList();
}

Future<List<SocialProfile>> getTopProfiles({int limit = 50}) async {
  final snap = await _db
      .collection('social_profiles')
      .orderBy('followerCount', descending: true)
      .limit(limit)
      .get();
  return snap.docs
      .map((d) => SocialProfile.fromMap(d.data(), id: d.id))
      .toList();
}

// ── Uploads ─────────────────────────────────────────────────────────────────

final recentUploadsProvider = StreamProvider<List<UploadedTrack>>((ref) {
  return _db
      .collection('uploads')
      .where('moderationStatus', isEqualTo: 'approved')
      .orderBy('uploadedAt', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => UploadedTrack.fromMap(d.data(), id: d.id))
            .toList(),
      );
});

final featuredUploadsProvider = StreamProvider<List<UploadedTrack>>((ref) {
  return _db
      .collection('uploads')
      .where('moderationStatus', isEqualTo: 'approved')
      .where('featured', isEqualTo: true)
      .orderBy('likeCount', descending: true)
      .limit(30)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => UploadedTrack.fromMap(d.data(), id: d.id))
            .toList(),
      );
});

final userUploadsProvider = StreamProvider.family<List<UploadedTrack>, String>((
  ref,
  userId,
) {
  final session = ref.watch(sessionProvider).value;
  final ownProfile = session?.userId == userId;
  var query = _db.collection('uploads').where('uploadedBy', isEqualTo: userId);
  if (!ownProfile) {
    query = query.where('moderationStatus', isEqualTo: 'approved');
  }
  return query
      .orderBy('uploadedAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => UploadedTrack.fromMap(d.data(), id: d.id))
            .toList(),
      );
});

String newUploadId() => _db.collection('uploads').doc().id;

Future<String> uploadAudio({
  required String userId,
  required String uploadId,
  required String filePath,
  required String fileName,
  void Function(double)? onProgress,
}) async {
  final ref = _storage.ref(
    'uploads/$userId/$uploadId/audio_${_safeStorageName(fileName)}',
  );
  final task = ref.putFile(
    File(filePath),
    SettableMetadata(contentType: _audioContentType(fileName)),
  );
  if (onProgress != null) {
    task.snapshotEvents.listen((snap) {
      if (snap.totalBytes > 0) {
        onProgress(snap.bytesTransferred / snap.totalBytes);
      }
    });
  }
  await task;
  return ref.fullPath;
}

Future<String> uploadArtwork({
  required String userId,
  required String uploadId,
  required String filePath,
}) async {
  final ref = _storage.ref(
    'artwork/$userId/$uploadId/artwork_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await ref.putFile(
    File(filePath),
    SettableMetadata(contentType: 'image/jpeg'),
  );
  return ref.fullPath;
}

Future<String> uploadProfilePhoto({
  required String userId,
  required String filePath,
}) async {
  final ref = _storage.ref(
    'profile_photos/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await ref.putFile(
    File(filePath),
    SettableMetadata(contentType: 'image/jpeg'),
  );
  return await ref.getDownloadURL();
}

String _audioContentType(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'mp3' => 'audio/mpeg',
    'm4a' || 'mp4' => 'audio/mp4',
    'aac' => 'audio/aac',
    'wav' => 'audio/wav',
    'flac' => 'audio/flac',
    'ogg' => 'audio/ogg',
    'aiff' || 'aif' => 'audio/aiff',
    _ => 'audio/mpeg',
  };
}

Future<UploadedTrack> createUpload(UploadedTrack track) async {
  if (track.id.isEmpty) {
    final doc = await _db.collection('uploads').add(track.toMap());
    return UploadedTrack.fromMap(track.toMap(), id: doc.id);
  }

  await _db.collection('uploads').doc(track.id).set(track.toMap());
  return UploadedTrack.fromMap(track.toMap(), id: track.id);
}

Future<void> deleteUpload(String uploadId) async {
  await _db.collection('uploads').doc(uploadId).delete();
}

Future<String> resolveCommunityMediaUrl(String reference) async {
  if (reference.isEmpty) return '';
  if (reference.startsWith('http://') || reference.startsWith('https://')) {
    return reference;
  }
  if (reference.startsWith('gs://')) {
    return _storage.refFromURL(reference).getDownloadURL();
  }
  return _storage.ref(reference).getDownloadURL();
}

String _safeStorageName(String fileName) {
  final cleaned = fileName
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'upload' : cleaned;
}

// ── Follows ─────────────────────────────────────────────────────────────────

final followingIdsProvider = StreamProvider<Set<String>>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null || !session.isAuthenticated) return Stream.value({});
  return _db
      .collection('follows')
      .where('followerId', isEqualTo: session.userId)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => d.data()['followeeId'] as String).toSet(),
      );
});

Future<void> followUser(String followerId, String followeeId) async {
  final docId = '${followerId}_$followeeId';
  await _db.collection('follows').doc(docId).set({
    'followerId': followerId,
    'followeeId': followeeId,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

Future<void> unfollowUser(String followerId, String followeeId) async {
  final docId = '${followerId}_$followeeId';
  await _db.collection('follows').doc(docId).delete();
}

// ── Moderation: Reports ───────────────────────────────────────────────────────

/// Writes a moderation report to the `reports` collection. [contentType] is
/// either 'upload' or 'profile'; [contentId] is the upload id or the profile
/// uid; [reportedUid] is the uid of the user who owns the content.
Future<void> reportContent({
  required String reportedBy,
  required String contentType,
  required String contentId,
  required String reportedUid,
  required String reason,
}) async {
  await _db.collection('reports').add({
    'reportedBy': reportedBy,
    'contentType': contentType,
    'contentId': contentId,
    'reportedUid': reportedUid,
    'reason': reason,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

// ── Moderation: Blocks ────────────────────────────────────────────────────────

/// Stream of uids the current user has blocked. Used to filter blocked users'
/// uploads and profiles out of community feeds and discovery.
final blockedUidsProvider = StreamProvider<Set<String>>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null || !session.isAuthenticated) return Stream.value({});
  return _db
      .collection('blocks')
      .where('blockerUid', isEqualTo: session.userId)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => d.data()['blockedUid'] as String).toSet(),
      );
});

Future<void> blockUser(String blockerUid, String blockedUid) async {
  final docId = '${blockerUid}_$blockedUid';
  await _db.collection('blocks').doc(docId).set({
    'blockerUid': blockerUid,
    'blockedUid': blockedUid,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

Future<void> unblockUser(String blockerUid, String blockedUid) async {
  final docId = '${blockerUid}_$blockedUid';
  await _db.collection('blocks').doc(docId).delete();
}

// ── Likes ───────────────────────────────────────────────────────────────────

final likedUploadIdsProvider = StreamProvider<Set<String>>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null || !session.isAuthenticated) return Stream.value({});
  // We store likes as a subcollection: upload_likes/{uploadId}/users/{userId}
  // For efficiency, we also store a user-level collection of liked upload IDs
  return _db
      .collection('user_likes')
      .doc(session.userId)
      .snapshots()
      .map(
        (snap) =>
            ((snap.data()?['uploadIds'] as List?) ?? []).cast<String>().toSet(),
      );
});

Future<void> toggleLike(String uploadId, String userId) async {
  await _functions.httpsCallable('toggleUploadLike').call<void>({
    'uploadId': uploadId,
  });
}

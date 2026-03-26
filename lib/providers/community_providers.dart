import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/social_profile.dart';
import '../models/uploaded_track.dart';
import 'app_state.dart';

final _db = FirebaseFirestore.instance;
final _storage = FirebaseStorage.instance;

// ── Social Profile ──────────────────────────────────────────────────────────

final myProfileProvider = StreamProvider<SocialProfile>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null || !session.isAuthenticated) {
    return Stream.value(SocialProfile.empty());
  }
  return _db.collection('social_profiles').doc(session.userId).snapshots().map(
    (snap) => snap.exists
        ? SocialProfile.fromMap(snap.data()!, id: snap.id)
        : SocialProfile(userId: session.userId, displayName: session.displayName),
  );
});

final profileProvider = StreamProvider.family<SocialProfile, String>((ref, userId) {
  return _db.collection('social_profiles').doc(userId).snapshots().map(
    (snap) => snap.exists
        ? SocialProfile.fromMap(snap.data()!, id: snap.id)
        : SocialProfile(userId: userId, displayName: 'Unknown'),
  );
});

Future<void> updateProfile(SocialProfile profile) async {
  await _db.collection('social_profiles').doc(profile.userId).set(
    profile.toMap(),
    SetOptions(merge: true),
  );
}

Future<List<SocialProfile>> searchProfiles(String query, {int limit = 30}) async {
  // Firestore doesn't support full-text search, so we use prefix matching on displayName
  final snap = await _db.collection('social_profiles')
      .orderBy('displayName')
      .startAt([query.toUpperCase()])
      .endAt(['${query.toLowerCase()}\uf8ff'])
      .limit(limit)
      .get();
  return snap.docs.map((d) => SocialProfile.fromMap(d.data(), id: d.id)).toList();
}

Future<List<SocialProfile>> getTopProfiles({int limit = 50}) async {
  final snap = await _db.collection('social_profiles')
      .orderBy('followerCount', descending: true)
      .limit(limit)
      .get();
  return snap.docs.map((d) => SocialProfile.fromMap(d.data(), id: d.id)).toList();
}

// ── Uploads ─────────────────────────────────────────────────────────────────

final recentUploadsProvider = StreamProvider<List<UploadedTrack>>((ref) {
  return _db.collection('uploads')
      .orderBy('uploadedAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs.map((d) => UploadedTrack.fromMap(d.data(), id: d.id)).toList());
});

final featuredUploadsProvider = StreamProvider<List<UploadedTrack>>((ref) {
  return _db.collection('uploads')
      .where('featured', isEqualTo: true)
      .orderBy('likeCount', descending: true)
      .limit(30)
      .snapshots()
      .map((snap) => snap.docs.map((d) => UploadedTrack.fromMap(d.data(), id: d.id)).toList());
});

final userUploadsProvider = StreamProvider.family<List<UploadedTrack>, String>((ref, userId) {
  return _db.collection('uploads')
      .where('uploadedBy', isEqualTo: userId)
      .orderBy('uploadedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs.map((d) => UploadedTrack.fromMap(d.data(), id: d.id)).toList());
});

Future<String> uploadAudio({
  required String userId,
  required String filePath,
  required String fileName,
  void Function(double)? onProgress,
}) async {
  final ref = _storage.ref('uploads/$userId/${DateTime.now().millisecondsSinceEpoch}_$fileName');
  final task = ref.putFile(File(filePath));
  if (onProgress != null) {
    task.snapshotEvents.listen((snap) {
      if (snap.totalBytes > 0) {
        onProgress(snap.bytesTransferred / snap.totalBytes);
      }
    });
  }
  await task;
  return await ref.getDownloadURL();
}

Future<String> uploadArtwork({
  required String userId,
  required String filePath,
}) async {
  final ref = _storage.ref('artwork/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg');
  await ref.putFile(File(filePath));
  return await ref.getDownloadURL();
}

Future<String> uploadProfilePhoto({
  required String userId,
  required String filePath,
}) async {
  final ref = _storage.ref('profile_photos/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg');
  await ref.putFile(File(filePath));
  return await ref.getDownloadURL();
}

Future<UploadedTrack> createUpload(UploadedTrack track) async {
  final doc = await _db.collection('uploads').add(track.toMap());
  // Increment upload count on profile
  await _db.collection('social_profiles').doc(track.uploadedBy).update({
    'uploadCount': FieldValue.increment(1),
  }).catchError((_) {});
  return UploadedTrack.fromMap(track.toMap(), id: doc.id);
}

Future<void> deleteUpload(String uploadId, String ownerId) async {
  await _db.collection('uploads').doc(uploadId).delete();
  await _db.collection('social_profiles').doc(ownerId).update({
    'uploadCount': FieldValue.increment(-1),
  }).catchError((_) {});
}

// ── Follows ─────────────────────────────────────────────────────────────────

final followingIdsProvider = StreamProvider<Set<String>>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null || !session.isAuthenticated) return Stream.value({});
  return _db.collection('follows')
      .where('followerId', isEqualTo: session.userId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.data()['followeeId'] as String).toSet());
});

Future<void> followUser(String followerId, String followeeId) async {
  final docId = '${followerId}_$followeeId';
  await _db.collection('follows').doc(docId).set({
    'followerId': followerId,
    'followeeId': followeeId,
    'createdAt': FieldValue.serverTimestamp(),
  });
  // Update counts
  await _db.collection('social_profiles').doc(followerId).update({
    'followingCount': FieldValue.increment(1),
  }).catchError((_) {});
  await _db.collection('social_profiles').doc(followeeId).update({
    'followerCount': FieldValue.increment(1),
  }).catchError((_) {});
}

Future<void> unfollowUser(String followerId, String followeeId) async {
  final docId = '${followerId}_$followeeId';
  await _db.collection('follows').doc(docId).delete();
  await _db.collection('social_profiles').doc(followerId).update({
    'followingCount': FieldValue.increment(-1),
  }).catchError((_) {});
  await _db.collection('social_profiles').doc(followeeId).update({
    'followerCount': FieldValue.increment(-1),
  }).catchError((_) {});
}

// ── Likes ───────────────────────────────────────────────────────────────────

final likedUploadIdsProvider = StreamProvider<Set<String>>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null || !session.isAuthenticated) return Stream.value({});
  // We store likes as a subcollection: upload_likes/{uploadId}/users/{userId}
  // For efficiency, we also store a user-level collection of liked upload IDs
  return _db.collection('user_likes').doc(session.userId).snapshots().map(
    (snap) => ((snap.data()?['uploadIds'] as List?) ?? []).cast<String>().toSet(),
  );
});

Future<void> toggleLike(String uploadId, String userId) async {
  final userLikesRef = _db.collection('user_likes').doc(userId);
  final uploadRef = _db.collection('uploads').doc(uploadId);

  final doc = await userLikesRef.get();
  final currentLikes = ((doc.data()?['uploadIds'] as List?) ?? []).cast<String>();

  if (currentLikes.contains(uploadId)) {
    // Unlike
    await userLikesRef.set({
      'uploadIds': FieldValue.arrayRemove([uploadId]),
    }, SetOptions(merge: true));
    await uploadRef.update({'likeCount': FieldValue.increment(-1)}).catchError((_) {});
  } else {
    // Like
    await userLikesRef.set({
      'uploadIds': FieldValue.arrayUnion([uploadId]),
    }, SetOptions(merge: true));
    await uploadRef.update({'likeCount': FieldValue.increment(1)}).catchError((_) {});
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/crate.dart';
import '../../models/user_profile.dart';

abstract class UserRepository {
  Stream<UserProfile> watchUser({
    required String userId,
    required String fallbackName,
  });

  Future<void> toggleWatchlist({
    required String userId,
    required String fallbackName,
    required String trackId,
  });

  Future<void> saveCrate({
    required String userId,
    required String fallbackName,
    required Crate crate,
  });

  Future<void> updatePreferredRegion({
    required String userId,
    required String fallbackName,
    required String region,
  });
}

class MockUserRepository implements UserRepository {
  final Map<String, UserProfile> _profiles = {};
  final Map<String, StreamController<UserProfile>> _controllers = {};

  @override
  Future<void> saveCrate({
    required String userId,
    required String fallbackName,
    required Crate crate,
  }) async {
    final profile = _getOrCreate(userId, fallbackName);
    final remaining = profile.savedCrates.where((item) => item.id != crate.id);
    final updated = profile.copyWith(
      savedCrates: [...remaining, crate]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
    );
    _emit(updated);
  }

  @override
  Future<void> toggleWatchlist({
    required String userId,
    required String fallbackName,
    required String trackId,
  }) async {
    final profile = _getOrCreate(userId, fallbackName);
    final watchlist = profile.watchlist.toSet();
    if (!watchlist.add(trackId)) {
      watchlist.remove(trackId);
    }
    _emit(profile.copyWith(watchlist: watchlist));
  }

  @override
  Future<void> updatePreferredRegion({
    required String userId,
    required String fallbackName,
    required String region,
  }) async {
    _emit(_getOrCreate(userId, fallbackName).copyWith(preferredRegion: region));
  }

  @override
  Stream<UserProfile> watchUser({
    required String userId,
    required String fallbackName,
  }) {
    final controller = _controllers.putIfAbsent(
      userId,
      () => StreamController<UserProfile>.broadcast(),
    );
    controller.add(_getOrCreate(userId, fallbackName));
    return controller.stream;
  }

  UserProfile _getOrCreate(String userId, String fallbackName) {
    return _profiles.putIfAbsent(
      userId,
      () => UserProfile.empty(
        id: userId,
        displayName: fallbackName,
        preferredRegion: 'GH',
      ),
    );
  }

  void _emit(UserProfile profile) {
    _profiles[profile.id] = profile;
    _controllers
        .putIfAbsent(
          profile.id,
          () => StreamController<UserProfile>.broadcast(),
        )
        .add(profile);
  }
}

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<void> saveCrate({
    required String userId,
    required String fallbackName,
    required Crate crate,
  }) async {
    final docRef = _firestore.collection('users').doc(userId);
    final snapshot = await docRef.get();
    final profile = UserProfile.fromMap(
      userId,
      snapshot.data(),
      fallbackName: fallbackName,
    );
    final crates = [
      ...profile.savedCrates.where((item) => item.id != crate.id),
      crate,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    await docRef.set(
      profile.copyWith(savedCrates: crates).toMap(),
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> toggleWatchlist({
    required String userId,
    required String fallbackName,
    required String trackId,
  }) async {
    final docRef = _firestore.collection('users').doc(userId);
    final snapshot = await docRef.get();
    final profile = UserProfile.fromMap(
      userId,
      snapshot.data(),
      fallbackName: fallbackName,
    );

    final watchlist = profile.watchlist.toSet();
    if (!watchlist.add(trackId)) {
      watchlist.remove(trackId);
    }

    await docRef.set(
      profile.copyWith(watchlist: watchlist).toMap(),
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> updatePreferredRegion({
    required String userId,
    required String fallbackName,
    required String region,
  }) async {
    final docRef = _firestore.collection('users').doc(userId);
    final snapshot = await docRef.get();
    final profile = UserProfile.fromMap(
      userId,
      snapshot.data(),
      fallbackName: fallbackName,
    );
    await docRef.set(
      profile.copyWith(preferredRegion: region).toMap(),
      SetOptions(merge: true),
    );
  }

  @override
  Stream<UserProfile> watchUser({
    required String userId,
    required String fallbackName,
  }) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map(
          (doc) => UserProfile.fromMap(
            userId,
            doc.data(),
            fallbackName: fallbackName,
          ),
        );
  }
}

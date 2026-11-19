import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform.dart';

/// Registers the device for push (FCM) and keeps the signed-in user's token set
/// in `users/{uid}.fcm_tokens` so Cloud Functions can notify them (e.g. a new
/// setlist arriving from the phone).
///
/// Push is wired for the phone form factor only for now — the desktop is
/// notified in-app via the live Firestore stream. Everything is best-effort: if
/// APNs isn't provisioned yet (the .p8 still being uploaded) `getToken()` simply
/// returns null / throws and we no-op rather than break sign-in.
class MessagingService {
  MessagingService(this._firestore);

  final FirebaseFirestore _firestore;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  String? _uid;

  /// Called when a user signs in. Requests permission, stores the token, and
  /// keeps it fresh on rotation.
  Future<void> register(String uid) async {
    if (!isMobileForm) return;
    _uid = uid;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // Show banners while the app is foregrounded (iOS).
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token != null) await _storeToken(uid, token);

      await _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen((t) => _storeToken(uid, t));

      await _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForeground);
    } catch (error) {
      debugPrint('MessagingService.register skipped: $error');
    }
  }

  /// Called on sign-out: drop this device's token so the user stops receiving
  /// pushes on a device they've left.
  Future<void> unregister() async {
    final uid = _uid;
    await _refreshSub?.cancel();
    await _foregroundSub?.cancel();
    _refreshSub = null;
    _foregroundSub = null;
    if (uid == null || !isMobileForm) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(uid).set({
          'fcm_tokens': FieldValue.arrayRemove([token]),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // best-effort.
    }
    _uid = null;
  }

  void _onForeground(RemoteMessage message) {
    // The OS suppresses its own banner while foregrounded on some platforms;
    // the presentation options above re-enable it on iOS. Nothing else to do —
    // the in-app surfaces already update live from Firestore.
    debugPrint('FCM foreground: ${message.notification?.title}');
  }

  Future<void> _storeToken(String uid, String token) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'fcm_tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('MessagingService.storeToken failed: $error');
    }
  }
}

final messagingServiceProvider = Provider<MessagingService>(
  (ref) => MessagingService(FirebaseFirestore.instance),
);

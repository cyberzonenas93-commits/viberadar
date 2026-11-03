import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/session_state.dart';
import '../services/iap_service.dart';
import 'app_state.dart';

final iapServiceProvider = Provider<IapService>((ref) => IapService());

class BillingState {
  const BillingState({
    this.storeAvailable = false,
    this.loadingProducts = true,
    this.products = const [],
    this.missingProductIds = const {},
    this.processing = false,
    this.message,
    this.error,
  });

  final bool storeAvailable;
  final bool loadingProducts;
  final List<ProductDetails> products;
  final Set<String> missingProductIds;
  final bool processing;
  final String? message;
  final String? error;

  BillingState copyWith({
    bool? storeAvailable,
    bool? loadingProducts,
    List<ProductDetails>? products,
    Set<String>? missingProductIds,
    bool? processing,
    Object? message = _sentinel,
    Object? error = _sentinel,
  }) {
    return BillingState(
      storeAvailable: storeAvailable ?? this.storeAvailable,
      loadingProducts: loadingProducts ?? this.loadingProducts,
      products: products ?? this.products,
      missingProductIds: missingProductIds ?? this.missingProductIds,
      processing: processing ?? this.processing,
      message: identical(message, _sentinel)
          ? this.message
          : message as String?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

class BillingController extends Notifier<BillingState> {
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  @override
  BillingState build() {
    final session = ref.watch(sessionProvider).value;
    if (session?.isAuthenticated != true || session?.isDemo == true) {
      return const BillingState(loadingProducts: false, storeAvailable: false);
    }
    if (Firebase.apps.isEmpty) {
      return const BillingState(loadingProducts: false, storeAvailable: false);
    }

    final service = ref.watch(iapServiceProvider);
    _purchaseSub = service.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error) {
        state = state.copyWith(
          processing: false,
          error: 'Purchase update failed: $error',
        );
      },
    );
    ref.onDispose(() => _purchaseSub?.cancel());
    unawaited(Future<void>.microtask(loadProducts));
    return const BillingState();
  }

  Future<void> loadProducts() async {
    state = state.copyWith(loadingProducts: true, error: null);
    try {
      final service = ref.read(iapServiceProvider);
      final available = await service.isAvailable();
      if (!available) {
        state = state.copyWith(
          storeAvailable: false,
          loadingProducts: false,
          products: const [],
          missingProductIds: viberadarIapProductIds,
          error: 'The App Store is unavailable on this device.',
        );
        return;
      }

      final response = await service.queryProducts();
      final products = [...response.productDetails]
        ..sort((a, b) => _productRank(a.id).compareTo(_productRank(b.id)));
      state = state.copyWith(
        storeAvailable: true,
        loadingProducts: false,
        products: products,
        missingProductIds: response.notFoundIDs.toSet(),
        error: response.error?.message,
      );
    } catch (error) {
      state = state.copyWith(
        loadingProducts: false,
        error: 'Unable to load App Store products: $error',
      );
    }
  }

  Future<void> purchase(ProductDetails product, SessionState session) async {
    if (!session.isAuthenticated || session.isDemo || session.userId.isEmpty) {
      state = state.copyWith(error: 'Sign in before purchasing VibeRadar Pro.');
      return;
    }
    state = state.copyWith(processing: true, error: null, message: null);
    try {
      await ref
          .read(iapServiceProvider)
          .purchase(
            product,
            accountToken: appAccountTokenForUid(session.userId),
          );
    } catch (error) {
      state = state.copyWith(
        processing: false,
        error: 'Purchase could not start: $error',
      );
    }
  }

  Future<void> restore(SessionState session) async {
    if (!session.isAuthenticated || session.isDemo || session.userId.isEmpty) {
      state = state.copyWith(error: 'Sign in before restoring purchases.');
      return;
    }
    state = state.copyWith(processing: true, error: null, message: null);
    try {
      await ref
          .read(iapServiceProvider)
          .restore(accountToken: appAccountTokenForUid(session.userId));
      state = state.copyWith(
        message: 'Restore started. Any purchases found will appear shortly.',
      );
    } catch (error) {
      state = state.copyWith(
        processing: false,
        error: 'Restore failed: $error',
      );
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    final service = ref.read(iapServiceProvider);
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(
            processing: true,
            message: 'Purchase is pending App Store approval.',
            error: null,
          );
          break;
        case PurchaseStatus.error:
          if (purchase.pendingCompletePurchase) {
            await service.complete(purchase);
          }
          state = state.copyWith(
            processing: false,
            error: purchase.error?.message ?? 'Purchase failed.',
          );
          break;
        case PurchaseStatus.canceled:
          if (purchase.pendingCompletePurchase) {
            await service.complete(purchase);
          }
          state = state.copyWith(
            processing: false,
            message: 'Purchase cancelled.',
          );
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _syncAndComplete(purchase);
          break;
      }
    }
  }

  Future<void> _syncAndComplete(PurchaseDetails purchase) async {
    final service = ref.read(iapServiceProvider);
    try {
      await service.syncPurchase(purchase);
      if (purchase.pendingCompletePurchase) {
        await service.complete(purchase);
      }
      ref.invalidate(appEntitlementProvider);
      state = state.copyWith(
        processing: false,
        message: purchase.status == PurchaseStatus.restored
            ? 'Purchase restored.'
            : 'VibeRadar Pro is active.',
        error: null,
      );
    } catch (error) {
      state = state.copyWith(
        processing: false,
        error: 'Purchase verification failed: $error',
      );
    }
  }
}

final billingControllerProvider =
    NotifierProvider<BillingController, BillingState>(BillingController.new);

String appAccountTokenForUid(String uid) {
  final bytes = sha256
      .convert(utf8.encode('viberadar:$uid'))
      .bytes
      .take(16)
      .toList(growable: false);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return [
    hex.substring(0, 8),
    hex.substring(8, 12),
    hex.substring(12, 16),
    hex.substring(16, 20),
    hex.substring(20, 32),
  ].join('-');
}

int _productRank(String id) {
  return switch (id) {
    'viberadar_pro_yearly' => 0,
    'viberadar_pro_monthly' => 1,
    _ => 10,
  };
}

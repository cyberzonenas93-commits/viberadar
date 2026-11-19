import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

const viberadarIapProductIds = <String>{
  'viberadar_pro_monthly',
  'viberadar_pro_yearly',
};

class IapService {
  IapService({InAppPurchase? inAppPurchase, FirebaseFunctions? functions})
    : _iap = inAppPurchase ?? InAppPurchase.instance,
      _functions = functions;

  final InAppPurchase _iap;
  FirebaseFunctions? _functions;

  FirebaseFunctions get _functionsClient =>
      _functions ??= FirebaseFunctions.instanceFor(region: 'us-central1');

  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  Future<bool> isAvailable() => _iap.isAvailable();

  Future<ProductDetailsResponse> queryProducts() {
    return _iap.queryProductDetails(viberadarIapProductIds);
  }

  Future<bool> purchase(
    ProductDetails product, {
    required String accountToken,
  }) {
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: product,
        applicationUserName: accountToken,
      ),
    );
  }

  Future<void> restore({required String accountToken}) {
    return _iap.restorePurchases(applicationUserName: accountToken);
  }

  Future<Map<String, dynamic>> syncPurchase(PurchaseDetails purchase) async {
    final transactionId = purchase.purchaseID?.trim();
    if (transactionId == null || transactionId.isEmpty) {
      throw StateError('App Store transaction id was missing.');
    }

    final result = await _functionsClient
        .httpsCallable('syncAppStorePurchase')
        .call({
          'transactionId': transactionId,
          'productId': purchase.productID,
        });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> complete(PurchaseDetails purchase) {
    return _iap.completePurchase(purchase);
  }
}

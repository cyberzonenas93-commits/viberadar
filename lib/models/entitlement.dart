import 'package:cloud_firestore/cloud_firestore.dart';

class AppEntitlement {
  const AppEntitlement({
    this.tier = 'free',
    this.active = false,
    this.status = 'free',
    this.provider = '',
    this.productId = '',
    this.expiresAt,
    this.lastVerifiedAt,
  });

  final String tier;
  final bool active;
  final String status;
  final String provider;
  final String productId;
  final DateTime? expiresAt;
  final DateTime? lastVerifiedAt;

  bool get isPro => active && (tier == 'pro' || tier == 'studio');

  String get displayTier {
    if (!active) return 'Free';
    return switch (tier) {
      'studio' => 'Studio',
      'pro' => 'Pro',
      _ => 'Free',
    };
  }

  factory AppEntitlement.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AppEntitlement();
    return AppEntitlement(
      tier: map['tier'] as String? ?? 'free',
      active: map['active'] as bool? ?? false,
      status: map['status'] as String? ?? 'free',
      provider: map['provider'] as String? ?? '',
      productId: map['productId'] as String? ?? '',
      expiresAt: _dateFrom(map['expiresAt']),
      lastVerifiedAt: _dateFrom(map['lastVerifiedAt']),
    );
  }

  static DateTime? _dateFrom(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

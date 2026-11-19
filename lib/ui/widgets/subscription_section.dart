import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../providers/billing_provider.dart';

const _proBenefitSummary =
    'Pro includes live trend charts and catalog results, platform search, AI set '
    'building, manual live refresh, and cloud-synced setlists on iPhone and Mac.';

class SubscriptionSection extends ConsumerWidget {
  const SubscriptionSection({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final entitlement = ref.watch(appEntitlementProvider).value;
    final billing = ref.watch(billingControllerProvider);
    final products = billing.products.isEmpty
        ? _fallbackProducts()
        : billing.products.map(_StoreProductView.fromProduct).toList();
    final canPurchase =
        session?.isAuthenticated == true && session?.isDemo != true;

    return Column(
      key: const Key('subscription_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.workspace_premium_rounded, color: AppTheme.lime),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'VibeRadar Pro',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _PlanPill(label: entitlement?.displayTier ?? 'Free'),
          ],
        ),
        const SizedBox(height: 12),
        if (entitlement?.isPro == true)
          _StatusLine(
            icon: Icons.verified_rounded,
            text: _activeText(entitlement!.expiresAt),
            color: AppTheme.lime,
          )
        else
          const _StatusLine(
            icon: Icons.lock_open_rounded,
            text: 'Free plan active',
            color: AppTheme.textSecondary,
          ),
        const SizedBox(height: 12),
        const _BenefitSummary(),
        const SizedBox(height: 16),
        if (billing.loadingProducts)
          const LinearProgressIndicator(minHeight: 2)
        else
          ...products.map(
            (product) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ProductRow(
                product: product,
                enabled:
                    canPurchase &&
                    billing.storeAvailable &&
                    !billing.processing &&
                    product.productDetails != null,
                onPressed: product.productDetails == null || session == null
                    ? null
                    : () => ref
                          .read(billingControllerProvider.notifier)
                          .purchase(product.productDetails!, session),
              ),
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          key: const Key('restore_purchases_button'),
          onPressed: canPurchase && !billing.processing
              ? () => ref
                    .read(billingControllerProvider.notifier)
                    .restore(session!)
              : null,
          icon: billing.processing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.restore_rounded, size: 18),
          label: const Text('Restore Purchases'),
        ),
        if (!canPurchase) ...[
          const SizedBox(height: 8),
          const Text(
            'Sign in to purchase or restore.',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
          ),
        ],
        if (billing.message != null) ...[
          const SizedBox(height: 8),
          _InlineNotice(text: billing.message!, color: AppTheme.cyan),
        ],
        if (billing.error != null) ...[
          const SizedBox(height: 8),
          _InlineNotice(text: billing.error!, color: Colors.redAccent),
        ],
        if (billing.missingProductIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InlineNotice(
            text:
                'Missing App Store products: ${billing.missingProductIds.join(', ')}',
            color: Colors.amberAccent,
          ),
        ],
        // App Store Guideline 3.1.2: auto-renew disclosure plus functional
        // Terms of Use (EULA) and Privacy Policy links at the point of purchase.
        const SizedBox(height: 14),
        const Text(
          key: Key('subscription_auto_renew_disclosure'),
          'VibeRadar Pro is an auto-renewable subscription (\$9.99/month or '
          '\$79.99/year). Payment is charged to your Apple ID at confirmation. '
          'It renews automatically unless canceled at least 24 hours before the '
          'end of the current period; manage or cancel anytime in your App '
          'Store account settings.',
          style: TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            _LegalLink(
              label: 'Terms of Use (EULA)',
              url: 'https://viberadar-462b8.web.app/terms.html',
            ),
            _LegalLink(
              label: 'Privacy Policy',
              url: 'https://viberadar-462b8.web.app/privacy.html',
            ),
          ],
        ),
      ],
    );
  }

  static String _activeText(DateTime? expiresAt) {
    if (expiresAt == null) return 'Subscription active';
    return 'Active until ${expiresAt.month}/${expiresAt.day}/${expiresAt.year}';
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.enabled,
    required this.onPressed,
  });

  final _StoreProductView product;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: Key('purchase_${product.id}_button'),
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        side: BorderSide(color: AppTheme.edge.withValues(alpha: 0.7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.subtitle,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            product.price,
            style: const TextStyle(
              color: AppTheme.lime,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanPill extends StatelessWidget {
  const _PlanPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.lime.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.lime.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.lime,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(color: color, fontSize: 12));
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.cyan,
          fontSize: 12,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class _StoreProductView {
  const _StoreProductView({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.price,
    this.productDetails,
  });

  final String id;
  final String title;
  final String subtitle;
  final String price;
  final ProductDetails? productDetails;

  factory _StoreProductView.fromProduct(ProductDetails product) {
    return _StoreProductView(
      id: product.id,
      title: _cleanTitle(product.title, product.id),
      subtitle: _fallbackSubtitle(product.id),
      price: product.price,
      productDetails: product,
    );
  }
}

class _BenefitSummary extends StatelessWidget {
  const _BenefitSummary();

  @override
  Widget build(BuildContext context) {
    return const Text(
      key: Key('subscription_benefit_summary'),
      _proBenefitSummary,
      style: TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 12,
        height: 1.4,
      ),
    );
  }
}

List<_StoreProductView> _fallbackProducts() => const [
  _StoreProductView(
    id: 'viberadar_pro_yearly',
    title: 'Pro Yearly',
    subtitle: 'Annual access',
    price: r'$79.99/year',
  ),
  _StoreProductView(
    id: 'viberadar_pro_monthly',
    title: 'Pro Monthly',
    subtitle: 'Monthly access',
    price: r'$9.99/month',
  ),
];

String _cleanTitle(String title, String id) {
  final fallback = id == 'viberadar_pro_yearly'
      ? 'Pro Yearly'
      : id == 'viberadar_pro_monthly'
      ? 'Pro Monthly'
      : title;
  return title.trim().isEmpty ? fallback : title.replaceAll('(VibeRadar)', '');
}

String _fallbackSubtitle(String id) {
  return id == 'viberadar_pro_yearly'
      ? 'Yearly access to live charts, AI sets, platform search, refresh, and sync'
      : id == 'viberadar_pro_monthly'
      ? 'Monthly access to live charts, AI sets, platform search, refresh, and sync'
      : 'VibeRadar subscription';
}

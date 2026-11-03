import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../providers/repositories.dart';
import 'subscription_section.dart';

const _paywallLockedHeroAsset = 'assets/paywall/pro_locked_hero.png';
const _paywallSheetAsset = 'assets/paywall/pro_sheet_badge.png';
const _paywallBannerAsset = 'assets/paywall/pro_banner_live.png';

void showVibeRadarProSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: 20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: const _ProSheetContent(),
      ),
    ),
  );
}

class ProUpsellBanner extends ConsumerWidget {
  const ProUpsellBanner({
    super.key,
    this.compact = false,
    this.margin = EdgeInsets.zero,
  });

  final bool compact;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(liveCatalogAccessProvider);
    if (!access.requiresUpgrade) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final showArtwork = constraints.maxWidth >= 340;
        final message = Text(
          'FREE PREVIEW: MOCK SONGS ONLY. The songs listed are sample tracks, not real live songs or trend data. Pro unlocks the live catalog.',
          maxLines: narrow ? 4 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        );
        final button = _upgradeButton(context, label: 'Upgrade');

        return Container(
          margin: margin,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: AppTheme.lime.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.lime.withValues(alpha: 0.38)),
            boxShadow: AppTheme.glow(AppTheme.lime, blur: 18, opacity: 0.08),
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (showArtwork) ...[
                          SizedBox(
                            width: compact ? 56 : 70,
                            child: _ProArtwork(
                              assetPath: _paywallBannerAsset,
                              height: compact ? 42 : 48,
                              radius: 9,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ] else ...[
                          const Icon(
                            Icons.workspace_premium_rounded,
                            color: AppTheme.lime,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: message),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: button),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: compact ? 70 : 92,
                      child: _ProArtwork(
                        assetPath: _paywallBannerAsset,
                        height: compact ? 44 : 56,
                        radius: 10,
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 12),
                    Expanded(child: message),
                    const SizedBox(width: 12),
                    button,
                  ],
                ),
        );
      },
    );
  }
}

Widget _upgradeButton(BuildContext context, {required String label}) {
  return FilledButton.icon(
    onPressed: () => showVibeRadarProSheet(context),
    icon: const Icon(Icons.lock_open_rounded, size: 16),
    label: Text(label),
    style: FilledButton.styleFrom(
      backgroundColor: AppTheme.lime,
      foregroundColor: AppTheme.ink,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

class _ProArtwork extends StatelessWidget {
  const _ProArtwork({
    required this.assetPath,
    required this.height,
    this.radius = 12,
  });

  final String assetPath;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.lime.withValues(alpha: 0.2)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, AppTheme.ink.withValues(alpha: 0.14)],
        ),
      ),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.cyan.withValues(alpha: 0.22),
                  AppTheme.lime.withValues(alpha: 0.18),
                  AppTheme.panelRaised,
                ],
              ),
            ),
            child: const Center(
              child: Icon(Icons.radar_rounded, color: AppTheme.lime, size: 28),
            ),
          );
        },
      ),
    );
  }
}

class ProLockedPanel extends ConsumerWidget {
  const ProLockedPanel({super.key, required this.feature});

  final String feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(liveCatalogAccessProvider);
    if (access.requiresSignIn) {
      return _SignInPanel(feature: feature);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 460 ||
            (constraints.hasBoundedHeight && constraints.maxHeight < 520);
        final outerPadding = compact ? 12.0 : 24.0;
        final innerPadding = compact ? 16.0 : 22.0;
        final minHeight =
            constraints.hasBoundedHeight &&
                constraints.maxHeight > outerPadding * 2
            ? constraints.maxHeight - outerPadding * 2
            : 0.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(outerPadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.panel.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.hairlineStrong),
                    boxShadow: AppTheme.ambientShadow,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(innerPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProArtwork(
                          assetPath: _paywallLockedHeroAsset,
                          height: compact ? 128 : 188,
                          radius: 12,
                        ),
                        SizedBox(height: compact ? 14 : 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: compact ? 34 : 40,
                              height: compact ? 34 : 40,
                              decoration: BoxDecoration(
                                color: AppTheme.lime.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.lime.withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Icon(
                                Icons.workspace_premium_rounded,
                                color: AppTheme.lime,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Unlock $feature with Pro',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: AppTheme.textPrimary,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Free accounts show MOCK SONGS ONLY: sample tracks, not real live songs or trend data. Upgrade for live catalog data, platform search, AI set building, and manual refresh.',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      height: 1.42,
                                      fontSize: compact ? 12.5 : 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 14 : 18),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            _ProValueChip(
                              icon: Icons.local_fire_department_rounded,
                              label: 'Live trends',
                            ),
                            _ProValueChip(
                              icon: Icons.search_rounded,
                              label: 'Platform search',
                            ),
                            _ProValueChip(
                              icon: Icons.auto_awesome_rounded,
                              label: 'AI sets',
                            ),
                            _ProValueChip(
                              icon: Icons.refresh_rounded,
                              label: 'Manual refresh',
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 16 : 20),
                        if (compact)
                          _upgradeButton(context, label: 'Upgrade to Pro')
                        else
                          const SubscriptionSection(compact: true),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProSheetContent extends StatelessWidget {
  const _ProSheetContent();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProArtwork(assetPath: _paywallSheetAsset, height: 156, radius: 12),
          SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded, color: AppTheme.lime),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Upgrade to VibeRadar Pro',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Live music intelligence, platform search, AI set building, and manual refresh are included with Pro.',
            style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
          SizedBox(height: 18),
          SubscriptionSection(compact: true),
        ],
      ),
    );
  }
}

class _SignInPanel extends ConsumerWidget {
  const _SignInPanel({required this.feature});

  final String feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 420 ||
            (constraints.hasBoundedHeight && constraints.maxHeight < 520);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.panel.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.hairlineStrong),
                  boxShadow: AppTheme.ambientShadow,
                ),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 18 : 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProArtwork(
                        assetPath: _paywallSheetAsset,
                        height: compact ? 116 : 136,
                        radius: 12,
                      ),
                      const SizedBox(height: 14),
                      const Icon(Icons.login_rounded, color: AppTheme.cyan),
                      const SizedBox(height: 12),
                      Text(
                        '$feature needs an account',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sign in to subscribe and use live VibeRadar features.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.read(sessionRepositoryProvider).signOut(),
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProValueChip extends StatelessWidget {
  const _ProValueChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.lime, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

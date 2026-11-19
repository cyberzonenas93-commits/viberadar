import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/repositories.dart';

class GuestModeBanner extends ConsumerWidget {
  const GuestModeBanner({
    super.key,
    this.compact = false,
    this.margin = EdgeInsets.zero,
  });

  final bool compact;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: margin,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.amber,
            size: 19,
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Text(
              'MOCK SONGS ONLY. The songs shown here are sample tracks, not real live songs or real trend data. Sign in for real catalog data, search, AI, cloud sync, community, and pairing.',
              maxLines: compact ? 4 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () => ref.read(sessionRepositoryProvider).signOut(),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.amber,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}

class GuestLockedPanel extends ConsumerWidget {
  const GuestLockedPanel({super.key, required this.feature});

  final String feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 360 ||
            (constraints.hasBoundedHeight && constraints.maxHeight < 360);
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
                constraints: const BoxConstraints(maxWidth: 520),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.panel.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.hairlineStrong),
                    boxShadow: AppTheme.ambientShadow,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(innerPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          color: AppTheme.amber,
                          size: compact ? 20 : 24,
                        ),
                        SizedBox(height: compact ? 10 : 14),
                        Text(
                          '$feature needs sign-in',
                          style:
                              (compact
                                      ? theme.textTheme.titleMedium
                                      : theme.textTheme.titleLarge)
                                  ?.copyWith(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        SizedBox(height: compact ? 6 : 8),
                        Text(
                          compact
                              ? 'MOCK SONGS ONLY. Demo Mode lists sample tracks, not real songs or live trend data. Sign in for real catalog data, cloud sync, AI, community, pairing, and subscriptions.'
                              : 'MOCK SONGS ONLY. Demo Mode lists local sample tracks, not real live songs or trend data, so it never calls live catalog, platform, AI, billing, community, or pairing services.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            height: compact ? 1.32 : 1.45,
                            fontSize: compact ? 12.5 : null,
                          ),
                        ),
                        SizedBox(height: compact ? 14 : 18),
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
          ),
        );
      },
    );
  }
}

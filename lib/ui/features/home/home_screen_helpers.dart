part of 'home_screen.dart';

double _regionalRelevance(Track track, String region) {
  final rawScore = track.regionScores[region.toUpperCase()] ?? 0.0;
  final genre = track.genre.toLowerCase();
  double genreBoost = 0.0;
  final r = region.toUpperCase();
  if (r == 'GH' || r == 'NG') {
    if (genre.contains('afrobeats') || genre.contains('afro')) genreBoost = 0.4;
    if (genre.contains('dancehall')) genreBoost = 0.25;
    if (genre.contains('hip-hop') || genre.contains('r&b')) genreBoost = 0.15;
  } else if (r == 'ZA') {
    if (genre.contains('amapiano')) genreBoost = 0.45;
    if (genre.contains('gqom') || genre.contains('house')) genreBoost = 0.3;
  } else if (r == 'GB') {
    if (genre.contains('drill') || genre.contains('garage')) genreBoost = 0.35;
    if (genre.contains('house') || genre.contains('dance')) genreBoost = 0.2;
  } else if (r == 'US') {
    if (genre.contains('hip-hop') || genre.contains('r&b')) genreBoost = 0.3;
    if (genre.contains('latin')) genreBoost = 0.2;
  }
  return (rawScore + genreBoost + track.trendScore * 0.3).clamp(0.0, 1.0);
}

// ── Region picker badge ───────────────────────────────────────────────────────

class _RegionPickerBadge extends ConsumerWidget {
  const _RegionPickerBadge({required this.currentRegion});

  final String currentRegion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regions = ref.watch(availableRegionsProvider);
    final session = ref.watch(sessionProvider).value;

    return PopupMenuButton<String>(
      tooltip: 'Change region',
      offset: const Offset(0, 32),
      color: AppTheme.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.edge),
      ),
      onSelected: (region) {
        // Apply immediately as local UI state so the change takes effect for
        // everyone — including guests, who have no writable profile doc.
        ref.read(selectedRegionProvider.notifier).set(region);
        // Persist to the profile only for a genuinely signed-in user; a guest
        // has an empty userId that Firestore's rules would reject.
        if (session != null &&
            session.isAuthenticated &&
            session.userId.isNotEmpty) {
          ref.read(userRepositoryProvider).updatePreferredRegion(
                userId: session.userId,
                fallbackName: session.displayName,
                region: region,
              );
        }
      },
      itemBuilder: (_) => regions
          .map(
            (r) => PopupMenuItem<String>(
              value: r,
              child: Row(
                children: [
                  if (r == currentRegion)
                    const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: AppTheme.cyan,
                    )
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 8),
                  Text(
                    formatRegionLabel(r),
                    style: TextStyle(
                      color: r == currentRegion
                          ? AppTheme.cyan
                          : AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.cyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Region: ${formatRegionLabel(currentRegion)}',
              style: const TextStyle(
                color: AppTheme.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down_rounded,
              color: AppTheme.cyan,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

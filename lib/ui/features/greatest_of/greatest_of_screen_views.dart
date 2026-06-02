part of 'greatest_of_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Era-grouped view
// ─────────────────────────────────────────────────────────────────────────────

class _EraGroupedView extends StatelessWidget {
  final Map<String, List<Track>> eraGroups;
  final Map<String, double> scoreMap;
  final WidgetRef ref;
  const _EraGroupedView({required this.eraGroups, required this.scoreMap, required this.ref});

  @override
  Widget build(BuildContext context) {
    final eras = ['2000s', '2010s', '2020s'].where(eraGroups.containsKey).toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
      itemCount: eras.length,
      itemBuilder: (context, eraIdx) {
        final era = eras[eraIdx];
        final tracks = eraGroups[era]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.violet, AppTheme.cyan]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(era, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Text('${tracks.length} tracks', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ]),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: tracks.length,
              itemBuilder: (ctx, i) => _TrackCard(
                track: tracks[i],
                rank: i + 1,
                greatestScore: scoreMap[tracks[i].id] ?? 0.0,
                ref: ref,
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top 3 Podium — hero layout with large artwork
// ─────────────────────────────────────────────────────────────────────────────

class _PodiumSection extends StatelessWidget {
  final List<Track> tracks;
  final Map<String, double> scoreMap;
  final WidgetRef ref;
  const _PodiumSection({required this.tracks, required this.scoreMap, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // #1 — Hero card (large)
        Expanded(
          flex: 5,
          child: _HeroCard(
              track: tracks[0], rank: 1,
              greatestScore: scoreMap[tracks[0].id] ?? 0.0, ref: ref),
        ),
        const SizedBox(width: 12),
        // #2 and #3 stacked
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _RunnerUpCard(track: tracks[1], rank: 2,
                  greatestScore: scoreMap[tracks[1].id] ?? 0.0, ref: ref),
              const SizedBox(height: 12),
              _RunnerUpCard(track: tracks[2], rank: 3,
                  greatestScore: scoreMap[tracks[2].id] ?? 0.0, ref: ref),
            ],
          ),
        ),
      ],
    );
  }
}

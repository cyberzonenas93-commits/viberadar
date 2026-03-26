import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/uploaded_track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/community_providers.dart';
import '../../../models/app_section.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});
  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            children: [
              const Icon(Icons.groups_rounded, color: AppTheme.pink, size: 24),
              const SizedBox(width: 10),
              Text('Community', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => ref.read(workspaceControllerProvider.notifier).setSection(AppSection.upload),
                icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                label: const Text('Upload Track'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.violet),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.cyan,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.cyan,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: const [Tab(text: 'Feed'), Tab(text: 'Featured'), Tab(text: 'Trending')],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _FeedTab(),
              _FeaturedTab(),
              _TrendingTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadsAsync = ref.watch(recentUploadsProvider);
    return uploadsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.cyan)),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppTheme.textTertiary))),
      data: (uploads) => uploads.isEmpty
          ? _EmptyFeed()
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220, childAspectRatio: 0.75, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: uploads.length,
              itemBuilder: (ctx, i) => _UploadCard(track: uploads[i]),
            ),
    );
  }
}

class _FeaturedTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadsAsync = ref.watch(featuredUploadsProvider);
    return uploadsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.cyan)),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppTheme.textTertiary))),
      data: (uploads) => uploads.isEmpty
          ? const Center(child: Text('No featured tracks yet', style: TextStyle(color: AppTheme.textTertiary)))
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220, childAspectRatio: 0.75, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: uploads.length,
              itemBuilder: (ctx, i) => _UploadCard(track: uploads[i]),
            ),
    );
  }
}

class _TrendingTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadsAsync = ref.watch(recentUploadsProvider);
    return uploadsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.cyan)),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppTheme.textTertiary))),
      data: (uploads) {
        final sorted = [...uploads]..sort((a, b) => b.likeCount.compareTo(a.likeCount));
        return sorted.isEmpty
            ? const Center(child: Text('No uploads yet', style: TextStyle(color: AppTheme.textTertiary)))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220, childAspectRatio: 0.75, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: sorted.length,
                itemBuilder: (ctx, i) => _UploadCard(track: sorted[i]),
              );
      },
    );
  }
}

class _UploadCard extends ConsumerStatefulWidget {
  final UploadedTrack track;
  const _UploadCard({required this.track});
  @override
  ConsumerState<_UploadCard> createState() => _UploadCardState();
}

class _UploadCardState extends ConsumerState<_UploadCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final likedIds = ref.watch(likedUploadIdsProvider).value ?? {};
    final isLiked = likedIds.contains(t.id);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (t.audioUrl.isNotEmpty) {
            final uri = Uri.tryParse(t.audioUrl);
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artwork
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(imageUrl: t.artworkUrl, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _artPlaceholder())
                            : _artPlaceholder(),
                      ),
                    ),
                    // Genre badge
                    if (t.genre.isNotEmpty)
                      Positioned(top: 8, left: 8, child: _Badge(t.genre, AppTheme.violet)),
                    // BPM badge
                    if (t.bpm > 0)
                      Positioned(top: 8, right: 8, child: _Badge('${t.bpm}', AppTheme.amber)),
                    // Play overlay
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.cyan, shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 16)],
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                          )),
                        ),
                      ),
                  ],
                ),
              ),
              // Info
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(t.artistName, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Uploader
                        if (t.uploaderPhotoUrl.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: CircleAvatar(radius: 8, backgroundImage: CachedNetworkImageProvider(t.uploaderPhotoUrl)),
                          ),
                        Expanded(child: Text(t.uploaderName, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 9), overflow: TextOverflow.ellipsis)),
                        // Like button
                        GestureDetector(
                          onTap: () {
                            final session = ref.read(sessionProvider).value;
                            if (session != null && session.isAuthenticated) {
                              toggleLike(t.id, session.userId);
                            }
                          },
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                size: 12, color: isLiked ? AppTheme.pink : AppTheme.textTertiary),
                            const SizedBox(width: 3),
                            Text('${t.likeCount}', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 9)),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artPlaceholder() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [AppTheme.pink.withValues(alpha: 0.15), AppTheme.violet.withValues(alpha: 0.08), AppTheme.edge],
      ),
    ),
    child: const Center(child: Icon(Icons.headphones_rounded, color: AppTheme.textTertiary, size: 36)),
  );
}

class _Badge extends StatelessWidget {
  final String text; final Color color;
  const _Badge(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(5)),
    child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
  );
}

class _EmptyFeed extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: AppTheme.pink.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.headphones_rounded, size: 40, color: AppTheme.pink)),
      const SizedBox(height: 16),
      const Text('No uploads yet', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
      const SizedBox(height: 6),
      const Text('Be the first to share a track with the community!', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
    ]),
  );
}

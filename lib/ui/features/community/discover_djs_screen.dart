import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/social_profile.dart';
import '../../../models/app_section.dart';
import '../../../providers/app_state.dart';
import '../../../providers/community_providers.dart';

class DiscoverDJsScreen extends ConsumerStatefulWidget {
  const DiscoverDJsScreen({super.key});
  @override
  ConsumerState<DiscoverDJsScreen> createState() => _DiscoverDJsScreenState();
}

class _DiscoverDJsScreenState extends ConsumerState<DiscoverDJsScreen> {
  List<SocialProfile> _profiles = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _loading = true);
    try {
      _profiles = await getTopProfiles(limit: 100);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final myId = session?.userId ?? '';
    final followingIds = ref.watch(followingIdsProvider).value ?? {};

    final filtered = _search.isEmpty
        ? _profiles
        : _profiles.where((p) =>
            p.displayName.toLowerCase().contains(_search.toLowerCase()) ||
            p.genres.any((g) => g.toLowerCase().contains(_search.toLowerCase()))).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(children: [
            const Icon(Icons.explore_rounded, color: AppTheme.cyan, size: 24),
            const SizedBox(width: 10),
            Text('Discover DJs & Artists', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary)),
            const Spacer(),
            SizedBox(
              width: 240,
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search DJs, genres...',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary, size: 18),
                  filled: true, fillColor: AppTheme.panel,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.edge)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.edge)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.cyan)))
        else if (filtered.isEmpty)
          const Expanded(child: Center(child: Text('No DJs found. Be the first to create a profile!', style: TextStyle(color: AppTheme.textTertiary))))
        else
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240, childAspectRatio: 0.85, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) => _DJCard(
                profile: filtered[i],
                isFollowing: followingIds.contains(filtered[i].userId),
                isMe: filtered[i].userId == myId,
                onFollow: () {
                  if (followingIds.contains(filtered[i].userId)) {
                    unfollowUser(myId, filtered[i].userId);
                  } else {
                    followUser(myId, filtered[i].userId);
                  }
                },
                onTap: () {
                  // Navigate to their profile — for now just open community
                  ref.read(workspaceControllerProvider.notifier).setSection(AppSection.community);
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _DJCard extends StatefulWidget {
  final SocialProfile profile;
  final bool isFollowing;
  final bool isMe;
  final VoidCallback onFollow;
  final VoidCallback onTap;
  const _DJCard({required this.profile, required this.isFollowing, required this.isMe, required this.onFollow, required this.onTap});
  @override
  State<_DJCard> createState() => _DJCardState();
}

class _DJCardState extends State<_DJCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35)),
          ),
          child: Column(
            children: [
              // Avatar
              CircleAvatar(
                radius: 32,
                backgroundColor: AppTheme.violet.withValues(alpha: 0.2),
                backgroundImage: p.photoUrl.isNotEmpty ? CachedNetworkImageProvider(p.photoUrl) : null,
                child: p.photoUrl.isEmpty ? Text(p.displayName.isNotEmpty ? p.displayName[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppTheme.violet, fontSize: 24, fontWeight: FontWeight.w700)) : null,
              ),
              const SizedBox(height: 10),
              // Name
              Text(p.displayName, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
              const SizedBox(height: 2),
              // Role
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                child: Text(p.role, style: const TextStyle(color: AppTheme.cyan, fontSize: 9, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              // Genre chips
              if (p.genres.isNotEmpty)
                Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: p.genres.take(3).map((g) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.violet.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(g, style: const TextStyle(color: AppTheme.violet, fontSize: 9)),
                )).toList()),
              const Spacer(),
              // Stats
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${p.followerCount}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                const Text(' followers', style: TextStyle(color: AppTheme.textTertiary, fontSize: 9)),
                const SizedBox(width: 12),
                Text('${p.uploadCount}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                const Text(' tracks', style: TextStyle(color: AppTheme.textTertiary, fontSize: 9)),
              ]),
              const SizedBox(height: 8),
              // Follow button
              if (!widget.isMe)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.onFollow,
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.isFollowing ? AppTheme.edge : AppTheme.pink,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(widget.isFollowing ? 'Following' : 'Follow',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

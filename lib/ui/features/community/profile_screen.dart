import 'dart:developer' as developer;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/social_profile.dart';
import '../../../models/uploaded_track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/community_providers.dart';
import '../../widgets/ui_kit.dart';
import 'moderation_actions.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.userId});
  final String? userId; // null = own profile
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _bioController = TextEditingController();
  final _locationController = TextEditingController();
  String _role = 'DJ';
  List<String> _genres = [];
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final isOwn = widget.userId == null || widget.userId == session?.userId;
    final profileAsync = isOwn
        ? ref.watch(myProfileProvider)
        : ref.watch(profileProvider(widget.userId!));

    return profileAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppTheme.cyan)),
      error: (e, _) => Center(
        child: Text(
          'Error: $e',
          style: const TextStyle(color: AppTheme.textTertiary),
        ),
      ),
      data: (profile) =>
          _buildProfile(context, profile, isOwn, session?.userId ?? ''),
    );
  }

  Widget _buildProfile(
    BuildContext context,
    SocialProfile profile,
    bool isOwn,
    String myUserId,
  ) {
    final uploadsAsync = ref.watch(userUploadsProvider(profile.userId));
    final followingIds = ref.watch(followingIdsProvider).value ?? {};
    final isFollowing = followingIds.contains(profile.userId);

    return CustomScrollView(
      slivers: [
        // Profile header
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(
              AppTheme.r2xl,
              AppTheme.s6,
              AppTheme.r2xl,
              0,
            ),
            padding: const EdgeInsets.all(AppTheme.s6),
            decoration: AppTheme.glass(
              radius: AppTheme.rXl,
              tint: AppTheme.violet,
              border: AppTheme.violet.withValues(alpha: 0.2),
              glowShadow: AppTheme.glow(
                AppTheme.violet,
                blur: 24,
                opacity: 0.10,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                GestureDetector(
                  onTap: isOwn ? _pickProfilePhoto : null,
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppTheme.violet.withValues(alpha: 0.2),
                    backgroundImage: profile.photoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(profile.photoUrl)
                        : null,
                    child: profile.photoUrl.isEmpty
                        ? const Icon(
                            Icons.person_rounded,
                            size: 40,
                            color: AppTheme.violet,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 20),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              profile.displayName,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.cyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              profile.role,
                              style: const TextStyle(
                                color: AppTheme.cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (profile.bio.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            profile.bio,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      if (profile.location.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                size: 12,
                                color: AppTheme.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                profile.location,
                                style: const TextStyle(
                                  color: AppTheme.textTertiary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      // Stats
                      Wrap(
                        spacing: 20,
                        children: [
                          _Stat('${profile.uploadCount}', 'Uploads'),
                          _Stat('${profile.followerCount}', 'Followers'),
                          _Stat('${profile.followingCount}', 'Following'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Genre chips
                      if (profile.genres.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: profile.genres
                              .map(
                                (g) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.violet.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    g,
                                    style: const TextStyle(
                                      color: AppTheme.violet,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Action buttons
                Column(
                  children: [
                    if (isOwn)
                      FilledButton.icon(
                        onPressed: () => _showEditDialog(context, profile),
                        icon: const Icon(Icons.edit_rounded, size: 14),
                        label: const Text('Edit Profile'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.violet,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GradientButton(
                            label: isFollowing ? 'Following' : 'Follow',
                            icon: isFollowing
                                ? Icons.check_rounded
                                : Icons.person_add_rounded,
                            height: 40,
                            glow: !isFollowing,
                            gradient: isFollowing
                                ? const LinearGradient(
                                    colors: [AppTheme.edge, AppTheme.edge],
                                  )
                                : const LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [AppTheme.pink, AppTheme.violet],
                                  ),
                            onPressed: () {
                              if (isFollowing) {
                                unfollowUser(myUserId, profile.userId);
                              } else {
                                followUser(myUserId, profile.userId);
                              }
                            },
                          ),
                          const SizedBox(width: 6),
                          PopupMenuButton<String>(
                            tooltip: 'More',
                            color: AppTheme.panelRaised,
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: AppTheme.textSecondary,
                            ),
                            onSelected: (v) {
                              if (v == 'report') {
                                showReportDialog(
                                  context,
                                  ref,
                                  contentType: 'profile',
                                  contentId: profile.userId,
                                  reportedUid: profile.userId,
                                );
                              } else if (v == 'block') {
                                showBlockDialog(
                                  context,
                                  ref,
                                  blockedUid: profile.userId,
                                  blockedName: profile.displayName,
                                );
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'report',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.flag_outlined,
                                      size: 16,
                                      color: AppTheme.textSecondary,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Report',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'block',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.block_rounded,
                                      size: 16,
                                      color: AppTheme.pink,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Block user',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Uploads grid
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.r2xl,
              AppTheme.s5,
              AppTheme.r2xl,
              AppTheme.s2,
            ),
            child: Text(
              'Uploads',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
        uploadsAsync.when(
          loading: () => const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.cyan),
            ),
          ),
          error: (e, _) =>
              SliverFillRemaining(child: Center(child: Text('$e'))),
          data: (uploads) => uploads.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: VibeEmptyState(
                    icon: Icons.cloud_upload_rounded,
                    title: isOwn
                        ? 'You haven\'t uploaded any tracks yet'
                        : 'No uploads yet',
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          childAspectRatio: 0.78,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _UploadTile(track: uploads[i]),
                      childCount: uploads.length,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _pickProfilePhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final session = ref.read(sessionProvider).value;
    if (session == null) return;
    try {
      final url = await uploadProfilePhoto(
        userId: session.userId,
        filePath: result.files.first.path!,
      );
      final profile = ref.read(myProfileProvider).value;
      if (profile != null) {
        await updateProfile(profile.copyWith(photoUrl: url));
      }
    } catch (e, st) {
      developer.log(
        'Failed to upload profile photo',
        name: 'ProfileScreen',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _showEditDialog(BuildContext context, SocialProfile profile) {
    _bioController.text = profile.bio;
    _locationController.text = profile.location;
    _role = profile.role;
    _genres = [...profile.genres];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rLg),
          ),
          title: const Text(
            'Edit Profile',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Role selector
                  Row(
                    children: [
                      const Text(
                        'Role: ',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ...['DJ', 'MC', 'Producer', 'Artist'].map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              r,
                              style: TextStyle(
                                fontSize: 11,
                                color: _role == r
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                              ),
                            ),
                            selected: _role == r,
                            selectedColor: AppTheme.violet,
                            backgroundColor: AppTheme.panelRaised,
                            onSelected: (_) => setDialogState(() => _role = r),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bioController,
                    maxLines: 3,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      hintText: 'Tell others about yourself...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locationController,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      hintText: 'e.g. Accra, Ghana',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Genre chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in [
                        'Afrobeats',
                        'Amapiano',
                        'R&B',
                        'Hip-Hop',
                        'House',
                        'Pop',
                        'Dancehall',
                        'Afro-House',
                        'Open Format',
                      ])
                        FilterChip(
                          label: Text(g, style: const TextStyle(fontSize: 11)),
                          selected: _genres.contains(g),
                          selectedColor: AppTheme.violet.withValues(
                            alpha: 0.25,
                          ),
                          onSelected: (sel) => setDialogState(() {
                            if (sel) {
                              _genres.add(g);
                            } else {
                              _genres.remove(g);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setDialogState(() => _saving = true);
                      await updateProfile(
                        profile.copyWith(
                          bio: _bioController.text.trim(),
                          location: _locationController.text.trim(),
                          role: _role,
                          genres: _genres,
                        ),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      setState(() => _saving = false);
                    },
              child: Text(_saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 16,
          letterSpacing: -0.5,
        ),
      ),
      Text(
        label,
        style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
      ),
    ],
  );
}

class _UploadTile extends StatelessWidget {
  final UploadedTrack track;
  const _UploadTile({required this.track});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.glass(
        radius: AppTheme.rMd,
        border: AppTheme.hairline,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
              child: SizedBox.expand(
                child: track.artworkUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.artworkUrl,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: AppTheme.edge,
                        child: const Center(
                          child: Icon(
                            Icons.headphones_rounded,
                            color: AppTheme.textTertiary,
                            size: 32,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${track.likeCount} likes · ${track.timeAgo}',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

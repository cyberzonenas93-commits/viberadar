import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_state.dart';
import '../../../providers/community_providers.dart';

/// Lists the current user's blocked accounts with an Unblock action.
/// Satisfies the "block abusive users" requirement of App Store Guideline 1.2
/// by giving users a reversible block path.
Future<void> showBlockedUsersDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => const Dialog(
      backgroundColor: AppTheme.panel,
      insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: SizedBox(width: 440, height: 520, child: _BlockedUsersList()),
    ),
  );
}

class _BlockedUsersList extends ConsumerWidget {
  const _BlockedUsersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedUidsProvider);
    final myId = ref.watch(sessionProvider).value?.userId ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
          child: Row(
            children: [
              const Icon(Icons.block_rounded, color: AppTheme.pink, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Blocked users',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppTheme.edge),
        Expanded(
          child: blockedAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppTheme.cyan),
            ),
            error: (e, _) => Center(
              child: Text(
                'Error: $e',
                style: const TextStyle(color: AppTheme.textTertiary),
              ),
            ),
            data: (blocked) {
              if (blocked.isEmpty) {
                return const Center(
                  child: Text(
                    "You haven't blocked anyone.",
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                  ),
                );
              }
              final ids = blocked.toList();
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: ids.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppTheme.edge, indent: 16, endIndent: 16),
                itemBuilder: (ctx, i) => _BlockedRow(blockedUid: ids[i], myId: myId),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BlockedRow extends ConsumerWidget {
  const _BlockedRow({required this.blockedUid, required this.myId});
  final String blockedUid;
  final String myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider(blockedUid));
    final profile = profileAsync.value;
    final name = profile?.displayName ?? 'User';
    final photo = profile?.photoUrl ?? '';

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: AppTheme.violet.withValues(alpha: 0.2),
        backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
        child: photo.isEmpty
            ? const Icon(Icons.person_rounded, size: 18, color: AppTheme.violet)
            : null,
      ),
      title: Text(
        name,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed: () => unblockUser(myId, blockedUid),
        style: TextButton.styleFrom(foregroundColor: AppTheme.cyan),
        child: const Text('Unblock'),
      ),
    );
  }
}

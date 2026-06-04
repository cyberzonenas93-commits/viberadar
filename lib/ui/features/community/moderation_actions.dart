import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_state.dart';
import '../../../providers/community_providers.dart';

/// Shared UGC moderation actions (report / block) used by community uploads and
/// user profiles. Satisfies App Store Guideline 1.2: a way to report
/// objectionable content and block abusive users.

const List<String> kReportReasons = [
  'Spam',
  'Offensive/abusive',
  'Copyright',
  'Other',
];

/// Shows a dialog letting the user pick a report reason, then writes a doc to
/// the `reports` collection and confirms with a snackbar.
Future<void> showReportDialog(
  BuildContext context,
  WidgetRef ref, {
  required String contentType, // 'upload' | 'profile'
  required String contentId,
  required String reportedUid,
}) async {
  final session = ref.read(sessionProvider).value;
  if (session == null || !session.isAuthenticated) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please sign in to report content'),
        backgroundColor: AppTheme.pink,
      ),
    );
    return;
  }

  final selected = await showDialog<String>(
    context: context,
    builder: (ctx) {
      String reason = kReportReasons.first;
      return StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Report content',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why are you reporting this?',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final r in kReportReasons)
                _ReasonOption(
                  label: r,
                  selected: reason == r,
                  onTap: () => setDialogState(() => reason = r),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, reason),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.pink),
              child: const Text('Submit report'),
            ),
          ],
        ),
      );
    },
  );

  if (selected == null) return;

  await reportContent(
    reportedBy: session.userId,
    contentType: contentType,
    contentId: contentId,
    reportedUid: reportedUid,
    reason: selected,
  );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("Thanks — we'll review this within 24 hours."),
      backgroundColor: AppTheme.lime,
    ),
  );
}

/// Confirms then writes a doc to the `blocks` collection so the blocked user's
/// content is filtered out of feeds. Shows a confirmation snackbar.
Future<void> showBlockDialog(
  BuildContext context,
  WidgetRef ref, {
  required String blockedUid,
  String? blockedName,
}) async {
  final session = ref.read(sessionProvider).value;
  if (session == null || !session.isAuthenticated) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please sign in to block users'),
        backgroundColor: AppTheme.pink,
      ),
    );
    return;
  }
  if (session.userId == blockedUid) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Block user',
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      content: Text(
        blockedName != null && blockedName.isNotEmpty
            ? "You won't see $blockedName's uploads or profile anymore. You can unblock them later from the Community screen."
            : "You won't see this user's uploads or profile anymore. You can unblock them later from the Community screen.",
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.pink),
          child: const Text('Block'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  await blockUser(session.userId, blockedUid);

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        blockedName != null && blockedName.isNotEmpty
            ? 'Blocked $blockedName'
            : 'User blocked',
      ),
      backgroundColor: AppTheme.panelRaised,
    ),
  );
}

class _ReasonOption extends StatelessWidget {
  const _ReasonOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? AppTheme.cyan : AppTheme.textTertiary,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

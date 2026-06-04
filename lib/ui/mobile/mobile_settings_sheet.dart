import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../providers/repositories.dart';
import '../../services/account_deletion_service.dart';
import '../../services/secure_storage_service.dart';

/// Bottom-sheet with basic account info, sign-out, and account deletion.
///
/// Shown from the Setlists AppBar. Satisfies App Store Guideline 5.1.1(v)
/// (account deletion available from within the app).
class MobileSettingsSheet extends ConsumerWidget {
  const MobileSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionProvider);
    final email = sessionAsync.value?.email ?? '';

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppTheme.edge,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          const Text(
            'Account',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),

          // Signed-in email
          if (email.isNotEmpty)
            Text(
              email,
              key: const Key('settings_email_label'),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),

          const SizedBox(height: 28),
          Divider(color: AppTheme.edge.withValues(alpha: 0.4), height: 1),
          const SizedBox(height: 20),

          // Sign out
          OutlinedButton.icon(
            key: const Key('sign_out_button'),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _signOut(context, ref),
          ),

          const SizedBox(height: 12),

          // Delete account — destructive
          OutlinedButton.icon(
            key: const Key('delete_account_button'),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Delete account'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade400,
              side: BorderSide(color: Colors.red.shade400.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _confirmDelete(context, ref),
          ),

          const SizedBox(height: 16),
          // Privacy policy — App Store requires an in-app link for data apps.
          Center(
            child: TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://viberadar-462b8.web.app/privacy.html'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text(
                'Privacy Policy',
                style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(sessionRepositoryProvider).signOut();
    } catch (_) {
      // Swallow errors — Firebase may already be signed out.
    }
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.red.shade400.withValues(alpha: 0.4)),
        ),
        title: const Text(
          'Delete account?',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'This will permanently delete your account and all your data. '
          'This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            key: const Key('confirm_delete_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await ref.read(accountDeletionServiceProvider).deleteAccount();
      // Sign out after deletion to clear local auth state.
      try {
        await ref.read(sessionRepositoryProvider).signOut();
      } catch (_) {
        // intentional: best-effort sign-out cleanup after account deletion;
        // the account is already deleted, so a sign-out failure is harmless.
      }
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please sign in again, then retry deletion.'),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.message}')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

/// Lets the user store their personal OpenAI API key, used by the AI tab.
///
/// The key is written to this device's Keychain via [SecureStorageService] and
/// is never bundled or synced. Saving an empty value clears the stored key.
class OpenAiKeySection extends StatefulWidget {
  const OpenAiKeySection({super.key, this.storage});

  /// Injectable backend for tests; defaults to the real Keychain-backed service.
  final SecureStorageService? storage;

  @override
  State<OpenAiKeySection> createState() => _OpenAiKeySectionState();
}

class _OpenAiKeySectionState extends State<OpenAiKeySection> {
  late final SecureStorageService _storage =
      widget.storage ?? SecureStorageService();
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await _storage.readSecret(kOpenAiApiKey);
    if (!mounted) return;
    setState(() {
      if (key != null) _controller.text = key;
      _saved = key != null && key.trim().isNotEmpty;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      await _storage.deleteSecret(kOpenAiApiKey);
    } else {
      await _storage.writeSecret(kOpenAiApiKey, key);
    }
    if (!mounted) return;
    setState(() => _saved = key.isNotEmpty);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(key.isEmpty ? 'OpenAI key cleared' : 'OpenAI key saved'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'OpenAI API Key',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 8),
            if (_saved)
              const Icon(Icons.check_circle, size: 16, color: AppTheme.lime),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Powers the AI tab. Stored only on this device.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('openai_key_field'),
                controller: _controller,
                obscureText: true,
                enabled: !_loading,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'sk-…',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary),
                  filled: true,
                  fillColor: AppTheme.panel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              key: const Key('save_openai_key_button'),
              onPressed: _loading ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

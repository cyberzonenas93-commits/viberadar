import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/crate.dart';
import '../../providers/setlist_provider.dart';
import '../../services/pairing_service.dart';

/// Desktop "Pair a Phone" screen.
///
/// Calls [PairingService.createPairing] on open, displays the 6-char code and
/// a QR encoding that code, then subscribes to the shared-setlist channel and
/// shows received setlists. Merging into local crates is left for a follow-up.
class PairPhoneScreen extends ConsumerStatefulWidget {
  const PairPhoneScreen({super.key});

  @override
  ConsumerState<PairPhoneScreen> createState() => _PairPhoneScreenState();
}

class _PairPhoneScreenState extends ConsumerState<PairPhoneScreen> {
  // ── Pairing handshake state ───────────────────────────────────────────────

  /// null = loading; non-null = paired successfully.
  ({String pairingId, String code})? _pairing;

  /// Non-null when [PairingService.createPairing] throws.
  String? _error;

  // ── Setlist subscription ──────────────────────────────────────────────────

  StreamSubscription<List<Crate>>? _setlistSub;
  List<Crate> _receivedSetlists = const [];

  /// Crate ids currently being saved into the desktop's local crates.
  final Set<String> _importingIds = {};

  /// Crate ids already imported into the desktop's local crates.
  final Set<String> _importedIds = {};

  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _startPairing();
  }

  @override
  void dispose() {
    _setlistSub?.cancel();
    super.dispose();
  }

  Future<void> _startPairing() async {
    try {
      final result = await ref
          .read(pairingServiceProvider)
          .createPairing(desktopName: 'VibeRadar Desktop');

      if (!mounted) return;

      setState(() => _pairing = result);

      // Subscribe to the shared-setlist channel.
      _setlistSub = ref
          .read(pairingServiceProvider)
          .watchSharedSetlists(result.pairingId)
          .listen((crates) {
        if (mounted) setState(() => _receivedSetlists = crates);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'Pairing unavailable — enable Anonymous Auth in Firebase.';
        });
      }
    }
  }

  /// Saves a received [crate] into the desktop's own saved crates so the DJ can
  /// actually use it. Idempotent — re-importing updates the same crate.
  Future<void> _importSetlist(Crate crate) async {
    setState(() => _importingIds.add(crate.id));
    try {
      await ref.read(setlistActionsProvider).save(crate);
      if (!mounted) return;
      setState(() {
        _importingIds.remove(crate.id);
        _importedIds.add(crate.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported "${crate.name}" to your crates')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _importingIds.remove(crate.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import "${crate.name}"')),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair a Phone'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: _buildBody(textTheme),
        ),
      ),
    );
  }

  Widget _buildBody(TextTheme textTheme) {
    // Loading state
    if (_pairing == null && _error == null) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Creating pairing code…'),
        ],
      );
    }

    // Error state
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link_off_rounded, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    // Paired state
    final code = _pairing!.code;
    final setlistCount = _receivedSetlists.length;
    final countLabel =
        setlistCount == 1 ? '1 setlist received' : '$setlistCount setlists received';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Open VibeRadar on your phone and enter this code:',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),

          // ── 6-char code ──────────────────────────────────────────────────
          Text(
            code,
            style: textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
          ),
          const SizedBox(height: 24),

          // ── QR code ──────────────────────────────────────────────────────
          QrImageView(
            data: code,
            size: 180,
          ),
          const SizedBox(height: 32),

          // ── Received setlists ─────────────────────────────────────────────
          Text(countLabel, style: textTheme.titleMedium),

          if (_receivedSetlists.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._receivedSetlists.map(
              (crate) {
                final importing = _importingIds.contains(crate.id);
                final imported = _importedIds.contains(crate.id);
                return ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(crate.name),
                  subtitle: Text(
                    '${crate.trackIds.length} '
                    '${crate.trackIds.length == 1 ? "track" : "tracks"}',
                  ),
                  trailing: importing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : imported
                          ? const Icon(Icons.check_circle_rounded,
                              color: Colors.green)
                          : TextButton.icon(
                              onPressed: () => _importSetlist(crate),
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('Import'),
                            ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

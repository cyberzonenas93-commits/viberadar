import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/crate.dart';
import '../../models/track.dart';
import '../../providers/setlist_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/crate_export_planner.dart';
import '../../services/pairing_service.dart';

const _kDesktopPairingPrefsKey = 'desktop_pairing_v1';

/// The desktop's pairing, persisted across app restarts.
///
/// Previously the screen minted a fresh code on every open, so the phone had to
/// re-pair each time and its stored pairing could point at a dead channel. Now
/// the code is reused from disk (the channel survives restarts on both ends);
/// [_PairPhoneScreenState] exposes "Generate new code" to rotate it on demand.
final desktopPairingProvider =
    FutureProvider<({String pairingId, String code})>((ref) async {
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_kDesktopPairingPrefsKey);
        if (raw != null) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final id = map['id'] as String?;
          final code = map['code'] as String?;
          if (id != null && code != null) return (pairingId: id, code: code);
        }
      } catch (_) {
        prefs =
            null; // prefs unavailable (e.g. tests) — create without persisting.
      }

      final created = await ref
          .read(pairingServiceProvider)
          .createPairing(desktopName: 'VibeRadar Desktop');

      if (prefs != null) {
        try {
          await prefs.setString(
            _kDesktopPairingPrefsKey,
            jsonEncode({'id': created.pairingId, 'code': created.code}),
          );
        } catch (_) {
          // best-effort persistence.
        }
      }
      return created;
    });

/// Setlists pushed from the phone for the current pairing. Rebinds
/// automatically when [desktopPairingProvider] changes (e.g. after rotation).
final sharedSetlistsProvider = StreamProvider<List<Crate>>((ref) {
  final pairing = ref.watch(desktopPairingProvider).asData?.value;
  if (pairing == null) return const Stream<List<Crate>>.empty();
  return ref
      .read(pairingServiceProvider)
      .watchSharedSetlists(pairing.pairingId);
});

/// Desktop "Pair a Phone" screen.
///
/// Shows the (session-stable) 6-char code + QR, streams setlists the phone
/// pushes, and imports them into the DJ's saved setlists — where the Saved
/// Setlists view matches them to the local library and exports real DJ crates.
class PairPhoneScreen extends ConsumerStatefulWidget {
  const PairPhoneScreen({super.key});

  @override
  ConsumerState<PairPhoneScreen> createState() => _PairPhoneScreenState();
}

class _PairPhoneScreenState extends ConsumerState<PairPhoneScreen> {
  /// Setlist ids currently being imported into the desktop.
  final Set<String> _importingIds = {};

  /// Setlist ids already imported into the desktop.
  final Set<String> _importedIds = {};

  /// Saves a received [crate] into account setlists when possible and always
  /// seeds the local Export Studio so the DJ can match + export it immediately.
  /// Idempotent — re-importing updates the same setlist.
  Future<void> _importSetlist(Crate crate) async {
    setState(() => _importingIds.add(crate.id));
    try {
      final resolved = resolveCrateTracks(crate.tracks, const <Track>[]);
      ref
          .read(crateProvider.notifier)
          .importCrate(
            crate.name,
            resolved.tracks.map(exportStudioId).toList(),
          );
      await ref.read(setlistActionsProvider).save(crate);
      if (!mounted) return;
      setState(() {
        _importingIds.remove(crate.id);
        _importedIds.add(crate.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported "${crate.name}" to your setlists')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _importingIds.remove(crate.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import "${crate.name}"')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pairing = ref.watch(desktopPairingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair a Phone'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Generate a new code',
            onPressed: () async {
              final current = pairing.asData?.value;
              if (current != null) {
                await ref
                    .read(pairingServiceProvider)
                    .revokePairing(current.pairingId)
                    .catchError((_) {
                      // Local rotation must still work if the old pairing is
                      // already gone or the user is offline.
                    });
              }
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove(_kDesktopPairingPrefsKey);
              } catch (_) {
                // best-effort — invalidation below still rotates in-session.
              }
              if (!mounted) return;
              setState(_importedIds.clear);
              ref.invalidate(desktopPairingProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
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
          child: pairing.when(
            loading: () => const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('Creating pairing code…'),
              ],
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.link_off_rounded,
                    size: 48,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pairing is unavailable right now. Try again after signing in or check your connection.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            data: (p) => _buildPaired(textTheme, p.code),
          ),
        ),
      ),
    );
  }

  Widget _buildPaired(TextTheme textTheme, String code) {
    final setlists =
        ref.watch(sharedSetlistsProvider).asData?.value ?? const [];
    final countLabel = setlists.length == 1
        ? '1 setlist received'
        : '${setlists.length} setlists received';

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
          Text(
            code,
            style: textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
          ),
          const SizedBox(height: 24),
          QrImageView(data: code, size: 180),
          const SizedBox(height: 32),
          Text(countLabel, style: textTheme.titleMedium),
          if (setlists.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...setlists.map((crate) {
              final importing = _importingIds.contains(crate.id);
              final imported = _importedIds.contains(crate.id);
              return ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(crate.name),
                subtitle: Text(
                  '${crate.tracks.length} '
                  '${crate.tracks.length == 1 ? "track" : "tracks"}',
                ),
                trailing: importing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : imported
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green,
                      )
                    : TextButton.icon(
                        onPressed: () => _importSetlist(crate),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Import'),
                      ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

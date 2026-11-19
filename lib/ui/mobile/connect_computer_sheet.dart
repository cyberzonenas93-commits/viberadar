import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/paired_computer_provider.dart';
import '../../services/pairing_service.dart';
import 'qr_scan_screen.dart';

export '../../providers/paired_computer_provider.dart';

// ---------------------------------------------------------------------------
// ConnectComputerSheet
// ---------------------------------------------------------------------------

/// A bottom-sheet widget that accepts a 6-character manual pairing code,
/// calls [PairingService.claimPairing], and updates [pairedComputerProvider].
///
/// Shown via [showModalBottomSheet] from the setlists AppBar.
class ConnectComputerSheet extends ConsumerStatefulWidget {
  const ConnectComputerSheet({super.key});

  @override
  ConsumerState<ConnectComputerSheet> createState() =>
      _ConnectComputerSheetState();
}

class _ConnectComputerSheetState extends ConsumerState<ConnectComputerSheet> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final scanned = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (!mounted || scanned == null) return;
    _codeController.text = scanned.toUpperCase();
    await _connect();
  }

  Future<void> _connect() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(pairingServiceProvider).claimPairing(code);
      if (!mounted) return;

      // Update state before closing so that tests can read it while the widget
      // is still in the tree (no separate Navigator pop in widget tests).
      ref
          .read(pairedComputerProvider.notifier)
          .set(PairedComputer(result.pairingId, result.desktopName));

      // Close the sheet if it has its own route (modal usage).
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${result.desktopName}')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Invalid or expired code';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Push content above the keyboard.
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
          const Text(
            'Connect a Computer',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the 6-character code shown on your desktop app.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.lime.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.lime.withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_done_outlined, color: AppTheme.lime, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Signed in on your Mac with the same account? Your setlists '
                    'already sync automatically — no code needed.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('pairing_code_field'),
            controller: _codeController,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            // Force uppercase as the user types.
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              _UpperCaseTextFormatter(),
            ],
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              letterSpacing: 6,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'ABC123',
              hintStyle: const TextStyle(
                color: AppTheme.textTertiary,
                letterSpacing: 6,
                fontSize: 24,
              ),
              counterText: '',
              errorText: _errorMessage,
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.edge.withValues(alpha: 0.6),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppTheme.violet,
                  width: 1.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red.shade400),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const Key('connect_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.violet,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _loading ? null : _connect,
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Connect',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loading ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.cyan,
              side: BorderSide(color: AppTheme.cyan.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            label: const Text('Scan QR code instead'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text formatter — uppercases input
// ---------------------------------------------------------------------------

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

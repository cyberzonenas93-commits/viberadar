import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the active phone-to-desktop pairing.
class PairedComputer {
  const PairedComputer(this.pairingId, this.desktopName);

  final String pairingId;
  final String desktopName;
}

class PairedComputerController extends Notifier<PairedComputer?> {
  static const _prefsKey = 'paired_computer_v1';

  @override
  PairedComputer? build() {
    // Restore the last paired computer so the link survives an app restart.
    // This is best-effort because SharedPreferences can be unavailable in tests.
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final id = map['id'] as String?;
      final name = map['name'] as String?;
      if (id != null && name != null) state = PairedComputer(id, name);
    } catch (_) {
      // prefs unavailable/corrupt: start unpaired.
    }
  }

  void set(PairedComputer? p) {
    state = p;
    unawaited(_persist(p));
  }

  Future<void> _persist(PairedComputer? p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (p == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(
          _prefsKey,
          jsonEncode({'id': p.pairingId, 'name': p.desktopName}),
        );
      }
    } catch (_) {
      // best-effort persistence.
    }
  }
}

final pairedComputerProvider =
    NotifierProvider<PairedComputerController, PairedComputer?>(
      PairedComputerController.new,
    );

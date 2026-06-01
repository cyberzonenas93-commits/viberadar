import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Triggers a manual re-ingestion of track data from all sources.
class IngestService {
  static const _ingestUrl = 'https://manualingesttracksignals-hcw675cb3a-uc.a.run.app';

  /// Returns a summary string on success, or an error message.
  static Future<String> triggerIngest() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return 'Sign in to refresh live ingestion.';
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return 'Could not refresh: missing Firebase ID token.';
      }

      final ingestResponse = await http.post(
        Uri.parse(_ingestUrl),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 120));

      if (ingestResponse.statusCode == 200) {
        final data = jsonDecode(ingestResponse.body);
        final signals = data['fetchedSignals'] ?? 0;
        final tracks = data['writtenTracks'] ?? 0;
        return 'Refreshed: $signals signals → $tracks tracks';
      } else {
        return 'Ingest failed (${ingestResponse.statusCode})';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }
}

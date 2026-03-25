import 'dart:convert';
import 'package:http/http.dart' as http;

/// Triggers a manual re-ingestion of track data from all sources.
class IngestService {
  static const _authUrl = 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=AIzaSyCDZ2kVmhIQenh-YsI_sWXIYDPmWmMFmRE';
  static const _ingestUrl = 'https://manualingesttracksignals-hcw675cb3a-uc.a.run.app';
  static const _email = 'cli-ingest@viberadar.app';
  static const _password = 'VibeRadar2026!';

  /// Returns a summary string on success, or an error message.
  static Future<String> triggerIngest() async {
    try {
      // 1. Get auth token
      final authResponse = await http.post(
        Uri.parse(_authUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _email,
          'password': _password,
          'returnSecureToken': true,
        }),
      ).timeout(const Duration(seconds: 15));

      if (authResponse.statusCode != 200) {
        return 'Auth failed (${authResponse.statusCode})';
      }

      final authData = jsonDecode(authResponse.body);
      final idToken = authData['idToken'] as String;

      // 2. Trigger ingestion
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

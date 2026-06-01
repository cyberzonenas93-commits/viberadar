import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../models/crate.dart';
import '../../providers/setlist_provider.dart';
import '../../services/ai_copilot_service.dart';

// ── Injectable provider (overridable in tests) ─────────────────────────────

final aiCopilotServiceProvider =
    Provider<AiCopilotService>((ref) => AiCopilotService());

// ── Draft track model ──────────────────────────────────────────────────────

class _DraftTrack {
  const _DraftTrack({
    required this.title,
    required this.artist,
    required this.bpm,
    required this.key,
  });

  final String title;
  final String artist;
  final int bpm;
  final String key;

  /// Synthesized stable id — deferred Firestore resolution handled on desktop.
  String get synthesizedId =>
      'ai:${('${artist.toLowerCase()} - ${title.toLowerCase()}').trim()}';
}

// ── Crate-block regex (mirrors ai_copilot_screen.dart) ────────────────────

final _crateRegex = RegExp(r'```crate\s*\n([\s\S]*?)\n```');

({String name, List<_DraftTrack> tracks})? _extractCrate(String response) {
  final match = _crateRegex.firstMatch(response);
  if (match == null) return null;
  try {
    final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final name = data['name'] as String? ?? 'AI Set';
    final rawList = data['tracks'] as List? ?? const [];
    final tracks = <_DraftTrack>[];
    for (final t in rawList) {
      if (t is Map) {
        final title = t['title']?.toString() ?? '';
        final artist = t['artist']?.toString() ?? '';
        if (title.isEmpty) continue;
        tracks.add(_DraftTrack(
          title: title,
          artist: artist,
          bpm: (t['bpm'] as num?)?.toInt() ?? 0,
          key: t['key']?.toString() ?? '',
        ));
      }
    }
    return (name: name, tracks: tracks);
  } catch (_) {
    return null;
  }
}

// ── Widget ─────────────────────────────────────────────────────────────────

class AiTab extends ConsumerStatefulWidget {
  const AiTab({super.key});

  @override
  ConsumerState<AiTab> createState() => _AiTabState();
}

class _AiTabState extends ConsumerState<AiTab> {
  final _promptController = TextEditingController();

  bool _loading = false;
  String? _replyText; // plain-text reply when no crate block found
  String? _errorText;
  String? _draftName;
  List<_DraftTrack> _draftTracks = const [];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasDraft = _draftTracks.isNotEmpty;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),

          // Main scrollable content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // Prompt field
                TextField(
                  controller: _promptController,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style:
                      const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Describe the set you want to build…',
                    hintStyle: const TextStyle(
                        color: AppTheme.textTertiary, fontSize: 14),
                    filled: true,
                    fillColor: AppTheme.panelRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: AppTheme.edge.withValues(alpha: 0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: AppTheme.edge.withValues(alpha: 0.5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.violet),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),

                // Build button
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _onBuild,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.violet,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Build',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),

                // Error
                if (_errorText != null) _buildErrorBanner(),

                // Plain text reply (no crate block)
                if (_replyText != null && !hasDraft) _buildReply(),

                // Draft crate
                if (hasDraft) ...[
                  _buildDraftHeader(),
                  ..._draftTracks.map(_buildTrackRow),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.lime.withValues(alpha: 0.15),
                        foregroundColor: AppTheme.lime,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side:
                            BorderSide(color: AppTheme.lime.withValues(alpha: 0.4)),
                      ),
                      child: const Text('Save as setlist',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ] else ...[
                  // Save button is always present but disabled when no draft
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save as setlist'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-widgets ────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.edge.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.violet, AppTheme.pink],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            'AI Set Builder',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFF6B6B), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorText!,
              style:
                  const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReply() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
      ),
      child: Text(
        _replyText!,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildDraftHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.playlist_play_rounded,
              color: AppTheme.violet, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _draftName ?? 'AI Set',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${_draftTracks.length} tracks',
            style:
                const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackRow(_DraftTrack track) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${track.artist} - ${track.title}',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (track.bpm > 0 || track.key.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              [
                if (track.bpm > 0) '${track.bpm} BPM',
                if (track.key.isNotEmpty) track.key,
              ].join(' · '),
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _onBuild() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _loading = true;
      _errorText = null;
      _replyText = null;
      _draftName = null;
      _draftTracks = const [];
    });

    try {
      final svc = ref.read(aiCopilotServiceProvider);
      final reply = await svc.chat(
        const [], // no history for a single-shot mobile request
        prompt,
        trackContext: null,
      );

      final parsed = _extractCrate(reply);

      setState(() {
        _loading = false;
        if (parsed != null && parsed.tracks.isNotEmpty) {
          _draftName = parsed.name;
          _draftTracks = parsed.tracks;
        } else {
          _replyText = reply;
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorText = 'Something went wrong — please try again.';
      });
    }
  }

  Future<void> _onSave() async {
    if (_draftTracks.isEmpty) return;

    final name = _draftName ?? 'AI Set';
    final trackIds = _draftTracks.map((t) => t.synthesizedId).toList();
    final now = DateTime.now();

    final crate = Crate(
      id: const Uuid().v4(),
      name: name,
      context: 'AI set',
      trackIds: trackIds,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await ref.read(setlistActionsProvider).save(crate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved "$name"'),
            backgroundColor: AppTheme.violet,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}

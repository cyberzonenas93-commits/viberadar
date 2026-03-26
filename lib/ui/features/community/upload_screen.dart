import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/app_section.dart';
import '../../../models/social_profile.dart';
import '../../../models/uploaded_track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/community_providers.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});
  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _bpmController = TextEditingController();
  final _keyController = TextEditingController();
  final _tagsController = TextEditingController();
  String _genre = 'Afrobeats';
  String? _audioPath;
  String? _artworkPath;
  String _audioFileName = '';
  bool _uploading = false;
  double _progress = 0;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _bpmController.dispose();
    _keyController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            const Icon(Icons.cloud_upload_rounded, color: AppTheme.violet, size: 24),
            const SizedBox(width: 10),
            Text('Upload Track', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary)),
          ]),
          const SizedBox(height: 6),
          const Text('Share your music with the VibeRadar community. DJs and listeners will discover your tracks.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),

          // Upload form in a card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.edge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Audio file picker
                _FilePickerRow(
                  label: 'Audio File',
                  hint: 'Select MP3, WAV, FLAC, AAC, or M4A',
                  icon: Icons.audio_file_rounded,
                  fileName: _audioFileName,
                  onPick: _pickAudioFile,
                  color: AppTheme.cyan,
                ),
                const SizedBox(height: 16),

                // Artwork picker
                _FilePickerRow(
                  label: 'Cover Art (optional)',
                  hint: 'Select JPG or PNG image',
                  icon: Icons.image_rounded,
                  fileName: _artworkPath != null ? 'Selected' : '',
                  onPick: _pickArtwork,
                  color: AppTheme.pink,
                ),
                const SizedBox(height: 20),

                // Title + Artist
                Row(children: [
                  Expanded(child: _Field(controller: _titleController, label: 'Track Title', hint: 'e.g. "Calm Down"')),
                  const SizedBox(width: 12),
                  Expanded(child: _Field(controller: _artistController, label: 'Artist Name', hint: 'e.g. "Rema"')),
                ]),
                const SizedBox(height: 12),

                // Genre + BPM + Key
                Row(children: [
                  // Genre dropdown
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Genre', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: AppTheme.panelRaised, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.edge)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _genre, isExpanded: true, isDense: true, dropdownColor: AppTheme.panel,
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                            items: ['Afrobeats', 'Amapiano', 'R&B', 'Hip-Hop', 'House', 'Pop', 'Dancehall', 'Afro-House', 'Drill', 'Highlife', 'Gospel', 'Other']
                                .map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (v) => setState(() => _genre = v ?? 'Afrobeats'),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: 100, child: _Field(controller: _bpmController, label: 'BPM', hint: '120')),
                  const SizedBox(width: 12),
                  SizedBox(width: 80, child: _Field(controller: _keyController, label: 'Key', hint: '4A')),
                ]),
                const SizedBox(height: 12),

                // Tags
                _Field(controller: _tagsController, label: 'Tags (comma-separated)', hint: 'afro, summer, dance'),
                const SizedBox(height: 20),

                // Error
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: AppTheme.pink, fontSize: 12)),
                  ),

                // Progress
                if (_uploading) ...[
                  LinearProgressIndicator(value: _progress, backgroundColor: AppTheme.edge, valueColor: const AlwaysStoppedAnimation(AppTheme.cyan)),
                  const SizedBox(height: 8),
                  Text('Uploading... ${(_progress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 12),
                ],

                // Upload button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _uploading || _audioPath == null || _titleController.text.trim().isEmpty
                        ? null
                        : () => _upload(session),
                    icon: _uploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: Text(_uploading ? 'Uploading...' : 'Upload to Community'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.violet,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'aiff'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _audioPath = result.files.first.path;
        _audioFileName = result.files.first.name;
        // Auto-fill title from filename if empty
        if (_titleController.text.isEmpty) {
          final name = result.files.first.name.replaceAll(RegExp(r'\.[^.]+$'), '');
          final parts = name.split(RegExp(r'\s+-\s+'));
          if (parts.length >= 2) {
            _artistController.text = parts[0].trim();
            _titleController.text = parts[1].trim();
          } else {
            _titleController.text = name;
          }
        }
      });
    }
  }

  Future<void> _pickArtwork() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _artworkPath = result.files.first.path);
    }
  }

  Future<void> _upload(dynamic session) async {
    if (session == null || !session.isAuthenticated) {
      setState(() => _error = 'Please sign in to upload');
      return;
    }
    setState(() { _uploading = true; _error = null; _progress = 0; });

    try {
      // Ensure profile exists
      final profile = ref.read(myProfileProvider).value;
      if (profile == null || profile.userId.isEmpty) {
        await updateProfile(SocialProfile(
          userId: session.userId,
          displayName: session.displayName,
        ));
      }

      // Upload audio
      final audioUrl = await uploadAudio(
        userId: session.userId,
        filePath: _audioPath!,
        fileName: _audioFileName,
        onProgress: (p) => setState(() => _progress = p * 0.8), // 80% for audio
      );

      // Upload artwork if provided
      String artworkUrl = '';
      if (_artworkPath != null) {
        artworkUrl = await uploadArtwork(userId: session.userId, filePath: _artworkPath!);
      }
      setState(() => _progress = 0.95);

      // Create upload document
      await createUpload(UploadedTrack(
        id: '',
        title: _titleController.text.trim(),
        artistName: _artistController.text.trim().isEmpty ? session.displayName : _artistController.text.trim(),
        audioUrl: audioUrl,
        artworkUrl: artworkUrl,
        genre: _genre,
        bpm: int.tryParse(_bpmController.text) ?? 0,
        keySignature: _keyController.text.trim(),
        uploadedBy: session.userId,
        uploaderName: session.displayName,
        uploadedAt: DateTime.now(),
        tags: _tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
        uploaderPhotoUrl: profile?.photoUrl ?? '',
      ));

      setState(() => _progress = 1.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Track uploaded successfully!'), backgroundColor: AppTheme.lime),
        );
        // Navigate to community feed
        ref.read(workspaceControllerProvider.notifier).setSection(AppSection.community);
      }
    } catch (e) {
      setState(() { _error = 'Upload failed: $e'; _uploading = false; });
      return;
    }

    setState(() => _uploading = false);
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  const _Field({required this.controller, required this.label, required this.hint});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.textTertiary),
          filled: true, fillColor: AppTheme.panelRaised,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.edge)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.edge)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    ],
  );
}

class _FilePickerRow extends StatelessWidget {
  final String label, hint, fileName;
  final IconData icon;
  final VoidCallback onPick;
  final Color color;
  const _FilePickerRow({required this.label, required this.hint, required this.fileName, required this.icon, required this.onPick, required this.color});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPick,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), style: BorderStyle.solid),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          Text(fileName.isNotEmpty ? fileName : hint, style: TextStyle(color: fileName.isNotEmpty ? AppTheme.textPrimary : AppTheme.textTertiary, fontSize: 11)),
        ])),
        Icon(Icons.add_circle_outline_rounded, color: color, size: 20),
      ]),
    ),
  );
}

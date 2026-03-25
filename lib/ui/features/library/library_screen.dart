import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Library', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Scan your local music folder to index tracks and detect duplicates.', style: TextStyle(color: Color(0xFF9099B8), fontSize: 13)),
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: AppTheme.violet.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.violet.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.folder_rounded, size: 48, color: AppTheme.violet),
                ),
                const SizedBox(height: 24),
                const Text('No library scanned yet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
                const SizedBox(height: 8),
                const Text('Select a folder containing your music files\nto automatically extract metadata and detect duplicates.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9099B8), fontSize: 13, height: 1.5)),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Select Music Folder'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.violet,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 20,
                  children: [
                    _InfoCard(icon: Icons.audio_file_rounded, label: 'Supports MP3, FLAC, WAV, AAC, M4A'),
                    _InfoCard(icon: Icons.fingerprint_rounded, label: 'Extracts BPM, key, energy metadata'),
                    _InfoCard(icon: Icons.content_copy_rounded, label: 'Auto-detects duplicate tracks'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoCard({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      width: 200,
      decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.edge)),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.cyan, size: 22),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9099B8), fontSize: 11, height: 1.4)),
        ],
      ),
    );
  }
}

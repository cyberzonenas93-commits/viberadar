import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class ExportsScreen extends StatelessWidget {
  const ExportsScreen({super.key});

  static const _formats = [
    (icon: Icons.music_note_rounded, name: 'Rekordbox XML', desc: 'Pioneer DJ crate export'),
    (icon: Icons.queue_music_rounded, name: 'Serato CSV', desc: 'Serato DJ playlist'),
    (icon: Icons.list_alt_rounded, name: 'M3U Playlist', desc: 'Universal format'),
    (icon: Icons.folder_zip_rounded, name: 'Traktor NML', desc: 'Native Instruments'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Exports', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Export your crates to any DJ software format.', style: TextStyle(color: Color(0xFF9099B8), fontSize: 13)),
          const SizedBox(height: 32),
          Text('Export Formats', style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 3.5,
            children: _formats.map((f) => Container(
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.edge),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(f.icon, color: AppTheme.violet, size: 22),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(f.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(f.desc, style: const TextStyle(color: Color(0xFF9099B8), fontSize: 11)),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.edge,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Export', style: TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ],
              ),
            )).toList(),
          ),
          const SizedBox(height: 32),
          const Text('Export History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                const Icon(Icons.history_rounded, color: Color(0xFF9099B8), size: 36),
                const SizedBox(height: 8),
                const Text('No exports yet', style: TextStyle(color: Color(0xFF9099B8), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

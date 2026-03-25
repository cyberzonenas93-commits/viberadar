import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class DuplicatesScreen extends StatelessWidget {
  const DuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Duplicates', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Automatically detect duplicate and near-duplicate tracks in your library.', style: TextStyle(color: Color(0xFF9099B8), fontSize: 13)),
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: AppTheme.cyan.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.cyan.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.content_copy_rounded, size: 48, color: AppTheme.cyan),
                ),
                const SizedBox(height: 24),
                const Text('Scan library first', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
                const SizedBox(height: 8),
                const Text('Duplicate detection runs automatically when you scan your library in My Library.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9099B8), fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

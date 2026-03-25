import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class GreatestOfScreen extends StatefulWidget {
  const GreatestOfScreen({super.key});
  @override
  State<GreatestOfScreen> createState() => _GreatestOfScreenState();
}

class _GreatestOfScreenState extends State<GreatestOfScreen> {
  String _selectedArtist = 'Burna Boy';
  String _selectedGenre = 'All Genres';

  static const _artists = ['Burna Boy', 'Wizkid', 'Tems', 'Rema', 'Drake', 'SZA', 'Fred Again'];
  static const _genres = ['All Genres', 'Afrobeats', 'Amapiano', 'R&B', 'Hip-Hop', 'House'];

  static const _tracks = [
    (title: 'Last Last', artist: 'Burna Boy', bpm: 93, key: '10A', score: 97.2, year: 2022),
    (title: 'Last Last (Remix)', artist: 'Burna Boy', bpm: 93, key: '10A', score: 94.1, year: 2022),
    (title: 'Anybody', artist: 'Burna Boy', bpm: 104, key: '7A', score: 91.5, year: 2019),
    (title: 'On the Low', artist: 'Burna Boy', bpm: 97, key: '4A', score: 89.7, year: 2019),
    (title: 'Ye', artist: 'Burna Boy', bpm: 88, key: '2A', score: 87.3, year: 2018),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Greatest Of', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
              const SizedBox(height: 6),
              const Text('Discover an artist\'s most impactful tracks of all time.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 20),
              Row(
                children: [
                  _Chip(
                    label: 'Artist',
                    value: _selectedArtist,
                    options: _artists,
                    onChanged: (v) => setState(() => _selectedArtist = v),
                  ),
                  const SizedBox(width: 12),
                  _Chip(
                    label: 'Genre',
                    value: _selectedGenre,
                    options: _genres,
                    onChanged: (v) => setState(() => _selectedGenre = v),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('Generate'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.violet),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            itemCount: _tracks.length,
            itemBuilder: (context, i) {
              final t = _tracks[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.edge),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: AppTheme.violet.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('${i + 1}', style: const TextStyle(color: AppTheme.violet, fontWeight: FontWeight.w700))),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                          Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                    Text('${t.bpm} BPM', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.edge, borderRadius: BorderRadius.circular(6)),
                      child: Text(t.key, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 16),
                    Text('${t.score}', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20, color: AppTheme.violet),
                      onPressed: () {},
                      tooltip: 'Add to crate',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _Chip({required this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: AppTheme.edge, borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: AppTheme.panel,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

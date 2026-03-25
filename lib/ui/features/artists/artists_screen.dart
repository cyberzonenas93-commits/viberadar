import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class ArtistsScreen extends StatelessWidget {
  const ArtistsScreen({super.key});

  static const _artists = [
    (name: 'Burna Boy', genre: 'Afrobeats', country: 'NG', listeners: '45.2M', trend: 0.96),
    (name: 'Wizkid', genre: 'Afrobeats', country: 'NG', listeners: '38.7M', trend: 0.91),
    (name: 'Tems', genre: 'Afrobeats / R&B', country: 'NG', listeners: '32.1M', trend: 0.88),
    (name: 'Rema', genre: 'Afrobeats', country: 'NG', listeners: '28.9M', trend: 0.94),
    (name: 'Davido', genre: 'Afrobeats', country: 'NG', listeners: '27.4M', trend: 0.82),
    (name: 'Kabza De Small', genre: 'Amapiano', country: 'ZA', listeners: '19.2M', trend: 0.87),
    (name: 'DJ Maphorisa', genre: 'Amapiano', country: 'ZA', listeners: '17.8M', trend: 0.83),
    (name: 'Uncle Waffles', genre: 'Amapiano', country: 'ZA', listeners: '14.5M', trend: 0.79),
    (name: 'SZA', genre: 'R&B', country: 'US', listeners: '41.3M', trend: 0.93),
    (name: 'Drake', genre: 'Hip-Hop', country: 'CA', listeners: '68.9M', trend: 0.89),
    (name: 'Travis Scott', genre: 'Hip-Hop', country: 'US', listeners: '44.1M', trend: 0.86),
    (name: 'Fred Again', genre: 'House / Electronic', country: 'GB', listeners: '22.6M', trend: 0.95),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Row(
            children: [
              Text('Artists', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
              const Spacer(),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search artists...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.edge)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              childAspectRatio: 0.78,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _artists.length,
            itemBuilder: (context, i) {
              final a = _artists[i];
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.edge),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppTheme.violet.withOpacity(0.2),
                      child: Text(
                        a.name[0],
                        style: const TextStyle(color: AppTheme.violet, fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(a.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(a.genre, style: const TextStyle(color: Color(0xFF9099B8), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('${a.listeners} listeners', style: const TextStyle(color: Color(0xFF9099B8), fontSize: 11)),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.edge,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(a.country, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                        const Spacer(),
                        Text('${(a.trend * 100).toInt()}', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700, fontSize: 14)),
                        const Text(' score', style: TextStyle(color: Color(0xFF9099B8), fontSize: 11)),
                      ],
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

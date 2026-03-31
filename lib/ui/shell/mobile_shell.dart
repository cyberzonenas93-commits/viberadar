import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/home/home_screen.dart';
import '../features/trending/trending_screen.dart';
import '../features/search/search_screen.dart';
import '../features/library/library_screen.dart';
import '../../providers/streaming_provider.dart' show appleMusicProvider, AppleMusicState;
import '../../providers/track_selection_provider.dart';
import '../widgets/selection_action_bar.dart';
import '../../models/track.dart';
import '../../models/user_profile.dart';

/// Mobile navigation shell — bottom tab bar for phones and small tablets.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key, required this.statusMessage});
  final String statusMessage;

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(trackSelectionProvider);
    final hasSelection = selection.selectedIds.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: [
                HomeScreen(
                  allTracks: const [],
                  userProfile: UserProfile.empty(
                    id: 'mobile',
                    displayName: 'DJ',
                  ),
                ),
                const TrendingScreen(),
                const SearchScreen(),
                const LibraryScreen(),
                const _SavedCratesTab(),
              ],
            ),
            if (hasSelection)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 80,
                child: SelectionActionBar(),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MobilePlayerBar(),
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: const Color(0xFF0d0f1a),
            selectedItemColor: const Color(0xFF8f6cff),
            unselectedItemColor: const Color(0xFF636b8c),
            selectedFontSize: 11,
            unselectedFontSize: 11,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.trending_up_outlined),
                activeIcon: Icon(Icons.trending_up),
                label: 'Trending',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search_outlined),
                activeIcon: Icon(Icons.search),
                label: 'Search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music_outlined),
                activeIcon: Icon(Icons.library_music),
                label: 'Library',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.folder_outlined),
                activeIcon: Icon(Icons.folder),
                label: 'Crates',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mini player bar for mobile
class _MobilePlayerBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final am = ref.watch(appleMusicProvider);
    final track = am.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Color(0xFF141728),
        border: Border(top: BorderSide(color: Color(0xFF1e2240))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (track.artworkUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                track.artworkUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 40,
                  height: 40,
                  color: const Color(0xFF1e2240),
                  child: const Icon(Icons.music_note,
                      size: 20, color: Colors.white38),
                ),
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  track.artist,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9ca3c4)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              am.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () {
              if (am.isPlaying) {
                ref.read(appleMusicProvider.notifier).pause();
              } else {
                ref.read(appleMusicProvider.notifier).resume();
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Placeholder saved crates tab for mobile
class _SavedCratesTab extends StatelessWidget {
  const _SavedCratesTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Saved Crates',
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ai_tab.dart';
import 'search_tab.dart';
import 'setlists_tab.dart';
import 'trending_tab.dart';

class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});
  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          SetlistsTab(),
          SearchTab(),
          const TrendingTab(),
          const AiTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.queue_music), label: 'Setlists'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.local_fire_department), label: 'Trending'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'AI'),
        ],
      ),
    );
  }
}

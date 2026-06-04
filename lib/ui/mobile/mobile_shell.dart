import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/vibe_backdrop.dart';
import 'ai_tab.dart';
import 'search_tab.dart';
import 'setlists_tab.dart';
import 'trending_tab.dart';

/// Mobile companion shell.
///
/// Keep the primary navigation focused on the approved phone use cases:
/// setlist curation, search, trending discovery, and AI set building.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _index = 0;
  final Set<int> _visited = {0};

  static const List<Widget> _tabs = [
    SetlistsTab(),
    _MobilePage(title: 'Search', child: SearchTab()),
    _MobilePage(title: 'Trending', child: TrendingTab()),
    AiTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: VibeBackdrop(
        compact: true,
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _visited.contains(i) ? _tabs[i] : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.queue_music_rounded),
            label: 'Setlists',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_fire_department_rounded),
            label: 'Trending',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_rounded),
            label: 'AI',
          ),
        ],
      ),
    );
  }
}

class _MobilePage extends StatelessWidget {
  const _MobilePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: AppTheme.panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: child,
    );
  }
}

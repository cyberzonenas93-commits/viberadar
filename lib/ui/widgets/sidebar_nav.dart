import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_section.dart';

class SidebarNav extends StatelessWidget {
  const SidebarNav({
    super.key,
    required this.selectedSection,
    required this.onSelected,
    required this.statusMessage,
  });

  final AppSection selectedSection;
  final ValueChanged<AppSection> onSelected;
  final String statusMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <({AppSection section, IconData icon, String label})>[
      (section: AppSection.home, icon: Icons.home_rounded, label: 'Home'),
      (
        section: AppSection.trending,
        icon: Icons.local_fire_department_rounded,
        label: 'Trending',
      ),
      (
        section: AppSection.regions,
        icon: Icons.public_rounded,
        label: 'Regions',
      ),
      (
        section: AppSection.genres,
        icon: Icons.library_music_rounded,
        label: 'Genres',
      ),
      (
        section: AppSection.setBuilder,
        icon: Icons.auto_awesome_motion_rounded,
        label: 'Set Builder',
      ),
      (
        section: AppSection.savedCrates,
        icon: Icons.folder_copy_rounded,
        label: 'Saved Crates',
      ),
      (
        section: AppSection.watchlist,
        icon: Icons.visibility_rounded,
        label: 'Watchlist',
      ),
      (
        section: AppSection.settings,
        icon: Icons.settings_rounded,
        label: 'Settings',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.edge),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF151830), Color(0xFF0E1222)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [AppTheme.violet, AppTheme.pink, AppTheme.cyan],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VibeRadar',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'DJ intelligence workstation',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Navigation',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white54,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final item in items) ...[
                    _SidebarButton(
                      selected: item.section == selectedSection,
                      icon: item.icon,
                      label: item.label,
                      onTap: () => onSelected(item.section),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 16),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withValues(alpha: 0.03),
                      border: Border.all(color: AppTheme.edge),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.bolt_rounded,
                              color: AppTheme.cyan,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Workspace Status',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          statusMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? AppTheme.cyan.withValues(alpha: 0.14)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? AppTheme.cyan.withValues(alpha: 0.42)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? AppTheme.cyan : Colors.white70),
              const SizedBox(width: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: selected ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

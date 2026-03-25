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
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: AppTheme.panel,
        border: Border(right: BorderSide(color: AppTheme.edge)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Row(
              children: [
                const Icon(Icons.radio_button_checked, color: AppTheme.violet, size: 22),
                const SizedBox(width: 10),
                Text(
                  'VIBE RADAR',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.violet,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.edge, indent: 20, endIndent: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader('DISCOVER'),
                  _NavItem(section: AppSection.home, icon: Icons.home_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.trending, icon: Icons.local_fire_department_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.artists, icon: Icons.person_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.regions, icon: Icons.public_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.genres, icon: Icons.library_music_rounded, selected: selectedSection, onSelected: onSelected),

                  _SectionHeader('BUILD'),
                  _NavItem(section: AppSection.greatestOf, icon: Icons.star_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.setBuilder, icon: Icons.queue_music_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.aiCopilot, icon: Icons.auto_awesome_rounded, selected: selectedSection, onSelected: onSelected),

                  _SectionHeader('LIBRARY'),
                  _NavItem(section: AppSection.library, icon: Icons.folder_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.duplicates, icon: Icons.content_copy_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.savedCrates, icon: Icons.folder_copy_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.watchlist, icon: Icons.visibility_rounded, selected: selectedSection, onSelected: onSelected),

                  _SectionHeader('EXPORT'),
                  _NavItem(section: AppSection.exports, icon: Icons.upload_rounded, selected: selectedSection, onSelected: onSelected),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const Divider(color: AppTheme.edge, height: 1),
          _NavItem(section: AppSection.settings, icon: Icons.settings_rounded, selected: selectedSection, onSelected: onSelected),
          // Status bar
          if (statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                statusMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.cyan.withValues(alpha: 0.7), fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.edge,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final AppSection section;
  final IconData icon;
  final AppSection selected;
  final ValueChanged<AppSection> onSelected;

  const _NavItem({
    required this.section,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.selected == widget.section;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onSelected(widget.section),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.violet.withValues(alpha: 0.18)
                : _hovered
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? const Border(left: BorderSide(color: AppTheme.violet, width: 3))
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 17,
                color: isActive ? AppTheme.violet : AppTheme.edge,
              ),
              const SizedBox(width: 10),
              Text(
                widget.section.label,
                style: TextStyle(
                  color: isActive ? AppTheme.violet : const Color(0xFF9099B8),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

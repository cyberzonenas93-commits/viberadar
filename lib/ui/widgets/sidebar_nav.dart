import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_section.dart';
import '../../services/ingest_service.dart';

class SidebarNav extends StatefulWidget {
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
  State<SidebarNav> createState() => _SidebarNavState();
}

class _SidebarNavState extends State<SidebarNav> {
  bool _refreshing = false;
  String? _refreshResult;

  Future<void> _refresh() async {
    setState(() { _refreshing = true; _refreshResult = null; });
    final result = await IngestService.triggerIngest();
    if (mounted) {
      setState(() { _refreshing = false; _refreshResult = result; });
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _refreshResult = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSection = widget.selectedSection;
    final onSelected = widget.onSelected;
    final statusMessage = _refreshResult ?? widget.statusMessage;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppTheme.panel,
        border: Border(
          right: BorderSide(color: AppTheme.edge.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.violet, AppTheme.pink],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.radio_button_checked, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Text(
                  'VIBE RADAR',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: AppTheme.edge.withValues(alpha: 0.4), indent: 16, endIndent: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader('DISCOVER'),
                  _NavItem(section: AppSection.forYou, icon: Icons.favorite_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.home, icon: Icons.dashboard_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.trending, icon: Icons.local_fire_department_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.search, icon: Icons.search_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.artists, icon: Icons.person_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.regions, icon: Icons.public_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.genres, icon: Icons.library_music_rounded, selected: selectedSection, onSelected: onSelected),

                  _SectionHeader('BUILD'),
                  _NavItem(section: AppSection.greatestOf, icon: Icons.star_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.setBuilder, icon: Icons.queue_music_rounded, selected: selectedSection, onSelected: onSelected),
                  _NavItem(section: AppSection.aiCopilot, icon: Icons.auto_awesome_rounded, selected: selectedSection, onSelected: onSelected, badge: true),

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
          Divider(color: AppTheme.edge.withValues(alpha: 0.4), height: 1),
          // Refresh / re-ingest button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Material(
              color: _refreshing
                  ? AppTheme.cyan.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _refreshing ? null : _refresh,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      if (_refreshing)
                        const SizedBox(
                          width: 17, height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyan),
                        )
                      else
                        const Icon(Icons.refresh_rounded, size: 17, color: AppTheme.cyan),
                      const SizedBox(width: 10),
                      Text(
                        _refreshing ? 'Refreshing...' : 'Refresh Data',
                        style: TextStyle(
                          color: _refreshing ? AppTheme.cyan : AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _NavItem(section: AppSection.settings, icon: Icons.settings_rounded, selected: selectedSection, onSelected: onSelected),
          // Status bar
          if (statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.cyan.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppTheme.lime,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusMessage,
                        style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: AppTheme.sectionHeader,
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
  final bool badge;

  const _NavItem({
    required this.section,
    required this.icon,
    required this.selected,
    required this.onSelected,
    this.badge = false,
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
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onSelected(widget.section),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.violet.withValues(alpha: 0.15)
                : _hovered
                    ? AppTheme.textPrimary.withValues(alpha: 0.04)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.violet : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                widget.icon,
                size: 17,
                color: isActive ? AppTheme.violet : AppTheme.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.section.label,
                  style: TextStyle(
                    color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ),
              if (widget.badge)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.violet, AppTheme.pink],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

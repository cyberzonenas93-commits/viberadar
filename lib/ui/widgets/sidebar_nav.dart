import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/platform.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_section.dart';
import '../../services/ingest_service.dart';

class SidebarNav extends StatefulWidget {
  const SidebarNav({
    super.key,
    required this.selectedSection,
    required this.onSelected,
    required this.statusMessage,
    this.isDemoMode = false,
    this.onRefreshComplete,
  });

  final AppSection selectedSection;
  final ValueChanged<AppSection> onSelected;
  final String statusMessage;

  /// When true the app is running on demo/offline data (Firebase unavailable);
  /// the status indicator switches to an amber warning so it can't be mistaken
  /// for a healthy "connected" state.
  final bool isDemoMode;

  /// Called after a manual refresh completes so the parent can update the track cache.
  final VoidCallback? onRefreshComplete;

  @override
  State<SidebarNav> createState() => _SidebarNavState();
}

class _SidebarNavState extends State<SidebarNav> {
  bool _refreshing = false;
  String? _refreshResult;

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _refreshResult = null;
    });
    final result = await IngestService.triggerIngest();
    widget.onRefreshComplete?.call();
    if (mounted) {
      setState(() {
        _refreshing = false;
        _refreshResult = result;
      });
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
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.58)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _BrandHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader('DISCOVER'),
                    _NavItem(
                      section: AppSection.forYou,
                      icon: Icons.favorite_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.home,
                      icon: Icons.dashboard_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.trending,
                      icon: Icons.local_fire_department_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.search,
                      icon: Icons.search_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.artists,
                      icon: Icons.person_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.regions,
                      icon: Icons.public_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.genres,
                      icon: Icons.library_music_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.playlists,
                      icon: Icons.playlist_play_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _SectionHeader('COMMUNITY'),
                    _NavItem(
                      section: AppSection.community,
                      icon: Icons.groups_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.myProfile,
                      icon: Icons.account_circle_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.upload,
                      icon: Icons.cloud_upload_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.discoverDJs,
                      icon: Icons.explore_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _SectionHeader('BUILD'),
                    // Mobile-only: the companion's setlists + computer pairing,
                    // preserved as a destination in the mirrored full shell.
                    if (isMobileForm)
                      _NavItem(
                        section: AppSection.setlists,
                        icon: Icons.featured_play_list_rounded,
                        selected: selectedSection,
                        onSelected: onSelected,
                      ),
                    _NavItem(
                      section: AppSection.greatestOf,
                      icon: Icons.star_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.setBuilder,
                      icon: Icons.queue_music_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.aiCopilot,
                      icon: Icons.auto_awesome_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                      badge: true,
                    ),
                    _SectionHeader('LIBRARY'),
                    _NavItem(
                      section: AppSection.library,
                      icon: Icons.folder_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.duplicates,
                      icon: Icons.content_copy_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.savedCrates,
                      icon: Icons.folder_copy_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _NavItem(
                      section: AppSection.watchlist,
                      icon: Icons.visibility_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    _SectionHeader('EXPORT'),
                    _NavItem(
                      section: AppSection.exports,
                      icon: Icons.upload_rounded,
                      selected: selectedSection,
                      onSelected: onSelected,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Divider(color: AppTheme.edge.withValues(alpha: 0.42), height: 1),
            _RefreshButton(refreshing: _refreshing, onRefresh: _refresh),
            _NavItem(
              section: AppSection.settings,
              icon: Icons.settings_rounded,
              selected: selectedSection,
              onSelected: onSelected,
            ),
            if (statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: _StatusPill(
                  statusMessage: statusMessage,
                  isDemoMode: widget.isDemoMode,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.cyan.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VIBERADAR',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'DJ intelligence',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.cyan.withValues(alpha: 0),
                  AppTheme.cyan.withValues(alpha: 0.36),
                  AppTheme.pink.withValues(alpha: 0.26),
                  AppTheme.amber.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: AppTheme.sectionHeader,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.refreshing, required this.onRefresh});

  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: refreshing
            ? AppTheme.cyan.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: refreshing ? null : () => unawaited(onRefresh()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                if (refreshing)
                  const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.cyan,
                    ),
                  )
                else
                  const Icon(
                    Icons.refresh_rounded,
                    color: AppTheme.cyan,
                    size: 17,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    refreshing ? 'Refreshing signals...' : 'Refresh trends',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.statusMessage, required this.isDemoMode});

  final String statusMessage;
  final bool isDemoMode;

  @override
  Widget build(BuildContext context) {
    final color = isDemoMode ? AppTheme.amber : AppTheme.lime;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDemoMode ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              isDemoMode
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_rounded,
              color: color,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isDemoMode ? 'Demo mode: sample data is loaded.' : statusMessage,
              maxLines: isDemoMode ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDemoMode ? AppTheme.amber : AppTheme.textSecondary,
                fontSize: 10.5,
                fontWeight: isDemoMode ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.section,
    required this.icon,
    required this.selected,
    required this.onSelected,
    this.badge = false,
  });

  final AppSection section;
  final IconData icon;
  final AppSection selected;
  final ValueChanged<AppSection> onSelected;
  final bool badge;

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
                ? AppTheme.cyan.withValues(alpha: 0.12)
                : _hovered
                ? AppTheme.textPrimary.withValues(alpha: 0.045)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(color: AppTheme.cyan.withValues(alpha: 0.24))
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.cyan : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
              Icon(
                widget.icon,
                size: 17,
                color: isActive ? AppTheme.cyan : AppTheme.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
              if (widget.badge)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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

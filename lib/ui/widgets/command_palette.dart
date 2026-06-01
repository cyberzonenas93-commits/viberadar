import "dart:ui";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/theme/app_theme.dart";
import "../../models/app_section.dart";
import "../../models/library_track.dart";
import "../../providers/library_provider.dart";

/// A single selectable row in the command palette.
class CommandPaletteItem {
  const CommandPaletteItem({
    required this.label,
    required this.icon,
    required this.category,
    required this.onSelect,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final String category;
  final VoidCallback onSelect;
}

/// Intents used by the palette's Shortcuts/Actions wiring.
class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);
  final int delta;
}

class _ActivateIntent extends Intent {
  const _ActivateIntent();
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}

/// The global command palette — a ⌘K-style floating overlay that lets DJs
/// quickly jump to any screen, search their library, or trigger an action.
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({
    super.key,
    required this.onDismiss,
    required this.onNavigate,
    required this.onOpenTrack,
  });

  final VoidCallback onDismiss;
  final void Function(AppSection) onNavigate;
  final void Function(LibraryTrack) onOpenTrack;

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  static const _maxTrackResults = 25;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  String _query = "";
  int _highlighted = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.text == _query) return;
      setState(() {
        _query = _controller.text;
        _highlighted = 0;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Item sources ──────────────────────────────────────────────────────────

  /// Navigation items — hardcoded list, mirrors the top-level destinations.
  static const _navSections = <_NavSectionEntry>[
    _NavSectionEntry(AppSection.home, Icons.home_rounded),
    _NavSectionEntry(AppSection.forYou, Icons.favorite_rounded),
    _NavSectionEntry(AppSection.trending, Icons.trending_up_rounded),
    _NavSectionEntry(AppSection.library, Icons.library_music_rounded),
    _NavSectionEntry(AppSection.artists, Icons.people_rounded),
    _NavSectionEntry(AppSection.greatestOf, Icons.emoji_events_rounded),
    _NavSectionEntry(AppSection.aiCopilot, Icons.auto_awesome_rounded),
    _NavSectionEntry(AppSection.community, Icons.groups_rounded),
    _NavSectionEntry(AppSection.duplicates, Icons.copy_all_rounded),
    _NavSectionEntry(AppSection.exports, Icons.ios_share_rounded),
    _NavSectionEntry(AppSection.settings, Icons.settings_rounded),
  ];

  List<CommandPaletteItem> _buildItems(BuildContext context) {
    final items = <CommandPaletteItem>[];
    final q = _query.trim().toLowerCase();

    // ── Navigation ────────────────────────────────────────────────────────
    for (final entry in _navSections) {
      final label = entry.section.label;
      if (q.isEmpty || label.toLowerCase().contains(q)) {
        items.add(CommandPaletteItem(
          label: label,
          icon: entry.icon,
          category: "Go to",
          onSelect: () => widget.onNavigate(entry.section),
        ));
      }
    }

    // ── Tracks (only when user has typed something) ──────────────────────
    if (q.isNotEmpty) {
      final libraryTracks = ref.read(libraryProvider).tracks;
      final matches = <LibraryTrack>[];
      for (final t in libraryTracks) {
        if (matches.length >= _maxTrackResults) break;
        if (t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q)) {
          matches.add(t);
        }
      }
      for (final t in matches) {
        items.add(CommandPaletteItem(
          label: t.title.isEmpty ? t.fileName : t.title,
          subtitle: t.artist.isEmpty ? null : t.artist,
          icon: Icons.music_note_rounded,
          category: "Tracks",
          onSelect: () => widget.onOpenTrack(t),
        ));
      }
    }

    // ── Actions ──────────────────────────────────────────────────────────
    final actions = <CommandPaletteItem>[
      CommandPaletteItem(
        label: "Scan Library",
        subtitle: "Jump to Library to pick a folder to scan",
        icon: Icons.folder_open_rounded,
        category: "Actions",
        onSelect: () => widget.onNavigate(AppSection.library),
      ),
      CommandPaletteItem(
        label: "Refresh Trending",
        subtitle: "Open the Trending view",
        icon: Icons.refresh_rounded,
        category: "Actions",
        onSelect: () => widget.onNavigate(AppSection.trending),
      ),
      CommandPaletteItem(
        label: "Open Settings",
        subtitle: "Adjust preferences",
        icon: Icons.settings_rounded,
        category: "Actions",
        onSelect: () => widget.onNavigate(AppSection.settings),
      ),
      CommandPaletteItem(
        label: "Find Duplicates",
        subtitle: "Review duplicate tracks in your library",
        icon: Icons.copy_all_rounded,
        category: "Actions",
        onSelect: () => widget.onNavigate(AppSection.duplicates),
      ),
      CommandPaletteItem(
        label: "Open Exports",
        subtitle: "Export crates to Rekordbox, Serato, Virtual DJ",
        icon: Icons.ios_share_rounded,
        category: "Actions",
        onSelect: () => widget.onNavigate(AppSection.exports),
      ),
    ];
    for (final a in actions) {
      if (q.isEmpty ||
          a.label.toLowerCase().contains(q) ||
          (a.subtitle?.toLowerCase().contains(q) ?? false)) {
        items.add(a);
      }
    }

    return items;
  }

  // ── Keyboard handling ─────────────────────────────────────────────────────

  void _move(int delta, int itemCount) {
    if (itemCount == 0) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, itemCount - 1);
    });
    _ensureHighlightedVisible();
  }

  void _ensureHighlightedVisible() {
    if (!_scroll.hasClients) return;
    const rowHeight = 56.0; // approx, matches _ResultRow layout
    final targetTop = _highlighted * rowHeight;
    final targetBottom = targetTop + rowHeight;
    final viewTop = _scroll.offset;
    final viewBottom = viewTop + _scroll.position.viewportDimension;
    if (targetTop < viewTop) {
      _scroll.animateTo(
        targetTop,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    } else if (targetBottom > viewBottom) {
      _scroll.animateTo(
        targetBottom - _scroll.position.viewportDimension,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    }
  }

  void _activate(List<CommandPaletteItem> items) {
    if (items.isEmpty) return;
    if (_highlighted < 0 || _highlighted >= items.length) return;
    final selected = items[_highlighted];
    widget.onDismiss();
    selected.onSelect();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(context);
    if (_highlighted >= items.length) {
      _highlighted = items.isEmpty ? 0 : items.length - 1;
    }

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(-1),
        SingleActivator(LogicalKeyboardKey.enter): _ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
      },
      child: Actions(
        actions: {
          _MoveIntent: CallbackAction<_MoveIntent>(
            onInvoke: (intent) {
              _move(intent.delta, items.length);
              return null;
            },
          ),
          _ActivateIntent: CallbackAction<_ActivateIntent>(
            onInvoke: (_) {
              _activate(items);
              return null;
            },
          ),
          _DismissIntent: CallbackAction<_DismissIntent>(
            onInvoke: (_) {
              widget.onDismiss();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              // Blurred, tap-to-dismiss backdrop.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDismiss,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(color: Colors.black.withValues(alpha: 0.35)),
                  ),
                ),
              ),
              // Centered floating palette.
              Align(
                alignment: const Alignment(0, -0.4),
                child: _PaletteCard(
                  controller: _controller,
                  searchFocus: _searchFocus,
                  scrollController: _scroll,
                  items: items,
                  highlighted: _highlighted,
                  onHover: (i) => setState(() => _highlighted = i),
                  onTap: (i) {
                    _highlighted = i;
                    _activate(items);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSectionEntry {
  const _NavSectionEntry(this.section, this.icon);
  final AppSection section;
  final IconData icon;
}

// ── Palette card ────────────────────────────────────────────────────────────

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({
    required this.controller,
    required this.searchFocus,
    required this.scrollController,
    required this.items,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final TextEditingController controller;
  final FocusNode searchFocus;
  final ScrollController scrollController;
  final List<CommandPaletteItem> items;
  final int highlighted;
  final void Function(int) onHover;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: AppTheme.panelRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.edge.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SearchField(controller: controller, focusNode: searchFocus),
              Divider(
                height: 1,
                thickness: 1,
                color: AppTheme.edge.withValues(alpha: 0.6),
              ),
              _ResultList(
                items: items,
                highlighted: highlighted,
                scrollController: scrollController,
                onHover: onHover,
                onTap: onTap,
              ),
              _FooterHint(resultCount: items.length),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Search field ────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppTheme.textTertiary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: AppTheme.violet,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: "Search screens, tracks, actions...",
                hintStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 16),
              ),
            ),
          ),
          const _KeyHint(label: "esc"),
        ],
      ),
    );
  }
}

// ── Result list ─────────────────────────────────────────────────────────────

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.items,
    required this.highlighted,
    required this.scrollController,
    required this.onHover,
    required this.onTap,
  });

  final List<CommandPaletteItem> items;
  final int highlighted;
  final ScrollController scrollController;
  final void Function(int) onHover;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(
            "No results",
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 14),
          ),
        ),
      );
    }

    // Compute group boundaries so we can render category headers.
    final widgets = <Widget>[];
    String? currentCategory;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.category != currentCategory) {
        currentCategory = item.category;
        widgets.add(_CategoryHeader(label: item.category));
      }
      widgets.add(
        _ResultRow(
          item: item,
          isHighlighted: i == highlighted,
          onEnter: () => onHover(i),
          onTap: () => onTap(i),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: Scrollbar(
        controller: scrollController,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(vertical: 6),
          shrinkWrap: true,
          children: widgets,
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.sectionHeader,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.item,
    required this.isHighlighted,
    required this.onEnter,
    required this.onTap,
  });

  final CommandPaletteItem item;
  final bool isHighlighted;
  final VoidCallback onEnter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isHighlighted
        ? AppTheme.violet.withValues(alpha: 0.18)
        : Colors.transparent;
    final iconColor =
        isHighlighted ? AppTheme.violet : AppTheme.textSecondary;
    return MouseRegion(
      onEnter: (_) => onEnter(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted
                  ? AppTheme.violet.withValues(alpha: 0.4)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (item.subtitle != null && item.subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (isHighlighted)
                const _KeyHint(label: "return", accent: true),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Footer & key hint ───────────────────────────────────────────────────────

class _FooterHint extends StatelessWidget {
  const _FooterHint({required this.resultCount});
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          _hint("\u2191\u2193", "navigate"),
          const SizedBox(width: 16),
          _hint("\u21B5", "select"),
          const Spacer(),
          Text(
            "$resultCount result${resultCount == 1 ? '' : 's'}",
            style: const TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.edge.withValues(alpha: 0.6)),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.label, this.accent = false});
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent
            ? AppTheme.violet.withValues(alpha: 0.2)
            : AppTheme.panel,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: accent
              ? AppTheme.violet.withValues(alpha: 0.5)
              : AppTheme.edge.withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent ? AppTheme.violet : AppTheme.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Entry-point helper ──────────────────────────────────────────────────────

/// Open the command palette as a dialog. Dismisses on backdrop tap, Esc,
/// or after a selection is made.
void showCommandPalette(
  BuildContext context, {
  required void Function(AppSection) onNavigate,
  required void Function(LibraryTrack) onOpenTrack,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    builder: (dialogContext) {
      return CommandPalette(
        onDismiss: () => Navigator.of(dialogContext).pop(),
        onNavigate: (section) {
          onNavigate(section);
        },
        onOpenTrack: (track) {
          onOpenTrack(track);
        },
      );
    },
  );
}

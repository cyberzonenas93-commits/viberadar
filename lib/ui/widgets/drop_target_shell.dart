import 'dart:developer' as developer;
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_theme.dart';
import '../../providers/library_provider.dart';

// ── Dropped-item classification ─────────────────────────────────────────────

/// Classification of a dropped filesystem entry.
enum DropType { directory, audioFile, unsupported }

/// Audio extensions we accept via drag-drop. Kept in sync with the scanner's
/// own extension list where practical.
const Set<String> kSupportedAudioExtensions = {
  '.mp3', '.wav', '.flac', '.aiff', '.aif', '.m4a', '.ogg', '.aac',
};

/// Pure-function classifier — testable without touching the filesystem.
/// If [existsOverride] is provided, it's used to answer "is this a directory
/// / file / missing"; otherwise we hit `dart:io` directly.
DropType classifyDroppedPath(
  String path, {
  FileSystemEntityType Function(String)? existsOverride,
}) {
  final type = existsOverride != null
      ? existsOverride(path)
      : FileSystemEntity.typeSync(path, followLinks: true);
  if (type == FileSystemEntityType.directory) return DropType.directory;
  if (type == FileSystemEntityType.file) {
    final ext = p.extension(path).toLowerCase();
    if (kSupportedAudioExtensions.contains(ext)) return DropType.audioFile;
  }
  return DropType.unsupported;
}

// ── Widget ──────────────────────────────────────────────────────────────────

/// Wraps [child] in a drop target. On valid drop:
///   - directory → kicks off a library scan of that path
///   - audio file → scans its parent directory (the scanner picks it up + any
///     siblings; treating a single track as a one-off is a lot of plumbing)
///   - unsupported → SnackBar explaining what was rejected
class DropTargetShell extends ConsumerStatefulWidget {
  const DropTargetShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DropTargetShell> createState() => _DropTargetShellState();
}

class _DropTargetShellState extends ConsumerState<DropTargetShell>
    with SingleTickerProviderStateMixin {
  bool _dragging = false;
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _setDragging(bool v) {
    if (v == _dragging) return;
    setState(() => _dragging = v);
    if (v) {
      _fade.forward();
    } else {
      _fade.reverse();
    }
  }

  Future<void> _onDrop(List<XFile> files) async {
    _setDragging(false);
    if (files.isEmpty) return;

    final dirs = <String>[];
    final unsupported = <String>[];

    for (final f in files) {
      switch (classifyDroppedPath(f.path)) {
        case DropType.directory:
          dirs.add(f.path);
        case DropType.audioFile:
          dirs.add(p.dirname(f.path));
        case DropType.unsupported:
          unsupported.add(p.basename(f.path));
      }
    }

    if (dirs.isEmpty && unsupported.isNotEmpty) {
      _showSnack('Unsupported files: ${unsupported.join(", ")}');
      return;
    }

    // De-duplicate — dropping 3 audio files from the same folder should scan
    // that folder once, not three times.
    final uniqueDirs = dirs.toSet().toList();

    for (final dir in uniqueDirs) {
      try {
        await ref.read(libraryProvider.notifier).scanDirectory(dir);
      } catch (e, st) {
        developer.log('Drop scan failed for $dir',
            name: 'DropTargetShell', error: e, stackTrace: st);
        _showSnack('Failed to scan $dir');
      }
    }

    if (uniqueDirs.isNotEmpty) {
      _showSnack(
        uniqueDirs.length == 1
            ? 'Scanning ${uniqueDirs.first}…'
            : 'Scanning ${uniqueDirs.length} folders…',
      );
    }
    if (unsupported.isNotEmpty) {
      _showSnack(
        'Skipped ${unsupported.length} unsupported file${unsupported.length == 1 ? "" : "s"}',
      );
    }
  }

  void _showSnack(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => _setDragging(true),
      onDragExited: (_) => _setDragging(false),
      onDragDone: (detail) => _onDrop(detail.files),
      child: Stack(
        children: [
          widget.child,
          IgnorePointer(
            ignoring: !_dragging,
            child: FadeTransition(
              opacity: _fade,
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.file_download_outlined,
                        size: 72,
                        color: AppTheme.violet,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Drop to import',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Audio files or folders',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

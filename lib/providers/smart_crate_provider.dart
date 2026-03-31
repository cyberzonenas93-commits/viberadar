import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/smart_crate_generator_service.dart';
import '../services/export_service.dart';
import '../services/dj_root_detection_service.dart';
import '../services/virtual_dj_export_service.dart';
import '../services/serato_export_service.dart';
import '../core/theme/app_theme.dart';
import 'library_provider.dart';

// ── State ────────────────────────────────────────────────────────────────────

class SmartCrateState {
  const SmartCrateState({
    this.preferences = const SmartCratePreferences(),
    this.isGenerating = false,
    this.crates = const [],
    this.error,
    this.progress = '',
  });

  final SmartCratePreferences preferences;
  final bool isGenerating;
  final List<GeneratedCrate> crates;
  final String? error;
  final String progress;

  SmartCrateState copyWith({
    SmartCratePreferences? preferences,
    bool? isGenerating,
    List<GeneratedCrate>? crates,
    Object? error = _sentinel,
    String? progress,
  }) =>
      SmartCrateState(
        preferences: preferences ?? this.preferences,
        isGenerating: isGenerating ?? this.isGenerating,
        crates: crates ?? this.crates,
        error: identical(error, _sentinel) ? this.error : error as String?,
        progress: progress ?? this.progress,
      );
}

const _sentinel = Object();

// ── Notifier ─────────────────────────────────────────────────────────────────

class SmartCrateNotifier extends Notifier<SmartCrateState> {
  @override
  SmartCrateState build() => const SmartCrateState();

  final SmartCrateGeneratorService _service = SmartCrateGeneratorService();

  // ── Preference setters ─────────────────────────────────────────────────

  void updatePreferences(SmartCratePreferences prefs) {
    state = state.copyWith(preferences: prefs);
  }

  void setGenres(List<String> genres) {
    state = state.copyWith(
      preferences: state.preferences.copyWith(genres: genres),
    );
  }

  void toggleGenre(String genre) {
    final current = List<String>.from(state.preferences.genres);
    if (current.contains(genre)) {
      current.remove(genre);
    } else {
      current.add(genre);
    }
    state = state.copyWith(
      preferences: state.preferences.copyWith(genres: current),
    );
  }

  void setBpmRange(double min, double max) {
    state = state.copyWith(
      preferences: state.preferences.copyWith(minBpm: min, maxBpm: max),
    );
  }

  void setMood(String? mood) {
    state = state.copyWith(
      preferences: state.preferences.copyWith(mood: mood),
    );
  }

  void setEnergyLevel(String? energy) {
    state = state.copyWith(
      preferences: state.preferences.copyWith(energyLevel: energy),
    );
  }

  void setCrateCount(int count) {
    state = state.copyWith(
      preferences: state.preferences.copyWith(crateCount: count),
    );
  }

  void setCustomPrompt(String? prompt) {
    state = state.copyWith(
      preferences: state.preferences.copyWith(customPrompt: prompt),
    );
  }

  // ── Generate ───────────────────────────────────────────────────────────

  Future<void> generate() async {
    final lib = ref.read(libraryProvider);
    if (lib.tracks.isEmpty) {
      state = state.copyWith(error: 'No tracks in library. Scan a folder first.');
      return;
    }

    state = state.copyWith(
      isGenerating: true,
      error: null,
      crates: [],
      progress: 'Analyzing library and building track manifest...',
    );

    try {
      state = state.copyWith(
        progress: 'Sending ${lib.tracks.length} tracks to AI for crate generation...',
      );

      final crates = await _service.generate(lib.tracks, state.preferences);

      if (crates.isEmpty) {
        state = state.copyWith(
          isGenerating: false,
          error: 'AI did not return any crates. Check your API key and try again.',
          progress: '',
        );
      } else {
        state = state.copyWith(
          isGenerating: false,
          crates: crates,
          progress: '',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: 'Generation failed: $e',
        progress: '',
      );
    }
  }

  // ── Save to local crates ───────────────────────────────────────────────

  void saveCrate(int index) {
    if (index < 0 || index >= state.crates.length) return;
    final crate = state.crates[index];
    final crateNotifier = ref.read(crateProvider.notifier);

    crateNotifier.createCrate(crate.name);
    for (final track in crate.tracks) {
      crateNotifier.addTrackToCrate(crate.name, track.id);
    }
  }

  // ── Export to VirtualDJ ────────────────────────────────────────────────

  Future<void> exportToVdj(int index, BuildContext context) async {
    if (index < 0 || index >= state.crates.length) return;
    final crate = state.crates[index];

    try {
      final rootSvc = DjRootDetectionService();
      final vdjRoot = await rootSvc.resolveVirtualDjRoot();
      if (vdjRoot == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('VirtualDJ not found. Install VirtualDJ and try again.'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }

      final lib = ref.read(libraryProvider);
      final result = await VirtualDjExportService().exportCrate(
        vdjRoot: vdjRoot,
        playlistName: crate.name,
        tracks: crate.tracks,
        localLibrary: lib.tracks.isNotEmpty ? lib.tracks : null,
      );

      if (context.mounted) {
        final trackCount = result.tracks.where((t) => t.isLocal).length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Exported "${crate.name}" to VirtualDJ ($trackCount tracks)\n${result.outputPath}'),
          backgroundColor: AppTheme.lime,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Show in Finder',
            textColor: Colors.white,
            onPressed: () => ExportService.revealInFinder(result.outputPath),
          ),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('VirtualDJ export failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Export to Serato ───────────────────────────────────────────────────

  Future<void> exportToSerato(int index, BuildContext context) async {
    if (index < 0 || index >= state.crates.length) return;
    final crate = state.crates[index];

    try {
      final rootSvc = DjRootDetectionService();
      final seratoRoot = await rootSvc.resolveSeratoRoot();
      if (seratoRoot == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Serato not found. Install Serato DJ and try again.'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }

      final result = await SeratoExportService().exportCrate(
        seratoRoot: seratoRoot,
        crateName: crate.name,
        tracks: crate.tracks,
      );

      if (context.mounted) {
        final trackCount = result.tracks.where((t) => t.isLocal).length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Exported "${crate.name}" to Serato ($trackCount tracks)\n${result.outputPath}'),
          backgroundColor: AppTheme.lime,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Show in Finder',
            textColor: Colors.white,
            onPressed: () => ExportService.revealInFinder(result.outputPath),
          ),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Serato export failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Export M3U ─────────────────────────────────────────────────────────

  Future<void> exportToM3u(int index, BuildContext context) async {
    if (index < 0 || index >= state.crates.length) return;
    final crate = state.crates[index];

    final buf = StringBuffer();
    buf.writeln('#EXTM3U');
    for (final t in crate.tracks) {
      buf.writeln('#EXTINF:${t.durationSeconds.round()},${t.artist} - ${t.title}');
      buf.writeln(t.filePath);
    }

    try {
      final exportService = ExportService();
      final path = await exportService.exportM3u(
        ExportCrate(name: crate.name, tracks: crate.tracks),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('M3U exported: $path')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('M3U export failed: $e')),
        );
      }
    }
  }
}

final smartCrateProvider =
    NotifierProvider<SmartCrateNotifier, SmartCrateState>(
        SmartCrateNotifier.new);

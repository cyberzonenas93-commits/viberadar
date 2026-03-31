import 'dart:convert';
import 'dart:developer' as dev;

import '../models/library_track.dart';
import 'ai_copilot_service.dart';

// ── Preferences model ────────────────────────────────────────────────────────

class SmartCratePreferences {
  const SmartCratePreferences({
    this.genres = const [],
    this.minBpm,
    this.maxBpm,
    this.mood,
    this.energyLevel,
    this.mixingStyle,
    this.crateCount = 3,
    this.customPrompt,
  });

  final List<String> genres;
  final double? minBpm;
  final double? maxBpm;
  final String? mood;
  final String? energyLevel;
  final String? mixingStyle;
  final int crateCount;
  final String? customPrompt;

  SmartCratePreferences copyWith({
    List<String>? genres,
    double? minBpm,
    double? maxBpm,
    String? mood,
    String? energyLevel,
    String? mixingStyle,
    int? crateCount,
    String? customPrompt,
  }) =>
      SmartCratePreferences(
        genres: genres ?? this.genres,
        minBpm: minBpm ?? this.minBpm,
        maxBpm: maxBpm ?? this.maxBpm,
        mood: mood ?? this.mood,
        energyLevel: energyLevel ?? this.energyLevel,
        mixingStyle: mixingStyle ?? this.mixingStyle,
        crateCount: crateCount ?? this.crateCount,
        customPrompt: customPrompt ?? this.customPrompt,
      );
}

// ── Generated crate result ───────────────────────────────────────────────────

class GeneratedCrate {
  const GeneratedCrate({
    required this.name,
    required this.description,
    required this.tracks,
  });

  final String name;
  final String description;
  final List<LibraryTrack> tracks;

  double get totalDurationSeconds =>
      tracks.fold(0.0, (sum, t) => sum + t.durationSeconds);

  String get totalDurationFormatted {
    final totalSec = totalDurationSeconds.round();
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }
}

// ── Service ──────────────────────────────────────────────────────────────────

class SmartCrateGeneratorService {
  final AiCopilotService _ai = AiCopilotService();

  /// Generates smart crates from the user's library using AI in batches.
  ///
  /// Strategy for large libraries (e.g. 17,000 tracks):
  /// 1. Pre-filter by user preferences (genre, BPM)
  /// 2. Send tracks to AI in batches of ~300 — AI picks the best from each batch
  /// 3. Combine all AI-selected tracks
  /// 4. Final AI pass to organize selections into named crates with sequencing
  ///
  /// This means AI actually curates every track, not just names groups.
  Future<List<GeneratedCrate>> generate(
    List<LibraryTrack> library,
    SmartCratePreferences prefs,
  ) async {
    if (library.isEmpty) return [];

    // Pre-filter by user preferences
    var filtered = _preFilter(library, prefs);
    if (filtered.isEmpty) filtered = library;

    // Shuffle so we don't always pick from the same alphabetical slice
    filtered.shuffle();

    dev.log(
      'SmartCrateGenerator: ${library.length} total, ${filtered.length} after pre-filter',
      name: 'SmartCrate',
    );

    final trackMap = {for (final t in filtered) t.id: t};

    // Target: ~40-80 tracks per crate
    final targetPerCrate = 50;
    final totalTarget = targetPerCrate * prefs.crateCount;

    // If library is small enough, send it all at once (old behavior but working)
    if (filtered.length <= 400) {
      return _singlePassGenerate(filtered, trackMap, prefs);
    }

    // Large library: batch selection
    final selectedIds = <String>{};
    final batchSize = 300;
    final batches = <List<LibraryTrack>>[];
    for (var i = 0; i < filtered.length; i += batchSize) {
      batches.add(filtered.sublist(i, (i + batchSize).clamp(0, filtered.length)));
    }

    // How many tracks to pick per batch (distribute evenly)
    final picksPerBatch = (totalTarget / batches.length).ceil().clamp(10, 80);

    dev.log('SmartCrateGenerator: ${batches.length} batches, picking ~$picksPerBatch per batch', name: 'SmartCrate');

    // Process batches — AI selects best tracks from each
    for (var i = 0; i < batches.length && selectedIds.length < totalTarget * 1.5; i++) {
      final batch = batches[i];
      final manifest = _buildCompactManifest(batch);
      final selectionPrompt = '''You are a DJ track selector. From this batch of ${batch.length} tracks, pick the $picksPerBatch BEST tracks for DJ crates.

USER PREFERENCES:
${prefs.genres.isNotEmpty ? 'Genres: ${prefs.genres.join(", ")}' : 'All genres'}
${prefs.mood != null ? 'Mood: ${prefs.mood}' : ''}
${prefs.energyLevel != null ? 'Energy: ${prefs.energyLevel}' : ''}
${prefs.mixingStyle != null ? 'Style: ${prefs.mixingStyle}' : ''}
${prefs.customPrompt != null && prefs.customPrompt!.isNotEmpty ? 'Custom: ${prefs.customPrompt}' : ''}

$manifest

Pick tracks that:
- Are actual songs (not sound effects, intros, jingles, sleep music, ambient noise)
- Match the requested genre/mood/energy
- Would work well in a DJ set
- Have good BPM and key for mixing

Reply with ONLY a JSON array of selected track IDs, nothing else:
["id1","id2","id3"]''';

      try {
        final response = await _ai.chat(const [], selectionPrompt, trackContext: null);
        final ids = _parseIdArray(response);
        selectedIds.addAll(ids.where((id) => trackMap.containsKey(id)));
        dev.log('SmartCrateGenerator: batch ${i + 1}/${batches.length} → ${ids.length} picked, ${selectedIds.length} total', name: 'SmartCrate');
      } catch (e) {
        dev.log('SmartCrateGenerator: batch ${i + 1} failed: $e', name: 'SmartCrate');
      }
    }

    if (selectedIds.isEmpty) {
      dev.log('SmartCrateGenerator: no tracks selected, falling back to local grouping', name: 'SmartCrate');
      return _localFallback(filtered, prefs);
    }

    // Final pass: organize selected tracks into named crates
    final selectedTracks = selectedIds.map((id) => trackMap[id]!).toList();
    return _organizationPass(selectedTracks, trackMap, prefs);
  }

  /// Single-pass for small libraries (<=400 tracks) — send everything to AI
  Future<List<GeneratedCrate>> _singlePassGenerate(
    List<LibraryTrack> tracks,
    Map<String, LibraryTrack> trackMap,
    SmartCratePreferences prefs,
  ) async {
    final manifest = _buildCompactManifest(tracks);
    final summary = _buildSummary(tracks);
    final userMessage = _buildUserMessage(summary, manifest, prefs);

    final response = await _ai.chat(const [], userMessage, trackContext: null);
    return _parseResponse(response, trackMap);
  }

  /// Final AI pass to organize pre-selected tracks into named crates
  Future<List<GeneratedCrate>> _organizationPass(
    List<LibraryTrack> selected,
    Map<String, LibraryTrack> trackMap,
    SmartCratePreferences prefs,
  ) async {
    final manifest = _buildCompactManifest(selected);
    final prompt = '''You are VibeRadar Smart Crate Generator. Organize these ${selected.length} pre-selected DJ tracks into ${prefs.crateCount} crates.

$manifest

RULES:
- Use ONLY track IDs from the list above
- Each crate: creative DJ name + one-line description
- Consider BPM flow, key compatibility, energy progression, genre cohesion
- Distribute tracks roughly evenly across crates
- Order tracks within each crate for smooth DJ mixing (BPM/key flow)
${prefs.mood != null ? '- Mood: ${prefs.mood}' : ''}
${prefs.energyLevel != null ? '- Energy: ${prefs.energyLevel}' : ''}
${prefs.mixingStyle != null ? '- Style: ${prefs.mixingStyle}' : ''}

Reply with ONLY this JSON, no other text:
```crate
{"crates":[{"name":"Name","description":"Description","trackIds":["id1","id2"]}]}
```''';

    try {
      final response = await _ai.chat(const [], prompt, trackContext: null);
      final crates = _parseResponse(response, trackMap);
      if (crates.isNotEmpty) return crates;
    } catch (e) {
      dev.log('SmartCrateGenerator: organization pass failed: $e', name: 'SmartCrate');
    }

    // Fallback: split selected tracks into groups locally
    return _localFallback(selected, prefs);
  }

  /// Fallback: group tracks locally by genre when AI completely fails
  List<GeneratedCrate> _localFallback(List<LibraryTrack> tracks, SmartCratePreferences prefs) {
    final groups = _groupTracksLocally(tracks, prefs.crateCount);
    return groups.asMap().entries.map((e) {
      final topGenre = _topGenreOf(e.value);
      return GeneratedCrate(
        name: '$topGenre Mix ${e.key + 1}',
        description: '${e.value.length} tracks — auto-grouped by genre & BPM',
        tracks: e.value,
      );
    }).toList();
  }

  /// Build a compact manifest using minimal tokens
  String _buildCompactManifest(List<LibraryTrack> tracks) {
    final buf = StringBuffer();
    buf.writeln('TRACKS (ID|Title|Artist|BPM|Key|Genre):');
    for (final t in tracks) {
      buf.writeln('${t.id}|${t.title}|${t.artist}|${t.bpm.toStringAsFixed(0)}|${t.key}|${t.genre}');
    }
    return buf.toString();
  }

  /// Parse a JSON array of track IDs from AI response
  List<String> _parseIdArray(String response) {
    try {
      final arrayRegex = RegExp(r'\[[\s\S]*?\]');
      final match = arrayRegex.firstMatch(response);
      if (match == null) return [];
      final list = jsonDecode(match.group(0)!) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (e) {
      return [];
    }
  }

  /// Groups tracks locally using genre + BPM clustering.
  /// This processes ALL tracks — no 500-track cap.
  List<List<LibraryTrack>> _groupTracksLocally(List<LibraryTrack> tracks, int targetGroups) {
    // Step 1: Group by primary genre
    final byGenre = <String, List<LibraryTrack>>{};
    for (final t in tracks) {
      final genre = t.genre.isNotEmpty && t.genre != 'Unknown' ? t.genre : 'Mixed';
      (byGenre[genre] ??= []).add(t);
    }

    // Step 2: If we have more genre groups than target, merge small ones
    var entries = byGenre.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));

    if (entries.length <= targetGroups) {
      // Already at or below target — use genre groups directly
      return entries.map((e) {
        final list = e.value;
        // Sort by BPM within each group for DJ flow
        list.sort((a, b) => a.bpm.compareTo(b.bpm));
        return list;
      }).toList();
    }

    // Take top N-1 genres, merge rest into "Mixed"
    final result = <List<LibraryTrack>>[];
    final mixed = <LibraryTrack>[];
    for (var i = 0; i < entries.length; i++) {
      if (i < targetGroups - 1) {
        final list = entries[i].value;
        list.sort((a, b) => a.bpm.compareTo(b.bpm));
        result.add(list);
      } else {
        mixed.addAll(entries[i].value);
      }
    }
    if (mixed.isNotEmpty) {
      // Split mixed by BPM ranges for better DJ utility
      mixed.sort((a, b) => a.bpm.compareTo(b.bpm));
      result.add(mixed);
    }

    // Step 3: If large groups exist (>200 tracks), split by BPM sub-ranges
    final finalResult = <List<LibraryTrack>>[];
    for (final group in result) {
      if (group.length > 200 && finalResult.length < targetGroups) {
        // Split into low/high BPM halves
        final mid = group.length ~/ 2;
        finalResult.add(group.sublist(0, mid));
        finalResult.add(group.sublist(mid));
      } else {
        finalResult.add(group);
      }
    }

    // Trim to target count if we went over
    while (finalResult.length > targetGroups && finalResult.length > 1) {
      // Merge the two smallest groups
      finalResult.sort((a, b) => a.length.compareTo(b.length));
      final smallest = finalResult.removeAt(0);
      finalResult[0].addAll(smallest);
      finalResult[0].sort((a, b) => a.bpm.compareTo(b.bpm));
    }

    return finalResult;
  }

  String _topGenreOf(List<LibraryTrack> tracks) {
    final counts = <String, int>{};
    for (final t in tracks) {
      final g = t.genre.isNotEmpty && t.genre != 'Unknown' ? t.genre : 'Mixed';
      counts[g] = (counts[g] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'Mixed';
    return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  List<Map<String, String>> _parseNamingResponse(String response, int expectedCount) {
    try {
      // Find JSON array in response
      final arrayRegex = RegExp(r'\[[\s\S]*\]');
      final match = arrayRegex.firstMatch(response);
      if (match == null) return [];
      final list = jsonDecode(match.group(0)!) as List<dynamic>;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return {'name': m['name']?.toString() ?? '', 'description': m['description']?.toString() ?? ''};
      }).toList();
    } catch (e) {
      dev.log('SmartCrateGenerator: naming parse error: $e', name: 'SmartCrate');
      return [];
    }
  }

  // ── Pre-filter ─────────────────────────────────────────────────────────────

  List<LibraryTrack> _preFilter(
    List<LibraryTrack> library,
    SmartCratePreferences prefs,
  ) {
    return library.where((t) {
      if (prefs.genres.isNotEmpty &&
          !prefs.genres.any(
            (g) => t.genre.toLowerCase().contains(g.toLowerCase()),
          )) {
        return false;
      }
      if (prefs.minBpm != null && t.bpm > 0 && t.bpm < prefs.minBpm!) {
        return false;
      }
      if (prefs.maxBpm != null && t.bpm > 0 && t.bpm > prefs.maxBpm!) {
        return false;
      }
      return true;
    }).toList();
  }

  // ── Summary builder ────────────────────────────────────────────────────────

  String _buildSummary(List<LibraryTrack> library) {
    final genreCounts = <String, int>{};
    final artistCounts = <String, int>{};
    double minBpm = double.infinity, maxBpm = 0;
    int minYear = 9999, maxYear = 0;

    for (final t in library) {
      if (t.genre.isNotEmpty && t.genre != 'Unknown') {
        genreCounts[t.genre] = (genreCounts[t.genre] ?? 0) + 1;
      }
      if (t.artist.isNotEmpty && t.artist != 'Unknown Artist') {
        artistCounts[t.artist] = (artistCounts[t.artist] ?? 0) + 1;
      }
      if (t.bpm > 0) {
        if (t.bpm < minBpm) minBpm = t.bpm;
        if (t.bpm > maxBpm) maxBpm = t.bpm;
      }
      if (t.year != null && t.year! > 1900) {
        if (t.year! < minYear) minYear = t.year!;
        if (t.year! > maxYear) maxYear = t.year!;
      }
    }

    final topGenres = (genreCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(10)
        .map((e) => '${e.key}(${e.value})')
        .join(', ');

    final topArtists = (artistCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(15)
        .map((e) => e.key)
        .join(', ');

    final buf = StringBuffer();
    buf.writeln('LIBRARY SUMMARY:');
    buf.writeln('Total tracks: ${library.length}');
    buf.writeln('Top genres: $topGenres');
    buf.writeln('Top artists: $topArtists');
    if (minBpm < double.infinity && maxBpm > 0) {
      buf.writeln(
        'BPM range: ${minBpm.toStringAsFixed(0)}-${maxBpm.toStringAsFixed(0)}',
      );
    }
    if (minYear < 9999 && maxYear > 0) {
      buf.writeln('Year range: $minYear-$maxYear');
    }
    return buf.toString();
  }

  // ── Manifest builder ───────────────────────────────────────────────────────

  String _buildManifest(List<LibraryTrack> tracks) {
    final buf = StringBuffer();
    buf.writeln('TRACK MANIFEST (ID|Title|Artist|BPM|Key|Genre):');
    for (final t in tracks) {
      buf.writeln(
        '${t.id}|${t.title}|${t.artist}|${t.bpm.toStringAsFixed(0)}|${t.key}|${t.genre}',
      );
    }
    return buf.toString();
  }

  // ── Prompt builders ────────────────────────────────────────────────────────

  String _buildSystemPrompt(
    String summary,
    String manifest,
    SmartCratePreferences prefs,
  ) {
    // Note: We embed the system prompt as part of the user message since
    // AiCopilotService.chat() already has its own system prompt. We override
    // by sending all context in the user message.
    return '''You are VibeRadar Smart Crate Generator — an expert DJ intelligence that organizes
music libraries into perfectly curated crates.

$summary

$manifest

RULES:
- You MUST ONLY use track IDs from the manifest above. Do NOT invent IDs.
- Group tracks into ${prefs.crateCount} crates.
- Each crate should have a creative DJ-friendly name and brief description.
- Consider BPM flow, key compatibility (Camelot wheel), energy progression, and genre cohesion.
- Aim for 10-30 tracks per crate (adjust based on library size).
${prefs.mood != null ? '- Target mood: ${prefs.mood}' : ''}
${prefs.energyLevel != null ? '- Target energy: ${prefs.energyLevel}' : ''}
${prefs.mixingStyle != null ? '- Mixing style: ${prefs.mixingStyle}' : ''}
${prefs.customPrompt != null && prefs.customPrompt!.isNotEmpty ? '- Custom instructions: ${prefs.customPrompt}' : ''}

MANDATORY OUTPUT FORMAT:
You MUST end your response with a ```crate JSON block in EXACTLY this format:
```crate
{"crates":[{"name":"Crate Name","description":"Brief description","trackIds":["id1","id2","id3"]}]}
```

The trackIds MUST be exact IDs from the manifest. No other IDs are valid.
''';
  }

  String _buildUserMessage(
    String summary,
    String manifest,
    SmartCratePreferences prefs,
  ) {
    final buf = StringBuffer();
    buf.write(
      'Analyze my library and create ${prefs.crateCount} smart DJ crates',
    );
    if (prefs.genres.isNotEmpty) {
      buf.write(' focusing on ${prefs.genres.join(", ")}');
    }
    if (prefs.mood != null) {
      buf.write(' with a ${prefs.mood} vibe');
    }
    buf.write('.');
    if (prefs.customPrompt != null && prefs.customPrompt!.isNotEmpty) {
      buf.write(' ${prefs.customPrompt}');
    }
    // Embed full context since chat() uses its own system prompt
    buf.write('\n\n');
    buf.write(_buildSystemPrompt(summary, manifest, prefs));
    return buf.toString();
  }

  // ── Response parser ────────────────────────────────────────────────────────

  List<GeneratedCrate> _parseResponse(
    String response,
    Map<String, LibraryTrack> trackMap,
  ) {
    // Look for ```crate JSON block
    final crateBlockRegex = RegExp(r'```crate\s*\n([\s\S]*?)\n```');
    final match = crateBlockRegex.firstMatch(response);

    String? jsonStr;
    if (match != null) {
      jsonStr = match.group(1)?.trim();
    } else {
      // Fallback: try to find raw JSON with "crates" key
      final jsonRegex = RegExp(r'\{[\s\S]*"crates"[\s\S]*\}');
      final fallback = jsonRegex.firstMatch(response);
      if (fallback != null) {
        jsonStr = fallback.group(0);
      }
    }

    if (jsonStr == null || jsonStr.isEmpty) {
      dev.log(
        'SmartCrateGenerator: no crate JSON found in response',
        name: 'SmartCrate',
      );
      return [];
    }

    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final crateList = data['crates'] as List<dynamic>? ?? [];
      final result = <GeneratedCrate>[];

      for (final c in crateList) {
        final cMap = c as Map<String, dynamic>;
        final name = cMap['name'] as String? ?? 'Unnamed Crate';
        final description = cMap['description'] as String? ?? '';
        final trackIds = (cMap['trackIds'] as List<dynamic>?)
                ?.map((id) => id.toString())
                .toList() ??
            [];

        // Resolve IDs to LibraryTrack objects
        final resolvedTracks = <LibraryTrack>[];
        for (final id in trackIds) {
          final track = trackMap[id];
          if (track != null) {
            resolvedTracks.add(track);
          } else {
            dev.log(
              'SmartCrateGenerator: track ID "$id" not found in manifest',
              name: 'SmartCrate',
            );
          }
        }

        if (resolvedTracks.isNotEmpty) {
          result.add(GeneratedCrate(
            name: name,
            description: description,
            tracks: resolvedTracks,
          ));
        }
      }

      dev.log(
        'SmartCrateGenerator: parsed ${result.length} crates with '
        '${result.fold<int>(0, (s, c) => s + c.tracks.length)} total tracks',
        name: 'SmartCrate',
      );

      return result;
    } catch (e) {
      dev.log(
        'SmartCrateGenerator: JSON parse error: $e',
        name: 'SmartCrate',
      );
      return [];
    }
  }
}

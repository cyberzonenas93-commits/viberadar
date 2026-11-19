import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/library_track.dart';
import '../models/track.dart';
import 'local_match_service.dart';

typedef SetFolderAiAssistBuilder =
    Future<String?> Function(SetFolderAiAssistContext context);

class SetFolderAiAssistContext {
  const SetFolderAiAssistContext({
    required this.crateName,
    required this.copied,
    required this.missing,
    required this.review,
  });

  final String crateName;
  final List<PreparedSetFolderCopy> copied;
  final List<PreparedSetFolderMissing> missing;
  final List<PreparedSetFolderReview> review;
}

class PreparedSetFolderCopy {
  const PreparedSetFolderCopy({
    required this.track,
    required this.sourcePath,
    required this.destinationPath,
    required this.matchStatus,
    required this.confidence,
    required this.matchMethod,
  });

  final Track track;
  final String sourcePath;
  final String destinationPath;
  final MatchStatus matchStatus;
  final double confidence;
  final String matchMethod;
}

class PreparedSetFolderReview {
  const PreparedSetFolderReview({
    required this.track,
    required this.reason,
    required this.candidates,
    required this.confidence,
    required this.matchMethod,
  });

  final Track track;
  final String reason;
  final List<String> candidates;
  final double confidence;
  final String matchMethod;
}

class PreparedSetFolderMissing {
  const PreparedSetFolderMissing({
    required this.track,
    required this.tidalSearchUrl,
    required this.platformUrls,
  });

  final Track track;
  final String tidalSearchUrl;
  final Map<String, String> platformUrls;
}

class PreparedSetFolderResult {
  const PreparedSetFolderResult({
    required this.folderPath,
    required this.playlistPath,
    required this.missingManifestPath,
    required this.matchReportPath,
    required this.copied,
    required this.missing,
    required this.review,
    required this.errors,
    this.aiNotes,
  });

  final String folderPath;
  final String playlistPath;
  final String missingManifestPath;
  final String matchReportPath;
  final List<PreparedSetFolderCopy> copied;
  final List<PreparedSetFolderMissing> missing;
  final List<PreparedSetFolderReview> review;
  final List<String> errors;
  final String? aiNotes;

  int get copiedCount => copied.length;
  int get missingCount => missing.length;
  int get reviewCount => review.length;
}

class SetFolderPreparationService {
  SetFolderPreparationService({LocalMatchService? matcher})
    : _matcher = matcher ?? LocalMatchService();

  final LocalMatchService _matcher;

  Future<PreparedSetFolderResult> prepare({
    required String crateName,
    required List<Track> tracks,
    required List<LibraryTrack> library,
    required String destinationParentDir,
    bool overwriteExisting = false,
    SetFolderAiAssistBuilder? aiAssist,
    void Function(int done, int total)? onProgress,
  }) async {
    final safeName = _safeName(crateName);
    final folder = Directory(p.join(destinationParentDir, safeName));
    await folder.create(recursive: true);

    final matches = await _matcher.matchSet(tracks, library);
    final copied = <PreparedSetFolderCopy>[];
    final missing = <PreparedSetFolderMissing>[];
    final review = <PreparedSetFolderReview>[];
    final errors = <String>[];
    final usedDestinations = <String>{};

    for (var i = 0; i < matches.length; i++) {
      onProgress?.call(i, matches.length);
      final match = matches[i];
      final sourcePath = match.localFilePath;

      if (_shouldCopy(match) && sourcePath != null) {
        final source = File(sourcePath);
        if (!source.existsSync()) {
          errors.add('Source not found: $sourcePath');
          missing.add(_missing(match.vibeTrack));
          continue;
        }

        final destinationPath = _uniqueDestinationPath(
          folder.path,
          p.basename(sourcePath),
          usedDestinations,
        );
        usedDestinations.add(destinationPath);
        final destination = File(destinationPath);

        if (destination.existsSync() && !overwriteExisting) {
          copied.add(
            PreparedSetFolderCopy(
              track: match.vibeTrack,
              sourcePath: sourcePath,
              destinationPath: destinationPath,
              matchStatus: match.status,
              confidence: match.matchScore,
              matchMethod: match.matchMethod,
            ),
          );
          continue;
        }

        try {
          await source.copy(destinationPath);
          copied.add(
            PreparedSetFolderCopy(
              track: match.vibeTrack,
              sourcePath: sourcePath,
              destinationPath: destinationPath,
              matchStatus: match.status,
              confidence: match.matchScore,
              matchMethod: match.matchMethod,
            ),
          );
        } catch (e) {
          errors.add('${_label(match.vibeTrack)}: $e');
        }
        continue;
      }

      if (match.isUncertain) {
        final candidates = <String>[
          ...match.candidates.where((path) => path != sourcePath),
        ];
        if (sourcePath != null) {
          candidates.insert(0, sourcePath);
        }
        review.add(
          PreparedSetFolderReview(
            track: match.vibeTrack,
            reason:
                'Possible local match found, but confidence is too low to '
                'copy automatically.',
            candidates: candidates,
            confidence: match.matchScore,
            matchMethod: match.matchMethod,
          ),
        );
      } else {
        missing.add(_missing(match.vibeTrack));
      }
    }

    onProgress?.call(matches.length, matches.length);

    final playlistPath = p.join(folder.path, '$safeName.m3u');
    final missingManifestPath = p.join(folder.path, 'MISSING_TRACKS.txt');
    final matchReportPath = p.join(folder.path, 'MATCH_REPORT.txt');
    final aiNotes = await _loadAiNotes(
      aiAssist,
      SetFolderAiAssistContext(
        crateName: crateName,
        copied: copied,
        missing: missing,
        review: review,
      ),
    );

    await File(playlistPath).writeAsString(_buildPlaylist(crateName, copied));
    await File(
      missingManifestPath,
    ).writeAsString(_buildMissingManifest(crateName, missing, review));
    await File(matchReportPath).writeAsString(
      _buildMatchReport(crateName, copied, missing, review, errors, aiNotes),
    );

    return PreparedSetFolderResult(
      folderPath: folder.path,
      playlistPath: playlistPath,
      missingManifestPath: missingManifestPath,
      matchReportPath: matchReportPath,
      copied: copied,
      missing: missing,
      review: review,
      errors: errors,
      aiNotes: aiNotes,
    );
  }

  Future<String?> _loadAiNotes(
    SetFolderAiAssistBuilder? aiAssist,
    SetFolderAiAssistContext context,
  ) async {
    if (aiAssist == null) return null;
    if (context.missing.isEmpty && context.review.isEmpty) return null;
    final String? notes;
    try {
      notes = await aiAssist(context);
    } catch (_) {
      return null;
    }
    final trimmed = notes?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  bool _shouldCopy(TrackMatch match) =>
      (match.isFound || match.isFuzzy) &&
      match.localFilePath != null &&
      match.matchScore >= 0.75;

  PreparedSetFolderMissing _missing(Track track) {
    final platformUrls = Map<String, String>.from(track.platformLinks);
    return PreparedSetFolderMissing(
      track: track,
      tidalSearchUrl: _tidalSearchUrl(track),
      platformUrls: platformUrls,
    );
  }

  String _buildPlaylist(String crateName, List<PreparedSetFolderCopy> copied) {
    final buf = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#PLAYLIST:$crateName')
      ..writeln('#EXTGRP:VibeRadar Prepared Set Folder');
    for (final item in copied) {
      buf
        ..writeln('#EXTINF:-1,${_label(item.track)}')
        ..writeln(item.destinationPath);
    }
    return buf.toString();
  }

  String _buildMissingManifest(
    String crateName,
    List<PreparedSetFolderMissing> missing,
    List<PreparedSetFolderReview> review,
  ) {
    final buf = StringBuffer()
      ..writeln('# Missing tracks for $crateName')
      ..writeln()
      ..writeln(
        'These tracks were not copied into the prepared set folder. Use the '
        'TIDAL search fallback or source them manually before importing into '
        'Serato or VirtualDJ.',
      )
      ..writeln();

    if (missing.isEmpty && review.isEmpty) {
      buf.writeln('No missing or review-needed tracks.');
      return buf.toString();
    }

    if (missing.isNotEmpty) {
      buf.writeln('Missing:');
      for (var i = 0; i < missing.length; i++) {
        final item = missing[i];
        buf
          ..writeln('${i + 1}. ${_label(item.track)}')
          ..writeln('   TIDAL search: ${item.tidalSearchUrl}');
        for (final entry in item.platformUrls.entries) {
          buf.writeln('   ${_platformLabel(entry.key)}: ${entry.value}');
        }
      }
      buf.writeln();
    }

    if (review.isNotEmpty) {
      buf.writeln('Needs review before copying:');
      for (var i = 0; i < review.length; i++) {
        final item = review[i];
        buf
          ..writeln('${i + 1}. ${_label(item.track)}')
          ..writeln(
            '   Reason: ${item.reason} '
            '(${_percent(item.confidence)} via ${item.matchMethod})',
          );
        for (final candidate in item.candidates) {
          buf.writeln('   Candidate: $candidate');
        }
      }
    }

    return buf.toString();
  }

  String _buildMatchReport(
    String crateName,
    List<PreparedSetFolderCopy> copied,
    List<PreparedSetFolderMissing> missing,
    List<PreparedSetFolderReview> review,
    List<String> errors,
    String? aiNotes,
  ) {
    final buf = StringBuffer()
      ..writeln('# VibeRadar Smart Match Report')
      ..writeln('# Set: $crateName')
      ..writeln()
      ..writeln('Copied: ${copied.length}')
      ..writeln('Missing: ${missing.length}')
      ..writeln('Needs review: ${review.length}')
      ..writeln('Errors: ${errors.length}')
      ..writeln()
      ..writeln(
        'VibeRadar copied exact, duplicate, and high-confidence fuzzy matches. '
        'Lower-confidence filename guesses are listed for review so the app '
        'does not silently prepare the wrong song.',
      )
      ..writeln();

    if (copied.isNotEmpty) {
      buf.writeln('Copied files:');
      for (final item in copied) {
        buf
          ..writeln('- ${_label(item.track)}')
          ..writeln('  Source: ${item.sourcePath}')
          ..writeln('  Copy: ${item.destinationPath}')
          ..writeln(
            '  Match: ${item.matchMethod} (${_percent(item.confidence)})',
          );
      }
      buf.writeln();
    }

    if (review.isNotEmpty) {
      buf.writeln('Review queue:');
      for (final item in review) {
        buf
          ..writeln('- ${_label(item.track)}')
          ..writeln(
            '  Match: ${item.matchMethod} (${_percent(item.confidence)})',
          );
        for (final candidate in item.candidates) {
          buf.writeln('  Candidate: $candidate');
        }
      }
      buf.writeln();
    }

    if (missing.isNotEmpty) {
      buf.writeln('Missing fallback list:');
      for (final item in missing) {
        buf
          ..writeln('- ${_label(item.track)}')
          ..writeln('  TIDAL search: ${item.tidalSearchUrl}');
      }
      buf.writeln();
    }

    if (aiNotes != null && aiNotes.trim().isNotEmpty) {
      buf
        ..writeln('AI assistance:')
        ..writeln(aiNotes.trim())
        ..writeln();
    }

    if (errors.isNotEmpty) {
      buf.writeln('Errors:');
      for (final error in errors) {
        buf.writeln('- $error');
      }
    }

    return buf.toString();
  }

  String _safeName(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[/:*?"<>|\\]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'VibeRadar Set' : cleaned;
  }

  String _uniqueDestinationPath(
    String folderPath,
    String fileName,
    Set<String> reserved,
  ) {
    final baseName = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var candidate = p.join(folderPath, fileName);
    var suffix = 2;
    while (reserved.contains(candidate) || File(candidate).existsSync()) {
      candidate = p.join(folderPath, '$baseName ($suffix)$extension');
      suffix++;
    }
    return candidate;
  }

  String _tidalSearchUrl(Track track) {
    final tidalLink = track.platformLinks['tidal'];
    if (tidalLink != null && tidalLink.trim().isNotEmpty) return tidalLink;
    return Uri.https('tidal.com', '/search', {'q': _label(track)}).toString();
  }

  String _label(Track track) => '${track.artist} - ${track.title}'.trim();

  String _platformLabel(String platform) => platform.isEmpty
      ? 'Platform'
      : '${platform[0].toUpperCase()}${platform.substring(1)}';

  String _percent(double value) => '${(value * 100).round()}%';
}

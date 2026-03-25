class LibraryTrack {
  const LibraryTrack({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.bpm,
    required this.key,
    required this.durationSeconds,
    required this.fileSizeBytes,
    required this.fileExtension,
    required this.md5Hash,
    required this.bitrate,
    required this.sampleRate,
    this.year,
  });

  final String id;
  final String filePath;
  final String fileName;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final double bpm;
  final String key;
  final double durationSeconds;
  final int fileSizeBytes;
  final String fileExtension;
  final String md5Hash;
  final int bitrate;
  final int sampleRate;
  final int? year;

  String get durationFormatted {
    final m = (durationSeconds / 60).floor();
    final s = (durationSeconds % 60).floor();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get fileSizeFormatted {
    if (fileSizeBytes < 1024 * 1024) return '${(fileSizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  LibraryTrack copyWith({String? md5Hash}) => LibraryTrack(
    id: id, filePath: filePath, fileName: fileName, title: title, artist: artist,
    album: album, genre: genre, bpm: bpm, key: key, durationSeconds: durationSeconds,
    fileSizeBytes: fileSizeBytes, fileExtension: fileExtension,
    md5Hash: md5Hash ?? this.md5Hash, bitrate: bitrate, sampleRate: sampleRate, year: year,
  );
}

class DuplicateGroup {
  const DuplicateGroup({required this.tracks, required this.reason});
  final List<LibraryTrack> tracks;
  final String reason;

  String get reasonLabel {
    switch (reason) {
      case 'exact_hash': return 'Exact duplicate';
      case 'same_title_artist': return 'Same title & artist';
      case 'similar_name': return 'Similar filename';
      default: return 'Possible duplicate';
    }
  }
}

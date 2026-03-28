enum VideoSourceType { local, youtube }

class VideoPlaybackItem {
  const VideoPlaybackItem({
    required this.trackId,
    required this.sourceType,
    this.localFilePath,
    this.youtubeVideoId,
    this.youtubeThumbnail,
    this.title,
    this.channelName,
    this.durationSeconds,
    this.isOfficialVideo = false,
    this.isLyricVideo = false,
    this.isLivePerformance = false,
  });

  final String trackId;
  final VideoSourceType sourceType;

  /// Absolute file path for local video files.
  final String? localFilePath;

  /// YouTube video ID (e.g. "dQw4w9WgXcQ").
  final String? youtubeVideoId;

  final String? youtubeThumbnail;
  final String? title;
  final String? channelName;
  final double? durationSeconds;

  /// True if the channel/uploader appears to be the official artist account.
  final bool isOfficialVideo;

  /// True if the title contains lyric-video keywords.
  final bool isLyricVideo;

  /// True if the title or channel suggests a live performance.
  final bool isLivePerformance;

  // ── Computed ────────────────────────────────────────────────────────────────

  bool get hasVideo => localFilePath != null || youtubeVideoId != null;

  String get youtubeWatchUrl =>
      'https://www.youtube.com/watch?v=$youtubeVideoId';

  // ── Factory constructors ────────────────────────────────────────────────────

  /// Create a local-file video item.
  factory VideoPlaybackItem.local({
    required String trackId,
    required String filePath,
    String? title,
    double? durationSeconds,
  }) {
    return VideoPlaybackItem(
      trackId: trackId,
      sourceType: VideoSourceType.local,
      localFilePath: filePath,
      title: title,
      durationSeconds: durationSeconds,
    );
  }

  /// Create a YouTube video item, auto-detecting video type from [rawTitle]
  /// and optionally checking [artistName] against [channelName] for official
  /// video detection.
  factory VideoPlaybackItem.youtube({
    required String trackId,
    required String videoId,
    String? rawTitle,
    String? channelName,
    String? thumbnailUrl,
    double? durationSeconds,
    String? artistName,
  }) {
    final title = rawTitle ?? '';
    final isLyric = _detectLyricVideo(title);
    final isLive = _detectLivePerformance(title);
    final isOfficial = _detectOfficialVideo(title, channelName, artistName);

    return VideoPlaybackItem(
      trackId: trackId,
      sourceType: VideoSourceType.youtube,
      youtubeVideoId: videoId,
      youtubeThumbnail: thumbnailUrl,
      title: rawTitle,
      channelName: channelName,
      durationSeconds: durationSeconds,
      isOfficialVideo: isOfficial,
      isLyricVideo: isLyric,
      isLivePerformance: isLive,
    );
  }

  // ── Keyword detection helpers ───────────────────────────────────────────────

  static bool _detectLyricVideo(String title) {
    final lower = title.toLowerCase();
    return lower.contains('lyric') ||
        lower.contains('lyrics') ||
        lower.contains('lyric video');
  }

  static bool _detectLivePerformance(String title) {
    final lower = title.toLowerCase();
    return lower.contains('live') ||
        lower.contains('live performance') ||
        lower.contains('concert') ||
        lower.contains('tour') ||
        lower.contains('acoustic') ||
        lower.contains('unplugged') ||
        lower.contains('session') ||
        lower.contains('live at') ||
        lower.contains('live from');
  }

  static bool _detectOfficialVideo(
    String title,
    String? channelName,
    String? artistName,
  ) {
    final lowerTitle = title.toLowerCase();
    final hasOfficialKeyword =
        lowerTitle.contains('official video') ||
        lowerTitle.contains('official music video') ||
        lowerTitle.contains('official audio') ||
        lowerTitle.contains('official mv');

    if (hasOfficialKeyword) return true;

    // If artist name is provided, check if it appears in channel name
    if (artistName != null && channelName != null) {
      final lowerArtist = artistName.toLowerCase();
      final lowerChannel = channelName.toLowerCase();
      if (lowerChannel.contains(lowerArtist) ||
          lowerArtist.contains(lowerChannel)) {
        return true;
      }
    }

    // VEVO channels are typically official
    if (channelName != null &&
        channelName.toUpperCase().contains('VEVO')) {
      return true;
    }

    return false;
  }

  // ── Serialization ───────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'trackId': trackId,
      'sourceType': sourceType.name,
      'localFilePath': localFilePath,
      'youtubeVideoId': youtubeVideoId,
      'youtubeThumbnail': youtubeThumbnail,
      'title': title,
      'channelName': channelName,
      'durationSeconds': durationSeconds,
      'isOfficialVideo': isOfficialVideo,
      'isLyricVideo': isLyricVideo,
      'isLivePerformance': isLivePerformance,
    };
  }

  factory VideoPlaybackItem.fromJson(Map<String, dynamic> json) {
    final sourceTypeStr = json['sourceType'] as String? ?? 'youtube';
    final sourceType = VideoSourceType.values.firstWhere(
      (s) => s.name == sourceTypeStr,
      orElse: () => VideoSourceType.youtube,
    );

    return VideoPlaybackItem(
      trackId: json['trackId'] as String? ?? '',
      sourceType: sourceType,
      localFilePath: json['localFilePath'] as String?,
      youtubeVideoId: json['youtubeVideoId'] as String?,
      youtubeThumbnail: json['youtubeThumbnail'] as String?,
      title: json['title'] as String?,
      channelName: json['channelName'] as String?,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble(),
      isOfficialVideo: json['isOfficialVideo'] as bool? ?? false,
      isLyricVideo: json['isLyricVideo'] as bool? ?? false,
      isLivePerformance: json['isLivePerformance'] as bool? ?? false,
    );
  }

  VideoPlaybackItem copyWith({
    String? trackId,
    VideoSourceType? sourceType,
    String? localFilePath,
    String? youtubeVideoId,
    String? youtubeThumbnail,
    String? title,
    String? channelName,
    double? durationSeconds,
    bool? isOfficialVideo,
    bool? isLyricVideo,
    bool? isLivePerformance,
  }) {
    return VideoPlaybackItem(
      trackId: trackId ?? this.trackId,
      sourceType: sourceType ?? this.sourceType,
      localFilePath: localFilePath ?? this.localFilePath,
      youtubeVideoId: youtubeVideoId ?? this.youtubeVideoId,
      youtubeThumbnail: youtubeThumbnail ?? this.youtubeThumbnail,
      title: title ?? this.title,
      channelName: channelName ?? this.channelName,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isOfficialVideo: isOfficialVideo ?? this.isOfficialVideo,
      isLyricVideo: isLyricVideo ?? this.isLyricVideo,
      isLivePerformance: isLivePerformance ?? this.isLivePerformance,
    );
  }
}

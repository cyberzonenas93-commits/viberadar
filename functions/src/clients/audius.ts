import type { SourceTrackSignal } from "../types";

const BASE_URL = "https://api.audius.co/v1";
const TRENDING_LIMIT = 18;

interface AudiusTrack {
  id: string;
  title?: string;
  genre?: string;
  mood?: string;
  tags?: string;
  release_date?: string;
  created_at?: string;
  bpm?: number;
  musical_key?: string;
  favorite_count?: number;
  repost_count?: number;
  comment_count?: number;
  play_count?: number;
  permalink?: string;
  artwork?: {
    "150x150"?: string;
    "480x480"?: string;
    "1000x1000"?: string;
  };
  user?: {
    name?: string;
    handle?: string;
  };
}

export async function fetchAudiusSignals(): Promise<SourceTrackSignal[]> {
  const [trendingResponse, undergroundResponse] = await Promise.all([
    fetch(`${BASE_URL}/tracks/trending?limit=${TRENDING_LIMIT}`),
    fetch(`${BASE_URL}/tracks/trending/underground?limit=${TRENDING_LIMIT}`),
  ]);

  if (!trendingResponse.ok) {
    throw new Error(`Audius trending API failed: ${trendingResponse.status}`);
  }
  if (!undergroundResponse.ok) {
    throw new Error(
      `Audius underground API failed: ${undergroundResponse.status}`,
    );
  }

  const [trendingPayload, undergroundPayload] = (await Promise.all([
    trendingResponse.json(),
    undergroundResponse.json(),
  ])) as [{ data?: AudiusTrack[] }, { data?: AudiusTrack[] }];

  return [
    ...mapTracks(trendingPayload.data ?? [], "audius trending"),
    ...mapTracks(undergroundPayload.data ?? [], "audius underground"),
  ];
}

function mapTracks(
  tracks: AudiusTrack[],
  sourceKeyword: string,
): SourceTrackSignal[] {
  return tracks.map((track) => {
    const favorites = track.favorite_count ?? 0;
    const reposts = track.repost_count ?? 0;
    const comments = track.comment_count ?? 0;
    const plays = track.play_count ?? 0;
    const releasedAt = track.release_date ?? track.created_at;

    return {
      source: "audius",
      sourceId: track.id,
      title: sanitizeTitle(track.title ?? "Untitled"),
      artist: track.user?.name ?? track.user?.handle ?? "Audius Artist",
      artworkUrl:
        track.artwork?.["1000x1000"] ??
        track.artwork?.["480x480"] ??
        track.artwork?.["150x150"],
      genre: track.genre ?? undefined,
      bpm: track.bpm ?? undefined,
      key: track.musical_key ?? undefined,
      platformUrl: buildTrackUrl(track.permalink, track.id),
      keywords: buildKeywords(track, sourceKeyword),
      engagement: cappedNormalize(
        plays + favorites * 14 + reposts * 18 + comments * 20,
        300_000,
      ),
      growthRate: cappedNormalize(
        favorites + reposts * 3 + comments * 4,
        20_000,
      ),
      recency: recencyScore(releasedAt),
      releasedAt,
    } satisfies SourceTrackSignal;
  });
}

function buildKeywords(track: AudiusTrack, sourceKeyword: string): string[] {
  const tags = (track.tags ?? "")
    .split(/[,\s]+/)
    .map((tag) => tag.trim())
    .filter(Boolean);

  return Array.from(
    new Set(
      [
        sourceKeyword,
        track.genre ?? "",
        track.mood ?? "",
        ...tags.slice(0, 8),
      ].filter(Boolean),
    ),
  );
}

function buildTrackUrl(permalink?: string, id?: string): string {
  if (permalink) {
    return `https://audius.co${permalink}`;
  }
  if (id) {
    return `https://audius.co/tracks/${id}`;
  }
  return "https://audius.co";
}

function sanitizeTitle(title: string): string {
  return title.replace(/\(snippet\)|\[snippet]/gi, "").trim();
}

function cappedNormalize(value: number, max: number): number {
  return Number(Math.min(value / max, 1).toFixed(4));
}

function recencyScore(date?: string): number {
  if (!date) {
    return 0.5;
  }

  const releasedAt = new Date(date);
  const ageInDays = Math.max(
    1,
    (Date.now() - releasedAt.getTime()) / (1000 * 60 * 60 * 24),
  );
  return Number(Math.max(0.1, 1 - ageInDays / 90).toFixed(4));
}

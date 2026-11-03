import type { SourceTrackSignal } from "../types";

export async function fetchYouTubeSignals(input: {
  apiKey?: string;
  region: string;
}): Promise<SourceTrackSignal[]> {
  const { apiKey, region } = input;
  if (!apiKey) {
    return [];
  }

  const response = await fetch(
    `https://www.googleapis.com/youtube/v3/videos?part=snippet,statistics&chart=mostPopular&videoCategoryId=10&maxResults=20&regionCode=${region}&key=${apiKey}`,
  );

  if (!response.ok) {
    throw new Error(`YouTube API failed: ${response.status}`);
  }

  const payload = (await response.json()) as {
    items?: Array<{
      id: string;
      snippet?: {
        title?: string;
        channelTitle?: string;
        publishedAt?: string;
        tags?: string[];
        categoryId?: string;
        thumbnails?: { high?: { url?: string } };
      };
      statistics?: {
        viewCount?: string;
        likeCount?: string;
        commentCount?: string;
      };
    }>;
  };

  const IRRELEVANT = [
    /\bbts\b/i, /\bjungkook\b/i, /\bblackpink\b/i, /\btwice\b/i,
    /\bstray\s*kids\b/i, /\bnewjeans\b/i, /\baespa\b/i,
    /\b(k-?pop|kpop|j-?pop|jpop|c-?pop|cpop|anime|bollywood)\b/i,
    /\b(country|folk|bluegrass|gospel|christian|classical|metal|punk)\b/i,
  ];

  return (payload.items ?? []).filter((item) => {
    const text = `${item.snippet?.title ?? ""} ${item.snippet?.channelTitle ?? ""} ${(item.snippet?.tags ?? []).join(" ")}`;
    return !IRRELEVANT.some((p) => p.test(text));
  }).map((item) => {
    const views = Number(item.statistics?.viewCount ?? 0);
    const likes = Number(item.statistics?.likeCount ?? 0);
    const comments = Number(item.statistics?.commentCount ?? 0);
    const artist = sanitizeChannelArtist(
      item.snippet?.channelTitle ?? "YouTube Music",
    );
    return {
      source: "youtube",
      sourceId: item.id,
      title: sanitizeVideoTitle(item.snippet?.title ?? "Untitled", artist),
      artist,
      artworkUrl: item.snippet?.thumbnails?.high?.url,
      region,
      platformUrl: `https://youtube.com/watch?v=${item.id}`,
      keywords: item.snippet?.tags?.slice(0, 8) ?? [],
      engagement: cappedNormalize(
        views + likes * 12 + comments * 18,
        8_000_000,
      ),
      growthRate: cappedNormalize(likes + comments * 4, 250_000),
      recency: recencyScore(item.snippet?.publishedAt),
      releasedAt: item.snippet?.publishedAt,
    } satisfies SourceTrackSignal;
  });
}

function sanitizeVideoTitle(title: string, artist: string): string {
  let sanitized = title
    .replace(/\(official.*?\)|\[official.*?]/gi, "")
    .replace(/\b(official\s+)?(music\s+)?video\b/gi, "")
    .replace(/\b(audio|lyric video|visualizer|performance video)\b/gi, "")
    .replace(/[“”]/g, '"')
    .replace(/[‘’]/g, "'")
    .trim();

  const artistPrefix = new RegExp(`^${escapeRegExp(artist)}\\s*[-:|]\\s*`, "i");
  sanitized = sanitized.replace(artistPrefix, "");

  return sanitized.replace(/\s{2,}/g, " ").trim();
}

function sanitizeChannelArtist(channelTitle: string): string {
  return channelTitle
    .replace(/\s*-\s*topic$/i, "")
    .replace(/\s*vevo$/i, "")
    .trim();
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function cappedNormalize(value: number, max: number): number {
  return Number(Math.min(value / max, 1).toFixed(4));
}

function recencyScore(date?: string): number {
  if (!date) {
    return 0.4;
  }
  const published = new Date(date);
  const ageInDays = Math.max(
    1,
    (Date.now() - published.getTime()) / (1000 * 60 * 60 * 24),
  );
  return Number(Math.max(0.1, 1 - ageInDays / 60).toFixed(4));
}

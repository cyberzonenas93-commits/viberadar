import type { SourceTrackSignal } from "../types";

export async function fetchBeatportSignals(input: {
  apiToken?: string;
  apiBaseUrl?: string;
  region: string;
}): Promise<SourceTrackSignal[]> {
  const { apiToken, apiBaseUrl, region } = input;
  if (!apiToken || !apiBaseUrl) {
    return [];
  }

  const url = new URL(apiBaseUrl);
  url.searchParams.set("region", region);

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${apiToken}`,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`Beatport API failed: ${response.status}`);
  }

  const payload = (await response.json()) as {
    tracks?: Array<{
      id: string | number;
      title?: string;
      artist?: string;
      genre?: string;
      bpm?: number;
      key?: string;
      url?: string;
      artwork_url?: string;
      chart_position?: number;
      engagement?: number;
      growth_rate?: number;
      released_at?: string;
    }>;
  };

  return (payload.tracks ?? []).map((track, index) => ({
    source: "beatport",
    sourceId: String(track.id),
    title: track.title ?? "Untitled",
    artist: track.artist ?? "Unknown",
    artworkUrl: track.artwork_url ?? undefined,
    genre: track.genre ?? undefined,
    bpm: track.bpm ?? undefined,
    key: track.key ?? undefined,
    keywords: [track.genre ?? "beatport", "dj"],
    region,
    platformUrl: track.url ?? "https://www.beatport.com",
    engagement:
      track.engagement !== undefined
        ? Number(track.engagement.toFixed(4))
        : Number(Math.max(0.12, 1 - index / 25).toFixed(4)),
    growthRate:
      track.growth_rate !== undefined
        ? Number(track.growth_rate.toFixed(4))
        : Number(Math.max(0.1, 1 - index / 20).toFixed(4)),
    recency: recencyScore(track.released_at),
    releasedAt: track.released_at,
  }));
}

function recencyScore(date?: string): number {
  if (!date) {
    return 0.55;
  }
  const releasedAt = new Date(date);
  const ageInDays = Math.max(
    1,
    (Date.now() - releasedAt.getTime()) / (1000 * 60 * 60 * 24)
  );
  return Number(Math.max(0.1, 1 - ageInDays / 240).toFixed(4));
}

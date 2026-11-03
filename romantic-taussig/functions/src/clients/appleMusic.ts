import { appleStorefrontForRegion } from "../lib/config";
import type { SourceTrackSignal } from "../types";

export async function fetchAppleMusicSignals(input: {
  developerToken?: string;
  region: string;
}): Promise<SourceTrackSignal[]> {
  const { developerToken, region } = input;
  if (!developerToken) {
    return [];
  }

  const storefront = appleStorefrontForRegion(region);
  const response = await fetch(
    `https://api.music.apple.com/v1/catalog/${storefront}/charts?types=songs&limit=20`,
    {
      headers: {
        Authorization: `Bearer ${developerToken}`,
      },
    }
  );

  if (!response.ok) {
    throw new Error(`Apple Music API failed: ${response.status}`);
  }

  const payload = (await response.json()) as {
    results?: {
      songs?: Array<{
        data?: Array<{
          id: string;
          attributes?: {
            name?: string;
            artistName?: string;
            genreNames?: string[];
            url?: string;
            releaseDate?: string;
            artwork?: {
              url?: string;
            };
          };
        }>;
      }>;
    };
  };

  const songs = payload.results?.songs?.[0]?.data ?? [];
  return songs.map((song, index) => ({
    source: "apple",
    sourceId: song.id,
    title: song.attributes?.name ?? "Untitled",
    artist: song.attributes?.artistName ?? "Unknown",
    artworkUrl: song.attributes?.artwork?.url
      ?.replace("{w}", "600")
      .replace("{h}", "600"),
    genre: song.attributes?.genreNames?.[0],
    region,
    platformUrl: song.attributes?.url ?? "https://music.apple.com",
    keywords: song.attributes?.genreNames ?? [],
    engagement: Number(Math.max(0.1, 1 - index / 20).toFixed(4)),
    growthRate: Number(Math.max(0.1, 1 - index / 16).toFixed(4)),
    recency: recencyScore(song.attributes?.releaseDate),
    releasedAt: song.attributes?.releaseDate,
  }));
}

function recencyScore(date?: string): number {
  if (!date) {
    return 0.5;
  }
  const releaseDate = new Date(date);
  const ageInDays = Math.max(1, (Date.now() - releaseDate.getTime()) / (1000 * 60 * 60 * 24));
  return Number(Math.max(0.1, 1 - ageInDays / 120).toFixed(4));
}

import type { SourceTrackSignal } from "../types";

const SEARCH_QUERIES = [
  "afrobeats new",
  "amapiano hits",
  "house music new",
  "tech house",
  "deep house",
  "afro house",
  "dancehall new",
  "reggaeton new",
  "latin club",
  "hip hop club",
  "drill new",
  "r&b new",
  "dance pop new",
  "edm new",
  "uk garage",
  "soca new",
  "afro swing",
  "gqom",
  "baile funk",
  "club bangers",
];

export async function fetchSpotifySignals(input: {
  clientId?: string;
  clientSecret?: string;
  region: string;
}): Promise<SourceTrackSignal[]> {
  const { clientId, clientSecret, region } = input;
  if (!clientId || !clientSecret) {
    return [];
  }

  const tokenResponse = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });

  if (!tokenResponse.ok) {
    throw new Error(`Spotify auth failed: ${tokenResponse.status}`);
  }

  const tokenPayload = (await tokenResponse.json()) as { access_token: string };
  const aggregate: SourceTrackSignal[] = [];

  await Promise.all(
    SEARCH_QUERIES.map(async (query) => {
      const response = await fetch(
        `https://api.spotify.com/v1/search?q=${encodeURIComponent(query)}&type=track&market=${region}&limit=50`,
        {
          headers: {
            Authorization: `Bearer ${tokenPayload.access_token}`,
          },
        }
      );

      if (!response.ok) {
        return;
      }

      const payload = (await response.json()) as {
        tracks?: {
          items?: Array<{
            id: string;
            name: string;
            popularity: number;
            external_urls?: { spotify?: string };
            album?: {
              images?: Array<{ url: string }>;
              release_date?: string;
            };
            artists?: Array<{ name: string }>;
          }>;
        };
      };

      for (const track of payload.tracks?.items ?? []) {
        aggregate.push({
          source: "spotify",
          sourceId: track.id,
          title: track.name,
          artist: track.artists?.map((artist) => artist.name).join(", ") || "Unknown",
          artworkUrl: track.album?.images?.[0]?.url,
          region,
          platformUrl: track.external_urls?.spotify ?? "https://open.spotify.com",
          keywords: [query],
          engagement: track.popularity / 100,
          growthRate: track.popularity / 100,
          recency: recencyScore(track.album?.release_date),
          releasedAt: track.album?.release_date,
        });
      }
    })
  );

  return aggregate;
}


function recencyScore(date?: string): number {
  if (!date) {
    return 0.5;
  }
  const releaseDate = new Date(date);
  const ageInDays = Math.max(1, (Date.now() - releaseDate.getTime()) / (1000 * 60 * 60 * 24));
  return Number(Math.max(0.1, 1 - ageInDays / 90).toFixed(4));
}

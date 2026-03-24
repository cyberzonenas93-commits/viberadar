import type { SourceTrackSignal } from "../types";

const SEARCH_QUERIES = [
  "viral hits",
  "afrobeats",
  "dancefloor",
  "amapiano",
  "latin reggaeton",
  "hip hop trending",
  "r&b new",
  "house music",
  "drill",
  "dancehall",
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
        `https://api.spotify.com/v1/search?q=${encodeURIComponent(query)}&type=track&market=${region}&limit=12`,
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

  // Enrich with audio features (BPM, key) in batches of 100
  const trackIds = aggregate.map((s) => s.sourceId);
  const featureMap = new Map<string, { bpm: number; key: string }>();

  for (let i = 0; i < trackIds.length; i += 100) {
    const batch = trackIds.slice(i, i + 100);
    const featResponse = await fetch(
      `https://api.spotify.com/v1/audio-features?ids=${batch.join(",")}`,
      {
        headers: {
          Authorization: `Bearer ${tokenPayload.access_token}`,
        },
      },
    );

    if (featResponse.ok) {
      const featPayload = (await featResponse.json()) as {
        audio_features?: Array<{
          id: string;
          tempo?: number;
          key?: number;
          mode?: number;
        } | null>;
      };

      for (const feat of featPayload.audio_features ?? []) {
        if (!feat) continue;
        featureMap.set(feat.id, {
          bpm: feat.tempo ? Math.round(feat.tempo) : 0,
          key: pitchToKey(feat.key, feat.mode),
        });
      }
    }
  }

  for (const signal of aggregate) {
    const features = featureMap.get(signal.sourceId);
    if (features) {
      signal.bpm = features.bpm || signal.bpm;
      signal.key = features.key || signal.key;
    }
  }

  return aggregate;
}

const PITCH_CLASSES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];

function pitchToKey(pitch?: number, mode?: number): string {
  if (pitch == null || pitch < 0 || pitch > 11) return "";
  const note = PITCH_CLASSES[pitch];
  const suffix = mode === 1 ? "" : "m";
  return `${note}${suffix}`;
}

function recencyScore(date?: string): number {
  if (!date) {
    return 0.5;
  }
  const releaseDate = new Date(date);
  const ageInDays = Math.max(1, (Date.now() - releaseDate.getTime()) / (1000 * 60 * 60 * 24));
  return Number(Math.max(0.1, 1 - ageInDays / 90).toFixed(4));
}

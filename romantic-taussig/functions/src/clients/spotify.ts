import type { SourceTrackSignal } from "../types";

/**
 * Spotify genre seeds that align with VibeRadar's DJ focus.
 * Used with the recommendations endpoint for genre-locked results.
 */
const GENRE_SEEDS = [
  "afrobeat",
  "house",
  "deep-house",
  "tech-house",
  "dancehall",
  "reggaeton",
  "hip-hop",
  "r-n-b",
  "dance",
  "electronic",
  "drum-and-bass",
  "garage",
  "latin",
  "samba",
  "funk",
];

/**
 * Focused search queries — each includes genre-locking terms to prevent
 * Spotify from drifting into K-pop, rock, or country territory.
 */
const SEARCH_QUERIES = [
  "afrobeats 2026",
  "amapiano new",
  "afro house",
  "tech house new",
  "deep house new",
  "dancehall 2026",
  "reggaeton new",
  "drill new",
  "uk garage new",
  "soca new",
  "gqom",
  "baile funk",
  "hip hop club mix",
  "r&b new release",
];

/**
 * Artists/terms that indicate non-DJ-relevant content.
 * Tracks matching these are dropped before returning signals.
 */
const IRRELEVANT_PATTERNS = [
  /\bbts\b/i,
  /\bjungkook\b/i,
  /\bblackpink\b/i,
  /\btwice\b/i,
  /\bstray\s*kids\b/i,
  /\bnewjeans\b/i,
  /\baespa\b/i,
  /\benhypen\b/i,
  /\btxt\b/i,
  /\bsevente+n\b/i,
  /\b(k-?pop|kpop)\b/i,
  /\btaylor\s*swift\b/i,
  /\bed\s*sheeran\b/i,
  /\bcoldplay\b/i,
  /\bimagine\s*dragons\b/i,
  /\bmaroon\s*5\b/i,
  /\bone\s*direction\b/i,
  /\bjustin\s*bieber\b/i,
  /\barirang\b/i,
  /\b(anime|j-?pop|jpop|c-?pop|cpop|bollywood)\b/i,
  /\b(country|folk|bluegrass|gospel|christian|classical|metal|punk|emo)\b/i,
];

// Note: Spotify editorial playlists (Top 50 Ghana, etc.) return 404 with
// Client Credentials auth. Regional relevance is handled in the normalize
// layer via genreRegionAffinity() instead.

function isRelevant(title: string, artist: string): boolean {
  const combined = `${title} ${artist}`;
  return !IRRELEVANT_PATTERNS.some((pattern) => pattern.test(combined));
}

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
  const token = tokenPayload.access_token;
  const aggregate: SourceTrackSignal[] = [];

  // 1. Search-based discovery (focused queries, limit 30 per query)
  await Promise.all(
    SEARCH_QUERIES.map(async (query) => {
      const response = await fetch(
        `https://api.spotify.com/v1/search?q=${encodeURIComponent(query)}&type=track&market=${region}&limit=30`,
        { headers: { Authorization: `Bearer ${token}` } },
      );

      if (!response.ok) return;

      const payload = (await response.json()) as {
        tracks?: {
          items?: SpotifyTrack[];
        };
      };

      for (const track of payload.tracks?.items ?? []) {
        if (!isRelevant(track.name, artistNames(track))) continue;
        aggregate.push(mapTrack(track, region, query));
      }
    }),
  );

  // 2. Recommendations from genre seeds (more focused than search)
  const seedBatches = chunkArray(GENRE_SEEDS, 5); // Spotify allows max 5 seeds
  await Promise.all(
    seedBatches.slice(0, 3).map(async (seeds) => {
      const response = await fetch(
        `https://api.spotify.com/v1/recommendations?seed_genres=${seeds.join(",")}&market=${region}&limit=30&min_popularity=40`,
        { headers: { Authorization: `Bearer ${token}` } },
      );

      if (!response.ok) return;

      const payload = (await response.json()) as {
        tracks?: SpotifyTrack[];
      };

      for (const track of payload.tracks ?? []) {
        if (!isRelevant(track.name, artistNames(track))) continue;
        aggregate.push(mapTrack(track, region, `reco:${seeds[0]}`));
      }
    }),
  );

  return aggregate;
}

interface SpotifyTrack {
  id: string;
  name: string;
  popularity: number;
  external_urls?: { spotify?: string };
  album?: {
    images?: Array<{ url: string }>;
    release_date?: string;
  };
  artists?: Array<{ name: string }>;
}

function artistNames(track: SpotifyTrack): string {
  return track.artists?.map((a) => a.name).join(", ") || "Unknown";
}

function mapTrack(
  track: SpotifyTrack,
  region: string,
  keyword: string,
): SourceTrackSignal {
  return {
    source: "spotify",
    sourceId: track.id,
    title: track.name,
    artist: artistNames(track),
    artworkUrl: track.album?.images?.[0]?.url,
    region,
    platformUrl:
      track.external_urls?.spotify ?? "https://open.spotify.com",
    keywords: [keyword],
    engagement: track.popularity / 100,
    growthRate: track.popularity / 100,
    recency: recencyScore(track.album?.release_date),
    releasedAt: track.album?.release_date,
  };
}

function recencyScore(date?: string): number {
  if (!date) return 0.5;
  const releaseDate = new Date(date);
  const ageInDays = Math.max(
    1,
    (Date.now() - releaseDate.getTime()) / (1000 * 60 * 60 * 24),
  );
  return Number(Math.max(0.1, 1 - ageInDays / 90).toFixed(4));
}

function chunkArray<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

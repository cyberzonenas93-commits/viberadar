import type { SourceTrackSignal } from "../types";

const BASE_URL = "https://api.deezer.com";

interface DeezerTrack {
  id: number;
  title?: string;
  title_short?: string;
  duration?: number;
  rank?: number;
  position?: number;
  release_date?: string;
  explicit_lyrics?: boolean;
  preview?: string;
  link?: string;
  artist?: {
    id: number;
    name?: string;
    picture_medium?: string;
  };
  album?: {
    id: number;
    title?: string;
    cover_big?: string;
    cover_medium?: string;
  };
}

interface DeezerChartResponse {
  tracks?: {
    data?: DeezerTrack[];
  };
}

interface DeezerSearchResponse {
  data?: DeezerTrack[];
  total?: number;
}

const GENRE_IDS: Record<string, number> = {
  rap: 116,
  rnb: 165,
  dance: 113,
  electro: 106,
  reggae: 144,
  pop: 132,
  afro: 2,
};

const SEARCH_QUERIES = [
  "afrobeats",
  "amapiano",
  "afro house",
  "dancehall",
  "hip hop",
  "r&b new",
  "house music",
  "drill",
  "uk garage",
  "soca",
];

const IRRELEVANT_PATTERNS = [
  /\bbts\b/i, /\bjungkook\b/i, /\bblackpink\b/i, /\btwice\b/i,
  /\bstray\s*kids\b/i, /\bnewjeans\b/i, /\baespa\b/i,
  /\b(k-?pop|kpop|j-?pop|jpop|c-?pop|cpop|anime|bollywood)\b/i,
  /\b(country|folk|bluegrass|gospel|christian|classical|metal|punk)\b/i,
];

function isRelevant(title: string, artist: string): boolean {
  const combined = `${title} ${artist}`;
  return !IRRELEVANT_PATTERNS.some((p) => p.test(combined));
}

/**
 * Fetch trending tracks from Deezer charts and genre-specific searches.
 * Deezer's API is completely free and requires no authentication.
 */
export async function fetchDeezerSignals(input: {
  region?: string;
}): Promise<SourceTrackSignal[]> {
  const region = input.region ?? "US";
  const signals: SourceTrackSignal[] = [];

  // 1. Global chart
  const chartSettled = await Promise.allSettled([
    fetchJson<DeezerChartResponse>(`${BASE_URL}/chart`),
  ]);

  for (const result of chartSettled) {
    if (result.status === "fulfilled") {
      const tracks = result.value.tracks?.data ?? [];
      signals.push(...mapTracks(tracks, "deezer chart", region));
    }
  }

  // 2. Genre-specific charts
  const genreKeys = ["rap", "rnb", "dance", "electro", "afro"];
  const genreSettled = await Promise.allSettled(
    genreKeys.map((genre) =>
      fetchJson<DeezerChartResponse>(
        `${BASE_URL}/chart/${GENRE_IDS[genre] ?? 0}`,
      ),
    ),
  );

  for (let i = 0; i < genreSettled.length; i++) {
    const result = genreSettled[i];
    if (result.status === "fulfilled") {
      const tracks = result.value.tracks?.data ?? [];
      signals.push(
        ...mapTracks(tracks, `deezer ${genreKeys[i]} chart`, region),
      );
    }
  }

  // 3. Country-specific editorial charts (actual regional popularity!)
  // Deezer editorial endpoint: GET /editorial/{id}/charts returns real
  // country charts. IDs found via /editorial endpoint.
  const COUNTRY_EDITORIAL_MAP: Record<string, number> = {
    "GH": 0,  // Ghana uses the main editorial endpoint with country context
    "NG": 0,
    "ZA": 0,
    "GB": 0,
    "US": 0,
    "DE": 0,
  };

  // Deezer editorial charts respond to the editorial/0/charts endpoint
  // but we can also search for country-specific trending content
  const countrySearches: Array<{ query: string; region: string }> = [
    { query: "ghana afrobeats", region: "GH" },
    { query: "ghana highlife", region: "GH" },
    { query: "ghana drill", region: "GH" },
    { query: "nigerian afrobeats", region: "NG" },
    { query: "naija music", region: "NG" },
    { query: "south africa amapiano", region: "ZA" },
    { query: "gqom south africa", region: "ZA" },
    { query: "uk drill", region: "GB" },
    { query: "uk garage", region: "GB" },
  ];

  const countrySettled = await Promise.allSettled(
    countrySearches.map((cs) =>
      fetchJson<DeezerSearchResponse>(
        `${BASE_URL}/search?q=${encodeURIComponent(cs.query)}&order=RANKING&limit=25`,
      ).then((data) => ({ data, region: cs.region, query: cs.query })),
    ),
  );

  for (const result of countrySettled) {
    if (result.status === "fulfilled") {
      const { data, region: r, query } = result.value;
      const tracks = data.data ?? [];
      signals.push(...mapTracks(tracks, `deezer ${query}`, r));
    }
  }

  // 4. Deezer editorial playlists for African music
  const EDITORIAL_PLAYLISTS = [
    { id: 1440614715, region: "GH", tag: "afro-hits" },      // Afro Hits
    { id: 3153080842, region: "NG", tag: "afrobeats-hits" },  // Afrobeats Hits
    { id: 2135000122, region: "NG", tag: "viral-afro" },      // Viral Afro
  ];

  const playlistSettled = await Promise.allSettled(
    EDITORIAL_PLAYLISTS.map(async (pl) => {
      const data = await fetchJson<{ data?: DeezerTrack[] }>(
        `${BASE_URL}/playlist/${pl.id}/tracks?limit=50`,
      );
      return { tracks: data.data ?? [], region: pl.region, tag: pl.tag };
    }),
  );

  for (const result of playlistSettled) {
    if (result.status === "fulfilled") {
      signals.push(
        ...mapTracks(result.value.tracks, `deezer:${result.value.tag}`, result.value.region),
      );
    }
  }

  // 5. Search-based discovery
  const searchQueries = SEARCH_QUERIES.slice(0, 3);
  const searchSettled = await Promise.allSettled(
    searchQueries.map((q) =>
      fetchJson<DeezerSearchResponse>(
        `${BASE_URL}/search?q=${encodeURIComponent(q)}&order=RANKING&limit=15`,
      ),
    ),
  );

  for (let i = 0; i < searchSettled.length; i++) {
    const result = searchSettled[i];
    if (result.status === "fulfilled") {
      const tracks = result.value.data ?? [];
      signals.push(...mapTracks(tracks, `deezer ${searchQueries[i]}`, region));
    }
  }

  return signals;
}

async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url, {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) {
    throw new Error(`Deezer API failed: ${response.status} for ${url}`);
  }
  return response.json() as Promise<T>;
}

function mapTracks(
  tracks: DeezerTrack[],
  sourceKeyword: string,
  region: string,
): SourceTrackSignal[] {
  return tracks.filter((t) => isRelevant(t.title_short ?? t.title ?? "", t.artist?.name ?? "")).map((track) => {
    const rank = track.rank ?? 0;
    const position = track.position ?? 50;

    return {
      source: "deezer" as const,
      sourceId: String(track.id),
      title: (track.title_short ?? track.title ?? "Untitled").trim(),
      artist: track.artist?.name ?? "Unknown Artist",
      artworkUrl: track.album?.cover_big ?? track.album?.cover_medium,
      genre: undefined,
      platformUrl: track.link ?? `https://www.deezer.com/track/${track.id}`,
      keywords: [sourceKeyword].filter(Boolean),
      region,
      engagement: cappedNormalize(rank, 1_000_000),
      growthRate: cappedNormalize(Math.max(0, 100 - position) * 10_000, 1_000_000),
      recency: recencyScore(track.release_date),
      releasedAt: track.release_date ?? undefined,
    } satisfies SourceTrackSignal;
  });
}

function cappedNormalize(value: number, max: number): number {
  return Number(Math.min(value / max, 1).toFixed(4));
}

function recencyScore(date?: string): number {
  if (!date) return 0.5;
  const releasedAt = new Date(date);
  const ageInDays = Math.max(
    1,
    (Date.now() - releasedAt.getTime()) / (1000 * 60 * 60 * 24),
  );
  return Number(Math.max(0.1, 1 - ageInDays / 90).toFixed(4));
}

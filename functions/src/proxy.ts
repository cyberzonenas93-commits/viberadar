/**
 * proxy.ts — Server-side proxy Cloud Functions for Spotify, Apple Music, and
 * YouTube. Clients call these callables instead of hitting the platform APIs
 * directly, so no API keys are ever shipped in the app bundle.
 *
 * All three functions require Firebase Auth (`request.auth`).
 *
 * To run unit tests (pure helpers only — no network):
 *   cd functions && npx ts-node --project tsconfig.json test/proxy.test.ts
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import {
  SOUNDCHARTS_API_KEY,
  SOUNDCHARTS_APP_ID,
  SPOTIFY_CLIENT_ID,
  SPOTIFY_CLIENT_SECRET,
  YOUTUBE_API_KEY,
  APPLE_MUSIC_DEVELOPER_TOKEN,
  APPLE_MUSIC_PRIVATE_KEY,
  APPLE_MUSIC_KEY_ID,
  APPLE_MUSIC_TEAM_ID,
  getConfiguredRegions,
  getSoundchartsCreds,
  getSoundchartsPlatforms,
  normalizeSecretValue,
} from "./lib/config";
import { getAppleMusicDeveloperToken } from "./lib/appleMusicToken";
import {
  cachedYoutubeGet,
  firestoreYoutubeCacheStore,
} from "./lib/youtubeCache";
import { appClientCallableOptions } from "./lib/appCheck";
import { requireFullCallableAccount } from "./lib/auth";
import { requireProUsageLimitsForUser } from "./lib/entitlements";
import { enforceUsageLimit } from "./lib/usage";
import {
  fetchSoundchartsSignals,
  makeHttpGet,
  SOUNDCHARTS_GLOBAL_REGION,
} from "./clients/soundcharts";
import {
  firestoreSoundchartsCacheStore,
  withSoundchartsCache,
} from "./lib/soundchartsCache";
import type { SourceTrackSignal } from "./types";

// ---------------------------------------------------------------------------
// Path allowlists — prevent open-relay abuse
// ---------------------------------------------------------------------------

const SPOTIFY_ALLOWED_PREFIXES = [
  "search",
  "artists",
  "tracks",
  "albums",
  "browse",
  "playlists",
];
const APPLE_ALLOWED_PREFIXES = ["catalog"];
const YOUTUBE_ALLOWED_PREFIXES = ["search", "videos"];

const ONBOARDING_ARTIST_NAMES = [
  "Drake",
  "Kendrick Lamar",
  "Bad Bunny",
  "The Weeknd",
  "Taylor Swift",
  "Asake",
  "Wizkid",
  "Burna Boy",
  "Davido",
  "Fireboy DML",
  "Rema",
  "Tems",
  "Ayra Starr",
  "Ckay",
  "Beyoncé",
  "SZA",
  "Doja Cat",
  "Cardi B",
  "Nicki Minaj",
  "Travis Scott",
  "Future",
  "Lil Baby",
  "Gunna",
  "J. Cole",
  "Nas",
  "Jay-Z",
  "Kanye West",
  "Tyler the Creator",
  "Frank Ocean",
  "Bryson Tiller",
  "H.E.R.",
  "Jhené Aiko",
  "Summer Walker",
  "Chris Brown",
  "Usher",
  "Brent Faiyaz",
  "PartyNextDoor",
  "Headie One",
  "Central Cee",
  "Dave",
  "Stormzy",
  "AJ Tracey",
  "Fivio Foreign",
  "Lil Durk",
  "Rod Wave",
  "Morgan Wallen",
  "Luke Combs",
  "Zach Bryan",
  "Peso Pluma",
  "Feid",
  "J Balvin",
  "Maluma",
  "Daddy Yankee",
  "Farruko",
  "Ozuna",
] as const;

const ONBOARDING_ARTIST_LOOKUP = new Map(
  ONBOARDING_ARTIST_NAMES.map((name) => [normalizeArtistName(name), name]),
);
const ONBOARDING_ARTIST_MAX_NAMES = 20;
const ONBOARDING_ARTIST_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

interface OnboardingArtistImagesRequest {
  names?: unknown;
}

interface OnboardingArtistImageResult {
  name: string;
  spotifyId: string;
  imageUrl: string;
}

interface CachedOnboardingArtistImage {
  value: OnboardingArtistImageResult | null;
  expiresAt: number;
}

interface SpotifyArtistSearchItem {
  id?: unknown;
  name?: unknown;
  images?: unknown;
}

const onboardingArtistImageCache = new Map<
  string,
  CachedOnboardingArtistImage
>();

// ---------------------------------------------------------------------------
// Pure helpers (exported for unit tests)
// ---------------------------------------------------------------------------

/**
 * Encode a plain-object of query params into a URL querystring.
 * Values are URI-encoded. Undefined/null values are omitted.
 */
export function encodeQuery(
  params: Record<string, string | number | boolean | undefined | null>,
): string {
  const parts: string[] = [];
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    parts.push(
      `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`,
    );
  }
  return parts.join("&");
}

/**
 * Build a full request URL from a base, a path, and an optional query object.
 * Throws HttpsError("invalid-argument") if the path does not start with one of
 * the allowed prefixes.
 *
 * The path is always stripped of leading slashes before appending so callers
 * cannot craft a path that escapes the base URL.
 */
export function buildUrl(
  base: string,
  path: string,
  query: Record<string, string | number | boolean | undefined | null>,
  allowedPrefixes: readonly string[],
): string {
  const cleanPath = path.replace(/^\/+/, "");

  const allowed = allowedPrefixes.some(
    (prefix) => cleanPath === prefix || cleanPath.startsWith(`${prefix}/`),
  );
  if (!allowed) {
    throw new HttpsError(
      "invalid-argument",
      `Path "${cleanPath}" is not allowed. Allowed prefixes: ${allowedPrefixes.join(", ")}`,
    );
  }

  const qs = encodeQuery(query);
  const separator = base.endsWith("/") ? "" : "/";
  return qs
    ? `${base}${separator}${cleanPath}?${qs}`
    : `${base}${separator}${cleanPath}`;
}

/**
 * Validate that a path starts with one of the given prefixes. Returns true if
 * allowed, false otherwise. Pure function used directly in unit tests.
 */
export function isAllowedPath(
  path: string,
  allowedPrefixes: readonly string[],
): boolean {
  const cleanPath = path.replace(/^\/+/, "");
  return allowedPrefixes.some(
    (prefix) => cleanPath === prefix || cleanPath.startsWith(`${prefix}/`),
  );
}

export function normalizeArtistName(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, " ");
}

export function resolveOnboardingArtistNames(value: unknown): string[] {
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "names must be an array");
  }
  if (value.length > ONBOARDING_ARTIST_MAX_NAMES) {
    throw new HttpsError(
      "invalid-argument",
      `names can include at most ${ONBOARDING_ARTIST_MAX_NAMES} artists`,
    );
  }

  const names: string[] = [];
  const seen = new Set<string>();
  for (const raw of value) {
    if (typeof raw !== "string") {
      throw new HttpsError("invalid-argument", "artist names must be strings");
    }
    const normalized = normalizeArtistName(raw);
    const allowedName = ONBOARDING_ARTIST_LOOKUP.get(normalized);
    if (!allowedName) {
      throw new HttpsError(
        "invalid-argument",
        `artist "${raw}" is not available for onboarding preview`,
      );
    }
    if (!seen.has(normalized)) {
      seen.add(normalized);
      names.push(allowedName);
    }
  }
  return names;
}

function spotifyImages(value: unknown): Array<{ url?: unknown }> {
  return Array.isArray(value) ? (value as Array<{ url?: unknown }>) : [];
}

export function pickBestOnboardingArtistImage(
  targetName: string,
  items: SpotifyArtistSearchItem[],
): OnboardingArtistImageResult | null {
  const normalizedTarget = normalizeArtistName(targetName);
  const candidates = [...items].sort((a, b) => {
    const aExact =
      typeof a.name === "string" &&
      normalizeArtistName(a.name) === normalizedTarget;
    const bExact =
      typeof b.name === "string" &&
      normalizeArtistName(b.name) === normalizedTarget;
    if (aExact === bExact) return 0;
    return aExact ? -1 : 1;
  });

  for (const item of candidates) {
    if (typeof item.id !== "string" || typeof item.name !== "string") continue;
    const image = spotifyImages(item.images).find(
      (candidate) => typeof candidate.url === "string" && candidate.url.trim(),
    );
    if (!image || typeof image.url !== "string") continue;
    return {
      name: targetName,
      spotifyId: item.id,
      imageUrl: image.url,
    };
  }
  return null;
}

// ---------------------------------------------------------------------------
// Spotify — client-credentials token flow (mirrors clients/spotify.ts)
// ---------------------------------------------------------------------------

async function getSpotifyAccessToken(
  clientId: string,
  clientSecret: string,
): Promise<string> {
  const tokenResponse = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });

  if (!tokenResponse.ok) {
    throw new HttpsError(
      "internal",
      `Spotify auth failed: ${tokenResponse.status}`,
    );
  }

  const payload = (await tokenResponse.json()) as { access_token: string };
  return payload.access_token;
}

// ---------------------------------------------------------------------------
// Request / response types
// ---------------------------------------------------------------------------

interface ProxyRequest {
  path: string;
  query?: Record<string, string | number | boolean>;
}

interface SoundchartsProxyRequest {
  query?: unknown;
  region?: unknown;
  regions?: unknown;
  platforms?: unknown;
  limit?: unknown;
}

interface SoundchartsProxyTrack {
  title: string;
  artist: string;
  artworkUrl?: string;
  soundchartsUrl: string;
  source: string;
  region?: string;
  genre?: string;
  popularity: number;
  trendScore: number;
  sources: string[];
  regions: string[];
}

interface ResolvedSoundchartsProxyInput {
  query: string;
  regions: string[];
  platforms: string[];
  limit: number;
}

const SOUNDCHARTS_MAX_LIMIT = 100;
const SOUNDCHARTS_MAX_REGIONS = 6;
const SOUNDCHARTS_SEARCH_STOPWORDS = new Set([
  "all",
  "best",
  "bpm",
  "classic",
  "classics",
  "club",
  "crate",
  "dj",
  "essential",
  "greatest",
  "hit",
  "hits",
  "hot",
  "mix",
  "mixes",
  "music",
  "new",
  "party",
  "playlist",
  "popular",
  "release",
  "releases",
  "rising",
  "set",
  "song",
  "songs",
  "top",
  "track",
  "tracks",
  "trend",
  "trending",
]);

async function enforcePlatformProxyLimit(uid: string): Promise<void> {
  const { limits } = await requireProUsageLimitsForUser(
    uid,
    "VibeRadar Pro is required to search live music platforms.",
  );
  await enforceUsageLimit({
    uid,
    key: "platform_proxy_calls",
    limit: limits.platformProxyMonthlyLimit,
    window: "monthly",
  });
}

function clampSoundchartsLimit(value: unknown): number {
  if (value === undefined || value === null) return 50;
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1) {
    throw new HttpsError(
      "invalid-argument",
      "limit must be a positive integer",
    );
  }
  return Math.min(n, SOUNDCHARTS_MAX_LIMIT);
}

function normalizeRegionCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const region = value.trim().toUpperCase();
  if (!region) return null;
  if (region === "ALL" || region === SOUNDCHARTS_GLOBAL_REGION) {
    return SOUNDCHARTS_GLOBAL_REGION;
  }
  if (!/^[A-Z]{2,3}$/.test(region)) {
    throw new HttpsError("invalid-argument", `Invalid region "${value}"`);
  }
  return region;
}

function normalizeStringArray(value: unknown, label: string): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${label} must be an array`);
  }
  return value
    .map((item) => {
      if (typeof item !== "string") {
        throw new HttpsError(
          "invalid-argument",
          `${label} must contain strings`,
        );
      }
      return item.trim();
    })
    .filter(Boolean);
}

export function resolveSoundchartsProxyInput(
  data: SoundchartsProxyRequest | undefined,
  defaults: { regions: string[]; platforms: string[] },
): ResolvedSoundchartsProxyInput {
  const query = typeof data?.query === "string" ? data.query.trim() : "";
  const explicitRegions = normalizeStringArray(data?.regions, "regions")
    .map((region) => normalizeRegionCode(region))
    .filter((region): region is string => Boolean(region));
  const singleRegion = normalizeRegionCode(data?.region);
  const regions = (
    explicitRegions.length > 0
      ? explicitRegions
      : singleRegion
        ? [singleRegion]
        : [SOUNDCHARTS_GLOBAL_REGION]
  ).slice(0, SOUNDCHARTS_MAX_REGIONS);

  const configuredPlatforms = new Set(
    defaults.platforms.map((p) => p.toLowerCase()),
  );
  const requestedPlatforms = normalizeStringArray(data?.platforms, "platforms")
    .map((platform) => platform.toLowerCase())
    .filter((platform) => configuredPlatforms.has(platform));
  const platforms =
    requestedPlatforms.length > 0 ? requestedPlatforms : defaults.platforms;

  if (regions.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "No Soundcharts regions configured",
    );
  }
  if (platforms.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "No Soundcharts platforms configured",
    );
  }

  return {
    query,
    regions,
    platforms,
    limit: clampSoundchartsLimit(data?.limit),
  };
}

export function normalizeSoundchartsSearchTokens(value: string): string[] {
  const seen = new Set<string>();
  return value
    .toLowerCase()
    .split(/[^a-z0-9&]+/)
    .map((token) => token.trim())
    .filter((token) => {
      if (token.length < 2) return false;
      if (/^\d+$/.test(token)) return false;
      if (SOUNDCHARTS_SEARCH_STOPWORDS.has(token)) return false;
      if (seen.has(token)) return false;
      seen.add(token);
      return true;
    });
}

export function signalMatchesSoundchartsQuery(
  signal: SourceTrackSignal,
  query: string,
): boolean {
  const tokens = normalizeSoundchartsSearchTokens(query);
  if (tokens.length === 0) return true;

  const text = [
    signal.title,
    signal.artist,
    signal.genre ?? "",
    signal.region ?? "",
    signal.source,
    ...signal.keywords,
  ]
    .join(" ")
    .toLowerCase();
  const hits = tokens.filter((token) => text.includes(token)).length;
  const requiredHits = tokens.length === 1 ? 1 : Math.min(2, tokens.length);
  return hits >= requiredHits;
}

/**
 * Chart position must dominate. An equal-weight average let a brand-new #53
 * entry (recency 1.0, growth 0.9) outscore the long-charting #2 hit (recency
 * floor 0.1), so the returned list inverted the actual chart order. Movement
 * and freshness stay as tie-breakers, not drivers.
 */
function soundchartsWeightedScore(signal: SourceTrackSignal): number {
  return (
    signal.engagement * 0.7 + signal.growthRate * 0.15 + signal.recency * 0.15
  );
}

function soundchartsPopularity(signal: SourceTrackSignal): number {
  return Math.round(soundchartsWeightedScore(signal) * 100);
}

function soundchartsTrendScore(signal: SourceTrackSignal): number {
  return Number(soundchartsWeightedScore(signal).toFixed(4));
}

function soundchartsProxyKey(signal: SourceTrackSignal): string {
  return `${normalizeArtistName(signal.title)}::${normalizeArtistName(signal.artist)}`;
}

export function mergeSoundchartsProxyTracks(
  signals: SourceTrackSignal[],
): SoundchartsProxyTrack[] {
  const merged = new Map<string, SoundchartsProxyTrack>();

  for (const signal of signals) {
    const popularity = soundchartsPopularity(signal);
    const trendScore = soundchartsTrendScore(signal);
    const key = soundchartsProxyKey(signal);
    const existing = merged.get(key);
    if (!existing) {
      merged.set(key, {
        title: signal.title,
        artist: signal.artist,
        artworkUrl: signal.artworkUrl,
        soundchartsUrl: signal.platformUrl,
        source: signal.source,
        region: signal.region,
        genre: signal.genre,
        popularity,
        trendScore,
        sources: [signal.source],
        regions: signal.region ? [signal.region] : [],
      });
      continue;
    }

    const sources = new Set([...existing.sources, signal.source]);
    const regions = new Set([
      ...existing.regions,
      ...(signal.region ? [signal.region] : []),
    ]);
    if (popularity >= existing.popularity) {
      existing.soundchartsUrl = signal.platformUrl;
      existing.source = signal.source;
      existing.region = signal.region ?? existing.region;
      existing.artworkUrl = existing.artworkUrl ?? signal.artworkUrl;
      existing.genre = existing.genre ?? signal.genre;
      existing.popularity = popularity;
      existing.trendScore = trendScore;
    }
    existing.sources = Array.from(sources).sort();
    existing.regions = Array.from(regions).sort();
  }

  return Array.from(merged.values()).sort(
    (a, b) => b.popularity - a.popularity,
  );
}

// ---------------------------------------------------------------------------
// spotifyProxy
// ---------------------------------------------------------------------------

export const spotifyProxy = onCall(
  {
    region: "us-central1",
    secrets: [SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET],
    ...appClientCallableOptions,
  },
  async (request: CallableRequest<ProxyRequest>): Promise<unknown> => {
    const auth = requireFullCallableAccount(
      request.auth,
      "A full account is required to use platform search.",
    );

    const { path, query = {} } = request.data ?? {};
    if (!path || typeof path !== "string") {
      throw new HttpsError("invalid-argument", "path is required");
    }

    await enforcePlatformProxyLimit(auth.uid);

    const clientId = normalizeSecretValue(SPOTIFY_CLIENT_ID.value());
    const clientSecret = normalizeSecretValue(SPOTIFY_CLIENT_SECRET.value());
    if (!clientId || !clientSecret) {
      throw new HttpsError(
        "internal",
        "Spotify credentials are not configured",
      );
    }

    const token = await getSpotifyAccessToken(clientId, clientSecret);

    // buildUrl validates path against the allowlist
    const url = buildUrl(
      "https://api.spotify.com/v1",
      path,
      query,
      SPOTIFY_ALLOWED_PREFIXES,
    );

    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    });

    if (!response.ok) {
      throw new HttpsError("internal", `Spotify API error: ${response.status}`);
    }

    return response.json();
  },
);

// ---------------------------------------------------------------------------
// spotifyOnboardingArtistImages
// ---------------------------------------------------------------------------

async function fetchOnboardingArtistImage(
  name: string,
  token: string,
): Promise<OnboardingArtistImageResult | null> {
  const cacheKey = normalizeArtistName(name);
  const cached = onboardingArtistImageCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return cached.value;

  const url = buildUrl(
    "https://api.spotify.com/v1",
    "search",
    { q: name, type: "artist", limit: 5 },
    SPOTIFY_ALLOWED_PREFIXES,
  );
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    throw new HttpsError("internal", `Spotify API error: ${response.status}`);
  }

  const data = (await response.json()) as {
    artists?: { items?: SpotifyArtistSearchItem[] };
  };
  const value = pickBestOnboardingArtistImage(name, data.artists?.items ?? []);
  onboardingArtistImageCache.set(cacheKey, {
    value,
    expiresAt: Date.now() + ONBOARDING_ARTIST_CACHE_TTL_MS,
  });
  return value;
}

export const spotifyOnboardingArtistImages = onCall(
  {
    region: "us-central1",
    secrets: [SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET],
    ...appClientCallableOptions,
  },
  async (
    request: CallableRequest<OnboardingArtistImagesRequest>,
  ): Promise<{ artists: OnboardingArtistImageResult[] }> => {
    const names = resolveOnboardingArtistNames(request.data?.names);
    if (names.length === 0) return { artists: [] };

    const clientId = normalizeSecretValue(SPOTIFY_CLIENT_ID.value());
    const clientSecret = normalizeSecretValue(SPOTIFY_CLIENT_SECRET.value());
    if (!clientId || !clientSecret) {
      throw new HttpsError(
        "internal",
        "Spotify credentials are not configured",
      );
    }

    const token = await getSpotifyAccessToken(clientId, clientSecret);
    const results = await Promise.all(
      names.map(async (name) => {
        try {
          return await fetchOnboardingArtistImage(name, token);
        } catch (error) {
          logger.warn("Failed to fetch onboarding artist image", {
            artist: name,
            error,
          });
          return null;
        }
      }),
    );

    return {
      artists: results.filter(
        (artist): artist is OnboardingArtistImageResult => artist !== null,
      ),
    };
  },
);

// ---------------------------------------------------------------------------
// appleProxy
// ---------------------------------------------------------------------------

export const appleProxy = onCall(
  {
    region: "us-central1",
    secrets: [
      APPLE_MUSIC_DEVELOPER_TOKEN,
      APPLE_MUSIC_PRIVATE_KEY,
      APPLE_MUSIC_KEY_ID,
      APPLE_MUSIC_TEAM_ID,
    ],
    ...appClientCallableOptions,
  },
  async (request: CallableRequest<ProxyRequest>): Promise<unknown> => {
    const auth = requireFullCallableAccount(
      request.auth,
      "A full account is required to use platform search.",
    );

    const { path, query = {} } = request.data ?? {};
    if (!path || typeof path !== "string") {
      throw new HttpsError("invalid-argument", "path is required");
    }

    await enforcePlatformProxyLimit(auth.uid);

    const developerToken = getAppleMusicDeveloperToken();
    if (!developerToken) {
      throw new HttpsError(
        "internal",
        "Apple Music developer token is not configured",
      );
    }

    const url = buildUrl(
      "https://api.music.apple.com/v1",
      path,
      query,
      APPLE_ALLOWED_PREFIXES,
    );

    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${developerToken}` },
    });

    if (!response.ok) {
      throw new HttpsError(
        "internal",
        `Apple Music API error: ${response.status}`,
      );
    }

    return response.json();
  },
);

// ---------------------------------------------------------------------------
// youtubeProxy
// ---------------------------------------------------------------------------

export const youtubeProxy = onCall(
  {
    region: "us-central1",
    secrets: [YOUTUBE_API_KEY],
    ...appClientCallableOptions,
  },
  async (request: CallableRequest<ProxyRequest>): Promise<unknown> => {
    const auth = requireFullCallableAccount(
      request.auth,
      "A full account is required to use platform search.",
    );

    const { path, query = {} } = request.data ?? {};
    if (!path || typeof path !== "string") {
      throw new HttpsError("invalid-argument", "path is required");
    }

    await enforcePlatformProxyLimit(auth.uid);

    const apiKey = normalizeSecretValue(YOUTUBE_API_KEY.value());
    if (!apiKey) {
      throw new HttpsError("internal", "YouTube API key is not configured");
    }

    // Inject the server-side key; client-supplied key is ignored
    const url = buildUrl(
      "https://www.googleapis.com/youtube/v3",
      path,
      { ...query, key: apiKey },
      YOUTUBE_ALLOWED_PREFIXES,
    );

    // Cache identical YouTube queries (search.list = 100 quota units) across
    // all users; serve a stale entry if a live call is rate-limited (429).
    return cachedYoutubeGet({
      path,
      query: query as Record<string, unknown>,
      store: firestoreYoutubeCacheStore(),
      fetcher: async () => {
        const response = await fetch(url);
        if (!response.ok) {
          throw new HttpsError(
            "internal",
            `YouTube API error: ${response.status}`,
          );
        }
        return response.json();
      },
    });
  },
);

// ---------------------------------------------------------------------------
// soundchartsProxy
// ---------------------------------------------------------------------------

export const soundchartsProxy = onCall(
  {
    region: "us-central1",
    secrets: [SOUNDCHARTS_APP_ID, SOUNDCHARTS_API_KEY],
    timeoutSeconds: 120,
    memory: "512MiB",
    ...appClientCallableOptions,
  },
  async (
    request: CallableRequest<SoundchartsProxyRequest>,
  ): Promise<{ tracks: SoundchartsProxyTrack[] }> => {
    const auth = requireFullCallableAccount(
      request.auth,
      "A full account is required to use Soundcharts search.",
    );

    await enforcePlatformProxyLimit(auth.uid);

    const creds = getSoundchartsCreds();
    if (!creds) {
      throw new HttpsError(
        "internal",
        "Soundcharts credentials are not configured",
      );
    }

    const input = resolveSoundchartsProxyInput(request.data, {
      regions: getConfiguredRegions(),
      platforms: getSoundchartsPlatforms(),
    });

    const httpGet = withSoundchartsCache(
      makeHttpGet(creds.appId, creds.apiKey),
      firestoreSoundchartsCacheStore(),
    );

    const signals: SourceTrackSignal[] = [];
    const perRegion: Record<string, number> = {};
    for (const region of input.regions) {
      const regionSignals = await fetchSoundchartsSignals({
        region,
        platforms: input.platforms,
        appId: creds.appId,
        apiKey: creds.apiKey,
        httpGet,
      });
      perRegion[region] = regionSignals.length;
      signals.push(...regionSignals);
    }

    const filtered = signals.filter((signal) =>
      signalMatchesSoundchartsQuery(signal, input.query),
    );
    const tracks = mergeSoundchartsProxyTracks(filtered).slice(0, input.limit);

    logger.info("soundchartsProxy complete", {
      uid: auth.uid,
      query: input.query,
      regions: input.regions,
      platforms: input.platforms,
      fetchedSignals: signals.length,
      returnedTracks: tracks.length,
      perRegion,
    });

    return { tracks };
  },
);

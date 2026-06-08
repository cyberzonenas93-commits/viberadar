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
import {
  SPOTIFY_CLIENT_ID,
  SPOTIFY_CLIENT_SECRET,
  YOUTUBE_API_KEY,
  APPLE_MUSIC_DEVELOPER_TOKEN,
  normalizeSecretValue,
} from "./lib/config";
import { getUsageLimitsForUser } from "./lib/entitlements";
import { enforceUsageLimit } from "./lib/usage";

// ---------------------------------------------------------------------------
// Path allowlists — prevent open-relay abuse
// ---------------------------------------------------------------------------

const SPOTIFY_ALLOWED_PREFIXES = ["search", "artists", "tracks", "albums", "browse", "playlists"];
const APPLE_ALLOWED_PREFIXES = ["catalog"];
const YOUTUBE_ALLOWED_PREFIXES = ["search", "videos"];

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
    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
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

async function enforcePlatformProxyLimit(uid: string): Promise<void> {
  const { limits } = await getUsageLimitsForUser(uid);
  await enforceUsageLimit({
    uid,
    key: "platform_proxy_calls",
    limit: limits.platformProxyMonthlyLimit,
    window: "monthly",
  });
}

// ---------------------------------------------------------------------------
// spotifyProxy
// ---------------------------------------------------------------------------

export const spotifyProxy = onCall(
  {
    region: "us-central1",
    secrets: [SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET],
  },
  async (request: CallableRequest<ProxyRequest>): Promise<unknown> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const { path, query = {} } = request.data ?? {};
    if (!path || typeof path !== "string") {
      throw new HttpsError("invalid-argument", "path is required");
    }

    await enforcePlatformProxyLimit(request.auth.uid);

    const clientId = normalizeSecretValue(SPOTIFY_CLIENT_ID.value());
    const clientSecret = normalizeSecretValue(SPOTIFY_CLIENT_SECRET.value());
    if (!clientId || !clientSecret) {
      throw new HttpsError("internal", "Spotify credentials are not configured");
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
      throw new HttpsError(
        "internal",
        `Spotify API error: ${response.status}`,
      );
    }

    return response.json();
  },
);

// ---------------------------------------------------------------------------
// appleProxy
// ---------------------------------------------------------------------------

export const appleProxy = onCall(
  {
    region: "us-central1",
    secrets: [APPLE_MUSIC_DEVELOPER_TOKEN],
  },
  async (request: CallableRequest<ProxyRequest>): Promise<unknown> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const { path, query = {} } = request.data ?? {};
    if (!path || typeof path !== "string") {
      throw new HttpsError("invalid-argument", "path is required");
    }

    await enforcePlatformProxyLimit(request.auth.uid);

    const developerToken = normalizeSecretValue(
      APPLE_MUSIC_DEVELOPER_TOKEN.value(),
    );
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
  },
  async (request: CallableRequest<ProxyRequest>): Promise<unknown> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const { path, query = {} } = request.data ?? {};
    if (!path || typeof path !== "string") {
      throw new HttpsError("invalid-argument", "path is required");
    }

    await enforcePlatformProxyLimit(request.auth.uid);

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

    const response = await fetch(url);

    if (!response.ok) {
      throw new HttpsError(
        "internal",
        `YouTube API error: ${response.status}`,
      );
    }

    return response.json();
  },
);

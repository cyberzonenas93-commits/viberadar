import * as crypto from "crypto";
import type { SourceTrackSignal } from "../types";

const BASE_URL = "https://api.audiomack.com/v1";

interface AudiomackTrack {
  id: string;
  title?: string;
  artist?: string;
  genre?: string;
  image?: string;
  url_slug?: string;
  uploaded?: string;
  released?: string;
  featuring?: string;
  producer?: string;
  type?: string;
  uploader?: {
    name?: string;
    url_slug?: string;
    image?: string;
    verified?: string;
  };
}

/**
 * Build an OAuth 1.0a signed URL for 2-legged (consumer-only) requests.
 */
function buildOAuthUrl(
  method: string,
  url: string,
  consumerKey: string,
  consumerSecret: string,
  extraParams: Record<string, string> = {},
): string {
  const oauthParams: Record<string, string> = {
    oauth_consumer_key: consumerKey,
    oauth_nonce: crypto.randomBytes(16).toString("hex"),
    oauth_signature_method: "HMAC-SHA1",
    oauth_timestamp: Math.floor(Date.now() / 1000).toString(),
    oauth_version: "1.0",
  };

  // Merge all params for signing
  const allParams = { ...oauthParams, ...extraParams };
  const sortedKeys = Object.keys(allParams).sort();
  const paramString = sortedKeys
    .map((k) => `${encodeRFC3986(k)}=${encodeRFC3986(allParams[k])}`)
    .join("&");

  // Build signature base string
  const baseString = [
    method.toUpperCase(),
    encodeRFC3986(url),
    encodeRFC3986(paramString),
  ].join("&");

  // Sign with consumer secret + empty token secret
  const signingKey = `${encodeRFC3986(consumerSecret)}&`;
  const signature = crypto
    .createHmac("sha1", signingKey)
    .update(baseString)
    .digest("base64");

  oauthParams["oauth_signature"] = signature;

  // Build Authorization header value
  const authHeader =
    "OAuth " +
    Object.keys(oauthParams)
      .sort()
      .map((k) => `${encodeRFC3986(k)}="${encodeRFC3986(oauthParams[k])}"`)
      .join(", ");

  // Build final URL with extra params as query string
  const queryString = Object.entries(extraParams)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join("&");
  const finalUrl = queryString ? `${url}?${queryString}` : url;

  return JSON.stringify({ url: finalUrl, auth: authHeader });
}

function encodeRFC3986(str: string): string {
  return encodeURIComponent(str).replace(
    /[!'()*]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

async function fetchSigned(
  method: string,
  endpoint: string,
  consumerKey: string,
  consumerSecret: string,
  params: Record<string, string> = {},
): Promise<unknown> {
  const url = `${BASE_URL}${endpoint}`;
  const oauthParams: Record<string, string> = {
    oauth_consumer_key: consumerKey,
    oauth_nonce: crypto.randomBytes(16).toString("hex"),
    oauth_signature_method: "HMAC-SHA1",
    oauth_timestamp: Math.floor(Date.now() / 1000).toString(),
    oauth_version: "1.0",
  };

  const allParams = { ...oauthParams, ...params };
  const sortedKeys = Object.keys(allParams).sort();
  const paramString = sortedKeys
    .map((k) => `${encodeRFC3986(k)}=${encodeRFC3986(allParams[k])}`)
    .join("&");

  const baseString = [
    method.toUpperCase(),
    encodeRFC3986(url),
    encodeRFC3986(paramString),
  ].join("&");

  const signingKey = `${encodeRFC3986(consumerSecret)}&`;
  const signature = crypto
    .createHmac("sha1", signingKey)
    .update(baseString)
    .digest("base64");

  oauthParams["oauth_signature"] = signature;

  const authHeader =
    "OAuth " +
    Object.keys(oauthParams)
      .sort()
      .map((k) => `${encodeRFC3986(k)}="${encodeRFC3986(oauthParams[k])}"`)
      .join(", ");

  const queryString = Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join("&");
  const finalUrl = queryString ? `${url}?${queryString}` : url;

  const response = await fetch(finalUrl, {
    method,
    headers: {
      Authorization: authHeader,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`Audiomack API ${endpoint} failed: ${response.status}`);
  }

  return response.json();
}

export async function fetchAudiomackSignals(input: {
  consumerKey?: string;
  consumerSecret?: string;
}): Promise<SourceTrackSignal[]> {
  const { consumerKey, consumerSecret } = input;
  if (!consumerKey || !consumerSecret) {
    return [];
  }

  const endpoints = [
    { path: "/music/trending", keyword: "audiomack trending", params: { limit: "20" } },
    { path: "/chart/songs/weekly", keyword: "audiomack weekly chart", params: { limit: "20" } },
    { path: "/music/rap/trending", keyword: "audiomack hip-hop trending", params: { limit: "20" } },
  ];

  const settled = await Promise.allSettled(
    endpoints.map((ep) =>
      fetchSigned("GET", ep.path, consumerKey, consumerSecret, ep.params),
    ),
  );

  const signals: SourceTrackSignal[] = [];
  for (let i = 0; i < settled.length; i++) {
    const result = settled[i];
    if (result.status !== "fulfilled") continue;
    const payload = result.value as { results?: AudiomackTrack[] };
    const tracks = payload.results ?? [];
    signals.push(...mapTracks(tracks, endpoints[i].keyword));
  }

  return signals;
}

function mapTracks(
  tracks: AudiomackTrack[],
  sourceKeyword: string,
): SourceTrackSignal[] {
  return tracks
    .filter((t) => t.type === "song" || !t.type)
    .map((track) => {
      const artistName =
        track.uploader?.name ?? track.artist ?? "Unknown Artist";
      const artworkUrl = track.image ?? track.uploader?.image;
      const releasedAt = track.released
        ? new Date(Number(track.released) * 1000).toISOString()
        : track.uploaded
          ? new Date(Number(track.uploaded) * 1000).toISOString()
          : undefined;

      const slug = track.uploader?.url_slug ?? "";
      const trackSlug = track.url_slug ?? "";
      const platformUrl =
        slug && trackSlug
          ? `https://audiomack.com/${slug}/song/${trackSlug}`
          : `https://audiomack.com`;

      return {
        source: "audiomack" as const,
        sourceId: track.id,
        title: (track.title ?? "Untitled").replace(/\s+/g, " ").trim(),
        artist: artistName,
        artworkUrl,
        genre: track.genre || undefined,
        platformUrl,
        keywords: [
          sourceKeyword,
          track.genre ?? "",
          track.featuring ? `feat ${track.featuring}` : "",
        ].filter(Boolean),
        engagement: 0.5,
        growthRate: 0.5,
        recency: recencyScore(releasedAt),
        releasedAt,
      } satisfies SourceTrackSignal;
    });
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

import { createHash } from "node:crypto";
import * as admin from "firebase-admin";

/**
 * Firestore-backed response cache for the YouTube Data API.
 *
 * `search.list` costs 100 quota units; the default project quota is ~10,000
 * units/day (≈100 searches). Live catalog/Set Builder/search flows fan out many
 * identical YouTube searches, so without caching the project hits HTTP 429 fast.
 * Caching at the proxy means every user shares one cached payload per query for
 * the TTL, and a stale entry is served if a live call is rate-limited.
 *
 * Server-only collection — clients never read it (the proxy uses the admin SDK,
 * which bypasses security rules).
 */
const CACHE_COLLECTION = "youtube_cache";
export const YOUTUBE_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

export interface YoutubeCacheEntry {
  payload: string;
  fetchedAt: number;
}

export interface YoutubeCacheStore {
  read(key: string): Promise<YoutubeCacheEntry | null>;
  write(key: string, entry: YoutubeCacheEntry): Promise<void>;
}

/**
 * Deterministic cache key from path + query. The injected `key` (API key) is
 * excluded so the key is stable across key rotation and never embeds a secret,
 * and query order does not matter.
 */
export function youtubeCacheKey(
  path: string,
  query: Record<string, unknown>,
): string {
  const canonical = Object.keys(query)
    .filter((k) => k !== "key")
    .sort()
    .map((k) => `${k}=${String(query[k])}`)
    .join("&");
  return createHash("sha1").update(`${path}?${canonical}`).digest("hex");
}

export function firestoreYoutubeCacheStore(
  firestore?: admin.firestore.Firestore,
): YoutubeCacheStore {
  const collection = (firestore ?? admin.firestore()).collection(
    CACHE_COLLECTION,
  );
  return {
    async read(key) {
      const snap = await collection.doc(key).get();
      if (!snap.exists) return null;
      const data = snap.data() ?? {};
      if (
        typeof data.payload !== "string" ||
        typeof data.fetchedAt !== "number"
      ) {
        return null;
      }
      return { payload: data.payload, fetchedAt: data.fetchedAt };
    },
    async write(key, entry) {
      await collection.doc(key).set(entry);
    },
  };
}

/**
 * Serve a YouTube response from cache when fresh; otherwise fetch live, cache
 * it, and (crucially) fall back to a stale cached entry when the live call
 * fails — e.g. a 429 — so quota exhaustion degrades gracefully.
 */
export async function cachedYoutubeGet(opts: {
  path: string;
  query: Record<string, unknown>;
  store: YoutubeCacheStore;
  fetcher: () => Promise<unknown>;
  ttlMs?: number;
  now?: () => number;
}): Promise<unknown> {
  const now = opts.now ?? Date.now;
  const ttl = opts.ttlMs ?? YOUTUBE_CACHE_TTL_MS;
  const key = youtubeCacheKey(opts.path, opts.query);

  let stale: YoutubeCacheEntry | null = null;
  try {
    const hit = await opts.store.read(key);
    if (hit) {
      if (now() - hit.fetchedAt < ttl) {
        return JSON.parse(hit.payload);
      }
      stale = hit;
    }
  } catch {
    // Cache read failures fall through to a live fetch.
  }

  try {
    const fresh = await opts.fetcher();
    try {
      await opts.store.write(key, {
        payload: JSON.stringify(fresh),
        fetchedAt: now(),
      });
    } catch {
      // Best-effort write; the response is still served.
    }
    return fresh;
  } catch (error) {
    if (stale) {
      return JSON.parse(stale.payload);
    }
    throw error;
  }
}

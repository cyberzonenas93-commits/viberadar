import { createHash } from "node:crypto";
import * as admin from "firebase-admin";

import type { SoundchartsHttp } from "../clients/soundcharts";

/**
 * Firestore-backed response cache for Soundcharts GETs.
 *
 * The free Soundcharts tier is ~1,000 calls total, and chart lists/rankings
 * change slowly (rankings refresh roughly daily). Caching at the HTTP layer
 * means the proxy, Set Builder searches, and the daily ingest all share the
 * same cached payloads instead of each burning quota for identical data.
 */
const CHART_LIST_TTL_MS = 24 * 60 * 60 * 1000;
const RANKING_TTL_MS = 6 * 60 * 60 * 1000;
const CACHE_COLLECTION = "soundcharts_cache";

export interface SoundchartsCacheEntry {
  path: string;
  payload: string;
  fetchedAt: number;
}

export interface SoundchartsCacheStore {
  read(key: string): Promise<SoundchartsCacheEntry | null>;
  write(key: string, entry: SoundchartsCacheEntry): Promise<void>;
}

export function ttlForPath(path: string): number {
  return path.includes("/ranking/") ? RANKING_TTL_MS : CHART_LIST_TTL_MS;
}

export function cacheKeyForPath(path: string): string {
  return createHash("sha1").update(path).digest("hex");
}

export function firestoreSoundchartsCacheStore(
  firestore?: admin.firestore.Firestore,
): SoundchartsCacheStore {
  const collection = (firestore ?? admin.firestore()).collection(
    CACHE_COLLECTION,
  );
  return {
    async read(key) {
      const snap = await collection.doc(key).get();
      if (!snap.exists) return null;
      const data = snap.data() ?? {};
      if (typeof data.payload !== "string" || typeof data.fetchedAt !== "number") {
        return null;
      }
      return {
        path: typeof data.path === "string" ? data.path : "",
        payload: data.payload,
        fetchedAt: data.fetchedAt,
      };
    },
    async write(key, entry) {
      await collection.doc(key).set(entry);
    },
  };
}

export function withSoundchartsCache(
  inner: SoundchartsHttp,
  store: SoundchartsCacheStore,
  now: () => number = Date.now,
): SoundchartsHttp {
  return async (path) => {
    const key = cacheKeyForPath(path);
    try {
      const hit = await store.read(key);
      if (hit && now() - hit.fetchedAt < ttlForPath(path)) {
        return JSON.parse(hit.payload) as Awaited<ReturnType<SoundchartsHttp>>;
      }
    } catch {
      // Cache read failures fall through to a live fetch.
    }
    const fresh = await inner(path);
    try {
      await store.write(key, {
        path,
        payload: JSON.stringify(fresh),
        fetchedAt: now(),
      });
    } catch {
      // Best-effort write; the response is still served.
    }
    return fresh;
  };
}

import assert from "node:assert/strict";

import {
  cachedYoutubeGet,
  youtubeCacheKey,
  type YoutubeCacheEntry,
  type YoutubeCacheStore,
} from "../src/lib/youtubeCache";

function memoryStore(): YoutubeCacheStore & {
  entries: Map<string, YoutubeCacheEntry>;
} {
  const entries = new Map<string, YoutubeCacheEntry>();
  return {
    entries,
    async read(key) {
      return entries.get(key) ?? null;
    },
    async write(key, entry) {
      entries.set(key, entry);
    },
  };
}

async function run() {
  // 1) Key is deterministic, ignores the injected API key, order-independent.
  const k1 = youtubeCacheKey("search", { q: "amapiano", part: "snippet", key: "SECRET" });
  const k2 = youtubeCacheKey("search", { part: "snippet", q: "amapiano" });
  assert.equal(k1, k2, "key must ignore api key and query order");
  const k3 = youtubeCacheKey("search", { q: "house" });
  assert.notEqual(k1, k3, "different queries must differ");

  // 2) Miss → fetcher runs once and the result is cached.
  const store = memoryStore();
  let calls = 0;
  const fetcher = async () => {
    calls += 1;
    return { items: [{ id: calls }] };
  };
  const first = await cachedYoutubeGet({
    path: "search",
    query: { q: "amapiano" },
    store,
    fetcher,
    now: () => 1000,
  });
  assert.deepEqual(first, { items: [{ id: 1 }] });
  assert.equal(calls, 1);

  // 3) Fresh hit → served from cache, fetcher NOT called again.
  const second = await cachedYoutubeGet({
    path: "search",
    query: { q: "amapiano" },
    store,
    fetcher,
    now: () => 1000 + 60_000,
  });
  assert.deepEqual(second, { items: [{ id: 1 }] });
  assert.equal(calls, 1, "fresh hit must not call YouTube");

  // 4) Expired hit → refetch.
  const third = await cachedYoutubeGet({
    path: "search",
    query: { q: "amapiano" },
    store,
    fetcher,
    ttlMs: 1000,
    now: () => 1000 + 5000,
  });
  assert.deepEqual(third, { items: [{ id: 2 }] });
  assert.equal(calls, 2);

  // 5) Quota/error with a stale entry present → serve stale (graceful 429 handling).
  const failing = async () => {
    throw new Error("YouTube API error: 429");
  };
  const stale = await cachedYoutubeGet({
    path: "search",
    query: { q: "amapiano" },
    store,
    fetcher: failing,
    ttlMs: 1, // force expiry so the fetcher runs
    now: () => 9_999_999,
  });
  assert.deepEqual(stale, { items: [{ id: 2 }] }, "must fall back to stale on 429");

  // 6) Error with no cache present → rethrow.
  let threw = false;
  try {
    await cachedYoutubeGet({
      path: "search",
      query: { q: "never-seen" },
      store,
      fetcher: failing,
      now: () => 1,
    });
  } catch {
    threw = true;
  }
  assert.equal(threw, true, "no cache + error must rethrow");

  console.log("youtubeCache.test passed");
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});

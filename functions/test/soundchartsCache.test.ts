import assert from "node:assert/strict";
import {
  cacheKeyForPath,
  ttlForPath,
  withSoundchartsCache,
  type SoundchartsCacheEntry,
  type SoundchartsCacheStore,
} from "../src/lib/soundchartsCache";

function memoryStore(): SoundchartsCacheStore & {
  entries: Map<string, SoundchartsCacheEntry>;
} {
  const entries = new Map<string, SoundchartsCacheEntry>();
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

void (async () => {
  // ── TTLs: rankings refresh faster than chart lists ──────────────────────────
  assert.ok(
    ttlForPath("/api/v2.14/chart/song/x/ranking/latest?limit=100") <
      ttlForPath("/api/v2/chart/song/by-platform/shazam?countryCode="),
    "ranking TTL shorter than chart-list TTL",
  );
  assert.notEqual(
    cacheKeyForPath("/a"),
    cacheKeyForPath("/b"),
    "distinct paths → distinct keys",
  );

  // ── miss → fetch + store; hit → no second fetch ─────────────────────────────
  const store = memoryStore();
  let fetches = 0;
  let clock = 1_000_000;
  const cached = withSoundchartsCache(
    async (path) => {
      fetches += 1;
      return { items: [{ slug: `chart-for-${path.length}` }] };
    },
    store,
    () => clock,
  );

  const path = "/api/v2/chart/song/by-platform/shazam?countryCode=&limit=100";
  const first = await cached(path);
  assert.equal(fetches, 1, "miss fetches upstream");
  assert.equal(store.entries.size, 1, "response stored");

  const second = await cached(path);
  assert.equal(fetches, 1, "hit serves from cache");
  assert.deepEqual(second, first, "cached payload round-trips");

  // ── expiry: stale entries refetch ───────────────────────────────────────────
  clock += 25 * 60 * 60 * 1000; // beyond the 24h chart-list TTL
  await cached(path);
  assert.equal(fetches, 2, "stale entry refetches");

  // ── store failures degrade to live fetches, never errors ────────────────────
  const brokenStore: SoundchartsCacheStore = {
    async read() {
      throw new Error("firestore down");
    },
    async write() {
      throw new Error("firestore down");
    },
  };
  let liveFetches = 0;
  const degraded = withSoundchartsCache(
    async () => {
      liveFetches += 1;
      return { items: [] };
    },
    brokenStore,
    () => clock,
  );
  await degraded(path);
  assert.equal(liveFetches, 1, "broken cache still serves live data");

  console.log("soundcharts cache: assertions passed");
})();

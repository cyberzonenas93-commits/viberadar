# Soundcharts Ingestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Soundcharts ingestion client covering shazam/tiktok/boomplay (new) + soundcloud/beatport (replacing the dead direct clients), wired so a future paid key activates it with zero code change.

**Architecture:** One new `clients/soundcharts.ts` with pure, unit-tested mappers + an injectable HTTP seam; a creds gate that no-ops in production until real secrets are set; wired into `runIngestion` replacing the soundcloud/beatport fetches.

**Tech Stack:** TypeScript, Firebase Functions v2, ts-node + `node:assert` tests (same as `recency.test.ts`).

**Note:** Inline execution, no commits (same as prior tasks). After each task: `cd functions && npx tsc --noEmit`. The parallel entitlements workstream also edits `index.ts`/`config.ts` — work with their current content (shown below), don't revert it.

---

## File structure
- **New:** `functions/src/clients/soundcharts.ts` (client + pure mappers), `functions/test/soundcharts.test.ts`.
- **Modify:** `functions/src/lib/config.ts` (secrets + platforms + helpers), `functions/src/types.ts` (source union), `functions/src/index.ts` (wire in, drop soundcloud/beatport fetches), `functions/package.json` (test script).

Real Soundcharts ranking item shape (from sandbox `global-28`), used by the mapper:
```jsonc
{ "song": { "uuid","name","creditName","imageUrl" },
  "position": 1, "positionEvolution": 1, "metric": 5016487,
  "entryState": "", "entryDate": "2026-05-29T12:00:00+00:00",
  "oldPosition": 2, "timeOnChart": 10, "timeOnChartUnit": "DOC" }
// envelope: { related: { chart: { slug, platform, countryCode, maxResultsCount, metric } }, items: [...] }
```

---

## Task 1: Config — secrets, platforms, creds gate

**Files:** Modify `functions/src/lib/config.ts`; Test `functions/test/soundcharts.test.ts` (new, starts here).

- [ ] **Step 1: Write the failing test**

```ts
// functions/test/soundcharts.test.ts
import assert from "node:assert/strict";
import { getSoundchartsCreds, getSoundchartsPlatforms } from "../src/lib/config";

// getSoundchartsCreds returns null unless BOTH app id + api key are real.
process.env.SOUNDCHARTS_APP_ID = "";
process.env.SOUNDCHARTS_API_KEY = "";
assert.equal(getSoundchartsCreds(), null, "no creds → null");

process.env.SOUNDCHARTS_APP_ID = "myapp";
process.env.SOUNDCHARTS_API_KEY = "PLACEHOLDER";
assert.equal(getSoundchartsCreds(), null, "placeholder key → null");

process.env.SOUNDCHARTS_APP_ID = "myapp";
process.env.SOUNDCHARTS_API_KEY = "realkey";
assert.deepEqual(getSoundchartsCreds(), { appId: "myapp", apiKey: "realkey" }, "both real → creds");

// platforms default + override
delete process.env.SOUNDCHARTS_PLATFORMS;
assert.deepEqual(
  getSoundchartsPlatforms(),
  ["shazam", "tiktok", "boomplay", "soundcloud", "beatport"],
  "default platforms",
);
process.env.SOUNDCHARTS_PLATFORMS = "shazam, tiktok";
assert.deepEqual(getSoundchartsPlatforms(), ["shazam", "tiktok"], "override platforms");

console.log("soundcharts config: assertions passed");
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd functions && npx ts-node --project tsconfig.json test/soundcharts.test.ts`
Expected: FAIL — `getSoundchartsCreds`/`getSoundchartsPlatforms` not exported.

- [ ] **Step 3: Implement** — append to `functions/src/lib/config.ts`

Add to the top-of-file declarations (after the existing `defineSecret` lines, before `normalizeSecretValue`):
```ts
export const SOUNDCHARTS_APP_ID = defineSecret("SOUNDCHARTS_APP_ID");
export const SOUNDCHARTS_API_KEY = defineSecret("SOUNDCHARTS_API_KEY");
export const SOUNDCHARTS_PLATFORMS = defineString("SOUNDCHARTS_PLATFORMS", {
  default: "shazam,tiktok,boomplay,soundcloud,beatport",
});
export const SOUNDCHARTS_BASE_URL = "https://customer.api.soundcharts.com";
```
Append at the end of the file:
```ts
/** Real Soundcharts credentials, or null when unset/placeholder (no-op signal).
 *  Reads process.env first so unit tests can set values without the params SDK. */
export function getSoundchartsCreds(): { appId: string; apiKey: string } | null {
  const appId = normalizeSecretValue(
    process.env.SOUNDCHARTS_APP_ID ?? SOUNDCHARTS_APP_ID.value(),
  );
  const apiKey = normalizeSecretValue(
    process.env.SOUNDCHARTS_API_KEY ?? SOUNDCHARTS_API_KEY.value(),
  );
  if (!appId || !apiKey) return null;
  return { appId, apiKey };
}

export function getSoundchartsPlatforms(): string[] {
  const raw = process.env.SOUNDCHARTS_PLATFORMS ?? SOUNDCHARTS_PLATFORMS.value();
  return raw
    .split(",")
    .map((p) => p.trim().toLowerCase())
    .filter(Boolean);
}
```
NOTE: `SOUNDCHARTS_APP_ID.value()` throws outside a function runtime if the env var is unset; the `process.env.X ?? ...` short-circuits in tests (env set) and in production the params SDK provides `.value()`. To be safe in unit tests, the `process.env` branch is evaluated first.

- [ ] **Step 4: Run to verify it passes**

Run: `cd functions && npx ts-node --project tsconfig.json test/soundcharts.test.ts`
Expected: "soundcharts config: assertions passed".

---

## Task 2: Source union

**Files:** Modify `functions/src/types.ts`.

- [ ] **Step 1: Add the three new sources** — in `SourceTrackSignal`, change the `source` union:

```ts
  source:
    | "spotify"
    | "youtube"
    | "apple"
    | "soundcloud"
    | "beatport"
    | "audius"
    | "audiomack"
    | "deezer"
    | "billboard"
    | "shazam"
    | "tiktok"
    | "boomplay";
```

- [ ] **Step 2: Verify typecheck**

Run: `cd functions && npx tsc --noEmit`
Expected: exit 0 (no other code asserts the old union exhaustively).

---

## Task 3: Pure mappers — `selectCharts`, scoring, `mapRanking`

**Files:** Create `functions/src/clients/soundcharts.ts`; Test `functions/test/soundcharts.test.ts` (append).

- [ ] **Step 1: Append failing tests**

```ts
import {
  selectCharts,
  engagementFromEntry,
  growthFromMovement,
  recencyFromEntry,
  mapRanking,
} from "../src/clients/soundcharts";

// selectCharts: prefer country match, cap at max, allow global fallback
const charts = [
  { slug: "global-top", name: "Top Songs", countryCode: "" },
  { slug: "ng-top", name: "Top 100 Nigeria", countryCode: "NG" },
  { slug: "ng-disc", name: "Discovery Nigeria", countryCode: "NG" },
  { slug: "us-top", name: "Top 100 USA", countryCode: "US" },
];
const picked = selectCharts(charts, "NG", 2);
assert.equal(picked.length, 2, "caps at max");
assert.ok(picked.every((c) => c.countryCode === "NG"), "only NG charts when available");
assert.deepEqual(selectCharts(charts, "FR", 2).map((c) => c.slug), ["global-top"], "global fallback when no country match");

// engagementFromEntry: top of chart → high, bottom → low, clamped
assert.equal(engagementFromEntry(1, 100), 1, "position 1 → 1.0");
assert.equal(engagementFromEntry(100, 100), 0.01, "last → ~0.01");
assert.equal(engagementFromEntry(50, 0), 0.5, "bad chartSize falls back to 100");

// growthFromMovement: new entry high, climbing > falling, clamped 0.05..1
assert.equal(growthFromMovement(0, true), 0.9, "new entry → 0.9");
assert.ok(growthFromMovement(10, false) > growthFromMovement(-10, false), "climb beats fall");
assert.equal(growthFromMovement(-1000, false), 0.05, "big fall clamps to floor");

// recencyFromEntry: recent entry high, old low, missing → 0.5
const NOW = Date.UTC(2026, 5, 8);
assert.equal(recencyFromEntry(undefined, NOW), 0.5, "missing → 0.5");
assert.ok(recencyFromEntry("2026-06-07T12:00:00+00:00", NOW) > 0.9, "yesterday → high");
assert.equal(recencyFromEntry("2020-01-01T00:00:00+00:00", NOW), 0.1, "ancient → floor");

// mapRanking: full item → signal
const item = {
  song: { uuid: "u1", name: "Essence", creditName: "Wizkid", imageUrl: "art" },
  position: 3, positionEvolution: 2, metric: 1000,
  entryState: "", entryDate: "2026-06-01T12:00:00+00:00", oldPosition: 5,
};
const sig = mapRanking(item, "shazam", "NG", { slug: "ng-top", maxResultsCount: 100 }, NOW)!;
assert.equal(sig.source, "shazam");
assert.equal(sig.sourceId, "u1");
assert.equal(sig.title, "Essence");
assert.equal(sig.artist, "Wizkid");
assert.equal(sig.region, "NG");
assert.equal(sig.artworkUrl, "art");
assert.deepEqual(sig.keywords, ["soundcharts:ng-top"]);
assert.ok(sig.engagement > 0.9 && sig.growthRate > 0.5 && sig.recency > 0.8);
assert.equal(mapRanking({ song: {} } as never, "shazam", "NG", { slug: "x" }, NOW), null, "no uuid → null");

console.log("soundcharts mappers: assertions passed");
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd functions && npx ts-node --project tsconfig.json test/soundcharts.test.ts`
Expected: FAIL — `soundcharts.ts` does not exist.

- [ ] **Step 3: Create `functions/src/clients/soundcharts.ts`** (mappers first)

```ts
import { SOUNDCHARTS_BASE_URL } from "../lib/config";
import type { SourceTrackSignal } from "../types";

export interface SoundchartsChart {
  slug: string;
  name?: string;
  countryCode?: string;
  maxResultsCount?: number;
}
export interface SoundchartsRankItem {
  song?: { uuid?: string; name?: string; creditName?: string; imageUrl?: string };
  position?: number;
  positionEvolution?: number | null;
  metric?: number;
  entryState?: string;
  entryDate?: string;
  oldPosition?: number | null;
}

const IRRELEVANT_PATTERNS = [
  /\bbts\b/i, /\bjungkook\b/i, /\bblackpink\b/i, /\btwice\b/i,
  /\bstray\s*kids\b/i, /\bnewjeans\b/i, /\baespa\b/i,
  /\b(k-?pop|kpop|j-?pop|jpop|c-?pop|cpop|anime|bollywood)\b/i,
  /\b(country|folk|bluegrass|gospel|christian|classical|metal|punk)\b/i,
];
function isRelevant(title: string, artist: string): boolean {
  return !IRRELEVANT_PATTERNS.some((p) => p.test(`${title} ${artist}`));
}

/** Choose the best charts for a region: country-specific first (capped at max),
 *  else the global/worldwide charts as a fallback. */
export function selectCharts(
  charts: SoundchartsChart[],
  region: string,
  max: number,
): SoundchartsChart[] {
  const r = region.toUpperCase();
  const country = charts.filter((c) => (c.countryCode ?? "").toUpperCase() === r);
  const pool = country.length > 0
    ? country
    : charts.filter((c) => (c.countryCode ?? "") === "");
  return pool.slice(0, Math.max(1, max));
}

function clamp(v: number, lo: number, hi: number): number {
  return Number(Math.min(hi, Math.max(lo, v)).toFixed(4));
}

export function engagementFromEntry(position: number, chartSize: number): number {
  const size = chartSize > 0 ? chartSize : 100;
  return clamp((size - position + 1) / size, 0, 1);
}

export function growthFromMovement(
  positionEvolution: number | null | undefined,
  isNew: boolean,
): number {
  if (isNew) return 0.9;
  const evo = positionEvolution ?? 0;
  return clamp(0.5 + evo / 40, 0.05, 1);
}

export function recencyFromEntry(entryDate: string | undefined, nowMs: number): number {
  if (!entryDate) return 0.5;
  const t = Date.parse(entryDate);
  if (Number.isNaN(t)) return 0.5;
  const ageDays = Math.max(1, (nowMs - t) / 86_400_000);
  return clamp(1 - ageDays / 90, 0.1, 1);
}

export function mapRanking(
  item: SoundchartsRankItem,
  source: SourceTrackSignal["source"],
  region: string,
  chart: SoundchartsChart,
  nowMs: number,
): SourceTrackSignal | null {
  const song = item.song ?? {};
  if (!song.uuid) return null;
  const position = item.position ?? 100;
  const isNew = (item.entryState ?? "").toUpperCase() === "NEW" || item.oldPosition == null;
  return {
    source,
    sourceId: song.uuid,
    title: (song.name ?? "Untitled").trim(),
    artist: (song.creditName ?? "Unknown Artist").trim(),
    artworkUrl: song.imageUrl,
    genre: undefined,
    platformUrl: `https://app.soundcharts.com/app/song/${song.uuid}`,
    keywords: [`soundcharts:${chart.slug}`],
    region,
    engagement: engagementFromEntry(position, chart.maxResultsCount ?? 100),
    growthRate: growthFromMovement(item.positionEvolution, isNew),
    recency: recencyFromEntry(item.entryDate, nowMs),
    releasedAt: undefined,
  } satisfies SourceTrackSignal;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd functions && npx ts-node --project tsconfig.json test/soundcharts.test.ts`
Expected: "soundcharts mappers: assertions passed".

---

## Task 4: The client orchestration (`fetchSoundchartsSignals`)

**Files:** Modify `functions/src/clients/soundcharts.ts`; Test `functions/test/soundcharts.test.ts` (append).

- [ ] **Step 1: Append failing tests**

```ts
import { fetchSoundchartsSignals } from "../src/clients/soundcharts";

// no creds → [] and ZERO http calls
let calls = 0;
const noCred = await fetchSoundchartsSignals({
  region: "NG", platforms: ["shazam"], appId: undefined, apiKey: undefined,
  httpGet: async () => { calls++; return {}; },
});
assert.deepEqual(noCred, [], "no creds → []");
assert.equal(calls, 0, "no creds → no http");

// with creds + injected http → discovers chart, fetches ranking, maps
const fakeHttp = async (path: string) => {
  if (path.includes("/by-platform/")) {
    return { items: [{ slug: "ng-top", name: "Top 100 Nigeria", countryCode: "NG" }] };
  }
  if (path.includes("/ranking/latest")) {
    return {
      related: { chart: { slug: "ng-top", maxResultsCount: 100 } },
      items: [
        { song: { uuid: "a", name: "Calm Down", creditName: "Rema", imageUrl: "i" },
          position: 1, positionEvolution: 3, entryDate: "2026-06-07T12:00:00+00:00", oldPosition: 4 },
        { song: { uuid: "b", name: "K-Pop Anthem", creditName: "BTS" },
          position: 2, entryDate: "2026-06-07T12:00:00+00:00" }, // filtered out
      ],
    };
  }
  return {};
};
const sigs = await fetchSoundchartsSignals({
  region: "NG", platforms: ["shazam"], appId: "x", apiKey: "y", httpGet: fakeHttp,
});
assert.equal(sigs.length, 1, "1 relevant signal (BTS filtered)");
assert.equal(sigs[0].source, "shazam");
assert.equal(sigs[0].sourceId, "a");
assert.equal(sigs[0].region, "NG");

console.log("soundcharts client: assertions passed");
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd functions && npx ts-node --project tsconfig.json test/soundcharts.test.ts`
Expected: FAIL — `fetchSoundchartsSignals` not exported.

- [ ] **Step 3: Implement** — append to `functions/src/clients/soundcharts.ts`

```ts
export type SoundchartsHttp = (path: string) => Promise<{
  items?: SoundchartsChart[] & SoundchartsRankItem[];
  related?: { chart?: SoundchartsChart };
}>;

const MAX_CHARTS_PER_PLATFORM = 2;

export async function fetchSoundchartsSignals(input: {
  region: string;
  platforms: string[];
  appId?: string;
  apiKey?: string;
  httpGet?: SoundchartsHttp;
}): Promise<SourceTrackSignal[]> {
  const { region, platforms, appId, apiKey } = input;
  if (!appId || !apiKey) return []; // no-op until a real key is configured

  const get = input.httpGet ?? makeHttpGet(appId, apiKey);
  const now = Date.now();
  const out: SourceTrackSignal[] = [];

  for (const code of platforms) {
    try {
      const chartResp = await get(
        `/api/v2/chart/song/by-platform/${encodeURIComponent(code)}?countryCode=${encodeURIComponent(region)}`,
      );
      const charts = selectCharts(
        (chartResp.items as SoundchartsChart[]) ?? [],
        region,
        MAX_CHARTS_PER_PLATFORM,
      );
      for (const chart of charts) {
        const rankResp = await get(
          `/api/v2.14/chart/song/${encodeURIComponent(chart.slug)}/ranking/latest?limit=100`,
        );
        const meta = rankResp.related?.chart ?? chart;
        for (const item of (rankResp.items as SoundchartsRankItem[]) ?? []) {
          const sig = mapRanking(item, code as SourceTrackSignal["source"], region, meta, now);
          if (sig && isRelevant(sig.title, sig.artist)) out.push(sig);
        }
      }
    } catch {
      // skip this platform; like every other source, ingestion is resilient
    }
  }
  return out;
}

function makeHttpGet(appId: string, apiKey: string): SoundchartsHttp {
  return async (path) => {
    const res = await fetch(`${SOUNDCHARTS_BASE_URL}${path}`, {
      headers: { "x-app-id": appId, "x-api-key": apiKey },
    });
    if (!res.ok) throw new Error(`Soundcharts ${res.status} for ${path}`);
    return res.json() as ReturnType<SoundchartsHttp>;
  };
}
```

- [ ] **Step 4: Run + register the test in the suite**

Run: `cd functions && npx ts-node --project tsconfig.json test/soundcharts.test.ts`
Expected: all three "…assertions passed" lines.
Edit `functions/package.json` `"test"` script: append ` && ts-node --project tsconfig.json test/soundcharts.test.ts`.

---

## Task 5: Wire into `runIngestion` (replace soundcloud/beatport)

**Files:** Modify `functions/src/index.ts`.

- [ ] **Step 1: Imports** — add near the other client imports:
```ts
import { fetchSoundchartsSignals } from "./clients/soundcharts";
```
add to the `./lib/config` import list: `SOUNDCHARTS_APP_ID, SOUNDCHARTS_API_KEY, getSoundchartsCreds, getSoundchartsPlatforms`.
Remove the now-unused imports `fetchSoundCloudSignals` (from `./clients/soundcloud`) and `fetchBeatportSignals` (from `./clients/beatport`). (Leave the `SOUNDCLOUD_*`/`BEATPORT_*` config imports — still referenced in `functionSecrets`.)

- [ ] **Step 2: Secrets** — add the two Soundcharts secrets to the `functionSecrets` array (keep the existing entries):
```ts
  SOUNDCHARTS_APP_ID,
  SOUNDCHARTS_API_KEY,
```

- [ ] **Step 3: Replace the soundcloud + beatport fetches** in the region loop's `settled` array. Replace the two `withRetry(() => fetchSoundCloudSignals(...))` and `withRetry(() => fetchBeatportSignals(...))` blocks with a single Soundcharts fetch, and update `sourceNames`:

```ts
    const scCreds = getSoundchartsCreds();
    const sourceNames = ["spotify", "youtube", "apple", "deezer", "soundcharts"];
    const settled = await Promise.allSettled([
      withRetry(() =>
        fetchSpotifySignals({
          clientId: normalizeSecretValue(SPOTIFY_CLIENT_ID.value()),
          clientSecret: normalizeSecretValue(SPOTIFY_CLIENT_SECRET.value()),
          region,
        }),
      ),
      withRetry(() =>
        fetchYouTubeSignals({
          apiKey: normalizeSecretValue(YOUTUBE_API_KEY.value()),
          region,
        }),
      ),
      withRetry(() =>
        fetchAppleMusicSignals({
          developerToken: normalizeSecretValue(APPLE_MUSIC_DEVELOPER_TOKEN.value()),
          region,
        }),
      ),
      withRetry(() => fetchDeezerSignals({ region })),
      withRetry(() =>
        fetchSoundchartsSignals({
          region,
          platforms: getSoundchartsPlatforms(),
          appId: scCreds?.appId,
          apiKey: scCreds?.apiKey,
        }),
      ),
    ]);
```
(The `regionCounts`/logging loop below is unchanged — it maps `settled[i]` to `sourceNames[i]`.)

- [ ] **Step 4: Update the returned `sources` list** in `runIngestion`'s return — replace the `"soundcloud", "beatport"` entries with `"shazam", "tiktok", "boomplay"` (they now come via Soundcharts). Find the `sources: [ ... ]` array and set it to:
```ts
    sources: [
      "spotify", "youtube", "apple", "audius", "audiomack",
      "deezer", "shazam", "tiktok", "boomplay",
    ],
```

- [ ] **Step 5: Typecheck**

Run: `cd functions && npx tsc --noEmit`
Expected: exit 0. (If `fetchSoundCloudSignals`/`fetchBeatportSignals` or `getBeatportApiBaseUrl` are now unused-import errors, remove those specific imports too.)

---

## Task 6: Full verification

- [ ] **Step 1: Functions test suite** — `cd functions && npm test` → Expected: all test files pass incl. soundcharts.
- [ ] **Step 2: Typecheck** — `cd functions && npx tsc --noEmit` → exit 0.
- [ ] **Step 3: Live sandbox smoke** (proves the real request/response contract, free):
```bash
cd functions && SOUNDCHARTS_APP_ID=soundcharts SOUNDCHARTS_API_KEY=soundcharts \
  npx ts-node -e "import('./src/clients/soundcharts').then(async m => { \
    const s = await m.fetchSoundchartsSignals({ region:'US', platforms:['spotify'], appId:'soundcharts', apiKey:'soundcharts', \
      httpGet: async (p)=>{ const r= await fetch('https://customer.api.soundcharts.com'+p,{headers:{'x-app-id':'soundcharts','x-api-key':'soundcharts'}}); return r.json(); } }); \
    console.log('sandbox signals:', s.length, s[0]); })"
```
Expected: prints a small number of signals from the sandbox's allowed charts (proves discovery→ranking→map works end-to-end against the live API). Note: sandbox `by-platform` may return charts whose ranking slugs are sandbox-restricted, so 0 is acceptable here — the unit tests already prove the mapping; this only confirms auth + endpoint paths.

---

## Self-review
- **Spec coverage:** secrets+platforms+creds gate (T1), source union (T2), pure mappers incl. auto-discover `selectCharts` (T3), no-op gate + orchestration (T4), wiring + soundcloud/beatport replacement + secret binding (T5), verify+sandbox (T6). All spec sections mapped.
- **Types consistent:** `getSoundchartsCreds`, `getSoundchartsPlatforms`, `selectCharts`, `engagementFromEntry`, `growthFromMovement`, `recencyFromEntry`, `mapRanking(item,source,region,chart,nowMs)`, `fetchSoundchartsSignals({region,platforms,appId,apiKey,httpGet})`, `SoundchartsHttp` used identically across tasks.
- **No-rebuild:** secrets bound in `functionSecrets` at deploy (T5); activation = `secrets:set` + redeploy, no code change.
- **Risk flagged:** sandbox ranking slugs are restricted (T6 note); real metric-field tweaks isolated to `mapRanking` (T3).

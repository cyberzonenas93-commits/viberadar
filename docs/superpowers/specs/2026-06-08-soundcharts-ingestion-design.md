# Soundcharts ingestion — Shazam/TikTok/Boomplay + replace SoundCloud/Beatport

**Date:** 2026-06-08
**Status:** Design — awaiting review

## Goal

Add Soundcharts as an ingestion provider for **five** platforms — `shazam`, `tiktok`, `boomplay` (new high-signal sources) plus `soundcloud` and `beatport` (replacing the currently-dead direct clients) — engineered so that a future move to the **paid Soundcharts plan requires no code rebuild**: it's wired in now and activates the moment a real API key is set.

## Decisions (locked)

- **Auto-discover** the main chart(s) per platform/region (no hand-maintained slugs).
- **Scope:** add shazam/tiktok/boomplay AND route soundcloud/beatport through Soundcharts.
- **No-op in production until a real key is set** — sandbox sample data never reaches the live `tracks` collection.

## Architecture

### 1. Source model
Add `shazam`, `tiktok`, `boomplay` to the `SourceTrackSignal.source` **union** in [types.ts](functions/src/types.ts) (`soundcloud`/`beatport` already exist) — that union is the *only* place source slugs are enumerated. `normalize.ts` derives sources dynamically (`new Set(signals.map(s => s.source))`, `platformDiversity` is `Math.min(count/4, 1)`), so it needs **no change** — the data flows through dedup/scoring/`platformDiversity` unchanged.

### 2. Config & secrets — [config.ts](functions/src/lib/config.ts)
- `SOUNDCHARTS_APP_ID = defineSecret("SOUNDCHARTS_APP_ID")`, `SOUNDCHARTS_API_KEY = defineSecret("SOUNDCHARTS_API_KEY")`.
- `SOUNDCHARTS_PLATFORMS = defineString("SOUNDCHARTS_PLATFORMS", { default: "shazam,tiktok,boomplay,soundcloud,beatport" })` — tune platforms with no code change.
- `getSoundchartsCreds(): { appId, apiKey } | null` — uses `normalizeSecretValue`; returns `null` when either secret is unset/placeholder (the "no real key" signal). Regions reuse `getConfiguredRegions()`.
- Constant `SOUNDCHARTS_BASE_URL = "https://customer.api.soundcharts.com"`. (The free sandbox uses the same URL with creds `soundcharts`/`soundcharts` — used **only** in tests/manual smoke, never as a production default that writes data.)

### 3. Client — `functions/src/clients/soundcharts.ts`
`fetchSoundchartsSignals({ region, platforms, appId, apiKey }): Promise<SourceTrackSignal[]>`:
1. If `!appId || !apiKey` → **return `[]`** (no-op gate; no HTTP).
2. For each platform `code` in `platforms`:
   - `GET /api/v2/chart/song/by-platform/{code}?countryCode={region}` → charts.
   - `selectCharts(charts, region, MAX=2)` (pure): keep country-matching (or global) charts, rank by relevance heuristic, take top `MAX`.
   - For each selected `slug`: `GET /api/v2.14/chart/song/{slug}/ranking/latest?limit=100` → ranked songs.
   - `mapRanking(entry, code, region, chartSlug)` (pure) → `SourceTrackSignal`:
     - `source = code`, `sourceId = song.uuid` (fallback ISRC), `title`, `artist` (creditName / first artist), `platformUrl`, `region`.
     - `engagement = engagementFromEntry(entry)` — normalized platform metric (streams/views/video-count) when present, else derived from `position`.
     - `growthRate = growthFromMovement(position, oldPosition)` — climbing → positive, new-entry → high, falling → low.
     - `recency = recencyFromEntry(entryDate)`.
     - `keywords = ['soundcharts:' + chartSlug]`, `releasedAt`.
   - Apply the shared K-pop/country **relevance filter** (same pattern as deezer.ts).
3. Auth via `x-app-id` / `x-api-key` headers; `fetchJson` helper throws on non-200 (caught by `Promise.allSettled` upstream, like every other source).

Pure, unit-tested helpers: `selectCharts`, `mapRanking`, `engagementFromEntry`, `growthFromMovement`, `recencyFromEntry`, plus the creds gate.

### 4. Wiring — [index.ts](functions/src/index.ts) `runIngestion()`
- Add `withRetry(() => fetchSoundchartsSignals({ region, platforms, ...creds }))` to the per-region `Promise.allSettled`, sourcing creds from `getSoundchartsCreds()` (skip entirely when `null`).
- **Remove** the `fetchSoundCloudSignals` and `fetchBeatportSignals` calls + their now-unused imports; drop `SOUNDCLOUD_CLIENT_ID/SOUNDCLOUD_OAUTH_TOKEN/BEATPORT_API_TOKEN` from `functionSecrets` (Soundcharts supplies those platforms now). The orphaned `clients/soundcloud.ts` / `clients/beatport.ts` files stay on disk (unimported) — optional later cleanup.
- Add `SOUNDCHARTS_APP_ID` + `SOUNDCHARTS_API_KEY` to `functionSecrets` so the function is **bound to the secrets at deploy time** (this is what makes later activation code-free).
- Update the summary log + `sources` list to reflect the new set.

### 5. Testing (TDD)
Unit tests (`functions/test/soundcharts.test.ts`, HTTP injected/mocked):
- `getSoundchartsCreds`: `null` for unset/placeholder; object for real values.
- `fetchSoundchartsSignals` returns `[]` and makes **no HTTP call** when creds are null.
- `selectCharts`: picks the country chart, caps at MAX, handles empty.
- `mapRanking`: position→engagement, climb→positive growth / fall→low, entryDate→recency, `source` = platform, `sourceId` from uuid.
- relevance filter drops blocked artists.
- Manual smoke (not in CI): hit the live sandbox (`soundcharts`/`soundcharts`) once to confirm the request/response contract.

## Files
**New:** `functions/src/clients/soundcharts.ts`, `functions/test/soundcharts.test.ts`.
**Modified:** `functions/src/types.ts` (source union), `functions/src/lib/config.ts` (secrets + platforms + creds helper), `functions/src/index.ts` (wire in Soundcharts, remove soundcloud/beatport calls), `functions/package.json` (test script). `normalize.ts` needs **no change**.

## The "no-rebuild" guarantee (explicit)
Deploy **once now** → the client ships wired-in but no-ops (no key) and the function is bound to the two secrets. To go paid later, the entire process is:
```
firebase functions:secrets:set SOUNDCHARTS_APP_ID
firebase functions:secrets:set SOUNDCHARTS_API_KEY
firebase deploy --only functions:ingestTrackSignals   # attaches the secret values
```
No code is written or restructured — just a secret + a redeploy. Platforms/regions are env-tunable (`SOUNDCHARTS_PLATFORMS`, `INGEST_REGIONS`) with no code change either.

## Risks
- **Real chart slugs + exact metric field names are unknowable without a paid key** (sandbox returns limited sample data). Mapping is coded defensively — every Soundcharts field treated as optional with sensible fallbacks — and validated against the sandbox response *contract*; the first real run may need a small tweak to the metric-field mapping (isolated to `mapRanking`/`engagementFromEntry`, the pure functions).
- **Secret activation needs a redeploy** (Firebase binds secret versions at deploy). That's a `firebase deploy`, not a code rebuild — acceptable per the requirement.
- Removing soundcloud/beatport direct fetches means those platforms produce **no data until a Soundcharts key is added** — but they already produce none today (SoundCloud returns 0, Beatport disabled), so it's a net wash until activation.

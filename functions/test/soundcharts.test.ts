import assert from "node:assert/strict";
import { getSoundchartsCreds, getSoundchartsPlatforms } from "../src/lib/config";
import {
  selectCharts,
  engagementFromEntry,
  growthFromMovement,
  recencyFromEntry,
  mapRanking,
  fetchSoundchartsSignals,
} from "../src/clients/soundcharts";

// ── creds gate: null unless BOTH app id + api key are real ───────────────────
process.env.SOUNDCHARTS_APP_ID = "";
process.env.SOUNDCHARTS_API_KEY = "";
assert.equal(getSoundchartsCreds(), null, "no creds → null");

process.env.SOUNDCHARTS_APP_ID = "myapp";
process.env.SOUNDCHARTS_API_KEY = "PLACEHOLDER";
assert.equal(getSoundchartsCreds(), null, "placeholder key → null");

process.env.SOUNDCHARTS_APP_ID = "myapp";
process.env.SOUNDCHARTS_API_KEY = "realkey";
assert.deepEqual(
  getSoundchartsCreds(),
  { appId: "myapp", apiKey: "realkey" },
  "both real → creds",
);

// ── platforms: default + override ────────────────────────────────────────────
delete process.env.SOUNDCHARTS_PLATFORMS;
assert.deepEqual(
  getSoundchartsPlatforms(),
  ["shazam", "tiktok", "boomplay", "soundcloud", "beatport"],
  "default platforms",
);
process.env.SOUNDCHARTS_PLATFORMS = "shazam, tiktok";
assert.deepEqual(
  getSoundchartsPlatforms(),
  ["shazam", "tiktok"],
  "override platforms",
);

console.log("soundcharts config: assertions passed");

// ── selectCharts: prefer country match, cap at max, global fallback ──────────
const charts = [
  { slug: "global-top", name: "Top Songs", countryCode: "" },
  { slug: "ng-top", name: "Top 100 Nigeria", countryCode: "NG" },
  { slug: "ng-disc", name: "Discovery Nigeria", countryCode: "NG" },
  { slug: "us-top", name: "Top 100 USA", countryCode: "US" },
];
const picked = selectCharts(charts, "NG", 2);
assert.equal(picked.length, 2, "caps at max");
assert.ok(picked.every((c) => c.countryCode === "NG"), "only NG charts when available");
assert.deepEqual(
  selectCharts(charts, "FR", 2).map((c) => c.slug),
  ["global-top"],
  "global fallback when no country match",
);

// ── scoring helpers ──────────────────────────────────────────────────────────
assert.equal(engagementFromEntry(1, 100), 1, "position 1 → 1.0");
assert.equal(engagementFromEntry(100, 100), 0.01, "last → ~0.01");
assert.equal(engagementFromEntry(50, 0), 0.51, "bad chartSize falls back to 100");

assert.equal(growthFromMovement(0, true), 0.9, "new entry → 0.9");
assert.ok(
  growthFromMovement(10, false) > growthFromMovement(-10, false),
  "climb beats fall",
);
assert.equal(growthFromMovement(-1000, false), 0.05, "big fall clamps to floor");

const NOW = Date.UTC(2026, 5, 8);
assert.equal(recencyFromEntry(undefined, NOW), 0.5, "missing → 0.5");
assert.ok(recencyFromEntry("2026-06-07T12:00:00+00:00", NOW) > 0.9, "yesterday → high");
assert.equal(recencyFromEntry("2020-01-01T00:00:00+00:00", NOW), 0.1, "ancient → floor");

// ── mapRanking ───────────────────────────────────────────────────────────────
const item = {
  song: { uuid: "u1", name: "Essence", creditName: "Wizkid", imageUrl: "art" },
  position: 3,
  positionEvolution: 2,
  metric: 1000,
  entryState: "",
  entryDate: "2026-06-01T12:00:00+00:00",
  oldPosition: 5,
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
assert.equal(
  mapRanking({ song: {} } as never, "shazam", "NG", { slug: "x" }, NOW),
  null,
  "no uuid → null",
);

console.log("soundcharts mappers: assertions passed");

// ── client orchestration (no-op gate + discover→rank→map) ────────────────────
void (async () => {
  let calls = 0;
  const noCred = await fetchSoundchartsSignals({
    region: "NG",
    platforms: ["shazam"],
    appId: undefined,
    apiKey: undefined,
    httpGet: async () => {
      calls++;
      return {};
    },
  });
  assert.deepEqual(noCred, [], "no creds → []");
  assert.equal(calls, 0, "no creds → no http");

  const fakeHttp = async (path: string) => {
    if (path.includes("/by-platform/")) {
      return {
        items: [{ slug: "ng-top", name: "Top 100 Nigeria", countryCode: "NG" }],
      };
    }
    if (path.includes("/ranking/latest")) {
      return {
        related: { chart: { slug: "ng-top", maxResultsCount: 100 } },
        items: [
          {
            song: { uuid: "a", name: "Calm Down", creditName: "Rema", imageUrl: "i" },
            position: 1,
            positionEvolution: 3,
            entryDate: "2026-06-07T12:00:00+00:00",
            oldPosition: 4,
          },
          {
            song: { uuid: "b", name: "K-Pop Anthem", creditName: "BTS" },
            position: 2,
            entryDate: "2026-06-07T12:00:00+00:00",
          },
        ],
      };
    }
    return {};
  };
  const sigs = await fetchSoundchartsSignals({
    region: "NG",
    platforms: ["shazam"],
    appId: "x",
    apiKey: "y",
    httpGet: fakeHttp as never,
  });
  assert.equal(sigs.length, 1, "1 relevant signal (BTS filtered)");
  assert.equal(sigs[0].source, "shazam");
  assert.equal(sigs[0].sourceId, "a");
  assert.equal(sigs[0].region, "NG");

  console.log("soundcharts client: assertions passed");
})();

import assert from "node:assert/strict";
import { getSoundchartsCreds, getSoundchartsPlatforms } from "../src/lib/config";
import {
  selectCharts,
  chartPriority,
  engagementFromEntry,
  growthFromMovement,
  recencyFromEntry,
  mapRanking,
  isRelevant,
  defaultGenreForRegion,
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
  ["shazam", "tiktok", "boomplay"],
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
assert.deepEqual(
  selectCharts(charts, "GLOBAL", 2).map((c) => c.slug),
  ["global-top"],
  "GLOBAL uses worldwide charts only",
);

// ── chart priority: main Top-N charts beat alphabetical genre/radio charts ───
// Regression: the live Shazam worldwide list is alphabetical, so list order
// used to pick "AfroBeats" + "Afrobeats on Radio" while "Top 200" (index ~98)
// was never selected.
const worldwideCharts = [
  { slug: "genre-global-10", name: "AfroBeats", countryCode: "" },
  { slug: "afrobeats-on-radio", name: "Afrobeats on Radio", countryCode: "" },
  { slug: "genre-global-9", name: "Country", countryCode: "" },
  { slug: "genre-global", name: "Pop", countryCode: "" },
  { slug: "shazam-top-200-world", name: "Top 200", countryCode: "" },
];
assert.deepEqual(
  selectCharts(worldwideCharts, "GLOBAL", 2).map((c) => c.slug),
  ["shazam-top-200-world", "genre-global-10"],
  "Top 200 selected first regardless of list order",
);

const usCharts = [
  { slug: "genre-shazam-us-country-1", name: "Country", countryCode: "US" },
  { slug: "genre-shazam-us-dance", name: "Dance", countryCode: "US" },
  { slug: "shazam-top-200-us", name: "Top 200", countryCode: "US" },
];
assert.equal(
  selectCharts(usCharts, "US", 2)[0].slug,
  "shazam-top-200-us",
  "country Top 200 beats alphabetical genre charts",
);

const boomplayGlobal = [
  {
    slug: "boomplay-daily-100-christian-gospel-europe",
    name: "Daily 100 Christian & Gospel Europe",
    countryCode: "",
  },
  { slug: "boomplay-daily-100-global", name: "Daily 100", countryCode: "" },
];
assert.deepEqual(
  selectCharts(boomplayGlobal, "GLOBAL", 2).map((c) => c.slug),
  ["boomplay-daily-100-global"],
  "gospel chart editions are excluded at selection time",
);
assert.ok(
  chartPriority({ slug: "pop-on-radio", name: "Pop on Radio" }) < 0,
  "radio airplay charts are excluded",
);
assert.ok(
  chartPriority({ slug: "tiktok-hot-50-us", name: "Hot 50" }) >
    chartPriority({ slug: "tiktok-breakout-us", name: "Breakout" }),
  "Hot 50 beats Breakout",
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
assert.equal(sig.genre, "Afrobeats", "NG chart → Afrobeats default genre");
assert.deepEqual(sig.keywords, ["soundcharts:ng-top"]);
assert.ok(sig.engagement > 0.9 && sig.growthRate > 0.5 && sig.recency > 0.8);
assert.equal(
  mapRanking({ song: {} } as never, "shazam", "NG", { slug: "x" }, NOW),
  null,
  "no uuid → null",
);

console.log("soundcharts mappers: assertions passed");

// ── relevance filter: secular Afrobeats kept; gospel/worship + k-pop dropped ──
assert.equal(isRelevant("Calm Down", "Rema"), true, "secular Afrobeats kept");
assert.equal(isRelevant("Essence", "Wizkid"), true, "secular Afrobeats kept");
assert.equal(
  isRelevant("Chanel", "Blaqbonez & Asake"),
  true,
  "secular Afrobeats kept",
);
assert.equal(
  isRelevant("Imela", "Sis. Chinyere Udoma"),
  false,
  "gospel honorific (Sis.) filtered",
);
assert.equal(
  isRelevant("Worship Medley", "Pastor Chris"),
  false,
  "worship + pastor honorific filtered",
);
assert.equal(
  isRelevant("Jehovah Overdo", "Moses Bliss"),
  false,
  "jehovah in title filtered",
);
assert.equal(isRelevant("Dynamite", "BTS"), false, "k-pop still filtered");

console.log("soundcharts filter: assertions passed");

// ── region → default genre (unblocks regional views for genre-less rankings) ──
assert.equal(defaultGenreForRegion("NG"), "Afrobeats", "NG → Afrobeats");
assert.equal(defaultGenreForRegion("GH"), "Afrobeats", "GH → Afrobeats");
assert.equal(defaultGenreForRegion("ZA"), "Amapiano", "ZA → Amapiano");
assert.equal(defaultGenreForRegion("US"), undefined, "US → no default");
assert.equal(defaultGenreForRegion("GB"), undefined, "GB → no default");
assert.equal(defaultGenreForRegion("ng"), "Afrobeats", "case-insensitive");

console.log("soundcharts genre defaults: assertions passed");

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

  const globalCalls: string[] = [];
  const globalHttp = async (path: string) => {
    globalCalls.push(path);
    if (path.includes("/by-platform/")) {
      return {
        items: [
          { slug: "world-top", name: "Top Songs", countryCode: "" },
          { slug: "gh-top", name: "Top 100 Ghana", countryCode: "GH" },
        ],
      };
    }
    if (path.includes("/ranking/latest")) {
      return {
        related: { chart: { slug: "world-top", maxResultsCount: 100 } },
        items: [
          {
            song: { uuid: "g", name: "Global Hit", creditName: "Global Artist" },
            position: 1,
            entryDate: "2026-06-07T12:00:00+00:00",
          },
        ],
      };
    }
    return {};
  };
  const globalSigs = await fetchSoundchartsSignals({
    region: "GLOBAL",
    platforms: ["shazam"],
    appId: "x",
    apiKey: "y",
    httpGet: globalHttp as never,
  });
  assert.ok(
    globalCalls.some((path) => path.includes("countryCode=")),
    "GLOBAL requests worldwide countryCode",
  );
  assert.equal(globalSigs.length, 1, "GLOBAL returns worldwide signal");
  assert.equal(globalSigs[0].region, "GLOBAL");
  assert.equal(globalSigs[0].genre, undefined);

  // ── pagination: a Top 200 chart on page 2 of the chart list is found ───────
  const pagedCalls: string[] = [];
  const pagedHttp = async (path: string) => {
    pagedCalls.push(path);
    if (path.includes("/by-platform/") && !path.includes("offset=100")) {
      return {
        items: [{ slug: "genre-global-10", name: "AfroBeats", countryCode: "" }],
        page: { next: "/api/v2/chart/song/by-platform/shazam?countryCode=&offset=100&limit=100" },
      };
    }
    if (path.includes("offset=100")) {
      return {
        items: [{ slug: "shazam-top-200-world", name: "Top 200", countryCode: "" }],
        page: { next: null },
      };
    }
    if (path.includes("/ranking/latest")) {
      return {
        related: { chart: { slug: "shazam-top-200-world", maxResultsCount: 200 } },
        items: [
          {
            song: { uuid: "t", name: "Chart Hit", creditName: "Chart Artist" },
            position: 1,
            entryDate: "2026-06-07T12:00:00+00:00",
          },
        ],
      };
    }
    return {};
  };
  const pagedSigs = await fetchSoundchartsSignals({
    region: "GLOBAL",
    platforms: ["shazam"],
    appId: "x",
    apiKey: "y",
    httpGet: pagedHttp as never,
  });
  assert.ok(
    pagedCalls.some((path) => path.includes("offset=100")),
    "chart list pagination is followed",
  );
  assert.ok(
    pagedCalls.some((path) => path.includes("shazam-top-200-world/ranking")),
    "paginated Top 200 chart is ranked",
  );
  assert.ok(
    pagedSigs.some((sig) => sig.sourceId === "t"),
    "signals come from the paginated Top 200 chart",
  );

  console.log("soundcharts client: assertions passed");
})();

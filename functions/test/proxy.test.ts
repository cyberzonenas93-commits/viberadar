/**
 * Unit tests for proxy.ts pure helpers.
 *
 * Tests only the pure URL-building functions and path-validation logic.
 * HTTP calls are integration-verified at deploy time; no network required here.
 *
 * To run:
 *   cd functions && npx ts-node --project tsconfig.json test/proxy.test.ts
 *
 * Exit code 0 = all pass, non-zero = failures.
 */

// We import the pure helpers directly. The onCall exports are not tested here
// because they require Firebase initialisation.
import {
  buildUrl,
  encodeQuery,
  isAllowedPath,
  mergeSoundchartsProxyTracks,
  normalizeSoundchartsSearchTokens,
  pickBestOnboardingArtistImage,
  resolveSoundchartsProxyInput,
  resolveOnboardingArtistNames,
  signalMatchesSoundchartsQuery,
} from "../src/proxy";

// ---------------------------------------------------------------------------
// Minimal assertion helpers (same pattern as pairing.test.ts)
// ---------------------------------------------------------------------------

let passed = 0;
let failed = 0;

function assert(condition: boolean, message: string): void {
  if (condition) {
    console.log(`  PASS  ${message}`);
    passed++;
  } else {
    console.error(`  FAIL  ${message}`);
    failed++;
  }
}

function assertEqual<T>(actual: T, expected: T, label: string): void {
  assert(
    actual === expected,
    `${label} (expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)})`,
  );
}

function assertThrows(fn: () => unknown, message: string): void {
  let threw = false;
  try {
    fn();
  } catch {
    threw = true;
  }
  assert(threw, message);
}

// ---------------------------------------------------------------------------
// encodeQuery
// ---------------------------------------------------------------------------

console.log("\n--- encodeQuery ---");

{
  const qs = encodeQuery({ q: "hello world", limit: 10, type: "track" });
  assert(qs.includes("q=hello%20world"), "encodeQuery: spaces encoded");
  assert(qs.includes("limit=10"), "encodeQuery: number value included");
  assert(qs.includes("type=track"), "encodeQuery: string value included");
}

{
  const qs = encodeQuery({ a: "x", b: undefined, c: null });
  assert(!qs.includes("b="), "encodeQuery: undefined values omitted");
  assert(!qs.includes("c="), "encodeQuery: null values omitted");
  assert(qs.includes("a=x"), "encodeQuery: defined values kept");
}

{
  const qs = encodeQuery({});
  assertEqual(qs, "", "encodeQuery: empty object → empty string");
}

{
  const qs = encodeQuery({ flag: true, off: false });
  assert(qs.includes("flag=true"), "encodeQuery: boolean true encoded");
  assert(qs.includes("off=false"), "encodeQuery: boolean false encoded");
}

{
  // Special characters in values must be percent-encoded
  const qs = encodeQuery({ key: "a&b=c" });
  assert(
    !qs.includes("a&b=c"),
    "encodeQuery: special chars in value are encoded",
  );
  assert(
    qs.includes("a%26b%3Dc"),
    "encodeQuery: & and = in value encoded correctly",
  );
}

// ---------------------------------------------------------------------------
// isAllowedPath
// ---------------------------------------------------------------------------

console.log("\n--- isAllowedPath ---");

const spotifyPrefixes = ["search", "artists", "tracks", "albums"];
const applePrefixes = ["catalog"];
const youtubePrefixes = ["search", "videos"];

// Spotify
{
  assert(
    isAllowedPath("search", spotifyPrefixes),
    "isAllowedPath: 'search' exact match allowed",
  );
  assert(
    isAllowedPath("artists", spotifyPrefixes),
    "isAllowedPath: 'artists' exact match allowed",
  );
  assert(
    isAllowedPath("artists/123", spotifyPrefixes),
    "isAllowedPath: 'artists/123' sub-path allowed",
  );
  assert(
    isAllowedPath("tracks/abc/features", spotifyPrefixes),
    "isAllowedPath: deep sub-path allowed",
  );
  assert(
    !isAllowedPath("recommendations", spotifyPrefixes),
    "isAllowedPath: 'recommendations' not allowed",
  );
  assert(
    !isAllowedPath("me/player", spotifyPrefixes),
    "isAllowedPath: 'me/player' not allowed",
  );
  assert(
    !isAllowedPath("", spotifyPrefixes),
    "isAllowedPath: empty path not allowed",
  );
}

// Leading slash stripped
{
  assert(
    isAllowedPath("/search", spotifyPrefixes),
    "isAllowedPath: leading slash is stripped before check",
  );
  assert(
    isAllowedPath("//artists", spotifyPrefixes),
    "isAllowedPath: double leading slash stripped",
  );
}

// Apple
{
  assert(
    isAllowedPath("catalog", applePrefixes),
    "isAllowedPath: 'catalog' exact match allowed",
  );
  assert(
    isAllowedPath("catalog/us/charts", applePrefixes),
    "isAllowedPath: 'catalog/us/charts' allowed",
  );
  assert(
    !isAllowedPath("admin", applePrefixes),
    "isAllowedPath: 'admin' not allowed for Apple",
  );
}

// YouTube
{
  assert(
    isAllowedPath("search", youtubePrefixes),
    "isAllowedPath: 'search' allowed for YouTube",
  );
  assert(
    isAllowedPath("videos", youtubePrefixes),
    "isAllowedPath: 'videos' allowed for YouTube",
  );
  assert(
    !isAllowedPath("channels", youtubePrefixes),
    "isAllowedPath: 'channels' not allowed for YouTube",
  );
  assert(
    !isAllowedPath("playlists", youtubePrefixes),
    "isAllowedPath: 'playlists' not allowed for YouTube",
  );
}

// Prefix-partial match must not pass (e.g. "searchmore" should not match "search")
{
  assert(
    !isAllowedPath("searchmore", spotifyPrefixes),
    "isAllowedPath: 'searchmore' does not match 'search' prefix",
  );
  assert(
    !isAllowedPath("artistsextra", spotifyPrefixes),
    "isAllowedPath: 'artistsextra' does not match 'artists' prefix",
  );
}

// ---------------------------------------------------------------------------
// buildUrl
// ---------------------------------------------------------------------------

console.log("\n--- buildUrl ---");

// Correct URL assembly
{
  const url = buildUrl(
    "https://api.spotify.com/v1",
    "search",
    { q: "test", type: "track", limit: 5 },
    spotifyPrefixes,
  );
  assert(
    url.startsWith("https://api.spotify.com/v1/search?"),
    "buildUrl: Spotify search URL structure correct",
  );
  assert(url.includes("q=test"), "buildUrl: query param q present");
  assert(url.includes("type=track"), "buildUrl: query param type present");
  assert(url.includes("limit=5"), "buildUrl: query param limit present");
}

{
  const url = buildUrl(
    "https://api.spotify.com/v1",
    "artists/1234",
    {},
    spotifyPrefixes,
  );
  assertEqual(
    url,
    "https://api.spotify.com/v1/artists/1234",
    "buildUrl: no query → no trailing ?",
  );
}

{
  const url = buildUrl(
    "https://api.music.apple.com/v1",
    "catalog/us/charts",
    { types: "songs", limit: 20 },
    applePrefixes,
  );
  assert(
    url.startsWith("https://api.music.apple.com/v1/catalog/us/charts?"),
    "buildUrl: Apple Music catalog URL correct",
  );
}

{
  const url = buildUrl(
    "https://www.googleapis.com/youtube/v3",
    "search",
    { part: "snippet", q: "afrobeats", key: "FAKE_KEY" },
    youtubePrefixes,
  );
  assert(
    url.startsWith("https://www.googleapis.com/youtube/v3/search?"),
    "buildUrl: YouTube search URL correct",
  );
  assert(url.includes("key=FAKE_KEY"), "buildUrl: API key injected in query");
}

// Leading slash in path is stripped cleanly
{
  const url = buildUrl(
    "https://api.spotify.com/v1",
    "/search",
    { q: "house" },
    spotifyPrefixes,
  );
  assert(
    !url.includes("//search"),
    "buildUrl: double slash not produced when path has leading /",
  );
  assert(
    url.includes("/v1/search?"),
    "buildUrl: path joined correctly after stripping leading /",
  );
}

// Disallowed path throws
{
  assertThrows(
    () =>
      buildUrl(
        "https://api.spotify.com/v1",
        "recommendations",
        {},
        spotifyPrefixes,
      ),
    "buildUrl: disallowed Spotify path throws",
  );
  assertThrows(
    () =>
      buildUrl("https://api.spotify.com/v1", "me/player", {}, spotifyPrefixes),
    "buildUrl: disallowed 'me/player' path throws",
  );
  assertThrows(
    () =>
      buildUrl("https://api.music.apple.com/v1", "admin", {}, applePrefixes),
    "buildUrl: disallowed Apple path throws",
  );
  assertThrows(
    () =>
      buildUrl(
        "https://www.googleapis.com/youtube/v3",
        "playlists",
        {},
        youtubePrefixes,
      ),
    "buildUrl: disallowed YouTube path throws",
  );
}

// Empty path throws
{
  assertThrows(
    () => buildUrl("https://api.spotify.com/v1", "", {}, spotifyPrefixes),
    "buildUrl: empty path throws",
  );
}

// Base with trailing slash — no double slash
{
  const url = buildUrl(
    "https://api.spotify.com/v1/",
    "search",
    { q: "test" },
    spotifyPrefixes,
  );
  assert(
    !url.includes("v1//"),
    "buildUrl: base with trailing slash does not produce double slash",
  );
}

// ---------------------------------------------------------------------------
// onboarding artist preview helpers
// ---------------------------------------------------------------------------

console.log("\n--- onboarding artist preview helpers ---");

{
  const names = resolveOnboardingArtistNames([
    "Drake",
    " drake ",
    "Kendrick Lamar",
  ]);
  assertEqual(
    names.length,
    2,
    "resolveOnboardingArtistNames: duplicate names removed",
  );
  assertEqual(
    names[0],
    "Drake",
    "resolveOnboardingArtistNames: canonical name returned",
  );
  assertEqual(
    names[1],
    "Kendrick Lamar",
    "resolveOnboardingArtistNames: second canonical name returned",
  );
}

{
  assertThrows(
    () => resolveOnboardingArtistNames(["Not In The Curated List"]),
    "resolveOnboardingArtistNames: rejects non-onboarding artist names",
  );
  assertThrows(
    () => resolveOnboardingArtistNames(new Array(21).fill("Drake")),
    "resolveOnboardingArtistNames: rejects oversized batches",
  );
}

{
  const picked = pickBestOnboardingArtistImage("Drake", [
    {
      id: "fuzzy",
      name: "Drake Bell",
      images: [{ url: "https://example.com/fuzzy.jpg" }],
    },
    {
      id: "exact",
      name: "Drake",
      images: [{ url: "https://example.com/exact.jpg" }],
    },
  ]);
  assertEqual(
    picked?.spotifyId,
    "exact",
    "pickBestOnboardingArtistImage: exact match wins",
  );
  assertEqual(
    picked?.imageUrl,
    "https://example.com/exact.jpg",
    "pickBestOnboardingArtistImage: image URL returned",
  );
}

{
  const picked = pickBestOnboardingArtistImage("Drake", [
    { id: "no-image", name: "Drake", images: [] },
  ]);
  assertEqual(
    picked,
    null,
    "pickBestOnboardingArtistImage: null when no image exists",
  );
}

// ---------------------------------------------------------------------------
// Soundcharts proxy helpers
// ---------------------------------------------------------------------------

console.log("\n--- Soundcharts proxy helpers ---");

{
  const input = resolveSoundchartsProxyInput(
    {
      query: "best Afrobeats hits",
      region: "ng",
      platforms: ["shazam", "not-configured"],
      limit: 500,
    },
    {
      regions: ["US", "NG", "GH"],
      platforms: ["shazam", "tiktok"],
    },
  );
  assertEqual(
    input.query,
    "best Afrobeats hits",
    "resolveSoundchartsProxyInput: query trimmed",
  );
  assertEqual(
    input.regions.join(","),
    "NG",
    "resolveSoundchartsProxyInput: single region normalized",
  );
  assertEqual(
    input.platforms.join(","),
    "shazam",
    "resolveSoundchartsProxyInput: unconfigured platforms filtered",
  );
  assertEqual(input.limit, 100, "resolveSoundchartsProxyInput: limit capped");
}

{
  const input = resolveSoundchartsProxyInput(
    { query: "global songs" },
    {
      regions: ["US", "NG", "GH"],
      platforms: ["shazam", "tiktok"],
    },
  );
  assertEqual(
    input.regions.join(","),
    "GLOBAL",
    "resolveSoundchartsProxyInput: no region means worldwide charts",
  );
}

{
  const input = resolveSoundchartsProxyInput(
    { region: "All" },
    {
      regions: ["US", "NG", "GH"],
      platforms: ["shazam", "tiktok"],
    },
  );
  assertEqual(
    input.regions.join(","),
    "GLOBAL",
    "resolveSoundchartsProxyInput: All maps to worldwide charts",
  );
}

{
  const tokens = normalizeSoundchartsSearchTokens(
    "best top popular Afrobeats 120 bpm",
  );
  assertEqual(
    tokens.join(","),
    "afrobeats",
    "normalizeSoundchartsSearchTokens: removes builder noise",
  );
}

const soundchartsSignal = {
  source: "shazam" as const,
  sourceId: "u1",
  title: "Last Last",
  artist: "Burna Boy",
  artworkUrl: "https://example.com/art.jpg",
  genre: "Afrobeats",
  platformUrl: "https://app.soundcharts.com/app/song/u1",
  keywords: ["soundcharts:ng-top"],
  region: "NG",
  engagement: 0.9,
  growthRate: 0.8,
  recency: 0.7,
};

{
  assert(
    signalMatchesSoundchartsQuery(soundchartsSignal, "Burna Boy"),
    "signalMatchesSoundchartsQuery: artist query matches",
  );
  assert(
    signalMatchesSoundchartsQuery(soundchartsSignal, "best Afrobeats hits"),
    "signalMatchesSoundchartsQuery: genre query matches",
  );
  assert(
    !signalMatchesSoundchartsQuery(soundchartsSignal, "Amapiano"),
    "signalMatchesSoundchartsQuery: unrelated genre does not match",
  );
}

{
  const merged = mergeSoundchartsProxyTracks([
    soundchartsSignal,
    {
      ...soundchartsSignal,
      source: "tiktok" as const,
      sourceId: "u2",
      region: "GH",
      growthRate: 1,
    },
  ]);
  assertEqual(
    merged.length,
    1,
    "mergeSoundchartsProxyTracks: duplicates by title+artist",
  );
  assertEqual(
    merged[0].sources.join(","),
    "shazam,tiktok",
    "mergeSoundchartsProxyTracks: source list merged",
  );
  assertEqual(
    merged[0].regions.join(","),
    "GH,NG",
    "mergeSoundchartsProxyTracks: region list merged",
  );
  assert(
    merged[0].popularity > 0,
    "mergeSoundchartsProxyTracks: popularity is scored",
  );
}

{
  // Regression: chart position must dominate the score. Equal weighting let a
  // brand-new mid-chart entry outscore the long-charting #2 hit, inverting
  // chart order in the returned list.
  const longChartingTopHit = {
    ...soundchartsSignal,
    sourceId: "top-hit",
    title: "Jamaican (Bam Bam)",
    engagement: 0.99, // chart position #2
    growthRate: 0.5,
    recency: 0.1, // charting since last year
  };
  const brandNewMidEntry = {
    ...soundchartsSignal,
    sourceId: "new-entry",
    title: "RUBBERZ",
    engagement: 0.48, // chart position #53
    growthRate: 0.9, // NEW
    recency: 1.0, // entered this week
  };
  const ranked = mergeSoundchartsProxyTracks([
    brandNewMidEntry,
    longChartingTopHit,
  ]);
  assertEqual(
    ranked[0].title,
    "Jamaican (Bam Bam)",
    "scoring: top-of-chart hit outranks brand-new mid-chart entry",
  );
  assert(
    ranked[1].popularity > 40,
    "scoring: new entries still get meaningful movement/freshness credit",
  );
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

console.log(`\n=== Results: ${passed} passed, ${failed} failed ===\n`);
if (failed > 0) process.exit(1);

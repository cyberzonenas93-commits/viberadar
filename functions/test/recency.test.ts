import assert from "node:assert/strict";
import {
  ageInHours,
  recencyDecayFactor,
  decayedScore,
  isStale,
  planTrackDecay,
  RECENCY_DEFAULTS,
} from "../src/lib/recency";

const NOW = Date.UTC(2026, 5, 8, 16, 0, 0); // 2026-06-08T16:00:00Z
const H = 3_600_000;
const iso = (ms: number) => new Date(ms).toISOString();

// ── ageInHours ──────────────────────────────────────────────────────────────
assert.equal(ageInHours("2026-06-08T16:00:00.000Z", NOW), 0, "same instant → 0h");
assert.equal(ageInHours("2026-06-08T04:00:00.000Z", NOW), 12, "12h old");
assert.equal(ageInHours("2026-06-07T16:00:00.000Z", NOW), 24, "24h old");
assert.equal(ageInHours("2026-06-08T18:00:00.000Z", NOW), -2, "future → negative age");
assert.equal(ageInHours("not-a-date", NOW), null, "unparseable → null");
assert.equal(ageInHours("", NOW), null, "empty → null");
assert.equal(ageInHours(undefined, NOW), null, "missing → null");

// ── recencyDecayFactor (half-life 24h, retire at 72h) ───────────────────────
assert.equal(recencyDecayFactor(0), 1, "fresh → 1");
assert.equal(recencyDecayFactor(24), 0.5, "one half-life → 0.5");
assert.equal(recencyDecayFactor(48), 0.25, "two half-lives → 0.25");
assert.equal(recencyDecayFactor(72), 0, "retire cliff at 72h → 0");
assert.equal(recencyDecayFactor(200), 0, "well past retire → 0");
assert.equal(recencyDecayFactor(-5), 1, "negative age (clock skew) → 1");
assert.ok(
  Math.abs(recencyDecayFactor(12) - Math.SQRT1_2) < 1e-9,
  "12h ≈ 0.7071",
);

// ── decayedScore ────────────────────────────────────────────────────────────
assert.equal(decayedScore(0.8, 0), 0.8, "fresh keeps base score");
assert.equal(decayedScore(0.8, 24), 0.4, "24h halves the score");
assert.equal(decayedScore(0.8, 48), 0.2, "48h quarters the score");
assert.equal(decayedScore(0.8, 72), 0, "stale → 0");
assert.equal(decayedScore(0, 0), 0, "zero base stays zero");

// ── isStale ─────────────────────────────────────────────────────────────────
assert.equal(isStale(0), false, "fresh not stale");
assert.equal(isStale(71), false, "just under retire window not stale");
assert.equal(isStale(72), true, "at retire window → stale");
assert.equal(isStale(500), true, "ancient → stale");

// ── planTrackDecay (the per-doc decision the sweep applies) ──────────────────
assert.deepEqual(
  planTrackDecay({ trendScore: 0.8, updatedAt: iso(NOW) }, NOW),
  { trendScore: 0.8, baseScore: 0.8, clearRegions: false },
  "fresh doc without base_score → seeds base_score",
);
assert.equal(
  planTrackDecay({ trendScore: 0.8, baseScore: 0.8, updatedAt: iso(NOW) }, NOW),
  null,
  "fresh doc, base set, unchanged → null (skip write)",
);
assert.deepEqual(
  planTrackDecay({ trendScore: 0.8, baseScore: 0.8, updatedAt: iso(NOW - 24 * H) }, NOW),
  { trendScore: 0.4, baseScore: 0.8, clearRegions: false },
  "24h old halves the score",
);
assert.deepEqual(
  planTrackDecay({ trendScore: 0.8, updatedAt: iso(NOW - 24 * H) }, NOW),
  { trendScore: 0.4, baseScore: 0.8, clearRegions: false },
  "existing doc seeds base from current score, then decays",
);
assert.deepEqual(
  planTrackDecay({ trendScore: 0.7, baseScore: 0.7, updatedAt: iso(NOW - 100 * H) }, NOW),
  { trendScore: 0, baseScore: 0.7, clearRegions: true },
  "stale doc → retire (score 0) and clear regions",
);
assert.equal(
  planTrackDecay({ trendScore: 0.8, updatedAt: "bad" }, NOW),
  null,
  "unparseable updated_at → null (leave untouched)",
);
assert.equal(
  planTrackDecay({ trendScore: 0.8, baseScore: 0.8, updatedAt: iso(NOW + 2 * H) }, NOW),
  null,
  "future timestamp (clock skew) treated as fresh → skip",
);

// ── write epsilon: don't rewrite a doc whose score barely moved ──────────────
assert.equal(
  planTrackDecay({ trendScore: 0.5, baseScore: 0.5, updatedAt: iso(NOW - 0.2 * H) }, NOW),
  null,
  "sub-epsilon decay on a base-set doc → null (skip write)",
);
assert.deepEqual(
  planTrackDecay({ trendScore: 0.001, baseScore: 0.5, updatedAt: iso(NOW - 100 * H) }, NOW),
  { trendScore: 0, baseScore: 0.5, clearRegions: true },
  "stale still retires regardless of epsilon",
);

// ── defaults are sane ───────────────────────────────────────────────────────
assert.equal(RECENCY_DEFAULTS.retireHours, 72, "retires after 3 days");
assert.ok(RECENCY_DEFAULTS.halfLifeHours > 0, "positive half-life");

console.log("recency.test.ts: all assertions passed");

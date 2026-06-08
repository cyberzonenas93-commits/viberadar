/**
 * recency.ts — recency-aware trend scoring.
 *
 * `trend_score` from the ingestion batch is a *relative* signal strength that
 * is only meaningful within a single run. Left alone, a track that charted once
 * keeps its high score forever (writeTracks only updates tracks present in the
 * current batch), so stale songs pin the top of "Trending". These pure helpers
 * decay a track's score by how long ago it was last seen and retire it entirely
 * once it has fallen off the charts for `retireHours`.
 */

export interface RecencyOptions {
  /** Hours for the score to halve. */
  halfLifeHours?: number;
  /** Age at/after which a track is retired (score forced to 0). */
  retireHours?: number;
  /** Minimum score delta worth a Firestore write (avoids churn as tracks age). */
  writeEpsilon?: number;
}

export const RECENCY_DEFAULTS = {
  halfLifeHours: 24,
  retireHours: 72,
  writeEpsilon: 0.01,
} as const;

/**
 * Hours between `updatedAtIso` and `nowMs`. Returns null when the timestamp is
 * missing or unparseable (caller should leave such docs untouched). A future
 * timestamp yields a negative value (treated as fresh downstream).
 */
export function ageInHours(
  updatedAtIso: string | undefined | null,
  nowMs: number,
): number | null {
  if (!updatedAtIso) return null;
  const parsed = Date.parse(updatedAtIso);
  if (Number.isNaN(parsed)) return null;
  return (nowMs - parsed) / 3_600_000;
}

/** Multiplier in [0, 1]: 1 when fresh, 0.5 per half-life, 0 once retired. */
export function recencyDecayFactor(
  ageHours: number,
  opts: RecencyOptions = {},
): number {
  const halfLife = opts.halfLifeHours ?? RECENCY_DEFAULTS.halfLifeHours;
  const retire = opts.retireHours ?? RECENCY_DEFAULTS.retireHours;
  if (ageHours <= 0) return 1;
  if (ageHours >= retire) return 0;
  return Math.pow(0.5, ageHours / halfLife);
}

/** A base score decayed by age, rounded to 4dp to match stored precision. */
export function decayedScore(
  baseScore: number,
  ageHours: number,
  opts: RecencyOptions = {},
): number {
  return Number((baseScore * recencyDecayFactor(ageHours, opts)).toFixed(4));
}

/** True once a track has aged past the retire window. */
export function isStale(ageHours: number, opts: RecencyOptions = {}): boolean {
  const retire = opts.retireHours ?? RECENCY_DEFAULTS.retireHours;
  return ageHours >= retire;
}

export interface TrackDecayPlan {
  /** New, recency-decayed score to store (0 when retired). */
  trendScore: number;
  /** Stable pre-decay score; seeded from the current score on first sweep. */
  baseScore: number;
  /** Whether the track has aged out and its region_scores should be cleared. */
  clearRegions: boolean;
}

/**
 * Decide how to rescore one track. Returns null when nothing needs to change
 * (so the sweep can skip the write) or when `updatedAt` is missing/unparseable
 * (so a malformed doc is never clobbered).
 *
 * `baseScore` is the un-decayed signal strength. Existing docs predate the
 * field, so the first sweep seeds it from the current `trendScore` (which is
 * still the original value, since decay has not run yet).
 */
export function planTrackDecay(
  track: { trendScore: number; baseScore?: number | null; updatedAt?: string | null },
  nowMs: number,
  opts: RecencyOptions = {},
): TrackDecayPlan | null {
  const age = ageInHours(track.updatedAt, nowMs);
  if (age === null) return null;

  const hasBase = typeof track.baseScore === "number";
  const base = hasBase ? (track.baseScore as number) : track.trendScore;
  const newTrend = decayedScore(base, age, opts);
  const retire = isStale(age, opts);

  const epsilon = opts.writeEpsilon ?? RECENCY_DEFAULTS.writeEpsilon;
  const scoreChanged =
    Math.abs(newTrend - Number(track.trendScore.toFixed(4))) >= epsilon;
  if (hasBase && !scoreChanged && !retire) return null;

  return { trendScore: newTrend, baseScore: base, clearRegions: retire };
}

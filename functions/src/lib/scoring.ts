interface ScoringInput {
  growthRate: number;
  engagement: number;
  recency: number;
  platformDiversity: number;
  regionWeight: number;
}

export function normalizeMetric(values: number[]): number[] {
  if (values.length === 0) {
    return [];
  }
  const min = Math.min(...values);
  const max = Math.max(...values);
  if (max === min) {
    return values.map(() => 0.5);
  }
  return values.map((value) => Number(((value - min) / (max - min)).toFixed(4)));
}

export function scoreTrend(input: ScoringInput): number {
  const score =
    input.growthRate * 0.4 +
    input.engagement * 0.2 +
    input.recency * 0.2 +
    input.platformDiversity * 0.1 +
    input.regionWeight * 0.1;

  return Number(score.toFixed(4));
}

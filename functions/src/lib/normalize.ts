import { createHash } from "node:crypto";

import { classifyVibe, deriveEnergyLevel } from "./classify";
import { normalizeMetric, scoreTrend } from "./scoring";
import type { SourceTrackSignal, UnifiedTrackRecord } from "../types";

interface ExistingTrackSnapshot {
  trend_history?: Array<{ label: string; score: number }>;
  created_at?: string;
  genre?: string;
  platform_links?: Record<string, string>;
}

interface MergeAccumulator {
  title: string;
  artist: string;
  artworkUrl: string;
  bpm: number | null;
  key: string;
  genre: string;
  keywords: string[];
  platformLinks: Record<string, string>;
  signals: SourceTrackSignal[];
  regionScores: Record<string, number>;
}

export function mergeSignalsIntoTracks(
  signals: SourceTrackSignal[],
  existingById: Record<string, ExistingTrackSnapshot>,
): UnifiedTrackRecord[] {
  const merged = new Map<string, MergeAccumulator>();

  for (const signal of signals) {
    const key = `${canonicalize(signal.title)}::${canonicalize(signal.artist)}`;
    const current = merged.get(key) ?? {
      title: signal.title,
      artist: signal.artist,
      artworkUrl: signal.artworkUrl ?? "",
      bpm: signal.bpm ?? null,
      key: signal.key ?? "--",
      genre: signal.genre ?? inferGenreFromKeywords(signal.keywords),
      keywords: [...signal.keywords],
      platformLinks: {},
      signals: [],
      regionScores: {},
    };

    current.artworkUrl = current.artworkUrl || signal.artworkUrl || "";
    current.bpm = current.bpm ?? signal.bpm ?? null;
    current.key = current.key === "--" ? (signal.key ?? "--") : current.key;
    current.genre =
      current.genre || signal.genre || inferGenreFromKeywords(signal.keywords);
    current.keywords = Array.from(
      new Set([...current.keywords, ...signal.keywords]),
    );
    current.platformLinks[signal.source] = signal.platformUrl;
    current.signals.push(signal);
    if (signal.region) {
      current.regionScores[signal.region] = Math.max(
        current.regionScores[signal.region] ?? 0,
        (signal.engagement + signal.growthRate + signal.recency) / 3,
      );
    }

    merged.set(key, current);
  }

  const aggregateMetrics = Array.from(merged.values()).map((entry) => ({
    growthRate: average(entry.signals.map((signal) => signal.growthRate)),
    engagement: average(entry.signals.map((signal) => signal.engagement)),
    recency: average(entry.signals.map((signal) => signal.recency)),
    platformDiversity: Math.min(
      new Set(entry.signals.map((signal) => signal.source)).size / 4,
      1,
    ),
    regionWeight: Math.min(Object.keys(entry.regionScores).length / 4, 1),
  }));

  const normalizedGrowth = normalizeMetric(
    aggregateMetrics.map((metric) => metric.growthRate),
  );
  const normalizedEngagement = normalizeMetric(
    aggregateMetrics.map((metric) => metric.engagement),
  );
  const normalizedRecency = normalizeMetric(
    aggregateMetrics.map((metric) => metric.recency),
  );
  const normalizedPlatform = normalizeMetric(
    aggregateMetrics.map((metric) => metric.platformDiversity),
  );
  const normalizedRegion = normalizeMetric(
    aggregateMetrics.map((metric) => metric.regionWeight),
  );

  const now = new Date();
  return Array.from(merged.entries()).map(([mergeKey, entry], index) => {
    const trendScore = scoreTrend({
      growthRate: normalizedGrowth[index] ?? 0.5,
      engagement: normalizedEngagement[index] ?? 0.5,
      recency: normalizedRecency[index] ?? 0.5,
      platformDiversity: normalizedPlatform[index] ?? 0.5,
      regionWeight: normalizedRegion[index] ?? 0.5,
    });
    const id = buildTrackId(mergeKey);
    const previous = existingById[id];
    const history = [...(previous?.trend_history ?? [])].slice(-6).concat([
      {
        label: `T${now.getUTCHours().toString().padStart(2, "0")}`,
        score: trendScore,
      },
    ]);

    return {
      id,
      title: entry.title,
      artist: entry.artist,
      artwork_url: entry.artworkUrl,
      bpm: entry.bpm,
      key: entry.key,
      genre:
        (entry.genre && entry.genre !== "Open Format"
          ? entry.genre
          : previous?.genre) || "Open Format",
      vibe: classifyVibe({
        bpm: entry.bpm,
        genre:
          (entry.genre && entry.genre !== "Open Format"
            ? entry.genre
            : previous?.genre) || "Open Format",
        keywords: entry.keywords,
      }),
      trend_score: trendScore,
      region_scores: Object.fromEntries(
        Object.entries(entry.regionScores).map(([region, value]) => [
          region,
          Number(value.toFixed(4)),
        ]),
      ),
      platform_links: {
        ...(previous?.platform_links ?? {}),
        ...entry.platformLinks,
      },
      created_at: previous?.created_at ?? now.toISOString(),
      updated_at: now.toISOString(),
      energy_level: deriveEnergyLevel({
        bpm: entry.bpm,
        genre:
          (entry.genre && entry.genre !== "Open Format"
            ? entry.genre
            : previous?.genre) || "Open Format",
        keywords: entry.keywords,
      }),
      trend_history: history.slice(-7),
      source_count: entry.signals.length,
    } satisfies UnifiedTrackRecord;
  });
}

function buildTrackId(value: string): string {
  return createHash("sha1").update(value).digest("hex").slice(0, 20);
}

function canonicalize(value: string): string {
  return value
    .toLowerCase()
    .replace(/\((?!remix|edit|mix|version|vip|dub|flip|bootleg)[^)]*\)/gi, "")
    .replace(/\[(?!remix|edit|mix|version|vip|dub|flip|bootleg)[^\]]*]/gi, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function inferGenreFromKeywords(keywords: string[]): string {
  const text = ` ${keywords.join(" ").toLowerCase()} `;
  if (/\b(afrobeats?|afro[-\s]?pop|afro[-\s]?swing)\b/.test(text)) {
    return "Afrobeats";
  }
  if (/\bamapiano\b/.test(text)) {
    return "Amapiano";
  }
  if (/\b(deep\s?house|tech\s?house|house\s?music|afro[-\s]?house)\b/.test(text) || /\bhouse\b/.test(text)) {
    return "House";
  }
  if (/\b(edm|dance[-\s]?hall|dancehall|dance\s?music|electronic)\b/.test(text)) {
    return "Dance";
  }
  if (/\b(hip[-\s]?hop|rap|trap)\b/.test(text)) {
    return "Hip-Hop";
  }
  if (/\b(r&b|rnb|soul)\b/.test(text)) {
    return "R&B";
  }
  if (/\b(reggaeton|latin)\b/.test(text)) {
    return "Latin";
  }
  if (/\b(drill|grime|uk\s?drill)\b/.test(text)) {
    return "Drill";
  }
  return "Open Format";
}

function average(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

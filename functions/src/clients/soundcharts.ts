import { SOUNDCHARTS_BASE_URL } from "../lib/config";
import type { SourceTrackSignal } from "../types";

export interface SoundchartsChart {
  slug: string;
  name?: string;
  countryCode?: string;
  maxResultsCount?: number;
}

export interface SoundchartsRankItem {
  song?: {
    uuid?: string;
    name?: string;
    creditName?: string;
    imageUrl?: string;
  };
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

/**
 * Choose the best charts for a region: country-specific first (capped at max),
 * otherwise the global/worldwide charts (countryCode === "") as a fallback.
 */
export function selectCharts(
  charts: SoundchartsChart[],
  region: string,
  max: number,
): SoundchartsChart[] {
  const r = region.toUpperCase();
  const country = charts.filter(
    (c) => (c.countryCode ?? "").toUpperCase() === r,
  );
  const pool =
    country.length > 0
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

export function recencyFromEntry(
  entryDate: string | undefined,
  nowMs: number,
): number {
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
  const isNew =
    (item.entryState ?? "").toUpperCase() === "NEW" || item.oldPosition == null;
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

// ── Orchestration (added in Task 4) ──────────────────────────────────────────

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
          const sig = mapRanking(
            item,
            code as SourceTrackSignal["source"],
            region,
            meta,
            now,
          );
          if (sig && isRelevant(sig.title, sig.artist)) out.push(sig);
        }
      }
    } catch {
      // skip this platform; ingestion is resilient (Promise.allSettled upstream)
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

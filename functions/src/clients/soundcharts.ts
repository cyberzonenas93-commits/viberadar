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

export const SOUNDCHARTS_GLOBAL_REGION = "GLOBAL";

const IRRELEVANT_PATTERNS = [
  /\bbts\b/i, /\bjungkook\b/i, /\bblackpink\b/i, /\btwice\b/i,
  /\bstray\s*kids\b/i, /\bnewjeans\b/i, /\baespa\b/i,
  /\b(k-?pop|kpop|j-?pop|jpop|c-?pop|cpop|anime|bollywood)\b/i,
  /\b(country|folk|bluegrass|gospel|christian|classical|metal|punk)\b/i,
  // Worship/gospel dominates Boomplay NG/GH charts but isn't useful for the
  // DJ/club use case. Kept high-precision: artist honorifics first (the
  // strongest signal — e.g. "Sis. Chinyere Udoma", "Pastor Chris"), then a
  // few unambiguous content terms.
  /\b(pastor|bishop|evangelist|apostle|prophet|reverend|deaconess)\b/i,
  /\b(sis|bro|evang|rev|min|pst|ev)\.\s/i,
  /\b(jehovah|hallelujah|hosanna|anointing|redeemer)\b/i,
  /\bpraise\s+(the\s+)?(lord|god|jesus)\b/i,
  /\bworship\b/i,
];

function isGlobalRegion(region: string): boolean {
  const value = region.trim().toUpperCase();
  return value === "" || value === "ALL" || value === SOUNDCHARTS_GLOBAL_REGION;
}

export function isRelevant(title: string, artist: string): boolean {
  return !IRRELEVANT_PATTERNS.some((p) => p.test(`${title} ${artist}`));
}

/**
 * Whole charts that can never feed the DJ/club use case (gospel editions,
 * radio-airplay recurrents). Filtering at chart level saves the ranking call
 * entirely instead of discarding rows one-by-one after fetching them.
 */
const EXCLUDED_CHART_PATTERN =
  /\b(christian|gospel|worship|on[ -]radio)\b/i;

/**
 * Rank a chart by how well it represents "what is actually big right now".
 * The Soundcharts chart list is alphabetical and paginated, so taking it in
 * list order used to select genre charts ("AfroBeats", "Country") while the
 * real "Top 200" charts sorted last and were never picked. Higher is better;
 * negative means never use this chart.
 */
export function chartPriority(chart: SoundchartsChart): number {
  const text = `${chart.name ?? ""} ${chart.slug}`.toLowerCase();
  if (EXCLUDED_CHART_PATTERN.test(text)) return -1;
  if (/\btop[ -]?200\b/.test(text)) return 100;
  if (/\btop[ -]?\d+\b/.test(text)) return 90;
  if (/\bdaily[ -]?\d+\b/.test(text)) return 85;
  if (/\bhot[ -]?\d+\b/.test(text)) return 80;
  if (/\btop\b/.test(text)) return 60;
  if (/\b(viral|trending)\b/.test(text)) return 50;
  if (chart.slug.startsWith("genre-")) return 5;
  return 10;
}

/**
 * Soundcharts ranking items carry no genre, so a chart-only track would land as
 * "Open Format" and get zeroed by the merge's genre↔region affinity gate —
 * excluding exactly the local Shazam/TikTok/Boomplay tracks we want from the
 * "Hot in <country>" views. Seed a region-appropriate default so they surface.
 *
 * Only the African markets get a default (their charts are overwhelmingly one
 * bucket); Western markets stay undefined to avoid mislabeling their mixed
 * charts. The default is self-correcting: any crossover hit that also appears on
 * Spotify/Deezer/Apple is rewritten with its real genre by the 30-min job, so
 * the default only persists for genuinely local tracks — where it's correct.
 */
export function defaultGenreForRegion(region: string): string | undefined {
  const map: Record<string, string> = {
    NG: "Afrobeats",
    GH: "Afrobeats",
    ZA: "Amapiano",
  };
  return map[region.toUpperCase()];
}

/**
 * Choose the best charts for a region: country-specific first (capped at max),
 * otherwise the global/worldwide charts (countryCode === "") as a fallback.
 * Within the pool, charts are ranked by [chartPriority] so the main "Top N"
 * chart wins over genre/radio editions regardless of list order.
 */
export function selectCharts(
  charts: SoundchartsChart[],
  region: string,
  max: number,
): SoundchartsChart[] {
  const pickBest = (pool: SoundchartsChart[]): SoundchartsChart[] =>
    pool
      .filter((c) => chartPriority(c) >= 0)
      .sort((a, b) => chartPriority(b) - chartPriority(a))
      .slice(0, Math.max(1, max));

  if (isGlobalRegion(region)) {
    return pickBest(charts.filter((c) => (c.countryCode ?? "") === ""));
  }
  const r = region.toUpperCase();
  const country = charts.filter(
    (c) => (c.countryCode ?? "").toUpperCase() === r,
  );
  const pool =
    country.length > 0
      ? country
      : charts.filter((c) => (c.countryCode ?? "") === "");
  return pickBest(pool);
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
    genre: defaultGenreForRegion(region),
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
  page?: { next?: string | null };
}>;

const MAX_CHARTS_PER_PLATFORM = 2;

/**
 * The chart list is alphabetical, so the main "Top N" charts sort near the
 * end (Shazam worldwide has 323 charts; "Top 200" is past index 90). Follow
 * pagination far enough to actually see them. Pages are cacheable upstream,
 * so the extra calls are a once-per-TTL cost, not a per-request cost.
 */
const MAX_CHART_LIST_PAGES = 4;

async function fetchChartList(
  get: SoundchartsHttp,
  platformCode: string,
  countryCode: string,
): Promise<SoundchartsChart[]> {
  const charts: SoundchartsChart[] = [];
  let path: string | null =
    `/api/v2/chart/song/by-platform/${encodeURIComponent(platformCode)}` +
    `?countryCode=${encodeURIComponent(countryCode)}&limit=100`;
  for (let page = 0; page < MAX_CHART_LIST_PAGES && path; page += 1) {
    const resp = await get(path);
    charts.push(...((resp.items as SoundchartsChart[]) ?? []));
    path = resp.page?.next ?? null;
  }
  return charts;
}

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
  const signalRegion = isGlobalRegion(region)
    ? SOUNDCHARTS_GLOBAL_REGION
    : region.trim().toUpperCase();
  const countryCode = signalRegion === SOUNDCHARTS_GLOBAL_REGION
    ? ""
    : signalRegion;

  for (const code of platforms) {
    try {
      const allCharts = await fetchChartList(get, code, countryCode);
      const charts = selectCharts(
        allCharts,
        signalRegion,
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
            signalRegion,
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

export function makeHttpGet(appId: string, apiKey: string): SoundchartsHttp {
  return async (path) => {
    const res = await fetch(`${SOUNDCHARTS_BASE_URL}${path}`, {
      headers: { "x-app-id": appId, "x-api-key": apiKey },
    });
    if (!res.ok) throw new Error(`Soundcharts ${res.status} for ${path}`);
    return res.json() as ReturnType<SoundchartsHttp>;
  };
}

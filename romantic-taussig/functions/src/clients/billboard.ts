import type { SourceTrackSignal } from "../types";

/**
 * Billboard chart URLs from the mhollingshead/billboard-hot-100 GitHub archive.
 * Updated daily. No auth needed.
 */
const CHART_URLS: Array<{ url: string; tag: string; region: string }> = [
  {
    url: "https://raw.githubusercontent.com/mhollingshead/billboard-hot-100/main/recent.json",
    tag: "billboard:hot-100",
    region: "US",
  },
];

/**
 * Additional Billboard charts via the same archive format from other repos.
 * These use the billboard.com scraping pattern.
 */
const SCRAPE_CHARTS: Array<{ chart: string; tag: string; region: string }> = [
  { chart: "hot-100", tag: "billboard:hot-100", region: "US" },
  { chart: "billboard-200", tag: "billboard:200", region: "US" },
  { chart: "artist-100", tag: "billboard:artist-100", region: "US" },
];

interface BillboardSong {
  song?: string;
  name?: string;
  artist?: string;
  this_week?: number;
  last_week?: number | null;
  peak_position?: number;
  weeks_on_chart?: number;
}

interface BillboardChart {
  date?: string;
  data?: BillboardSong[];
}

const IRRELEVANT_PATTERNS = [
  /\bbts\b/i, /\bjungkook\b/i, /\bblackpink\b/i, /\btwice\b/i,
  /\bstray\s*kids\b/i, /\bnewjeans\b/i, /\baespa\b/i,
  /\b(k-?pop|kpop|j-?pop|jpop|c-?pop|cpop|anime|bollywood)\b/i,
  /\b(country|folk|bluegrass|gospel|christian|classical|metal|punk)\b/i,
];

function isRelevant(title: string, artist: string): boolean {
  const combined = `${title} ${artist}`;
  return !IRRELEVANT_PATTERNS.some((p) => p.test(combined));
}

export async function fetchBillboardSignals(): Promise<SourceTrackSignal[]> {
  const signals: SourceTrackSignal[] = [];

  // Fetch from the JSON archive
  for (const source of CHART_URLS) {
    try {
      const response = await fetch(source.url, {
        headers: { Accept: "application/json" },
      });

      if (!response.ok) continue;

      const raw = await response.json();
      // The archive returns either a single chart object or an array
      const chart: BillboardChart = Array.isArray(raw) ? raw[raw.length - 1] : raw;
      const songs = chart.data ?? [];

      for (const song of songs) {
        const title = (song.song ?? song.name ?? "").trim();
        const artist = (song.artist ?? "").trim();
        if (!title || !artist) continue;
        if (!isRelevant(title, artist)) continue;

        const position = song.this_week ?? 100;
        const lastWeek = song.last_week ?? position;
        const peakPos = song.peak_position ?? position;
        const weeksOn = song.weeks_on_chart ?? 1;

        // Calculate engagement from chart position (1 = highest)
        const positionScore = Math.max(0, (101 - position) / 100);
        // Growth: improving position = higher score
        const growth = typeof lastWeek === "number"
          ? Math.max(0, Math.min(1, (lastWeek - position) / 50 + 0.5))
          : 0.5;
        // Recency: new entries and rising tracks score higher
        const recency = weeksOn <= 4 ? 0.9 : weeksOn <= 12 ? 0.7 : 0.5;

        signals.push({
          source: "billboard",
          sourceId: `bb-${position}-${title.toLowerCase().replace(/\W+/g, "-").slice(0, 30)}`,
          title,
          artist,
          artworkUrl: undefined,
          region: source.region,
          platformUrl: `https://www.billboard.com/charts/hot-100/`,
          keywords: [source.tag, `peak:${peakPos}`, `weeks:${weeksOn}`],
          engagement: positionScore,
          growthRate: growth,
          recency,
          releasedAt: chart.date,
        });
      }
    } catch {
      // Silently skip failed chart fetches
    }
  }

  return signals;
}

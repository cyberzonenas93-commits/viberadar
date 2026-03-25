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

  // Server-side blocklist — final safety net to prevent K-pop and other
  // non-DJ-relevant content from ever reaching Firestore.
  const filteredSignals = signals.filter(
    (s) => !isBlockedArtist(`${s.title} ${s.artist}`),
  );

  for (const signal of filteredSignals) {
    const key = `${canonicalize(signal.title)}::${canonicalize(signal.artist)}`;
    const current = merged.get(key) ?? {
      title: signal.title,
      artist: signal.artist,
      artworkUrl: signal.artworkUrl ?? "",
      bpm: signal.bpm ?? null,
      key: signal.key ?? "--",
      genre: normalizeGenre(signal.genre ?? inferGenreFromKeywords(signal.keywords)),
      keywords: [...signal.keywords],
      platformLinks: {},
      signals: [],
      regionScores: {},
    };

    current.artworkUrl = current.artworkUrl || signal.artworkUrl || "";
    current.bpm = current.bpm ?? signal.bpm ?? null;
    current.key = current.key === "--" ? (signal.key ?? "--") : current.key;
    current.genre =
      current.genre || normalizeGenre(signal.genre || inferGenreFromKeywords(signal.keywords));
    current.keywords = Array.from(
      new Set([...current.keywords, ...signal.keywords]),
    );
    current.platformLinks[signal.source] = signal.platformUrl;
    current.signals.push(signal);
    // Store raw region scores — genre affinity is applied AFTER all signals
    // are merged, so we have the final genre for each track.
    if (signal.region && signal.region !== "GLOBAL") {
      const rawScore = (signal.engagement + signal.growthRate + signal.recency) / 3;
      current.regionScores[signal.region] = Math.max(
        current.regionScores[signal.region] ?? 0,
        rawScore,
      );
    }

    merged.set(key, current);
  }

  // Apply genre-region affinity NOW that we know each track's final genre.
  // This prevents Pop/Country/Classical from getting high scores in GH/NG/ZA.
  for (const entry of merged.values()) {
    const finalGenre = entry.genre || "Open Format";
    const adjusted: Record<string, number> = {};
    for (const [region, rawScore] of Object.entries(entry.regionScores)) {
      const affinity = genreRegionAffinity(finalGenre, region);
      const score = rawScore * affinity;
      // Debug: log unexpected high scores for non-matching genres
      if (region === "GH" && score > 0.15 && !finalGenre.toLowerCase().includes("afrobeats") && !finalGenre.toLowerCase().includes("dancehall")) {
        console.log(`[REGION DEBUG] GH: "${entry.title}" by ${entry.artist} | genre=${finalGenre} | raw=${rawScore.toFixed(3)} * affinity=${affinity} = ${score.toFixed(3)}`);
      }
      if (score > 0.15) {
        adjusted[region] = score;
      }
    }
    entry.regionScores = adjusted;
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
      bpm: entry.bpm ?? estimateBpmFromGenre(
        (entry.genre && entry.genre !== "Open Format"
          ? entry.genre
          : previous?.genre) || "Open Format",
      ),
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

function normalizeGenre(raw: string): string {
  const lower = raw.toLowerCase().trim();
  const map: Record<string, string> = {
    "afrobeats": "Afrobeats",
    "afrobeat": "Afrobeats",
    "afro-beat": "Afrobeats",
    "afro-pop": "Afrobeats",
    "afro-fusion": "Afrobeats",
    "afro-swing": "Afrobeats",
    "african": "Afrobeats",
    "amapiano": "Amapiano",
    "house": "House",
    "deep house": "House",
    "tech house": "House",
    "afro house": "House",
    "progressive house": "House",
    "future house": "House",
    "electro house": "House",
    "uk garage": "UK Garage",
    "garage": "UK Garage",
    "hip-hop": "Hip-Hop",
    "hip-hop/rap": "Hip-Hop",
    "rap": "Hip-Hop",
    "trap": "Hip-Hop",
    "r&b": "R&B",
    "r&b/soul": "R&B",
    "rnb": "R&B",
    "soul": "R&B",
    "drill": "Drill",
    "uk drill": "Drill",
    "grime": "Drill",
    "latin": "Latin",
    "reggaeton": "Latin",
    "dancehall": "Dancehall",
    "ragga": "Dancehall",
    "dance": "Dance",
    "edm": "Dance",
    "electronic": "Dance",
    "electro": "Dance",
    "pop": "Pop",
    "dance pop": "Pop",
    "k-pop": "Pop",
    "indie rock": "Pop",
    "rock": "Pop",
    "alternative": "Pop",
    "country": "Pop",
    "soca": "Soca",
    "calypso": "Soca",
    "gqom": "Gqom",
    "baile funk": "Baile Funk",
    "funk carioca": "Baile Funk",
    "brazilian bass": "Baile Funk",
    "dubstep": "Dance",
    "drum & bass": "Dance",
    "drum and bass": "Dance",
    "trance": "Dance",
    "future bass": "Dance",
    "techno": "Dance",
    "maskandi": "Afrobeats",
    "worldwide": "Open Format",
  };
  return map[lower] ?? raw;
}

function inferGenreFromKeywords(keywords: string[]): string {
  const text = ` ${keywords.join(" ").toLowerCase()} `;
  if (/\b(afrobeats?|afro[-\s]?pop|afro[-\s]?swing|afro[-\s]?fusion)\b/.test(text)) {
    return "Afrobeats";
  }
  if (/\bamapiano\b/.test(text)) {
    return "Amapiano";
  }
  if (/\b(deep\s?house|tech\s?house|house\s?music|afro[-\s]?house)\b/.test(text) || /\bhouse\b/.test(text)) {
    return "House";
  }
  if (/\b(uk\s?garage|garage)\b/.test(text)) {
    return "UK Garage";
  }
  if (/\b(dancehall|ragga)\b/.test(text)) {
    return "Dancehall";
  }
  if (/\b(edm|dance\s?(music|pop)|electronic|club\s?bangers?)\b/.test(text)) {
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
  if (/\b(soca|calypso)\b/.test(text)) {
    return "Soca";
  }
  if (/\bgqom\b/.test(text)) {
    return "Gqom";
  }
  if (/\b(baile\s?funk|funk\s?carioca|brazilian\s?bass)\b/.test(text)) {
    return "Baile Funk";
  }
  return "Open Format";
}

function estimateBpmFromGenre(genre: string): number {
  // Typical BPM ranges for DJ genres, returns midpoint with slight randomization
  const bpmMap: Record<string, [number, number]> = {
    "Afrobeats": [95, 115],
    "Amapiano": [110, 120],
    "House": [120, 130],
    "Dance": [120, 135],
    "Dancehall": [90, 110],
    "Hip-Hop": [80, 100],
    "R&B": [70, 95],
    "Latin": [90, 110],
    "Drill": [138, 148],
    "UK Garage": [130, 140],
    "Soca": [130, 145],
    "Gqom": [115, 125],
    "Baile Funk": [130, 150],
    "Pop": [100, 130],
    "Open Format": [110, 130],
  };
  const range = bpmMap[genre] ?? [110, 130];
  // Deterministic-ish spread within the range
  return Math.round(range[0] + Math.random() * (range[1] - range[0]));
}

function average(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

/**
 * Returns a 0-1 multiplier for how well a genre fits a region's music scene.
 * 1.0 = perfect fit, 0.1 = barely relevant, used to prevent Tame Impala
 * from showing as "Hot in Ghana" just because Spotify returned it for market=GH.
 */
function genreRegionAffinity(genre: string, region: string): number {
  const g = (genre || "").toLowerCase();
  const r = region.toUpperCase();

  const map: Record<string, Record<string, number>> = {
    "GH": {
      "afrobeats": 1.0, "dancehall": 0.4, "amapiano": 0.3,
    },
    "NG": {
      "afrobeats": 1.0, "dancehall": 0.3, "hip-hop": 0.05, "r&b": 0.05,
    },
    "ZA": {
      "amapiano": 1.0, "gqom": 0.9, "house": 0.15, "afrobeats": 0.1,
    },
    "GB": {
      "drill": 0.9, "uk garage": 0.9, "house": 0.6, "dance": 0.5,
      "hip-hop": 0.5, "afrobeats": 0.4, "r&b": 0.4, "pop": 0.2,
      "open format": 0.05,
    },
    "US": {
      "hip-hop": 0.8, "r&b": 0.8, "latin": 0.6, "house": 0.4,
      "dance": 0.4, "pop": 0.3, "afrobeats": 0.2,
      "open format": 0.05,
    },
    "DE": {
      "house": 0.8, "dance": 0.7, "hip-hop": 0.3, "pop": 0.2,
      "afrobeats": 0.1, "open format": 0.05,
    },
  };

  const regionMap = map[r];
  if (!regionMap) return 0.3; // Unknown region, moderate penalty

  // Check for partial genre match
  for (const [genreKey, score] of Object.entries(regionMap)) {
    if (g.includes(genreKey) || genreKey.includes(g)) return score;
  }

  // Genre doesn't match this region — near-zero score (v2)
  return 0.02;
}

const BLOCKED_PATTERNS = [
  /\bbts\b/i, /\bjungkook\b/i, /\bblackpink\b/i, /\btwice\b/i,
  /\bstray\s*kids\b/i, /\bnewjeans\b/i, /\baespa\b/i, /\benhypen\b/i,
  /\btxt\b/i, /\bsevente+n\b/i, /\bnct\b/i, /\bzerobaseone\b/i,
  /\bhybe\s*labels\b/i, /\bitzy\b/i, /\bive\b/i, /\ble\s*sserafim\b/i,
  /\b(k-?pop|kpop|j-?pop|jpop|c-?pop|cpop|anime|bollywood)\b/i,
  /\btaylor\s*swift\b/i, /\bed\s*sheeran\b/i, /\bcoldplay\b/i,
  /\bimagine\s*dragons\b/i, /\bone\s*direction\b/i,
  /\b(country|folk|bluegrass|gospel|christian|classical|metal|punk|emo)\b/i,
];

function isBlockedArtist(text: string): boolean {
  return BLOCKED_PATTERNS.some((pattern) => pattern.test(text));
}

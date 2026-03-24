import type { UnifiedTrackRecord } from "../types";

const MUSICBRAINZ_BASE_URL = "https://musicbrainz.org/ws/2";
const MUSICBRAINZ_USER_AGENT = "VibeRadar/1.0 ( support@viberadar.app )";
const MUSICBRAINZ_MATCH_LIMIT = 12;
const MUSICBRAINZ_DELAY_MS = 1100;

interface MusicBrainzSearchPayload {
  recordings?: Array<{
    id: string;
    title?: string;
    score?: string | number;
    disambiguation?: string;
    tags?: Array<{ name?: string; count?: number }>;
    "artist-credit"?: Array<{
      name?: string;
      artist?: { name?: string };
    }>;
  }>;
}

export async function enrichTracksWithMusicBrainz(
  tracks: UnifiedTrackRecord[],
): Promise<void> {
  const pending = tracks
    .filter((track) => !track.platform_links.musicbrainz)
    .sort((left, right) => right.trend_score - left.trend_score)
    .slice(0, MUSICBRAINZ_MATCH_LIMIT);

  for (const [index, track] of pending.entries()) {
    if (index > 0) {
      await sleep(MUSICBRAINZ_DELAY_MS);
    }

    const match = await findBestRecordingMatch(track.title, track.artist);
    if (!match) {
      continue;
    }

    track.platform_links = {
      ...track.platform_links,
      musicbrainz: `https://musicbrainz.org/recording/${match.id}`,
    };

    if (track.genre === "Open Format" && match.genre) {
      track.genre = match.genre;
    }
  }
}

async function findBestRecordingMatch(title: string, artist: string) {
  const candidates = buildLookupCandidates(title, artist);

  for (const [index, candidate] of candidates.entries()) {
    if (index > 0) {
      await sleep(250);
    }

    const query = `recording:${escapeQuery(candidate.title)} AND artist:${escapeQuery(
      candidate.artist,
    )}`;
    const url =
      `${MUSICBRAINZ_BASE_URL}/recording?query=${encodeURIComponent(query)}` +
      "&fmt=json&limit=5";
    const response = await fetch(url, {
      headers: {
        Accept: "application/json",
        "User-Agent": MUSICBRAINZ_USER_AGENT,
      },
    });

    if (!response.ok) {
      throw new Error(`MusicBrainz API failed: ${response.status}`);
    }

    const payload = (await response.json()) as MusicBrainzSearchPayload;
    const matches = payload.recordings ?? [];

    for (const match of matches) {
      if (!isCompatibleMatch(match, candidate.title, candidate.artist)) {
        continue;
      }

      return {
        id: match.id,
        genre: inferGenreFromTags(match.tags),
      };
    }
  }

  return undefined;
}

function buildLookupCandidates(
  title: string,
  artist: string,
): Array<{ title: string; artist: string }> {
  const cleanedArtist = cleanArtistForLookup(artist);
  const primaryArtist = extractPrimaryArtist(cleanedArtist);
  const cleanedTitles = new Set(
    [
      title,
      cleanTitleForLookup(title, cleanedArtist),
      cleanTitleForLookup(title, primaryArtist),
    ].filter(Boolean),
  );
  const artists = Array.from(
    new Set([cleanedArtist, primaryArtist].filter(Boolean)),
  );

  const candidates: Array<{ title: string; artist: string }> = [];
  for (const candidateTitle of cleanedTitles) {
    for (const candidateArtist of artists) {
      candidates.push({
        title: candidateTitle,
        artist: candidateArtist,
      });
    }
  }

  return candidates;
}

function isCompatibleMatch(
  match: NonNullable<MusicBrainzSearchPayload["recordings"]>[number],
  title: string,
  artist: string,
): boolean {
  const matchArtist = canonicalize(
    match["artist-credit"]
      ?.map((credit) => credit.artist?.name ?? credit.name ?? "")
      .join(" ") ?? "",
  );
  const matchTitle = canonicalize(match.title ?? "");
  const expectedTitle = canonicalize(title);
  const expectedArtist = canonicalize(artist);
  const score = Number(match.score ?? 0);
  const titleCompatible =
    matchTitle === expectedTitle ||
    matchTitle.includes(expectedTitle) ||
    expectedTitle.includes(matchTitle);
  const artistCompatible =
    matchArtist === expectedArtist ||
    matchArtist.includes(expectedArtist) ||
    expectedArtist.includes(matchArtist);

  return titleCompatible && artistCompatible && score >= 80;
}

function inferGenreFromTags(
  tags?: Array<{ name?: string; count?: number }>,
): string | undefined {
  const topTag = [...(tags ?? [])]
    .filter((tag) => tag.name)
    .sort((left, right) => (right.count ?? 0) - (left.count ?? 0))[0];

  return topTag?.name
    ?.split(/\s+/)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function escapeQuery(value: string): string {
  return `"${value.replace(/["\\]/g, "").trim()}"`;
}

function cleanTitleForLookup(title: string, artist: string): string {
  let cleaned = title
    .replace(/[“”]/g, '"')
    .replace(/[‘’]/g, "'")
    .replace(/\(official.*?\)|\[official.*?]/gi, "")
    .replace(/\b(official\s+)?(music\s+)?video\b/gi, "")
    .replace(/\b(audio|lyric video|visualizer|performance video)\b/gi, "")
    .replace(/\bfeat(?:uring)?\.?\s+.+$/i, "")
    .replace(/\bft\.?\s+.+$/i, "")
    .trim();

  if (artist) {
    const artistPrefix = new RegExp(
      `^${escapeRegExp(artist)}\\s*[-:|]\\s*`,
      "i",
    );
    cleaned = cleaned.replace(artistPrefix, "");
  }

  const colonParts = cleaned
    .split(/\s*:\s*/)
    .map((part) => part.trim())
    .filter(Boolean);
  if (colonParts.length >= 2) {
    cleaned = colonParts[colonParts.length - 1] ?? cleaned;
  }

  return cleaned
    .replace(/^["']|["']$/g, "")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function cleanArtistForLookup(artist: string): string {
  return artist
    .replace(/\s*-\s*topic$/i, "")
    .replace(/\s*vevo$/i, "")
    .trim();
}

function extractPrimaryArtist(artist: string): string {
  return artist.split(/\s*(?:,|&| x | feat\.?|ft\.?)\s*/i)[0]?.trim() ?? artist;
}

function canonicalize(value: string): string {
  return value
    .toLowerCase()
    .replace(/\(.*?\)|\[.*?]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

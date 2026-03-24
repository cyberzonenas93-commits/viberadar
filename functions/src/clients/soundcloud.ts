import type { SourceTrackSignal } from "../types";

const SEARCH_TERMS = ["afro house", "amapiano", "club edit", "dance remix"];

export async function fetchSoundCloudSignals(input: {
  clientId?: string;
  oauthToken?: string;
  region: string;
}): Promise<SourceTrackSignal[]> {
  const { clientId, oauthToken, region } = input;
  if (!clientId && !oauthToken) {
    return [];
  }

  const headers: Record<string, string> = {};
  if (oauthToken) {
    headers.Authorization = `OAuth ${oauthToken}`;
  }
  const clientQuery = clientId
    ? `&client_id=${encodeURIComponent(clientId)}`
    : "";
  const aggregate: SourceTrackSignal[] = [];

  await Promise.all(
    SEARCH_TERMS.map(async (term) => {
      const response = await fetch(
        `https://api.soundcloud.com/tracks?q=${encodeURIComponent(
          term
        )}&limit=12&linked_partitioning=1${clientQuery}`,
        {
          headers,
        }
      );

      if (!response.ok) {
        return;
      }

      const payload = (await response.json()) as {
        collection?: Array<{
          id: number;
          title?: string;
          permalink_url?: string;
          genre?: string;
          artwork_url?: string;
          user?: { username?: string };
          likes_count?: number;
          playback_count?: number;
          comment_count?: number;
          created_at?: string;
          tag_list?: string;
          bpm?: number;
        }>;
      };

      for (const track of payload.collection ?? []) {
        const likes = track.likes_count ?? 0;
        const plays = track.playback_count ?? 0;
        const comments = track.comment_count ?? 0;
        aggregate.push({
          source: "soundcloud",
          sourceId: String(track.id),
          title: sanitizeTitle(track.title ?? "Untitled"),
          artist: track.user?.username ?? "Unknown",
          artworkUrl: track.artwork_url ?? undefined,
          genre: track.genre ?? undefined,
          bpm: track.bpm ?? undefined,
          region,
          platformUrl: track.permalink_url ?? "https://soundcloud.com",
          keywords: [
            term,
            ...(track.tag_list?.split(" ").filter(Boolean).slice(0, 8) ?? []),
          ],
          engagement: cappedNormalize(
            plays + likes * 10 + comments * 15,
            1_500_000
          ),
          growthRate: cappedNormalize(likes + comments * 8, 90_000),
          recency: recencyScore(track.created_at),
          releasedAt: track.created_at,
        });
      }
    })
  );

  return aggregate;
}

function sanitizeTitle(title: string): string {
  return title.replace(/\(preview\)|\[preview]/gi, "").trim();
}

function cappedNormalize(value: number, max: number): number {
  return Number(Math.min(value / max, 1).toFixed(4));
}

function recencyScore(date?: string): number {
  if (!date) {
    return 0.35;
  }
  const createdAt = new Date(date);
  const ageInDays = Math.max(
    1,
    (Date.now() - createdAt.getTime()) / (1000 * 60 * 60 * 24)
  );
  return Number(Math.max(0.1, 1 - ageInDays / 180).toFixed(4));
}

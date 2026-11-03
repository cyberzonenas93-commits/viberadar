import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

import { fetchAppleMusicSignals } from "./clients/appleMusic";
import { fetchBillboardSignals } from "./clients/billboard";
import { fetchAudiomackSignals } from "./clients/audiomack";
import { fetchAudiusSignals } from "./clients/audius";
import { fetchDeezerSignals } from "./clients/deezer";
import { fetchBeatportSignals } from "./clients/beatport";
import { enrichTracksWithMusicBrainz } from "./clients/musicbrainz";
import { fetchSoundCloudSignals } from "./clients/soundcloud";
import { fetchSpotifySignals } from "./clients/spotify";
import { fetchYouTubeSignals } from "./clients/youtube";
import {
  APPLE_MUSIC_DEVELOPER_TOKEN,
  AUDIOMACK_CONSUMER_KEY,
  AUDIOMACK_CONSUMER_SECRET,
  BEATPORT_API_TOKEN,
  getBeatportApiBaseUrl,
  getConfiguredRegions,
  normalizeSecretValue,
  SOUNDCLOUD_CLIENT_ID,
  SOUNDCLOUD_OAUTH_TOKEN,
  SPOTIFY_CLIENT_ID,
  SPOTIFY_CLIENT_SECRET,
  YOUTUBE_API_KEY,
} from "./lib/config";
import { mergeSignalsIntoTracks } from "./lib/normalize";
import type {
  IngestionSummary,
  SourceTrackSignal,
  UnifiedTrackRecord,
} from "./types";

admin.initializeApp();
const firestore = admin.firestore();

const functionSecrets = [
  SPOTIFY_CLIENT_ID,
  SPOTIFY_CLIENT_SECRET,
  YOUTUBE_API_KEY,
  APPLE_MUSIC_DEVELOPER_TOKEN,
  SOUNDCLOUD_CLIENT_ID,
  SOUNDCLOUD_OAUTH_TOKEN,
  BEATPORT_API_TOKEN,
  AUDIOMACK_CONSUMER_KEY,
  AUDIOMACK_CONSUMER_SECRET,
];

export const ingestTrackSignals = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "Etc/UTC",
    region: "us-central1",
    secrets: functionSecrets,
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const summary = await runIngestion();
    logger.info("VibeRadar ingestion complete", summary);
  },
);

export const manualIngestTrackSignals = onRequest(
  {
    region: "us-central1",
    secrets: functionSecrets,
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (request, response) => {
    const authHeader = request.headers.authorization ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      response.status(401).json({ error: "Missing Bearer token" });
      return;
    }

    const idToken = authHeader.slice(7);
    try {
      await admin.auth().verifyIdToken(idToken);
    } catch {
      response.status(403).json({ error: "Invalid or expired token" });
      return;
    }

    const summary = await runIngestion();
    response.json(summary);
  },
);

async function withRetry<T>(
  fn: () => Promise<T>,
  retries = 2,
  delayMs = 1500,
): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (attempt >= retries) throw error;
      logger.warn(`Retry ${attempt + 1}/${retries}`, error);
      await new Promise((resolve) => setTimeout(resolve, delayMs * (attempt + 1)));
    }
  }
}

async function runIngestion(): Promise<IngestionSummary> {
  const regions = getConfiguredRegions();
  const collectedSignals: SourceTrackSignal[] = [];
  const globalSettled = await Promise.allSettled([
    withRetry(() => fetchAudiusSignals()),
    withRetry(() =>
      fetchAudiomackSignals({
        consumerKey: normalizeSecretValue(AUDIOMACK_CONSUMER_KEY.value()),
        consumerSecret: normalizeSecretValue(AUDIOMACK_CONSUMER_SECRET.value()),
      }),
    ),
  ]);

  for (const result of globalSettled) {
    if (result.status === "fulfilled") {
      collectedSignals.push(...result.value);
    } else {
      logger.warn("Global source fetch failed", result.reason);
    }
  }

  for (let ri = 0; ri < regions.length; ri++) {
    const region = regions[ri];
    // Small delay between regions to avoid Spotify rate limits
    if (ri > 0) {
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
    const sourceNames = ["spotify", "youtube", "apple", "soundcloud", "beatport", "deezer"];
    const settled = await Promise.allSettled([
      withRetry(() =>
        fetchSpotifySignals({
          clientId: normalizeSecretValue(SPOTIFY_CLIENT_ID.value()),
          clientSecret: normalizeSecretValue(SPOTIFY_CLIENT_SECRET.value()),
          region,
        }),
      ),
      withRetry(() =>
        fetchYouTubeSignals({
          apiKey: normalizeSecretValue(YOUTUBE_API_KEY.value()),
          region,
        }),
      ),
      withRetry(() =>
        fetchAppleMusicSignals({
          developerToken: normalizeSecretValue(
            APPLE_MUSIC_DEVELOPER_TOKEN.value(),
          ),
          region,
        }),
      ),
      withRetry(() =>
        fetchSoundCloudSignals({
          clientId: normalizeSecretValue(SOUNDCLOUD_CLIENT_ID.value()),
          oauthToken: normalizeSecretValue(SOUNDCLOUD_OAUTH_TOKEN.value()),
          region,
        }),
      ),
      withRetry(() =>
        fetchBeatportSignals({
          apiToken: normalizeSecretValue(BEATPORT_API_TOKEN.value()),
          apiBaseUrl: getBeatportApiBaseUrl(),
          region,
        }),
      ),
      withRetry(() =>
        fetchDeezerSignals({ region }),
      ),
    ]);

    const regionCounts: Record<string, number> = {};
    for (let i = 0; i < settled.length; i++) {
      const result = settled[i];
      const name = sourceNames[i] ?? `source-${i}`;
      if (result.status === "fulfilled") {
        regionCounts[name] = result.value.length;
        collectedSignals.push(...result.value);
      } else {
        regionCounts[name] = -1;
        logger.warn(`Source fetch failed for ${region}/${name}`, result.reason);
      }
    }
    logger.info(`Region ${region} signals`, regionCounts);
  }

  // Billboard charts (US-only, outside region loop)
  try {
    const billboardSignals = await fetchBillboardSignals();
    collectedSignals.push(...billboardSignals);
    // billboard added to signals
    logger.info(`Billboard: ${billboardSignals.length} signals`);
  } catch (err) {
    logger.warn("Billboard fetch failed", err);
  }

  const existingSnapshots = await loadExistingTrackState();
  const unifiedTracks = mergeSignalsIntoTracks(
    collectedSignals,
    existingSnapshots,
  );
  try {
    await enrichTracksWithMusicBrainz(unifiedTracks);
  } catch (error) {
    logger.warn("MusicBrainz enrichment failed", error);
  }
  await writeTracks(unifiedTracks);

  return {
    fetchedSignals: collectedSignals.length,
    writtenTracks: unifiedTracks.length,
    regions,
    sources: [
      "spotify",
      "youtube",
      "apple",
      "audius",
      "audiomack",
      "soundcloud",
      "beatport",
      "deezer",
    ],
  };
}

async function loadExistingTrackState(): Promise<
  Record<
    string,
    {
      created_at?: string;
      genre?: string;
      platform_links?: Record<string, string>;
      trend_history?: Array<{ label: string; score: number }>;
    }
  >
> {
  const snapshot = await firestore
    .collection("tracks")
    .select("created_at", "genre", "platform_links", "trend_history")
    .get();
  return Object.fromEntries(
    snapshot.docs.map((doc) => [
      doc.id,
      {
        created_at: doc.get("created_at"),
        genre: doc.get("genre"),
        platform_links: doc.get("platform_links"),
        trend_history: doc.get("trend_history"),
      },
    ]),
  );
}

async function writeTracks(tracks: UnifiedTrackRecord[]): Promise<void> {
  // Firestore batch limit is 500 operations
  for (let i = 0; i < tracks.length; i += 499) {
    const chunk = tracks.slice(i, i + 499);
    const batch = firestore.batch();
    for (const track of chunk) {
      batch.set(firestore.collection("tracks").doc(track.id), track, {
        merge: true,
      });
    }
    await batch.commit();
  }
}

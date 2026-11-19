import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

export { createPairing, claimPairing, revokePairing } from "./pairing";
export {
  spotifyProxy,
  spotifyOnboardingArtistImages,
  appleProxy,
  soundchartsProxy,
  youtubeProxy,
} from "./proxy";
export { openaiProxy } from "./openai";
export { syncAppStorePurchase, appStoreServerNotification } from "./iap";
export { deleteMyAccount, onUserDeleted } from "./accountCleanup";
export { decayTrendingScores } from "./decayTrending";
export { ingestSoundchartsDaily } from "./soundchartsIngest";
export { notifyOnSharedSetlist } from "./messaging";
export {
  onUploadCreated,
  onUploadDeleted,
  onFollowCreated,
  onFollowDeleted,
  toggleUploadLike,
} from "./socialCounters";

import { fetchAppleMusicSignals } from "./clients/appleMusic";
import { fetchBillboardSignals } from "./clients/billboard";
import { fetchAudiomackSignals } from "./clients/audiomack";
import { fetchAudiusSignals } from "./clients/audius";
import { fetchDeezerSignals } from "./clients/deezer";
import { enrichTracksWithMusicBrainz } from "./clients/musicbrainz";
import { fetchSpotifySignals } from "./clients/spotify";
import { fetchYouTubeSignals } from "./clients/youtube";
import {
  APPLE_MUSIC_DEVELOPER_TOKEN,
  APPLE_MUSIC_KEY_ID,
  APPLE_MUSIC_PRIVATE_KEY,
  APPLE_MUSIC_TEAM_ID,
  AUDIOMACK_CONSUMER_KEY,
  AUDIOMACK_CONSUMER_SECRET,
  BEATPORT_API_TOKEN,
  getConfiguredRegions,
  normalizeSecretValue,
  SOUNDCLOUD_CLIENT_ID,
  SOUNDCLOUD_OAUTH_TOKEN,
  SPOTIFY_CLIENT_ID,
  SPOTIFY_CLIENT_SECRET,
  YOUTUBE_API_KEY,
} from "./lib/config";
import { getAppleMusicDeveloperToken } from "./lib/appleMusicToken";
import { requireProUsageLimitsForUser } from "./lib/entitlements";
import { mergeSignalsIntoTracks } from "./lib/normalize";
import { loadExistingTrackState, writeTracks } from "./lib/trackStore";
import { enforceUsageLimit } from "./lib/usage";
import { verifyHttpAppCheckIfRequired } from "./lib/appCheck";
import { isAnonymousDecodedToken } from "./lib/auth";
import type { IngestionSummary, SourceTrackSignal } from "./types";

admin.initializeApp();
const firestore = admin.firestore();

const functionSecrets = [
  SPOTIFY_CLIENT_ID,
  SPOTIFY_CLIENT_SECRET,
  YOUTUBE_API_KEY,
  APPLE_MUSIC_DEVELOPER_TOKEN,
  APPLE_MUSIC_PRIVATE_KEY,
  APPLE_MUSIC_KEY_ID,
  APPLE_MUSIC_TEAM_ID,
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
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    response.set(
      "Access-Control-Allow-Headers",
      "Authorization, Content-Type, X-Firebase-AppCheck",
    );

    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }

    try {
      await verifyHttpAppCheckIfRequired(request);
    } catch (error) {
      const code = (error as { code?: string }).code;
      response.status(code === "permission-denied" ? 403 : 401).json({
        error:
          code === "permission-denied"
            ? "Invalid App Check token"
            : "App Check token required",
      });
      return;
    }

    const authHeader = request.headers.authorization ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      response.status(401).json({ error: "Missing Bearer token" });
      return;
    }

    const idToken = authHeader.slice(7);
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      if (isAnonymousDecodedToken(decoded)) {
        response.status(403).json({
          error: "A full account is required to refresh trends manually.",
        });
        return;
      }
      uid = decoded.uid;
    } catch {
      response.status(403).json({ error: "Invalid or expired token" });
      return;
    }

    try {
      const { limits } = await requireProUsageLimitsForUser(
        uid,
        "VibeRadar Pro is required to refresh live trends manually.",
      );
      await enforceUsageLimit({
        uid,
        key: "manual_ingest",
        limit: limits.manualIngestDailyLimit,
        window: "daily",
      });
    } catch (error) {
      const code = (error as { code?: unknown }).code;
      if (code === "failed-precondition") {
        response.status(402).json({
          error: "VibeRadar Pro is required to refresh live trends manually.",
        });
        return;
      }
      if (code === "resource-exhausted") {
        response.status(429).json({
          error:
            "Manual refresh limit reached. Try again after the daily reset.",
        });
        return;
      }
      throw error;
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
      await new Promise((resolve) =>
        setTimeout(resolve, delayMs * (attempt + 1)),
      );
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
    // Soundcharts (shazam/tiktok/boomplay) is intentionally NOT fetched here —
    // it runs in the once-a-day `ingestSoundchartsDaily` job, the only function
    // bound to the Soundcharts secrets, so this 30-min job can't burn the free
    // ~1,000-call budget.
    const sourceNames = ["spotify", "youtube", "apple", "deezer"];
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
          developerToken: getAppleMusicDeveloperToken(),
          region,
        }),
      ),
      withRetry(() => fetchDeezerSignals({ region })),
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

  const existingSnapshots = await loadExistingTrackState(firestore);
  const unifiedTracks = mergeSignalsIntoTracks(
    collectedSignals,
    existingSnapshots,
  );
  try {
    await enrichTracksWithMusicBrainz(unifiedTracks);
  } catch (error) {
    logger.warn("MusicBrainz enrichment failed", error);
  }
  await writeTracks(firestore, unifiedTracks);

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
      "deezer",
      "billboard",
    ],
  };
}

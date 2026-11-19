import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

import { fetchSoundchartsSignals, makeHttpGet } from "./clients/soundcharts";
import {
  firestoreSoundchartsCacheStore,
  withSoundchartsCache,
} from "./lib/soundchartsCache";
import {
  getConfiguredRegions,
  getSoundchartsCreds,
  getSoundchartsPlatforms,
  SOUNDCHARTS_API_KEY,
  SOUNDCHARTS_APP_ID,
} from "./lib/config";
import { mergeSignalsIntoTracks } from "./lib/normalize";
import { loadExistingTrackState, writeTracks } from "./lib/trackStore";
import type { SourceTrackSignal } from "./types";

/**
 * ingestSoundchartsDaily — Shazam / TikTok / Boomplay trends via Soundcharts.
 *
 * Runs ONCE A DAY and is the ONLY function bound to the Soundcharts secrets.
 * This is deliberate budget protection: the free Soundcharts tier is ~1,000
 * calls total, and the 30-min `ingestTrackSignals` job would exhaust it in
 * hours. At 3 platforms × the configured regions × ≤2 charts each (~9 calls per
 * region) a daily run is well within budget for weeks, leaving runway to decide
 * on a paid plan. The discovery → ranking → map → filter client is shared, so
 * moving to a richer cadence later is a config change, not a rebuild.
 *
 * Output flows through the same `mergeSignalsIntoTracks` → `writeTracks` path as
 * the main job (merge:true), so platform_links accumulate and the hourly
 * `decayTrendingScores` sweep ages these tracks out once they leave the charts.
 */
export const ingestSoundchartsDaily = onSchedule(
  {
    schedule: "15 6 * * *",
    timeZone: "Etc/UTC",
    region: "us-central1",
    secrets: [SOUNDCHARTS_APP_ID, SOUNDCHARTS_API_KEY],
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const creds = getSoundchartsCreds();
    if (!creds) {
      logger.warn("ingestSoundchartsDaily: Soundcharts creds unset — skipping");
      return;
    }

    const platforms = getSoundchartsPlatforms();
    const regions = getConfiguredRegions();
    const collected: SourceTrackSignal[] = [];
    const perRegion: Record<string, number> = {};
    const httpGet = withSoundchartsCache(
      makeHttpGet(creds.appId, creds.apiKey),
      firestoreSoundchartsCacheStore(),
    );

    for (const region of regions) {
      try {
        const signals = await fetchSoundchartsSignals({
          region,
          platforms,
          appId: creds.appId,
          apiKey: creds.apiKey,
          httpGet,
        });
        collected.push(...signals);
        perRegion[region] = signals.length;
      } catch (err) {
        perRegion[region] = -1;
        logger.warn(`Soundcharts fetch failed for ${region}`, err);
      }
    }

    const firestore = admin.firestore();
    const existing = await loadExistingTrackState(firestore);
    const tracks = mergeSignalsIntoTracks(collected, existing);
    await writeTracks(firestore, tracks);

    logger.info("ingestSoundchartsDaily complete", {
      fetchedSignals: collected.length,
      writtenTracks: tracks.length,
      platforms,
      perRegion,
    });
  },
);

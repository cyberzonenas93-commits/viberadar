import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { planTrackDecay } from "./lib/recency";

const REGION = "us-central1";

/**
 * Upper bound on docs rescored per run. The steady-state working set (tracks
 * still scoring > 0) is well under this; the cap only matters while clearing
 * the initial backlog of never-decayed tracks, and keeps us clear of the
 * function timeout. Highest-scored docs are processed first because those are
 * the ones pinning the top of the feed.
 */
const MAX_PER_RUN = 4000;
const BATCH_LIMIT = 450;

/**
 * decayTrendingScores — recency-aware rescoring sweep.
 *
 * `ingestTrackSignals` only rewrites tracks present in the current batch, so a
 * song that charted once keeps its high `trend_score` forever and pins the top
 * of every "top songs" surface. This scheduled sweep decays each track's score
 * by how long ago it was last seen and retires it (score 0, region_scores
 * cleared) once it has been off the charts past the retire window. A track that
 * re-charts is rewritten fresh by ingestion and re-enters the feed.
 *
 * Runs hourly (offset 15 min from ingestion so the two don't race on the same
 * docs). Hourly + the per-doc write epsilon keeps Firestore write volume low.
 */
export const decayTrendingScores = onSchedule(
  {
    schedule: "15 * * * *",
    timeZone: "Etc/UTC",
    region: REGION,
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();
    const now = Date.now();

    // Retired tracks (trend_score == 0) fall out of this query and are never
    // touched again until ingestion rewrites them on a re-chart.
    const snap = await db
      .collection("tracks")
      .where("trend_score", ">", 0)
      .orderBy("trend_score", "desc")
      .limit(MAX_PER_RUN)
      .get();

    let decayed = 0;
    let retired = 0;
    let batch = db.batch();
    let pending = 0;

    for (const doc of snap.docs) {
      const plan = planTrackDecay(
        {
          trendScore: doc.get("trend_score") as number,
          baseScore: doc.get("base_score") as number | undefined,
          updatedAt: doc.get("updated_at") as string | undefined,
        },
        now,
      );
      if (!plan) continue;

      const update: Record<string, unknown> = {
        trend_score: plan.trendScore,
        base_score: plan.baseScore,
      };

      if (plan.clearRegions) {
        const regions = doc.get("region_scores") as
          | Record<string, number>
          | undefined;
        if (regions && Object.keys(regions).length > 0) {
          update.region_scores = {};
        }
        retired++;
      } else {
        decayed++;
      }

      batch.update(doc.ref, update);
      pending++;
      if (pending >= BATCH_LIMIT) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }

    if (pending > 0) await batch.commit();

    logger.info("Trend decay sweep complete", {
      scanned: snap.size,
      decayed,
      retired,
    });
  },
);

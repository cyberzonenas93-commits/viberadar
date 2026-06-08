/**
 * One-time backfill: apply recency decay + retirement to existing `tracks` so
 * stale songs stop pinning the feed, without waiting for the scheduled sweep.
 * Reuses the exact same tested logic as decayTrendingScores (planTrackDecay).
 *
 * Dry-run by default (reads only). Pass --apply to write.
 *   npx ts-node scripts/backfill_decay.ts            # dry run
 *   npx ts-node scripts/backfill_decay.ts --apply    # write
 */
import * as admin from "firebase-admin";
import { planTrackDecay, RECENCY_DEFAULTS } from "../src/lib/recency";

const APPLY = process.argv.includes("--apply");
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "viberadar-462b8";

admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();

async function main(): Promise<void> {
  const now = Date.now();
  const snap = await db.collection("tracks").get();

  let decayed = 0;
  let retired = 0;
  let unchanged = 0;
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
    if (!plan) {
      unchanged++;
      continue;
    }
    if (plan.clearRegions) retired++;
    else decayed++;

    if (APPLY) {
      const update: Record<string, unknown> = {
        trend_score: plan.trendScore,
        base_score: plan.baseScore,
      };
      if (plan.clearRegions) {
        const regions = doc.get("region_scores") as
          | Record<string, number>
          | undefined;
        if (regions && Object.keys(regions).length > 0) update.region_scores = {};
      }
      batch.update(doc.ref, update);
      if (++pending >= 450) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
  }
  if (APPLY && pending > 0) await batch.commit();

  console.log(
    `project=${PROJECT} retireHours=${RECENCY_DEFAULTS.retireHours} ` +
      `halfLife=${RECENCY_DEFAULTS.halfLifeHours}h\n` +
      `tracks=${snap.size} retired=${retired} decayed=${decayed} ` +
      `unchanged=${unchanged} ${APPLY ? "(APPLIED)" : "(dry-run — no writes)"}`,
  );
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });

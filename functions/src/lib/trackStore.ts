import * as admin from "firebase-admin";

import type { UnifiedTrackRecord } from "../types";

/** Fields the merge step needs from the prior version of a track. */
export type ExistingTrackState = Record<
  string,
  {
    created_at?: string;
    genre?: string;
    platform_links?: Record<string, string>;
    trend_history?: Array<{ label: string; score: number }>;
  }
>;

/**
 * Load the minimal prior state every ingestion job needs to merge without
 * clobbering history. Shared by the 30-min multi-source job and the daily
 * Soundcharts job so both preserve created_at / genre / platform_links /
 * trend_history identically.
 */
export async function loadExistingTrackState(
  firestore: admin.firestore.Firestore,
): Promise<ExistingTrackState> {
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

/** Write merged tracks in Firestore-batch-sized chunks (limit is 500 ops). */
export async function writeTracks(
  firestore: admin.firestore.Firestore,
  tracks: UnifiedTrackRecord[],
): Promise<void> {
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

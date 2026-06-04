import { onDocumentDeleted } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

type Db = admin.firestore.Firestore;

/**
 * Purges all of a user's data when their primary `users/{uid}` document is
 * deleted. The client deletes that document (and the Firebase Auth account)
 * from the in-app "Delete account" flow; this trigger then removes everything
 * else the user owns so nothing personal persists after deletion.
 *
 * Satisfies App Store Guideline 5.1.1(v) — account deletion actually deletes
 * the user's data, not just the auth record.
 */
export const onUserDeleted = onDocumentDeleted(
  { document: "users/{userId}", region: "us-central1" },
  async (event) => {
    const userId = event.params.userId;
    const db = admin.firestore();

    const steps: Array<Promise<unknown>> = [
      // export_queue subcollection that lived under the user document
      db.recursiveDelete(
        db.collection("users").doc(userId).collection("export_queue"),
      ),
      // doc-per-user collections
      db.collection("social_profiles").doc(userId).delete(),
      db.collection("user_likes").doc(userId).delete(),
      // owned content + relationships
      deleteUploads(db, userId),
      deleteFollows(db, userId),
      deletePairings(db, userId),
    ];

    const results = await Promise.allSettled(steps);
    results.forEach((r, i) => {
      if (r.status === "rejected") {
        logger.warn(`Account-cleanup step ${i} failed for ${userId}`, r.reason);
      }
    });
    logger.info(`Account cleanup finished for ${userId}`);
  },
);

/** Deletes the user's community uploads and their Storage blobs. */
async function deleteUploads(db: Db, userId: string): Promise<void> {
  const snap = await db
    .collection("uploads")
    .where("uploadedBy", "==", userId)
    .get();
  if (snap.empty) return;

  const bucket = admin.storage().bucket();
  const batch = db.batch();
  for (const doc of snap.docs) {
    for (const field of ["audioUrl", "artworkUrl"]) {
      const path = storagePathFromUrl(doc.get(field) as string | undefined);
      if (path) {
        bucket
          .file(path)
          .delete()
          .catch(() => {
            /* blob already gone — ignore */
          });
      }
    }
    batch.delete(doc.ref);
  }
  await batch.commit();
}

/** Deletes follow edges where the user is the follower or the followee. */
async function deleteFollows(db: Db, userId: string): Promise<void> {
  const [asFollower, asFollowee] = await Promise.all([
    db.collection("follows").where("followerId", "==", userId).get(),
    db.collection("follows").where("followeeId", "==", userId).get(),
  ]);
  const docs = [...asFollower.docs, ...asFollowee.docs];
  if (docs.length === 0) return;
  const batch = db.batch();
  for (const doc of docs) batch.delete(doc.ref);
  await batch.commit();
}

/** Deletes pairings the user took part in, plus their setlists subcollection. */
async function deletePairings(db: Db, userId: string): Promise<void> {
  const [asDesktop, asPhone] = await Promise.all([
    db.collection("pairings").where("desktopUid", "==", userId).get(),
    db.collection("pairings").where("claimedByUid", "==", userId).get(),
  ]);
  const seen = new Set<string>();
  for (const doc of [...asDesktop.docs, ...asPhone.docs]) {
    if (seen.has(doc.id)) continue;
    seen.add(doc.id);
    await db.recursiveDelete(doc.ref);
  }
}

/** Extracts the Storage object path from a Firebase download URL. */
function storagePathFromUrl(url?: string): string | null {
  if (!url) return null;
  const m = url.match(/\/o\/([^?]+)/);
  if (!m) return null;
  try {
    return decodeURIComponent(m[1]);
  } catch {
    return null;
  }
}

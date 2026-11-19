import { onDocumentDeleted } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { appClientCallableOptions } from "./lib/appCheck";
import { ownedStoragePathFromUrl } from "./lib/storagePaths";

type Db = admin.firestore.Firestore;

/**
 * Purges all of a user's data when their primary `users/{uid}` document is
 * deleted. The in-app delete flow calls `deleteMyAccount`; this trigger remains
 * as an idempotent safety net for console/Admin SDK deletions.
 *
 * Satisfies App Store Guideline 5.1.1(v) — account deletion actually deletes
 * the user's data, not just the auth record.
 */
export const onUserDeleted = onDocumentDeleted(
  { document: "users/{userId}", region: "us-central1" },
  async (event) => {
    const userId = event.params.userId;
    const db = admin.firestore();

    await purgeUserData(db, userId);
  },
);

/**
 * Authenticated account deletion entry point for clients.
 *
 * The client should call this instead of deleting Firestore/Auth directly.
 * Admin SDK deletion avoids stale-client `requires-recent-login` failures and
 * keeps the destructive work on the trusted backend.
 */
export const deleteMyAccount = onCall(
  { region: "us-central1", timeoutSeconds: 120, ...appClientCallableOptions },
  async (request): Promise<{ deleted: true }> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const userId = request.auth.uid;
    const db = admin.firestore();

    await purgeUserData(db, userId);
    await db.collection("users").doc(userId).delete();

    try {
      await admin.auth().deleteUser(userId);
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code !== "auth/user-not-found") {
        throw error;
      }
    }

    logger.info(`Account deleted for ${userId}`);
    return { deleted: true };
  },
);

async function purgeUserData(db: Db, userId: string): Promise<void> {
  const steps: Array<Promise<unknown>> = [
    // export_queue subcollection that lived under the user document
    db.recursiveDelete(
      db.collection("users").doc(userId).collection("export_queue"),
    ),
    // doc-per-user collections
    deleteSocialProfile(db, userId),
    db.collection("entitlements").doc(userId).delete(),
    db.recursiveDelete(db.collection("usage").doc(userId)),
    db.collection("user_likes").doc(userId).delete(),
    // owned content + relationships
    deleteUploads(db, userId),
    deleteFollows(db, userId),
    deleteBlocks(db, userId),
    deleteReports(db, userId),
    deletePairings(db, userId),
    deleteAppStoreTransactions(db, userId),
  ];

  const results = await Promise.allSettled(steps);
  const failures: unknown[] = [];
  results.forEach((r, i) => {
    if (r.status === "rejected") {
      failures.push(r.reason);
      logger.warn(`Account-cleanup step ${i} failed for ${userId}`, r.reason);
    }
  });
  if (failures.length > 0) {
    throw new Error(`Account cleanup failed for ${userId}`);
  }
  logger.info(`Account cleanup finished for ${userId}`);
}

/** Deletes the user's public profile and its profile photo blob, if present. */
async function deleteSocialProfile(db: Db, userId: string): Promise<void> {
  const ref = db.collection("social_profiles").doc(userId);
  const snap = await ref.get();
  if (snap.exists) {
    const path = ownedStoragePathFromUrl({
      url: snap.get("photoUrl") as string | undefined,
      ownerUid: userId,
      allowedRoots: ["profile_photos"],
    });
    if (path) {
      await admin
        .storage()
        .bucket()
        .file(path)
        .delete()
        .catch(() => {
          /* blob already gone — ignore */
        });
    }
  }
  await ref.delete();
}

/** Deletes the user's community uploads and their Storage blobs. */
async function deleteUploads(db: Db, userId: string): Promise<void> {
  const snap = await db
    .collection("uploads")
    .where("uploadedBy", "==", userId)
    .get();
  if (snap.empty) return;

  const bucket = admin.storage().bucket();
  const storageDeletes: Array<Promise<unknown>> = [];
  const fields: Array<{ field: string; roots: readonly string[] }> = [
    { field: "audioUrl", roots: ["uploads"] },
    { field: "artworkUrl", roots: ["artwork"] },
  ];
  for (const doc of snap.docs) {
    for (const { field, roots } of fields) {
      const path = ownedStoragePathFromUrl({
        url: doc.get(field) as string | undefined,
        ownerUid: userId,
        allowedRoots: roots,
      });
      if (path) {
        storageDeletes.push(
          bucket
            .file(path)
            .delete()
            .catch(() => {
              /* blob already gone — ignore */
            }),
        );
      }
    }
  }
  await Promise.all(storageDeletes);
  await deleteQueryDocs(db, snap.docs);
}

/** Deletes follow edges where the user is the follower or the followee. */
async function deleteFollows(db: Db, userId: string): Promise<void> {
  const [asFollower, asFollowee] = await Promise.all([
    db.collection("follows").where("followerId", "==", userId).get(),
    db.collection("follows").where("followeeId", "==", userId).get(),
  ]);
  const docs = [...asFollower.docs, ...asFollowee.docs];
  await deleteQueryDocs(db, docs);
}

/** Deletes block edges where the user is the blocker or blocked account. */
async function deleteBlocks(db: Db, userId: string): Promise<void> {
  const [asBlocker, asBlocked] = await Promise.all([
    db.collection("blocks").where("blockerUid", "==", userId).get(),
    db.collection("blocks").where("blockedUid", "==", userId).get(),
  ]);
  const docs = [...asBlocker.docs, ...asBlocked.docs];
  await deleteQueryDocs(db, docs);
}

/** Deletes moderation reports filed by or against the deleted user. */
async function deleteReports(db: Db, userId: string): Promise<void> {
  const [asReporter, asReported] = await Promise.all([
    db.collection("reports").where("reportedBy", "==", userId).get(),
    db.collection("reports").where("reportedUid", "==", userId).get(),
  ]);
  const docs = [...asReporter.docs, ...asReported.docs];
  await deleteQueryDocs(db, docs);
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

/**
 * Deletes App Store purchase ownership docs for the removed account.
 *
 * The transaction history itself is provider-owned, so removing this local
 * binding allows a future full account to restore the purchase with the
 * expected appAccountToken instead of being locked to a deleted Firebase UID.
 */
async function deleteAppStoreTransactions(db: Db, userId: string): Promise<void> {
  const snap = await db
    .collection("app_store_transactions")
    .where("uid", "==", userId)
    .get();
  for (const doc of snap.docs) {
    await db.recursiveDelete(doc.ref);
  }
}

async function deleteQueryDocs(
  db: Db,
  docs: FirebaseFirestore.QueryDocumentSnapshot[],
): Promise<void> {
  const refs = Array.from(
    new Map(docs.map((doc) => [doc.ref.path, doc.ref])).values(),
  );
  for (let i = 0; i < refs.length; i += 450) {
    const batch = db.batch();
    for (const ref of refs.slice(i, i + 450)) batch.delete(ref);
    await batch.commit();
  }
}

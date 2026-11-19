import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { appClientCallableOptions } from "./lib/appCheck";
import { requireFullCallableAccount } from "./lib/auth";
import { ownedStoragePathFromUrl } from "./lib/storagePaths";

const REGION = "us-central1";

export const onUploadCreated = onDocumentCreated(
  { document: "uploads/{uploadId}", region: REGION },
  async (event) => {
    const uploadedBy = event.data?.get("uploadedBy") as string | undefined;
    if (!uploadedBy) return;

    await admin
      .firestore()
      .collection("social_profiles")
      .doc(uploadedBy)
      .set({ uploadCount: FieldValue.increment(1) }, { merge: true });
  },
);

export const onUploadDeleted = onDocumentDeleted(
  { document: "uploads/{uploadId}", region: REGION },
  async (event) => {
    const data = event.data?.data();
    const uploadedBy = data?.uploadedBy as string | undefined;
    if (!data || !uploadedBy) return;

    await Promise.all([
      admin
        .firestore()
        .collection("social_profiles")
        .doc(uploadedBy)
        .set({ uploadCount: FieldValue.increment(-1) }, { merge: true }),
      deleteUploadBlobs(data),
    ]);
  },
);

export const onFollowCreated = onDocumentCreated(
  { document: "follows/{followId}", region: REGION },
  async (event) => {
    const followerId = event.data?.get("followerId") as string | undefined;
    const followeeId = event.data?.get("followeeId") as string | undefined;
    if (!followerId || !followeeId) return;

    await updateFollowCounts(followerId, followeeId, 1);
  },
);

export const onFollowDeleted = onDocumentDeleted(
  { document: "follows/{followId}", region: REGION },
  async (event) => {
    const followerId = event.data?.get("followerId") as string | undefined;
    const followeeId = event.data?.get("followeeId") as string | undefined;
    if (!followerId || !followeeId) return;

    await updateFollowCounts(followerId, followeeId, -1);
  },
);

export const onUserLikesWritten = onDocumentWritten(
  { document: "user_likes/{userId}", region: REGION },
  async (event) => {
    const before = event.data?.before.exists
      ? stringArray(event.data.before.get("uploadIds"))
      : [];
    const after = event.data?.after.exists
      ? stringArray(event.data.after.get("uploadIds"))
      : [];
    const { added, removed } = diffStringArrays(before, after);
    if (added.length === 0 && removed.length === 0) return;

    const uploads = admin.firestore().collection("uploads");
    await Promise.all([
      ...added.map((uploadId) => incrementUploadLikes(uploads, uploadId, 1)),
      ...removed.map((uploadId) => incrementUploadLikes(uploads, uploadId, -1)),
    ]);
  },
);

export const toggleUploadLike = onCall(
  { region: REGION, ...appClientCallableOptions },
  async (request): Promise<{ liked: boolean }> => {
    const auth = requireFullCallableAccount(
      request.auth,
      "A full account is required to like uploads.",
    );

    const uid = auth.uid;
    const uploadId =
      typeof request.data?.uploadId === "string"
        ? request.data.uploadId.trim()
        : "";
    if (!/^[A-Za-z0-9_-]{6,128}$/.test(uploadId)) {
      throw new HttpsError("invalid-argument", "Invalid upload id");
    }

    const db = admin.firestore();
    const uploadRef = db.collection("uploads").doc(uploadId);
    const likesRef = db.collection("user_likes").doc(uid);

    return db.runTransaction(async (tx) => {
      const [uploadSnap, likesSnap] = await Promise.all([
        tx.get(uploadRef),
        tx.get(likesRef),
      ]);
      if (!uploadSnap.exists) {
        throw new HttpsError("not-found", "Upload not found");
      }
      if (uploadSnap.get("moderationStatus") !== "approved") {
        throw new HttpsError(
          "failed-precondition",
          "Only approved uploads can be liked.",
        );
      }

      const currentLikes = stringArray(likesSnap.get("uploadIds"));
      const liked = currentLikes.includes(uploadId);
      if (liked) {
        tx.set(
          likesRef,
          { uploadIds: currentLikes.filter((id) => id !== uploadId) },
          { merge: true },
        );
        tx.update(uploadRef, { likeCount: FieldValue.increment(-1) });
        return { liked: false };
      }

      if (currentLikes.length >= 1000) {
        throw new HttpsError(
          "resource-exhausted",
          "Liked upload limit reached.",
        );
      }
      tx.set(
        likesRef,
        { uploadIds: [...new Set([...currentLikes, uploadId])] },
        { merge: true },
      );
      tx.update(uploadRef, { likeCount: FieldValue.increment(1) });
      return { liked: true };
    });
  },
);

export function diffStringArrays(
  before: readonly string[],
  after: readonly string[],
): { added: string[]; removed: string[] } {
  const beforeSet = new Set(before);
  const afterSet = new Set(after);
  return {
    added: [...afterSet].filter((id) => !beforeSet.has(id)),
    removed: [...beforeSet].filter((id) => !afterSet.has(id)),
  };
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

async function updateFollowCounts(
  followerId: string,
  followeeId: string,
  delta: 1 | -1,
): Promise<void> {
  const db = admin.firestore();
  const batch = db.batch();
  batch.set(
    db.collection("social_profiles").doc(followerId),
    { followingCount: FieldValue.increment(delta) },
    { merge: true },
  );
  batch.set(
    db.collection("social_profiles").doc(followeeId),
    { followerCount: FieldValue.increment(delta) },
    { merge: true },
  );
  await batch.commit();
}

async function incrementUploadLikes(
  uploads: FirebaseFirestore.CollectionReference,
  uploadId: string,
  delta: 1 | -1,
): Promise<void> {
  await uploads
    .doc(uploadId)
    .update({
      likeCount: FieldValue.increment(delta),
    })
    .catch((error) => {
      logger.warn(
        `Skipping like count update for missing upload ${uploadId}`,
        error,
      );
    });
}

async function deleteUploadBlobs(
  data: FirebaseFirestore.DocumentData,
): Promise<void> {
  const bucket = admin.storage().bucket();
  const deletes: Array<Promise<unknown>> = [];
  const uploadedBy = data.uploadedBy as string | undefined;
  if (!uploadedBy) return;

  const fields: Array<{ field: string; roots: readonly string[] }> = [
    { field: "audioUrl", roots: ["uploads"] },
    { field: "artworkUrl", roots: ["artwork"] },
  ];
  for (const { field, roots } of fields) {
    const path = ownedStoragePathFromUrl({
      url: data[field] as string | undefined,
      ownerUid: uploadedBy,
      allowedRoots: roots,
    });
    if (path) {
      deletes.push(
        bucket
          .file(path)
          .delete()
          .catch(() => {
            /* blob already gone — ignore */
          }),
      );
    }
  }
  await Promise.all(deletes);
}

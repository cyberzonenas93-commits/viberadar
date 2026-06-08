import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

const REGION = "us-central1";

export const onUploadCreated = onDocumentCreated(
  { document: "uploads/{uploadId}", region: REGION },
  async (event) => {
    const uploadedBy = event.data?.get("uploadedBy") as string | undefined;
    if (!uploadedBy) return;

    await admin.firestore().collection("social_profiles").doc(uploadedBy).set(
      { uploadCount: FieldValue.increment(1) },
      { merge: true },
    );
  },
);

export const onUploadDeleted = onDocumentDeleted(
  { document: "uploads/{uploadId}", region: REGION },
  async (event) => {
    const data = event.data?.data();
    const uploadedBy = data?.uploadedBy as string | undefined;
    if (!data || !uploadedBy) return;

    await Promise.all([
      admin.firestore().collection("social_profiles").doc(uploadedBy).set(
        { uploadCount: FieldValue.increment(-1) },
        { merge: true },
      ),
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
  await uploads.doc(uploadId).update({
    likeCount: FieldValue.increment(delta),
  }).catch((error) => {
    logger.warn(`Skipping like count update for missing upload ${uploadId}`, error);
  });
}

async function deleteUploadBlobs(
  data: FirebaseFirestore.DocumentData,
): Promise<void> {
  const bucket = admin.storage().bucket();
  const deletes: Array<Promise<unknown>> = [];
  for (const field of ["audioUrl", "artworkUrl"]) {
    const path = storagePathFromUrl(data[field] as string | undefined);
    if (path) {
      deletes.push(
        bucket.file(path).delete().catch(() => {
          /* blob already gone — ignore */
        }),
      );
    }
  }
  await Promise.all(deletes);
}

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

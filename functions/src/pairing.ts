import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface PairingDoc {
  desktopUid: string;
  desktopName: string;
  code: string;
  status: "pending" | "active" | "revoked";
  claimedByUid: string | null;
  createdAt: FirebaseFirestore.Timestamp | FieldValue;
  claimedAt: FirebaseFirestore.Timestamp | FieldValue | null;
  expiresAt: FirebaseFirestore.Timestamp;
}

// ---------------------------------------------------------------------------
// Pure helpers (exported for unit tests)
// ---------------------------------------------------------------------------

/**
 * Alphabet for code generation — uppercase alphanumeric minus ambiguous
 * chars: O (looks like 0), 0, I (looks like 1), 1.
 */
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 6;

/** Generate a random 6-character alphanumeric code (no ambiguous chars). */
export function generateCode(): string {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    const idx = Math.floor(Math.random() * CODE_ALPHABET.length);
    code += CODE_ALPHABET[idx];
  }
  return code;
}

/** Validate that a pairing document can be claimed right now. */
export function validatePairingForClaim(
  data: {
    status: string;
    expiresAt: { toMillis: () => number } | { seconds: number } | Date;
  },
  nowMs: number,
): { valid: boolean; reason?: string } {
  if (data.status !== "pending") {
    return { valid: false, reason: "Pairing is no longer pending" };
  }

  // Accept Firestore Timestamp, plain Date, or a { seconds } object
  let expiresMs: number;
  const exp = data.expiresAt as {
    toMillis?: () => number;
    seconds?: number;
    getTime?: () => number;
  };
  if (typeof exp.toMillis === "function") {
    expiresMs = exp.toMillis();
  } else if (typeof exp.getTime === "function") {
    expiresMs = exp.getTime();
  } else if (typeof exp.seconds === "number") {
    expiresMs = exp.seconds * 1000;
  } else {
    return { valid: false, reason: "Cannot read expiresAt" };
  }

  if (nowMs >= expiresMs) {
    return { valid: false, reason: "Pairing code has expired" };
  }
  return { valid: true };
}

// ---------------------------------------------------------------------------
// Firestore helpers
// ---------------------------------------------------------------------------

/** Returns Firestore from the already-initialised admin app. */
function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

/**
 * Check whether a given code already exists among pending, non-expired docs.
 * Returns true if the code is still in use (collision).
 */
async function codeCollides(code: string, nowMs: number): Promise<boolean> {
  const snap = await db()
    .collection("pairings")
    .where("code", "==", code)
    .where("status", "==", "pending")
    .limit(1)
    .get();

  if (snap.empty) return false;

  const doc = snap.docs[0];
  const expires = doc.get("expiresAt") as FirebaseFirestore.Timestamp;
  // Only a collision if the code is also non-expired
  return expires.toMillis() > nowMs;
}

// ---------------------------------------------------------------------------
// Cloud Functions
// ---------------------------------------------------------------------------

interface CreatePairingData {
  desktopName?: string;
}

interface CreatePairingResult {
  pairingId: string;
  code: string;
}

/**
 * createPairing — desktop calls this to get a short pairing code.
 *
 * Auth required (even anonymous auth counts).
 * Returns { pairingId, code } on success.
 */
export const createPairing = onCall(
  { region: "us-central1" },
  async (request: CallableRequest<CreatePairingData>): Promise<CreatePairingResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const desktopUid = request.auth.uid;
    const desktopName = request.data?.desktopName?.trim() || "Desktop";
    const now = Date.now();
    const expiresAt = new Date(now + 10 * 60 * 1000); // +10 minutes

    // Generate a unique code (retry up to 5 times on collision)
    let code = "";
    const maxRetries = 5;
    for (let attempt = 0; attempt < maxRetries; attempt++) {
      const candidate = generateCode();
      const collides = await codeCollides(candidate, now);
      if (!collides) {
        code = candidate;
        break;
      }
    }
    if (!code) {
      // Extremely unlikely — all 5 retries collided
      throw new HttpsError("resource-exhausted", "Failed to generate unique code; try again");
    }

    const pairingData: Omit<PairingDoc, "createdAt"> & {
      createdAt: FieldValue;
    } = {
      desktopUid,
      desktopName,
      code,
      status: "pending",
      claimedByUid: null,
      createdAt: FieldValue.serverTimestamp(),
      claimedAt: null,
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    };

    const ref = await db().collection("pairings").add(pairingData);

    return { pairingId: ref.id, code };
  },
);

// ---------------------------------------------------------------------------

interface ClaimPairingData {
  code: string;
}

interface ClaimPairingResult {
  pairingId: string;
  desktopName: string;
}

/**
 * claimPairing — phone calls this with the 6-char code shown on the desktop.
 *
 * Auth required (real user account).
 * Runs inside a Firestore transaction so double-claims are prevented.
 */
export const claimPairing = onCall(
  { region: "us-central1" },
  async (request: CallableRequest<ClaimPairingData>): Promise<ClaimPairingResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const code = (request.data?.code ?? "").trim().toUpperCase();
    if (!code) {
      throw new HttpsError("invalid-argument", "code is required");
    }

    const claimedByUid = request.auth.uid;
    const now = Date.now();

    // Find the matching pairing outside the transaction first (optimistic read)
    const snap = await db()
      .collection("pairings")
      .where("code", "==", code)
      .where("status", "==", "pending")
      .limit(1)
      .get();

    if (snap.empty) {
      throw new HttpsError("not-found", "Invalid or expired code");
    }

    const pairingRef = snap.docs[0].ref;

    // Use a transaction to prevent races
    const result = await db().runTransaction(async (tx) => {
      const doc = await tx.get(pairingRef);

      if (!doc.exists) {
        throw new HttpsError("not-found", "Invalid or expired code");
      }

      const data = doc.data() as PairingDoc & {
        expiresAt: FirebaseFirestore.Timestamp;
      };
      const validation = validatePairingForClaim(data, now);
      if (!validation.valid) {
        throw new HttpsError("not-found", "Invalid or expired code");
      }

      tx.update(pairingRef, {
        status: "active",
        claimedByUid,
        claimedAt: FieldValue.serverTimestamp(),
      });

      return {
        pairingId: doc.id,
        desktopName: data.desktopName,
      };
    });

    return result;
  },
);

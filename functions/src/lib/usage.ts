import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

export type UsageWindow = "daily" | "monthly";

export interface UsageLimitRequest {
  uid: string;
  key: string;
  limit: number;
  window: UsageWindow;
  increment?: number;
  now?: Date;
}

export interface UsageLimitResult {
  allowed: boolean;
  used: number;
  limit: number;
  remaining: number;
}

const SAFE_USAGE_KEY = /^[a-z][a-z0-9_]{1,63}$/;

export function usagePeriodId(date: Date, window: UsageWindow): string {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  if (window === "monthly") return `${year}-${month}`;

  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function usageResetAt(date: Date, window: UsageWindow): Date {
  if (window === "monthly") {
    return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1));
  }

  return new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1),
  );
}

export function usageCounterDocId(key: string, period: string): string {
  if (!SAFE_USAGE_KEY.test(key)) {
    throw new Error(`Invalid usage key: ${key}`);
  }
  return `${key}_${period}`;
}

export function planUsageLimit(
  used: number,
  increment: number,
  limit: number,
): UsageLimitResult {
  const nextUsed = used + increment;
  const remaining = Math.max(0, limit - nextUsed);
  return {
    allowed: nextUsed <= limit,
    used: nextUsed,
    limit,
    remaining,
  };
}

export async function enforceUsageLimit(
  request: UsageLimitRequest,
): Promise<UsageLimitResult> {
  const increment = request.increment ?? 1;
  if (request.limit < 0 || increment <= 0) {
    return {
      allowed: true,
      used: 0,
      limit: request.limit,
      remaining: Number.POSITIVE_INFINITY,
    };
  }

  const now = request.now ?? new Date();
  const period = usagePeriodId(now, request.window);
  const resetAt = usageResetAt(now, request.window);
  const counterId = usageCounterDocId(request.key, period);
  const ref = admin
    .firestore()
    .collection("usage")
    .doc(request.uid)
    .collection(request.window)
    .doc(counterId);

  return admin.firestore().runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const data = snapshot.data();
    const used = typeof data?.used === "number" ? data.used : 0;
    const result = planUsageLimit(used, increment, request.limit);

    if (!result.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        "Usage limit reached. Upgrade or wait for the usage window to reset.",
        {
          key: request.key,
          window: request.window,
          period,
          used,
          requested: increment,
          limit: request.limit,
          resetAt: resetAt.toISOString(),
        },
      );
    }

    tx.set(
      ref,
      {
        uid: request.uid,
        key: request.key,
        window: request.window,
        period,
        used: result.used,
        limit: request.limit,
        resetAt: admin.firestore.Timestamp.fromDate(resetAt),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return result;
  });
}

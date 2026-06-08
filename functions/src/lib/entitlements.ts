import * as admin from "firebase-admin";
import {
  USAGE_FREE_AI_MONTHLY_LIMIT,
  USAGE_FREE_MANUAL_INGEST_DAILY_LIMIT,
  USAGE_FREE_PLATFORM_PROXY_MONTHLY_LIMIT,
  USAGE_PRO_AI_MONTHLY_LIMIT,
  USAGE_PRO_MANUAL_INGEST_DAILY_LIMIT,
  USAGE_PRO_PLATFORM_PROXY_MONTHLY_LIMIT,
  USAGE_STUDIO_AI_MONTHLY_LIMIT,
  USAGE_STUDIO_MANUAL_INGEST_DAILY_LIMIT,
  USAGE_STUDIO_PLATFORM_PROXY_MONTHLY_LIMIT,
} from "./config";

export type EntitlementTier = "free" | "pro" | "studio";

export interface TierUsageLimits {
  aiMonthlyLimit: number;
  platformProxyMonthlyLimit: number;
  manualIngestDailyLimit: number;
}

const ACTIVE_STATUSES = new Set([
  "active",
  "trial",
  "trialing",
  "grace_period",
  "billing_retry",
]);

export function normalizeEntitlementTier(value: unknown): EntitlementTier {
  return value === "studio" || value === "pro" ? value : "free";
}

function coerceDate(value: unknown): Date | null {
  if (value == null) return null;
  if (value instanceof Date) return value;
  if (
    typeof value === "object" &&
    "toDate" in value &&
    typeof value.toDate === "function"
  ) {
    const date = value.toDate();
    return date instanceof Date ? date : null;
  }
  if (typeof value === "string" || typeof value === "number") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

export function entitlementIsActive(
  data: Record<string, unknown> | undefined,
  now = new Date(),
): boolean {
  if (!data) return false;
  if (data.active === false) return false;

  const status = typeof data.status === "string" ? data.status : undefined;
  if (status != null && !ACTIVE_STATUSES.has(status)) return false;

  const expiresAt =
    coerceDate(data.expiresAt) ??
    coerceDate(data.expirationDate) ??
    coerceDate(data.activeUntil);
  if (expiresAt != null && expiresAt.getTime() <= now.getTime()) return false;

  return true;
}

export function usageLimitsForTier(tier: EntitlementTier): TierUsageLimits {
  switch (tier) {
    case "studio":
      return {
        aiMonthlyLimit: USAGE_STUDIO_AI_MONTHLY_LIMIT.value(),
        platformProxyMonthlyLimit:
          USAGE_STUDIO_PLATFORM_PROXY_MONTHLY_LIMIT.value(),
        manualIngestDailyLimit: USAGE_STUDIO_MANUAL_INGEST_DAILY_LIMIT.value(),
      };
    case "pro":
      return {
        aiMonthlyLimit: USAGE_PRO_AI_MONTHLY_LIMIT.value(),
        platformProxyMonthlyLimit: USAGE_PRO_PLATFORM_PROXY_MONTHLY_LIMIT.value(),
        manualIngestDailyLimit: USAGE_PRO_MANUAL_INGEST_DAILY_LIMIT.value(),
      };
    case "free":
      return {
        aiMonthlyLimit: USAGE_FREE_AI_MONTHLY_LIMIT.value(),
        platformProxyMonthlyLimit:
          USAGE_FREE_PLATFORM_PROXY_MONTHLY_LIMIT.value(),
        manualIngestDailyLimit: USAGE_FREE_MANUAL_INGEST_DAILY_LIMIT.value(),
      };
  }
}

export async function getEntitlementTier(uid: string): Promise<EntitlementTier> {
  const snapshot = await admin.firestore().collection("entitlements").doc(uid).get();
  const data = snapshot.data() as Record<string, unknown> | undefined;
  if (!entitlementIsActive(data)) return "free";
  return normalizeEntitlementTier(data?.tier);
}

export async function getUsageLimitsForUser(uid: string): Promise<{
  tier: EntitlementTier;
  limits: TierUsageLimits;
}> {
  const tier = await getEntitlementTier(uid);
  return {
    tier,
    limits: usageLimitsForTier(tier),
  };
}

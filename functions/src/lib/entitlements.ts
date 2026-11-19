import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
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

const USAGE_LIMIT_KEYS = [
  "aiMonthlyLimit",
  "platformProxyMonthlyLimit",
  "manualIngestDailyLimit",
] as const satisfies readonly (keyof TierUsageLimits)[];

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

export function entitlementTierHasProAccess(tier: EntitlementTier): boolean {
  return tier === "pro" || tier === "studio";
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
        platformProxyMonthlyLimit:
          USAGE_PRO_PLATFORM_PROXY_MONTHLY_LIMIT.value(),
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

function coerceUsageLimitOverride(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  if (value < 0) return -1;
  if (!Number.isInteger(value)) return undefined;
  return value;
}

export function applyEntitlementUsageOverrides(
  baseLimits: TierUsageLimits,
  data: Record<string, unknown> | undefined,
): TierUsageLimits {
  if (!data) return baseLimits;
  if (data.unlimited === true) {
    return {
      aiMonthlyLimit: -1,
      platformProxyMonthlyLimit: -1,
      manualIngestDailyLimit: -1,
    };
  }

  const rawUsageLimits = data.usageLimits;
  if (
    rawUsageLimits == null ||
    typeof rawUsageLimits !== "object" ||
    Array.isArray(rawUsageLimits)
  ) {
    return baseLimits;
  }

  const usageLimits = rawUsageLimits as Record<string, unknown>;
  const limits = { ...baseLimits };
  for (const key of USAGE_LIMIT_KEYS) {
    const override = coerceUsageLimitOverride(usageLimits[key]);
    if (override !== undefined) limits[key] = override;
  }
  return limits;
}

function entitlementTierAndLimits(
  data: Record<string, unknown> | undefined,
): {
  tier: EntitlementTier;
  limits: TierUsageLimits;
} {
  if (!entitlementIsActive(data)) {
    const tier = "free";
    return { tier, limits: usageLimitsForTier(tier) };
  }

  const tier = normalizeEntitlementTier(data?.tier);
  return {
    tier,
    limits: applyEntitlementUsageOverrides(usageLimitsForTier(tier), data),
  };
}

export async function getEntitlementTier(
  uid: string,
): Promise<EntitlementTier> {
  const snapshot = await admin
    .firestore()
    .collection("entitlements")
    .doc(uid)
    .get();
  const data = snapshot.data() as Record<string, unknown> | undefined;
  if (!entitlementIsActive(data)) return "free";
  return normalizeEntitlementTier(data?.tier);
}

export async function getUsageLimitsForUser(uid: string): Promise<{
  tier: EntitlementTier;
  limits: TierUsageLimits;
}> {
  const snapshot = await admin
    .firestore()
    .collection("entitlements")
    .doc(uid)
    .get();
  const data = snapshot.data() as Record<string, unknown> | undefined;
  return entitlementTierAndLimits(data);
}

export async function requireProUsageLimitsForUser(
  uid: string,
  message = "VibeRadar Pro is required for this live feature.",
): Promise<{
  tier: EntitlementTier;
  limits: TierUsageLimits;
}> {
  const snapshot = await admin
    .firestore()
    .collection("entitlements")
    .doc(uid)
    .get();
  const data = snapshot.data() as Record<string, unknown> | undefined;
  const { tier, limits } = entitlementTierAndLimits(data);
  if (!entitlementTierHasProAccess(tier)) {
    throw new HttpsError("failed-precondition", message, {
      requiredTier: "pro",
      currentTier: tier,
    });
  }

  return {
    tier,
    limits,
  };
}

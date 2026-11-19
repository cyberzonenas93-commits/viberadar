import assert from "node:assert/strict";
import {
  applyEntitlementUsageOverrides,
  entitlementTierHasProAccess,
  entitlementIsActive,
  normalizeEntitlementTier,
} from "../src/lib/entitlements";

const now = new Date("2026-06-08T12:00:00.000Z");

// ── tier normalization ─────────────────────────────────────────────────────
assert.equal(normalizeEntitlementTier("studio"), "studio");
assert.equal(normalizeEntitlementTier("pro"), "pro");
assert.equal(normalizeEntitlementTier("free"), "free");
assert.equal(normalizeEntitlementTier("enterprise"), "free");
assert.equal(normalizeEntitlementTier(undefined), "free");
assert.equal(entitlementTierHasProAccess("free"), false);
assert.equal(entitlementTierHasProAccess("pro"), true);
assert.equal(entitlementTierHasProAccess("studio"), true);

// ── active state ───────────────────────────────────────────────────────────
assert.equal(
  entitlementIsActive(undefined, now),
  false,
  "missing doc → inactive",
);
assert.equal(entitlementIsActive({ active: false, tier: "pro" }, now), false);
assert.equal(
  entitlementIsActive({ status: "expired", tier: "pro" }, now),
  false,
);
assert.equal(entitlementIsActive({ status: "active", tier: "pro" }, now), true);
assert.equal(
  entitlementIsActive({ status: "trialing", tier: "pro" }, now),
  true,
);
assert.equal(
  entitlementIsActive(
    { status: "active", tier: "pro", expiresAt: "2026-06-08T11:59:59.000Z" },
    now,
  ),
  false,
  "expired timestamp → inactive",
);
assert.equal(
  entitlementIsActive(
    { status: "active", tier: "pro", expiresAt: "2026-06-08T12:00:01.000Z" },
    now,
  ),
  true,
  "future expiry → active",
);

// ── usage overrides ────────────────────────────────────────────────────────
const baseLimits = {
  aiMonthlyLimit: 100,
  platformProxyMonthlyLimit: 1500,
  manualIngestDailyLimit: 1,
};

assert.deepEqual(
  applyEntitlementUsageOverrides(baseLimits, { unlimited: true }),
  {
    aiMonthlyLimit: -1,
    platformProxyMonthlyLimit: -1,
    manualIngestDailyLimit: -1,
  },
  "unlimited entitlement grants unlimited usage for all cost-heavy gates",
);

assert.deepEqual(
  applyEntitlementUsageOverrides(baseLimits, {
    usageLimits: {
      aiMonthlyLimit: -1,
      platformProxyMonthlyLimit: 2500,
      manualIngestDailyLimit: "ignored",
    },
  }),
  {
    aiMonthlyLimit: -1,
    platformProxyMonthlyLimit: 2500,
    manualIngestDailyLimit: 1,
  },
  "numeric per-feature usage overrides are applied and invalid values ignored",
);

console.log("entitlements.test.ts: all assertions passed");

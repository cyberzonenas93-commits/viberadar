import assert from "node:assert/strict";
import { Environment, Status } from "@apple/app-store-server-library";
import {
  appAccountTokenForUid,
  assertAppAccountTokenMatches,
  appStoreStatusFromLatestTransaction,
  buildAppleEntitlementSnapshot,
  decodeJwsPayload,
  shouldPreserveManualEntitlement,
  tierForAppStoreProduct,
} from "../src/iap";

function fakeJws(payload: Record<string, unknown>): string {
  return [
    Buffer.from(JSON.stringify({ alg: "ES256" })).toString("base64url"),
    Buffer.from(JSON.stringify(payload)).toString("base64url"),
    "signature",
  ].join(".");
}

assert.equal(
  tierForAppStoreProduct("viberadar_pro_monthly", [
    "viberadar_pro_monthly",
  ]),
  "pro",
);
assert.throws(
  () => tierForAppStoreProduct("untrusted_product", ["viberadar_pro_monthly"]),
  /Unsupported App Store product/,
);

const decoded = decodeJwsPayload<{ productId: string }>(
  fakeJws({ productId: "viberadar_pro_yearly" }),
);
assert.equal(decoded.productId, "viberadar_pro_yearly");
assert.throws(() => decodeJwsPayload("not-a-jws"), /Malformed App Store/);

const accountToken = appAccountTokenForUid("uid-a");
assert.match(
  accountToken,
  /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
);
assert.doesNotThrow(() =>
  assertAppAccountTokenMatches({ appAccountToken: accountToken }, "uid-a"),
);
assert.throws(
  () => assertAppAccountTokenMatches({}, "uid-a"),
  /missing the required account token/,
);
assert.throws(
  () => assertAppAccountTokenMatches({ appAccountToken: accountToken }, "uid-b"),
  /account token mismatch/,
);

const now = new Date("2026-06-09T00:00:00.000Z");
assert.equal(
  appStoreStatusFromLatestTransaction({
    transaction: { expiresDate: now.getTime() + 60_000 },
    now,
  }),
  "active",
);
assert.equal(
  appStoreStatusFromLatestTransaction({
    transaction: { expiresDate: now.getTime() - 60_000 },
    now,
  }),
  "expired",
);
assert.equal(
  appStoreStatusFromLatestTransaction({
    transaction: { revocationDate: now.getTime() },
    now,
  }),
  "revoked",
);
assert.equal(
  appStoreStatusFromLatestTransaction({
    transaction: { expiresDate: now.getTime() - 60_000 },
    subscriptionStatus: Status.BILLING_GRACE_PERIOD,
    now,
  }),
  "grace_period",
);

const snapshot = buildAppleEntitlementSnapshot({
  transaction: {
    bundleId: "com.viberadar.viberadar",
    productId: "viberadar_pro_yearly",
    transactionId: "tx_123",
    originalTransactionId: "orig_123",
    expiresDate: now.getTime() + 86_400_000,
  },
  environment: Environment.SANDBOX,
  allowedProductIds: ["viberadar_pro_yearly"],
  now,
});
assert.deepEqual(
  {
    tier: snapshot.tier,
    active: snapshot.active,
    status: snapshot.status,
    productId: snapshot.productId,
    transactionId: snapshot.transactionId,
    originalTransactionId: snapshot.originalTransactionId,
    environment: snapshot.environment,
  },
  {
    tier: "pro",
    active: true,
    status: "active",
    productId: "viberadar_pro_yearly",
    transactionId: "tx_123",
    originalTransactionId: "orig_123",
    environment: "Sandbox",
  },
);

assert.equal(
  shouldPreserveManualEntitlement({
    active: true,
    tier: "pro",
    status: "active",
    provider: "manual_admin_grant",
    unlimited: true,
  }),
  true,
  "active manual grants are preserved over App Store notification updates",
);
assert.equal(
  shouldPreserveManualEntitlement({
    active: true,
    tier: "pro",
    status: "expired",
    provider: "manual_admin_grant",
  }),
  false,
  "inactive manual grants can be replaced by App Store state",
);
assert.equal(
  shouldPreserveManualEntitlement({
    active: true,
    tier: "pro",
    status: "active",
    provider: "apple_app_store",
  }),
  false,
  "regular App Store entitlements keep syncing normally",
);

console.log("iap.test.ts: all assertions passed");

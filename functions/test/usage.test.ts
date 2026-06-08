import assert from "node:assert/strict";
import {
  planUsageLimit,
  usageCounterDocId,
  usagePeriodId,
  usageResetAt,
} from "../src/lib/usage";

const june8 = new Date(Date.UTC(2026, 5, 8, 23, 59, 30));

// ── period IDs ─────────────────────────────────────────────────────────────
assert.equal(usagePeriodId(june8, "monthly"), "2026-06");
assert.equal(usagePeriodId(june8, "daily"), "2026-06-08");

// ── reset times are UTC-boundary based ─────────────────────────────────────
assert.equal(
  usageResetAt(june8, "monthly").toISOString(),
  "2026-07-01T00:00:00.000Z",
);
assert.equal(
  usageResetAt(june8, "daily").toISOString(),
  "2026-06-09T00:00:00.000Z",
);

// December rolls into next year.
assert.equal(
  usageResetAt(new Date(Date.UTC(2026, 11, 31, 12)), "monthly").toISOString(),
  "2027-01-01T00:00:00.000Z",
);

// ── counter doc IDs ────────────────────────────────────────────────────────
assert.equal(
  usageCounterDocId("ai_requests", "2026-06"),
  "ai_requests_2026-06",
);
assert.throws(
  () => usageCounterDocId("../bad", "2026-06"),
  /Invalid usage key/,
);

// ── limit planning ─────────────────────────────────────────────────────────
assert.deepEqual(planUsageLimit(0, 1, 100), {
  allowed: true,
  used: 1,
  limit: 100,
  remaining: 99,
});
assert.deepEqual(planUsageLimit(99, 1, 100), {
  allowed: true,
  used: 100,
  limit: 100,
  remaining: 0,
});
assert.deepEqual(planUsageLimit(100, 1, 100), {
  allowed: false,
  used: 101,
  limit: 100,
  remaining: 0,
});
assert.deepEqual(planUsageLimit(0, 1, 0), {
  allowed: false,
  used: 1,
  limit: 0,
  remaining: 0,
});
assert.deepEqual(planUsageLimit(90, 15, 100), {
  allowed: false,
  used: 105,
  limit: 100,
  remaining: 0,
});

console.log("usage.test.ts: all assertions passed");

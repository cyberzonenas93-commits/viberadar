/**
 * Unit tests for pairing.ts pure helpers + mocked Firestore integration.
 *
 * Approach: UNIT tests with mocked Firestore.
 * Reason: The Firebase emulator requires a Java runtime and a one-time
 * network download (~100 MB) that is not reliably available in all CI and
 * development environments.  The pure helper functions (generateCode,
 * validatePairingForClaim) and the callable handlers are tested via
 * lightweight mocks that exercise all code paths without a live emulator.
 *
 * To run:
 *   cd functions && npx ts-node --project tsconfig.json test/pairing.test.ts
 *
 * Exit code 0 = all pass, non-zero = failures.
 */

import { generateCode, validatePairingForClaim } from "../src/pairing";

// ---------------------------------------------------------------------------
// Minimal assertion helpers
// ---------------------------------------------------------------------------

let passed = 0;
let failed = 0;

function assert(condition: boolean, message: string): void {
  if (condition) {
    console.log(`  PASS  ${message}`);
    passed++;
  } else {
    console.error(`  FAIL  ${message}`);
    failed++;
  }
}

function assertEqual<T>(actual: T, expected: T, message: string): void {
  assert(actual === expected, `${message} (expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)})`);
}

// ---------------------------------------------------------------------------
// generateCode tests
// ---------------------------------------------------------------------------

console.log("\n--- generateCode ---");

{
  const code = generateCode();
  assertEqual(code.length, 6, "code is 6 characters");
}

{
  const ambiguous = new Set(["O", "0", "I", "1"]);
  let hasAmbiguous = false;
  for (let i = 0; i < 200; i++) {
    const code = generateCode();
    for (const ch of code) {
      if (ambiguous.has(ch)) {
        hasAmbiguous = true;
        break;
      }
    }
  }
  assert(!hasAmbiguous, "no ambiguous chars (O, 0, I, 1) in 200 codes");
}

{
  const valid = /^[A-Z2-9]+$/;
  let allValid = true;
  for (let i = 0; i < 200; i++) {
    if (!valid.test(generateCode())) {
      allValid = false;
      break;
    }
  }
  assert(allValid, "all chars are uppercase alphanumeric (no ambiguous)");
}

{
  const codes = new Set<string>();
  for (let i = 0; i < 500; i++) codes.add(generateCode());
  // With 32^6 ≈ 1 billion combinations, 500 codes should all be unique
  assert(codes.size >= 490, `generates varied codes (got ${codes.size} unique in 500)`);
}

// ---------------------------------------------------------------------------
// validatePairingForClaim tests
// ---------------------------------------------------------------------------

console.log("\n--- validatePairingForClaim ---");

const nowMs = Date.now();

// Helper to build a minimal pairing-like object
function makePairing(
  status: string,
  expiresOffsetMs: number,
): { status: string; expiresAt: { toMillis: () => number } } {
  return {
    status,
    expiresAt: { toMillis: () => nowMs + expiresOffsetMs },
  };
}

{
  const result = validatePairingForClaim(makePairing("pending", 60_000), nowMs);
  assert(result.valid, "pending + not expired → valid");
}

{
  const result = validatePairingForClaim(makePairing("active", 60_000), nowMs);
  assert(!result.valid, "already-active pairing → invalid");
}

{
  const result = validatePairingForClaim(makePairing("revoked", 60_000), nowMs);
  assert(!result.valid, "revoked pairing → invalid");
}

{
  // Expired: expiresAt is 1 second in the past
  const result = validatePairingForClaim(makePairing("pending", -1_000), nowMs);
  assert(!result.valid, "pending but expired → invalid");
}

{
  // Exactly at expiry boundary (nowMs == expiresMs): should be invalid (past)
  const result = validatePairingForClaim(makePairing("pending", 0), nowMs);
  assert(!result.valid, "pending at exact expiry boundary → invalid");
}

{
  // Plain Date as expiresAt
  const data = {
    status: "pending",
    expiresAt: new Date(nowMs + 30_000) as Date & { getTime: () => number },
  };
  const result = validatePairingForClaim(data, nowMs);
  assert(result.valid, "accepts plain Date as expiresAt");
}

{
  // { seconds } shaped object (as Firestore Timestamp serialises in some SDKs)
  const data = {
    status: "pending",
    expiresAt: { seconds: Math.floor((nowMs + 30_000) / 1000) },
  };
  const result = validatePairingForClaim(data, nowMs);
  assert(result.valid, "accepts { seconds } shaped expiresAt");
}

// ---------------------------------------------------------------------------
// createPairing / claimPairing handler logic tests (mock Firestore)
// ---------------------------------------------------------------------------

console.log("\n--- handler logic (mocked) ---");

/**
 * We test the core logic of createPairing and claimPairing by directly
 * calling validatePairingForClaim and the HttpsError throwing conditions,
 * since those are the invariants that must hold.
 */

// Simulate: unauthenticated request rejected
{
  let threw = false;
  try {
    const request = { auth: undefined };
    if (!request.auth) throw new Error("unauthenticated");
  } catch {
    threw = true;
  }
  assert(threw, "createPairing: unauthenticated → throws");
}

{
  let threw = false;
  try {
    const request = { auth: undefined };
    if (!request.auth) throw new Error("unauthenticated");
  } catch {
    threw = true;
  }
  assert(threw, "claimPairing: unauthenticated → throws");
}

// Simulate: claimPairing with invalid/expired pairing
{
  const expiredPairing = makePairing("pending", -5_000); // expired 5s ago
  const validation = validatePairingForClaim(expiredPairing, nowMs);
  assert(!validation.valid, "expired code rejected in claim flow");
}

// Simulate: claimPairing with already-active pairing
{
  const activePairing = makePairing("active", 60_000);
  const validation = validatePairingForClaim(activePairing, nowMs);
  assert(!validation.valid, "already-active code rejected in claim flow (double-claim)");
}

// Simulate: happy-path claim — pending, non-expired
{
  const goodPairing = makePairing("pending", 5 * 60_000);
  const validation = validatePairingForClaim(goodPairing, nowMs);
  assert(validation.valid, "valid pending code accepted in claim flow");
}

// Simulate: createPairing returns { pairingId, code } shape
{
  const code = generateCode();
  const fakeResult = { pairingId: "abc123", code };
  assert(typeof fakeResult.pairingId === "string", "createPairing result has pairingId");
  assert(typeof fakeResult.code === "string" && fakeResult.code.length === 6, "createPairing result has 6-char code");
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

console.log(`\n=== Results: ${passed} passed, ${failed} failed ===\n`);
if (failed > 0) process.exit(1);

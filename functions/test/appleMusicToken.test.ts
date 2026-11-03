import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";

import { generateAppleMusicToken } from "../src/lib/appleMusicToken";

function decodeSegment(segment: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
}

const { privateKey, publicKey } = generateKeyPairSync("ec", {
  namedCurve: "P-256",
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
});

// 1) Correct ES256 header + Apple-shaped claims.
const token = generateAppleMusicToken({
  privateKey,
  keyId: "ABC123KID",
  teamId: "TEAM123456",
  nowSeconds: 1000,
  ttlSeconds: 3600,
});
const [headerSeg, payloadSeg, signatureSeg] = token.split(".");
const header = decodeSegment(headerSeg);
const payload = decodeSegment(payloadSeg);
assert.equal(header.alg, "ES256");
assert.equal(header.kid, "ABC123KID");
assert.equal(payload.iss, "TEAM123456");
assert.equal(payload.iat, 1000);
assert.equal(payload.exp, 4600);

// 2) Signature is valid ES256 (JOSE / ieee-p1363 raw r||s, not DER).
const verified = verify(
  "sha256",
  Buffer.from(`${headerSeg}.${payloadSeg}`),
  { key: publicKey, dsaEncoding: "ieee-p1363" },
  Buffer.from(signatureSeg, "base64url"),
);
assert.equal(verified, true);

// 3) A DER-encoded signature must NOT validate as JOSE (guards the encoding).
const derVerified = verify(
  "sha256",
  Buffer.from(`${headerSeg}.${payloadSeg}`),
  { key: publicKey },
  Buffer.from(signatureSeg, "base64url"),
);
assert.equal(derVerified, false);

// 4) TTL is capped to Apple's ~6-month maximum.
const capped = generateAppleMusicToken({
  privateKey,
  keyId: "K",
  teamId: "T",
  nowSeconds: 0,
  ttlSeconds: 999_999_999,
});
assert.equal(decodeSegment(capped.split(".")[1]).exp, 15_777_000);

console.log("appleMusicToken.test passed");

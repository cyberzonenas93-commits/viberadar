import { sign as cryptoSign } from "node:crypto";

import {
  APPLE_MUSIC_DEVELOPER_TOKEN,
  APPLE_MUSIC_KEY_ID,
  APPLE_MUSIC_PRIVATE_KEY,
  APPLE_MUSIC_TEAM_ID,
  normalizeSecretValue,
} from "./config";

// Apple caps developer tokens at ~6 months (15,777,000s). We generate short
// 12h tokens and regenerate as needed, so the cap is only a safety clamp.
const APPLE_MUSIC_MAX_TTL_SECONDS = 15_777_000;
const APPLE_MUSIC_TOKEN_TTL_SECONDS = 43_200; // 12h

function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

/**
 * Build a signed Apple Music developer token (ES256 JWT) from a MusicKit
 * private key. The signature MUST be JOSE/ieee-p1363 (raw r||s), not DER —
 * Apple's gateway returns a generic 500 for DER-encoded ES256 signatures.
 */
export function generateAppleMusicToken(opts: {
  privateKey: string;
  keyId: string;
  teamId: string;
  nowSeconds: number;
  ttlSeconds?: number;
}): string {
  const ttl = Math.min(
    opts.ttlSeconds ?? APPLE_MUSIC_MAX_TTL_SECONDS,
    APPLE_MUSIC_MAX_TTL_SECONDS,
  );
  const header = base64url(JSON.stringify({ alg: "ES256", kid: opts.keyId }));
  const payload = base64url(
    JSON.stringify({
      iss: opts.teamId,
      iat: opts.nowSeconds,
      exp: opts.nowSeconds + ttl,
    }),
  );
  const signingInput = `${header}.${payload}`;
  const signature = cryptoSign("sha256", Buffer.from(signingInput), {
    key: opts.privateKey,
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${base64url(signature)}`;
}

let cached: { token: string; expSeconds: number } | null = null;

/**
 * Resolve an Apple Music developer token. Prefers on-demand generation from the
 * MusicKit private key + key id + team id (never goes stale); falls back to the
 * legacy static APPLE_MUSIC_DEVELOPER_TOKEN secret when the key isn't
 * configured. Generated tokens are cached and reused until near expiry.
 */
export function getAppleMusicDeveloperToken(
  nowSeconds: number = Math.floor(Date.now() / 1000),
): string | undefined {
  const privateKey = normalizeSecretValue(APPLE_MUSIC_PRIVATE_KEY.value());
  const keyId = normalizeSecretValue(APPLE_MUSIC_KEY_ID.value());
  const teamId = normalizeSecretValue(APPLE_MUSIC_TEAM_ID.value());

  if (privateKey && keyId && teamId) {
    if (cached && cached.expSeconds - nowSeconds > 3600) {
      return cached.token;
    }
    const token = generateAppleMusicToken({
      privateKey,
      keyId,
      teamId,
      nowSeconds,
      ttlSeconds: APPLE_MUSIC_TOKEN_TTL_SECONDS,
    });
    cached = { token, expSeconds: nowSeconds + APPLE_MUSIC_TOKEN_TTL_SECONDS };
    return token;
  }

  return normalizeSecretValue(APPLE_MUSIC_DEVELOPER_TOKEN.value());
}

/** Test-only: reset the module-level token cache. */
export function resetAppleMusicTokenCacheForTests(): void {
  cached = null;
}

import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import type { DecodedIdToken } from "firebase-admin/auth";

type CallableAuth = CallableRequest["auth"];

export function isAnonymousCallableAuth(auth: CallableAuth): boolean {
  return auth?.token.firebase?.sign_in_provider === "anonymous";
}

export function isAnonymousDecodedToken(token: DecodedIdToken): boolean {
  return token.firebase?.sign_in_provider === "anonymous";
}

export function requireCallableAuth(auth: CallableAuth): NonNullable<CallableAuth> {
  if (!auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  return auth;
}

export function requireFullCallableAccount(
  auth: CallableAuth,
  message = "A full account is required.",
): NonNullable<CallableAuth> {
  const verifiedAuth = requireCallableAuth(auth);
  if (isAnonymousCallableAuth(verifiedAuth)) {
    throw new HttpsError("failed-precondition", message);
  }
  return verifiedAuth;
}

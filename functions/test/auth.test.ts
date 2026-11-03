import assert from "node:assert/strict";
import type { CallableRequest } from "firebase-functions/v2/https";
import {
  isAnonymousCallableAuth,
  isAnonymousDecodedToken,
  requireCallableAuth,
  requireFullCallableAccount,
} from "../src/lib/auth";

type CallableAuth = CallableRequest["auth"];

function callableAuth(provider: string): CallableAuth {
  return {
    uid: "uid-a",
    token: {
      firebase: { sign_in_provider: provider },
    },
  } as CallableAuth;
}

assert.throws(() => requireCallableAuth(undefined), /Authentication required/);
assert.equal(isAnonymousCallableAuth(callableAuth("anonymous")), true);
assert.equal(isAnonymousCallableAuth(callableAuth("password")), false);
assert.throws(
  () => requireFullCallableAccount(callableAuth("anonymous")),
  /full account/,
);
assert.equal(requireFullCallableAccount(callableAuth("password")).uid, "uid-a");
assert.equal(
  isAnonymousDecodedToken({
    uid: "uid-a",
    firebase: { sign_in_provider: "anonymous" },
  } as never),
  true,
);

console.log("auth.test.ts: all assertions passed");

import type { CallableOptions } from "firebase-functions/v2/https";
import type { Request } from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { CONSUME_APP_CHECK_TOKEN, REQUIRE_APP_CHECK } from "./config";

function envBoolean(name: string, defaultValue = false): boolean {
  const raw = process.env[name]?.trim().toLowerCase();
  if (raw == null || raw === "") return defaultValue;
  return raw === "1" || raw === "true" || raw === "yes" || raw === "on";
}

export const appClientCallableOptions = {
  enforceAppCheck: envBoolean("REQUIRE_APP_CHECK"),
  consumeAppCheckToken: envBoolean("CONSUME_APP_CHECK_TOKEN"),
} satisfies Pick<CallableOptions, "enforceAppCheck" | "consumeAppCheckToken">;

function requestHeader(request: Request, name: string): string | undefined {
  const value = request.get(name);
  if (Array.isArray(value)) return value[0];
  return value;
}

export async function verifyHttpAppCheckIfRequired(
  request: Request,
): Promise<void> {
  if (!REQUIRE_APP_CHECK.value()) {
    return;
  }

  const token = requestHeader(request, "X-Firebase-AppCheck");
  if (!token) {
    throw new HttpsError("unauthenticated", "App Check token required");
  }

  try {
    await admin.appCheck().verifyToken(token);
  } catch {
    throw new HttpsError("permission-denied", "Invalid App Check token");
  }
}

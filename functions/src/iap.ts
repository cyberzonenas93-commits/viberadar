import {
  APIException,
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
  Status,
  VerificationException,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
  type StatusResponse,
} from "@apple/app-store-server-library";
import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { createHash } from "crypto";
import { readFileSync } from "fs";
import { join } from "path";

import {
  APP_STORE_APP_APPLE_ID,
  APP_STORE_BUNDLE_ID,
  APP_STORE_ENVIRONMENT,
  APP_STORE_ISSUER_ID,
  APP_STORE_KEY_ID,
  APP_STORE_PRIVATE_KEY,
  getAppStoreProductIds,
  normalizeSecretValue,
} from "./lib/config";
import { appClientCallableOptions } from "./lib/appCheck";
import { requireFullCallableAccount } from "./lib/auth";
import {
  entitlementIsActive,
  type EntitlementTier,
} from "./lib/entitlements";

type AppleEnvironmentName = "Production" | "Sandbox";

interface SyncAppStorePurchaseData {
  transactionId?: string;
  productId?: string;
  environment?: string;
}

export interface AppleEntitlementSnapshot {
  tier: EntitlementTier;
  active: boolean;
  status: "active" | "billing_retry" | "grace_period" | "expired" | "revoked";
  productId: string;
  transactionId: string;
  originalTransactionId: string;
  environment: AppleEnvironmentName;
  expiresAt: Date | null;
}

const PRODUCT_TO_TIER: Record<string, EntitlementTier> = {
  viberadar_pro_monthly: "pro",
  viberadar_pro_yearly: "pro",
  viberadar_studio_monthly: "studio",
  viberadar_studio_yearly: "studio",
};

const APPLE_ROOT_CERT_FILES = [
  "AppleIncRootCertificate.cer",
  "AppleRootCA-G2.cer",
  "AppleRootCA-G3.cer",
];

let appleRootCertificateCache: Buffer[] | null = null;

function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

export function appAccountTokenForUid(uid: string): string {
  const bytes = [...createHash("sha256").update(`viberadar:${uid}`).digest()]
    .slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join("-");
}

export function assertAppAccountTokenMatches(
  transaction: Pick<JWSTransactionDecodedPayload, "appAccountToken">,
  uid: string,
): void {
  const expected = appAccountTokenForUid(uid);
  if (!transaction.appAccountToken) {
    throw new HttpsError(
      "failed-precondition",
      "Transaction is missing the required account token",
    );
  }
  if (transaction.appAccountToken !== expected) {
    throw new HttpsError(
      "permission-denied",
      "Transaction account token mismatch",
    );
  }
}

export function tierForAppStoreProduct(
  productId: string,
  allowedProductIds = getAppStoreProductIds(),
): EntitlementTier {
  if (!allowedProductIds.includes(productId)) {
    throw new HttpsError("invalid-argument", "Unsupported App Store product");
  }
  const tier = PRODUCT_TO_TIER[productId];
  if (!tier) {
    throw new HttpsError("invalid-argument", "Unknown App Store product");
  }
  return tier;
}

export function decodeJwsPayload<T extends object>(signedPayload: string): T {
  const parts = signedPayload.split(".");
  if (parts.length !== 3 || !parts[1]) {
    throw new HttpsError("invalid-argument", "Malformed App Store signed data");
  }

  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")) as T;
  } catch {
    throw new HttpsError("invalid-argument", "Invalid App Store signed data");
  }
}

export function appleEnvironmentFromString(value?: string): Environment {
  const normalized = (value ?? APP_STORE_ENVIRONMENT.value())
    .trim()
    .toLowerCase();
  if (normalized === "sandbox") return Environment.SANDBOX;
  if (normalized === "production") return Environment.PRODUCTION;
  throw new HttpsError("invalid-argument", "Unsupported App Store environment");
}

function appleEnvironmentName(environment: Environment): AppleEnvironmentName {
  return environment === Environment.SANDBOX ? "Sandbox" : "Production";
}

export function appStoreStatusFromLatestTransaction(input: {
  transaction: JWSTransactionDecodedPayload;
  subscriptionStatus?: Status | number;
  now?: Date;
}): AppleEntitlementSnapshot["status"] {
  if (input.transaction.revocationDate != null) return "revoked";

  switch (input.subscriptionStatus) {
    case Status.ACTIVE:
      return "active";
    case Status.BILLING_RETRY:
      return "billing_retry";
    case Status.BILLING_GRACE_PERIOD:
      return "grace_period";
    case Status.REVOKED:
      return "revoked";
    case Status.EXPIRED:
      return "expired";
  }

  const nowMs = (input.now ?? new Date()).getTime();
  const expiresMs = input.transaction.expiresDate;
  if (typeof expiresMs === "number" && expiresMs <= nowMs) return "expired";
  return "active";
}

export function appStoreStatusIsActive(
  status: AppleEntitlementSnapshot["status"],
): boolean {
  return (
    status === "active" ||
    status === "billing_retry" ||
    status === "grace_period"
  );
}

function normalizePrivateKey(value: string): string {
  return value.replace(/\\n/g, "\n");
}

function appStoreClient(environment: Environment): AppStoreServerAPIClient {
  const issuerId = normalizeSecretValue(APP_STORE_ISSUER_ID.value());
  const keyId = normalizeSecretValue(APP_STORE_KEY_ID.value());
  const privateKey = normalizeSecretValue(APP_STORE_PRIVATE_KEY.value());
  const bundleId = APP_STORE_BUNDLE_ID.value().trim();

  if (!issuerId || !keyId || !privateKey || !bundleId) {
    throw new HttpsError(
      "failed-precondition",
      "App Store Server API credentials are not configured",
    );
  }

  return new AppStoreServerAPIClient(
    normalizePrivateKey(privateKey),
    keyId,
    issuerId,
    bundleId,
    environment,
  );
}

function appleRootCertificates(): Buffer[] {
  if (appleRootCertificateCache) return appleRootCertificateCache;
  appleRootCertificateCache = APPLE_ROOT_CERT_FILES.map((filename) => {
    try {
      return readFileSync(join(__dirname, "..", "certs", filename));
    } catch {
      throw new HttpsError(
        "failed-precondition",
        `Missing Apple root certificate asset: ${filename}`,
      );
    }
  });
  return appleRootCertificateCache;
}

function appAppleIdForSignedData(environment: Environment): number | undefined {
  if (environment === Environment.SANDBOX) return undefined;
  const appAppleId = APP_STORE_APP_APPLE_ID.value();
  if (!Number.isInteger(appAppleId) || appAppleId <= 0) {
    throw new HttpsError(
      "failed-precondition",
      "APP_STORE_APP_APPLE_ID is required for production signed-data verification",
    );
  }
  return appAppleId;
}

function signedDataVerifier(environment: Environment): SignedDataVerifier {
  return new SignedDataVerifier(
    appleRootCertificates(),
    true,
    environment,
    APP_STORE_BUNDLE_ID.value().trim(),
    appAppleIdForSignedData(environment),
  );
}

function signedDataVerificationError(error: unknown): HttpsError {
  if (error instanceof HttpsError) return error;
  if (error instanceof VerificationException) {
    return new HttpsError(
      "permission-denied",
      "Unable to verify signed App Store data",
      { status: error.status },
    );
  }
  return new HttpsError("permission-denied", "Unable to verify signed App Store data");
}

async function verifySignedTransaction(
  signedTransactionInfo: string,
  environment: Environment,
): Promise<JWSTransactionDecodedPayload> {
  try {
    return await signedDataVerifier(environment).verifyAndDecodeTransaction(
      signedTransactionInfo,
    );
  } catch (error) {
    throw signedDataVerificationError(error);
  }
}

async function verifySignedNotification(
  signedPayload: string,
): Promise<ResponseBodyV2DecodedPayload> {
  const decodedForEnvironment =
    decodeJwsPayload<ResponseBodyV2DecodedPayload>(signedPayload);
  const environment = appleEnvironmentFromString(
    decodedForEnvironment.data?.environment,
  );
  try {
    return await signedDataVerifier(environment).verifyAndDecodeNotification(
      signedPayload,
    );
  } catch (error) {
    throw signedDataVerificationError(error);
  }
}

function preferredEnvironments(environment: Environment): Environment[] {
  return environment === Environment.SANDBOX
    ? [Environment.SANDBOX, Environment.PRODUCTION]
    : [Environment.PRODUCTION, Environment.SANDBOX];
}

function subscriptionStatusForTransaction(
  response: StatusResponse | null,
  originalTransactionId: string,
): Status | number | undefined {
  for (const group of response?.data ?? []) {
    for (const item of group.lastTransactions ?? []) {
      if (item.originalTransactionId === originalTransactionId) {
        return item.status;
      }
    }
  }
  return undefined;
}

async function fetchTransactionFromApple(
  transactionId: string,
  requestedEnvironment: Environment,
): Promise<{
  environment: Environment;
  transaction: JWSTransactionDecodedPayload;
  statusResponse: StatusResponse | null;
}> {
  let lastError: unknown;
  for (const environment of preferredEnvironments(requestedEnvironment)) {
    try {
      const client = appStoreClient(environment);
      const transactionInfo = await client.getTransactionInfo(transactionId);
      if (!transactionInfo.signedTransactionInfo) {
        throw new HttpsError("not-found", "App Store transaction not found");
      }
      const transaction = await verifySignedTransaction(
        transactionInfo.signedTransactionInfo,
        environment,
      );
      const originalTransactionId =
        transaction.originalTransactionId ?? transaction.transactionId;
      let statusResponse: StatusResponse | null = null;
      if (originalTransactionId) {
        statusResponse = await client.getAllSubscriptionStatuses(
          originalTransactionId,
        );
      }
      return { environment, transaction, statusResponse };
    } catch (error) {
      lastError = error;
      if (error instanceof HttpsError) throw error;
      if (error instanceof APIException && error.httpStatusCode < 500) {
        continue;
      }
    }
  }

  throw new HttpsError("not-found", "Unable to verify App Store transaction", {
    reason: String(lastError),
  });
}

function dateFromMillis(value: number | undefined): Date | null {
  if (typeof value !== "number") return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function timestampOrNull(date: Date | null): Timestamp | null {
  return date == null ? null : Timestamp.fromDate(date);
}

export function buildAppleEntitlementSnapshot(input: {
  transaction: JWSTransactionDecodedPayload;
  subscriptionStatus?: Status | number;
  environment: Environment;
  allowedProductIds?: string[];
  now?: Date;
}): AppleEntitlementSnapshot {
  const transactionId = input.transaction.transactionId;
  const originalTransactionId =
    input.transaction.originalTransactionId ?? input.transaction.transactionId;
  const productId = input.transaction.productId;
  if (!transactionId || !originalTransactionId || !productId) {
    throw new HttpsError(
      "invalid-argument",
      "App Store transaction is missing required identifiers",
    );
  }

  const status = appStoreStatusFromLatestTransaction({
    transaction: input.transaction,
    subscriptionStatus: input.subscriptionStatus,
    now: input.now,
  });

  return {
    tier: tierForAppStoreProduct(productId, input.allowedProductIds),
    active: appStoreStatusIsActive(status),
    status,
    productId,
    transactionId,
    originalTransactionId,
    environment: appleEnvironmentName(input.environment),
    expiresAt: dateFromMillis(input.transaction.expiresDate),
  };
}

export function shouldPreserveManualEntitlement(
  data: Record<string, unknown> | undefined,
  now = new Date(),
): boolean {
  return data?.provider === "manual_admin_grant" && entitlementIsActive(data, now);
}

async function writeEntitlement(input: {
  uid: string;
  transaction: JWSTransactionDecodedPayload;
  snapshot: AppleEntitlementSnapshot;
}): Promise<void> {
  const entitlementRef = db().collection("entitlements").doc(input.uid);
  const originalRef = db()
    .collection("app_store_transactions")
    .doc(input.snapshot.originalTransactionId);
  const eventRef = originalRef
    .collection("events")
    .doc(input.snapshot.transactionId);

  await db().runTransaction(async (tx) => {
    const originalSnap = await tx.get(originalRef);
    const entitlementSnap = await tx.get(entitlementRef);
    const existingUid = originalSnap.get("uid") as string | undefined;
    if (existingUid && existingUid !== input.uid) {
      throw new HttpsError(
        "permission-denied",
        "This App Store purchase is already linked to another account",
      );
    }

    tx.set(
      originalRef,
      {
        uid: input.uid,
        provider: "apple_app_store",
        originalTransactionId: input.snapshot.originalTransactionId,
        productId: input.snapshot.productId,
        environment: input.snapshot.environment,
        status: input.snapshot.status,
        active: input.snapshot.active,
        expiresAt: timestampOrNull(input.snapshot.expiresAt),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    tx.set(
      eventRef,
      {
        uid: input.uid,
        provider: "apple_app_store",
        transactionId: input.snapshot.transactionId,
        originalTransactionId: input.snapshot.originalTransactionId,
        productId: input.snapshot.productId,
        environment: input.snapshot.environment,
        status: input.snapshot.status,
        active: input.snapshot.active,
        expiresAt: timestampOrNull(input.snapshot.expiresAt),
        purchaseDate: timestampOrNull(
          dateFromMillis(input.transaction.purchaseDate),
        ),
        revocationDate: timestampOrNull(
          dateFromMillis(input.transaction.revocationDate),
        ),
        storefront: input.transaction.storefront ?? null,
        transactionReason: input.transaction.transactionReason ?? null,
        syncedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const existingEntitlement = entitlementSnap.data() as
      | Record<string, unknown>
      | undefined;
    if (!shouldPreserveManualEntitlement(existingEntitlement)) {
      tx.set(
        entitlementRef,
        {
          tier: input.snapshot.active ? input.snapshot.tier : "free",
          active: input.snapshot.active,
          status: input.snapshot.status,
          provider: "apple_app_store",
          productId: input.snapshot.productId,
          transactionId: input.snapshot.transactionId,
          originalTransactionId: input.snapshot.originalTransactionId,
          environment: input.snapshot.environment,
          expiresAt: timestampOrNull(input.snapshot.expiresAt),
          lastVerifiedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  });
}

export const syncAppStorePurchase = onCall(
  {
    region: "us-central1",
    secrets: [APP_STORE_ISSUER_ID, APP_STORE_KEY_ID, APP_STORE_PRIVATE_KEY],
    timeoutSeconds: 60,
    ...appClientCallableOptions,
  },
  async (
    request: CallableRequest<SyncAppStorePurchaseData>,
  ): Promise<AppleEntitlementSnapshot> => {
    const auth = requireFullCallableAccount(
      request.auth,
      "A full account is required to sync App Store purchases.",
    );

    const transactionId = (request.data?.transactionId ?? "").trim();
    if (!/^[A-Za-z0-9_.-]{3,128}$/.test(transactionId)) {
      throw new HttpsError("invalid-argument", "transactionId is required");
    }

    const requestedEnvironment = appleEnvironmentFromString(
      request.data?.environment,
    );
    const { environment, transaction, statusResponse } =
      await fetchTransactionFromApple(transactionId, requestedEnvironment);

    const bundleId = APP_STORE_BUNDLE_ID.value().trim();
    if (transaction.bundleId !== bundleId) {
      throw new HttpsError("permission-denied", "Transaction bundle mismatch");
    }

    if (
      request.data?.productId &&
      transaction.productId !== request.data.productId
    ) {
      throw new HttpsError("permission-denied", "Transaction product mismatch");
    }
    assertAppAccountTokenMatches(transaction, auth.uid);

    const snapshot = buildAppleEntitlementSnapshot({
      transaction,
      subscriptionStatus: subscriptionStatusForTransaction(
        statusResponse,
        transaction.originalTransactionId ?? transaction.transactionId ?? "",
      ),
      environment,
    });

    await writeEntitlement({
      uid: auth.uid,
      transaction,
      snapshot,
    });

    return snapshot;
  },
);

export const appStoreServerNotification = onRequest(
  {
    region: "us-central1",
    secrets: [APP_STORE_ISSUER_ID, APP_STORE_KEY_ID, APP_STORE_PRIVATE_KEY],
    timeoutSeconds: 60,
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("Method not allowed");
      return;
    }

    const signedPayload =
      typeof request.body?.signedPayload === "string"
        ? request.body.signedPayload
        : undefined;
    if (!signedPayload) {
      response.status(400).send("signedPayload is required");
      return;
    }

    let notification: ResponseBodyV2DecodedPayload;
    try {
      notification = await verifySignedNotification(signedPayload);
    } catch (error) {
      logger.warn("Rejected unverifiable App Store notification", error);
      response.status(400).send("signedPayload could not be verified");
      return;
    }
    const signedTransactionInfo = notification.data?.signedTransactionInfo;
    if (!signedTransactionInfo) {
      logger.info("App Store notification without transaction info", {
        notificationType: notification.notificationType,
        subtype: notification.subtype,
      });
      response.status(204).send();
      return;
    }

    const requestedEnvironment = appleEnvironmentFromString(
      notification.data?.environment,
    );
    let notifiedTransaction: JWSTransactionDecodedPayload;
    try {
      notifiedTransaction = await verifySignedTransaction(
        signedTransactionInfo,
        requestedEnvironment,
      );
    } catch (error) {
      logger.warn("Rejected unverifiable App Store transaction notification", {
        notificationType: notification.notificationType,
        subtype: notification.subtype,
        error,
      });
      response.status(400).send("signedTransactionInfo could not be verified");
      return;
    }
    if (notifiedTransaction.bundleId !== APP_STORE_BUNDLE_ID.value().trim()) {
      response.status(400).send("transaction bundle mismatch");
      return;
    }
    const transactionId = notifiedTransaction.transactionId;
    const originalTransactionId =
      notifiedTransaction.originalTransactionId ?? transactionId;
    if (!transactionId || !originalTransactionId) {
      response.status(400).send("transaction identifiers are missing");
      return;
    }

    const originalRef = db()
      .collection("app_store_transactions")
      .doc(originalTransactionId);
    const originalSnap = await originalRef.get();
    const uid = originalSnap.get("uid") as string | undefined;
    if (!uid) {
      logger.info("Ignoring unlinked App Store notification", {
        transactionId,
        originalTransactionId,
      });
      response.status(204).send();
      return;
    }

    const { environment, transaction, statusResponse } =
      await fetchTransactionFromApple(transactionId, requestedEnvironment);
    const snapshot = buildAppleEntitlementSnapshot({
      transaction,
      subscriptionStatus: subscriptionStatusForTransaction(
        statusResponse,
        transaction.originalTransactionId ?? transaction.transactionId ?? "",
      ),
      environment,
    });
    await writeEntitlement({ uid, transaction, snapshot });

    logger.info("Processed App Store notification", {
      notificationType: notification.notificationType,
      subtype: notification.subtype,
      transactionId,
      originalTransactionId,
      uid,
      status: snapshot.status,
    });
    response.status(204).send();
  },
);

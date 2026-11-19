import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * notifyOnSharedSetlist — when a setlist is shared/updated on the phone↔desktop
 * pairing channel, push a notification to the OTHER paired side's devices.
 *
 * Self-shares (same account on both ends) notify no one — `lastEditedBy` is
 * excluded from the recipients, so you never get pinged for your own edit. Token
 * registration is phone-only today (see MessagingService), so this reaches the
 * recipient's phone; the desktop app surfaces the same arrival in-app via its
 * live Firestore stream.
 */
export const notifyOnSharedSetlist = onDocumentWritten(
  {
    document: "pairings/{pairingId}/setlists/{setlistId}",
    region: "us-central1",
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return; // deletion — nothing to notify

    const setlist = after.data() ?? {};
    const editorUid = setlist.lastEditedBy as string | undefined;
    const name = (setlist.name as string | undefined) ?? "A setlist";

    const { pairingId, setlistId } = event.params;
    const db = admin.firestore();

    const pairingSnap = await db.collection("pairings").doc(pairingId).get();
    const pairing = pairingSnap.data() ?? {};
    const desktopUid = pairing.desktopUid as string | undefined;
    const claimedByUid = pairing.claimedByUid as string | undefined;

    const recipients = [desktopUid, claimedByUid].filter(
      (uid): uid is string => !!uid && uid !== editorUid,
    );
    if (recipients.length === 0) return;

    const tokensByUser = new Map<string, string[]>();
    for (const uid of recipients) {
      const userSnap = await db.collection("users").doc(uid).get();
      const tokens =
        (userSnap.get("fcm_tokens") as string[] | undefined) ?? [];
      if (tokens.length > 0) tokensByUser.set(uid, tokens);
    }
    const allTokens = [...new Set([...tokensByUser.values()].flat())].filter(
      Boolean,
    );
    if (allTokens.length === 0) return;

    const response = await admin.messaging().sendEachForMulticast({
      tokens: allTokens,
      notification: {
        title: "New setlist ready",
        body: `"${name}" is ready to match & export.`,
      },
      data: { type: "shared_setlist", pairingId, setlistId },
      apns: { payload: { aps: { sound: "default" } } },
    });

    // Prune tokens FCM reports as permanently invalid.
    const stale: string[] = [];
    response.responses.forEach((r, i) => {
      const code = r.error?.code ?? "";
      if (
        !r.success &&
        (code.includes("registration-token-not-registered") ||
          code.includes("invalid-argument"))
      ) {
        stale.push(allTokens[i]);
      }
    });
    if (stale.length > 0) {
      await Promise.all(
        [...tokensByUser.keys()].map((uid) =>
          db
            .collection("users")
            .doc(uid)
            .set(
              {
                fcm_tokens:
                  admin.firestore.FieldValue.arrayRemove(...stale),
              },
              { merge: true },
            ),
        ),
      );
    }

    logger.info("notifyOnSharedSetlist sent", {
      recipients: recipients.length,
      tokens: allTokens.length,
      successCount: response.successCount,
      pruned: stale.length,
    });
  },
);

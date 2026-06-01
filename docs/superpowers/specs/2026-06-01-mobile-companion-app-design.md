# VibeRadar Mobile Companion App — Design Spec

- **Date:** 2026-06-01
- **Status:** Approved (design); pending spec review → implementation plan
- **Author:** brainstormed with the project owner

## 1. Goal & non-goals

**Goal.** A mobile companion to the existing VibeRadar macOS desktop app that lets a DJ **build and curate setlists on the go** and have them flow to/from their desktop. A setlist created on the phone shows up on the desktop; a setlist started on the desktop can be continued on the phone.

**Non-goals (v1).**
- **No track playback** on mobile (we show metadata and deep-link out to Spotify/Apple/YouTube).
- **No local library scanning, cue analysis, or Serato/VirtualDJ export on mobile** — those stay on the desktop, where the files and DJ software live.
- **No real-time "remote control"** of the desktop UI; control is asynchronous via the cloud.

## 2. Decisions (locked inputs)

| Decision | Choice |
|---|---|
| Control model | **Cloud sync** (async, via Firebase) — not a live LAN remote |
| Mobile scope (v1) | Build & sync setlists · edit desktop setlists · AI set builder · browse trending/artists |
| Platforms | **iOS first** (App Store), Android later — built cross-platform from day one |
| Code organization | **Approach 1**: one Flutter codebase, adaptive shell (desktop vs mobile) |
| Desktop↔phone link | **Pairing** — connects a desktop that is *not logged in* |
| Sync direction | **Bidirectional** live sync (start on either device, continue on the other) |

## 3. Architecture (Approach 1 — one codebase, adaptive shell)

One Flutter project. Add an iOS target (`flutter create --platforms=ios .`); Android added later to the same code.

- **Startup branch.** `main.dart` builds the same `ProviderScope`, runs the shared bootstrap/Firebase init, then selects the shell by form factor: mobile (iOS/Android) → new `MobileApp`; otherwise the existing `VibeShell`.
- **Reused verbatim:** all models, the Firestore repositories (`track`/`user`/`session`), `PlatformSearchService` (Spotify/Apple/YouTube), `AiCopilotService`, formatters, theme, Riverpod providers, auth.
- **Excluded on mobile** (guarded at call sites, never invoked): `LibraryScannerService` (`mdls`), all export services, cue writers, `dj_root_detection`, `desktop_drop`, `window_manager`. The macOS window setup in `main.dart` becomes desktop-only. Flutter drops these plugins' native side on iOS automatically — the rule is simply *don't call them on mobile*.
- **New mobile-only code** lives under `lib/ui/mobile/` so the desktop tree is untouched.

## 4. Mobile app structure (screens)

`MobileShell` with a 4-tab bottom nav matching scope. Each tab is a thin, touch-first view over an existing provider/service.

- **Setlists** — the shared/synced setlists; create, open editor (drag-reorder, swipe-remove, rename), per-setlist sync chip. Editing desktop-made setlists happens here (same shared list). Entry point for "Connect a computer."
- **Search** — reuse `PlatformSearchService`; ＋ on a result adds it to the open setlist.
- **Trending** — reuse `trackStreamProvider` (Firestore); browse + add.
- **AI** — reuse `AiCopilotService`; prompt → drafted setlist → "Save as setlist."

## 5. Pairing & sync

### 5.1 Identity (anonymous auth)
On launch the **desktop signs in anonymously** to Firebase, giving each desktop a stable `uid` without the DJ logging in. **Requires enabling Anonymous Auth** in the Firebase project (currently disabled — the same gap behind the earlier desktop "guest" issues). The **phone keeps a real account** (needed for AI and personal library).

### 5.2 Pairing handshake (two callable Cloud Functions)
Functions are used so pairing codes can't be brute-forced and claims are atomic.
1. Desktop → `createPairing()` → server writes `pairings/{id} = {desktopUid, desktopName, code, status:'pending', expiresAt}` and returns a short 6-char code. Desktop displays a **QR (encoding the code) + the code**.
2. Phone scans the QR (or types the code) → `claimPairing(code)` → server verifies valid/unexpired/unclaimed, sets `claimedByUid = phoneUid`, `status:'active'`, `claimedAt`. The devices are now linked.

### 5.3 Firestore data model
- `pairings/{pairingId}`: `{ desktopUid, desktopName, code, status: pending|active|revoked, claimedByUid, createdAt, claimedAt, expiresAt }`
- `pairings/{pairingId}/setlists/{setlistId}`: a `Crate` (`name`, `tracks[]`, `updatedAt`, `lastEditedBy: uid`). **The shared workspace** — both devices read, write, and watch it.
- `users/{uid}/...saved_crates` (existing): the **phone's personal library** for unpaired use and backup.

On a successful pair, each side's existing setlists are mirrored into the shared subcollection; from then on it is the single live source of truth while paired.

### 5.4 Bidirectional sync & conflicts
Both devices subscribe to `pairings/{id}/setlists` via Firestore **live `.snapshots()`**, so an edit on either device appears on the other within seconds ("start on computer, continue on phone"). Simultaneous edits resolve **last-write-wins per setlist** (whole-document writes keyed on `updatedAt`) — acceptable for v1, since a DJ rarely edits the same list on two devices at once. Firestore offline persistence reconciles on reconnect.

### 5.5 Security rules (sketch — refine in implementation)
```
match /pairings/{pairingId} {
  allow read: if request.auth != null &&
    (request.auth.uid == resource.data.desktopUid ||
     request.auth.uid == resource.data.claimedByUid);
  allow write: if false; // create/claim go through Cloud Functions only

  match /setlists/{setlistId} {
    allow read, write: if request.auth != null && request.auth.uid in [
      get(/databases/$(database)/documents/pairings/$(pairingId)).data.desktopUid,
      get(/databases/$(database)/documents/pairings/$(pairingId)).data.claimedByUid
    ];
  }
}
```

## 6. Desktop + backend changes (this feature is not mobile-only)
- **Backend:** enable Anonymous Auth; add `createPairing` + `claimPairing` callable functions; add the `pairings/**` security rules.
- **Desktop app:** anonymous sign-in on launch; a "Pair a phone" screen (QR + code); a listener that ingests setlists from `pairings/{id}/setlists` into its crates and publishes its own crates up; an "unpair" control.
- **Mobile app:** "Connect a computer" flow (scan/enter code); paired-computers list with names; setlists work in the shared channel when paired, in the account library when not.

## 7. App Store (ASC) compliance
1. **Minimum functionality (4.2):** full search + AI + browse + edit — substantial, not a thin remote. ✅
2. **Standalone review (2.1):** everything works **unpaired**; pairing is optional. Provide a **demo account** + review note explaining pairing needs the companion desktop.
3. **Sign in with Apple (4.8):** because Google/email login is offered, **must also offer Sign in with Apple** on iOS (`sign_in_with_apple` + Apple provider in Firebase).
4. **Account deletion (5.1.1(v)):** in-app "Delete account" — wipe `users/{uid}` + the user's pairings/setlists, then `FirebaseAuth.user.delete()`.
5. **Privacy:** App Privacy nutrition label (email, user content/setlists, Firebase identifier) + hosted **Privacy Policy URL**. No ad/tracking SDKs → no ATT prompt.
6. **Third-party content:** **no playback = no music licensing.** Add Spotify/Apple/YouTube **attribution + "Open in…"** deep links and follow each API's branding terms.
7. **Camera (QR):** `NSCameraUsageDescription`, requested just-in-time on "Scan"; manual code entry always available.
8. **Encryption exemption:** `ITSAppUsesNonExemptEncryption = false` (standard HTTPS only).
9. **IAP:** none needed for free v1; a future "Pro" subscription would require Apple IAP.

## 8. iOS build & release
`flutter create --platforms=ios .` → register an iOS app in Firebase → `flutterfire configure` (adds iOS to `firebase_options.dart`) → enable **Anonymous Auth + Apple** provider → bundle ID, app icons, launch screen, Info.plist usage strings, encryption flag, Sign-in-with-Apple capability → Apple Developer membership + App Store Connect record → **TestFlight** beta with real DJs → submit for review.

## 9. Testing
- Reuse existing service tests.
- New widget tests: `MobileShell` navigation, setlist editor (drag-reorder/remove), "Connect a computer" claim flow (mocked functions), bidirectional sync (mocked Firestore snapshots).
- Manual/TestFlight: pair a desktop ↔ phone, edit on both, verify live two-way sync; account deletion; Sign in with Apple.

## 10. Open items / future
- **Android + Play Store** (data-safety form, signing) — same codebase, later pass.
- **Conflict UX** beyond last-write-wins (e.g., per-track merge) if real DJs hit it.
- **Multiple paired computers** per phone — model already supports it (one `pairings` doc per desktop); v1 UI can start with one and grow.
- **"Send to decks now"** beyond plain sync (e.g., flag a setlist for immediate desktop export) — optional enhancement on top of the shared channel.

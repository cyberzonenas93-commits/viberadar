# VibeRadar Mobile Companion App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an iOS companion app (from the existing Flutter codebase) that lets a DJ build/edit setlists on the go and sync them bidirectionally with a paired, logged-out desktop.

**Architecture:** Single codebase, adaptive shell (Approach 1). On mobile, a lean `MobileShell` reuses existing models/services/providers; desktop-only services are never called. Setlists are `Crate`s; sync runs through Firebase (account library when unpaired, a bidirectional `pairings/{id}/setlists` channel when paired).

**Tech Stack:** Flutter (Dart), Riverpod 3, Firebase (Auth, Firestore, Cloud Functions/TypeScript), Sign in with Apple.

**Reference spec:** `docs/superpowers/specs/2026-06-01-mobile-companion-app-design.md`

---

## Phasing & external prerequisites

This plan is split into three phases. **Phase 1 is fully buildable and testable now.** Phases 2–3 depend on actions only the owner can do; those are listed up front so they can happen in parallel.

**Owner prerequisites (not codeable by the agent):**
- [ ] **Phase 2:** In Firebase console → Authentication → enable **Anonymous** provider (currently disabled).
- [ ] **Phase 3:** Enroll in the **Apple Developer Program**; create an **App Store Connect** app record; in Firebase console enable the **Apple** auth provider; create the Sign-in-with-Apple **Service ID + key**; host a **Privacy Policy** URL.
- [ ] **Phase 3 (agent-assisted):** Register an iOS app in Firebase via `flutterfire configure` (needs `dart pub global activate flutterfire_cli`); add `GoogleService-Info.plist` to `ios/Runner`.

## File structure (new / modified)

**Phase 1**
- Create `lib/core/platform.dart` — `isMobileForm` form-factor helper.
- Modify `lib/ui/auth/auth_gate.dart` — branch to `MobileShell` on mobile.
- Create `lib/ui/mobile/mobile_shell.dart` — bottom-nav scaffold (Setlists / Search / Trending / AI).
- Create `lib/ui/mobile/setlists_tab.dart`, `setlist_editor.dart`, `search_tab.dart`, `trending_tab.dart`, `ai_tab.dart`.
- Create `lib/providers/setlist_provider.dart` — setlist CRUD over the account crate store.
- Create `ios/` (via `flutter create --platforms=ios .`).
- Tests under `test/mobile/` + `test/core/platform_test.dart`.

**Phase 2**
- Create `functions/src/pairing.ts` — `createPairing` + `claimPairing` callables; export from `functions/src/index.ts`.
- Modify `firestore.rules` — `pairings/**`.
- Create `lib/services/pairing_service.dart` — client calls + shared-setlist sync.
- Create `lib/ui/mobile/connect_computer_sheet.dart` — QR/code claim UI.
- Create `lib/ui/shell/pair_phone_screen.dart` — desktop pairing screen + receiver.
- Modify `lib/app/bootstrap.dart` — desktop anonymous sign-in.

**Phase 3**
- Modify `ios/Runner/Info.plist` — usage strings, encryption flag.
- Create `lib/services/apple_signin_service.dart`; modify auth UI + `session_repository.dart`.
- Create `lib/services/account_deletion_service.dart`; add Settings entry.
- Modify search/trending cards — source attribution + "Open in…" links.

---

# PHASE 1 — Mobile foundation & setlist building (buildable now)

### Task 1.1: iOS scaffold + form-factor helper

**Files:**
- Create: `ios/` (generated)
- Create: `lib/core/platform.dart`
- Test: `test/core/platform_test.dart`

- [ ] **Step 1: Scaffold the iOS target**

Run: `flutter create --platforms=ios .`
Expected: creates `ios/` only; `lib/`, `macos/`, `pubspec.yaml` untouched. Verify with `git status` that no existing tracked file under `lib/` changed.

- [ ] **Step 2: Write the failing test**

```dart
// test/core/platform_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/core/platform.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('isMobileForm is true on iOS/Android, false on desktop', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isMobileForm, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isMobileForm, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isMobileForm, isFalse);
  });
}
```

- [ ] **Step 3: Run test, verify it fails** — `flutter test test/core/platform_test.dart` → FAIL (`platform.dart` missing).

- [ ] **Step 4: Implement**

```dart
// lib/core/platform.dart
import 'package:flutter/foundation.dart';

/// True when running on a phone/tablet form factor (iOS or Android).
/// Desktop (macOS/Windows/Linux) and web return false.
bool get isMobileForm =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);
```

- [ ] **Step 5: Run test, verify it passes.**

- [ ] **Step 6: Commit** — `git add lib/core/platform.dart test/core/platform_test.dart ios && git commit -m "feat(mobile): iOS target + form-factor helper"`

---

### Task 1.2: Adaptive shell branch + MobileShell skeleton

**Files:**
- Modify: `lib/ui/auth/auth_gate.dart` (the `return VibeShell(...)` at ~line 117)
- Create: `lib/ui/mobile/mobile_shell.dart`
- Test: `test/mobile/adaptive_shell_test.dart`

- [ ] **Step 1: Failing test** — pump `AuthGate` with an authenticated session; with `debugDefaultTargetPlatformOverride = iOS` expect `find.byType(MobileShell)`; with `macOS` expect `find.byType(VibeShell)`. (Override `sessionProvider` with an authenticated `SessionState`, and the repository providers with mock repos so the tree builds.)

- [ ] **Step 2: Run, verify fail** (MobileShell undefined).

- [ ] **Step 3: Create the skeleton**

```dart
// lib/ui/mobile/mobile_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';

class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});
  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  int _index = 0;
  static const _tabs = ['Setlists', 'Search', 'Trending', 'AI'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          Center(child: Text('Setlists')), // replaced in Task 1.4
          Center(child: Text('Search')),   // Task 1.6
          Center(child: Text('Trending')), // Task 1.7
          Center(child: Text('AI')),       // Task 1.8
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.queue_music), label: 'Setlists'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.local_fire_department), label: 'Trending'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'AI'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Branch the shell** in `auth_gate.dart`. Add `import '../../core/platform.dart';` and `import '../mobile/mobile_shell.dart';`. Replace the authenticated `return VibeShell(...)` with:

```dart
// On mobile the phone must be signed in (no guest); desktop keeps its behavior.
if (isMobileForm) {
  return session?.isAuthenticated == true
      ? const MobileShell()
      : _LoginScreen(statusMessage: widget.statusMessage);
}
return VibeShell(
  statusMessage: widget.statusMessage,
  isDemoMode: widget.isDemoMode,
);
```

- [ ] **Step 5: Run the adaptive-shell test + full suite (`flutter test`) — verify pass, desktop unaffected.**
- [ ] **Step 6: Commit** — `git commit -am "feat(mobile): adaptive shell selects MobileShell on phones"`

---

### Task 1.3: Setlist provider (account-backed CRUD)

**Files:**
- Create: `lib/providers/setlist_provider.dart`
- Test: `test/mobile/setlist_provider_test.dart`

The setlist list is the signed-in user's `Crate`s. Read from `userProfileProvider.value.savedCrates`; mutate via `userRepositoryProvider.saveCrate`. (Reuses existing `UserProfile.savedCrates` + `FirestoreUserRepository.saveCrate`.)

- [ ] **Step 1: Failing test** — with a `MockUserRepository` seeded with two crates, `ref.read(setlistsProvider)` returns them sorted by `updatedAt` desc; `createSetlist('Sunset')` then read shows three.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement**

```dart
// lib/providers/setlist_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/crate.dart';
import 'app_state.dart';
import 'repositories.dart';

final setlistsProvider = Provider<List<Crate>>((ref) {
  final crates = ref.watch(userProfileProvider).value?.savedCrates ?? const [];
  return [...crates]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});

final setlistActionsProvider = Provider<SetlistActions>((ref) => SetlistActions(ref));

class SetlistActions {
  SetlistActions(this._ref);
  final Ref _ref;

  Future<void> save(Crate crate) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null || !session.isAuthenticated) return;
    await _ref.read(userRepositoryProvider).saveCrate(
          userId: session.userId,
          fallbackName: session.displayName,
          crate: crate.copyWith(updatedAt: _now(_ref)),
        );
  }

  Future<void> create(String name) =>
      save(Crate(id: const Uuid().v4(), name: name, context: 'Open format',
          trackIds: const [], createdAt: _now(_ref), updatedAt: _now(_ref)));
}

DateTime _now(Ref ref) => DateTime.now();
```

> Note: confirm `Crate.copyWith` exists; if not, add it to `lib/models/crate.dart` in this task (fields: name, context, trackIds, updatedAt).

- [ ] **Step 4: Run, verify pass.** **Step 5: Commit.**

---

### Task 1.4: Setlists tab (list + create)

**Files:** Create `lib/ui/mobile/setlists_tab.dart`; Test `test/mobile/setlists_tab_test.dart`. Wire into `mobile_shell.dart` (replace the Setlists placeholder).

- [ ] **Step 1: Failing widget test** — override providers so `setlistsProvider` yields two named crates; pump `SetlistsTab`; expect both names visible and a "+" FAB.
- [ ] **Step 2: fail → Step 3: implement** a `ConsumerWidget` listing `ref.watch(setlistsProvider)` (each row: name, track count, `updatedAt`), a FAB opening a name dialog → `setlistActionsProvider.create(name)`, tapping a row pushes `SetlistEditor` (Task 1.5). Empty state: "No setlists yet — tap ＋."
- [ ] **Step 4: pass → Step 5: commit.**

---

### Task 1.5: Setlist editor (reorder / remove / rename)

**Files:** Create `lib/ui/mobile/setlist_editor.dart`; Test `test/mobile/setlist_editor_test.dart`.

- [ ] **Step 1: Failing test** — given a crate with trackIds `[a,b,c]` and a track lookup override, pump editor; simulate remove of `b`; assert `save` called with `[a,c]`; rename updates `name`.
- [ ] **Step 2: fail → Step 3: implement** a `ReorderableListView` of the crate's tracks (resolve display via `trackStreamProvider` map by id), swipe-to-remove, an editable title, "sync chip" placeholder. Every mutation calls `setlistActionsProvider.save(updatedCrate)`.
- [ ] **Step 4: pass → Step 5: commit.**

---

### Task 1.6: Search tab (reuse `PlatformSearchService`, add to setlist)

**Files:** Create `lib/ui/mobile/search_tab.dart`; Test `test/mobile/search_tab_test.dart`.

- [ ] **Step 1: Failing test** — inject a fake search service returning two results; type a query; expect both rendered with "Open in…" affordance and a ＋ to add.
- [ ] **Step 2: fail → Step 3: implement** a debounced search box over `PlatformSearchService.search`, result rows (artwork/title/artist + Spotify/Apple/YouTube deep-link buttons), ＋ → choose target setlist → add the track id. **Track-id resolution for external results reuses the desktop's existing online-track-resolution path** (the same mechanism behind commit `14f0bcf`/`d9af9da`); extract that into a shared helper if it currently lives in desktop-only code, and call it here. (If extraction is non-trivial, scope Phase 1 "add" to Firestore/trending tracks and file search-result-add as the first Phase 1.5 task.)
- [ ] **Step 4: pass → Step 5: commit.**

---

### Task 1.7: Trending tab (reuse `trackStreamProvider`, add to setlist)

**Files:** Create `lib/ui/mobile/trending_tab.dart`; Test `test/mobile/trending_tab_test.dart`.

- [ ] **Step 1: Failing test** — override `trackStreamProvider` with sample tracks; pump; expect a sorted list and a working ＋ that adds the track id to a chosen setlist.
- [ ] **Step 2: fail → Step 3: implement** a touch-optimized list of `ref.watch(trackStreamProvider)` sorted by `trendScore`, reusing `formatBpm`/source badges, ＋ adds to a setlist (these tracks already have Firestore ids — no resolution needed).
- [ ] **Step 4: pass → Step 5: commit.**

---

### Task 1.8: AI tab (reuse `AiCopilotService`, draft → save)

**Files:** Create `lib/ui/mobile/ai_tab.dart`; Test `test/mobile/ai_tab_test.dart`.

- [ ] **Step 1: Failing test** — inject a fake copilot returning a fixed crate JSON block; submit a prompt; assert a draft setlist renders with a "Save as setlist" button that calls `setlistActionsProvider.save`.
- [ ] **Step 2: fail → Step 3: implement** a prompt field → `AiCopilotService.chat`/`parseCommand`; render the drafted track list; "Save as setlist" persists it as a `Crate`. (Reuses the exact OpenAI path already verified working.)
- [ ] **Step 4: pass → Step 5: commit.**

---

### Task 1.9: Phase-1 verification gate

- [ ] `flutter analyze` → 0 errors.
- [ ] `flutter test` → all pass (desktop suite + new mobile tests).
- [ ] `flutter build ios --simulator --no-codesign` → builds (proves the iOS target compiles; full device run waits on Phase 3 Firebase/signing).
- [ ] Commit any cleanup. **Phase 1 done: a usable, standalone setlist-builder on iOS simulator.**

---

# PHASE 2 — Pairing & bidirectional sync

**Prerequisite:** Anonymous Auth enabled in Firebase console.

### Task 2.1: Desktop anonymous identity
- Modify `lib/app/bootstrap.dart`: after Firebase init on **desktop**, if `FirebaseAuth.instance.currentUser == null`, call `signInAnonymously()` so each desktop has a stable `uid`. Guard with `!isMobileForm`. Test: bootstrap result still wires real repos; add a unit test around the helper that decides "should anon sign-in" (true on desktop + unauthenticated).

### Task 2.2: Pairing Cloud Functions (TypeScript, TDD with emulator)
- Create `functions/src/pairing.ts`:
  - `createPairing` (callable, requires `context.auth`): generate a unique 6-char code, write `pairings/{id} = {desktopUid: auth.uid, desktopName, code, status:'pending', createdAt, expiresAt: +10min}`, return `{pairingId, code}`.
  - `claimPairing` (callable, requires `context.auth`): look up by `code`, verify `status=='pending'` and not expired, transactionally set `claimedByUid: auth.uid`, `status:'active'`, `claimedAt`. Return the pairing. Reject unknown/expired/claimed codes.
- Export both from `functions/src/index.ts`.
- Tests: `functions/test/pairing.test.ts` against the **Firestore emulator** (`firebase emulators:exec`): create→claim happy path; expired code rejected; double-claim rejected; unauthenticated rejected.
- Verify `npx tsc --noEmit` clean.

### Task 2.3: Security rules for `pairings/**`
- Add the `pairings/{pairingId}` + nested `setlists/{setlistId}` rules from the spec (§5.5) to `firestore.rules`.
- Tests: `@firebase/rules-unit-testing` — desktopUid and claimedByUid can read/write `setlists`; a third uid cannot; client cannot create/claim `pairings` directly (functions only).

### Task 2.4: Client pairing service + shared-setlist sync
- Create `lib/services/pairing_service.dart`: `createPairing()` (desktop) and `claimPairing(code)` (phone) via `FirebaseFunctions`; `watchSharedSetlists(pairingId)` → `pairings/{id}/setlists` snapshots; `pushSetlist(pairingId, crate)`; `removeSetlist`. Last-write-wins on `updatedAt`.
- Provider exposing the active pairing(s) per device.
- Tests with a fake functions/Firestore layer: claim stores the pairing locally; push writes the crate doc; incoming snapshot updates the shared list.

### Task 2.5: Desktop "Pair a phone" screen + receiver
- Create `lib/ui/shell/pair_phone_screen.dart`: button → `createPairing()` → show QR (encode the code; add `qr_flutter`) + the code; subscribe to `pairings/{id}/setlists` and merge incoming setlists into desktop crates; "unpair."
- Wire an entry point in the desktop shell (e.g., Settings/Sidebar).
- Widget test: shows code after createPairing; ingests an incoming setlist doc into the crate list.

### Task 2.6: Mobile "Connect a computer" + send/sync
- Create `lib/ui/mobile/connect_computer_sheet.dart`: scan QR (`mobile_scanner`) or type code → `claimPairing` → store paired computer(s) with names.
- In the Setlists tab/editor: when paired, read/write the **shared** `pairings/{id}/setlists` channel (bidirectional); the sync chip reflects state. Unpaired behavior (account library) unchanged.
- Widget tests: claim flow updates paired list; editing a setlist while paired writes to the shared channel; an incoming change updates the UI.

### Task 2.7: Phase-2 verification
- `flutter analyze` 0 errors; `flutter test` green; `npx tsc --noEmit` clean; emulator rules+functions tests green.
- Manual (emulator or live): desktop shows code → phone claims → edit on each side → appears on the other.

---

# PHASE 3 — ASC compliance & iOS release

**Prerequisites:** Apple Developer Program; App Store Connect record; Firebase Apple provider + Service ID/key; Privacy Policy URL; `flutterfire configure` for iOS.

### Task 3.1: Firebase iOS wiring
- `dart pub global activate flutterfire_cli`; `flutterfire configure` (select project `viberadar-462b8`, register iOS app) → updates `firebase_options.dart` + adds `GoogleService-Info.plist`. Verify desktop still launches with unchanged options.

### Task 3.2: Sign in with Apple
- Add `sign_in_with_apple`; create `lib/services/apple_signin_service.dart` (nonce + credential → `OAuthProvider("apple.com")` → Firebase). Add Apple capability/entitlement in `ios/Runner`. Add an "Sign in with Apple" button to the login UI (mobile). Test the nonce/credential mapping with a faked provider.

### Task 3.3: Account deletion (Guideline 5.1.1(v))
- Create `lib/services/account_deletion_service.dart`: delete `users/{uid}` (+ its crates), disable/delete the user's `pairings`/`setlists`, then `FirebaseAuth.user.delete()` (handle recent-login re-auth). Add a confirmation flow in mobile Settings. Tests with fakes: deletion removes user data + calls `user.delete()`.

### Task 3.4: Source attribution & deep links
- Update search/trending result cards to show **Spotify/Apple/YouTube attribution** and "Open in…" deep links per each provider's branding terms. Widget test asserts the correct link/label per source.

### Task 3.5: Info.plist & store metadata
- `ios/Runner/Info.plist`: `NSCameraUsageDescription` ("Scan the pairing code from your VibeRadar desktop app"), `ITSAppUsesNonExemptEncryption=false`, display name, launch screen, app icons (all sizes).
- App Store Connect: privacy nutrition label (email, user content, identifier), Privacy Policy URL, demo reviewer account + review note ("pairing needs the companion desktop; all features work standalone with this account").

### Task 3.6: Release
- `flutter build ipa` (signed) → upload to **TestFlight** → beta with real DJs → fix → submit for review.

---

## Self-review (against the spec)

- **Spec coverage:** control=cloud-sync (Phase 2 channel) ✓; scope build/edit/AI/browse (Tasks 1.4–1.8) ✓; iOS-first (Phase 1/3) ✓; Approach 1 adaptive shell (1.2) ✓; pairing for logged-out desktop (2.1–2.6) ✓; bidirectional last-write-wins (2.4/2.6) ✓; ASC items each map to Phase 3 tasks ✓.
- **Known soft spot (called out, not hidden):** external-result → `trackId` resolution in Task 1.6 — reuse the desktop's existing online-track-resolution; if extraction is heavy, defer search-result-add to a Phase 1.5 task and keep trending-add in Phase 1.
- **Type consistency:** `Crate` fields (`id,name,context,trackIds,createdAt,updatedAt`) used consistently; `setlistActionsProvider.save/create`, `pairing_service` method names consistent across tasks. Confirm/add `Crate.copyWith` in Task 1.3.

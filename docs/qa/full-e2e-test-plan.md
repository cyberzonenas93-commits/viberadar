# VibeRadar Full E2E Test Plan

This plan is the feature-by-feature checklist for validating VibeRadar across
desktop, web, Android, iOS, Firebase, and the DJ export workflows.

## Local Automated Gate

Run this before any manual feature pass:

```bash
./scripts/qa_local.sh
```

Default coverage:

- Flutter dependency resolution.
- Static analysis with `flutter analyze`.
- All Dart unit and widget tests with `flutter test`.
- Firebase Functions TypeScript build with `npm --prefix functions run build`.
- Flutter Web release build.
- macOS debug build.

Optional local builds:

```bash
QA_BUILD_ANDROID=1 ./scripts/qa_local.sh
QA_BUILD_IOS_SIM=1 ./scripts/qa_local.sh
QA_BUILD_ANDROID=1 QA_BUILD_IOS_SIM=1 ./scripts/qa_local.sh
```

## Required Test Data And Accounts

- Firebase project `viberadar-462b8` with Auth, Firestore, Storage, Hosting, and
  Functions enabled.
- Firebase Web app config for web builds and Android SHA fingerprints for Google
  sign-in.
- Apple Developer Services ID for web and Android Apple sign-in:
  `com.viberadar.signin`.
- Apple return URL:
  `https://viberadar-462b8.firebaseapp.com/__/auth/handler`.
- Google, Apple, email/password, and anonymous test users.
- Functions secrets for Spotify, YouTube, Apple Music, SoundCloud, and Beatport
  where those integrations are expected to return live data.
- A small local audio fixture folder with MP3, WAV, FLAC, M4A, duplicate tracks,
  files with missing metadata, non-ASCII filenames, and one corrupt/unsupported
  file.
- VirtualDJ and Serato fixture folders copied from safe test libraries, never a
  working DJ library.
- At least one Android emulator/device and one iOS simulator/device.

## Auth And Session

- Launch in demo/fallback mode with Firebase disabled and confirm demo data,
  sidebar navigation, and no crash.
- Email sign-up, sign-in, sign-out, wrong password, password reset if enabled,
  and account deletion.
- Google sign-in on macOS, web, Android, and iOS.
- Apple sign-in natively on iOS/macOS.
- Apple sign-in through Firebase OAuth on web and Android; confirm the return URL
  reaches `/__/auth/handler` and lands back in the app signed in.
- Anonymous/guest session: region changes, local selections, and blocked
  authenticated-only saves.
- Session persistence after app restart and browser refresh.

## Desktop macOS App

- Home: region selector, genre chips, top/rising/regional sections, track action
  menus, platform links, and detail panel activation.
- Trending: sorting, saved crate actions, watchlist toggles, and empty states.
- Search: Spotify, Apple Music, and YouTube results; merged duplicates; add to
  crate; open external platform links.
- Artists and For You: follow/unfollow artists, artist picker, recommendations,
  latest release, full catalog, and no-data states.
- Regions, Genres, Playlists, Greatest Of, and Set Builder: filters, generated
  results, save crate, and navigation to AI Copilot.
- AI Copilot: enter prompt, build draft set, parse crate block, save setlist,
  empty/error responses, and missing API key state.
- Library: folder scan, browser-safe import fallback where relevant, metadata,
  duplicate groups, search/filter/year filters, remove track, clear library,
  cache reload after restart.
- Hot cues: single-track cue generation, batch crate cue generation, cue rename,
  cue removal, VirtualDJ root detection, dry-run expectations, write success,
  invalid root, and backup restoration.
- Exports: Rekordbox XML, M3U, Traktor NML, Serato CSV, VirtualDJ XML/folder,
  Serato crate, TIDAL fallback, skipped tracks, physical crate copy, and alias
  link modes.
- Command palette: keyboard open, search, arrow navigation, enter activation,
  escape dismiss, no-results state.
- Drag/drop shell: supported audio file, directory, unsupported file, and missing
  path classification.
- Settings: API key save/delete, account sheet, theme/display options if present,
  and persistence after restart.

## Web App

- Build and serve `build/web`; verify first load, refresh on deep route, and
  service worker/cache behavior after rebuilding.
- Demo fallback without Firebase defines.
- Firebase web config with email, Google, Apple OAuth, and sign-out.
- Library import through file picker; confirm no desktop-only folder scan or
  Finder-reveal affordance is exposed as a broken action.
- Search, For You, AI, setlists, saved crates, watchlist, and exports that are
  download/browser-safe.
- Browser console has no uncaught errors during each major navigation path.

## Android

- Debug build installs and launches.
- Firebase config resolves, Google sign-in works, and Apple OAuth returns through
  Firebase.
- Mobile shell tabs: Setlists, Search, Trending, AI.
- Create/edit/delete setlists and save from Trending/Search/AI.
- Connect Computer: claim pairing code, display paired computer, push setlist,
  handle invalid/expired code.
- Rotation, small screen, large screen, back button, offline/reconnect behavior.

## iOS

- Simulator build launches without Firebase fallback errors.
- Native Apple sign-in works with bundle ID `com.viberadar.viberadar`.
- Google/email/guest sessions work.
- Mobile shell tabs, setlist editing, Search, Trending, AI, and Connect Computer.
- Account deletion and sign-out return to the auth flow.

## Firebase Functions And Rules

- Functions build succeeds.
- Emulator flow for `createPairing`, `claimPairing`, and setlist push.
- `spotifyProxy`, `appleProxy`, and `youtubeProxy` validate path/query handling,
  auth requirements, empty responses, rate-limit/error behavior, and malformed
  input.
- Scheduled/manual ingestion writes normalized tracks, preserves trend history,
  deduplicates title/artist, and skips optional providers with missing secrets.
- Firestore rules: authenticated user can read/write only allowed user-owned
  docs; public track reads work; pairings and shared setlists enforce ownership.
- Storage rules: uploads, artwork, and profile photos enforce expected ownership
  and content constraints.

## Release And Deployment

- macOS release script signs, notarizes, staples, creates DMG, and validates
  Gatekeeper.
- Web release build deploys to Firebase Hosting and refreshes without stale
  `main.dart.js`.
- Functions deploy predeploy build passes.
- Firestore indexes and rules deploy cleanly.
- Smoke test production URLs after deploy: auth, search, setlist save, pairing,
  and sign-out.

## Exit Criteria

- Local automated gate passes.
- Web, macOS, Android, and iOS smoke builds pass or have a documented external
  blocker.
- Every checklist item above has one of: pass, fail with linked issue, or blocked
  with the missing credential/device/service named.
- No production deploy until auth callbacks, Firebase rules, and pairing flows
  pass against `viberadar-462b8`.

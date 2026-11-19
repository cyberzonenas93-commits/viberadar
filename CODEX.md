# VibeRadar Engineering and Operations Memory

## Repository Structure

- `lib/`: Flutter app source.
- `lib/app/`: app bootstrap and root app wiring.
- `lib/core/`: platform helpers, config, theme, and utilities.
- `lib/models/`: domain models including `AppEntitlement` and uploaded/community models.
- `lib/providers/`: Riverpod providers/state, including billing and setlist state.
- `lib/providers/app_state.dart`: shared workspace/session/catalog providers. `appEntitlementProvider` reads backend-owned subscription state, `liveCatalogAccessProvider` centralizes guest/free/Pro catalog access, and `trackStreamProvider` returns mock preview data for guest/free users or `LiveTrackCatalogService` results for active Pro/Studio users.
- `lib/services/`: domain services and integrations, including `IapService` and `SetFolderPreparationService` for local prepared-set-folder creation from synced setlists.
- `lib/services/live_track_catalog_service.dart`: Pro live catalog adapter. It converts Apple Music, Spotify, YouTube, Deezer, and Soundcharts search results into app `Track` rows; do not replace it with direct Firestore `tracks` reads.
- `lib/services/soundcharts_ai_ranking_service.dart`: shared live-platform, AI-assisted ranking for song-selection surfaces. It uses Soundcharts/chart evidence as confidence signals, caps AI candidate windows, requires returned candidate IDs, and falls back to deterministic ranking.
- `lib/services/set_sequence_planner.dart`: deterministic Set Builder journey planner. It consumes live platform candidates, DJ context, local-library metadata, and behavior profile signals, then emits opener/warm-up/lift/peak/reset/closer tracks with confidence and reasons.
- `lib/services/set_builder_behavior_service.dart`: local Set Builder taste profile persisted in SharedPreferences under `set_builder_behavior_profile_v1`. It records save, delete, reorder, export, search-again, and mark-wrong actions for future ranking.
- `lib/ui/`: desktop, mobile, auth, onboarding, and shared widgets. `lib/ui/auth/splash_screen.dart` owns the launch splash with one procedural radar animation over a solid background. `lib/ui/auth/onboarding_screen.dart` owns the feature walkthrough and reusable artist picker; `AuthGate` now presents that artist picker only after real account sign-in and saves selections to `users/{uid}.followed_artists`. `lib/ui/widgets/guest_mode_banner.dart` owns the mock-data guest banner and sign-in gate panel for live-service screens. `lib/ui/widgets/pro_paywall.dart` owns the free-account preview banner, Pro locked panels, and direct subscription sheet used outside Settings.
- `assets/paywall/`: Gemini-rendered Pro/paywall graphics for locked live-service panels, subscription sheets, sign-in gates, and upgrade banners.
- `functions/`: Firebase Cloud Functions TypeScript project.
- `functions/src/lib/`: backend config, usage, entitlement, scoring, and storage helpers.
- `functions/test/`: TypeScript backend tests.
- `test/`: Flutter unit/widget tests.
- `ios/`, `macos/`, `android/`, `web/`: platform projects.
- `scripts/`: release/setup/asset scripts, including `gen_paywall_gemini.js` for the Gplus Gemini paywall artwork workflow.
- `docs/`: QA logs, design specs, and planning artifacts.

## Build Process

### Flutter

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
flutter build web --release --no-wasm-dry-run
flutter build ios --release
flutter build macos --release
```

### Firebase Functions

```bash
npm --prefix functions ci
npm --prefix functions run build
npm --prefix functions test
npm --prefix functions audit --audit-level=moderate
```

### Firebase Deploy

```bash
flutter build web --release --no-wasm-dry-run
firebase deploy --only hosting --project viberadar-462b8
firebase deploy --only firestore,storage --project viberadar-462b8
firebase deploy --only functions --project viberadar-462b8 --non-interactive
```

Functions deploy requires these secrets before the IAP backend can go live:

```bash
firebase functions:secrets:set APP_STORE_ISSUER_ID --project viberadar-462b8
firebase functions:secrets:set APP_STORE_KEY_ID --project viberadar-462b8
firebase functions:secrets:set APP_STORE_PRIVATE_KEY --project viberadar-462b8
```

On 2026-06-09 these App Store Server API secrets were set in Firebase Secret
Manager using the working Gplus App Store Connect API key path. Do not print or
commit the private key value.

Other backend secrets include `OPENAI_API_KEY`, platform API credentials, and Soundcharts/Beatport optional credentials.

Callable App Check enforcement is read from `functions/.env.<project_id>` at deploy time:

```bash
REQUIRE_APP_CHECK=true
CONSUME_APP_CHECK_TOKEN=false
APP_STORE_APP_APPLE_ID=6778432071
```

Register the iOS, macOS, Android, and web apps in Firebase App Check before enabling it. Web release builds need `--dart-define=FIREBASE_APPCHECK_RECAPTCHA_SITE_KEY=...`.
`APP_STORE_APP_APPLE_ID` is required for production App Store signed-data verification. For `viberadar-462b8`, the ASC App Apple ID is `6778432071`.

### macOS Distribution

```bash
APPLE_NOTARY_PROFILE=viberadar-notary ./scripts/release_macos.sh
```

The script signs, notarizes, staples, creates a DMG, signs/notarizes/staples the DMG, and writes artifacts to `build/macos/dist/`.

For Mac App Store packaging, use the separate ASC workflow after installing a
Mac App Store signing identity/provisioning profile and creating the ASC app
record:

```bash
APPLE_TEAM_ID=36TZ8UKL8W ./scripts/release_macos_appstore.sh
```

This uses automatic signing, `macos/ExportOptions-appstore.plist`, and validates
the exported `.pkg` with the App Store Connect API key. On 2026-06-09 it
produced `build/macos/appstore/VibeRadar.pkg`, which uploaded and processed in
ASC as macOS build `7d7c2b4a-72e2-4c5f-b289-8248cd4397a4` after a retry that
cleared generated DerivedData/local build caches to recover disk space.

## Development Standards

- Prefer Riverpod providers for shared state and dependency injection.
- Keep backend secrets in Firebase Functions Secret Manager; do not ship API keys in Flutter bundles.
- Use Firestore rules, Storage rules, and backend functions for ownership/authorization boundaries.
- Guest/demo mode must stay local mock-data only: no Firebase anonymous auth, no Firestore/Storage/Functions reads or writes, no StoreKit product loading, no platform proxy calls, no AI, no pairing, and no community access.
- Signed-in free mode must not read live catalog data or call cost-heavy providers. Use `liveCatalogAccessProvider` for client routing: free users get bundled preview tracks plus Pro upsell UI; only `LiveCatalogAccess.pro` may trigger Soundcharts/platform proxies, OpenAI, manual ingest, playlist aggregation, artist catalog/search, Set Builder, or automatic artwork-enrichment calls.
- Guest/demo and free-preview UI must explicitly say the catalog is mock/sample-only and not real live songs or trend data. Do not show normal "Connected to Firebase" / backend-health copy in customer-facing success states.
- Live song-selection screens should use `PlatformSearchService` for Apple Music, Spotify, YouTube, Deezer, and Soundcharts aggregation and `SoundchartsAiRankingService` for Set Builder / Greatest Of ranking. Do not let UI widgets sort only by a single provider's popularity when richer platform/chart evidence is available.
- Song rows should expose direct playback services through `PlatformPlayActions` whenever links exist. If a live result has only Soundcharts/chart evidence, keep the bounded `PlatformSearchService.enrichPlaybackLinksForResults` pass so top candidates regain `Play on Spotify`, `Play on Apple Music`, `Play on YouTube`, and Deezer actions.
- Genre controls should use `lib/core/config/music_genres.dart` as the canonical option source, then append discovered track/library/profile genres through `mergedGenreOptions`. Do not build global genre menus only from the currently loaded live tracks; a narrow chart result set must not hide other supported DJ lanes.
- Region-specific song selection must be storefront/market-aware, not chart-only. When a region is selected, pass that storefront/market to Apple Music and Spotify, search YouTube/Deezer with regional intent, and let platform-sourced rows appear; Soundcharts/Apple chart evidence should boost confidence and ordering rather than hard-blocking non-chart platform rows.
- Apple Music catalog and chart requests must use storefront-aware paths (`catalog/{storefront}/...`) for region-specific flows. Spotify track search must pass the matching market code.
- Set Builder must remain sequence-first and bounded-AI: collect DJ context, retrieve real candidates through deterministic live platform search, optionally AI-rerank only supplied candidate IDs, then let `SetSequencePlanner` handle phases, smooth transitions, dedupe/version choice, reasons, confidence, local matches, and behavior-profile boosts/penalties.
- Mobile Set Builder parity lives in `lib/ui/mobile/mobile_set_builder_tab.dart` and must save through `setlistActionsProvider` so generated phone sets sync to the account and can be picked up by the Mac handoff/export flows.
- Do not invent songs in AI prompts or UI copy. If a track was not returned by Soundcharts/platform/local-library search, it is not eligible for selection.
- Keep platform-specific behavior behind explicit platform checks.
- Add tests for risky state, quotas, auth, pairing, purchase sync, rules helpers, and subscription behavior.
- Keep generated/release artifacts out of source control. `.env.encrypted`, `.firebase/`, `public/*.dmg`, `build/macos/dist/`, and local outputs are ignored.
- CI format is blocking; run `dart format lib test` before pushing broad UI changes.

## Testing Procedures

### Current Verified Checks

Last verified on 2026-06-19 (AI char-limit fix — desktop set-build prompt > 12000):

- Root cause proven on the live proxy: oversized payload (~13k+ chars) → `INVALID_ARGUMENT "messages exceed the 12000-character limit"` (HTTP 400), which the client shows as "couldn't reach the AI service". Desktop `_getTrackContext()` sends up to 80 tracks → ~14–17k-char system prompt; `sanitize` runs before the Pro gate so even Pro hits it; mobile sends `trackContext: null`.
- Fix: `OPENAI_MAX_MESSAGE_CHARS` 12000 → 24000 in `functions/.env.viberadar-462b8`; `firebase deploy --only functions:openaiProxy --project viberadar-462b8 --non-interactive` succeeded (predeploy tsc passed). Server-side only — in-app picks it up with no rebuild.
- Verified live (throwaway Pro user): a 17,399-char system prompt that returned HTTP 400 before now returns HTTP 200 + a valid 20-track ```crate``` block on gpt-5.5 (~41s, within the 70s client callable timeout). Small/empty prompts still work; non-Pro still gets FAILED_PRECONDITION.
- Client-side bounding also added (`lib/services/ai_copilot_service.dart`, ships on next native rebuild): `renderTrackContext` caps the track block at 7000 chars (was unbounded `take(80)`); `boundedHistory` keeps the most recent ≤16 msgs / ≤9000 chars. TDD'd — `flutter test test/services/ai_copilot_service_test.dart` → 7 pass; `flutter analyze`/`dart format` clean; full suite still +N/-5 (the 5 are pre-existing drift: platform_play_actions ×3, pairing crate default, guest_mode 'Open Format' genre — unrelated).

Last verified on 2026-06-19 (Apple Music genre charts as primary genre source):

- Added Apple genre-chart sourcing: `appleGenreFor(lane)` + `AppleGenreMapping` in `lib/core/config/music_genres.dart`; `getGenreChartSongs` + `appleStorefrontForRegion`/`appleGenreChartStorefront` in `lib/services/apple_music_artist_service.dart`; `_searchAppleGenreChart` wired into `fetchTrendingChartTracks` (primary Apple source for mapped lanes) and seeded into `searchByGenre` in `lib/services/platform_search_service.dart`. Additive only; falls back to keyword search for unmapped lanes/failures.
- Apple genre ids verified live via a MusicKit developer token (key NUSAWKGJ7X / team 36TZ8UKL8W, ES256 ieee-p1363) against `api.music.apple.com`: `catalog/{sf}/genres` and `catalog/{sf}/charts?types=songs&chart=most-played&genre=<id>` return curated genre top-songs (US Hip-Hop→Drake, US Pop→Olivia Rodrigo). Afrobeats=100051/Amapiano=42 only in ZA/NG/GH storefronts.
- `dart format` (changed files) clean; `flutter analyze` → `No issues found!`; `flutter test test/core/music_genres_test.dart test/services/apple_genre_chart_test.dart` → all pass (TDD red→green).
- Full `flutter test` = 470 passed / 5 failed; the 5 are PRE-EXISTING working-tree drift, NOT from this change: untracked `lib/ui/widgets/platform_play_actions.dart` + its untracked test disagree on link order (apple-first vs spotify-first) and label ("YouTube Music" vs "YouTube"); `lib/models/crate.dart` (modified) defaults `'Custom setlist'` while `test/mobile/pairing_service_test.dart` expects `'Open format'`; untracked `test/providers/guest_mode_provider_test.dart` expects an `'Open Format'` genre option not present in `kCanonicalMusicGenres`. Recommend resolving these (decide source-vs-test of record) before the next commit/CI run.

Last verified on 2026-06-19 (macOS Sign in with Apple entitlement + AI backend re-verification):

- AI backend healthy (live probes): `gcloud secrets versions access latest --secret=OPENAI_API_KEY` = real 164-char `sk-proj` (v4 enabled, placeholder v3 disabled); direct `curl` to OpenAI `gpt-5.5` with the proxy's reasoning body (`max_completion_tokens` floored, no temperature, `reasoning_effort=low`) = HTTP 200; deployed `openaiProxy` end-to-end probe (throwaway Firebase email/password user + Firestore-REST Pro/unlimited entitlement, then delete both) returned `{"content":"pong","model":"gpt-5.5-2026-04-23"}` and a realistic 30-track set build returned a valid crate block in 36.4s. So a fresh "AI doesn't work" report is client-side (unauthenticated/not-Pro → generic "couldn't reach the AI service").
- Probe-script gotcha: never name a shell variable `UID` (read-only in zsh/bash → `failed to change user ID: operation not permitted`).
- macOS Apple sign-in: added `com.apple.developer.applesignin=[Default]` to `macos/Runner/Release.entitlements` + `DebugProfile.entitlements`; `plutil -lint` OK; `CODE_SIGN_ENTITLEMENTS` in `macos/Runner.xcodeproj/project.pbxproj` confirms Debug/Profile→DebugProfile, Release→Release.
- macOS build was blocked by HTTP 403 `PLA_NOT_ACCEPTED` (provisioning profile couldn't regenerate to add Sign in with Apple); after the account holder accepted the PLA, ASC API confirmed App ID `com.viberadar.viberadar` (`96477A3V26`) already has `APPLE_ID_AUTH`; `xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -allowProvisioningUpdates -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_R7BYLGVT9L.p8 -authenticationKeyID R7BYLGVT9L -authenticationKeyIssuerID 2d61090e-20f6-4c5c-9868-b0ecb45d51ad -destination 'platform=macOS' build` → BUILD SUCCEEDED; `codesign -d --entitlements` shows `applesignin` in the signed app; `codesign --verify` valid; `embedded.provisionprofile` includes the capability. Runtime Apple-ID sheet still needs a manual on-device test.

Last verified on 2026-06-18 (ASC 2.1(a) AI-error rejection root cause + fix):

- Live ASC: iOS `1.0.0` version `20c5730f` and macOS `ed0249fd` are `REJECTED`. iOS has **build 16** attached, macOS **build 11** (memory previously said build 10). Latest rejected submissions: iOS `4cc37428` (06-17) and macOS `938aa483` (06-16), both `UNRESOLVED_ISSUES`. Rejection = Guideline 2.1(a), single bug: AI feature shows an error (reviewed on iPad Air 11-inch M3 / iPadOS 26.5).
- Root cause proven on the live backend: deployed `OPENAI_API_KEY` secret was a placeholder (`sk-abc123…here`, version 3, set 06-17). Calling deployed `openaiProxy` as a Pro user returned `HTTP 500 "OpenAI error 401: Incorrect API key provided"`. `openaiProxy` (`functions/src/openai.ts`) is the only consumer of the key.
- Fix: `OPENAI_API_KEY` versions 1/2 are the real `sk-proj-…` keys (164 chars, authenticate, 62 models). Copied v2 → version 4 (latest), disabled placeholder v3, `firebase deploy --only functions:openaiProxy --project viberadar-462b8 --non-interactive` succeeded. Re-probe of the live proxy returned `HTTP 200` + a real completion. No code change; server-side only; build 16 needs no rebuild.
- Reviewer `test@viberadar.com` = uid `7pLYMX9aTHQIilvra7MuBsUEeGl2`, entitlement active `pro`/`unlimited:true`/`manual_admin_grant` (no `expiresAt`). `REQUIRE_APP_CHECK=false`; `OPENAI_ALLOWED_MODELS=gpt-4.1,gpt-4o-mini`.
- Probe method (reuse): create throwaway Firebase user via Identity Toolkit `signUp` (iOS key `AIzaSyCDZ2kVmhIQenh-YsI_sWXIYDPmWmMFmRE`), PATCH `entitlements/{uid}` active/pro/unlimited via Firestore REST with a gcloud token, POST `https://us-central1-viberadar-462b8.cloudfunctions.net/openaiProxy` with `Authorization: Bearer <idToken>` and `{"data":{...}}`, then delete the doc + user. ASC read API via `~/.appstoreconnect/private_keys/AuthKey_R7BYLGVT9L.p8` (key `R7BYLGVT9L`, issuer `2d61090e-20f6-4c5c-9868-b0ecb45d51ad`).
- AI model switched to **gpt-5.5**, forced server-side: `openaiProxy.buildChatCompletionBody()` redirects non-gpt-5 requests (incl. build 16's `gpt-4.1`) to `OPENAI_DEFAULT_MODEL`, omits `temperature` for gpt-5 (rejects non-default), sets `reasoning_effort=low`, floors `max_completion_tokens` to ≥3500 (set prompt lists tracks twice → 30-track set needs ~2.1k tokens; 2000 truncated the crate block), and the callable returns `model`. `.env`: `OPENAI_DEFAULT_MODEL=gpt-5.5`, `OPENAI_ALLOWED_MODELS=gpt-5.5,gpt-4.1,gpt-4o-mini`, `OPENAI_MAX_COMPLETION_TOKENS=4000`, `OPENAI_REASONING_EFFORT=low`. Client unchanged (no rebuild). `npm --prefix functions run build`+`test` passed; `firebase deploy --only functions:openaiProxy` succeeded; faithful proxy probe (build-16 payload) returned 200 on `gpt-5.5-2026-04-23` with a parseable 15-track crate block, `finish=stop`, ~13s. End-to-end AI smoke test against the live proxy = 7/7 (chat set-build incl. 30-track set, advice-no-crate, multi-turn, region variant, parseCommand JSON, Soundcharts ranking ids, non-Pro `FAILED_PRECONDITION` gate). Latency ~13–18s/build, ~45s for a max-size 30-track set; Pro AI quota 100/mo (Studio 400) now bills a premium model.

Last verified on 2026-06-09:

- `dart format --output=none --set-exit-if-changed lib test`: passed, 184 files, 0 changed.
- `flutter analyze`: passed.
- `flutter test --reporter expanded`: passed, 397 tests after the guest-cost gate and compact locked-panel fix.
- `flutter build web --release --no-wasm-dry-run`: passed.
- `npm --prefix functions run build`: passed.
- `npm --prefix functions test`: passed.
- `npm --prefix functions audit --audit-level=moderate`: passed, 0 vulnerabilities.
- `firebase deploy --only firestore:rules,storage --dry-run --project viberadar-462b8`: passed.
- `firebase deploy --only hosting --project viberadar-462b8`: passed.
- `firebase deploy --only firestore,storage --project viberadar-462b8`: passed.
- `firebase deploy --only functions --project viberadar-462b8 --non-interactive`: passed after setting App Store Server API secrets and explicit env params.
- `bash -n scripts/release_macos_appstore.sh scripts/release_macos.sh`: passed.
- `plutil -lint macos/ExportOptions-appstore.plist`: passed.
- `git diff --check`: passed.
- `flutter build ios --simulator --debug --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed after deleting stale generated BoringSSL/gRPC build products.
- `flutter build ios --simulator --debug --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed on 2026-06-10 and produced `build/ios/iphonesimulator/Runner.app` for Maestro QA.
- `~/.maestro/bin/maestro check-syntax docs/qa/maestro/ios_auth_smoke.yaml`: passed on 2026-06-10.
- `~/.maestro/bin/maestro --udid 43B20446-A259-4F82-9227-25DB7CCF74A9 test --debug-output outputs/maestro --flatten-debug-output docs/qa/maestro/ios_auth_smoke.yaml`: passed on 2026-06-10 against simulator `GPLUS-MARKET-QA` / iOS 26.5. Captures are stored under `outputs/maestro/screenshots/`.
- `~/.maestro/bin/maestro check-syntax docs/qa/maestro/ios_signed_in_smoke.yaml`: passed on 2026-06-10.
- `set -a; . outputs/maestro/credentials.env; set +a; ~/.maestro/bin/maestro --udid 43B20446-A259-4F82-9227-25DB7CCF74A9 test --debug-output outputs/maestro/debug-signed-in --flatten-debug-output --test-output-dir outputs/maestro/screenshots docs/qa/maestro/ios_signed_in_smoke.yaml -e MAESTRO_TEST_EMAIL="$MAESTRO_TEST_EMAIL" -e MAESTRO_TEST_PASSWORD="$MAESTRO_TEST_PASSWORD"`: passed on 2026-06-10. The ignored local credentials file contains the generated Firebase Auth Maestro account and must not be committed or copied into YAML.
- `flutter build macos --debug`: passed and produced `build/macos/Build/Products/Debug/VibeRadar.app`.
- `~/.maestro/bin/maestro list-devices`: passed on 2026-06-10 and confirmed Maestro exposes Android, iOS, and Web targets, but no native macOS app target.
- `flutter build macos --debug --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed on 2026-06-10 and produced `build/macos/Build/Products/Debug/VibeRadar.app`.
- `flutter test test/services/soundcharts_ai_ranking_service_test.dart test/desktop/greatest_of_service_test.dart --reporter expanded`: passed on 2026-06-10 with 37 tests after the Soundcharts AI ranking change.
- `flutter analyze`: passed on 2026-06-10 after the Soundcharts AI ranking change.
- `flutter test --reporter expanded`: passed on 2026-06-10 with 414 tests after the Soundcharts AI ranking change.
- `npm --prefix functions run build` and `npm --prefix functions test`: passed on 2026-06-10 after the Soundcharts AI ranking change, confirming existing Soundcharts/OpenAI callable support still builds and tests cleanly.
- `dart analyze lib/services/platform_search_service.dart lib/services/live_track_catalog_service.dart lib/services/soundcharts_ai_ranking_service.dart lib/ui/shell/vibe_shell_setbuilder.dart lib/ui/features/greatest_of/greatest_of_screen.dart lib/ui/features/search/search_screen_results.dart test/services/soundcharts_ai_ranking_service_test.dart test/services/live_track_catalog_service_test.dart`: passed on 2026-06-12 after restoring platform-first music sourcing.
- `flutter test test/services/live_track_catalog_service_test.dart test/services/soundcharts_ai_ranking_service_test.dart --reporter expanded`: passed on 2026-06-12 with 7 tests after restoring platform-first music sourcing.
- `dart analyze lib/services/platform_search_service.dart lib/ui/mobile/search_tab.dart lib/ui/features/search/search_screen.dart test/services/platform_search_service_test.dart`: passed on 2026-06-12 after restoring playback-link enrichment.
- `flutter test test/services/platform_search_service_test.dart test/services/live_track_catalog_service_test.dart test/widgets/platform_play_actions_test.dart test/mobile/search_tab_test.dart --reporter expanded`: passed on 2026-06-12 with 14 tests after restoring playback-link enrichment.
- `flutter analyze`: passed on 2026-06-12 after restoring platform-first music sourcing.
- `flutter test --reporter expanded`: passed on 2026-06-12 with 434 tests after restoring platform-first music sourcing and playback-link enrichment.
- `dart analyze lib/app/bootstrap.dart lib/ui/widgets/sidebar_nav.dart lib/ui/widgets/guest_mode_banner.dart lib/ui/widgets/pro_paywall.dart lib/ui/shell/vibe_shell_views.dart lib/ui/shell/pair_phone_screen.dart lib/ui/features/ai_copilot/ai_copilot_screen.dart test/widgets/pro_paywall_test.dart test/widgets/guest_mode_banner_test.dart test/widgets/sidebar_nav_test.dart`: passed on 2026-06-10 after the mock-song disclosure and connected-status cleanup.
- `flutter test test/widgets/pro_paywall_test.dart test/widgets/guest_mode_banner_test.dart test/widgets/sidebar_nav_test.dart test/mobile/iphone_overflow_test.dart --reporter expanded`: passed on 2026-06-10 with 8 tests after the mock-song disclosure cleanup.
- `flutter test test/mobile/pair_phone_screen_test.dart --reporter expanded`: passed on 2026-06-10 with 9 tests after removing the stale user-facing Anonymous Auth copy.
- `flutter analyze`: passed on 2026-06-10 after the mock-song disclosure and connected-status cleanup.
- `flutter test --reporter expanded`: passed on 2026-06-10 with 417 tests after the mock-song disclosure and connected-status cleanup.
- `flutter test test/services/set_folder_preparation_service_test.dart test/desktop/screen_smoke_test.dart test/desktop/artist_service_test.dart test/desktop/greatest_of_service_test.dart test/desktop/home_screen_logic_test.dart test/dj_root_detection_test.dart test/export_service_test.dart test/serato_export_test.dart test/virtual_dj_export_test.dart --reporter expanded`: passed on 2026-06-10 with 135 tests.
- Native macOS launch smoke on 2026-06-10: `open -n build/macos/Build/Products/Debug/VibeRadar.app` launched PID `94347`; System Events verified a `VibeRadar` window at `1280x820`; `cliclick` opened the guest/demo entry; screenshots are stored under ignored `outputs/macos-qa/`.
- `plutil -lint macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements`: passed after aligning Debug/Profile sandbox entitlement with Release.
- `curl -fsSI` for `/privacy.html`, `/support.html`, and `/terms.html`: all returned HTTP 200.
- App Store Connect API probe using the Gplus credential path: authenticated, found Gplus app and VibeRadar bundle ID `96477A3V26`; before the interactive ASC web step, no VibeRadar ASC app record existed for `com.viberadar.viberadar`.
- XcodeBuildMCP iOS build/run still times out at the MCP transport layer; direct Flutter/Xcode simulator builds should be rerun after cache cleanup before depending on simulator screenshot capture.
- ASC app record exists: `VibeRadar DJ`, App Apple ID `6778432071`, bundle ID `com.viberadar.viberadar`, SKU `VIBERADAR-2026`, primary locale `en-US`, iOS and macOS version shells `1.0`.
- App Store Server Notifications are configured in ASC for production and sandbox V2 at `https://us-central1-viberadar-462b8.cloudfunctions.net/appStoreServerNotification`.
- `functions/.env.viberadar-462b8` now has `APP_STORE_APP_APPLE_ID=6778432071`, and `firebase deploy --only functions --project viberadar-462b8 --non-interactive` passed after the update.
- VibeRadar Pro subscription group `22145074` exists with monthly product `6778435251` / `viberadar_pro_monthly` and yearly product `6778435163` / `viberadar_pro_yearly`; both are `WAITING_FOR_REVIEW`.
- Monthly pricing/availability: all countries, future countries enabled, United States base price `$9.99`.
- Yearly pricing/availability: all countries, future countries enabled, United States base price `$79.99`.
- IAP review screenshots are uploaded and processed by ASC for both subscriptions from the real iOS Simulator IAP screenshot surface: monthly screenshot `c3333cbc-ac79-4981-b5f6-a46c4615296d`, yearly screenshot `70053620-f274-4ef4-8a9a-d6526fc4dfe7`, both `COMPLETE` at `1320x2868`. Local capture: `docs/qa/screenshots/asc/iap-review/simctl/subscription-products.png`.
- ASC app info localization updated: subtitle `DJ trends and setlists`, privacy policy URL `https://viberadar-462b8.web.app/privacy.html`.
- ASC iOS/macOS version localizations updated with description, keywords, promotional text, support URL `https://viberadar-462b8.web.app/support.html`, and marketing URL `https://viberadar-462b8.web.app/`.
- ASC TestFlight beta group `VibeRadar QA` created as `b80d765c-cc20-4912-8ddf-2ad67a1f3cc6`; VibeRadar-specific beta tester `9a54e4bb-11d5-4ac8-a5f3-43d77f0105df` added for `cyberzonenas93@gmail.com`.
- ASC App Review Details are present for both iOS and macOS versions with reviewer demo account metadata; `whatsNew` is not editable on the first version shell.
- ASC app-level price schedule is Free, using U.S. base territory and the free price point.
- ASC app availability resource `6778432071` exists with `availableInNewTerritories=true`; `/v2/appAvailabilities/6778432071/territoryAvailabilities` returns 175 current App Store territory rows, all with `available=true` and zero unavailable territories. `CANNOT_SELL` / `AVAILABLE_FOR_SALE_UNRELEASED_APP` content statuses are expected until the first release is approved.
- ASC App Privacy labels were completed and published with ten linked data types: Name, Email Address, Photos or Videos, Audio Data, Other User Content, User ID, Device ID, Purchase History, Product Interaction, and Other Usage Data. All are marked not used for tracking; Product Interaction and Other Usage Data are used for App Functionality, Analytics, and Product Personalization; the others are used for App Functionality.
- Fresh iOS build `030a8669-1966-44ac-8676-b6a336ff7581` (build 10) is uploaded, valid, attached to iOS version `20c5730f-bd2f-4b39-b1b6-80928ed2e47a`, assigned to the `VibeRadar QA` beta group, submitted for App Review, and reports `usesNonExemptEncryption=false`.
- Fresh macOS build `efc7dc1e-5c84-4f57-86c8-2c36c5264cee` (build 10) is uploaded, valid, attached to macOS version `ed0249fd-1df2-4381-9225-7ab9d2bfad6b`, assigned to the `VibeRadar QA` beta group, submitted for App Review, and reports `usesNonExemptEncryption=false`.
- ASC product screenshot sets now contain actual app screens only: iPhone 6.9-inch set `1716fd99-0905-4601-8c16-00a61593d3d3` has 5 `COMPLETE` simulator screenshots at `1320x2868`; iPad 13-inch set `457d8c4e-fc38-49f3-85cf-7c47f35b09b8` has 5 `COMPLETE` simulator screenshots at `2064x2752`; macOS set `24851b61-7004-42d2-b734-0ff0d6f7d591` has 4 `COMPLETE` native cropped screenshots at `1280x800`.
- ASC iOS review submission `c5caa82d-829d-4f98-9f5f-94081143a428` and macOS review submission `5ff2e775-608d-4736-933f-3da6ab3353de` are `WAITING_FOR_REVIEW`; both app versions report `WAITING_FOR_REVIEW` on build 10 after the EULA metadata resubmission.
- Build 10 includes the setlist/crates parity, macOS large-setlist performance, phone-to-computer setlist handoff fixes, Pro cost-gate UI, Gemini-rendered paywall artwork, latest Demo Mode copy, restored platform play actions, Soundcharts-backed AI ranking, sequence-aware Set Builder, chart-evidence-anchored regional catalog results, mobile Set Builder parity, the Global/All region fallback fix, hard worldwide Soundcharts proxy defaults, and client chart-quality fixes.
- Subscription submissions succeeded after first app-version preparation: monthly `f900334c-ab35-4d46-8db2-c8fd7494de95`, yearly `f8911dfa-33d6-41aa-bf03-196ec8ae9545`; both products report `WAITING_FOR_REVIEW`.
- `flutter build ipa --release --build-name=1.0.0 --build-number=2 --export-method app-store`: passed and produced `build/ios/ipa/VibeRadar.ipa`.
- `xcrun altool --validate-app -f build/ios/ipa/VibeRadar.ipa -t ios`: verify succeeded.
- `xcrun altool --upload-app -f build/ios/ipa/VibeRadar.ipa -t ios`: upload succeeded, delivery/build ID `35f5742f-7a87-4da4-925d-ecfa167e93a0`.
- `APPLE_TEAM_ID=36TZ8UKL8W ASC_KEY_ID=R7BYLGVT9L ASC_ISSUER_ID=2d61090e-20f6-4c5c-9868-b0ecb45d51ad ./scripts/release_macos_appstore.sh`: archive succeeded; first export hit `No space left on device`.
- `xcodebuild -exportArchive -archivePath build/archives/VibeRadar-macOS.xcarchive -exportOptionsPlist macos/ExportOptions-appstore.plist -exportPath build/macos/appstore -allowProvisioningUpdates`: passed after clearing generated DerivedData/local build products.
- `pkgutil --check-signature build/macos/appstore/VibeRadar.pkg`: signed by `3rd Party Mac Developer Installer: Angelo Nartey (36TZ8UKL8W)`.
- `xcrun altool --validate-app -f build/macos/appstore/VibeRadar.pkg -t macos`: verify succeeded.
- `xcrun altool --upload-app -f build/macos/appstore/VibeRadar.pkg -t macos`: upload succeeded, delivery/build ID `7d7c2b4a-72e2-4c5f-b289-8248cd4397a4`.
- ASC actual-app screenshot verification after resubmission: iPhone screenshots `b77ce7ab-7031-445d-b81e-15416b782f8b`, `56dc2b7d-dac8-456b-8c95-b7013f5f21c4`, `5909692e-fa9c-46b0-9e3c-0c300e04b886`, `4b6da261-4bd6-46b0-8823-5b14773218fa`, `0f9b08e7-51c4-474b-a6b7-c6f6e7f124c6`; iPad screenshots `c2ea8c5a-3c13-428d-a7ab-561737d98785`, `f90ecd5a-887a-4006-9ea4-ce6cd0267775`, `77a3ba31-74e4-4a84-82a5-7f2771cedd7f`, `6e5c11f0-0e91-4ce3-ac20-c0ff2f0afec0`, `3184f31c-b52b-45c2-a5bf-dba3781e8d7d`; macOS screenshots `d6ec9456-4c7a-47b9-8e43-8ef252cd620b`, `3ac2dc40-4134-4d0c-90cd-26d395a0d57e`, `7af2d43f-0fb5-41cb-b81c-649b90a2f34f`, `cdfa59c9-f00a-4a32-8164-89be8a32e323`; monthly IAP screenshot `c3333cbc-ac79-4981-b5f6-a46c4615296d`; yearly IAP screenshot `70053620-f274-4ef4-8a9a-d6526fc4dfe7`; all are `COMPLETE`.
- Firebase Auth export confirmed reviewer account `test@viberadar.com` exists. Do not print the reviewer password in docs or logs.
- Historical ASC beta group check confirmed `cyberzonenas93@gmail.com` remained in `VibeRadar QA`; iOS build 4 and macOS build 4 were assigned to the beta group at that stage. Later build 10 artifacts were also assigned during submission; build 10 is submitted for App Review.
- `flutter test test/mobile/pairing_service_test.dart test/mobile/connect_computer_test.dart test/mobile/setlist_provider_test.dart test/mobile/setlists_tab_test.dart test/billing_provider_test.dart --reporter expanded`: passed, 34 tests.
- `npm --prefix functions test`: passed after IAP/ASC setup verification.
- `curl` invalid App Store Server Notification probe returned HTTP 400 with `signedPayload could not be verified`, confirming fail-closed behavior.
- `dart analyze lib/ui/auth/onboarding_screen.dart test/onboarding/onboarding_artist_images_test.dart`: passed.
- `flutter test test/onboarding --reporter expanded`: passed, 5 tests.
- `dart analyze lib/services/spotify_artist_service.dart lib/ui/auth/onboarding_screen.dart test/onboarding/onboarding_artist_images_test.dart`: passed after adding constrained onboarding artist-image lookup.
- `flutter test test/onboarding/onboarding_artist_images_test.dart --reporter expanded`: passed.
- `flutter test --reporter expanded`: passed, 392 tests.
- `flutter build web --release --no-wasm-dry-run --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed after onboarding artist-image changes.
- `npm --prefix functions run build`: passed after adding `spotifyOnboardingArtistImages`.
- `npm --prefix functions test`: passed after adding proxy helper coverage.
- `firebase deploy --only functions:spotifyOnboardingArtistImages --project viberadar-462b8 --non-interactive`: CLI printed deploy success then exited unexpectedly with code 2; `firebase functions:list` and a direct callable probe confirmed the function is live.
- `firebase deploy --only hosting --project viberadar-462b8 --non-interactive`: passed after rebuilding the web app; Hosting URL remains `https://viberadar-462b8.web.app`.
- Direct callable probe for `spotifyOnboardingArtistImages`: returned real Spotify artist IDs and `https://i.scdn.co/image/...` URLs for Drake, Kendrick Lamar, and Bad Bunny.
- Historical ASC product screenshot upload verification: the first onboarding/sign-in screenshot assets processed successfully, but those assets were later deleted and replaced with actual app screenshots in the same screenshot sets.
- `git diff --check`: passed.
- `dart analyze lib/app/app.dart lib/ui/widgets/subscription_section.dart`: passed after adding the IAP screenshot surface.
- `flutter analyze`: passed after the ASC submission continuation changes.
- `flutter test test/billing_provider_test.dart test/mobile/pairing_service_test.dart test/mobile/connect_computer_test.dart test/mobile/setlist_provider_test.dart test/mobile/setlists_tab_test.dart --reporter expanded`: passed, 34 tests.
- `npm --prefix functions test`: passed after the ASC submission continuation.
- `plutil -lint macos/Runner/Info.plist macos/Runner.xcodeproj/project.pbxproj macos/ExportOptions-appstore.plist macos/Runner/Release.entitlements ios/Runner.xcodeproj/project.pbxproj`: passed.
- `flutter test test/auth/auth_gate_onboarding_test.dart test/onboarding/onboarding_artist_images_test.dart --reporter expanded`: passed after moving artist preference capture behind sign-in.
- `flutter analyze`: passed after the post-auth artist preference routing change.
- `flutter test test/providers/guest_mode_provider_test.dart test/auth/auth_gate_onboarding_test.dart test/mobile/adaptive_shell_test.dart test/billing_provider_test.dart --reporter expanded`: passed after replacing guest Firebase anonymous auth with local mock-only mode.
- `flutter analyze`: passed after the guest-cost gate changes.
- `flutter test test/mobile/iphone_overflow_test.dart --reporter expanded`: passed after compacting the guest live-service sign-in gate for iPhone SE.
- `flutter test test/providers/guest_mode_provider_test.dart test/auth/auth_gate_onboarding_test.dart test/mobile/adaptive_shell_test.dart test/billing_provider_test.dart test/mobile/iphone_overflow_test.dart --reporter expanded`: passed, 12 tests, after guest-cost gate and compact locked-panel fix.
- `flutter test --reporter expanded`: passed, 397 tests, after guest-cost gate and compact locked-panel fix.
- `dart analyze lib/providers/paired_computer_provider.dart lib/ui/mobile/connect_computer_sheet.dart lib/providers/setlist_provider.dart lib/ui/shell/vibe_shell_crates.dart lib/models/app_section.dart lib/ui/onboarding/intro_carousel.dart lib/ui/onboarding/screen_tutorial.dart test/mobile/setlist_provider_test.dart lib/ui/shell/pair_phone_screen.dart test/mobile/pair_phone_screen_test.dart lib/ui/mobile/ai_tab.dart lib/ui/widgets/track_action_menu.dart lib/ui/features/search/search_screen_results.dart lib/ui/features/search/search_screen_widgets.dart lib/ui/features/exports/exports_screen.dart lib/ui/widgets/command_palette.dart lib/ui/features/artists/artists_screen_detail.dart lib/ui/shell/vibe_shell_setbuilder.dart lib/ui/features/ai_copilot/ai_copilot_screen.dart lib/ui/features/trending/trending_screen.dart`: passed after the setlist parity/performance/pairing fix.
- `flutter test test/mobile/setlist_provider_test.dart test/mobile/pair_phone_screen_test.dart test/mobile/connect_computer_test.dart`: passed, 23 tests, after adding paired-save and Mac import regressions.
- `flutter test test/mobile/setlists_tab_test.dart test/mobile/setlist_editor_test.dart test/mobile/trending_tab_test.dart test/mobile/ai_tab_test.dart`: passed, 37 tests, after product-copy and setlist flow changes.
- `flutter analyze`: passed after the setlist parity/performance/pairing fix.
- `flutter test`: passed, 400 tests, after the setlist parity/performance/pairing fix.
- `dart analyze lib/app/app.dart`: passed after adding `setlistsProvider` to the ASC product screenshot surface.
- `dart analyze lib/providers/paired_computer_provider.dart lib/ui/mobile/connect_computer_sheet.dart lib/providers/setlist_provider.dart lib/ui/shell/vibe_shell_crates.dart lib/models/app_section.dart lib/ui/shell/pair_phone_screen.dart lib/app/app.dart`: passed before the build 3 release upload.
- `flutter test test/mobile/setlist_provider_test.dart test/mobile/pair_phone_screen_test.dart test/mobile/connect_computer_test.dart --reporter expanded`: passed, 23 tests, before the build 3 release upload.
- `flutter analyze`: passed before the build 3 release upload.
- `flutter test test/mobile/setlists_tab_test.dart test/mobile/setlist_editor_test.dart test/mobile/trending_tab_test.dart test/mobile/ai_tab_test.dart --reporter expanded`: passed, 37 tests, before the build 3 release upload.
- `flutter build ipa --release --build-name=1.0.0 --build-number=3 --export-method app-store --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed and produced `build/ios/ipa/VibeRadar.ipa` with bundle `com.viberadar.viberadar`, version `1.0.0`, build `3`.
- `xcrun altool --validate-app -f build/ios/ipa/VibeRadar.ipa -t ios`: verify succeeded.
- `xcrun altool --upload-app -f build/ios/ipa/VibeRadar.ipa -t ios`: upload succeeded, delivery/build ID `7aae5142-4d03-4724-ba96-fb03cd047ccd`.
- `APPLE_TEAM_ID=36TZ8UKL8W ASC_KEY_ID=R7BYLGVT9L ASC_ISSUER_ID=2d61090e-20f6-4c5c-9868-b0ecb45d51ad BUILD_NAME=1.0.0 BUILD_NUMBER=3 FIREBASE_APP_CHECK_ENABLED=false ./scripts/release_macos_appstore.sh`: archive/export succeeded; Apple validation hit transient 500/502 app-lookup errors after export.
- `pkgutil --check-signature build/macos/appstore/VibeRadar.pkg`: signed by `3rd Party Mac Developer Installer: Angelo Nartey (36TZ8UKL8W)`.
- `build/archives/VibeRadar-macOS.xcarchive/Info.plist`: verified bundle `com.viberadar.viberadar`, version `1.0.0`, build `3`.
- `xcrun altool --upload-app -f build/macos/appstore/VibeRadar.pkg -t macos`: upload succeeded, delivery/build ID `a7e27648-ff32-4c62-88e5-89a2e4a851eb`.
- ASC API confirmed iOS build `7aae5142-4d03-4724-ba96-fb03cd047ccd` and macOS build `a7e27648-ff32-4c62-88e5-89a2e4a851eb` are `VALID`, attached to the `1.0.0` platform versions, `usesNonExemptEncryption=false`, assigned to `VibeRadar QA`, and submitted through review submissions `35e5e1c5-ed83-41e4-b425-8cf042b19484` and `25da2730-0952-4569-bf21-4a9663c2c7e2`.

Last verified on 2026-06-10:

- `dart analyze lib/providers/app_state.dart lib/providers/billing_provider.dart lib/providers/library_provider.dart lib/services/ai_copilot_service.dart lib/services/ingest_service.dart lib/ui/widgets/pro_paywall.dart lib/ui/widgets/sidebar_nav.dart lib/ui/shell/vibe_shell.dart lib/ui/mobile/mobile_shell.dart test/providers/guest_mode_provider_test.dart`: passed.
- `dart format lib/services/set_builder_behavior_service.dart lib/services/set_sequence_planner.dart lib/services/soundcharts_ai_ranking_service.dart lib/providers/library_provider.dart lib/services/export_service.dart lib/ui/shell/vibe_shell.dart lib/ui/shell/vibe_shell_setbuilder.dart lib/ui/shell/vibe_shell_playlists.dart lib/ui/shell/vibe_shell_crates.dart test/services/set_sequence_planner_test.dart test/services/set_builder_behavior_service_test.dart`: passed after the sequence-aware Set Builder implementation.
- `dart analyze lib/services/set_builder_behavior_service.dart lib/services/set_sequence_planner.dart lib/services/soundcharts_ai_ranking_service.dart lib/providers/library_provider.dart lib/services/export_service.dart lib/ui/shell/vibe_shell.dart lib/ui/shell/vibe_shell_setbuilder.dart lib/ui/shell/vibe_shell_playlists.dart lib/ui/shell/vibe_shell_crates.dart test/services/set_sequence_planner_test.dart test/services/set_builder_behavior_service_test.dart`: passed.
- `flutter test test/services/set_sequence_planner_test.dart test/services/set_builder_behavior_service_test.dart test/services/soundcharts_ai_ranking_service_test.dart test/set_builder_service_test.dart --reporter expanded`: passed with 10 tests after adding sequence planning and export behavior learning.
- `flutter analyze`: passed after sequence-aware Set Builder changes.
- `flutter test --reporter expanded`: passed with 423 tests after sequence-aware Set Builder changes.
- `flutter test test/providers/guest_mode_provider_test.dart test/billing_provider_test.dart --reporter expanded`: passed, 5 tests.
- `npm --prefix functions run build`: passed.
- `npm --prefix functions test`: passed.
- `flutter analyze`: passed.
- `flutter test --reporter expanded`: passed, 402 tests.
- `firebase deploy --only firestore:rules --dry-run --project viberadar-462b8 --non-interactive`: passed; Firestore rules compiled.
- `git diff --check`: passed.
- `firebase deploy --only firestore:rules,functions:openaiProxy,functions:spotifyProxy,functions:appleProxy,functions:youtubeProxy,functions:manualIngestTrackSignals --project viberadar-462b8 --non-interactive`: passed; Firestore rules and Pro-gated live-cost functions are deployed.
- `flutter build web --release --no-wasm-dry-run --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed.
- `firebase deploy --only hosting --project viberadar-462b8 --non-interactive`: passed; Hosting URL remains `https://viberadar-462b8.web.app`.
- `firebase functions:list --project viberadar-462b8 | rg "spotifyProxy|appleProxy|youtubeProxy|openaiProxy|manualIngestTrackSignals"`: confirmed all five updated functions are present.
- `dart analyze lib/providers/app_state.dart lib/services/apple_music_artist_service.dart lib/services/spotify_artist_service.dart lib/services/platform_search_service.dart lib/services/live_track_catalog_service.dart lib/services/set_sequence_planner.dart lib/services/soundcharts_ai_ranking_service.dart lib/ui/features/trending/trending_screen.dart lib/ui/mobile/mobile_shell.dart lib/ui/mobile/mobile_set_builder_tab.dart test/providers/guest_mode_provider_test.dart test/services/live_track_catalog_service_test.dart test/mobile/adaptive_shell_test.dart`: passed on 2026-06-10 after the regional live-catalog and mobile Set Builder parity changes.
- `flutter test test/providers/guest_mode_provider_test.dart test/services/live_track_catalog_service_test.dart test/mobile/adaptive_shell_test.dart test/services/soundcharts_ai_ranking_service_test.dart --reporter expanded`: passed on 2026-06-10 after the regional live-catalog and mobile Set Builder parity changes.
- `flutter analyze`: passed on 2026-06-10 after the regional live-catalog and mobile Set Builder parity changes.
- `flutter test --reporter expanded`: passed on 2026-06-10 with 427 tests after the regional live-catalog and mobile Set Builder parity changes.
- `curl -fsSI https://viberadar-462b8.web.app`: returned HTTP 200.
- `node --check scripts/gen_paywall_gemini.js`: passed.
- `dart analyze lib/ui/widgets/pro_paywall.dart`: passed.
- `dart analyze test/widgets/pro_paywall_test.dart`: passed.
- `flutter test test/widgets/pro_paywall_test.dart --reporter expanded`: passed, 3 tests.
- `flutter test test/providers/guest_mode_provider_test.dart test/billing_provider_test.dart test/mobile/iphone_overflow_test.dart --reporter expanded`: passed, 7 tests.
- `flutter analyze`: passed after adding Gemini paywall artwork.
- `flutter test --reporter expanded`: passed, 405 tests, after adding Gemini paywall artwork.
- `flutter build web --release --no-wasm-dry-run --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed after adding Gemini paywall artwork.
- `firebase deploy --only hosting --project viberadar-462b8 --non-interactive`: passed after adding Gemini paywall artwork.
- `curl -fsSI https://viberadar-462b8.web.app/assets/assets/paywall/pro_locked_hero.png`: returned HTTP 200.
- `flutter build ipa --release --build-name=1.0.0 --build-number=4 --export-method app-store --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed and produced `build/ios/ipa/VibeRadar.ipa`.
- `xcrun altool --validate-app -f build/ios/ipa/VibeRadar.ipa -t ios`: verify succeeded for build 4.
- `xcrun altool --upload-app -f build/ios/ipa/VibeRadar.ipa -t ios`: upload succeeded, delivery/build ID `19515410-b0d4-4d24-b404-ac8ecc352b05`.
- `APPLE_TEAM_ID=36TZ8UKL8W ASC_KEY_ID=R7BYLGVT9L ASC_ISSUER_ID=2d61090e-20f6-4c5c-9868-b0ecb45d51ad BUILD_NAME=1.0.0 BUILD_NUMBER=4 FIREBASE_APP_CHECK_ENABLED=false ./scripts/release_macos_appstore.sh`: archive/export/validation succeeded and produced `build/macos/appstore/VibeRadar.pkg`.
- `xcrun altool --upload-app -f build/macos/appstore/VibeRadar.pkg -t macos`: upload succeeded, delivery/build ID `f4e60855-5cfc-43b2-a5c8-7c972544aed2`.
- ASC API confirmed iOS build `19515410-b0d4-4d24-b404-ac8ecc352b05` and macOS build `f4e60855-5cfc-43b2-a5c8-7c972544aed2` are `VALID`, attached to the `1.0.0` platform versions, `usesNonExemptEncryption=false`, assigned to `VibeRadar QA`, and submitted through review submissions `776ca9d9-944e-417b-aa92-2139c9495f2e` and `a4664e3f-cecc-43ca-a251-2ae5d8c43e06`.
- `dart format lib/ui/auth/splash_screen.dart test/auth/splash_screen_test.dart`: passed after replacing the splash background animation.
- `dart analyze lib/ui/auth/splash_screen.dart test/auth/splash_screen_test.dart`: passed.
- `flutter test test/auth/splash_screen_test.dart --reporter expanded`: passed.
- `flutter test test/auth/auth_gate_onboarding_test.dart --reporter expanded`: passed.
- `dart format lib/services/set_folder_preparation_service.dart lib/ui/shell/vibe_shell.dart lib/ui/shell/vibe_shell_crates.dart test/services/set_folder_preparation_service_test.dart`: passed after adding desktop prepared set folders.
- `flutter test test/services/set_folder_preparation_service_test.dart`: passed, 4 tests.
- `flutter analyze lib/services/set_folder_preparation_service.dart lib/ui/shell/vibe_shell.dart lib/ui/shell/vibe_shell_crates.dart test/services/set_folder_preparation_service_test.dart`: passed.
- Real Mac prepared-folder QA against `/Users/angelonartey/Downloads/amapiano`: `flutter test tool/qa_amapiano_prepare_folder_test.dart --reporter expanded` passed before deleting the local-only harness. Scanner found 446 supported audio files; prepared-folder service copied 8 local tracks, wrote M3U/missing/match reports, produced 1 intentional TIDAL/Spotify fallback missing track, and returned 0 errors.
- `flutter build macos --debug`: passed and produced `build/macos/Build/Products/Debug/VibeRadar.app`. The native debug app launched and stayed alive in a smoke test, then was quit. Build warnings were dependency/toolchain warnings only: StoreKit deprecations, missing Metal cryptex Swift search paths, duplicate `-lc++`, old pod deployment targets, and Firebase plugin warnings.
- `flutter analyze`: passed after the build 5 version bump and macOS export-compliance metadata update.
- `flutter test --reporter expanded`: passed with 410 tests after the build 5 submission changes.
- `plutil -lint macos/Runner/Info.plist ios/Runner/Info.plist macos/ExportOptions-appstore.plist`: passed.
- `git diff --check pubspec.yaml macos/Runner/Info.plist lib/ui/auth/auth_gate.dart lib/ui/widgets/guest_mode_banner.dart lib/ui/widgets/sidebar_nav.dart CLAUDE.md CODEX.md`: passed.
- `flutter build ipa --release --build-name=1.0.0 --build-number=5 --export-method app-store --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed and produced `build/ios/ipa/VibeRadar.ipa`.
- `xcrun altool --validate-app -f build/ios/ipa/VibeRadar.ipa -t ios`: verify succeeded for build 5.
- `xcrun altool --upload-app -f build/ios/ipa/VibeRadar.ipa -t ios`: upload succeeded, delivery/build ID `fdb26cf9-a4dc-4c68-a912-0922ed3e8850`.
- `APPLE_TEAM_ID=36TZ8UKL8W ASC_KEY_ID=R7BYLGVT9L ASC_ISSUER_ID=2d61090e-20f6-4c5c-9868-b0ecb45d51ad BUILD_NAME=1.0.0 BUILD_NUMBER=5 FIREBASE_APP_CHECK_ENABLED=false ./scripts/release_macos_appstore.sh`: archive/export/validation succeeded and produced `build/macos/appstore/VibeRadar.pkg`.
- `pkgutil --check-signature build/macos/appstore/VibeRadar.pkg`: signed by `3rd Party Mac Developer Installer: Angelo Nartey (36TZ8UKL8W)`.
- `xcrun altool --upload-app -f build/macos/appstore/VibeRadar.pkg -t macos`: upload succeeded, delivery/build ID `a14e0c22-d13f-4297-9c20-13f0d91f2932`.
- ASC API confirmed iOS build `fdb26cf9-a4dc-4c68-a912-0922ed3e8850` and macOS build `a14e0c22-d13f-4297-9c20-13f0d91f2932` are `VALID`, attached to the `1.0.0` platform versions, `usesNonExemptEncryption=false`, assigned to `VibeRadar QA`, and submitted through review submissions `dae74ded-d00f-4cf9-b56a-bed487dc3a81` and `4b6f6412-2d4d-489c-80cc-865dfe70fdb1`.
- `flutter build ipa --release --build-name=1.0.0 --build-number=6 --export-method app-store --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed and produced `build/ios/ipa/VibeRadar.ipa`.
- `xcrun altool --validate-app -f build/ios/ipa/VibeRadar.ipa -t ios`: verify succeeded for build 6.
- `xcrun altool --upload-app -f build/ios/ipa/VibeRadar.ipa -t ios`: upload succeeded, delivery/build ID `31c17b48-be81-4abb-b7cc-a582c205c0b8`.
- `APPLE_TEAM_ID=36TZ8UKL8W ASC_KEY_ID=R7BYLGVT9L ASC_ISSUER_ID=2d61090e-20f6-4c5c-9868-b0ecb45d51ad BUILD_NAME=1.0.0 BUILD_NUMBER=6 FIREBASE_APP_CHECK_ENABLED=false ./scripts/release_macos_appstore.sh`: archive/export/validation succeeded and produced `build/macos/appstore/VibeRadar.pkg`.
- `xcrun altool --upload-app -f build/macos/appstore/VibeRadar.pkg -t macos`: upload succeeded, delivery/build ID `0d3f31f6-c265-4d0b-b6ea-4e9bd4a7281b`.
- ASC API confirmed iOS build `31c17b48-be81-4abb-b7cc-a582c205c0b8` and macOS build `0d3f31f6-c265-4d0b-b6ea-4e9bd4a7281b` are `VALID`, attached to the `1.0.0` platform versions, `usesNonExemptEncryption=false`, assigned to `VibeRadar QA`, and submitted through review submissions `bcf1c42d-1b9e-4f1d-99a5-6db8b45029cf` and `b3d9019f-b642-49a1-a0b0-f9554c134341`.
- `flutter build ipa --release --build-name=1.0.0 --build-number=7 --export-method app-store --dart-define=FIREBASE_APP_CHECK_ENABLED=false`: passed and produced `build/ios/ipa/VibeRadar.ipa`.
- `xcrun altool --validate-app -f build/ios/ipa/VibeRadar.ipa -t ios`: verify succeeded for build 7.
- `xcrun altool --upload-app -f build/ios/ipa/VibeRadar.ipa -t ios`: upload succeeded, delivery/build ID `2b3bbaa4-7271-46dc-968d-c11780b54c05`.
- `APPLE_TEAM_ID=36TZ8UKL8W ASC_KEY_ID=R7BYLGVT9L ASC_ISSUER_ID=2d61090e-20f6-4c5c-9868-b0ecb45d51ad BUILD_NAME=1.0.0 BUILD_NUMBER=7 FIREBASE_APP_CHECK_ENABLED=false ./scripts/release_macos_appstore.sh`: archive/export/validation succeeded and produced `build/macos/appstore/VibeRadar.pkg`.
- `xcrun altool --upload-app -f build/macos/appstore/VibeRadar.pkg -t macos`: upload succeeded, delivery/build ID `437272c9-f968-417e-80dc-8accb81c6de9`.
- ASC API confirmed iOS build `2b3bbaa4-7271-46dc-968d-c11780b54c05` and macOS build `437272c9-f968-417e-80dc-8accb81c6de9` are `VALID`, attached to the `1.0.0` platform versions, `usesNonExemptEncryption=false`, assigned to `VibeRadar QA`, and submitted through review submissions `172a8da4-58fe-48fe-bfda-5ad6560ffe33` and `90879f9a-5e99-4367-b2f8-dc44706737ec`.
- `flutter analyze`: passed after the Global/All region fallback fix.
- `flutter test --reporter expanded`: passed with 429 tests after the Global/All region fallback fix.
- `xcrun altool --validate-app -f build/ios/ipa/VibeRadar.ipa -t ios`: verify succeeded for build 8.
- `xcrun altool --upload-app -f build/ios/ipa/VibeRadar.ipa -t ios`: upload succeeded, delivery/build ID `05cfe54f-678c-4ae0-8bcd-416b12269fe2`.
- `APPLE_TEAM_ID=36TZ8UKL8W ASC_KEY_ID=R7BYLGVT9L ASC_ISSUER_ID=2d61090e-20f6-4c5c-9868-b0ecb45d51ad BUILD_NAME=1.0.0 BUILD_NUMBER=8 FIREBASE_APP_CHECK_ENABLED=false ./scripts/release_macos_appstore.sh`: archive/export/validation succeeded and produced `build/macos/appstore/VibeRadar.pkg`.
- `xcrun altool --upload-app -f build/macos/appstore/VibeRadar.pkg -t macos`: upload succeeded after retry, delivery/build ID `b9a2b09c-d206-4413-8eec-4cd525967874`.
- ASC API confirmed iOS build `05cfe54f-678c-4ae0-8bcd-416b12269fe2` and macOS build `b9a2b09c-d206-4413-8eec-4cd525967874` are `VALID`, attached to the `1.0.0` platform versions, `usesNonExemptEncryption=false`, assigned to `VibeRadar QA`, and submitted through review submissions `5c5e7d05-8254-4556-8b2d-2497ce3a7d51` and `73f7abb2-0050-4096-9080-9db240dc4fe7`.
- `npm --prefix functions ci`: passed after installing local Functions tool dependencies; npm warned that the shell uses Node 25 while the project declares Node 22, but installed with 0 vulnerabilities.
- `npm --prefix functions run build`: passed after adding per-entitlement unlimited usage overrides.
- `npm --prefix functions test`: passed after adding entitlement override coverage.
- `git diff --check functions/src/lib/entitlements.ts functions/test/entitlements.test.ts`: passed.
- `firebase deploy --only functions:openaiProxy,functions:spotifyProxy,functions:appleProxy,functions:youtubeProxy,functions:manualIngestTrackSignals --project viberadar-462b8 --non-interactive`: passed after adding the unlimited entitlement override path.
- `firebase functions:list --project viberadar-462b8 | rg "openaiProxy|spotifyProxy|appleProxy|youtubeProxy|manualIngestTrackSignals"`: confirmed all five updated live-cost functions are present on Node.js 22 in `us-central1`.
- Firebase Admin production grant verification confirmed `angelonartey@hotmail.com` (`XNsers0aOehYnWamR6hhn4yNDZv1`) and `cyberzonenas93@gmail.com` (`yOl5QwJUKPZjofGPF1ks02YNuAm1`) have active `studio` entitlement docs with `provider: manual_admin_grant`, `unlimited: true`, `usageLimits` all `-1`, and no `expiresAt` field.

### Required Release QA

- iOS simulator smoke test: onboarding/auth, setlist creation/editing, pairing claim, subscription products/restore.
- macOS smoke test: auth, pairing code creation, shared setlist arrival, setlist management, exports, subscription section.
- Parity check: phone-created setlist appears on desktop and desktop-created/edited setlist appears on phone.
- Screenshot capture for App Store Connect: iPhone 6.9-inch and iPad 13-inch product sets contain real simulator-captured actual app screens, cropped without device frames and processed by ASC. macOS contains real native app-window captures cropped to `1280x800`. Current local upload artifacts are under `docs/qa/screenshots/asc/iphone-69/simctl/app-screens/`, `docs/qa/screenshots/asc/ipad-13/simctl/app-screens/`, `docs/qa/screenshots/asc/macos/native/app-screens/`, plus IAP review capture `docs/qa/screenshots/asc/iap-review/simctl/subscription-products.png`.
- IAP end-to-end validation in Sandbox after App Review/TestFlight install paths are available for the submitted build 10 artifacts.

## Infrastructure

- Firebase project default currently points to `viberadar-462b8`.
- Firebase Hosting serves `build/web`; current Hosting URL is `https://viberadar-462b8.web.app`.
- Hosted Flutter assets include the Gemini-rendered paywall artwork under `assets/assets/paywall/`.
- Public legal/support links:
  - `https://viberadar-462b8.web.app/privacy.html`
  - `https://viberadar-462b8.web.app/support.html`
  - `https://viberadar-462b8.web.app/terms.html`
- Firestore rules: `firestore.rules`.
- Storage rules: `storage.rules`.
- Firestore indexes: `firestore.indexes.json`.
- App Store Server Notification target after Functions deploy:
  - `https://us-central1-viberadar-462b8.cloudfunctions.net/appStoreServerNotification`
- Live cost-gate functions currently deployed with Pro/Studio entitlement enforcement:
  - `openaiProxy`
  - `spotifyProxy`
  - `appleProxy`
  - `youtubeProxy`
  - `manualIngestTrackSignals`
- Firestore `tracks` reads require active Pro/Studio entitlement through `firestore.rules`; backend ingestion remains Admin SDK-owned.
- Spotify onboarding image callable:
  - `https://us-central1-viberadar-462b8.cloudfunctions.net/spotifyOnboardingArtistImages`
  - Accepts only curated onboarding artist names, not arbitrary search terms.
- App Store Connect:
  - App: `VibeRadar DJ` / `6778432071` / `com.viberadar.viberadar`.
  - App availability: all 175 current App Store territories enabled, future territories enabled.
  - Subscription group: `VibeRadar Pro` / `22145074`.
- Products: `viberadar_pro_monthly` (`6778435251`, `$9.99/month`) and `viberadar_pro_yearly` (`6778435163`, `$79.99/year`).
  - TestFlight group: `VibeRadar QA` / `b80d765c-cc20-4912-8ddf-2ad67a1f3cc6`.
  - iOS review submission: `c5caa82d-829d-4f98-9f5f-94081143a428` (`WAITING_FOR_REVIEW`, build 10 `030a8669-1966-44ac-8676-b6a336ff7581`).
  - macOS review submission: `5ff2e775-608d-4736-933f-3da6ab3353de` (`WAITING_FOR_REVIEW`, build 10 `efc7dc1e-5c84-4f57-86c8-2c36c5264cee`).
  - Subscription submissions: monthly `f900334c-ab35-4d46-8db2-c8fd7494de95`, yearly `f8911dfa-33d6-41aa-bf03-196ec8ae9545`.

## CI/CD Notes

- `.github/workflows/ci.yml` now runs Flutter format, analyze, tests with coverage, web build, Functions build/test/audit.
- Functions audit currently passes by overriding transitive `uuid` to `^11.1.1`.
- Release workflows still require Apple signing credentials and App Store Connect/API authentication.

## Refactoring History

### 2026-06-09

- Added IAP model/service/provider/UI and StoreKit purchase sync.
- Added App Store Server API backend transaction verification and notification reconciliation.
- Corrected StoreKit account binding to deterministic UUID `appAccountToken` values accepted by StoreKit 2.
- Added App Store transaction/notification JWS certificate-chain verification using bundled Apple root certificates.
- Hardened OpenAI proxy request sanitization and removed direct client OpenAI API-key UI.
- Added non-anonymous account gates for expensive callables/manual ingest and server-side pairing revocation.
- Moved upload likes to a callable transaction and made direct `user_likes` writes rule-denied.
- Hardened pairing code randomness/throttling and anonymous claim behavior.
- Hardened community upload/profile rules, moderation defaults, and Storage content-type/path constraints.
- Added safe owner-scoped Storage deletion helpers.
- Expanded account deletion to remove entitlements, usage counters, and App Store purchase bindings.
- Added a macOS release-script guard for unexpanded entitlements before codesigning.
- Removed tracked encrypted env artifact and setup script decrypt passphrase.
- Formatted `lib/` and `test/` to satisfy blocking CI.
- Removed tracked Firebase hosting cache artifact from source control.
- Added Mac App Store export scaffolding in `scripts/release_macos_appstore.sh` and `macos/ExportOptions-appstore.plist`.
- Set Firebase App Store Server API secrets from the working Gplus ASC credential path and deployed Functions.
- Captured initial iPhone/iPad onboarding screenshot artifacts for ASC QA.
- Created the ASC app record, configured server notification URLs, created/priced VibeRadar Pro subscriptions, uploaded accepted IAP review screenshots, filled public metadata/support/privacy links, created the TestFlight QA group/tester, and redeployed Functions with the real App Apple ID.
- Made the onboarding artist picker reusable/testable, added constrained backend Spotify image loading for default popular artist choices, and fixed a narrow-phone footer overflow found by widget testing.
- Added `spotifyOnboardingArtistImages` with curated-name validation, max-20 batches, exact-match image selection, 24-hour in-memory cache, and unit coverage for validation/image picking.
- Fixed `macos/Runner/DebugProfile.entitlements` so debug/profile sandbox state matches the release entitlement path.
- Added hidden `ASC_SCREENSHOT_SURFACE=iap` startup mode for real simulator IAP review screenshot capture without changing normal app behavior.
- Switched Mac App Store export to automatic signing with provisioning updates, added macOS App Store category metadata, exported/uploaded/validated the `.pkg`, and attached the processed macOS build to ASC.
- Set ASC app price schedule to Free, published App Privacy labels, set macOS build encryption compliance to `false`, and created the earlier empty review submission draft that was later superseded by final iOS/macOS review submissions.
- Moved artist preference capture out of the pre-auth walkthrough. `AuthGate` now shows `OnboardingArtistPicker` only after real non-guest authentication, persists selections with `UserRepository.setFollowedArtists`, and tracks completion per account with `artist_preferences_completed_v1_{uid}` while migrating old `pending_followed_artists` once.
- Replaced Firebase anonymous guest access with local mock-only guest mode. `FirebaseSessionRepository.signInAnonymously()` now activates `SessionState.demo()` locally, legacy anonymous Firebase users map to demo, `trackStreamProvider` and `userProfileProvider` short-circuit to local data until real auth exists, StoreKit billing does not initialize for guests, and desktop/mobile live-service screens show compact sign-in gates that pass iPhone SE overflow checks.
- Rebuilt fresh iOS/macOS App Store artifacts after the guest-cost gate, validated and uploaded both, attached build 2 to both platform versions, submitted monthly/yearly subscriptions, created separate iOS/macOS review submissions, and reached `WAITING_FOR_REVIEW` for both apps and both subscription products.
- Moved `PairedComputer` state into `lib/providers/paired_computer_provider.dart` so account/setlist logic can use the active pairing without depending on a mobile UI widget.
- Updated `SetlistActions.save` to write account state first, then best-effort push the saved setlist to the active paired computer. Pairing-channel failures are intentionally swallowed after account persistence because the account is the source of truth.
- Updated `PairPhoneScreen` import to seed the local Export Studio through `crateProvider.importCrate` from rich setlist entries before attempting account persistence, making paired handoff useful even when the Mac is not signed into the same account.
- Converted visible product copy from crates to setlists across saved-setlist, onboarding, AI, Set Builder, search, trending, artist bulk-add, command palette, and Export Studio setlist-list surfaces. Physical DJ crate export terminology remains unchanged.
- Changed the macOS Saved Setlists screen from eager card/track rendering to a lazy `ListView.builder` plus bounded per-card previews to prevent large setlists from freezing the desktop UI. Direct exports and Export Studio handoff still use the full track list.
- Added `setlistsProvider` to the ASC product screenshot surface so simulator/native App Store screenshots show populated account setlists instead of an empty Setlists tab.
- Replaced ASC onboarding/sign-in product screenshots with actual app screenshots, deleted stale screenshot assets, and resubmitted iOS/macOS review submissions.
- Created the ASC v2 app availability resource for `6778432071` with all current App Store territories enabled and `availableInNewTerritories=true`; verified 175/175 territory rows report `available=true`. After detecting the previous iOS review submission item had been removed, created and submitted replacement iOS review submission `7142414e-8f04-49b1-ab1f-af5909a5eb35`.
- Rebuilt and submitted ASC build `3` for both iOS and macOS after the setlist parity/performance/pairing fixes. The Mac App Store script now regenerates release config with the pubspec build number and clears stale screenshot-only dart defines before archive.
- Added the 2026-06-10 Pro live-cost gate: moved entitlement reads into shared app state, introduced `liveCatalogAccessProvider`, changed `trackStreamProvider` so signed-in free users see bundled preview tracks, added `ProUpsellBanner`/`ProLockedPanel` outside Settings, gated desktop/mobile cost-heavy routes, blocked desktop auto-ingest/sidebar refresh unless Pro, skipped local-library platform artwork enrichment unless Pro, and made AI/manual-ingest errors point to Pro where applicable.
- Added backend Pro/Studio entitlement enforcement for `openaiProxy`, `spotifyProxy`, `appleProxy`, `youtubeProxy`, and `manualIngestTrackSignals`, while leaving the constrained curated onboarding artist-image callable available separately. Free backend AI/platform defaults in `functions/src/lib/config.ts` and `functions/.env.viberadar-462b8` are now zero.
- Added per-entitlement usage overrides for administrative grants. `unlimited: true` resolves AI, platform proxy, and manual-ingest limits to `-1`, preserving existing global Pro/Studio limits for normal customers while allowing trusted lifetime/internal accounts to bypass usage counters.
- Added the Gemini Pro/paywall artwork pipeline. `scripts/gen_paywall_gemini.js` follows the Gplus repo's Gemini image-generation approach, falls back to the Gplus repo `.env` Developer API key path when Vertex is unavailable, renders optimized PNGs into `assets/paywall/`, and the Pro UI now uses those images in the banner, locked panel, sign-in gate, and subscription sheet with regression widget tests.
- Rebuilt, uploaded, attached, and submitted ASC build `4` for both iOS and macOS after the Pro cost-gate UI and Gemini paywall artwork landed. iOS build `19515410-b0d4-4d24-b404-ac8ecc352b05` and macOS build `f4e60855-5cfc-43b2-a5c8-7c972544aed2` are valid, export-compliance false, assigned to `VibeRadar QA`, and waiting for review through fresh platform review submissions.
- Rebuilt, uploaded, attached, and submitted ASC build `5` for both iOS and macOS after the guest Demo Mode copy cleanup and macOS Info.plist export-compliance update. iOS build `fdb26cf9-a4dc-4c68-a912-0922ed3e8850` and macOS build `a14e0c22-d13f-4297-9c20-13f0d91f2932` are valid, export-compliance false, assigned to `VibeRadar QA`, and waiting for review through fresh platform review submissions.
- Rebuilt, uploaded, attached, and submitted ASC build `6` for both iOS and macOS after sequence-aware Set Builder and Soundcharts AI ranking work. iOS build `31c17b48-be81-4abb-b7cc-a582c205c0b8` and macOS build `0d3f31f6-c265-4d0b-b6ea-4e9bd4a7281b` are valid, export-compliance false, assigned to `VibeRadar QA`, and waiting for review through fresh platform review submissions.
- Rebuilt, uploaded, attached, assigned to `VibeRadar QA`, and submitted ASC build `7` for both iOS and macOS after regional live-catalog source fixes and mobile Set Builder parity. iOS build `2b3bbaa4-7271-46dc-968d-c11780b54c05` and macOS build `437272c9-f968-417e-80dc-8accb81c6de9` are valid, export-compliance false, and waiting for review through fresh platform review submissions.
- Replaced the launch splash's full-screen generated frame sequence with a solid `0xFF0C1015` background behind the smaller procedural radar mark. The splash no longer precaches or bundles `assets/splash/frames/` on launch, and `test/auth/splash_screen_test.dart` guards against reintroducing an image-backed background animation.
- Added `SetFolderPreparationService` and a Saved Setlists `Prepare Folder` action. The flow uses explicit source/destination folder selection, reuses the local library scanner and `LocalMatchService`, copies exact/duplicate/high-confidence fuzzy matches into a setlist-named folder, writes an M3U plus missing/match reports, keeps uncertain filename matches in a review queue, and can append Pro-only AI guidance without sending full local paths.
- Added `docs/qa/maestro/ios_auth_smoke.yaml` as the first reusable Maestro suite. It verifies cold-launch intro onboarding, feature onboarding, the auth gate, and the email sign-in form using real iOS simulator accessibility labels.
- Added `docs/qa/maestro/ios_signed_in_smoke.yaml` for credentialed iOS QA. It loads `MAESTRO_TEST_EMAIL` and `MAESTRO_TEST_PASSWORD` from the environment, verifies Google/Apple/email auth options, signs in with email, confirms the post-auth artist preference gate, and lands in the signed-in free preview shell.
- Added shared Soundcharts AI ranking for live song selection. `SoundchartsAiRankingService` ranks Soundcharts/Shazam/TikTok/Boomplay evidence ahead of generic platform popularity, allows a bounded AI rerank over supplied candidate IDs only, and falls back locally if the AI proxy is unavailable. Set Builder and Greatest Of now use this shared ranker, and `GreatestOfService` boosts ingested Soundcharts evidence in the offline greatest-score calculation.
- Removed customer-facing normal backend connection success copy. `AppBootstrap` no longer emits a successful "Connected to Firebase" status, `SidebarNav` suppresses non-demo infrastructure success messages, guest/free banners now lead with `MOCK SONGS ONLY`, pairing/settings copy no longer references setup internals, and AI Copilot no longer shows generic connected badges.
- Added sequence-aware Set Builder. `SetSequencePlanner` builds opener/warm-up/lift/peak/reset/closer journeys from DJ context, capped Soundcharts/platform candidates, local-library BPM/key metadata, must-play/avoid terms, energy curve, content preference, and behavior profile signals. `AiCrateTrack` now persists phase/confidence/reasons/local/version metadata, exports include reasons, saved setlists record export behavior, and result cards expose move/delete/mark-wrong controls.
- Fixed the Global/All region regression after regional catalog hardening. Global/All now remains global rather than falling back to `GH` or account profile region; selected-region rows require exact Soundcharts/Apple chart evidence; wrong-market chart evidence is penalized; Soundcharts region metadata is parsed into platform results; and mobile/desktop Set Builder defaults are Global/Open Format instead of Ghana/Accra/Afrobeats.
- Rebuilt, uploaded, attached, assigned to `VibeRadar QA`, and submitted ASC build `8` for both iOS and macOS after the Global/All region fallback fix. iOS build `05cfe54f-678c-4ae0-8bcd-416b12269fe2` and macOS build `b9a2b09c-d206-4413-8eec-4cd525967874` are valid, export-compliance false, and waiting for review through fresh platform review submissions.

## Operational Notes

- App Store Connect API authentication works with the Gplus credential path. VibeRadar has an ASC app record, uploaded/attached iOS and macOS build 10 artifacts, actual-app product screenshots, published privacy labels, Free app pricing, all current App Store territories enabled with future territories enabled, and separate iOS/macOS review submissions in `WAITING_FOR_REVIEW` after the 2026-06-12 EULA metadata recovery. If ASC surfaces an updated Developer Program License Agreement during review, only the account holder may accept it.
- `cyberzonenas93@gmail.com` is added as a VibeRadar-specific TestFlight beta tester in the `VibeRadar QA` group. iOS build 10 and macOS build 10 are the current review builds; earlier build 9 artifacts were also assigned during the 2026-06-10 submission.
- Functions, Firestore/Storage rules, and Hosting are live. `syncAppStorePurchase`, `appStoreServerNotification`, `toggleUploadLike`, `revokePairing`, account cleanup, and social counters are deployed.
- As of 2026-06-10, Firestore rules, the five live-cost functions, and Firebase Hosting are redeployed with the Pro cost gate. Backend protection is live even for older native builds.
- As of 2026-06-10, `angelonartey@hotmail.com` and `cyberzonenas93@gmail.com` have active lifetime `studio` grants in `entitlements/{uid}` with `provider: manual_admin_grant`, `unlimited: true`, and `usageLimits` set to `-1` for AI, platform proxy, and manual ingest. Keep these as backend-owned admin grants; do not convert them into fake App Store transactions.
- `spotifyOnboardingArtistImages` is live and verified with real Spotify CDN image responses. Keep the general `spotifyProxy` full-account-only.
- Firebase Hosting was redeployed after the onboarding artist-image change so the hosted web app matches the current Flutter code.
- The real numeric `APP_STORE_APP_APPLE_ID=6778432071` is set in `functions/.env.viberadar-462b8`, and Functions were redeployed.
- ASC iPhone/iPad product screenshots and IAP review screenshots are uploaded from real simulator captures and processed complete; macOS product screenshots are uploaded from native captured/cropped app windows. Do not replace them with rendered/composited assets or onboarding-only screenshots.
- Run Sandbox purchases from both iOS and macOS after Apple makes submitted build 10 available through review/TestFlight install paths.
- On 2026-06-09, generated Xcode DerivedData and local Flutter iOS/macOS build products were removed to recover disk after a simulator build failed from exhausted storage. These are regenerable caches/artifacts and must be rebuilt before release screenshots or uploads.
- Do not upload rendered/composited product screenshots to ASC. User explicitly requires real simulator-captured, cropped screenshots.
- Artist preferences are account data. Do not collect "Choose Your Artists" before authentication; keep the picker behind real sign-in so selected artists are saved to the active user profile.
- Guest mode is a cost-control boundary. Do not reintroduce Firebase anonymous sign-in for guests or let guest/demo UI paths call Firestore, Storage, Functions, StoreKit, Spotify, Apple Music, YouTube, OpenAI, pairing, or community providers. Guest-visible data must be bundled sample data and must show a Demo Mode banner that clearly says the data is not real.
- Signed-in free mode is also a cost-control boundary for live intelligence. Do not let free users read Firestore `tracks` or call platform/AI/ingestion workflows. If adding a live-service screen, route it through `liveCatalogAccessProvider` and show `ProLockedPanel`/`ProUpsellBanner` when `requiresUpgrade` is true.
- Customer-facing startup/navigation chrome should not expose normal backend-provider connection labels. Use logs for operator diagnostics, and reserve visible status pills for demo/mock warnings or actionable refresh/degraded-service states.
- Live-platform AI ranking is intentionally bounded. Keep the candidate window small, keep AI output restricted to supplied IDs, and preserve deterministic local fallback so Set Builder and Greatest Of do not fail when OpenAI quota/auth/network is unavailable.
- Sequence-aware Set Builder is intentionally local after candidate fetch. Do not add extra OpenAI calls for planning/reasons unless the call is capped and constrained to existing candidate IDs. The local behavior profile is enough for this release; a cross-device Firestore taste profile would require privacy-label review and explicit product approval.
- Splash-screen rule: keep only the smaller procedural radar animation moving on launch. The background should remain a solid color that matches the radar palette, not another video/frame sequence.
- Fresh iOS and macOS ASC artifacts were rebuilt after the chart-quality/cache fixes and are the build 10 artifacts currently waiting for review.
- Native ASC build 10 includes the 2026-06-10 client-side Pro upsell/locked-panel UI, Gemini-rendered paywall artwork, latest guest Demo Mode copy, restored platform play actions, Soundcharts-backed AI ranking, sequence-aware Set Builder, chart-evidence-anchored regional catalog results, mobile Set Builder parity, the Global/All region fallback fix, worldwide Soundcharts proxy hardening, and the build-10 client chart-quality fixes. It does not include the later 2026-06-12 platform-first sourcing restoration until a new native build is produced and uploaded.
- Desktop setlist preparation is implemented as a separate explicit-consent local flow. The Mac app may search only a user-selected/scanned music folder, then create a user-selected destination folder named after the setlist, copy confident local matches, and write TIDAL/platform/manual acquisition fallbacks for missing tracks. Do not wire this into or regress the existing TIDAL/VirtualDJ export path; Pro-only AI assistance is advisory and must never block local folder creation.
- The 2026-06-10 Amapiano QA used a temporary local harness under `tool/`, then deleted it after verification because it hardcoded `/Users/angelonartey/Downloads/amapiano`. Recreate as a temporary/local test only if a future machine-specific disk QA is requested.
- Setlist parity rule: user-facing account-managed saved music is "Setlist" on both phone and Mac. Keep "crate" only for internal model names, legacy storage fields, AI fenced-response grammar, and physical DJ crate/export formats.
- Paired phone saves should now show up in both account sync and the active pairing channel. If a computer is offline/revoked, the phone account save still succeeds and the paired handoff can be retried.
- Mac pairing import no longer relies solely on signed-in account persistence; it also loads the setlist into the local Export Studio for immediate match/export.
- Large saved setlists should not render every row in the macOS Saved Setlists card. Preserve the bounded preview unless replacing it with a virtualized nested list.
- Maestro CLI is installed at `~/.maestro/bin/maestro` (version 2.6.0 as of 2026-06-10) rather than on the shell `PATH`. Java 25 currently emits Jansi restricted-native-access warnings, but the CLI still runs successfully.
- Maestro iOS flows should use `clearKeychain: true` with `clearState: true`; Firebase Auth can otherwise restore a previous iOS keychain session and bypass the login screen. Test credentials live in ignored `outputs/maestro/credentials.env` with `0600` permissions.
- Maestro cannot drive native macOS app windows in this environment. For macOS QA, use Maestro only to document the unsupported target boundary, then use Flutter build/tests plus native macOS launch, System Events/cliclick interaction, and screenshots.

## Known Limitations

- Runtime iOS launch QA succeeded for simulator screenshot surfaces, and ASC accepted 5 actual-app iPhone screenshots plus 5 actual-app iPad screenshots. Full live parity QA remains incomplete until submitted build 10 artifacts are available through review/TestFlight install paths.
- macOS debug/release packaging succeeds, and ASC accepted 4 actual-app native macOS screenshots.
- App Check enforcement remains a production activation step requiring Firebase App Check registration, env update, and Functions redeploy.
- iOS, macOS, and the first monthly/yearly subscriptions are submitted and waiting for Apple review.
- The live Pro cost gate is deployed to backend/web and included in native iOS/macOS build 10 waiting for review.
- The hosted web app includes the Gemini paywall graphics and updated Terms/EULA link; native build 10 includes the same Pro artwork and subscription surfaces.
- The repository still has a large dirty worktree with pre-existing/generated splash, onboarding, UI, and platform changes. Review the final diff before commit/submission packaging.

## 2026-06-12 Platform-First Music Sourcing Operations Update

- `PlatformSearchService` is again the cross-provider live music source for Apple Music, Spotify, YouTube, Deezer, and Soundcharts. New song-selection work should call this service rather than reading Firestore `tracks` or hand-calling individual provider services from UI code.
- `fetchTrendingChartTracks` keeps its historical name for compatibility, but it now merges cached Soundcharts evidence, optional Apple storefront charts, Spotify market search, Apple Music storefront search, YouTube, and Deezer. Do not assume every returned row has chart evidence.
- `enrichPlaybackLinksForResults` restores user-facing playback actions for chart-heavy rows by searching only the missing music services for the top candidate window. Keep the cap small and keep match acceptance strict; this exists to prevent rows from showing only `View on Soundcharts`.
- Selected-region behavior is storefront/market-aware rather than chart-only. Exact Soundcharts/Apple chart evidence should improve ordering and confidence, but platform-only rows with streaming URLs are allowed so Ghana/other regions do not collapse to narrow or stale chart feeds.
- `SoundchartsAiRankingService` should be read as a live-platform ranker despite its legacy name. AI reranking is allowed when the candidate window contains any live platform evidence, and AI must still return only supplied candidate IDs.
- Validation run on 2026-06-12: targeted Dart analysis for touched source/test files passed; focused `flutter test test/services/platform_search_service_test.dart test/services/live_track_catalog_service_test.dart test/widgets/platform_play_actions_test.dart test/mobile/search_tab_test.dart --reporter expanded` passed with 14 tests; `flutter analyze` passed; full `flutter test --reporter expanded` passed with 434 tests.

## 2026-06-10 Soundcharts Live Search / AI Operations Update

- Added and deployed `soundchartsProxy`, a Pro-gated callable in `functions/src/proxy.ts`. It is the live Soundcharts access path for clients; do not call Soundcharts directly from Flutter. It validates requested regions/platforms, uses configured Soundcharts secrets, filters noisy builder/search terms, merges duplicate Soundcharts hits, and returns scored track evidence with source/region metadata.
- `PlatformSearchService` owns cross-provider search. As of the later 2026-06-12 restoration, it covers Apple Music, Spotify, YouTube, Deezer, and Soundcharts.
- AI Copilot now uses `gpt-4.1` by default and only allows `gpt-4.1` or `gpt-4o-mini` from the client settings UI. Stale stored/local `gpt-5.4` model preferences are ignored and removed by `AiCopilotService.getModel()`.
- Soundcharts is now wired into Set Builder, Greatest Of platform augmentation, desktop/mobile search, and AI crate/setlist resolution. AI setlist tracks can persist `soundchartsUrl`, `soundchartsSource`, and `soundchartsRegion` in `AiCrateTrack` JSON.
- Set Builder and Greatest Of use `SoundchartsAiRankingService` for live-platform ranking plus bounded AI reranking; Greatest Of's local scoring also rewards ingested Soundcharts evidence.
- Production deploy command run: `firebase deploy --only functions:soundchartsProxy,functions:openaiProxy --project viberadar-462b8 --non-interactive`. Verification command run: `firebase functions:list --project viberadar-462b8 | rg "soundchartsProxy|openaiProxy"`.
- Validation run on 2026-06-10: `npm --prefix functions run build`; `npm --prefix functions test`; targeted `dart analyze` for touched Dart files; `flutter analyze`; focused `flutter test test/mobile/search_tab_test.dart test/mobile/ai_tab_test.dart test/desktop/greatest_of_service_test.dart --reporter expanded`; full `flutter test --reporter expanded` with 410 passing tests; `git diff --check`.
- Follow-up validation run on 2026-06-10 after adding shared Soundcharts AI ranking: targeted Dart analysis passed; `flutter analyze` passed; focused `flutter test test/services/soundcharts_ai_ranking_service_test.dart test/desktop/greatest_of_service_test.dart --reporter expanded` passed with 37 tests; full `flutter test --reporter expanded` passed with 414 tests; `npm --prefix functions run build` passed; `npm --prefix functions test` passed.

## 2026-06-10 Mock-Song Disclosure / Connected-Status Operations Update

- Successful bootstrap should provide an empty UI status message. Do not restore a `Connected to Firebase` banner or green connected status pill for normal operation.
- Guest/demo and signed-in free-preview surfaces must use direct copy such as `MOCK SONGS ONLY` and explain that visible songs are sample tracks, not real live songs or trend data.
- Product-facing copy should say "live catalog", "live services", or "real account data" instead of exposing Firebase/Auth setup details. Backend/provider names can remain in logs, tests, developer docs, and operational notes.
- Validation run on 2026-06-10: targeted Dart analysis for the touched UI/test files passed; focused widget/mobile tests passed with 8 plus 9 tests; `flutter analyze` passed; full `flutter test --reporter expanded` passed with 417 tests; `git diff --check` passed.

## 2026-06-10 Sequence-Aware Set Builder Operations Update

- `SetSequencePlanner` is the owner of DJ journey sequencing. It should receive real `PlatformTrackResult` candidates and produce phase-labeled `SequencePlannedTrack` values; UI code should not independently invent journey ordering.
- `DjSetContext` captures event type, city/market, crowd age, genre lane, energy curve, clean/explicit preference, set length, hard-switch preference, must-play terms, and avoid terms. Keep new context fields additive and pass them through the planner summary when asking bounded AI to rank candidates.
- `SetBuilderBehaviorService` stores local profile state in `SharedPreferences` as `set_builder_behavior_profile_v1`. Save/export/reorder are positive signals; delete/mark-wrong are negative signals; search-again increments dissatisfaction count. Batch export recording uses one local write for long saved setlists.
- Saved Set Builder tracks persist phase/confidence/reasons/local/version metadata in `AiCrateTrack`; `ExportService` includes phase/confidence/reasons in AI crate CSV and manifest exports.
- Validation run on 2026-06-10: `dart format` passed for touched Dart files; targeted `dart analyze` passed; focused `flutter test test/services/set_sequence_planner_test.dart test/services/set_builder_behavior_service_test.dart test/services/soundcharts_ai_ranking_service_test.dart test/set_builder_service_test.dart --reporter expanded` passed with 10 tests; `flutter analyze` passed; full `flutter test --reporter expanded` passed with 423 tests.

## 2026-06-10 Platform Play Actions Operations Update

- `lib/ui/widgets/platform_play_actions.dart` is the shared owner for visible song platform controls. Prefer it over one-off `IconButton`/`InkWell` URL launchers when a song can have Spotify, Apple Music, YouTube, Soundcharts, TIDAL, Deezer, SoundCloud, Audius, Beatport, or Billboard links.
- Use `PlatformPlayActions.fromUrls(...)` for `PlatformTrackResult`/`AiCrateTrack` style objects and `PlatformPlayActions(links: track.platformLinks)` for `Track` objects. Keep compact icon-only mode for dense tables/cards, and labeled `PlatformPlayLabelStyle.platform` or `playOnPlatform` where row width allows.
- Platform ordering is deterministic: Spotify, Apple Music, YouTube, TIDAL, Soundcharts, Deezer, SoundCloud, Audius, Beatport, Billboard, then any remaining cleaned keys. Empty URLs and duplicate URLs are filtered.
- Customer-facing action labels should come from `platformActionLabel()`. Music services use `Play on ...`; Soundcharts uses `View on Soundcharts`.
- Restored surfaces on 2026-06-10: desktop search, YouTube results, track intelligence table, track detail panel, track action menu, mobile search tooltip copy, mobile setlist editor rows, desktop Saved Setlists, playlist aggregation cards, Greatest Of platform rows, and Artist radar/unified/list rows.
- Validation run on 2026-06-10: `flutter analyze` passed; `flutter test test/widgets/platform_play_actions_test.dart test/mobile/search_tab_test.dart test/mobile/setlist_editor_test.dart test/desktop/screen_smoke_test.dart` passed with 24 tests; `git diff --check` passed.

## 2026-06-10 Global Worldwide Soundcharts and ASC Build 9 Operations Update

- Global/All must remain worldwide. Client defaults, mock profiles, ASC screenshot seed data, Settings options, desktop Regions, and `PlatformSearchService` now use `Global` rather than silently falling back to Ghana or profile defaults.
- Backend Soundcharts worldwide mode uses internal region `GLOBAL` and an empty Soundcharts `countryCode`. `resolveSoundchartsProxyInput` maps no region, `All`, and `Global` to `GLOBAL` rather than expanding to configured regional defaults.
- `selectCharts(..., "GLOBAL")` must select only worldwide charts where Soundcharts `countryCode` is empty. Do not reintroduce configured-region fanout for omitted region requests; that was the source of the Ghana lock.
- Production deployment run on 2026-06-10: `firebase deploy --only functions:soundchartsProxy --project viberadar-462b8 --non-interactive`; `flutter build web --release --no-wasm-dry-run --dart-define=FIREBASE_APP_CHECK_ENABLED=false`; `firebase deploy --only hosting --project viberadar-462b8 --non-interactive`.
- Native release run on 2026-06-10: bumped `pubspec.yaml` to `1.0.0+9`; built/validated/uploaded iOS IPA `build/ios/ipa/VibeRadar.ipa`; archived/exported/validated/uploaded macOS package `build/macos/appstore/VibeRadar.pkg`.
- ASC build 9 final state: iOS build `12ae5d34-7cdc-4c56-8e05-555d78c7a65e`, review submission `c8cf5193-e6b2-49cc-be8e-86d96043ffaa`; macOS build `5f774c7a-cbf9-44c6-a442-d33cef859610`, review submission `1d98a95d-a880-4a40-83f4-400b227dc440`. Both versions are `WAITING_FOR_REVIEW`, builds are `VALID`, `usesNonExemptEncryption=false`, and both builds are assigned to `VibeRadar QA`.
- Validation run on 2026-06-10: focused Dart analysis passed; focused Flutter tests passed with 8 tests; `npm --prefix functions run build` passed; `npm --prefix functions test` passed; full `flutter analyze` passed; full `flutter test --reporter expanded` passed with 429 tests; iOS `altool` validation/upload succeeded; macOS archive/export/package validation/upload succeeded; ASC API verification confirmed both platform versions are attached to build 9 and waiting for review.

## 2026-06-11 Chart Quality, Quota, and Cache Operations Update

- Soundcharts chart selection is now intent-ranked through `chartPriority` in `functions/src/clients/soundcharts.ts`: "Top 200" > "Top N" > "Daily N" > "Hot N" > generic "Top" > viral/trending > misc > genre charts. Charts whose name/slug matches christian/gospel/worship/on-radio are excluded at selection time. Never select charts by raw list order: the Soundcharts list is alphabetical, so list order selected "AfroBeats"/"Afrobeats on Radio" for Global and US Country/Dance genre charts for US while every "Top 200" chart sorted last and was never picked.
- Chart-list discovery follows pagination up to 4 pages (`MAX_CHART_LIST_PAGES`). Shazam worldwide alone has 323 charts; page 1 ends before most country "Top 200" charts.
- All Soundcharts HTTP GETs from `soundchartsProxy` and `ingestSoundchartsDaily` go through `withSoundchartsCache` (`functions/src/lib/soundchartsCache.ts`), a Firestore-backed cache in the server-only `soundcharts_cache` collection: chart lists cache 24h, rankings 6h, store failures degrade to live fetches. This is load-bearing budget protection: the free key has ~1k total calls and was down to 259 remaining on 2026-06-11 after a single uncached trending refresh burned ~540 calls on 2026-06-10.
- `soundchartsProxy` popularity/trendScore weighting is 0.7 engagement (chart position) + 0.15 growth + 0.15 recency. Do not return to equal weighting: it made a brand-new #53 chart entry outscore the long-charting #2 hit and inverted chart order in returned results.
- Client trending no longer goes through `searchByGenre('music')`. `LiveTrackCatalogService` calls `PlatformSearchService.fetchTrendingChartTracks`; this was chart-evidence-only on 2026-06-11, but the 2026-06-12 product decision restored Apple Music, Spotify, YouTube, and Deezer as row-creating sources while keeping Soundcharts and Apple chart evidence as ranking boosts. The old pre-cache path issued 10 stopword-equivalent queries per refresh (~2.5 minutes at 15-18s each).
- `_searchSoundcharts` canonicalizes queries to selection tokens before caching/sending, so stopword-variant queries from `searchByGenre` ("best X songs", "top X hits") dedupe into one proxy call.
- Deployment run on 2026-06-11: `firebase deploy --only functions:soundchartsProxy,functions:ingestSoundchartsDaily --project viberadar-462b8 --non-interactive` succeeded; `flutter build web --release --no-wasm-dry-run --dart-define=FIREBASE_APP_CHECK_ENABLED=false` succeeded; `firebase deploy --only hosting --project viberadar-462b8 --non-interactive` succeeded and the site returns HTTP 200.
- Validation run on 2026-06-11: `npm --prefix functions run build` passed; `npm --prefix functions test` passed including new `soundchartsCache.test.ts` and chart-priority/pagination/scoring regression tests; `flutter analyze` passed; full `flutter test` passed with 430 tests; a live end-to-end probe with production credentials confirmed Global now ranks `shazam-top-200-world` first and returns the worldwide Top 200 in chart order.
- Note: native build 9 was the prior review build and still ran the old 10-query client; build 10 supersedes it in App Review and carries the single-call client path.

## 2026-06-11 ASC Build 10 Operations Update

- Native build 10 (`1.0.0+10`) replaces build 9 in App Review and carries the client-side chart-quality fixes: `fetchTrendingChartTracks` single-call trending, chart-evidence-required Global rows, and canonicalized Soundcharts queries. Server-side chart selection/scoring/cache fixes were already live for all builds.
- Release run on 2026-06-11: `flutter build ipa --release --dart-define=FIREBASE_APP_CHECK_ENABLED=false` → `build/ios/ipa/VibeRadar.ipa`; `APPLE_TEAM_ID=36TZ8UKL8W ./scripts/release_macos_appstore.sh` → `build/macos/appstore/VibeRadar.pkg`; both validated and uploaded with `xcrun altool` using ASC key `R7BYLGVT9L`.
- ASC state: iOS build `030a8669-1966-44ac-8676-b6a336ff7581` and macOS build `efc7dc1e-5c84-4f57-86c8-2c36c5264cee` are `VALID`, attached to the `1.0.0` versions, assigned to `VibeRadar QA`, `usesNonExemptEncryption=false`. Build 9 submissions `c8cf5193`/`1d98a95d` were canceled; new submissions are iOS `0edee41d-b912-4d7f-b0e8-a86b6e169586` and macOS `60b2a249-edfa-4363-bb82-b0b7a54074e9`, both `WAITING_FOR_REVIEW`.
- ASC REST operations (cancel/attach/beta-assign/submit) were performed with a short-lived ES256 JWT generated from `~/.appstoreconnect/private_keys/AuthKey_R7BYLGVT9L.p8` (issuer `2d61090e-20f6-4c5c-9868-b0ecb45d51ad`). Cancel old submissions BEFORE PATCHing the version build relationship; wait for `CANCELING` to clear before POSTing new `reviewSubmissions`.

## 2026-06-12 Genre Catalog Operations Update

- `lib/core/config/music_genres.dart` is the shared source for supported genre controls. It exposes `kCanonicalMusicGenres`, `kGenreFilterOptions`, and `mergedGenreOptions(...)` for screens that need to combine canonical lanes with discovered local/custom genres.
- Desktop/mobile genre controls updated on 2026-06-12: main `availableGenresProvider`, Trending, Regional Pulse, Genre Landscape, Greatest Of, Set Builder slot dropdowns, playlist aggregation, search discovery chips, library filter, artist filter, community profile chips, community upload metadata, and mobile Set Builder defaults/fallbacks.
- Product rule: the live catalog may currently contain only `Open Format`/`Afrobeats`, but the UI must still expose the broader DJ catalog. Selecting a genre can still yield no rows in a pure filter view; search/set-builder/playlist flows should treat the selected genre as a live query.
- Validation run on 2026-06-12: `dart format` passed for touched Dart/test files; focused `dart analyze` passed; focused `flutter test test/core/music_genres_test.dart test/providers/guest_mode_provider_test.dart --reporter expanded` passed with 7 tests; `flutter analyze` passed; full `flutter test --reporter expanded` passed with 433 tests; `git diff --check` passed.

## 2026-06-12 ASC EULA Metadata Recovery Operations Update

- Apple rejected both build-10 app-version submissions under Guideline `3.1.2 Business: Payments - Subscriptions` because the auto-renewable-subscription metadata did not include a functional Terms of Use/EULA link in the App Description.
- Rejected submission IDs were iOS `0edee41d-b912-4d7f-b0e8-a86b6e169586` and macOS `60b2a249-edfa-4363-bb82-b0b7a54074e9`. Both showed the same Resolution Center message in App Store Connect.
- Fixed via metadata and hosting, not a binary rebuild: patched both ASC `en-US` version descriptions to include `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`, `https://viberadar-462b8.web.app/privacy.html`, and `https://viberadar-462b8.web.app/support.html`; updated `web/terms.html` and `build/web/terms.html` to link Apple's standard EULA; deployed Firebase Hosting.
- Cancelled the unresolved rejected submissions, waited for `CANCELING` to clear, created fresh review submissions, and submitted the existing valid build-10 binaries. Current review submissions: iOS `c5caa82d-829d-4f98-9f5f-94081143a428`; macOS `5ff2e775-608d-4736-933f-3da6ab3353de`; both report `WAITING_FOR_REVIEW`.
- Current build attachments remain iOS build `030a8669-1966-44ac-8676-b6a336ff7581` and macOS build `efc7dc1e-5c84-4f57-86c8-2c36c5264cee`, both build number `10`, `VALID`, and `usesNonExemptEncryption=false`.
- Validation run on 2026-06-12: ASC API verified both descriptions contain the EULA link and both platform versions are `WAITING_FOR_REVIEW`; Firebase Hosting deploy succeeded; `curl -fsSI https://viberadar-462b8.web.app/terms.html` returned HTTP 200; `curl` content check confirmed the Apple EULA URL is live; App Store Connect browser UI visibly showed iOS `Waiting for Review`. The macOS ASC browser page spinner lagged, but ASC API confirmed macOS `WAITING_FOR_REVIEW`.

## 2026-06-15 Genre-Aware Recommendations & Charts Operations Update

- Root cause audited: the selected genre was dropped before retrieval and mishandled in filtering. `LiveTrackCatalogService.fetchTrendingTracks`/`PlatformSearchService.fetchTrendingChartTracks` fetched by region only; client genre filters used exact `==` against heterogeneous labels (Apple `Hip-Hop/Rap`, Soundcharts regional defaults, `Open Format` for null), so any non-`All` selection nuked the feed; `_selectionScore` had no genre term; and the region penalty (`-120/-45`) buried genre-fit streaming rows.
- Genre intelligence now lives in `lib/core/config/music_genres.dart`: `canonicalGenre`, `genreMatches` (tolerant token-set match — compound, separator, plural, and parent↔subgenre families all match; `Open Format`/null/`All` handled), and `isSpecificGenre` (false for `All`/unknown/comma-joined multi-lane strings). These are the single source of truth for genre matching across the app.
- Retrieval is now genre-aware: `fetchTrendingChartTracks({region, genre})` and `fetchTrendingTracks({region, genre})` accept a lane; a specific lane drives genre-scoped Spotify/Apple/YouTube/Deezer queries, filters Apple/Soundcharts chart feeds to the lane, gates out known off-genre rows in `_merge`, boosts genre fit and softens the region gate in `_selectionScore`, and stamps the lane onto genre-discovered streaming rows that carry no genre (so the downstream filter keeps them). `searchByGenre` gained a `genreLane` param wired from desktop/mobile Set Builder and Greatest Of.
- Provider wiring: new `selectedGenreProvider` (null = All); `trackStreamProvider` watches it and refetches genre-scoped. Trending dropdown and the desktop Genres view now set the provider (full-catalog dropdowns, so no chip collapse). Home tab keeps its feed-derived quick chips as a tolerant post-filter only (no refetch) to avoid chip-set collapse.
- `genre=All`/null behavior is byte-for-byte unchanged (no gating, no stamping, original region penalties), so the broad charts/trending feed and Soundcharts worldwide path are untouched.
- Backend Soundcharts was intentionally NOT changed: the free Soundcharts budget is tight (~259 calls left) and for specific-genre selections the regional charts are mostly off-genre and would be gated client-side anyway. Soundcharts remains the driver for the broad (`All`) charts feed. No Functions redeploy was required by this change.
- Files: `lib/core/config/music_genres.dart`, `lib/services/platform_search_service.dart`, `lib/services/live_track_catalog_service.dart`, `lib/models/track_filters.dart`, `lib/providers/app_state.dart`, `lib/ui/features/trending/trending_screen.dart`, `lib/ui/features/home/home_screen.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/shell/vibe_shell_views.dart`, `lib/ui/shell/vibe_shell_setbuilder.dart`, `lib/ui/features/greatest_of/greatest_of_screen.dart`, `lib/ui/mobile/mobile_set_builder_tab.dart`, plus tests `test/core/music_genres_test.dart`, `test/services/platform_search_genre_test.dart`, `test/services/live_track_catalog_service_test.dart`, `test/models/track_filters_genre_test.dart`, `test/providers/genre_refetch_test.dart`, `test/providers/guest_mode_provider_test.dart`.
- Validation run on 2026-06-15: `flutter analyze` → `No issues found!`; `dart format --output=none --set-exit-if-changed lib/ test/` → 0 changed; full `flutter test` → 454 passed (433 prior + 21 new); `git diff --check` clean. Not yet shipped: web needs a Hosting redeploy and iOS/macOS need a native rebuild + ASC resubmission to carry this into review binaries.

## 2026-06-15 App Store Rejection-Risk Audit Operations Update

- macOS account deletion (5.1.1(v)) was the only HARD gap: desktop Settings (`vibe_shell_views.dart` `_SettingsView`) had Create Account/Sign Out but no deletion. Added `desktop_delete_account_button` + `_confirmDeleteAccount()` calling `accountDeletionServiceProvider.deleteAccount()` then best-effort sign-out; shown only when `session.isAuthenticated && !isDemo`. `vibe_shell_views.dart` is `part of vibe_shell.dart`, so the `cloud_functions` and `account_deletion_service` imports were added to the parent `vibe_shell.dart`.
- iOS `NSMicrophoneUsageDescription` removed — genuinely unused (no audio recording anywhere; the only `.record(...)` is `SetBuilderBehaviorService`, behavior analytics). Keep `NSCameraUsageDescription` (mobile_scanner QR pairing), `NSPhotoLibraryUsageDescription` (file_picker image uploads/avatars; PHPicker means it's belt-and-suspenders, kept to avoid any fallback crash), and `UIBackgroundModes: remote-notification` (FCM).
- `SubscriptionSection` now renders the 3.1.2 disclosure block at the point of purchase for ALL entry points (it's a shared widget used by the sign-in gate, mobile/desktop settings, and the paywall sheet): `subscription_auto_renew_disclosure` Text + `_LegalLink` buttons to hosted `terms.html` (which links Apple's standard EULA) and `privacy.html`. Removed the duplicate auto-renew line that `app.dart` rendered separately.
- Already-compliant (verified, no change): UGC moderation (`moderation_actions.dart` report+block, upload-screen zero-tolerance agreement) for Guideline 1.2; Sign in with Apple alongside Google/Email (4.8); hidden `ASC_SCREENSHOT_SURFACE` gated by `String.fromEnvironment` (empty in prod → unreachable, no 2.3.1 risk); macOS sandbox entitlements match usage.
- Test note: adding the disclosure made the mobile settings sheet taller, so `test/mobile/account_deletion_test.dart` now `ensureVisible`s the `delete_account_button` before tapping (the sheet is a `SingleChildScrollView`; real-app reachability is unaffected). New `test/widgets/subscription_disclosure_test.dart` locks in the 3.1.2 block (overriding only `sessionProvider` with an unauth session keeps `BillingController.build()` off StoreKit).
- Validation run on 2026-06-15: `flutter analyze` → `No issues found!`; `plutil -lint ios/Runner/Info.plist` → OK; full `flutter test` → 455 passed; `dart format` gate → 0 changed; `git diff --check` clean. These are binary changes — they require a new iOS/macOS build + ASC resubmission to take effect in review (build 10 does not include them).

## 2026-06-16 Apple Music On-Demand MusicKit Token Operations Update

- The Apple Music developer token is now generated on demand in `functions/src/lib/appleMusicToken.ts` (`generateAppleMusicToken` pure + `getAppleMusicDeveloperToken` cached), signed with Node `crypto.sign("sha256", data, {key, dsaEncoding:"ieee-p1363"})`. The `ieee-p1363` encoding is REQUIRED — a DER ES256 signature makes Apple Music API return a generic `500 "An unexpected error occurred"`, which is the trap the old static token fell into.
- Secrets bound to `appleProxy`, `ingestTrackSignals`, `manualIngestTrackSignals`: `APPLE_MUSIC_PRIVATE_KEY` (AuthKey_NUSAWKGJ7X.p8 contents), `APPLE_MUSIC_KEY_ID=NUSAWKGJ7X`, `APPLE_MUSIC_TEAM_ID=36TZ8UKL8W`. Legacy `APPLE_MUSIC_DEVELOPER_TOKEN` kept only as a fallback; can be deleted later.
- Diagnostic trick worth reusing: to identify which `.p8` is a MusicKit (vs APNs/ASC) key, sign a test ES256 token with each (`jsonwebtoken`/node crypto) and hit `https://api.music.apple.com/v1/catalog/us/search` — the MusicKit key returns `200`, others `401`. NUSAWKGJ7X serves BOTH APNs (push) and MusicKit here. The proxy wraps all non-2xx as `HttpsError("internal", "Apple Music API error: <status>")`, so read the upstream status, not the wrapped message.
- Deploy: `firebase deploy --only functions:appleProxy,functions:ingestTrackSignals,functions:manualIngestTrackSignals --project viberadar-462b8 --non-interactive` succeeded; all three are live on nodejs22/us-central1. Verified the live `appleProxy` returns `200` with real songs for a (temporarily Pro-granted, then revoked) QA account.
- Validation: `npm --prefix functions run build` + `npm --prefix functions test` passed (new `test/appleMusicToken.test.ts` asserts the signature validates as JOSE and NOT as DER, claims are Apple-shaped, and TTL is clamped to ~6 months).

## 2026-06-16 YouTube Proxy Quota Cache Operations Update

- `youtubeProxy` now caches via `functions/src/lib/youtubeCache.ts` (`youtube_cache` Firestore collection, 24h TTL), mirroring `soundchartsCache`. `youtubeCacheKey(path, query)` sha1s `path?<sorted query>` EXCLUDING the injected `key` param, so the key is stable and never embeds the secret. `cachedYoutubeGet` = read→(fresh? serve)→fetch→write, and on fetcher error returns a STALE entry if present (graceful 429 handling).
- Why: YouTube `search.list` is 100 quota units; default ~10k/day ≈ 100 searches. The live catalog/Set Builder/search paths fan out many identical searches → fast 429. Cache makes identical queries cost one upstream call per 24h, shared across all users.
- Deployed `functions:youtubeProxy` only (ingestion uses `fetchYouTubeSignals` directly, a separate scheduled/bounded path — cache it too if it starts 429ing). Collection is server-only (admin SDK bypasses rules; clients never read it) so no firestore.rules change needed, same as `soundcharts_cache`.
- Verified the deployed cache-hit path by seeding a `youtube_cache` doc and confirming the live proxy returned it at HTTP 200 with zero YouTube calls (a direct live call still 429s until the daily quota resets ~midnight Pacific). New `test/youtubeCache.test.ts` covers key determinism, miss→write, fresh hit, expiry, stale-on-429, and rethrow-when-empty. `npm --prefix functions run build` + `npm --prefix functions test` pass.
- Tuning knobs: `YOUTUBE_CACHE_TTL_MS` (24h) — raise for more savings / lower for fresher results. If still quota-bound, also cache the ingestion YouTube path and/or request a higher YouTube Data API quota in Google Cloud console.

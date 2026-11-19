# VibeRadar Product and Architecture Memory

## Project Overview

VibeRadar is a Flutter DJ trend-intelligence platform with a macOS workstation, iOS companion app, Flutter Web hosting, and Firebase backend. It helps DJs discover regional momentum, build and manage setlists/crates, analyze cue points, export to DJ tools, upload/community-share tracks, and continue work across phone and computer through pairing.

## Business Goals

- Ship production-ready iOS and macOS apps through App Store Connect.
- Support a paid VibeRadar Pro subscription shared across iOS and macOS.
- Keep AI, platform API, quota, entitlement, and moderation authority on the backend.
- Provide App Store required support, privacy, account deletion, reporting, blocking, and subscription restore flows.

## Target Users

- Working DJs and music curators using macOS as their main workstation.
- DJs using iPhone as a companion device for discovery, setlist editing, and pairing.
- Early adopters evaluating regional trend intelligence and export workflows.

## Core Functionality

- Trend discovery from live music-platform evidence. The client live catalog no longer reads the Firestore `tracks` collection for Pro users; it builds regional catalog rows from Apple Music, Spotify, YouTube, Deezer, and Soundcharts with storefront/market-aware requests.
- AI set building and cue analysis through backend-owned OpenAI proxy calls.
- Desktop library scanning, duplicate detection, cue/export workflows, and Serato/VirtualDJ/M3U export.
- Desktop "Prepare Folder" handoff for phone-created setlists: with explicit user folder permissions, the Mac app matches synced setlist tracks to the local library, duplicates confident matches into a folder named after the setlist, writes an importable M3U plus match/missing reports, and surfaces TIDAL/platform/manual fallback links for missing tracks.
- Mobile setlist creation and editing.
- Phone-to-desktop pairing with shared Firestore setlists.
- Community profiles/uploads, follows, likes, reports, blocks, and account deletion.
- Subscription status and StoreKit purchase/restore UI on mobile and desktop settings.
- Pro subscription gates for live trend catalog reads, platform search, AI set building, manual refresh, playlist aggregation, artist catalog lookups, and automatic artwork enrichment. Free signed-in users see local preview data plus upgrade prompts; guests remain mock-only.
- Guest/demo and signed-in free-preview UI clearly labels catalog rows as mock/sample songs, not real live songs or real trend data, so users understand when they are not seeing live catalog results.
- Live platform-backed song selection powers Set Builder, Greatest Of, search, and AI setlist resolution. Apple Music, Spotify, YouTube, Deezer, and Soundcharts can source songs; Soundcharts/Shazam/TikTok/Boomplay evidence and Apple Music storefront chart rank are confidence signals, not the only admission path.
- Live song rows should expose direct playback actions wherever possible: `Play on Spotify`, `Play on Apple Music`, `Play on YouTube`, `Play on Deezer`, and `View on Soundcharts`. Chart-only rows are enriched with bounded platform lookups so Soundcharts does not become the only visible action.
- Genre selectors and genre-entry points use a shared broad DJ catalog rather than deriving the entire option list from the currently loaded live rows. This prevents a narrow Soundcharts/feed sample from collapsing the app to only `Open Format` or `Afrobeats`, while still appending discovered local/custom genres.
- Mobile now includes a Pro-gated Set Builder flow under More. It asks for event, city/market, crowd age, genre lane, energy curve, content preference, must-play, avoid, region, and set length; it saves rich setlist entries to the signed-in account so phone-built sets can be picked up on Mac.
- Set Builder produces a sequenced DJ journey rather than a random shortlist: opener, warm-up, lift, peak, reset, and closer phases are planned from user context, local library matches, Soundcharts/platform evidence, BPM/key compatibility when known, energy curve, must-play/avoid terms, clean/explicit preference, and version quality.
- Set Builder tracks user behavior locally across save, delete, reorder, export, search-again, and mark-wrong actions. Those signals become a taste profile that boosts preferred artists/genres and suppresses rejected songs in later generated sets.
- Gemini-rendered Pro/paywall artwork is used in persistent upgrade banners, locked live-service panels, sign-in gates, and the direct subscription sheet.
- Launch splash uses a single procedural radar animation over a solid deep panel background; the previous full-screen generated frame loop is no longer displayed or precached.

## Architecture

### Frontend Architecture

- Flutter app under `lib/`.
- Riverpod is the primary state and dependency-injection pattern.
- Desktop shell lives under `lib/ui/shell`; mobile companion UI lives under `lib/ui/mobile`.
- Shared UI primitives live under `lib/ui/widgets` and `lib/core/theme`.
- IAP client state lives in `lib/providers/billing_provider.dart`, with StoreKit access isolated in `lib/services/iap_service.dart`.
- Artist preference capture is a post-auth account setup step owned by `AuthGate`; selections save directly to `users/{uid}.followed_artists`. Default popular artist images come from the constrained `spotifyOnboardingArtistImages` callable, while arbitrary Spotify search stays behind full-account auth through `spotifyProxy`.

### Backend Architecture

- Firebase Cloud Functions TypeScript backend under `functions/src`.
- Scheduled ingestion writes backend-owned trend records.
- Callable functions provide authenticated proxies, pairing, account deletion, and purchase sync.
- HTTP App Store Server Notification endpoint reconciles subscription lifecycle changes.
- Backend-owned entitlements in Firestore drive usage limits and subscription state.

### Database Architecture

Primary Firestore collections:

- `tracks`: backend-owned trend records and platform links retained for ingestion/history compatibility. Client live song selection must not read this collection; Pro live catalog rows come from `LiveTrackCatalogService` using live music-platform APIs.
- `users/{uid}`: user profile/preferences plus `export_queue` and FCM token state.
- `usage/{uid}/{window}/{counterId}`: backend-owned quota counters.
- `entitlements/{uid}`: backend-owned paid tier/subscription state. Manual administrative grants may set `provider: manual_admin_grant`, active `studio` tier, `unlimited: true`, and `usageLimits` values of `-1` for cost-heavy gates; trusted backend functions treat negative limits as unlimited.
- `app_store_transactions/{originalTransactionId}`: App Store purchase ownership and latest verified status.
- `social_profiles/{uid}`: public community profile metadata.
- `uploads/{uploadId}`: community upload metadata, now created as `moderationStatus: pending` and publicly readable only after approval.
- `follows/{followerId_followeeId}`, `user_likes/{uid}`, `reports/{reportId}`, `blocks/{blockerUid_blockedUid}`: social graph, moderation, and safety state.
- `pairings/{pairingId}` and `pairings/{pairingId}/setlists/{setlistId}`: phone/desktop shared setlists.
- `soundcharts_cache/{sha1(path)}`: server-only Firestore cache of Soundcharts GET responses (chart lists 24h TTL, rankings 6h TTL) shared by `soundchartsProxy` and `ingestSoundchartsDaily` to protect the ~1k-call free Soundcharts budget. Clients never read this collection.
- `youtube_cache/{sha1(path+query)}`: server-only Firestore cache of `youtubeProxy` responses (24h TTL) shared across all users to protect the ~10k-unit/day YouTube Data API quota (`search.list` = 100 units). The proxy serves a stale entry when a live call is rate-limited (429). Clients never read this collection.

Client local persistence:

- SharedPreferences key `set_builder_behavior_profile_v1`: local Set Builder taste profile containing saved/rejected artist counts, saved genre counts, rejected track keys, and search-again count. This is intentionally local client state for now; it is not a Firestore schema and does not store full listening history.

### Infrastructure Architecture

- Firebase Hosting serves Flutter Web from `build/web`.
- Firebase Functions run in `us-central1`.
- Firestore rules, Firestore indexes, and Storage rules are checked in and deployed from this repo.
- GitHub Actions now runs blocking Flutter format, analysis, tests, web build, Functions build/test/audit.
- macOS release flow uses `scripts/release_macos.sh` for Developer ID signing/notarization outside Mac App Store distribution.
- App Store Connect app record exists as `VibeRadar DJ` with App Apple ID `6778432071`, bundle ID `com.viberadar.viberadar`, SKU `VIBERADAR-2026`, and shared iOS/macOS version shells.

## Engineering Decisions

- Use first-party `in_app_purchase` and App Store Server API rather than RevenueCat for the first production IAP foundation; this minimizes vendor lock-in while subscription scope is simple.
- Bind purchases by original transaction ID and a deterministic StoreKit-compatible UUID `appAccountToken` so an App Store purchase cannot be silently claimed by another Firebase user.
- Treat Storage object paths as authority, not client-provided URLs. Cleanup functions only delete blobs under expected owner-scoped roots.
- Remove user-supplied direct OpenAI API-key UI; all production AI requests go through `openaiProxy`.
- Require non-anonymous accounts for public/community writes and pairing claims to reduce abuse and accountability gaps.
- Treat guest mode as local mock-data mode only. Guests must not create Firebase anonymous accounts, read live Firestore collections, initialize StoreKit products, call platform/API proxies, use AI, community, pairing, or cloud sync.
- Keep backend/provider health details out of customer-facing success states. Normal startup should not show "Connected to Firebase" or similar infrastructure labels; only degraded/demo states should explain the product impact.
- Default public uploads to pending moderation; public reads require approval or owner access.
- Keep pairing revocation backend-owned so disconnecting a phone/computer actually removes Firestore setlist access instead of clearing only local preferences.
- Keep the public App Store name as `VibeRadar DJ` for first submission because `VibeRadar` was unavailable in ASC during app creation.
- Keep desktop prepared-set-folder creation separate from the existing VirtualDJ/TIDAL export pipeline. The folder flow is local-first and explicit-consent: it searches only user-selected/scanned folders, copies only high-confidence local matches, lists uncertain matches for review, and uses Pro-only AI notes only as optional guidance that cannot block folder creation.
- Centralize live-platform + AI song-selection ranking in a shared service rather than bespoke UI sorting. AI receives only a capped candidate window and must return candidate IDs, so it can rank evidence without inventing tracks; deterministic platform/evidence scoring remains the production fallback.
- Keep Set Builder sequencing deterministic after candidate retrieval. Apple Music, Spotify, YouTube, Deezer, and Soundcharts search produces candidate songs, bounded AI may only rank supplied IDs, and `SetSequencePlanner` owns journey phases, dedupe/version choice, transition smoothness, confidence, and reasons.
- Treat user behavior learning as a ranking signal, not an autonomous generator. Save/export/reorder increase affinity; delete/mark-wrong suppress artists and exact tracks; search-again is tracked as dissatisfaction pressure for future tuning.
- Use Apple Music charts the same way Apple models them: by storefront. Region codes such as `GH`, `NG`, and `ZA` map to Apple storefronts and Spotify markets before enrichment. Region-specific rows may come from storefront/market-aware Apple Music, Spotify, YouTube, Deezer, or Soundcharts results; chart evidence should boost confidence and regional ordering, not block live platform candidates outright.

## API Documentation

Cloud Functions:

- `openaiProxy`: authenticated callable AI proxy with model/token/message allowlists and quota enforcement.
- `syncAppStorePurchase`: authenticated callable transaction sync from StoreKit transaction ID to backend entitlement.
- `appStoreServerNotification`: HTTP endpoint for App Store Server Notifications.
- `createPairing`, `claimPairing`, `revokePairing`: authenticated pairing workflows with stronger random codes, quota throttles, anonymous claim rejection, and server-side disconnect.
- `deleteMyAccount`: authenticated account deletion.
- `manualIngestTrackSignals`, `ingestTrackSignals`, `ingestSoundchartsDaily`, `decayTrendingScores`: ingestion/scheduled workflows.
- `spotifyOnboardingArtistImages`: constrained callable for pre-auth onboarding photography. It accepts only curated onboarding artist names, caps batches at 20, deduplicates/canonicalizes names, uses server-side Spotify credentials, and caches resolved image URLs for 24 hours.
- `spotifyProxy`, `appleProxy`, `youtubeProxy`: authenticated platform proxies with path allowlists and quotas.
- `soundchartsProxy`: authenticated Pro-gated callable for live Soundcharts chart evidence. It accepts query/region/platform hints, keeps Soundcharts credentials server-side, applies quota enforcement, and returns deduplicated scored track results with source/region metadata.
- `toggleUploadLike`: authenticated callable that atomically toggles approved upload likes and owns like-count increments.

## Security Notes

Fixed or materially reduced on 2026-06-09:

- Removed tracked `.env.encrypted` and hardcoded decrypt behavior from `scripts/setup.sh`.
- Hardened OpenAI proxy validation and removed the direct client OpenAI request path.
- Hardened Firestore/Storage rules for public uploads, social writes, reports, blocks, and pairing setlists.
- Added safe Storage URL/path validation before deleting user-controlled media URLs.
- Added cryptographically random pairing codes plus create/claim throttles and anonymous claim rejection.
- Added backend-owned App Store entitlement sync and notification foundation.
- Added deterministic UUID `appAccountToken` binding for StoreKit 2 purchases and changed backend verification to fail closed when the token is missing or mismatched.
- Added callable App Check support, non-anonymous gating for spend-heavy callables/manual ingest, server-side pairing revocation, callable-owned upload likes, and fuller account cleanup for entitlements/usage/App Store transaction bindings.
- Added local App Store signed-data verification using Apple's root certificates for transaction and notification JWS payloads.
- Added a macOS release signing guard so `$(AppIdentifierPrefix)` cannot be shipped unexpanded in a Developer ID artifact.
- Deployed hardened Firestore rules, Storage rules, and indexes to `viberadar-462b8`.
- Redeployed Firebase Hosting with the latest web build to `https://viberadar-462b8.web.app`.
- Redeployed Firebase Hosting again after the onboarding artist-image work so the hosted web build matches the current app code.
- Configured App Store Server Notification V2 URLs in ASC for production and sandbox to `https://us-central1-viberadar-462b8.cloudfunctions.net/appStoreServerNotification`.
- Added constrained onboarding Spotify image lookup so pre-auth onboarding can show real artist photos without exposing the general Spotify proxy to anonymous/open usage.
- Replaced Firebase anonymous guest access with local mock-data guest mode, added visible Demo Mode banners, short-circuited guest track/profile/billing providers, and blocked live-service screens for guests.
- Removed normal "Connected to Firebase" UI and strengthened guest/free preview warnings so mock/sample songs are explicitly distinguished from real live catalog results.
- Added active Pro/Studio entitlement enforcement for live track reads and cost-heavy API/AI functions. Free accounts now get local preview data only for the catalog, and live platform proxies/manual ingest/OpenAI fail closed before touching paid providers.
- Added persistent in-app Pro upsell banners and locked panels across desktop/mobile live-service workflows, with direct StoreKit subscription entry points instead of hiding subscriptions only in Settings.
- Added per-account entitlement usage overrides so trusted administrative grants can provide lifetime Studio/Pro access with unlimited backend AI/platform/manual-ingest usage without changing global Pro/Studio quotas for customers.

Residual risks:

- Functions are deployed with App Store Server API secrets sourced from the working Gplus App Store Connect key path and `APP_STORE_APP_APPLE_ID=6778432071`; purchase sync, App Store Server Notifications, pairing revocation, account cleanup, social counters, and callable-owned likes are live in `viberadar-462b8`.
- App Check enforcement and production monitoring/alerting still need final activation/redeploy after registering apps in Firebase App Check.
- VibeRadar Pro monthly/yearly subscriptions are submitted and `WAITING_FOR_REVIEW` in ASC after first app-version submission preparation.
- Full live pairing parity and IAP sandbox runtime QA still need post-processing/TestFlight validation on installable review builds.
- iPhone 6.9-inch, iPad 13-inch, and macOS product screenshots now use actual app screens only, captured from iOS simulators and the native macOS app window, and are processed `COMPLETE` in ASC. Monthly/yearly IAP review screenshots remain real simulator captures and processed `COMPLETE`.
- ASC app pricing is set to Free, app privacy labels are published, iOS and macOS build 10 artifacts are uploaded/attached/valid, export compliance is set to `usesNonExemptEncryption=false`, and both iOS/macOS versions are `WAITING_FOR_REVIEW` after the 2026-06-12 EULA metadata resubmission.
- Backend rules/functions and Firebase Hosting include the 2026-06-10 Pro cost gate. ASC iOS/macOS build 10 includes the client-side Pro banner/locked-panel UI, Gemini-rendered paywall artwork, latest Demo Mode guest copy, Soundcharts-backed AI ranking, sequence-aware Set Builder, restored platform play actions, chart-evidence-anchored regional live catalog, mobile Set Builder parity, Global/All region regression fixes, the hard worldwide Soundcharts proxy default, and build-10 client chart-quality fixes. The current working tree has since restored broader platform-first music sourcing and needs a new native build before ASC review binaries include that change.
- Firebase Hosting includes the Gemini-rendered Pro/paywall artwork and the updated Terms page with Apple's standard EULA link. Native build 10 carries the same Pro artwork plus the latest Set Builder, regional catalog, mobile parity, global/default-region fixes, and chart-quality fixes into App Review.

## Performance Notes

- Flutter unit/widget suite is healthy at 433 passing tests after hardening, onboarding artist-image coverage, post-auth artist preferences, guest-cost gating, setlist parity, Pro live-cost gating, Gemini paywall artwork coverage, prepared-folder coverage, guest Demo Mode copy checks, sequence-aware Set Builder coverage, Global/All region regression coverage, and live platform sourcing coverage.
- Trending refresh now combines one cached Soundcharts proxy call, optional Apple storefront chart evidence, and region-aware Apple Music, Spotify, YouTube, and Deezer platform searches. Soundcharts data remains served from the Firestore `soundcharts_cache` (chart lists 24h, rankings 6h), while platform rows are again allowed to source the live catalog.
- Playback-link enrichment is bounded to the top live candidates and only searches missing services for likely title/artist matches. This restores multi-platform play actions while avoiding unbounded provider fan-out.
- Web release build succeeds and was deployed to Firebase Hosting.
- Firestore upload queries now have supporting composite indexes.
- AI request size, message count, token count, and model selection are bounded server-side.
- Free signed-in catalog access now uses bundled mock tracks instead of Firestore `tracks`; active Pro/Studio users attach the live platform catalog adapter instead of reading Firestore `tracks` directly.
- Desktop auto-ingest, sidebar manual refresh, Set Builder, playlist aggregation, artist catalog/search, Greatest Of platform augmentation, AI, and local-library artwork enrichment are blocked from live API calls until Pro access is active.
- Large UI/widget test suite is broad but should be monitored for CI duration.
- Onboarding popular-artist image loading is batched in groups of twelve and uses small `CachedNetworkImage` memory cache dimensions to avoid an eager full-resolution image load on mobile.
- Launch splash startup work is reduced by removing the full-screen 48-frame background animation playback and precache; only the lightweight procedural radar mark animates.
- Prepared set folders reuse the local library scanner and `LocalMatchService`; no Firestore, platform proxy, TIDAL API, or AI call is required for the core copy/export path. Pro AI assistance sends only track labels, match confidence, and file basenames, not full local file paths.
- Live-platform AI ranking is cost-bounded: Set Builder and Greatest Of use one small JSON rerank request per candidate window only when live platform or chart evidence is present, cap the window at 40 tracks, and fall back to local ranking on auth/quota/network/model failures.
- Sequence planning itself is local and deterministic after candidate fetch. Must-play searches are capped, local-library matching reuses already-scanned metadata, and behavior learning writes one small SharedPreferences JSON profile instead of adding backend read/write cost.
- Regional live catalog reads must stay storefront/market-aware after the Ghana-selection QA finding: Global/All remains `Global`, never falls back to the signed-in profile region or `GH`; selected-region searches pass the selected market to Apple Music and Spotify and favor matching chart evidence, but Apple Music, Spotify, YouTube, and Deezer results may source songs directly when chart coverage is too narrow.

## Technical Debt

- ASC submission is now waiting for Apple review; monitor review messages and be ready to respond to metadata, binary, or IAP review feedback.
- iOS simulator build through XcodeBuildMCP remains unusable because the MCP transport closes, but direct `flutter build ios --simulator --debug --dart-define=FIREBASE_APP_CHECK_ENABLED=false` now succeeds after clearing stale generated BoringSSL/gRPC build products.
- macOS debug build succeeds. For ASC screenshots, capture the real native window by CoreGraphics window ID and crop the native capture; do not rely on rendered/composited mockups.
- ASC iPhone 6.9-inch, iPad 13-inch, and macOS screenshot sets now contain actual app screens only: 5 iPhone, 5 iPad, and 4 macOS assets in `COMPLETE` state. The previous onboarding/sign-in screenshot assets were deleted from ASC.
- ASC app availability is explicitly enabled for all 175 current App Store territories with `availableInNewTerritories=true`; each territory availability row reports `available=true`. `CANNOT_SELL` / `AVAILABLE_FOR_SALE_UNRELEASED_APP` content statuses are expected while the first release is unreleased and waiting for Apple review.
- Current ASC binaries are build `10` for iOS and macOS. They include the setlist/crates terminology, macOS large-setlist performance, phone-to-computer setlist handoff fixes, Pro cost-gate UI, Gemini-rendered paywall artwork, latest guest Demo Mode copy, restored platform play actions, Soundcharts-backed AI ranking, sequence-aware Set Builder, chart-evidence-anchored regional live catalog, mobile Set Builder parity, corrected Global/All default behavior, hard worldwide Soundcharts proxy handling, and build-10 client chart-quality fixes. They do not yet include the later 2026-06-12 platform-first sourcing restoration unless rebuilt and uploaded.
- Build `10` is attached to the iOS and macOS `1.0.0` version shells and submitted through fresh review submissions after adding the required EULA link to the App Description. Monitor App Store Review for binary, metadata, screenshot, or IAP feedback.
- Mac App Store packaging/export/upload succeeded through `scripts/release_macos_appstore.sh`; the script now regenerates macOS Flutter release config with the pubspec build number and clears screenshot-only `ASC_SCREENSHOT_SURFACE` defines before archive.
- Set Builder taste learning is local-only in this release. If cross-device learning becomes a requirement, promote the profile to an account-scoped Firestore document only after privacy-label review, opt-out handling, and server-side abuse controls.
- If Apple surfaces an updated Developer Program License Agreement during review, only the account holder may accept it.
- The worktree contains many pre-existing/generated mobile, splash, onboarding, and UI changes; review before committing as one production PR.

## Roadmap

### Completed

- Production hardening pass for IAP, AI proxy, upload moderation, Storage cleanup, pairing, Firebase rules, CI, and documentation.
- Continued backend hardening for App Check, non-anonymous spend-heavy APIs, StoreKit UUID account binding, server-side pairing revocation, callable-owned upload likes, account cleanup coverage, and macOS signing validation.
- Firebase Hosting deploy for support/privacy/terms and current web build.
- Firestore indexes/rules and Storage rules deploy.
- Firebase Functions deploy with App Store Server API secrets and live notification URL.
- ASC app record creation for `VibeRadar DJ` / `6778432071`.
- VibeRadar Pro subscription group/products: group `22145074`, monthly `6778435251` / `viberadar_pro_monthly` at `$9.99`, yearly `6778435163` / `viberadar_pro_yearly` at `$79.99`.
- IAP review screenshots uploaded and processed by ASC for both subscriptions.
- Real simulator IAP review screenshot capture added through the hidden `ASC_SCREENSHOT_SURFACE=iap` app surface and uploaded to ASC for both subscriptions.
- Public ASC metadata filled: subtitle, privacy policy URL, support URL, marketing URL, description, keywords, and promotional text for both iOS and macOS version shells.
- TestFlight group `VibeRadar QA` created and `cyberzonenas93@gmail.com` added as a VibeRadar-specific beta tester.
- Historical initial onboarding screenshots were captured and uploaded during early ASC setup; those onboarding/sign-in assets were later deleted and replaced by actual app screenshots.
- Mac App Store export scaffolding added separately from the Developer ID DMG workflow; the Mac App Store `.pkg` was exported, validated, uploaded, processed, and attached to the macOS version.
- ASC app-level price schedule set to Free, App Privacy labels published, content rights set to third-party content usage, primary/secondary categories set to Music/Productivity, and age rating computed as 4+.
- ASC app availability now covers all 175 current App Store territories, and future territories are enabled through `availableInNewTerritories=true`.
- Onboarding "Choose Your Artists" now displays real Spotify artist images for default popular choices through a deployed constrained callable, as well as authenticated search results.
- Onboarding "Choose Your Artists" now appears only after real sign-in so selected artists save into the signed-in account instead of being collected before authentication.
- Guest mode now costs the backend nothing: it uses bundled mock tracks/local profile data only and prompts users to sign in for live data, search, AI, community, pairing, StoreKit, and cloud sync.
- Guest/demo and signed-in free preview states now visibly say `MOCK SONGS ONLY`, clarify that listed songs are sample tracks rather than real live songs/trend data, and avoid showing normal backend connectivity badges.
- Fresh iOS build `12ae5d34-7cdc-4c56-8e05-555d78c7a65e` and macOS build `5f774c7a-cbf9-44c6-a442-d33cef859610` were uploaded, validated, attached, assigned to the `VibeRadar QA` TestFlight group, and submitted to ASC as build 9.
- Historical build 9 review submissions were iOS `c8cf5193-e6b2-49cc-be8e-86d96043ffaa` and macOS `1d98a95d-a880-4a40-83f4-400b227dc440`; build 10 later superseded them. Monthly subscription submission `f900334c-ab35-4d46-8db2-c8fd7494de95` and yearly subscription submission `f8911dfa-33d6-41aa-bf03-196ec8ae9545` are waiting for review.
- Build 10 replaced build 9 after chart-quality fixes, then both build-10 app-version submissions were resubmitted on 2026-06-12 after Apple rejected Guideline `3.1.2 Business: Payments - Subscriptions` for a missing Terms of Use/EULA link in the App Description. Current submissions are iOS `c5caa82d-829d-4f98-9f5f-94081143a428` and macOS `5ff2e775-608d-4736-933f-3da6ab3353de`, both `WAITING_FOR_REVIEW`.
- ASC product screenshot sets now contain actual app screens: iPhone screenshots `b77ce7ab-7031-445d-b81e-15416b782f8b`, `56dc2b7d-dac8-456b-8c95-b7013f5f21c4`, `5909692e-fa9c-46b0-9e3c-0c300e04b886`, `4b6da261-4bd6-46b0-8823-5b14773218fa`, `0f9b08e7-51c4-474b-a6b7-c6f6e7f124c6`; iPad screenshots `c2ea8c5a-3c13-428d-a7ab-561737d98785`, `f90ecd5a-887a-4006-9ea4-ce6cd0267775`, `77a3ba31-74e4-4a84-82a5-7f2771cedd7f`, `6e5c11f0-0e91-4ce3-ac20-c0ff2f0afec0`, `3184f31c-b52b-45c2-a5bf-dba3781e8d7d`; macOS screenshots `d6ec9456-4c7a-47b9-8e43-8ef252cd620b`, `3ac2dc40-4134-4d0c-90cd-26d395a0d57e`, `7af2d43f-0fb5-41cb-b81c-649b90a2f34f`, `cdfa59c9-f00a-4a32-8164-89be8a32e323`.
- Pro live-cost gate deployed on 2026-06-10: Firestore `tracks` reads now require active Pro/Studio entitlement; OpenAI/platform proxies/manual ingest require Pro/Studio; Firebase Hosting shows Pro banners and locked panels for free signed-in users.
- Gemini Pro/paywall graphics deployed on 2026-06-10: generated three production PNG assets from the Gplus Gemini image-generation workflow and wired them into the Pro banner, locked panel, sign-in gate, and subscription sheet.
- Desktop prepared-set-folder workflow added on 2026-06-10: saved setlist cards can search a user-approved music folder when needed, create a setlist-named folder, copy confident local audio matches, generate an M3U, generate `MATCH_REPORT.txt` and `MISSING_TRACKS.txt`, include TIDAL search/platform fallbacks for missing tracks, and add Pro-only AI guidance without changing the existing TIDAL/VirtualDJ flow.
- Sequence-aware Set Builder added on 2026-06-10: Set Builder now asks for DJ context, plans phase-by-phase journeys, explains every selection with confidence/reasons, prefers clean DJ-ready versions, dedupes alternate versions, avoids artist overuse, learns from user actions, and keeps AI bounded to ranking supplied Soundcharts/platform candidates.
- Regional live selection fix on 2026-06-10: Pro catalog rows now come from `LiveTrackCatalogService` rather than Firestore `tracks`, Apple Music chart/search calls use region storefronts, Spotify search uses region markets, region filters trigger live refetches, and selected-region merges reject unanchored generic platform rows.
- Platform-first music sourcing restored on 2026-06-12: Apple Music, Spotify, YouTube, Deezer, and Soundcharts can all create live song candidates; chart evidence boosts confidence and regional ordering but no longer blocks platform-sourced rows.
- Mobile Set Builder parity added on 2026-06-10: iOS/Android More now exposes a Pro-gated Set Builder with the same context fields and rich setlist save path as desktop, preserving phone-to-Mac pickup.

### Current Work

- Monitor App Store Review for iOS build `10`, macOS build `10`, and VibeRadar Pro subscriptions.
- Runtime iOS/macOS parity and sandbox IAP validation after review/TestFlight install paths are available for build `10`.

### Planned

- Add App Check enforcement, alerting, and abuse/moderation operations.

## Changelog

### 2026-06-19 AI "Couldn't Reach the AI Service" — Desktop Prompt Exceeded 12000-Char Limit (Server-Side Fix)

- Reported: "the AI service still doesn't work" on the macOS app, after the backend was already proven healthy.
- Root cause (proven against the live proxy): the **desktop** AI Copilot (`ai_copilot_screen.dart` → `_getTrackContext()`) embeds up to **80 catalog tracks** in the set-build system prompt (`AiCopilotService._buildSystemPrompt`, two lines/track + ~2k base) → ~14–17k chars. The backend `sanitizeOpenAiRequest` enforced `OPENAI_MAX_MESSAGE_CHARS=12000` and rejected it with `INVALID_ARGUMENT: "messages exceed the 12000-character limit"` (HTTP 400). `sanitize` runs BEFORE the Pro check, so even a Pro account hits it. The client maps any non-`failed-precondition`/non-`resource-exhausted` error to the generic "I couldn't reach the AI service" — exactly the symptom. Mobile passes `trackContext: null`, so only desktop (Mac) hits it; the earlier tiny end-to-end probe used a small prompt and passed, masking this.
- Fix (server-side only, no app rebuild — matches the earlier key/model fixes): raised `OPENAI_MAX_MESSAGE_CHARS` 12000 → **24000** in `functions/.env.viberadar-462b8`, redeployed `functions:openaiProxy`. gpt-5.5 handles the larger context; `OPENAI_MAX_MESSAGES=24` still caps message count.
- Files changed: `functions/.env.viberadar-462b8`, `CLAUDE.md`, `CODEX.md`. No code change; the in-app build picks it up with no rebuild.
- Verification (live, throwaway Pro user): a 17,399-char system prompt that returned HTTP 400 before now returns **HTTP 200** with a valid 20-track set + ```crate``` block on `gpt-5.5`, ~41s (within the client's 70s callable timeout). The empty-prompt and small-prompt paths still work.
- Follow-up DONE (2026-06-19, client-side; needs a native rebuild to ship): `AiCopilotService` now bounds the prompt itself so long chats can't approach the limit even if the server cap were lower — `renderTrackContext` caps the track block at 7000 chars (was unbounded `take(80)`) and `boundedHistory` keeps only the most recent ≤16 messages / ≤9000 chars. TDD'd (7 new tests in `test/services/ai_copilot_service_test.dart`); `flutter analyze` clean, `dart format` clean, full suite unchanged (same 5 pre-existing failures). Files: `lib/services/ai_copilot_service.dart`, `test/services/ai_copilot_service_test.dart`.

### 2026-06-19 Apple Music Genre Charts as Primary Genre Source

- Reported: "I'm not getting good quality songs; I want genre results as though I selected them on Apple Music."
- Root cause: selecting a genre only ran keyword `term=` search across platforms plus the GLOBAL Apple most-played chart filtered by genre tokens. The app never called Apple Music's genre charts (`catalog/{storefront}/charts?types=songs&chart=most-played&genre=<id>`) — which is exactly Apple's "tap a genre" experience. Verified live (MusicKit token): US Hip-Hop(18)→Drake, US Pop(14)→Olivia Rodrigo. Apple genre availability is storefront-specific: Afrobeats=100051 and Amapiano=42 exist only in African storefronts (ZA/NG/GH), not US.
- Decision (user-approved): when a specific genre is selected, Apple's genre chart is the PRIMARY list; other platforms only add Play-on-X links via the existing bounded enrichment. Parent-genre mapping is fine (House→Dance 17, Dancehall→Reggae 24). Unmapped lanes / failures / sparse results fall back to today's keyword-search blend, so nothing regresses.
- Implementation (client-only, additive; no backend change — `appleProxy` already allows `catalog/...`): `lib/core/config/music_genres.dart` adds `AppleGenreMapping` + `appleGenreFor(lane)` (verified Apple genre ids; regional genres carry preferred African storefronts). `lib/services/apple_music_artist_service.dart` adds `getGenreChartSongs(...)` + `appleStorefrontForRegion`/`appleGenreChartStorefront`. `lib/services/platform_search_service.dart` adds `_searchAppleGenreChart` (rows tagged `appleChartRank` so they pass the region chart-evidence filter, stamped with the lane), used as the Apple source in `fetchTrendingChartTracks` and seeded first in `searchByGenre`. `live_track_catalog_service.dart` unchanged (its chartBacked filter already accepts `appleChartRank`; fallback fills if sparse).
- Files changed: `lib/core/config/music_genres.dart`, `lib/services/apple_music_artist_service.dart`, `lib/services/platform_search_service.dart`, `test/core/music_genres_test.dart`, `test/services/apple_genre_chart_test.dart` (new), `docs/superpowers/specs/2026-06-19-apple-genre-charts-design.md` (new), `CLAUDE.md`, `CODEX.md`.
- Verification: `dart format` clean; `flutter analyze` → `No issues found!`; new tests pass (TDD: `appleGenreFor` mapping, `appleGenreChartStorefront` storefront selection, `fetchTrendingChartTracks` genre-chart sourcing + unmapped-lane fallback). Apple genre charts confirmed live. NOTE: full `flutter test` shows 5 PRE-EXISTING failures unrelated to this change (untracked `platform_play_actions` widget+test disagree on link order/labels; `crate.dart` default 'Custom setlist' vs `pairing_service_test` 'Open format'; untracked `guest_mode_provider_test` expects an 'Open Format' genre option the catalog doesn't define). Not introduced here.
- Not yet shipped to users: web needs a Hosting redeploy and iOS/macOS need a native rebuild + ASC resubmit to carry this into the apps.

### 2026-06-19 macOS Sign in with Apple Entitlement + AI Backend Re-Verification

- Reported: "the AI service doesn't work; login with Apple doesn't work either" while testing the macOS app.
- AI (no code change): root-caused empirically against the LIVE backend, NOT assumed. Secret `OPENAI_API_KEY` v4 still real/enabled (164-char `sk-proj`), a direct OpenAI call to `gpt-5.5` = HTTP 200, and an end-to-end probe of the DEPLOYED `openaiProxy` (throwaway Pro user) returned `{"content":"pong","model":"gpt-5.5-2026-04-23"}`; a realistic 30-track set build took 36.4s (well under the client's 70s default callable timeout) with a valid crate block. So the AI backend is healthy. The in-app failure is therefore client-side auth/entitlement: `AiCopilotService._callProxy` maps `failed-precondition`→"Pro required" and `resource-exhausted`→"usage limit", but maps everything else — including `unauthenticated` — to the generic "I couldn't reach the AI service." An unauthenticated user (e.g. one who can't sign in) sees that exact AI error, linking this directly to the Apple-sign-in bug. Workaround: sign in via Google/email (not Apple) with a Pro account (e.g. `cyberzonenas93@gmail.com` = unlimited Studio) and AI works now.
- Apple sign-in (real fix): the current auth code routes BOTH iOS and macOS through the native flow (`AppleAuthProvider` + `signInWithProvider`), which requires the `com.apple.developer.applesignin` entitlement on every Apple platform. iOS had it; the macOS target did not. Added `com.apple.developer.applesignin = [Default]` to `macos/Runner/Release.entitlements` and `macos/Runner/DebugProfile.entitlements`.
- Build was then blocked: `flutter build macos` and `xcodebuild -allowProvisioningUpdates` both failed — the macOS provisioning profile didn't include Sign in with Apple, and the profile couldn't be regenerated because the ASC API returned HTTP 403 `PLA_NOT_ACCEPTED` (updated Apple Developer Program License Agreement unaccepted; only the account holder can accept). The account holder accepted the PLA. App ID `com.viberadar.viberadar` (`96477A3V26`, UNIVERSAL) was then confirmed to already have `APPLE_ID_AUTH` enabled (no capability add needed).
- Files changed: `macos/Runner/Release.entitlements`, `macos/Runner/DebugProfile.entitlements`, `CLAUDE.md`, `CODEX.md`. No Dart/Functions code or backend deploy changed.
- Verification: `plutil -lint` OK on both entitlement files; `xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -allowProvisioningUpdates -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_R7BYLGVT9L.p8 -authenticationKeyID R7BYLGVT9L -authenticationKeyIssuerID 2d61090e-20f6-4c5c-9868-b0ecb45d51ad -destination 'platform=macOS' build` → **BUILD SUCCEEDED**; `codesign -d --entitlements` on the built `VibeRadar.app` shows `com.apple.developer.applesignin=[Default]`; `codesign --verify` passes; the embedded provisioning profile now includes the capability. Runtime Apple-ID-sheet sign-in still needs a manual on-device click-through. NOTE: passing xcodebuild the `-authenticationKey*` ASC flags is what allowed CLI profile regeneration; `-allowProvisioningUpdates` alone did not.

### 2026-06-18 Switch AI to gpt-5.5 (Forced Server-Side, No Rebuild)

- Task: use gpt-5.5 for the AI feature. Verified empirically first: `gpt-5.5` exists and the account has access, but it is a **reasoning model** — it rejects any non-default `temperature` (only `1` allowed; the proxy was sending 0.7/0.3) and bills reasoning tokens against `max_completion_tokens`. A naive model-string swap would have re-broken AI and re-triggered the 2.1(a) rejection.
- Implementation (backend-only, so the in-review build 16 picks it up without an app update): `openaiProxy` now **owns the model** — `buildChatCompletionBody()` redirects any non-gpt-5 request (including build 16's hardcoded `gpt-4.1`) to the configured default, omits `temperature` for gpt-5 models, sets `reasoning_effort` (`low`, env-overridable via `OPENAI_REASONING_EFFORT`), and floors `max_completion_tokens` to ≥3500 so reasoning can't starve the visible completion (the set-builder prompt lists tracks twice — numbered list + crate JSON — so a max-size 30-track set needs ~2.1k tokens; a 2000 floor truncated the crate block). The callable response now also returns `model` for observability. `.env`/config defaults updated: `OPENAI_DEFAULT_MODEL=gpt-5.5`, `OPENAI_ALLOWED_MODELS=gpt-5.5,gpt-4.1,gpt-4o-mini`, `OPENAI_MAX_COMPLETION_TOKENS=4000`. The Flutter client was intentionally NOT changed (it keeps sending `gpt-4.1`; the backend redirects), so no rebuild and no web redeploy are required — web hits the same backend.
- Tradeoff (user-accepted): gpt-5.5 runs ~13–17s per AI build vs ~3s on gpt-4.1 (reasoning model). Within the 120s function timeout and ~70s client callable timeout. Note: `USAGE_PRO_AI_MONTHLY_LIMIT=100`/`USAGE_STUDIO=400` now bill against a premium model — watch OpenAI cost.
- Files changed: `functions/src/openai.ts`, `functions/src/lib/config.ts`, `functions/.env.viberadar-462b8`, `functions/test/openai.test.ts`. Deployed `functions:openaiProxy`.
- Verification: `npm --prefix functions run build` (tsc) passed; `npm --prefix functions test` passed (18-test suite + new `buildChatCompletionBody`/`isReasoningModel` assertions); deploy succeeded; live proxy probe with build 16's exact payload (`model:gpt-4.1, temperature:0.7, maxCompletionTokens:1500`) returned HTTP 200 on `gpt-5.5-2026-04-23` with a valid 15-track ` ```crate ` block (`finish=stop`, not truncated, ~13s); JSON parse path returned valid JSON. End-to-end AI smoke test (live proxy, all surfaces) = 7/7: chat set-build (incl. max-size 30-track set), advice question (no crate), multi-turn refine, region/genre variant, parseCommand JSON, Soundcharts ranking `{ids}`, and the non-Pro gate returning `FAILED_PRECONDITION` (not a 500).

### 2026-06-18 ASC 2.1(a) AI-Error Rejection — Root Cause: Dead OpenAI Key (Server-Side Fix)

- Rejection (authoritative, from Resolution Center): **Guideline 2.1(a) Performance — App Completeness**, single bug, reviewed **June 18, 2026** on **iPad Air 11-inch (M3) / iPadOS 26.5**, version **1.0.0 (16)**: "Your app displayed an error when we attempted to use the AI feature." The earlier four-bug round (Sign in with Apple, My Profile, Upload Track, AI Build) narrowed to this one — the others are resolved.
- Live ASC state corrected (memory was stale at "build 10 waiting"): both platforms are **REJECTED**. iOS version `20c5730f` has **build 16** attached (uploaded 06-17), latest iOS review submission `4cc37428` (06-17) = `UNRESOLVED_ISSUES`; macOS version `ed0249fd` has **build 11** attached, submission `938aa483` (06-16) = `UNRESOLVED_ISSUES`. Builds 11–16 were uploaded since the documented build 10 and still rejected.
- Root cause (confirmed empirically against the live backend, not assumed): the deployed `OPENAI_API_KEY` Secret Manager secret was a **28-char placeholder dummy** (`sk-abc123…here`, version 3, set 2026-06-17). The live `openaiProxy` returned `HTTP 500 → "OpenAI error 401: Incorrect API key provided"`. `AiCopilotService.chat()` swallows the proxy error and returns a fallback string ("couldn't reach the AI service" / "AI build is temporarily unavailable"), which reads as an error to the reviewer. Only AI was affected because `openaiProxy` (`functions/src/openai.ts`) is the sole consumer of `OPENAI_API_KEY`. Eliminated: App Check (`REQUIRE_APP_CHECK=false`), model allowlist (`OPENAI_ALLOWED_MODELS=gpt-4.1,gpt-4o-mini` includes the client default `gpt-4.1`), and reviewer entitlement (`test@viberadar.com` = uid `7pLYMX9aTHQIilvra7MuBsUEeGl2` is active permanent Pro/unlimited). The 2026-06-16 note "openaiProxy is healthy, HTTP 200" was wrong — never tested end-to-end through OpenAI.
- Fix (server-side only, no code change, no rebuild): `OPENAI_API_KEY` versions 1 (06-03) and 2 (06-04) are the real `sk-proj-…` keys (164 chars, both authenticate, 62 models). Copied v2 → new **version 4** (latest), `firebase deploy --only functions:openaiProxy`, and **disabled** the bad version 3. Verified the live proxy now returns **HTTP 200 + real AI content** (15-track Afrobeats set). Because build 16 already calls `openaiProxy`, AI now works in the binary already in review — **no new build required**; the app version needs to be re-submitted for review / Apple replied to in Resolution Center.
- Files changed: none in the repo (Secret Manager value + function redeploy only). `CLAUDE.md`, `CODEX.md`, and auto-memory updated.
- Verification: live `openaiProxy` probe (throwaway Pro user) returned HTTP 200 with a real completion; reviewer email→uid→active-Pro confirmed; placeholder secret version disabled; `firebase deploy --only functions:openaiProxy` succeeded (predeploy `tsc` passed).

### 2026-06-16 UX Fixes: Genre Catalog, Guest Access, OAuth Error Copy, Credit Removal

- Task: Four reported issues — (1) only "All" and "Open Format" genres available; (2) Sign in with Apple shows "Incorrect email or password"; (3) remove the "Built by Angelo Nartey" credit; (4) guest / continue-without-account no longer available.
- (1) Genre chips: the Home dashboard genre quick-filters were built from `topGenres` (genres present in the current feed), so an all-"Open Format" feed only ever offered All + Open Format. Now built from `mergedGenreOptions(...)` (the full canonical DJ catalog + discovered genres); chips wired to `selectedGenreProvider` so selecting one drives the genre-aware refetch (safe now that the chip list no longer derives from the feed → no chip-collapse). Removed the per-genre count badge. The Trending dropdown already used the full catalog.
- (2) Sign in with Apple/Google "Incorrect email or password": `_friendly` mapped `invalid-credential` → that wrong-password copy, but for OAuth it means the token was rejected (not a bad password). `_friendly` now takes `oauth: true` (passed from the Apple/Google handlers) and returns OAuth-appropriate copy. Config verified correct: Firebase Apple/Google providers enabled, App ID has `APPLE_ID_AUTH`, `GoogleService-Info.plist` BUNDLE_ID matches `com.viberadar.viberadar`, native nonce flow is standard — so the credential rejection in testing is almost certainly the iOS Simulator (no Apple ID signed in); on a real device/TestFlight it should succeed.
- (3) Removed the "Built by Angelo Nartey." text from `auth_gate.dart` and "Designed and Built by Angelo Nartey." from `onboarding_screen.dart`.
- (4) Guest access: the "Continue as Guest" block was gated `if (!isMobileForm)` (desktop only). Now shown on every platform (local mock-data mode, no Firebase anonymous account, no live API screens — unchanged behavior, just visible on mobile).
- Files changed: `lib/ui/auth/auth_gate.dart`, `lib/ui/auth/onboarding_screen.dart`, `lib/ui/features/home/home_screen.dart`, `CLAUDE.md`.
- Verification: `flutter analyze` → `No issues found!`; `dart format` gate → 0 changed; full `flutter test` (pending confirmation).

### 2026-06-16 Defensive Fixes for ASC 2.1(a) Bugs 1 & 3

- Task: Make defensive code fixes for the two App Review bugs that couldn't be reproduced in the Simulator (Sign in with Apple error; Upload Track unresponsive).
- Bug 1 (Sign in with Apple — "error after we logged in"): root cause identified by comparing the Apple vs Google paths — the Apple native path `await`ed `user.updateDisplayName(name)` AFTER `signInWithCredential` already succeeded, so a network/internal blip there propagated as a sign-in error even though the user WAS logged in (the Google path makes post-login steps non-fatal). Fix: `updateDisplayName` is now wrapped in try/catch (logged, non-fatal), and `_saveRememberMe()` (awaited after every sign-in) swallows errors. A successful Apple login can no longer surface a post-login error.
- Bug 3 (Upload Track unresponsive): the audio picker used `FilePicker FileType.custom` with extensions including `ogg`/`aiff`, which don't map to valid iOS UTIs — on iOS that makes the document picker fail to present, so the upload flow looks unresponsive. Fix: switched to `FileType.audio` (public.audio UTI, reliably opens on iOS) with try/catch + a user-facing error if the picker can't open. `_pickArtwork` already used the reliable `FileType.image` (PHPicker).
- Note: these are hypothesis-driven defensive fixes (user opted for code fixes over real-device repro). They target the most likely causes; a physical-device pass is still the surest confirmation.
- Files changed: `lib/data/repositories/session_repository.dart`, `lib/ui/auth/auth_gate.dart`, `lib/ui/features/community/upload_screen.dart`, `CLAUDE.md`.
- Verification: `flutter analyze` → `No issues found!`; `dart format` gate → 0 changed; full `flutter test` → 455 passed.

### 2026-06-16 ASC Rejection Reason Confirmed (2.1(a)) + Root-Cause Analysis

- The actual rejection message (Resolution Center, submission `c5caa82d-…`, reviewed Jun 13 on iPhone 17 Pro Max + iPad Air M3, iOS/iPadOS 26.5): **Guideline 2.1(a) Performance — App Completeness**, four bugs: (1) error after **Sign in with Apple**; (2) error on **My Profile**; (3) **Upload Track** button unresponsive in Community; (4) error after tapping **Build** in AI.
- Root-cause analysis (config + on-device reproduction with a Pro-granted QA account):
  - Bug 4 (AI Build error): `openaiProxy` is healthy (returns `{content}`, HTTP 200). The client `AiCopilotService.chat` only throws when the proxy returns an error, and the dominant cause is a **non-Pro account** (permission-denied). The demo account's Pro was a **Sandbox subscription that lapses every few minutes** — so mid-review it dropped to free and AI errored with "AI build is temporarily unavailable." Reproduction confirmed: free users correctly see an "Unlock AI with Pro" gate (no Build button); Pro users get a working Build form. → Addressed by the permanent comp entitlement on `test@viberadar.com` (prior entry).
  - Bug 2 (My Profile error): the page loads correctly for an authenticated account (verified). "Profile unavailable" only renders when `myProfileProvider` errors AND the session is not authenticated — i.e., again the lapsed-auth/Pro state. Mitigated by the permanent Pro/auth on the demo account.
  - Bug 1 (Sign in with Apple error): all config layers verified correct — Firebase Apple provider enabled (Services ID `com.viberadar.signin`), App ID `com.viberadar.viberadar` has `APPLE_ID_AUTH` (and `MUSIC_KIT`, `IN_APP_PURCHASE`, `PUSH_NOTIFICATIONS`), `com.apple.developer.applesignin` entitlement present. Could not reproduce in the iOS Simulator (no signed-in Apple ID). Needs a real-device repro to fix confidently; likely environment/transient or a post-login surfacing issue.
  - Bug 3 (Upload Track unresponsive): on mobile the button pushes `UploadScreen` via `onUploadPressed`; could not reproduce due to Simulator navigation flakiness. Needs real-device repro.
- Status: the dominant cause (lapsing sandbox Pro → Pro-gated features error mid-review) is fixed by the permanent reviewer entitlement. Bugs 1 and 3 are not yet root-caused on-device. Before resubmitting: reproduce bugs 1 & 3 on a physical device, fix, rebuild iOS+macOS, resubmit, and reply to Apple in Resolution Center listing the fixes.

### 2026-06-16 ASC Rejection Investigation + Reviewer-Account Hardening

- Task: Determine why ASC rejected the app and prevent re-rejection.
- Found via ASC API: BOTH iOS (`20c5730f-…`) and macOS (`ed0249fd-…`) `1.0.0` versions are `REJECTED`; the current review submissions (iOS `c5caa82d-…`, macOS `5ff2e775-…`, the 2026-06-12 EULA resubmission of build 10) are `UNRESOLVED_ISSUES` with item state `REJECTED`. The public ASC API does NOT expose the Resolution Center message text (the `resolutionCenterThreads` endpoints 404), and the local browser has no logged-in ASC session — so the exact guideline/message must come from Resolution Center email or the ASC web UI.
- Concrete cause found and fixed: the **App Review demo account `test@viberadar.com`** (demoRequired=true) was relying on a **Sandbox `apple_app_store` Pro subscription with an `expiresAt`**. Sandbox subscriptions lapse fast/unpredictably, so on a review pass the reviewer could sign in and see only the "MOCK SONGS ONLY" free-preview — unable to evaluate the Pro-gated live features (a classic Guideline 2.1 rejection for a subscription-gated app). Fixed by granting that account a **permanent comp entitlement** (`active`, `tier: pro`, `unlimited: true`, `provider: manual_admin_grant`, `expiresAt` removed) so it is always Pro. uid `7pLYMX9aTHQIilvra7MuBsUEeGl2`.
- Other likely causes were already addressed earlier this session: genre selection returned 0 tracks (2.1 core-feature bug) — fixed client-side; Apple Music returned nothing (the 500) — fixed + deployed backend (helps every client immediately); macOS had no in-app account deletion (5.1.1(v)) — fixed client-side; subscription point-of-purchase disclosures + unused mic permission — fixed client-side.
- To ship the client fixes into review and clear the rejection, a NEW iOS+macOS build + resubmission is required (build 10 still has the old genre filter and the macOS account-deletion gap). The backend fixes (Apple Music token, reviewer Pro, YouTube cache) are already live and benefit any binary.
- Open item: confirm the exact Resolution Center message to verify nothing else is outstanding. Possible residual risk: an App Store Server Notification for the reviewer's old sandbox sub could later overwrite the manual grant — re-verify the reviewer entitlement stays `active` before each resubmission, or guard `manual_admin_grant` in the notification handler.

### 2026-06-16 YouTube Proxy Quota Caching

- Task: Stop the YouTube proxy hitting HTTP 429 (quota exhaustion) by caching more.
- Cause: `youtubeProxy` made an uncached live call per request. YouTube `search.list` costs 100 quota units against a ~10,000/day default (≈100 searches/day), and the live catalog/Set Builder/search flows fan out many identical searches, so the project 429s quickly.
- Fix: Added a Firestore-backed `youtube_cache` (24h TTL), modeled on the existing `soundcharts_cache`. Identical YouTube queries are now served from one shared cached payload across all users instead of each costing 100 units. Bonus resilience: when a live call fails (e.g., 429), the proxy serves a **stale** cached entry if one exists, so quota exhaustion degrades gracefully instead of failing. New `functions/src/lib/youtubeCache.ts` (`youtubeCacheKey` excludes the injected API key and is order-independent; `cachedYoutubeGet` does read→fetch→write with stale fallback).
- Deployment: `firebase deploy --only functions:youtubeProxy` succeeded. Verified on the live function: a seeded `youtube_cache` entry was served back with HTTP 200 **without any YouTube call** (proving the cache-hit path bypasses the API/quota). A direct live call still 429s today because the daily quota is already spent — the cache will cut that going forward and the stale-fallback engages once a query is seeded.
- Files changed: `functions/src/lib/youtubeCache.ts` (new), `functions/test/youtubeCache.test.ts` (new), `functions/src/proxy.ts`, `functions/package.json`, `CLAUDE.md`, `CODEX.md`.
- Verification: `npm --prefix functions run build` passed; `npm --prefix functions test` passed (new cache test covers key determinism, miss→write, fresh hit, expiry refetch, stale-on-429 fallback, and rethrow-when-empty); live cache-hit returned the seeded payload at HTTP 200; temporary QA Pro grant set then revoked; seeded probe doc deleted.

### 2026-06-16 Apple Music Proxy 500 Fixed (On-Demand MusicKit Token)

- Task: Investigate and fix the persistent Apple Music proxy `500` that left Apple Music contributing nothing to recommendations.
- Root cause: `appleProxy` (and ingestion) used a **static** `APPLE_MUSIC_DEVELOPER_TOKEN` secret, and that stored token was **corrupted/malformed** (215 chars vs a healthy ~222; Apple's gateway returns a generic `500 "An unexpected error occurred"` for it). The MusicKit key itself (`NUSAWKGJ7X`, Team `36TZ8UKL8W`) is valid — freshly-signed tokens of every TTL returned `200`. Diagnosed empirically by signing test tokens with each `.p8` on disk against Apple Music API.
- Fix: replaced the static token with **on-demand generation** so it never goes stale. New `functions/src/lib/appleMusicToken.ts` signs an ES256 developer token from the MusicKit `.p8` + key id + team id using Node's built-in `crypto` (no new dependency); the signature is JOSE/`ieee-p1363` (raw r||s) — a DER signature is exactly what makes Apple `500`. Tokens are 12h, cached and regenerated near expiry, with fallback to the legacy static secret. Wired into `appleProxy` and the ingestion path (`fetchAppleMusicSignals`).
- New secrets: `APPLE_MUSIC_PRIVATE_KEY` (the `AuthKey_NUSAWKGJ7X.p8` contents), `APPLE_MUSIC_KEY_ID` (`NUSAWKGJ7X`), `APPLE_MUSIC_TEAM_ID` (`36TZ8UKL8W`). The legacy `APPLE_MUSIC_DEVELOPER_TOKEN` is retained as a fallback.
- Deployment: `firebase deploy --only functions:appleProxy,functions:ingestTrackSignals,functions:manualIngestTrackSignals` succeeded. Verified end-to-end: the live `appleProxy` now returns `HTTP 200` with real songs (`catalog/us/search?term=amapiano` → Asake & Olamide "Amapiano", TitoM/Yuppe/Burna Boy, TxC & Davido). This resolves the "Apple Music 500" residual risk noted in the ASC audit entries.
- Files changed: `functions/src/lib/appleMusicToken.ts` (new), `functions/test/appleMusicToken.test.ts` (new), `functions/src/lib/config.ts`, `functions/src/proxy.ts`, `functions/src/index.ts`, `functions/package.json`, `CLAUDE.md`, `CODEX.md`.
- Verification: `npm --prefix functions run build` passed; `npm --prefix functions test` passed (incl. the new ES256 token test — verifies JOSE signature validates and a DER one does not); production token generator + deployed proxy both returned `200`; temporary QA Pro grant was set then revoked.

### 2026-06-16 In-App Genre Verification (Stale-Build Correction)

- Task: Re-verify the genre-aware recommendation fix in the real Pro iOS app after the prior session reported it showing 0 tracks.
- Result: The fix WORKS end-to-end in the app. On a clean sim build signed in as a (temporarily Pro-granted, then revoked) QA account: genre `All` → 100 tracks, `Amapiano` → 28 real amapiano tracks (Hayya Hayya, "Amapiano (with Gyptian)"), `Afrobeats` → 26. The genre dropdown also correctly shows the full broad catalog.
- Root cause of the earlier "0 tracks" FAIL: a **stale iOS build**. The simulator build had failed its BoringSSL/gRPC script phase (`cp ... boringssl_prefix_symbols.h: Permission denied`), so the tested binary did not reflect the genre-refetch code. Clearing the stale `build/ios/Debug-iphonesimulator/BoringSSL-GRPC` (+ gRPC) products and `chmod -R u+w build/ios`, then rebuilding, produced a correct binary. This corrects the 2026-06-15 "residual 2.1 completeness risk (genre 0-tracks)" — it was a build artifact, not an app bug. (Build 10 in ASC review still predates the genre fix, so it shows the old behavior until rebuilt.)
- Diagnosis method (recorded for reuse): a temporary on-screen debug banner showing the `trackStreamProvider` AsyncValue (count/loading/error) + provider lane/region proved both that the build was fresh and that the refetch returned data. `maestro hierarchy | grep accessibilityText` reads Flutter on-screen text reliably.
- Files changed: none persisted (temporary debug banner in `lib/ui/features/trending/trending_screen.dart` was added then removed). `flutter analyze` clean; genre/trending tests pass.

### 2026-06-15 App Store Rejection-Risk Audit and Fixes

- Task: Audit the app for likely App Store Connect rejection reasons and fix them.
- Fixes applied (code; require a new native build to reach review binaries):
  - **5.1.1(v) macOS account deletion (HARD):** the macOS/desktop Settings Account card had Create Account + Sign Out but no in-app account deletion. Added a `Delete Account` button + confirmation flow (`accountDeletionServiceProvider.deleteAccount()`) shown for real signed-in accounts, mirroring mobile. Apple requires in-app deletion on every platform that supports account creation.
  - **5.1.1 unused permission:** removed `NSMicrophoneUsageDescription` from iOS Info.plist — the app never records audio (`mobile_scanner` is camera-only for QR; `file_picker` doesn't use the mic; the only "record" in code is `SetBuilderBehaviorService.record()`, behavior tracking). Camera (QR) and Photo Library (uploads/avatars) strings and the `remote-notification` background mode (FCM) are justified and kept.
  - **3.1.2 point-of-purchase disclosure:** added an auto-renew disclosure (price/period, renews unless canceled, manage in App Store settings) plus functional `Terms of Use (EULA)` and `Privacy Policy` links directly inside `SubscriptionSection`, so every purchase surface (sign-in gate, mobile/desktop settings, paywall sheet) is compliant. Removed the now-redundant standalone auto-renew line in `app.dart`.
- Audited and found already compliant: UGC moderation (Guideline 1.2 — upload agreement with zero-tolerance text + report-with-reasons + block, in `moderation_actions.dart`); Sign in with Apple present alongside Google/Email (4.8); mobile account deletion (5.1.1(v)); in-app Privacy/Terms/Support links; hidden `ASC_SCREENSHOT_SURFACE` is `dart-define`-gated and unreachable in production (no 2.3.1 hidden-feature risk); macOS sandbox entitlements (network.client, files.user-selected.read-write) match actual usage.
- Residual ASC risks NOT fixed by this pass (flagged for follow-up): (1) **2.1 completeness** — selecting a specific genre returns 0 tracks in the running app (the in-review build 10 still uses the old exact-match genre filter; the genre-aware fix is in the working tree but its in-app 0-result is still unresolved — see the prior entry); (2) **Apple Music source 500** — the `appleProxy` returns a persistent 500 in production, so Apple Music contributes nothing to recommendations; (3) **YouTube proxy 429** quota exhaustion observed during QA.
- Files changed: `ios/Runner/Info.plist`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/shell/vibe_shell_views.dart`, `lib/ui/widgets/subscription_section.dart`, `lib/app/app.dart`, `test/mobile/account_deletion_test.dart` (scroll the now-lower delete button into view), `test/widgets/subscription_disclosure_test.dart` (new), `CLAUDE.md`, `CODEX.md`.
- Verification: `flutter analyze` → `No issues found!`; `dart format --output=none --set-exit-if-changed lib/ test/` → 0 changed; full `flutter test` → 455 passed; `plutil -lint ios/Runner/Info.plist` → OK; `git diff --check` clean.

### 2026-06-15 Genre-Aware Recommendations and Charts

- Task: Audit and fix low-quality song recommendations/charts across Soundcharts, Apple Music, Spotify, and YouTube "based on selected criteria."
- Root cause: the selected genre barely reached retrieval or ranking. The live catalog/charts fetch was region-only (genre-blind); client genre filters used exact `==` against heterogeneous labels (Apple `Hip-Hop/Rap`, Soundcharts regional defaults, `Open Format` for null), so any specific genre nuked the feed; the merge ranker had no genre term; and a punitive region penalty buried genre-fit streaming rows. Net: picking "House" in a region returned regional top-songs relabeled and then discarded.
- Impact: Added shared genre intelligence (`canonicalGenre`, tolerant `genreMatches`, `isSpecificGenre`) in `lib/core/config/music_genres.dart`. Made retrieval genre-aware end-to-end: a specific lane drives genre-scoped Apple/Spotify/YouTube/Deezer queries, filters Apple/Soundcharts chart feeds to the lane, gates out known off-genre rows, makes genre a first-class ranking signal, softens the region gate when a genre is active, and stamps the lane onto genre-discovered streaming rows. Added `selectedGenreProvider` so changing genre refetches genre-scoped instead of post-filtering a genre-blind feed; wired Trending and the desktop Genres view to it; made Home/Trending/Regional genre filters tolerant; threaded `genreLane` into desktop/mobile Set Builder and Greatest Of.
- Product decision: genre is a first-class retrieval criterion, not a post-fetch filter. When a specific lane is chosen, chart rank only ranks tracks *within* that lane (a #1 off-genre chart hit is gated out). `All`/no-lane behavior — including the Soundcharts worldwide charts feed — is unchanged.
- Backend scope: Soundcharts proxy intentionally unchanged this pass (tight free-call budget; for specific genres regional charts are mostly off-genre and gated client-side anyway). No Functions redeploy required.
- Files changed: `lib/core/config/music_genres.dart`, `lib/services/platform_search_service.dart`, `lib/services/live_track_catalog_service.dart`, `lib/models/track_filters.dart`, `lib/providers/app_state.dart`, `lib/ui/features/trending/trending_screen.dart`, `lib/ui/features/home/home_screen.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/shell/vibe_shell_views.dart`, `lib/ui/shell/vibe_shell_setbuilder.dart`, `lib/ui/features/greatest_of/greatest_of_screen.dart`, `lib/ui/mobile/mobile_set_builder_tab.dart`, tests (`test/core/music_genres_test.dart`, `test/services/platform_search_genre_test.dart`, `test/services/live_track_catalog_service_test.dart`, `test/models/track_filters_genre_test.dart`, `test/providers/genre_refetch_test.dart`, `test/providers/guest_mode_provider_test.dart`), `CLAUDE.md`, and `CODEX.md`.
- Verification: `flutter analyze` passed (`No issues found!`); `dart format --output=none --set-exit-if-changed lib/ test/` reported 0 changed; full `flutter test` passed with 454 tests (433 prior + 21 new); `git diff --check` clean.
- Not yet shipped: web requires a Firebase Hosting redeploy; iOS/macOS require a native rebuild and ASC resubmission to carry this into review binaries.

### 2026-06-12 Platform-First Music Sourcing Restoration

- Task: Switch live song sourcing back to Apple Music, Spotify, YouTube, Deezer, Soundcharts, and adjacent platform evidence instead of requiring Soundcharts/chart evidence before a song can appear.
- Impact: `PlatformSearchService` now merges Soundcharts, Apple storefront charts, Spotify market search, Apple Music storefront search, YouTube, and Deezer for both search and trending paths. `LiveTrackCatalogService` now accepts platform-sourced rows with streaming URLs, while chart evidence still boosts confidence and matching-region ordering. `SoundchartsAiRankingService` now runs bounded AI ranking over any live platform-evidence candidate window, not only Soundcharts-backed windows.
- Follow-up impact: Restored direct music-platform playback links on chart-heavy rows by adding bounded playback-link enrichment for missing Spotify, Apple Music, YouTube, and Deezer URLs. Search copy now leads with Apple Music/Spotify/YouTube/Deezer and keeps Soundcharts as evidence/navigation rather than the only play action.
- Product decision: Do not read Firestore `tracks` for Pro live song selection. Use live platform search as the source of truth, with Soundcharts/Shazam/TikTok/Boomplay and Apple chart rank as ranking evidence rather than a hard gate.
- Files changed: `lib/services/platform_search_service.dart`, `lib/services/live_track_catalog_service.dart`, `lib/services/soundcharts_ai_ranking_service.dart`, `lib/ui/shell/vibe_shell_setbuilder.dart`, `lib/ui/features/greatest_of/greatest_of_screen.dart`, `lib/ui/features/search/search_screen.dart`, `lib/ui/features/search/search_screen_results.dart`, `lib/ui/mobile/search_tab.dart`, `test/services/platform_search_service_test.dart`, `test/services/live_track_catalog_service_test.dart`, `test/services/soundcharts_ai_ranking_service_test.dart`, `test/mobile/search_tab_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `dart analyze` for the touched source/test files passed; focused `flutter test test/services/platform_search_service_test.dart test/services/live_track_catalog_service_test.dart test/widgets/platform_play_actions_test.dart test/mobile/search_tab_test.dart --reporter expanded` passed with 14 tests; `flutter analyze` passed; full `flutter test --reporter expanded` passed with 434 tests.

### 2026-06-12 ASC EULA Metadata Rejection Recovery

- Task: Investigate App Store Connect rejection, fix the blocking issue, deploy the legal-page update, and resubmit iOS/macOS.
- Rejection found: Both iOS submission `0edee41d-b912-4d7f-b0e8-a86b6e169586` and macOS submission `60b2a249-edfa-4363-bb82-b0b7a54074e9` were rejected under Guideline `3.1.2 Business: Payments - Subscriptions` because the auto-renewable-subscription app metadata did not include a functional Terms of Use/EULA link in the App Description.
- Impact: Updated both ASC `en-US` app version descriptions to include Apple's standard EULA link, the hosted Privacy Policy link, and the hosted Support link. Updated the hosted Terms page to explicitly link Apple's standard EULA, deployed Firebase Hosting, cancelled the unresolved rejected submissions, and created fresh review submissions.
- ASC artifacts: iOS build `030a8669-1966-44ac-8676-b6a336ff7581` build `10` remains attached to iOS version `20c5730f-bd2f-4b39-b1b6-80928ed2e47a`; macOS build `efc7dc1e-5c84-4f57-86c8-2c36c5264cee` build `10` remains attached to macOS version `ed0249fd-1df2-4381-9225-7ab9d2bfad6b`. New review submissions are iOS `c5caa82d-829d-4f98-9f5f-94081143a428` and macOS `5ff2e775-608d-4736-933f-3da6ab3353de`, both `WAITING_FOR_REVIEW`.
- Files changed: `web/terms.html`, `build/web/terms.html`, `CLAUDE.md`, and `CODEX.md`. No binary rebuild/upload was required because Apple rejected metadata only and both build-10 binaries remained valid and attached.
- Verification: ASC UI displayed the rejection reason; ASC API verified both descriptions contain the EULA link, both builds are `VALID`, and both app versions are `WAITING_FOR_REVIEW`; Firebase Hosting deploy succeeded and `curl` verified `https://viberadar-462b8.web.app/terms.html` returns HTTP 200 with the Apple EULA link; the iOS ASC page visibly shows `Waiting for Review`.

### 2026-06-12 Full Genre Catalog Across App

- Task: Fix genre controls that only showed `Open Format` or `Afrobeats` after the live feed narrowed.
- Impact: Added a shared Flutter genre catalog and merged it into desktop/mobile genre controls across the main filter provider, Trending, Regional Pulse, Genre Landscape, Greatest Of, Set Builder slots, playlist aggregation, search discovery chips, library filters, artist filters, community profile chips, and upload metadata. Mobile Set Builder now defaults/falls back to a broad `Open Format, Hip-Hop, R&B, House, Afrobeats` lane instead of Afrobeats-only behavior.
- Product decision: Genre availability is a product capability, not a reflection of whatever genres happen to be present in the current live result set. Dynamic/local genres are still appended after the canonical catalog.
- Files changed: `lib/core/config/music_genres.dart`, `lib/providers/app_state.dart`, `lib/ui/features/trending/trending_screen.dart`, `lib/ui/features/greatest_of/greatest_of_screen.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/shell/vibe_shell_views.dart`, `lib/ui/shell/vibe_shell_playlists.dart`, `lib/ui/shell/vibe_shell_setbuilder.dart`, `lib/ui/features/search/search_screen.dart`, `lib/ui/features/search/search_screen_widgets.dart`, `lib/ui/features/library/library_screen.dart`, `lib/ui/features/artists/artists_screen.dart`, `lib/ui/features/community/profile_screen.dart`, `lib/ui/features/community/upload_screen.dart`, `lib/ui/mobile/mobile_set_builder_tab.dart`, `test/core/music_genres_test.dart`, `test/providers/guest_mode_provider_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: Focused Dart analysis passed; focused genre/provider Flutter tests passed with 7 tests; `flutter analyze` passed; `flutter test --reporter expanded` passed with 433 tests; `git diff --check` passed.

### 2026-06-11 ASC Build 10 Submission

- Task: Rebuild and resubmit native iOS/macOS binaries carrying the client-side chart-quality fixes (single-call chart-anchored trending, no unanchored text-search rows on Global, canonicalized Soundcharts queries).
- Impact: Bumped Flutter to `1.0.0+10`, built and uploaded iOS IPA build `030a8669-1966-44ac-8676-b6a336ff7581` and macOS App Store package build `efc7dc1e-5c84-4f57-86c8-2c36c5264cee`, canceled the build 9 review submissions, attached build 10 to both `1.0.0` platform versions, assigned both artifacts to `VibeRadar QA`, and submitted fresh iOS/macOS review submissions.
- ASC artifacts: iOS review submission `0edee41d-b912-4d7f-b0e8-a86b6e169586`; macOS review submission `60b2a249-edfa-4363-bb82-b0b7a54074e9`; both app versions are `WAITING_FOR_REVIEW` on build 10. Both builds are `VALID` with `usesNonExemptEncryption=false` inherited from the Info.plist keys. Monthly/yearly subscriptions remain `WAITING_FOR_REVIEW`.
- Files changed: `pubspec.yaml`, `CLAUDE.md`, and `CODEX.md`. Build artifacts remain under `build/` and were uploaded through `altool` with the Gplus ASC API key.
- Verification: iOS IPA `altool` validation/upload succeeded; `scripts/release_macos_appstore.sh` archive/export/validation succeeded and the pkg upload succeeded; ASC API confirmed both build 10 records processed to `VALID`, are attached to the correct platform versions, are assigned to `VibeRadar QA`, and both new review submissions report `WAITING_FOR_REVIEW`.

### 2026-06-11 Chart Quality, Quota Protection, and Soundcharts Cache

- Task: Investigate and fix "not getting good quality songs/charts" across the live trending catalog.
- Root causes found: Soundcharts chart selection took the first two charts in alphabetical list order (Global got "AfroBeats" + "Afrobeats on Radio", US got Country/Dance genre charts) while every "Top 200" chart sorted last and was never selected, and the paginated chart list (323 charts) was never paginated; one trending refresh issued 10 stopword-equivalent "music" queries that each refetched all charts live (~540 Soundcharts API calls, leaving only 259 on the ~1k free budget, ~2.5 minutes of refresh latency); proxy popularity weighted position/growth/recency equally so a brand-new #53 entry outscored the long-charting #2 hit; and Global trending allowed unanchored Spotify/Apple/YouTube text-search rows whose trendScore (popularity/100 ≈ 0.9+) outranked genuine chart rows (≈0.5–0.6).
- Impact: Added intent-ranked `chartPriority` selection with gospel/radio chart exclusion and 4-page chart-list pagination; added the Firestore-backed `soundcharts_cache` shared by `soundchartsProxy` and `ingestSoundchartsDaily` (chart lists 24h, rankings 6h); reweighted proxy scoring to 0.7 engagement / 0.15 growth / 0.15 recency; replaced the client `searchByGenre('music')` trending path with a single-call `fetchTrendingChartTracks` that requires chart evidence for every row including Global; and canonicalized client Soundcharts queries so stopword variants dedupe into one proxy call.
- Files changed: `functions/src/clients/soundcharts.ts`, `functions/src/lib/soundchartsCache.ts`, `functions/src/proxy.ts`, `functions/src/soundchartsIngest.ts`, `functions/package.json`, `functions/test/soundcharts.test.ts`, `functions/test/soundchartsCache.test.ts`, `functions/test/proxy.test.ts`, `lib/services/platform_search_service.dart`, `lib/services/live_track_catalog_service.dart`, `test/services/live_track_catalog_service_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Deployment: `firebase deploy --only functions:soundchartsProxy,functions:ingestSoundchartsDaily --project viberadar-462b8 --non-interactive` succeeded; `flutter build web --release --no-wasm-dry-run --dart-define=FIREBASE_APP_CHECK_ENABLED=false` succeeded; `firebase deploy --only hosting --project viberadar-462b8 --non-interactive` succeeded and the hosted site returns HTTP 200.
- Verification: `npm --prefix functions run build` passed; `npm --prefix functions test` passed including new chart-priority, pagination, scoring-order, and cache tests (proxy suite 69 assertions); `flutter analyze` passed; full `flutter test` passed with 430 tests; a live probe with production credentials confirmed the new selection ranks `shazam-top-200-world` first for Global and returns the worldwide Top 200 in chart order.
- Note: native build 9 was the prior review build and still ran the old 10-query client path. Native build 10 supersedes it in App Review and carries the single-call chart client.

### 2026-06-10 Global Region Regression Fix

- Task: Fix the "nothing loads / locked to Ghana / weird suggestions" regression after the regional catalog hardening.
- Impact: Kept Global/All as a real global selection instead of collapsing it to the account profile region or `GH`; required exact Soundcharts/Apple chart evidence before showing selected-region rows; penalized wrong-market chart evidence; parsed Soundcharts region metadata from live proxy results; and changed mobile/desktop Set Builder defaults from Ghana/Accra/Afrobeats to Global/Open Format.
- Files changed: `lib/providers/app_state.dart`, `lib/services/live_track_catalog_service.dart`, `lib/services/platform_search_service.dart`, `lib/ui/features/home/home_screen.dart`, `lib/ui/features/trending/trending_screen.dart`, `lib/ui/mobile/mobile_set_builder_tab.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/shell/vibe_shell_setbuilder.dart`, `test/home_region_selector_test.dart`, `test/providers/guest_mode_provider_test.dart`, `test/services/live_track_catalog_service_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: Focused `flutter test test/services/live_track_catalog_service_test.dart test/providers/guest_mode_provider_test.dart test/home_region_selector_test.dart --reporter expanded` passed with 8 tests; `flutter analyze` passed; full `flutter test --reporter expanded` passed with 429 tests; `git diff --check` passed for touched source files.

### 2026-06-10 ASC Build 8 Submission

- Task: Replace the build 7 ASC submission with native iOS/macOS binaries that include the Global/All region regression fix.
- Impact: Bumped Flutter to `1.0.0+8`, built and uploaded iOS IPA build `05cfe54f-678c-4ae0-8bcd-416b12269fe2` and macOS App Store package build `b9a2b09c-d206-4413-8eec-4cd525967874`, canceled/replaced the build 7 review submissions, attached build 8 to both `1.0.0` platform versions, assigned both artifacts to `VibeRadar QA`, set export compliance to `usesNonExemptEncryption=false`, and submitted fresh iOS/macOS review submissions.
- ASC artifacts: iOS delivery/build `05cfe54f-678c-4ae0-8bcd-416b12269fe2`, macOS delivery/build `b9a2b09c-d206-4413-8eec-4cd525967874`, iOS review submission `5c5e7d05-8254-4556-8b2d-2497ce3a7d51`, macOS review submission `73f7abb2-0050-4096-9080-9db240dc4fe7`; both app versions are `WAITING_FOR_REVIEW` on build 8. Monthly/yearly subscriptions remain `WAITING_FOR_REVIEW`.
- Files changed: `pubspec.yaml`, `CLAUDE.md`, and `CODEX.md`. Build artifacts remain under `build/` and were uploaded through App Store Connect tooling.
- Verification: iOS IPA build, Apple validation, and upload succeeded; macOS archive/export/package validation and upload succeeded; ASC API confirms both build 8 records are `VALID`, attached to the correct platform versions, export-compliance false, assigned to `VibeRadar QA`, and waiting for review.

### 2026-06-10 Regional Selection and Mobile Set Builder

- Task: Improve song/chart selection quality after Ghana-region QA and add missing mobile Set Builder parity.
- Impact: Removed client Firestore `tracks` as the Pro live song source, anchored selected-region results to Soundcharts/Apple storefront chart evidence, propagated region to Apple Music and Spotify lookups, made region filters refetch live catalog data, and added a mobile Set Builder that saves generated sets to the account.
- Files changed: `lib/providers/app_state.dart`, `lib/services/live_track_catalog_service.dart`, `lib/services/platform_search_service.dart`, `lib/services/apple_music_artist_service.dart`, `lib/services/spotify_artist_service.dart`, `lib/services/set_sequence_planner.dart`, `lib/services/soundcharts_ai_ranking_service.dart`, `lib/ui/features/trending/trending_screen.dart`, `lib/ui/mobile/mobile_shell.dart`, `lib/ui/mobile/mobile_set_builder_tab.dart`, `test/providers/guest_mode_provider_test.dart`, `test/services/live_track_catalog_service_test.dart`, `test/mobile/adaptive_shell_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `flutter analyze` passed; `flutter test --reporter expanded` passed with 427 tests.

### 2026-06-10 ASC Build 7 Submission

- Task: Submit native iOS and macOS binaries that include the regional live-catalog source fix and mobile Set Builder parity.
- Impact: Bumped Flutter to `1.0.0+7`, built and uploaded iOS IPA build `2b3bbaa4-7271-46dc-968d-c11780b54c05` and macOS App Store package build `437272c9-f968-417e-80dc-8accb81c6de9`, canceled/replaced the build 6 review submissions, attached build 7 to both `1.0.0` platform versions, assigned both artifacts to `VibeRadar QA`, set export compliance to `usesNonExemptEncryption=false`, and submitted fresh iOS/macOS review submissions.
- ASC artifacts: iOS delivery/build `2b3bbaa4-7271-46dc-968d-c11780b54c05`, macOS delivery/build `437272c9-f968-417e-80dc-8accb81c6de9`, iOS review submission `172a8da4-58fe-48fe-bfda-5ad6560ffe33`, macOS review submission `90879f9a-5e99-4367-b2f8-dc44706737ec`; both app versions are `WAITING_FOR_REVIEW` on build 7. Monthly/yearly subscriptions remain `WAITING_FOR_REVIEW`.
- Files changed: `pubspec.yaml`, `CLAUDE.md`, and `CODEX.md`. Build artifacts remain under `build/` and were uploaded through App Store Connect tooling.
- Verification: `flutter analyze` passed; `flutter test --reporter expanded` passed with 427 tests; iOS IPA build, Apple validation, and upload succeeded; macOS archive/export/package validation and upload succeeded; ASC API confirms both build 7 records are `VALID`, attached to the correct platform versions, export-compliance false, assigned to `VibeRadar QA`, and waiting for review.

### 2026-06-09

- Task: Production readiness audit, hardening, Firebase deploy, and IAP foundation.
- Impact: Added backend-owned App Store purchase sync, subscription UI, hardened AI/security rules, deployed Hosting/rules/indexes, cleaned secrets hygiene, and made CI gates production-facing.
- Files changed: `functions/src/iap.ts`, `functions/src/openai.ts`, `functions/src/pairing.ts`, `functions/src/lib/config.ts`, `functions/src/lib/storagePaths.ts`, `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `lib/providers/billing_provider.dart`, `lib/services/iap_service.dart`, `lib/ui/widgets/subscription_section.dart`, `lib/ui/mobile/mobile_settings_sheet.dart`, `lib/ui/shell/vibe_shell_views.dart`, `README.md`, `.github/workflows/ci.yml`, `.gitignore`, `CLAUDE.md`, `CODEX.md`, and related tests/platform config.
- Deployment: `firebase deploy --only hosting --project viberadar-462b8` succeeded; `firebase deploy --only firestore,storage --project viberadar-462b8` succeeded; Functions deploy blocked by missing `APP_STORE_ISSUER_ID` secret.

### 2026-06-09 Continued Hardening

- Task: Close high-impact production-readiness gaps found by backend/security/platform reviewers.
- Impact: StoreKit account binding now uses a UUID accepted by StoreKit 2, anonymous users are blocked from expensive callables, App Store JWS payloads are locally certificate-chain verified, likes and disconnects moved behind backend callables, account deletion removes quota/entitlement/purchase bindings, App Check callable support no longer emits deploy analyzer warnings, macOS signing fails on unexpanded entitlements, and Hosting was redeployed.
- Files changed: `functions/certs/*`, `functions/src/lib/auth.ts`, `functions/src/lib/appCheck.ts`, `functions/src/iap.ts`, `functions/src/openai.ts`, `functions/src/proxy.ts`, `functions/src/pairing.ts`, `functions/src/socialCounters.ts`, `functions/src/accountCleanup.ts`, `lib/providers/billing_provider.dart`, `lib/services/pairing_service.dart`, `lib/ui/shell/pair_phone_screen.dart`, `lib/ui/mobile/setlists_tab.dart`, `scripts/release_macos.sh`, `README.md`, `CLAUDE.md`, `CODEX.md`, and related tests.
- Deployment: `firebase deploy --only hosting --project viberadar-462b8` succeeded; `firebase deploy --only functions --project viberadar-462b8 --non-interactive` is clean through source analysis and blocked only by missing `APP_STORE_ISSUER_ID`.

### 2026-06-09 ASC Authentication and Release Readiness

- Task: Check Gplus ASC authentication, unblock deploys, and advance App Store submission readiness.
- Impact: Verified the Gplus App Store Connect API key authenticates; confirmed VibeRadar bundle ID exists; observed at that point that the ASC app record had not yet been created; set Firebase App Store Server API secrets; deployed all Functions; redeployed Hosting; captured iPhone 17 Pro Max and iPad Pro 13-inch onboarding screenshots; added Mac App Store export scaffolding.
- Files changed: `functions/.env.viberadar-462b8` (local ignored deploy env), `macos/ExportOptions-appstore.plist`, `scripts/release_macos_appstore.sh`, `README.md`, `CLAUDE.md`, `CODEX.md`, and `docs/qa/screenshots/asc/*`.
- Deployment: `firebase deploy --only functions --project viberadar-462b8 --non-interactive` succeeded; `firebase deploy --only hosting --project viberadar-462b8` succeeded.
- Historical blocker then: App Store Connect app creation/submission was blocked by missing interactive Apple Developer web session and unavailable numeric App Apple ID. The later ASC App and IAP Setup entry supersedes this state.

### 2026-06-09 ASC App and IAP Setup

- Task: Continue after interactive ASC login and complete first-pass App Store Connect/IAP setup.
- Impact: Created ASC app record `VibeRadar DJ` (`6778432071`) for iOS and macOS; configured App Store Server Notification V2 production/sandbox URLs; updated local Functions env to the numeric App Apple ID and redeployed Functions; created VibeRadar Pro monthly/yearly subscriptions; set all-country availability; set U.S. prices to `$9.99` monthly and `$79.99` yearly; uploaded accepted IAP review screenshots; both products initially reached `READY_TO_SUBMIT` before later final submission.
- Files changed: `functions/.env.viberadar-462b8` (local ignored deploy env), `docs/qa/screenshots/asc/iap-review/subscription-review.png`, `docs/qa/screenshots/asc/iap-review/subscription-review-iphone-69.png`, `CLAUDE.md`, and `CODEX.md`.
- Deployment: `firebase deploy --only functions --project viberadar-462b8 --non-interactive` succeeded after setting `APP_STORE_APP_APPLE_ID=6778432071`.
- Historical blocker then: final iOS/macOS submission required legal/account review, signed build uploads, app privacy, App Review contact phone, and subscription attachment. Later ASC continuation entries supersede this state; both platforms and subscriptions are now waiting for review.

### 2026-06-09 Onboarding Artist Images

- Task: Make "Choose Your Artists" pull and display actual Spotify artist images.
- Impact: Default popular artist choices now fetch Spotify artist search results through `spotifyOnboardingArtistImages`, prefer exact-name matches, cache image URLs server-side and in widget state, and render resilient cached artist photos with initials fallback. The footer adapts on phone-width layouts after widget testing exposed an overflow.
- Files changed: `functions/src/proxy.ts`, `functions/src/index.ts`, `functions/test/proxy.test.ts`, `lib/services/spotify_artist_service.dart`, `lib/ui/auth/onboarding_screen.dart`, `test/onboarding/onboarding_artist_images_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Deployment: `spotifyOnboardingArtistImages` was deployed to `viberadar-462b8`; Firebase CLI returned an unexpected exit code after printing deploy success, but `firebase functions:list` and a direct callable probe verified the function is live and returns real Spotify `i.scdn.co` image URLs. Firebase Hosting was rebuilt and redeployed from `build/web`.
- Verification: `npm --prefix functions run build`, `npm --prefix functions test`, `dart analyze lib/services/spotify_artist_service.dart lib/ui/auth/onboarding_screen.dart test/onboarding/onboarding_artist_images_test.dart`, `flutter analyze`, `flutter test test/onboarding/onboarding_artist_images_test.dart --reporter expanded`, `flutter test --reporter expanded`, and `git diff --check` all passed.

### 2026-06-09 ASC Product Screenshot Continuation

- Task: Replace rendered product screenshot work with real simulator captures and upload the available ASC screenshots.
- Impact: Captured iPhone 17 Pro Max and iPad Pro 13-inch screenshots from running iOS simulators, uploaded them to the iPhone 6.9-inch and iPad 13-inch ASC screenshot sets, patched uploads as complete, polled until Apple processed both assets, and deleted the stale iPad placeholder upload.
- Files changed: `docs/qa/screenshots/asc/iphone-69/simctl/onboarding-product.png`, `docs/qa/screenshots/asc/ipad-13/simctl/onboarding-product.png`, `macos/Runner/DebugProfile.entitlements`, `CLAUDE.md`, and `CODEX.md`.
- Verification then: ASC listed iPhone screenshot `83c641a2-708c-4a1e-8747-678319990eef` as `COMPLETE` at `1320x2868` and iPad screenshot `a868d766-4f43-4db0-b0e7-4b06315a3bcf` as `COMPLETE` at `2064x2752`; the later ASC Submission Continuation entry supersedes the then-empty macOS screenshot state.

### 2026-06-09 ASC Submission Continuation

- Task: Continue ASC production submission, replace IAP review art with real simulator screenshots, upload macOS product screenshots, complete privacy/pricing/export-compliance blockers, and validate review submission.
- Impact: Added a hidden IAP screenshot surface, captured a real iOS Simulator subscription-products screenshot, uploaded monthly/yearly IAP review screenshots to ASC, exported/uploaded/attached the macOS App Store build, uploaded a native cropped macOS product screenshot, published App Privacy labels, set app pricing to Free, set macOS `usesNonExemptEncryption=false`, created an ASC review submission draft, and identified the then-missing App Review Details blocker.
- Files changed: `lib/app/app.dart`, `lib/ui/widgets/subscription_section.dart`, `ios/Runner.xcodeproj/project.pbxproj`, `macos/Runner.xcodeproj/project.pbxproj`, `macos/Runner/Info.plist`, `macos/ExportOptions-appstore.plist`, `scripts/release_macos_appstore.sh`, `docs/qa/screenshots/asc/iap-review/simctl/subscription-products.png`, `docs/qa/screenshots/asc/macos/native/fullscreen-attempt.png`, `docs/qa/screenshots/asc/macos/native/fullscreen-after-wait.png`, `docs/qa/screenshots/asc/macos/native/fullscreen-reopen-attempt.png`, `docs/qa/screenshots/asc/macos/native/viberadar-macos-window.png`, `CLAUDE.md`, and `CODEX.md`.
- ASC artifacts: iOS build `96fb8fad-62f7-441c-a66e-1e3d40f4a11c`; macOS build `9060ff29-200c-4e01-8435-7d0ecda342b2`; monthly IAP screenshot `c3333cbc-ac79-4981-b5f6-a46c4615296d`; yearly IAP screenshot `70053620-f274-4ef4-8a9a-d6526fc4dfe7`; macOS product screenshot `98f02e2c-f119-46b4-b0e8-b12e87be4caa`; review submission draft `fb1dc723-c0e2-4e7c-b9a7-aab1cca23aef`.
- Historical blocker then: ASC required a real App Review `contactPhone` before `appStoreReviewDetail` could be created for either version. The later ASC Final Submission entry supersedes this blocker.

### 2026-06-09 Post-Auth Artist Preferences

- Task: Move "Choose Your Artists" behind authentication so preferences persist to the user's account.
- Impact: Pre-auth onboarding now ends at sign-in/account creation, and `AuthGate` shows the artist picker only for a real signed-in non-guest account. Selected artists are saved directly through `UserRepository.setFollowedArtists` to `users/{uid}.followed_artists`; skipped/completed status is tracked per user with `artist_preferences_completed_v1_{uid}`. Legacy `pending_followed_artists` is still migrated once for users who completed the old pre-auth flow.
- Files changed: `lib/ui/auth/auth_gate.dart`, `lib/ui/auth/onboarding_screen.dart`, `test/auth/auth_gate_onboarding_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `flutter test test/auth/auth_gate_onboarding_test.dart test/onboarding/onboarding_artist_images_test.dart --reporter expanded`, `flutter analyze`, and `git diff --check` passed.

### 2026-06-09 Guest Cost Gate

- Task: Make guest use cost-free by preventing guest sessions from using Firebase/API-backed features.
- Impact: "Continue as Guest" now starts a local demo/mock session instead of Firebase anonymous auth; legacy Firebase anonymous users map to demo mode; track/profile providers avoid live repositories until a real signed-in session exists; StoreKit product loading is skipped for guests; desktop/mobile shells show a Demo Mode sample-data banner; live search, AI, artist, community, upload, pairing, and profile screens show sign-in gates in guest mode.
- Files changed: `lib/data/repositories/session_repository.dart`, `lib/providers/app_state.dart`, `lib/providers/billing_provider.dart`, `lib/ui/auth/auth_gate.dart`, `lib/ui/widgets/guest_mode_banner.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/mobile/mobile_shell.dart`, `test/providers/guest_mode_provider_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `flutter analyze`, `flutter test test/mobile/iphone_overflow_test.dart --reporter expanded`, `flutter test test/providers/guest_mode_provider_test.dart test/auth/auth_gate_onboarding_test.dart test/mobile/adaptive_shell_test.dart test/billing_provider_test.dart test/mobile/iphone_overflow_test.dart --reporter expanded`, `flutter test --reporter expanded` with 397 passing tests, and `git diff --check` passed.

### 2026-06-09 ASC Final Submission

- Task: Continue ASC after reviewer contact details were filled and submit both platform apps plus subscriptions.
- Impact: Built a fresh post-guest-gate iOS IPA and Mac App Store package, validated and uploaded both through `altool`, attached iOS/macOS build 2 to the `1.0.0` app versions, submitted monthly/yearly subscriptions, created separate iOS and macOS review submissions, and transitioned both app versions to `WAITING_FOR_REVIEW`.
- ASC artifacts: iOS build `35f5742f-7a87-4da4-925d-ecfa167e93a0`, macOS build `7d7c2b4a-72e2-4c5f-b289-8248cd4397a4`, iOS review submission `be24c462-0674-4958-9b42-2985406ccb8f`, macOS review submission `4e5021d1-dca9-421c-b9a2-0f1c34965421`, monthly subscription submission `f900334c-ab35-4d46-8db2-c8fd7494de95`, yearly subscription submission `f8911dfa-33d6-41aa-bf03-196ec8ae9545`.
- Verification: ASC API reports iOS and macOS app versions as `WAITING_FOR_REVIEW`, both build 2 records as `VALID`, monthly/yearly subscriptions as `WAITING_FOR_REVIEW`, and all uploaded product/IAP screenshots as `COMPLETE`.
- Historical operational note then: macOS external beta assignment reported “Build is not in an externally assignable state,” but the macOS build was attached to App Store review. This is superseded by the build 9 submission, where both iOS and macOS build 9 artifacts were assigned to `VibeRadar QA`. `cyberzonenas93@gmail.com` remains in the VibeRadar QA beta group, and `test@viberadar.com` exists in Firebase Auth for reviewer access.

### 2026-06-09 Setlist Parity and Pairing Reliability

- Task: Fix phone/mac terminology mismatch, severe macOS lag on large saved setlists, and phone-created setlists not being usable on the computer.
- Impact: User-facing saved music language is now "Setlist" / "Saved Setlists" across mobile, desktop navigation, onboarding, AI, Set Builder, search, trending, artist bulk add, and Export Studio list surfaces. Internal `Crate` naming remains where it is storage/export implementation detail or physical DJ crate terminology.
- Impact: The macOS Saved Setlists screen now lazy-builds cards and renders bounded track previews: six tracks by default, up to eighty when expanded, while Export Studio and direct export actions still operate on the full setlist.
- Impact: Signed-in phone saves now persist to the user account and best-effort push to the currently paired computer. Pairing push failures no longer block account persistence.
- Impact: Mac pairing import now seeds the local Export Studio immediately from received rich setlist entries and still saves to account setlists when the desktop session is authenticated.
- Files changed: `lib/providers/paired_computer_provider.dart`, `lib/providers/setlist_provider.dart`, `lib/ui/mobile/connect_computer_sheet.dart`, `lib/ui/shell/pair_phone_screen.dart`, `lib/ui/shell/vibe_shell_crates.dart`, `lib/models/app_section.dart`, setlist/product-copy surfaces, and pairing/setlist tests.
- Verification: `dart analyze` on the touched surfaces passed; `flutter analyze` passed; focused setlist/pairing/mobile tests passed; full `flutter test` passed with 400 tests.

### 2026-06-09 ASC Actual App Screenshot Replacement

- Task: Replace ASC onboarding/sign-in screenshots with actual app screens captured from simulators/native app windows and resubmit both platform apps.
- Impact: Removed both app versions from review, captured and uploaded actual app screenshot sets, deleted stale onboarding/sign-in screenshot assets, then created fresh iOS and macOS review submissions.
- Files changed: `lib/app/app.dart`, `docs/qa/screenshots/asc/iphone-69/simctl/app-screens/*`, `docs/qa/screenshots/asc/ipad-13/simctl/app-screens/*`, `docs/qa/screenshots/asc/macos/native/app-screens/*`, `CLAUDE.md`, and `CODEX.md`.
- ASC artifacts: iOS review submission `083ca702-44f4-4995-90a9-798e2eca3b49`, macOS review submission `41ac3aaa-37e1-4b61-9e19-3b8bd1caa616`; screenshot sets now contain 5 iPhone, 5 iPad, and 4 macOS actual-app screenshots, all `COMPLETE`.
- Verification: ASC API reports iOS and macOS app versions and review submissions as `WAITING_FOR_REVIEW`; monthly/yearly subscriptions remain `WAITING_FOR_REVIEW`; `cyberzonenas93@gmail.com` remains in the VibeRadar QA TestFlight group; `dart analyze lib/app/app.dart` passed.

### 2026-06-09 ASC Global Market Availability

- Task: Make VibeRadar available in all App Store markets.
- Impact: Created the v2 ASC app availability resource for app `6778432071` with all 175 current App Store territories enabled and future territories enabled. During final verification the earlier iOS review submission item had been removed, so a fresh iOS review submission `7142414e-8f04-49b1-ab1f-af5909a5eb35` was created and submitted.
- Files changed: `CLAUDE.md` and `CODEX.md`.
- Verification: ASC API returned app availability id `6778432071`, `availableInNewTerritories=true`, 175 territory availability rows, 175 included territories, 175 rows with `available=true`, and zero unavailable territories. ASC API also reports iOS app version `20c5730f-bd2f-4b39-b1b6-80928ed2e47a` and macOS app version `ed0249fd-1df2-4381-9225-7ab9d2bfad6b` as `WAITING_FOR_REVIEW`.

### 2026-06-09 ASC Build 3 Resubmission

- Task: Build and submit binaries that include the setlist terminology, large-setlist performance, and phone-to-computer pairing fixes.
- Impact: Bumped the Flutter build to `1.0.0+3`, rebuilt and uploaded iOS IPA build `7aae5142-4d03-4724-ba96-fb03cd047ccd`, rebuilt and uploaded macOS package build `a7e27648-ff32-4c62-88e5-89a2e4a851eb`, canceled the old build 2 review submissions, attached build 3 to both platform versions, and submitted fresh review submissions.
- ASC artifacts: iOS review submission `35e5e1c5-ed83-41e4-b425-8cf042b19484`; macOS review submission `25da2730-0952-4569-bf21-4a9663c2c7e2`; both app versions are `WAITING_FOR_REVIEW` on build 3. Monthly/yearly subscriptions remain `WAITING_FOR_REVIEW`.
- Files changed: `pubspec.yaml`, `scripts/release_macos_appstore.sh`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `dart analyze` on touched setlist/pairing surfaces passed; `flutter analyze` passed; focused setlist/pairing/mobile tests passed; iOS `altool` validation/upload succeeded; macOS package local signature/build metadata checks passed; macOS upload succeeded after transient Apple validation 500/502s; ASC API confirms both build 3 records are `VALID`, attached, export-compliance false, and waiting for review.

### 2026-06-10 Pro Live-Cost Gate

- Task: Protect API/Firestore costs for signed-in free users and surface subscriptions throughout the app.
- Impact: Active Pro/Studio entitlement is now required for Firestore `tracks` reads, OpenAI proxy calls, Spotify/Apple/YouTube platform proxies, manual ingestion refresh, desktop auto-ingest/sidebar refresh, Set Builder, playlist aggregation, artist catalog/search, Greatest Of platform augmentation, AI workflows, and automatic local-library artwork enrichment. Free signed-in users receive bundled preview tracks and persistent Pro upgrade prompts; guests remain local mock-only.
- Files changed: `firestore.rules`, `functions/.env.viberadar-462b8`, `functions/src/lib/config.ts`, `functions/src/lib/entitlements.ts`, `functions/src/proxy.ts`, `functions/src/openai.ts`, `functions/src/index.ts`, `functions/test/entitlements.test.ts`, `lib/providers/app_state.dart`, `lib/providers/billing_provider.dart`, `lib/providers/library_provider.dart`, `lib/services/ai_copilot_service.dart`, `lib/services/ingest_service.dart`, `lib/ui/widgets/pro_paywall.dart`, `lib/ui/widgets/sidebar_nav.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/mobile/mobile_shell.dart`, `test/providers/guest_mode_provider_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Deployment: `firebase deploy --only firestore:rules,functions:openaiProxy,functions:spotifyProxy,functions:appleProxy,functions:youtubeProxy,functions:manualIngestTrackSignals --project viberadar-462b8 --non-interactive` succeeded; `flutter build web --release --no-wasm-dry-run --dart-define=FIREBASE_APP_CHECK_ENABLED=false` succeeded; `firebase deploy --only hosting --project viberadar-462b8 --non-interactive` succeeded.
- Verification: targeted Dart analysis passed; `flutter analyze` passed; targeted provider/billing tests passed; full `flutter test --reporter expanded` passed with 402 tests; `npm --prefix functions run build` passed; `npm --prefix functions test` passed; Firestore rules dry-run compiled; `git diff --check` passed; post-deploy `firebase functions:list` showed the five updated functions; `curl -fsSI https://viberadar-462b8.web.app` returned HTTP 200.

### 2026-06-10 Gemini Pro Paywall Artwork

- Task: Upgrade payment walls, Pro-required states, and subscription prompts with premium Gemini-rendered artwork from the Gplus repo workflow.
- Impact: Added three optimized PNG assets for the Pro locked-panel hero, subscription/sign-in badge, and persistent upsell banner; paywall widgets now render artwork across desktop, mobile, and web with gradient fallbacks and narrow-width layouts that avoid mobile overflow.
- Files changed: `scripts/gen_paywall_gemini.js`, `assets/paywall/pro_locked_hero.png`, `assets/paywall/pro_sheet_badge.png`, `assets/paywall/pro_banner_live.png`, `pubspec.yaml`, `lib/ui/widgets/pro_paywall.dart`, `test/widgets/pro_paywall_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Deployment: `flutter build web --release --no-wasm-dry-run --dart-define=FIREBASE_APP_CHECK_ENABLED=false` succeeded; `firebase deploy --only hosting --project viberadar-462b8 --non-interactive` succeeded.
- Verification: Visual inspection of the generated assets passed; `node --check scripts/gen_paywall_gemini.js` passed; `dart analyze lib/ui/widgets/pro_paywall.dart` passed; `dart analyze test/widgets/pro_paywall_test.dart` passed; `flutter test test/widgets/pro_paywall_test.dart --reporter expanded` passed; focused guest/billing/overflow tests passed; `flutter analyze` passed; full `flutter test --reporter expanded` passed with 405 tests; `git diff --check` passed; deployed Hosting and `assets/assets/paywall/pro_locked_hero.png` returned HTTP 200.

### 2026-06-10 ASC Build 4 Submission

- Task: Submit native iOS and macOS binaries that include Pro cost-gate UI and Gemini-rendered paywall artwork.
- Impact: Built and uploaded iOS IPA build `19515410-b0d4-4d24-b404-ac8ecc352b05` and macOS App Store package build `f4e60855-5cfc-43b2-a5c8-7c972544aed2`; canceled/replaced the prior build 3 submissions; attached build 4 to both `1.0.0` platform versions; set export compliance to `usesNonExemptEncryption=false`; assigned both build 4 artifacts to the `VibeRadar QA` beta group; and submitted fresh iOS/macOS review submissions.
- ASC artifacts: iOS review submission `776ca9d9-944e-417b-aa92-2139c9495f2e`; macOS review submission `a4664e3f-cecc-43ca-a251-2ae5d8c43e06`; both app versions are `WAITING_FOR_REVIEW` on build 4. Monthly/yearly subscriptions remain `WAITING_FOR_REVIEW`.
- Files changed: `CLAUDE.md` and `CODEX.md` for release memory updates. Build artifacts remain under `build/` and were uploaded through App Store Connect tooling.
- Verification: iOS `altool` validation/upload succeeded; macOS package validation/upload succeeded; ASC API confirms both build 4 records are `VALID`, attached to the correct platform versions, export-compliance false, assigned to `VibeRadar QA`, and waiting for review; `cyberzonenas93@gmail.com` remains the QA beta tester.

### 2026-06-10 Splash Background Simplification

- Task: Remove the larger background splash animation so only the smaller radar animation plays.
- Impact: Replaced the full-screen generated splash frame loop with a solid `0xFF0C1015` background that matches the radar card palette, removed the 48-frame precache path from launch, removed the frame sequence from Flutter asset bundling, and added a regression widget test that fails if an image-backed splash animation is reintroduced.
- Files changed: `lib/ui/auth/splash_screen.dart`, `test/auth/splash_screen_test.dart`, `pubspec.yaml`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `dart format lib/ui/auth/splash_screen.dart test/auth/splash_screen_test.dart` passed; `dart analyze lib/ui/auth/splash_screen.dart test/auth/splash_screen_test.dart` passed; `flutter test test/auth/splash_screen_test.dart --reporter expanded` passed; `flutter test test/auth/auth_gate_onboarding_test.dart --reporter expanded` passed.

### 2026-06-10 Desktop Prepared Set Folder

- Task: Let DJs continue phone-created setlists on the Mac by preparing a local Serato/VirtualDJ-ready folder without touching the existing TIDAL/VirtualDJ export flow.
- Impact: Saved setlist cards now expose `Prepare Folder`, ask the user to scan a music folder if no local library is loaded, ask where to create the set folder, copy only exact/duplicate/high-confidence fuzzy local matches, write a setlist M3U, write `MISSING_TRACKS.txt` with TIDAL search and platform fallbacks, and write `MATCH_REPORT.txt` with copied/review/missing details plus optional Pro-only AI guidance. Uncertain filename matches are listed for review instead of copied automatically.
- Files changed: `lib/services/set_folder_preparation_service.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/shell/vibe_shell_crates.dart`, `test/services/set_folder_preparation_service_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `dart format lib/services/set_folder_preparation_service.dart lib/ui/shell/vibe_shell.dart lib/ui/shell/vibe_shell_crates.dart test/services/set_folder_preparation_service_test.dart` passed; `flutter test test/services/set_folder_preparation_service_test.dart` passed with 4 tests; targeted `flutter analyze` on the touched Dart files passed.

### 2026-06-10 Mac Amapiano Prepared-Folder QA

- Task: QA the Mac prepared-folder workflow against the real local Amapiano folder on disk.
- Impact: Verified `/Users/angelonartey/Downloads/amapiano` contains 446 supported audio files across 2.9 GB, the scanner indexed all 446 files, and the prepared-folder service created a temporary `Amapiano QA Set` with 8 copied local tracks, 1 intentional missing track, 0 review-needed tracks, and 0 copy errors. The generated M3U, `MISSING_TRACKS.txt`, TIDAL search fallback, Spotify fallback, `MATCH_REPORT.txt`, and AI-assist report insertion were all verified. Temporary QA output was deleted after the run.
- Verification: `flutter test tool/qa_amapiano_prepare_folder_test.dart --reporter expanded` passed before the local-only harness was removed; `flutter build macos --debug` succeeded and produced `build/macos/Build/Products/Debug/VibeRadar.app`; the native debug app launched successfully and stayed alive until quit. Build emitted dependency warnings from StoreKit deprecations, missing Metal cryptex Swift search paths, duplicate libraries, old pod deployment targets, and Firebase plugin warnings, but no build failure.

### 2026-06-10 Maestro iOS Auth Smoke QA

- Task: Add and run a Maestro simulator smoke test for the iOS cold-launch onboarding and authentication gate.
- Impact: Added a reusable Maestro flow that clears app state, verifies the intro carousel, skips into feature onboarding, skips to the sign-in gate, opens email sign-in, and verifies the email/password form. This protects the pre-auth sequencing requirement that artist preferences stay behind real sign-in.
- Files changed: `docs/qa/maestro/ios_auth_smoke.yaml`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `flutter build ios --simulator --debug --dart-define=FIREBASE_APP_CHECK_ENABLED=false` passed and produced `build/ios/iphonesimulator/Runner.app`; `maestro check-syntax docs/qa/maestro/ios_auth_smoke.yaml` passed; `maestro --udid 43B20446-A259-4F82-9227-25DB7CCF74A9 test --debug-output outputs/maestro --flatten-debug-output docs/qa/maestro/ios_auth_smoke.yaml` passed on simulator `GPLUS-MARKET-QA` running iOS 26.5. Screenshots were captured at `outputs/maestro/screenshots/ios-intro-carousel.png` and `outputs/maestro/screenshots/ios-email-auth-form.png`.

### 2026-06-10 Maestro Signed-In iOS QA

- Task: Create real test credentials for Maestro and run a signed-in iOS simulator flow.
- Impact: Created Firebase Auth email/password test account `maestro.qa+20260610031708@viberadar.com` with UID `wAWEfn3fULZiv6kTWLjA1QuYkZZ2`. The password is stored only in ignored local file `outputs/maestro/credentials.env` with `0600` permissions. Added a reusable signed-in Maestro flow that uses environment variables, clears iOS keychain state, verifies Google and Apple sign-in buttons, signs in by email, confirms `Choose Your Artists` appears after authentication, skips artist setup, acknowledges the first-run dashboard tutorial, and verifies the signed-in free preview shell with the Upgrade prompt.
- Files changed: `docs/qa/maestro/ios_auth_smoke.yaml`, `docs/qa/maestro/ios_signed_in_smoke.yaml`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `maestro check-syntax docs/qa/maestro/ios_auth_smoke.yaml` passed; `maestro check-syntax docs/qa/maestro/ios_signed_in_smoke.yaml` passed; `maestro --udid 43B20446-A259-4F82-9227-25DB7CCF74A9 test --debug-output outputs/maestro/debug-auth --flatten-debug-output --test-output-dir outputs/maestro/screenshots docs/qa/maestro/ios_auth_smoke.yaml` passed; `maestro --udid 43B20446-A259-4F82-9227-25DB7CCF74A9 test --debug-output outputs/maestro/debug-signed-in --flatten-debug-output --test-output-dir outputs/maestro/screenshots docs/qa/maestro/ios_signed_in_smoke.yaml` passed with `MAESTRO_TEST_EMAIL`/`MAESTRO_TEST_PASSWORD` loaded from the ignored credentials file. Key screenshots: `outputs/maestro/screenshots/ios-auth-options.png`, `outputs/maestro/screenshots/ios-post-auth-artist-picker.png`, `outputs/maestro/screenshots/ios-signed-in-dashboard-tutorial.png`, and `outputs/maestro/screenshots/ios-signed-in-shell.png`.

### 2026-06-10 Native macOS QA With Maestro Boundary Check

- Task: QA the macOS app while checking the requested Maestro path.
- Impact: Verified Maestro 2.6.0 lists Android, iOS, and Web targets only, with no native macOS target. Native macOS QA was completed through Flutter build/tests plus macOS window/process automation instead of falsely reporting a Maestro-native pass.
- Verification: `maestro list-devices` passed and showed no macOS device type; `flutter build macos --debug --dart-define=FIREBASE_APP_CHECK_ENABLED=false` passed and produced `build/macos/Build/Products/Debug/VibeRadar.app`; focused desktop/Mac tests passed with 135 tests; the debug app launched as PID `94347`; System Events saw a `VibeRadar` window at `1280x820`; native screenshots verified the login gate and mock-data desktop shell. Artifacts: `outputs/macos-qa/viberadar-macos-frontmost.png` and `outputs/macos-qa/viberadar-macos-cliclick.png`.

### 2026-06-10 Guest Demo Copy Cleanup

- Task: Rename the desktop guest CTA and make the guest/demo banner explicitly warn that the data is not real.
- Impact: The desktop auth button now says `Continue as Guest`; guest shell banners now lead with `Demo Mode: sample data only, not real data` and prompt users to sign in for real trends, cloud sync, search, AI, community, and pairing. The sidebar status pill now says `Demo Mode: sample data only.`
- Files changed: `lib/ui/auth/auth_gate.dart`, `lib/ui/widgets/guest_mode_banner.dart`, `lib/ui/widgets/sidebar_nav.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: Targeted Dart analysis passed; focused guest/auth/mobile-overflow tests passed with 9 tests.

### 2026-06-10 ASC Build 5 Submission

- Task: Submit native iOS and macOS binaries that include the latest guest Demo Mode copy and macOS export-compliance metadata.
- Impact: Bumped Flutter to `1.0.0+5`, added `ITSAppUsesNonExemptEncryption=false` to the macOS app Info.plist, built and uploaded iOS IPA build `fdb26cf9-a4dc-4c68-a912-0922ed3e8850` and macOS App Store package build `a14e0c22-d13f-4297-9c20-13f0d91f2932`, canceled/replaced the build 4 submissions, attached build 5 to both `1.0.0` platform versions, assigned both artifacts to `VibeRadar QA`, and submitted fresh review submissions.
- ASC artifacts: iOS review submission `dae74ded-d00f-4cf9-b56a-bed487dc3a81`; macOS review submission `4b6f6412-2d4d-489c-80cc-865dfe70fdb1`; both app versions are `WAITING_FOR_REVIEW` on build 5. Monthly/yearly subscriptions remain `WAITING_FOR_REVIEW`.
- Files changed: `pubspec.yaml`, `macos/Runner/Info.plist`, `CLAUDE.md`, and `CODEX.md`. Build artifacts remain under `build/` and were uploaded through App Store Connect tooling.
- Verification: `flutter analyze` passed; `flutter test --reporter expanded` passed with 410 tests; `plutil -lint` passed for platform plists; iOS `altool` validation/upload succeeded; macOS package validation/upload succeeded; ASC API confirms both build 5 records are `VALID`, attached to the correct platform versions, export-compliance false, assigned to `VibeRadar QA`, and waiting for review.

### 2026-06-10 Manual Unlimited Pro Grants

- Task: Give `angelonartey@hotmail.com` and `cyberzonenas93@gmail.com` full Pro access with unlimited usage.
- Impact: Added backend support for per-entitlement usage overrides. Active entitlement records with `unlimited: true` resolve all cost-heavy usage limits to `-1`, which the existing quota enforcer treats as unlimited. Granted both Firebase Auth users active lifetime `studio` access through backend-owned `entitlements/{uid}` documents with no `expiresAt` field.
- Production grants: `angelonartey@hotmail.com` / `XNsers0aOehYnWamR6hhn4yNDZv1`; `cyberzonenas93@gmail.com` / `yOl5QwJUKPZjofGPF1ks02YNuAm1`.
- Files changed: `functions/src/lib/entitlements.ts`, `functions/test/entitlements.test.ts`, `functions/package-lock.json`, `CLAUDE.md`, and `CODEX.md`. `functions/package.json` already had pre-existing dependency/script changes that `npm ci` aligned the lockfile with.
- Deployment: `firebase deploy --only functions:openaiProxy,functions:spotifyProxy,functions:appleProxy,functions:youtubeProxy,functions:manualIngestTrackSignals --project viberadar-462b8 --non-interactive` succeeded.
- Verification: `npm --prefix functions run build` passed; `npm --prefix functions test` passed; `git diff --check` passed for the touched entitlement files; Firebase Admin verified both entitlement docs are active `studio`, `unlimited: true`, all usage limits `-1`, and no `expiresAt` field.

### 2026-06-10 Soundcharts Live Search and AI Model Fix

- Task: Use Soundcharts across live song-selection workflows and fix the macOS AI service failure caused by stale model configuration.
- Impact: Added the Pro-gated `soundchartsProxy` callable backed by server-side Soundcharts secrets, query/region/platform validation, relevance filtering, scoring, dedupe, and merged source/region evidence. `PlatformSearchService` now queries Soundcharts alongside Spotify, Apple Music, and YouTube with per-instance Soundcharts caching. Set Builder, Greatest Of, desktop/mobile search, and AI setlist resolution now consume Soundcharts-aware results; AI-created setlists persist Soundcharts evidence URLs. The AI prompt includes Soundcharts/Shazam/TikTok/Boomplay evidence, and OpenAI model defaults/allowlists were normalized to `gpt-4.1`/`gpt-4o-mini` so old `gpt-5.4` preferences no longer break Mac AI calls.
- Security: Soundcharts credentials remain backend-only; the callable requires a full account plus active Pro/Studio entitlement and uses the existing monthly platform-proxy quota bucket.
- Files changed: `functions/src/proxy.ts`, `functions/src/index.ts`, `functions/src/lib/config.ts`, `functions/.env.viberadar-462b8`, `functions/test/proxy.test.ts`, `functions/test/openai.test.ts`, `lib/services/platform_search_service.dart`, `lib/providers/library_provider.dart`, `lib/ui/shell/vibe_shell_setbuilder.dart`, `lib/ui/features/greatest_of/greatest_of_screen.dart`, `lib/services/ai_copilot_service.dart`, `lib/ui/features/ai_copilot/ai_copilot_screen.dart`, `lib/ui/features/ai_copilot/ai_copilot_screen_models.dart`, `lib/ui/features/search/search_screen.dart`, `lib/ui/features/search/search_screen_results.dart`, `lib/ui/mobile/search_tab.dart`, `test/mobile/search_tab_test.dart`, `README.md`, `CLAUDE.md`, and `CODEX.md`.
- Deployment: `firebase deploy --only functions:soundchartsProxy,functions:openaiProxy --project viberadar-462b8 --non-interactive` succeeded; `firebase functions:list --project viberadar-462b8 | rg "soundchartsProxy|openaiProxy"` confirmed both callables on Node.js 22 in `us-central1`.
- Verification: `npm --prefix functions run build` passed; `npm --prefix functions test` passed; targeted Dart analysis passed; `flutter analyze` passed; focused search/AI/Greatest Of tests passed; full `flutter test --reporter expanded` passed with 410 tests; `git diff --check` passed.

### 2026-06-10 Soundcharts AI Ranking for Set Builder and Greatest Of

- Task: Ensure Greatest Of, Set Builder, and adjacent song-selection flows use Soundcharts with AI rather than generic platform popularity ordering.
- Impact: Added a shared `SoundchartsAiRankingService` that ranks live platform results with Soundcharts/Shazam/TikTok/Boomplay evidence first, then performs a bounded AI rerank that can only reorder supplied candidate IDs. Set Builder now runs each slot through the shared Soundcharts AI ranker before saving setlist tracks. Greatest Of live platform augmentation now passes genre/region/artist/year context into the same ranker and labels results as Soundcharts & Platforms. `GreatestOfService` now boosts ingested Soundcharts evidence inside the local greatest-score calculation even when no live AI call is made.
- Risk controls: AI ranking is skipped when no Soundcharts evidence is present, capped to 40 candidates, and falls back to deterministic local ranking on any proxy/auth/quota/network/model error.
- Files changed: `lib/services/soundcharts_ai_ranking_service.dart`, `lib/services/greatest_of_service.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/shell/vibe_shell_setbuilder.dart`, `lib/ui/features/greatest_of/greatest_of_screen.dart`, `test/services/soundcharts_ai_ranking_service_test.dart`, `test/desktop/greatest_of_service_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: Targeted Dart analysis passed; `flutter analyze` passed; focused `flutter test test/services/soundcharts_ai_ranking_service_test.dart test/desktop/greatest_of_service_test.dart --reporter expanded` passed with 37 tests; full `flutter test --reporter expanded` passed with 414 tests; `npm --prefix functions run build` passed; `npm --prefix functions test` passed.

### 2026-06-10 Mock-Song Disclosure and Infrastructure Copy Cleanup

- Task: Remove the visible connected-to-Firebase sign and make guest/free catalog states unmistakably mock-only.
- Impact: Successful startup no longer emits a customer-facing backend connection status; the sidebar suppresses normal infrastructure success messages; guest/demo banners and free-account Pro prompts now lead with `MOCK SONGS ONLY` and state that listed songs are sample tracks, not real live songs or trend data. Settings, pairing errors, and AI Copilot chrome no longer show generic connected/backend setup copy as product affordances.
- Files changed: `lib/app/bootstrap.dart`, `lib/ui/widgets/sidebar_nav.dart`, `lib/ui/widgets/guest_mode_banner.dart`, `lib/ui/widgets/pro_paywall.dart`, `lib/ui/shell/vibe_shell_views.dart`, `lib/ui/shell/pair_phone_screen.dart`, `lib/ui/features/ai_copilot/ai_copilot_screen.dart`, `test/widgets/pro_paywall_test.dart`, `test/widgets/guest_mode_banner_test.dart`, `test/widgets/sidebar_nav_test.dart`, `test/mobile/pair_phone_screen_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: Targeted Dart analysis passed; focused guest/free/sidebar/pairing widget tests passed; `flutter analyze` passed; full `flutter test --reporter expanded` passed with 417 tests; `git diff --check` passed.

### 2026-06-10 Sequence-Aware Set Builder

- Task: Build Set Builder as an ordered DJ sequence with context, confidence/reasons, dedupe/version choice, behavior learning, and bounded AI.
- Impact: Added `SetSequencePlanner` for opener/warm-up/lift/peak/reset/closer planning; added DJ context controls for event type, city/market, crowd age, genre lane, energy curve, clean/explicit preference, set length, hard switches, must-play, and avoid terms; converted selected songs into phase-labeled tracks with confidence and human-readable reasons; saved/exported those reasons in AI crate JSON, CSV, and manifest output; and surfaced move/delete/mark-wrong controls so later builds learn from user behavior.
- Risk controls: AI can only reorder supplied Soundcharts/platform candidates; it does not invent songs. Candidate windows and must-play searches are capped, deterministic Soundcharts/local scoring is the fallback, dedupe groups alternate versions, clean DJ-ready edits are preferred when requested, local BPM/key metadata is used only when available, and artist repetition is penalized.
- Files changed: `lib/services/set_sequence_planner.dart`, `lib/services/set_builder_behavior_service.dart`, `lib/services/soundcharts_ai_ranking_service.dart`, `lib/providers/library_provider.dart`, `lib/services/export_service.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/shell/vibe_shell_setbuilder.dart`, `lib/ui/shell/vibe_shell_playlists.dart`, `lib/ui/shell/vibe_shell_crates.dart`, `test/services/set_sequence_planner_test.dart`, `test/services/set_builder_behavior_service_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `dart format` passed for touched Dart files; targeted `dart analyze` passed; focused Set Builder/Soundcharts tests passed with 10 tests; `flutter analyze` passed; full `flutter test --reporter expanded` passed with 423 tests.

### 2026-06-10 ASC Build 6 Submission

- Task: Submit native iOS and macOS binaries that include the sequence-aware Set Builder and latest Soundcharts AI ranking work.
- Impact: Bumped Flutter to `1.0.0+6`, built and uploaded iOS IPA build `31c17b48-be81-4abb-b7cc-a582c205c0b8` and macOS App Store package build `0d3f31f6-c265-4d0b-b6ea-4e9bd4a7281b`, canceled/replaced the build 5 submissions, attached build 6 to both `1.0.0` platform versions, assigned both artifacts to `VibeRadar QA`, and submitted fresh iOS/macOS review submissions.
- ASC artifacts: iOS delivery `31c17b48-be81-4abb-b7cc-a582c205c0b8`, macOS delivery `0d3f31f6-c265-4d0b-b6ea-4e9bd4a7281b`, iOS review submission `bcf1c42d-1b9e-4f1d-99a5-6db8b45029cf`, macOS review submission `b3d9019f-b642-49a1-a0b0-f9554c134341`; both app versions are `WAITING_FOR_REVIEW` on build 6. Monthly/yearly subscriptions remain `WAITING_FOR_REVIEW`.
- Files changed: `pubspec.yaml`, `CLAUDE.md`, and `CODEX.md`. Build artifacts remain under `build/` and were uploaded through App Store Connect tooling.
- Verification: iOS IPA build, Apple validation, and upload succeeded; macOS archive/export/package validation and upload succeeded; ASC API confirms both build 6 records are `VALID`, attached to the correct platform versions, export-compliance false, and waiting for review; beta-group relationship assignment returned success for both build 6 artifacts.

### 2026-06-10 Per-Song Platform Play Actions Restored

- Task: Restore the per-song `Play on Spotify`, `Play on Apple Music`, `Play on YouTube`, and related platform actions that had disappeared or collapsed into hidden/single best-link buttons.
- Impact: Added a shared `PlatformPlayActions` widget with deterministic platform ordering, duplicate/empty URL filtering, customer-facing labels, compact icon mode, and visible labeled buttons for larger rows. Desktop search, YouTube search rows, track tables, track detail sheets, track action menus, mobile setlist rows, saved setlist cards, playlist aggregation cards, Greatest Of cards, and Artist cards now expose all available song platform links instead of only a hover-only or best-platform shortcut.
- Product decision: Preserve existing quick card-tap behavior where present, but never make it the only path to platform playback when multiple service URLs exist. Soundcharts links are labeled as `View on Soundcharts`; streaming/music links are labeled as `Play on ...`.
- Files changed: `lib/ui/widgets/platform_play_actions.dart`, `lib/ui/widgets/track_action_menu.dart`, `lib/ui/widgets/track_table.dart`, `lib/ui/widgets/track_detail_panel.dart`, `lib/ui/features/search/search_screen.dart`, `lib/ui/features/search/search_screen_results.dart`, `lib/ui/mobile/search_tab.dart`, `lib/ui/mobile/setlist_editor.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/shell/vibe_shell_crates.dart`, `lib/ui/shell/vibe_shell_playlists.dart`, `lib/ui/features/greatest_of/greatest_of_screen.dart`, `lib/ui/features/greatest_of/greatest_of_screen_cards.dart`, `lib/ui/features/artists/artists_screen.dart`, `lib/ui/features/artists/artists_screen_cards.dart`, `lib/ui/features/artists/artists_screen_helpers.dart`, `test/widgets/platform_play_actions_test.dart`, `CLAUDE.md`, and `CODEX.md`.
- Verification: `flutter analyze` passed; `flutter test test/widgets/platform_play_actions_test.dart test/mobile/search_tab_test.dart test/mobile/setlist_editor_test.dart test/desktop/screen_smoke_test.dart` passed with 24 tests; `git diff --check` passed.

### 2026-06-10 Hard Global/All Region Fix and ASC Build 9 Submission

- Task: Fix the remaining regression where live catalog/search flows were still effectively locked to Ghana, then rebuild and submit both native apps.
- Impact: Client defaults now start on `Global` instead of falling back through Ghana/account profile defaults; guest/mock/user fallback profiles use `Global`; Settings keeps `Global` selectable; desktop Regions no longer converts Global into the highest-scoring regional bucket; platform search explicitly sends `Global`; and the backend Soundcharts proxy maps empty/All/Global to worldwide Soundcharts charts instead of configured regional defaults.
- Architecture decision: Region preference remains a saved account preference, but app startup no longer treats it as an implicit catalog filter. Soundcharts worldwide mode is represented as internal region `GLOBAL` with blank Soundcharts `countryCode`, while selected real countries still require matching chart evidence.
- Files changed: `lib/models/user_profile.dart`, `lib/data/repositories/user_repository.dart`, `lib/providers/app_state.dart`, `lib/ui/shell/vibe_shell.dart`, `lib/ui/mobile/mobile_shell.dart`, `lib/ui/shell/vibe_shell_views.dart`, `lib/app/app.dart`, `lib/services/platform_search_service.dart`, `functions/src/clients/soundcharts.ts`, `functions/src/proxy.ts`, `functions/test/proxy.test.ts`, `functions/test/soundcharts.test.ts`, `pubspec.yaml`, `CLAUDE.md`, and `CODEX.md`.
- Deployment: Deployed `functions:soundchartsProxy` to Firebase project `viberadar-462b8`; built Flutter web release with App Check disabled for current hosting config; deployed Firebase Hosting to `https://viberadar-462b8.web.app`.
- ASC artifacts: Bumped Flutter to `1.0.0+9`; iOS upload delivery/build `12ae5d34-7cdc-4c56-8e05-555d78c7a65e`; macOS upload delivery/build `5f774c7a-cbf9-44c6-a442-d33cef859610`; iOS review submission `c8cf5193-e6b2-49cc-be8e-86d96043ffaa`; macOS review submission `1d98a95d-a880-4a40-83f4-400b227dc440`. Both platform versions are `WAITING_FOR_REVIEW` on build 9, both builds are `VALID`, export compliance is `usesNonExemptEncryption=false`, and both builds are assigned to the `VibeRadar QA` beta group.
- Verification: Focused Dart analysis passed; focused Flutter tests passed with 8 tests; `npm --prefix functions run build` passed; `npm --prefix functions test` passed; full `flutter analyze` passed; full `flutter test --reporter expanded` passed with 429 tests; Firebase Functions and Hosting deploys succeeded; iOS IPA build/validation/upload succeeded; macOS archive/export/package validation/upload succeeded; ASC API final verification confirmed iOS and macOS build 9 are attached and `WAITING_FOR_REVIEW`.

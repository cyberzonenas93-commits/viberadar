# VibeRadar

VibeRadar is a macOS-first DJ intelligence workstation built with Flutter and Firebase. It aggregates trend signals from streaming platforms and surfaces them in a desktop-grade workflow with a sidebar, track table, and live detail panel.

## MVP included

- Flutter macOS app with desktop shell
- Sortable multi-select track table
- Filters for BPM, genre, vibe, region, and energy
- Track detail panel with momentum graph and platform links
- Set Builder with drag reordering and crate saving
- Saved crates, watchlist, regions, genres, and settings views
- Firebase Auth hooks for email and Google sign-in
- Firestore-backed repositories with demo-mode fallback
- Cloud Functions ingestion pipeline for Spotify, YouTube, Apple Music, plus SoundCloud and Beatport-ready adapters

## Project structure

```text
lib/                 Flutter desktop application
functions/           Firebase Cloud Functions ingestion service
firestore.rules      Firestore security rules
firestore.indexes.json
```

## Flutter setup

Install packages:

```bash
flutter pub get
```

Run the macOS app in demo mode:

```bash
flutter run -d macos
```

Run against Firebase by supplying dart-defines:

```bash
flutter run -d macos \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_STORAGE_BUCKET=... \
  --dart-define=GOOGLE_CLIENT_ID=... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=...
```

## Web app setup

VibeRadar can also run as a Flutter Web app. Without Firebase web
configuration it falls back to the same demo workspace, which is useful for
local verification:

```bash
flutter build web --release --no-wasm-dry-run
python3 -m http.server 53334 --bind 127.0.0.1 --directory build/web
```

For the live hosted app, create/register a Firebase Web app and build with its
web configuration:

```bash
flutter build web --release --no-wasm-dry-run \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_STORAGE_BUCKET=... \
  --dart-define=FIREBASE_AUTH_DOMAIN=... \
  --dart-define=FIREBASE_MEASUREMENT_ID=... \
  --dart-define=GOOGLE_CLIENT_ID=...
```

Firebase Hosting now serves `build/web` directly:

```bash
firebase deploy --only hosting
```

Browser limitations: the web app can match the desktop UI and cloud-backed
workflows, but browsers cannot directly scan arbitrary local folders, write to
VirtualDJ/Serato databases, or reveal Finder paths. Those desktop-only actions
need browser-safe equivalents such as file pickers, generated downloads, or a
small local companion service if true filesystem automation is required.

## Signed macOS release

If you distribute VibeRadar outside the Mac App Store, do not upload the raw app bundle from `build/macos/Build/Products/Release/`. That build is fine for local development, but browser-downloaded apps must be `Developer ID` signed and notarized or Gatekeeper will block launch.

Store notarization credentials once in your keychain:

```bash
xcrun notarytool store-credentials viberadar-notary \
  --apple-id "you@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

Create the distributable release artifacts:

```bash
APPLE_NOTARY_PROFILE=viberadar-notary ./scripts/release_macos.sh
```

The script builds the release app, re-signs it with a `Developer ID Application` certificate, notarizes and staples the `.app`, then creates a notarized DMG and a zip in `build/macos/dist/`.

Upload the DMG to Hosting, not the raw `.app` from `build/macos/Build/Products/Release/`.

## Mac App Store release

Mac App Store submission is separate from the Developer ID DMG path above. It
requires an App Store Connect app record, a Mac App Store signing identity, and
a provisioning profile that matches `com.viberadar.viberadar`.

After those Apple-side records exist, build and validate the package:

```bash
APPLE_TEAM_ID=36TZ8UKL8W ./scripts/release_macos_appstore.sh
```

The script archives `macos/Runner.xcworkspace`, exports with
`macos/ExportOptions-appstore.plist`, validates the `.pkg` using the App Store
Connect API key, and prints the upload command. It intentionally fails early if
only Developer ID signing assets are installed.

## Firebase setup

Install backend dependencies:

```bash
cd functions
npm install
```

Set Firebase Functions secrets:

```bash
firebase functions:secrets:set SPOTIFY_CLIENT_ID
firebase functions:secrets:set SPOTIFY_CLIENT_SECRET
firebase functions:secrets:set YOUTUBE_API_KEY
firebase functions:secrets:set APPLE_MUSIC_DEVELOPER_TOKEN
firebase functions:secrets:set SOUNDCLOUD_CLIENT_ID
firebase functions:secrets:set SOUNDCLOUD_OAUTH_TOKEN
firebase functions:secrets:set BEATPORT_API_TOKEN
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set APP_STORE_ISSUER_ID
firebase functions:secrets:set APP_STORE_KEY_ID
firebase functions:secrets:set APP_STORE_PRIVATE_KEY
```

Set parameterized non-secret values in `functions/.env.<project_id>`:

```bash
cat > functions/.env.your-project-id <<'EOF'
INGEST_REGIONS=US,GB,GH,NG,ZA,DE
BEATPORT_API_BASE_URL=https://partner-endpoint.example.com/tracks
USAGE_FREE_AI_MONTHLY_LIMIT=5
USAGE_FREE_PLATFORM_PROXY_MONTHLY_LIMIT=100
USAGE_FREE_MANUAL_INGEST_DAILY_LIMIT=0
USAGE_PRO_AI_MONTHLY_LIMIT=100
USAGE_PRO_PLATFORM_PROXY_MONTHLY_LIMIT=1500
USAGE_PRO_MANUAL_INGEST_DAILY_LIMIT=1
USAGE_STUDIO_AI_MONTHLY_LIMIT=400
USAGE_STUDIO_PLATFORM_PROXY_MONTHLY_LIMIT=7500
USAGE_STUDIO_MANUAL_INGEST_DAILY_LIMIT=3
PAIRING_CREATE_DAILY_LIMIT=20
PAIRING_CLAIM_DAILY_LIMIT=40
OPENAI_DEFAULT_MODEL=gpt-4.1
OPENAI_ALLOWED_MODELS=gpt-4.1,gpt-4o-mini
OPENAI_MAX_COMPLETION_TOKENS=1200
OPENAI_MAX_MESSAGES=12
OPENAI_MAX_MESSAGE_CHARS=4000
REQUIRE_APP_CHECK=true
CONSUME_APP_CHECK_TOKEN=false
APP_STORE_BUNDLE_ID=com.viberadar.viberadar
APP_STORE_APP_APPLE_ID=1234567890
APP_STORE_ENVIRONMENT=production
APP_STORE_PRODUCT_IDS=viberadar_pro_monthly,viberadar_pro_yearly
EOF
```

`REQUIRE_APP_CHECK` and `CONSUME_APP_CHECK_TOKEN` are read when callable
functions are deployed. Change them in the project env file, then redeploy
Functions to change callable enforcement. The manual HTTP ingest endpoint also
checks `REQUIRE_APP_CHECK` at runtime.

For production Flutter builds that use Firebase App Check, register the iOS,
macOS, Android, and web apps in Firebase App Check. Web release builds also need
the reCAPTCHA site key:

```bash
flutter build web --release --no-wasm-dry-run \
  --dart-define=FIREBASE_APPCHECK_RECAPTCHA_SITE_KEY=...
```

## IAP pricing and usage tiers

Launch publicly with a single paid tier:

- **VibeRadar Pro** — `$9.99/month` or `$79.99/year`
- Product IDs: `viberadar_pro_monthly`, `viberadar_pro_yearly`
- Limits: `100` AI requests/month, `1500` platform proxy lookups/month,
  `1` manual ingest refresh/day

Keep the higher tier backend-ready but hidden until usage data justifies it:

- **VibeRadar Studio** — `$19.99/month` or `$149.99/year`
- Product IDs: `viberadar_studio_monthly`, `viberadar_studio_yearly`
- Limits: `400` AI requests/month, `7500` platform proxy lookups/month,
  `3` manual ingest refreshes/day

Users without an active entitlement fall back to the Free limits above. Store
subscription state in backend-owned `entitlements/{uid}` documents with
`tier: "pro"` or `tier: "studio"` and an active status; clients may read their
own entitlement but cannot write it.

The app syncs StoreKit purchases through the `syncAppStorePurchase` callable.
App Store Server Notifications should be configured to call:

```text
https://us-central1-<project-id>.cloudfunctions.net/appStoreServerNotification
```

Create the subscription products in App Store Connect with the same product IDs
used in `APP_STORE_PRODUCT_IDS`. Keep product IDs stable across iOS and macOS
if both binaries unlock the same VibeRadar Pro entitlement.

`APP_STORE_APP_APPLE_ID` is the numeric App Apple ID from App Store Connect and
is required for production App Store signed-data verification. The Functions
bundle includes the Apple root certificates from Apple's PKI page so
transaction and notification JWS payloads can be certificate-chain verified.

Build the backend:

```bash
cd functions
npm run build
```

Deploy rules, indexes, Storage rules, and functions:

```bash
firebase deploy --only firestore,storage,functions --project <project-id>
```

Deploy Hosting after building `build/web`:

```bash
flutter build web --release --no-wasm-dry-run
firebase deploy --only hosting --project <project-id>
```

## Ingestion architecture

- Scheduler runs every 30 minutes.
- Source clients fetch:
  - Spotify search-based momentum candidates
  - YouTube Music trending videos
  - Apple Music song charts
  - SoundCloud search candidates
  - Beatport partner feed when partner credentials are available
- Signals are normalized, deduplicated by canonical title/artist, scored, and written into `tracks`.
- Previous `trend_history` values are retained for the desktop trend graph.

## Firestore model

### `tracks`

- `id`
- `title`
- `artist`
- `artwork_url`
- `bpm`
- `key`
- `genre`
- `vibe`
- `trend_score`
- `region_scores`
- `platform_links`
- `created_at`
- `updated_at`
- `energy_level`
- `trend_history`

### `users`

- `display_name`
- `preferences.region`
- `watchlist`
- `saved_crates`

## Notes

- The app never streams audio. It only links out to source platforms.
- If Firebase is not configured, the app falls back to a realistic demo dataset so the desktop UX still works locally.
- For production, wire platform-specific Firebase Auth configuration for macOS and validate the Google OAuth client IDs used by `google_sign_in`.
- SoundCloud and Beatport are optional at runtime; the ingestion pipeline skips them automatically when credentials are not configured.

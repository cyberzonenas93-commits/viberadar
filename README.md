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
```

Set parameterized non-secret values in `functions/.env.<project_id>`:

```bash
cat > functions/.env.your-project-id <<'EOF'
INGEST_REGIONS=US,GB,GH,NG,ZA,DE
BEATPORT_API_BASE_URL=https://partner-endpoint.example.com/tracks
EOF
```

Build the backend:

```bash
cd functions
npm run build
```

Deploy rules, indexes, and functions:

```bash
firebase deploy --only firestore,functions
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

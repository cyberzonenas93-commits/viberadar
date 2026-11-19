# First-run onboarding: intro graphics + per-screen tutorials

**Date:** 2026-06-08
**Status:** Design — awaiting review

## Problem / goal

First-time users land in a feature-dense app (21 desktop sections, ~9 mobile) with no guidance. Add, for both phone and Mac:

1. A **post-splash intro carousel** with beautiful Gemini-generated graphics introducing the app (first launch, before sign-in).
2. **Per-screen tutorial cards** — the first time a user opens a key screen, a bottom sheet explains it (Gemini illustration + short copy), shown once per screen.

Artwork is generated with Gemini using the **gplus repo's pattern** (`gemini-3-pro-image-preview` via `generativelanguage.googleapis.com`).

## Decisions (locked)

- Per-screen style: **intro card (bottom sheet)**, once per screen.
- Art: **intro slides + a unique illustration per covered screen** (~14 images).
- Coverage: **key screens only** — phone: Home, Trending, Search, AI, Setlists, Community; Mac adds For You, Artists, Set Builder, Library, Exports.
- Intro timing: **before sign-in** (splash → intro → artist-pick onboarding → login).
- Trigger tutorials at the **shell level** (2 wiring points), not per-screen.

## Architecture

### 1. Gemini generation — `scripts/gen_onboarding_gemini.js`
Mirrors [gplus's gen_gplus_dashboard_imagery.js](file:///Users/angelonartey/Desktop/gplus-app/scripts/gen_gplus_dashboard_imagery.js): POST to
`generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image-preview:generateContent`,
`responseModalities: ["TEXT","IMAGE"]`, extract `inlineData` PNG. Writes to `assets/onboarding/`:

- `intro_01.png`, `intro_02.png`, `intro_03.png` — cinematic, radar-pulse + audio-waveform motif, cyan `#24C8DB`→violet `#8B5CF6` on near-black `#06070B`, **dark zone reserved for overlay text, NO text/logos in the image**.
- `screen_<AppSection.name>.png` for each covered section — i.e. `screen_home.png`, `screen_trending.png`, `screen_search.png`, `screen_aiCopilot.png`, `screen_setlists.png`, `screen_community.png`, `screen_forYou.png`, `screen_artists.png`, `screen_setBuilder.png`, `screen_library.png`, `screen_exports.png` (one abstract hero each). The registry's `asset` field is the single source of truth for these paths; the script generates exactly those filenames.

Key handling: read `process.env.GEMINI_API_KEY` (the gplus Gemini key, exported at run time) — **not hardcoded**, keeping this repo secret-free (per the prior audit). After each write, downscale with macOS `sips -Z 800` to keep assets ~200–400 KB (≈14 images → a few MB, not ~20 MB of raw 1024² PNGs). 2 s delay between calls (gplus convention).

### 2. First-run state — `lib/providers/onboarding_state.dart`
`OnboardingState` over `SharedPreferences` (versioned keys). Async methods so no bootstrap change:

```dart
class OnboardingState {
  static const _introKey = 'onboarding_intro_v1';
  String _tutKey(AppSection s) => 'tutorial_${s.name}_v1';
  Future<bool> isIntroSeen();      Future<void> markIntroSeen();
  Future<bool> isTutorialSeen(AppSection s);  Future<void> markTutorialSeen(AppSection s);
}
final onboardingStateProvider = Provider<OnboardingState>((_) => OnboardingState());
```
Tested with `SharedPreferences.setMockInitialValues`.

### 3. Intro carousel — `lib/ui/onboarding/intro_carousel.dart`
`IntroCarousel({required VoidCallback onFinish})`: a `PageView` over a const list of
`(asset, title, subtitle)` slides — full-bleed `Image.asset` (with an `errorBuilder`
gradient fallback so a missing asset never shows broken), gradient scrim, headline +
subtitle in the dark zone, page dots, **Skip** (jumps to end) / **Next** / **Get Started**.
`onFinish` fires on Get Started or Skip.

Draft copy: *"Spot the wave early"* / *"VibeRadar scans the world's charts so you play tomorrow's hits tonight."* · *"Build the perfect set"* / *"AI-assisted, harmonically mixed, ready to export."* · *"Made for DJs"* / *"Trends, community and your crates — anywhere you are."*

### 4. Per-screen card — `lib/ui/onboarding/screen_tutorial.dart`
- `tutorialRegistry`: `Map<AppSection, ({String asset, String title, String body})>` covering the key sections (copy drafted below).
- `showScreenTutorial(BuildContext, AppSection)` → `showModalBottomSheet` with a frosted card (matches the design system): illustration (`Image.asset` + fallback) + title + body + **Got it**.
- `maybeShowTutorial(WidgetRef, BuildContext, AppSection)`: if the registry has the section and `!isTutorialSeen` → show sheet, then `markTutorialSeen`.

Draft copy (one line each): Home — *"Your dashboard: at-a-glance metrics and today's movers, tuned to your region."* · Trending — *"The freshest charting tracks across Spotify, Apple, Deezer & more, ranked by real momentum."* · Search — *"Find any track, artist or genre across every source at once."* · AI — *"Describe a vibe; the AI drafts a set you can resolve to playable links and save to a crate."* · Setlists — *"Build, reorder and sync crates — send them to your Mac with a tap."* · Community — *"Share mixes, follow DJs, and see what the scene is playing."* · For You — *"A personalised feed picked for your taste and region."* · Artists — *"Track artist momentum and their rising records."* · Set Builder — *"Harmonically-mixed sets with BPM/key-aware transitions."* · Library — *"Everything you've saved, watch-listed and built, in one place."* · Exports — *"Export crates to Serato, Rekordbox and more."*

### 5. Wiring (2 shells + auth gate)
- [auth_gate.dart](lib/ui/auth/auth_gate.dart): add `_AuthPhase.intro`. `_finishSplash` becomes: `!introSeen` → `intro`; else existing onboarding/login routing. Intro `onFinish` → `markIntroSeen()` → onboarding (or login if already onboarded).
- [mobile_shell.dart](lib/ui/mobile/mobile_shell.dart): map active tab → `AppSection`; on first build and on tab change, post-frame `maybeShowTutorial(ref, context, section)`.
- [vibe_shell.dart](lib/ui/shell/vibe_shell.dart): on active `AppSection` change, same post-frame call.
- [pubspec.yaml](pubspec.yaml): add `assets/onboarding/`.

## Data flow
First launch: splash → (introSeen? no) IntroCarousel → markIntroSeen → artist onboarding → login → shell. In shell: land on a covered section → (tutorialSeen? no) bottom-sheet card → Got it → markTutorialSeen. Subsequent launches skip both.

## Testing (TDD)
- `OnboardingState`: intro + per-section mark/seen round-trip (mock prefs).
- `tutorialRegistry`: every covered `AppSection` has non-empty asset/title/body (no gaps).
- `IntroCarousel`: renders N slides; **Get Started** calls `onFinish`; missing asset → fallback (no broken image / no throw).
- `maybeShowTutorial`: shows sheet on first call for a covered section, marks seen, does **not** show on second call; no-op for uncovered sections.
- Gemini script: build-time tool, run to produce real art (like `gen_logo_gemini.js`) — not unit-tested.

## Files
**New:** `scripts/gen_onboarding_gemini.js`, `assets/onboarding/*.png` (generated), `lib/providers/onboarding_state.dart`, `lib/ui/onboarding/intro_carousel.dart`, `lib/ui/onboarding/screen_tutorial.dart`, 3 test files.
**Modified:** `lib/ui/auth/auth_gate.dart`, `lib/ui/mobile/mobile_shell.dart`, `lib/ui/shell/vibe_shell.dart`, `pubspec.yaml`.

## Risks
- **Asset bundle size** — mitigated by `sips` downscale; verify total after generation.
- **Generation needs the key + network** — run-time env var; `errorBuilder` fallbacks mean the app degrades gracefully if an asset is absent.
- **Mobile tab → AppSection mapping** — confirm the mobile shell exposes (or can derive) an `AppSection` for each tab during implementation.

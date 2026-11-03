# First-run Onboarding (intro graphics + per-screen tutorials) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** First-time users get a beautiful Gemini-art intro carousel after the splash (before sign-in) and a once-per-screen tutorial bottom sheet on each key screen, on both phone and Mac.

**Architecture:** A `TutorialHost` wrapper shows a screen's tutorial once on first mount (fits mobile lazy tabs/pushed routes and desktop's section pane). `OnboardingState` (shared_preferences) tracks intro + per-section "seen". A Node script generates the art with Gemini (gplus pattern) into `assets/onboarding/`. `errorBuilder` fallbacks mean missing art never breaks the UI.

**Tech Stack:** Flutter/Dart, Riverpod, shared_preferences, url_launcher; Node + Gemini `gemini-3-pro-image-preview`.

**Note:** Working inline in the current checkout (no commits) — same as prior tasks. Run `flutter analyze` + targeted `flutter test` after each Dart task.

---

## File structure

**New:**
- `lib/providers/onboarding_state.dart` — first-run flags over shared_preferences.
- `lib/ui/onboarding/screen_tutorial.dart` — `tutorialRegistry`, `showScreenTutorial`, `maybeShowTutorial`, `TutorialHost`.
- `lib/ui/onboarding/intro_carousel.dart` — post-splash intro `PageView`.
- `scripts/gen_onboarding_gemini.js` — Gemini art generator.
- `assets/onboarding/*.png` — generated art.
- Tests: `test/providers/onboarding_state_test.dart`, `test/onboarding/screen_tutorial_test.dart`, `test/onboarding/intro_carousel_test.dart`.

**Modified:**
- `lib/ui/auth/auth_gate.dart` — `intro` phase.
- `lib/ui/mobile/mobile_shell.dart` — wrap covered tabs + 2 pushed screens in `TutorialHost`.
- `lib/ui/shell/vibe_shell.dart` — wrap `mainPanel` in a keyed `TutorialHost`.
- `pubspec.yaml` — register `assets/onboarding/`.

Covered sections (registry keys): `home, trending, search, aiCopilot, setlists, community, forYou, artists, setBuilder, library, exports`.

---

## Task 1: `OnboardingState` + provider

**Files:** Create `lib/providers/onboarding_state.dart`; Test `test/providers/onboarding_state_test.dart`.

- [ ] **Step 1: Write the failing test**

```dart
// test/providers/onboarding_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viberadar/models/app_section.dart';
import 'package:viberadar/providers/onboarding_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('intro defaults unseen, then marks seen', () async {
    final s = OnboardingState();
    expect(await s.isIntroSeen(), false);
    await s.markIntroSeen();
    expect(await s.isIntroSeen(), true);
  });

  test('per-section tutorial seen is independent', () async {
    final s = OnboardingState();
    expect(await s.isTutorialSeen(AppSection.home), false);
    await s.markTutorialSeen(AppSection.home);
    expect(await s.isTutorialSeen(AppSection.home), true);
    expect(await s.isTutorialSeen(AppSection.trending), false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/onboarding_state_test.dart`
Expected: FAIL — `onboarding_state.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
// lib/providers/onboarding_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_section.dart';

/// First-run flags: whether the intro carousel has played, and which per-screen
/// tutorials have been shown. Versioned keys so a future revamp can re-show.
class OnboardingState {
  static const _introKey = 'onboarding_intro_v1';
  String _tutKey(AppSection s) => 'tutorial_${s.name}_v1';

  Future<bool> isIntroSeen() async =>
      (await SharedPreferences.getInstance()).getBool(_introKey) ?? false;

  Future<void> markIntroSeen() async =>
      (await SharedPreferences.getInstance()).setBool(_introKey, true);

  Future<bool> isTutorialSeen(AppSection s) async =>
      (await SharedPreferences.getInstance()).getBool(_tutKey(s)) ?? false;

  Future<void> markTutorialSeen(AppSection s) async =>
      (await SharedPreferences.getInstance()).setBool(_tutKey(s), true);
}

final onboardingStateProvider = Provider<OnboardingState>((_) => OnboardingState());
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/onboarding_state_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit** — (skipped; inline no-commit run.)

---

## Task 2: Tutorial registry

**Files:** Create `lib/ui/onboarding/screen_tutorial.dart` (registry only for now); Test `test/onboarding/screen_tutorial_test.dart`.

- [ ] **Step 1: Write the failing test**

```dart
// test/onboarding/screen_tutorial_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/app_section.dart';
import 'package:viberadar/ui/onboarding/screen_tutorial.dart';

void main() {
  const covered = [
    AppSection.home, AppSection.trending, AppSection.search, AppSection.aiCopilot,
    AppSection.setlists, AppSection.community, AppSection.forYou, AppSection.artists,
    AppSection.setBuilder, AppSection.library, AppSection.exports,
  ];

  test('every covered section has complete tutorial copy + onboarding asset', () {
    for (final s in covered) {
      final e = tutorialRegistry[s];
      expect(e, isNotNull, reason: 'missing ${s.name}');
      expect(e!.title.isNotEmpty, true);
      expect(e.body.isNotEmpty, true);
      expect(e.asset.startsWith('assets/onboarding/'), true);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/onboarding/screen_tutorial_test.dart`
Expected: FAIL — file/`tutorialRegistry` missing.

- [ ] **Step 3: Implement the registry** (start `lib/ui/onboarding/screen_tutorial.dart`)

```dart
import '../../models/app_section.dart';

typedef TutorialEntry = ({String asset, String title, String body});

String _art(AppSection s) => 'assets/onboarding/screen_${s.name}.png';

final Map<AppSection, TutorialEntry> tutorialRegistry = {
  AppSection.home: (asset: _art(AppSection.home), title: 'Your Dashboard',
      body: "At-a-glance metrics and today's movers, tuned to your region."),
  AppSection.trending: (asset: _art(AppSection.trending), title: 'Trending Radar',
      body: 'The freshest charting tracks across Spotify, Apple, Deezer & more — ranked by real momentum.'),
  AppSection.search: (asset: _art(AppSection.search), title: 'Find Anything',
      body: 'Search any track, artist or genre across every source at once.'),
  AppSection.aiCopilot: (asset: _art(AppSection.aiCopilot), title: 'AI Set Builder',
      body: 'Describe a vibe; the AI drafts a set you can resolve to playable links and save to a crate.'),
  AppSection.setlists: (asset: _art(AppSection.setlists), title: 'Your Crates',
      body: 'Build, reorder and sync crates — send them to your Mac with a tap.'),
  AppSection.community: (asset: _art(AppSection.community), title: 'DJ Community',
      body: 'Share mixes, follow DJs, and see what the scene is playing.'),
  AppSection.forYou: (asset: _art(AppSection.forYou), title: 'For You',
      body: 'A personalised feed of tracks and artists picked for your taste and region.'),
  AppSection.artists: (asset: _art(AppSection.artists), title: 'Artists',
      body: 'Track artist momentum and dive into their rising records.'),
  AppSection.setBuilder: (asset: _art(AppSection.setBuilder), title: 'Set Builder',
      body: 'Craft harmonically-mixed sets with BPM/key-aware transitions.'),
  AppSection.library: (asset: _art(AppSection.library), title: 'My Library',
      body: "Everything you've saved, watch-listed and built — in one place."),
  AppSection.exports: (asset: _art(AppSection.exports), title: 'Exports',
      body: 'Export your crates to Serato, Rekordbox and more.'),
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/onboarding/screen_tutorial_test.dart`
Expected: PASS.

---

## Task 3: `TutorialHost` + `maybeShowTutorial` + `showScreenTutorial`

**Files:** Modify `lib/ui/onboarding/screen_tutorial.dart`; Test `test/onboarding/screen_tutorial_test.dart` (add cases).

- [ ] **Step 1: Add the failing widget test** (append to the existing test file)

```dart
// add imports at top:
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:shared_preferences/shared_preferences.dart';

testWidgets('TutorialHost shows the sheet once, then never again', (tester) async {
  SharedPreferences.setMockInitialValues({});
  Widget app() => ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TutorialHost(section: AppSection.home, child: const Text('SCREEN')),
          ),
        ),
      );

  await tester.pumpWidget(app());
  await tester.pumpAndSettle();
  expect(find.text('Your Dashboard'), findsOneWidget); // sheet shown
  await tester.tap(find.text('Got it'));
  await tester.pumpAndSettle();
  expect(find.text('Your Dashboard'), findsNothing);

  // Remount: already seen → no sheet.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(app());
  await tester.pumpAndSettle();
  expect(find.text('Your Dashboard'), findsNothing);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/onboarding/screen_tutorial_test.dart`
Expected: FAIL — `TutorialHost` undefined.

- [ ] **Step 3: Implement** (append to `lib/ui/onboarding/screen_tutorial.dart`)

Add imports at the top of the file:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/onboarding_state.dart';
```

Append:
```dart
/// Shows a screen's tutorial bottom sheet exactly once. Marks it seen *before*
/// showing so dismissing any way (Got it / swipe / tap-outside) never re-shows.
Future<void> maybeShowTutorial(
  WidgetRef ref,
  BuildContext context,
  AppSection section,
) async {
  final entry = tutorialRegistry[section];
  if (entry == null) return;
  final state = ref.read(onboardingStateProvider);
  if (await state.isTutorialSeen(section)) return;
  await state.markTutorialSeen(section);
  if (!context.mounted) return;
  await showScreenTutorial(context, entry);
}

Future<void> showScreenTutorial(BuildContext context, TutorialEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.edge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.asset(
                  entry.asset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [AppTheme.cyan, AppTheme.violet]),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(entry.title,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(entry.body,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14, height: 1.5)),
            const SizedBox(height: 20),
            SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.cyan,
                  foregroundColor: AppTheme.ink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Wrap any screen to fire its tutorial once on first mount.
class TutorialHost extends ConsumerStatefulWidget {
  const TutorialHost({super.key, required this.section, required this.child});
  final AppSection section;
  final Widget child;
  @override
  ConsumerState<TutorialHost> createState() => _TutorialHostState();
}

class _TutorialHostState extends ConsumerState<TutorialHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowTutorial(ref, context, widget.section);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/onboarding/screen_tutorial_test.dart`
Expected: PASS (registry + TutorialHost tests). (Verify `AppTheme.edge`/`panel`/`cyan`/`violet`/`ink`/`textPrimary`/`textSecondary` exist — they're used throughout `lib/ui`; if `edge` differs, use `AppTheme.textTertiary`.)

---

## Task 4: `IntroCarousel`

**Files:** Create `lib/ui/onboarding/intro_carousel.dart`; Test `test/onboarding/intro_carousel_test.dart`.

- [ ] **Step 1: Write the failing test**

```dart
// test/onboarding/intro_carousel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/ui/onboarding/intro_carousel.dart';

void main() {
  testWidgets('Skip fires onFinish; missing art shows fallback (no throw)',
      (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: IntroCarousel(onFinish: () => finished = true),
    ));
    await tester.pumpAndSettle();
    // First slide visible, no broken image / exception.
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(finished, true);
  });

  testWidgets('reaching the last slide shows Get Started which finishes',
      (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: IntroCarousel(onFinish: () => finished = true),
    ));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Get Started'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(finished, true);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/onboarding/intro_carousel_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/ui/onboarding/intro_carousel.dart
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

typedef _Slide = ({String asset, String title, String subtitle});

const List<_Slide> _slides = [
  (asset: 'assets/onboarding/intro_01.png', title: 'Spot the wave early',
   subtitle: "VibeRadar scans the world's charts so you play tomorrow's hits tonight."),
  (asset: 'assets/onboarding/intro_02.png', title: 'Build the perfect set',
   subtitle: 'AI-assisted, harmonically mixed, ready to export.'),
  (asset: 'assets/onboarding/intro_03.png', title: 'Made for DJs',
   subtitle: 'Trends, community and your crates — anywhere you are.'),
];

class IntroCarousel extends StatefulWidget {
  const IntroCarousel({super.key, required this.onFinish});
  final VoidCallback onFinish;
  @override
  State<IntroCarousel> createState() => _IntroCarouselState();
}

class _IntroCarouselState extends State<IntroCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page >= _slides.length - 1) {
      widget.onFinish();
    } else {
      _controller.nextPage(
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: _slides.length,
            itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
          ),
          Positioned(
            top: 0, right: 0,
            child: SafeArea(
              child: TextButton(
                onPressed: widget.onFinish,
                child: const Text('Skip',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ),
          ),
          Positioned(
            left: 24, right: 24, bottom: 28,
            child: SafeArea(
              child: Row(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < _slides.length; i++)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          width: i == _page ? 22 : 7, height: 7,
                          decoration: BoxDecoration(
                            color: i == _page ? AppTheme.cyan : AppTheme.edge,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.cyan,
                      foregroundColor: AppTheme.ink,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _next,
                    child: Text(last ? 'Get Started' : 'Next',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          slide.asset,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight, end: Alignment.bottomLeft,
                colors: [AppTheme.violet, AppTheme.ink],
              ),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
              stops: [0.45, 1.0],
            ),
          ),
        ),
        Positioned(
          left: 24, right: 24, bottom: 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(slide.title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900,
                      height: 1.1)),
              const SizedBox(height: 12),
              Text(slide.subtitle,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 15, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/onboarding/intro_carousel_test.dart`
Expected: PASS (2 tests).

---

## Task 5: Gemini generator + generate art + register assets

**Files:** Create `scripts/gen_onboarding_gemini.js`; generate into `assets/onboarding/`; Modify `pubspec.yaml`.

- [ ] **Step 1: Write the script** `scripts/gen_onboarding_gemini.js`

```js
// scripts/gen_onboarding_gemini.js
// VibeRadar onboarding art via Gemini (gplus pattern). Writes PNGs to
// assets/onboarding/ and downscales with macOS `sips`.
//   GEMINI_API_KEY=<gplus key> node scripts/gen_onboarding_gemini.js
const https = require("https");
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const API_KEY = process.env.GEMINI_API_KEY;
const MODEL = "gemini-3-pro-image-preview";
const OUT = path.join(__dirname, "..", "assets", "onboarding");

const CYAN = "#24C8DB", VIOLET = "#8B5CF6", INK = "#06070B";
const BRAND = `Electric cyan ${CYAN} to violet ${VIOLET} gradient with a soft neon glow on a deep near-black ${INK} background. A subtle radar-pulse (concentric arcs) fused with an audio-waveform motif. Premium, cinematic, ultra-HD, slight grain. NO text, NO letters, NO logos. Leave the TOP THIRD darker/cleaner for overlay text.`;

const TARGETS = [
  { file: "intro_01.png", prompt: `Square 1024x1024 hero for a DJ trend-intelligence app's welcome screen — a glowing radar sweep detecting a rising soundwave across a stylised world map of city lights. ${BRAND}` },
  { file: "intro_02.png", prompt: `Square 1024x1024 hero — an abstract DJ set being assembled: floating translucent track cards aligning into a harmonic curve, equalizer bars rising. ${BRAND}` },
  { file: "intro_03.png", prompt: `Square 1024x1024 hero — a vibrant DJ community: abstract connected nodes/avatars pulsing around a central radar, energy flowing between them. ${BRAND}` },
  { file: "screen_home.png", prompt: `Square 1024x1024 abstract hero for a "Dashboard" screen — floating glassy metric tiles and a trend sparkline over a radar grid. ${BRAND}` },
  { file: "screen_trending.png", prompt: `Square 1024x1024 abstract hero for a "Trending" screen — a leaderboard of glowing track bars rising like a chart, radar sweep highlighting the top one. ${BRAND}` },
  { file: "screen_search.png", prompt: `Square 1024x1024 abstract hero for a "Search" screen — a luminous magnifier over a constellation of track/artist nodes. ${BRAND}` },
  { file: "screen_aiCopilot.png", prompt: `Square 1024x1024 abstract hero for an "AI Set Builder" screen — a glowing AI orb weaving scattered tracks into an ordered setlist ribbon. ${BRAND}` },
  { file: "screen_setlists.png", prompt: `Square 1024x1024 abstract hero for a "Crates / Setlists" screen — a stack of glassy track cards in a crate, a sync arc linking phone and laptop silhouettes. ${BRAND}` },
  { file: "screen_community.png", prompt: `Square 1024x1024 abstract hero for a "Community" screen — interconnected DJ avatar nodes sharing glowing mix waveforms. ${BRAND}` },
  { file: "screen_forYou.png", prompt: `Square 1024x1024 abstract hero for a "For You" personalised feed — a tailored stream of glowing track cards flowing toward a single listener silhouette. ${BRAND}` },
  { file: "screen_artists.png", prompt: `Square 1024x1024 abstract hero for an "Artists" screen — rising artist portraits-as-silhouettes with momentum arrows and a radar ring. ${BRAND}` },
  { file: "screen_setBuilder.png", prompt: `Square 1024x1024 abstract hero for a "Set Builder" screen — a harmonic mixing wheel (Camelot-like) with BPM arcs linking tracks. ${BRAND}` },
  { file: "screen_library.png", prompt: `Square 1024x1024 abstract hero for a "My Library" screen — neatly shelved glowing track tiles and a watchlist star. ${BRAND}` },
  { file: "screen_exports.png", prompt: `Square 1024x1024 abstract hero for an "Exports" screen — a track crate transforming into export file chips flowing into DJ-software panels. ${BRAND}` },
];

function gen(prompt) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { responseModalities: ["TEXT", "IMAGE"] },
    });
    const req = https.request({
      hostname: "generativelanguage.googleapis.com",
      path: `/v1beta/models/${MODEL}:generateContent?key=${API_KEY}`,
      method: "POST",
      headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) },
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const raw = Buffer.concat(chunks).toString();
        try {
          const json = JSON.parse(raw);
          if (json.error) return reject(new Error(JSON.stringify(json.error).slice(0, 300)));
          const parts = json.candidates?.[0]?.content?.parts ?? [];
          const img = parts.find((p) => p.inlineData?.mimeType?.startsWith("image/"));
          if (!img) return reject(new Error(`No image: ${raw.slice(0, 200)}`));
          resolve(Buffer.from(img.inlineData.data, "base64"));
        } catch (e) { reject(e); }
      });
    });
    req.on("error", reject);
    req.write(body); req.end();
  });
}

(async () => {
  if (!API_KEY) { console.error("Set GEMINI_API_KEY"); process.exit(2); }
  fs.mkdirSync(OUT, { recursive: true });
  let ok = 0;
  for (const t of TARGETS) {
    process.stdout.write(`  ${t.file.padEnd(24)}`);
    try {
      const buf = await gen(t.prompt);
      const out = path.join(OUT, t.file);
      fs.writeFileSync(out, buf);
      try { execFileSync("sips", ["-Z", "800", out], { stdio: "ignore" }); } catch (_) {}
      const kb = (fs.statSync(out).size / 1024).toFixed(0);
      console.log(` ✓ ${kb}KB`); ok++;
    } catch (e) { console.error(` ✗ ${e.message.slice(0, 160)}`); }
    await new Promise((r) => setTimeout(r, 2000));
  }
  console.log(`\n${ok}/${TARGETS.length} → ${OUT}`);
  process.exit(ok > 0 ? 0 : 3);
})();
```

- [ ] **Step 2: Generate the art**

Run: `GEMINI_API_KEY="$(node -e "console.log(require('fs').readFileSync('/Users/angelonartey/Desktop/gplus-app/scripts/gen_gplus_dashboard_imagery.js','utf8').match(/API_KEY = \"([^\"]+)\"/)[1])")" node scripts/gen_onboarding_gemini.js`
Expected: 14 lines each ending `✓ <size>KB`, then `14/14`. (If the key/model rejects, report the error before continuing — the app still works via fallbacks, but the point is the real art.)

- [ ] **Step 3: Register assets** in `pubspec.yaml`

Under the existing `flutter:` → `assets:` list, add:
```yaml
    - assets/onboarding/
```
Run: `flutter pub get`
Expected: success.

- [ ] **Step 4: Verify**

Run: `ls assets/onboarding | wc -l` → Expected: `14`.
Run: `flutter analyze lib/ui/onboarding` → Expected: clean.

---

## Task 6: Wire the intro phase into `auth_gate.dart`

**Files:** Modify `lib/ui/auth/auth_gate.dart`.

- [ ] **Step 1: Add the `intro` phase enum + import**

Add import: `import '../onboarding/intro_carousel.dart';` and `import '../../providers/onboarding_state.dart';`
Change `enum _AuthPhase { splash, onboarding, login }` → `enum _AuthPhase { splash, intro, onboarding, login }`.

- [ ] **Step 2: Track intro-seen state**

Add field: `bool _introSeen = false;`
In `_checkOnboardingStatus()`, after reading `completed`, also read intro:
```dart
final introSeen = await ref.read(onboardingStateProvider).isIntroSeen();
```
and set `_introSeen = introSeen;` inside the `setState`.

- [ ] **Step 3: Route splash → intro → onboarding/login**

Replace `_finishSplash`:
```dart
void _finishSplash() {
  setState(() {
    _phase = !_introSeen
        ? _AuthPhase.intro
        : (_onboardingCompleted ? _AuthPhase.login : _AuthPhase.onboarding);
  });
}

Future<void> _finishIntro() async {
  await ref.read(onboardingStateProvider).markIntroSeen();
  if (!mounted) return;
  setState(() {
    _introSeen = true;
    _phase = _onboardingCompleted ? _AuthPhase.login : _AuthPhase.onboarding;
  });
}
```

- [ ] **Step 4: Render the intro in `build`'s switch**

In the `switch (_phase)` add, before `onboarding`:
```dart
      case _AuthPhase.intro:
        return IntroCarousel(onFinish: _finishIntro);
```

- [ ] **Step 5: Verify**

Run: `flutter analyze lib/ui/auth/auth_gate.dart` → Expected: clean.
Run: `flutter test test/mobile/adaptive_shell_test.dart` (smoke that auth flow still builds) → Expected: PASS.

---

## Task 7: Wire `TutorialHost` into the mobile shell

**Files:** Modify `lib/ui/mobile/mobile_shell.dart`.

- [ ] **Step 1: Import**

Add: `import '../../models/app_section.dart';` and `import '../onboarding/screen_tutorial.dart';` (if `app_section` already imported, skip).

- [ ] **Step 2: Wrap the four covered tabs** — replace `_tabFor`:

```dart
  Widget _tabFor(int index) {
    return switch (index) {
      0 => TutorialHost(
            section: AppSection.home,
            child: _HomeTab(onOpenSearch: () => _selectTab(2))),
      1 => const TutorialHost(
            section: AppSection.trending,
            child: _MobilePage(title: 'Trending', child: TrendingScreen())),
      2 => const TutorialHost(
            section: AppSection.search,
            child: _MobilePage(title: 'Search', child: SearchTab())),
      3 => const TutorialHost(section: AppSection.aiCopilot, child: AiTab()),
      4 => const _MoreTab(),
      _ => const SizedBox.shrink(),
    };
  }
```

- [ ] **Step 3: Wrap the two pushed More-menu screens** (Setlists ~line 325, Community ~line 337):

```dart
        // Setlists
        action: (ctx) => _push(ctx,
            const TutorialHost(section: AppSection.setlists, child: SetlistsTab())),
```
```dart
        // Community
        action: (ctx) => _push(ctx, const TutorialHost(
            section: AppSection.community,
            child: _MobilePage(title: 'Community', child: CommunityScreen()))),
```

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/ui/mobile/mobile_shell.dart` → Expected: clean.
Run: `flutter test test/mobile/` → Expected: PASS (no regressions).

---

## Task 8: Wire `TutorialHost` into the desktop shell

**Files:** Modify `lib/ui/shell/vibe_shell.dart`.

- [ ] **Step 1: Import** `import '../onboarding/screen_tutorial.dart';` (AppSection already imported).

- [ ] **Step 2: Wrap `mainPanel`** — find where `mainPanel` is defined (≈ line 180, a Widget value passed `workspace:` etc.) and wrap it:

```dart
    final mainPanel = TutorialHost(
      key: ValueKey(workspace.section),
      section: workspace.section,
      child: <EXISTING mainPanel widget expression unchanged>,
    );
```
(Keep the existing widget as the `child:`. The `ValueKey(section)` remounts the host on section change so the tutorial fires once per first-visited section. Uncovered sections are no-ops via the registry.)

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/ui/shell/vibe_shell.dart` → Expected: clean.

---

## Task 9: Full verification + run

- [ ] **Step 1:** `flutter analyze` → Expected: "No issues found!".
- [ ] **Step 2:** `flutter test` → Expected: all pass (prior 380 + new onboarding tests).
- [ ] **Step 3: Run the app** (`flutter run -d macos`): after splash → **intro carousel** (3 slides, Get Started) → onboarding/login; then first visit to Home/Trending/etc. shows the **tutorial bottom sheet** with art; second visit does not. Confirm no broken images. Terminate when confirmed.

---

## Self-review
- **Spec coverage:** OnboardingState (T1), registry (T2), TutorialHost/sheet (T3), IntroCarousel (T4), Gemini script + generate + assets (T5), auth_gate intro before sign-in (T6), mobile 6 screens (T7), desktop 10 via keyed mainPanel (T8), verify+run (T9). All spec sections mapped.
- **Types consistent:** `OnboardingState`, `onboardingStateProvider`, `TutorialEntry`, `tutorialRegistry`, `maybeShowTutorial`, `showScreenTutorial`, `TutorialHost`, `IntroCarousel(onFinish:)` used identically across tasks.
- **Risks flagged inline:** confirm `AppTheme.edge` exists (T3); Gemini key/model rejection path (T5 Step 2); mobile tab→section mapping handled by wrapping in `_tabFor` (T7).

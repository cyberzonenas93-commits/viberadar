// scripts/gen_onboarding_gemini.js
// VibeRadar onboarding art via Gemini (gplus pattern). Writes PNGs to
// assets/onboarding/ and downscales with macOS `sips`.
//   GEMINI_API_KEY=<gplus key> node scripts/gen_onboarding_gemini.js
const https = require("https");
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

// Two auth paths (Vertex AI preferred — uses your gcloud creds like
// gen_logo_gemini.js; falls back to a Gemini Developer API key):
//   GCLOUD_TOKEN=$(gcloud auth print-access-token) GCLOUD_PROJECT=gplus-admin node scripts/gen_onboarding_gemini.js
//   GEMINI_API_KEY=<key> node scripts/gen_onboarding_gemini.js
const TOKEN = process.env.GCLOUD_TOKEN;
const PROJECT = process.env.GCLOUD_PROJECT || "gplus-admin";
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
    const useVertex = !!TOKEN;
    const body = JSON.stringify(
      useVertex
        ? {
            contents: [{ role: "user", parts: [{ text: prompt }] }],
            generationConfig: {
              responseModalities: ["IMAGE"],
              imageConfig: { aspectRatio: "1:1" },
            },
          }
        : {
            contents: [{ role: "user", parts: [{ text: prompt }] }],
            generationConfig: { responseModalities: ["TEXT", "IMAGE"] },
          },
    );
    const options = useVertex
      ? {
          hostname: "aiplatform.googleapis.com",
          path: `/v1/projects/${PROJECT}/locations/global/publishers/google/models/${MODEL}:generateContent`,
          method: "POST",
          headers: {
            Authorization: `Bearer ${TOKEN}`,
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(body),
          },
        }
      : {
          hostname: "generativelanguage.googleapis.com",
          path: `/v1beta/models/${MODEL}:generateContent?key=${API_KEY}`,
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(body),
          },
        };
    const req = https.request(options, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const raw = Buffer.concat(chunks).toString();
        try {
          const json = JSON.parse(raw);
          if (json.error) return reject(new Error(JSON.stringify(json.error).slice(0, 300)));
          const parts = json.candidates?.[0]?.content?.parts ?? [];
          const img = parts.find((p) => (p.inlineData || p.inline_data)?.data);
          if (!img) return reject(new Error(`No image: ${raw.slice(0, 200)}`));
          resolve(Buffer.from((img.inlineData || img.inline_data).data, "base64"));
        } catch (e) { reject(e); }
      });
    });
    req.on("error", reject);
    req.write(body); req.end();
  });
}

(async () => {
  if (!TOKEN && !API_KEY) { console.error("Set GCLOUD_TOKEN (preferred) or GEMINI_API_KEY"); process.exit(2); }
  console.log(TOKEN ? `Vertex AI (project ${PROJECT})` : "Gemini Developer API");
  fs.mkdirSync(OUT, { recursive: true });
  let ok = 0;
  for (const t of TARGETS) {
    process.stdout.write(`  ${t.file.padEnd(24)}`);
    const out = path.join(OUT, t.file);
    if (fs.existsSync(out) && fs.statSync(out).size > 1000) {
      console.log(" skip (exists)"); ok++; continue;
    }
    try {
      const buf = await gen(t.prompt);
      fs.writeFileSync(out, buf);
      try { execFileSync("sips", ["-Z", "800", out], { stdio: "ignore" }); } catch (_) {}
      const kb = (fs.statSync(out).size / 1024).toFixed(0);
      console.log(` OK ${kb}KB`); ok++;
    } catch (e) { console.error(` FAIL ${e.message.slice(0, 160)}`); }
    await new Promise((r) => setTimeout(r, 2000));
  }
  console.log(`\n${ok}/${TARGETS.length} -> ${OUT}`);
  process.exit(ok > 0 ? 0 : 3);
})();

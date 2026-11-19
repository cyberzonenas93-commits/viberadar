// scripts/gen_paywall_gemini.js
// VibeRadar Pro/paywall artwork via the Gplus Gemini image-generation pattern.
// Writes PNGs to assets/paywall/.
//
// Auth options:
//   GCLOUD_TOKEN=$(gcloud auth print-access-token) GCLOUD_PROJECT=gplus-admin node scripts/gen_paywall_gemini.js
//   GEMINI_API_KEY=<key> node scripts/gen_paywall_gemini.js
//
// If GEMINI_API_KEY is not set, this script also checks the gitignored .env in
// this repo and the Gplus repo at $GPLUS_REPO or ~/Desktop/gplus-app.

const https = require("https");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const GPLUS_REPO =
  process.env.GPLUS_REPO || path.join(os.homedir(), "Desktop", "gplus-app");
const OUT = path.join(ROOT, "assets", "paywall");

function loadEnv(file) {
  let raw = "";
  try {
    raw = fs.readFileSync(file, "utf8");
  } catch (_) {
    return;
  }
  for (const line of raw.split("\n")) {
    const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!match) continue;
    const key = match[1];
    if (process.env[key]) continue;
    let value = match[2].trim();
    const quoted =
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"));
    if (quoted) value = value.slice(1, -1);
    process.env[key] = value;
  }
}

loadEnv(path.join(ROOT, ".env"));
loadEnv(path.join(GPLUS_REPO, ".env"));

const TOKEN = process.env.GCLOUD_TOKEN;
const PROJECT = process.env.GCLOUD_PROJECT || "gplus-admin";
const MODEL = process.env.GEMINI_IMAGE_MODEL || "gemini-3-pro-image-preview";
const API_KEY = process.env.GEMINI_API_KEY;

const PALETTE =
  "VibeRadar palette: deep near-black #06070B, graphite panels, electric cyan #34D8D0, signal green #92F2B4, warm amber #FFCA5C, small magenta #FF6F8F accents. Avoid a one-note purple or blue look.";
const NO_TEXT =
  "No text, no letters, no numbers, no words, no logos, no watermarks, no readable UI labels.";
const QUALITY =
  "Photoreal premium app-store-quality commercial artwork, crisp focus, rich materials, subtle film grain, no clutter, no fake brand marks.";

const TARGETS = [
  {
    file: "pro_locked_hero.png",
    aspectRatio: "16:9",
    maxSize: "1400",
    prompt: `Wide 16:9 hero artwork for a premium DJ trend-intelligence subscription paywall.

Scene: a real DJ workstation at night, seen from a slightly elevated three-quarter angle: a Mac laptop, a phone, a compact DJ controller, vinyl sleeves, and headphones on a dark studio table. The laptop and phone show abstract live-music intelligence visuals only: radar arcs, clean waveform ribbons, regional momentum dots, and track cards with no readable writing. A small crowd and booth lights blur in the far background.

Composition: strong product signal, center-left workstation, upper third calm and dark enough for app UI overlay, clean negative space on the right for subscription controls. The entire canvas must feel like one continuous scene: smooth atmospheric falloff, no hard black rectangles, no split-screen blocks, no poster panels, no abrupt empty bars. ${PALETTE}

Lighting: cyan screen glow, signal-green radar highlights, warm amber edge light on equipment, very restrained magenta rim light.

${NO_TEXT} ${QUALITY}`,
  },
  {
    file: "pro_sheet_badge.png",
    aspectRatio: "1:1",
    maxSize: "1000",
    prompt: `Square 1:1 premium artwork for a VibeRadar Pro subscription sheet.

Scene: close-up tabletop still life: a matte graphite access token shaped like a rounded rectangle with subtle embossed concentric radar grooves and a small luminous sweep, a glowing radar projection over a vinyl record, headphones, and a phone showing abstract waveform/radar graphics with no readable writing. The access token is premium and detailed, not a blank card, and has no letters, logos, or words.

Composition: centered hero object, readable at small mobile sheet size, crisp premium materials, no crowded background. ${PALETTE}

Lighting: soft cyan and signal-green glow from the radar projection, amber specular highlights on vinyl grooves, near-black studio background.

${NO_TEXT} ${QUALITY}`,
  },
  {
    file: "pro_banner_live.png",
    aspectRatio: "16:9",
    maxSize: "1400",
    prompt: `Wide 16:9 artwork for a compact in-app upgrade banner in a DJ productivity app.

Scene: panoramic live music command surface: abstract radar rings, city momentum dots, DJ waveform strips, and tiny floating track-card shapes flowing from a phone to a laptop. Use believable glass UI panels but keep all panels free of text or letters. The image should crop well into a short horizontal banner.

Composition: brightest activity on the left and center, darker clean negative space on the right, strong diagonal motion suggesting live data unlocking. ${PALETTE}

Lighting: cyan scan line, signal-green live-data pulses, amber accents, dark graphite base with depth.

${NO_TEXT} ${QUALITY}`,
  },
];

function requestGemini(prompt, aspectRatio) {
  const useVertex = Boolean(TOKEN);
  const body = JSON.stringify({
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      responseModalities: useVertex ? ["IMAGE"] : ["TEXT", "IMAGE"],
      imageConfig: { aspectRatio },
    },
  });
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

  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        const raw = Buffer.concat(chunks).toString();
        let json = null;
        try {
          json = JSON.parse(raw);
        } catch (error) {
          reject(error);
          return;
        }
        if (json.error) {
          reject(new Error(JSON.stringify(json.error).slice(0, 360)));
          return;
        }
        const parts = json.candidates?.[0]?.content?.parts ?? [];
        const image = parts.find((part) =>
          (part.inlineData || part.inline_data)?.mimeType?.startsWith("image/")
        );
        const data = (image?.inlineData || image?.inline_data)?.data;
        if (!data) {
          reject(new Error(`No image in Gemini response: ${raw.slice(0, 240)}`));
          return;
        }
        resolve(Buffer.from(data, "base64"));
      });
    });
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

function optimizePng(file, maxSize) {
  try {
    execFileSync("sips", ["-Z", maxSize, file], { stdio: "ignore" });
  } catch (_) {}
  try {
    execFileSync(
      "pngquant",
      ["--force", "--skip-if-larger", "--strip", "--ext", ".png", file],
      { stdio: "ignore" }
    );
  } catch (_) {}
}

async function main() {
  if (!TOKEN && !API_KEY) {
    console.error(
      "Set GCLOUD_TOKEN or GEMINI_API_KEY. This script also checks .env and $GPLUS_REPO/.env."
    );
    process.exit(2);
  }
  fs.mkdirSync(OUT, { recursive: true });
  const arg = (process.argv[2] || "all").toLowerCase();
  const targets =
    arg === "all"
      ? TARGETS
      : TARGETS.filter((target) => target.file.toLowerCase().includes(arg));
  if (!targets.length) {
    console.error(`No paywall art target matched "${arg}".`);
    process.exit(2);
  }

  console.log(
    TOKEN
      ? `Vertex Gemini (${MODEL}, project ${PROJECT})`
      : `Gemini Developer API (${MODEL})`
  );

  let ok = 0;
  for (const target of targets) {
    process.stdout.write(`  ${target.file.padEnd(22)}`);
    try {
      const out = path.join(OUT, target.file);
      const image = await requestGemini(target.prompt, target.aspectRatio);
      fs.writeFileSync(out, image);
      optimizePng(out, target.maxSize);
      const kb = (fs.statSync(out).size / 1024).toFixed(0);
      console.log(`OK ${kb}KB`);
      ok += 1;
    } catch (error) {
      console.error(`FAIL ${String(error.message || error).slice(0, 220)}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  console.log(`\n${ok}/${targets.length} -> ${path.relative(ROOT, OUT)}`);
  process.exit(ok === targets.length ? 0 : 3);
}

main();

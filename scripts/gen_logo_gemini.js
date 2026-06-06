// scripts/gen_logo_gemini.js
// VibeRadar logo concepts via Vertex AI Gemini image models.
//   GCLOUD_TOKEN=$(gcloud auth print-access-token) GCLOUD_PROJECT=gplus-admin \
//     node scripts/gen_logo_gemini.js [all|<concept>]
// Saves PNG concepts to outputs/logo/ for review.

const https = require("https");
const fs = require("fs");
const path = require("path");

const TOKEN = process.env.GCLOUD_TOKEN;
const PROJECT = process.env.GCLOUD_PROJECT || "gplus-admin";
const LOCATION = "global";
const PRIMARY_MODEL = process.env.MODEL || "gemini-3-pro-image-preview";
const FALLBACK_MODEL = "gemini-2.5-flash-image";
const HOST = "aiplatform.googleapis.com";
const OUT = path.join(__dirname, "..", "outputs", "logo");

const BASE =
  "Premium mobile app icon for 'VibeRadar', a high-end DJ trend-intelligence app. " +
  "Rounded-square app-icon format, a single centered symbol with generous negative space. " +
  "Absolutely NO text, NO letters, NO words. " +
  "Deep near-black background (#06070B) with subtle radial depth. " +
  "Electric cyan (#24C8DB) to violet (#8B5CF6) gradient with a soft luminous neon glow. " +
  "Sleek, modern, iconic, Apple-design-award quality, crisp clean geometry, " +
  "subtle 3D depth and a glossy finish, studio lighting, perfectly centered. ";

const CONCEPTS = {
  radarwave:
    BASE +
    "The symbol fuses a RADAR PULSE (concentric arcs sweeping outward from a single point) " +
    "with an AUDIO WAVEFORM (clean equalizer bars) into one elegant unified mark — sound radiating like radar.",
  monogram:
    BASE +
    "The symbol is a bold geometric mark built from rising soundwave / equalizer bars that " +
    "together suggest a sharp upward 'V' shape, with one luminous radar-pulse arc curving through it.",
  pulse:
    BASE +
    "The symbol is a single minimal glowing audio waveform line that bends into a circular radar " +
    "sweep — one continuous elegant stroke, a pulse of sound detected on radar.",
  orb:
    BASE +
    "The symbol is a glowing futuristic orb/sphere with a luminous equalizer waveform wrapping " +
    "across its equator and faint concentric radar rings around it, premium and high-tech.",
};

function gen(prompt, model) {
  const body = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: { responseModalities: ["IMAGE"], imageConfig: { aspectRatio: "1:1" } },
  };
  const data = JSON.stringify(body);
  const p = `/v1/projects/${PROJECT}/locations/${LOCATION}/publishers/google/models/${model}:generateContent`;
  return new Promise((resolve, reject) => {
    const r = https.request(
      {
        hostname: HOST, path: p, method: "POST",
        headers: {
          Authorization: `Bearer ${TOKEN}`,
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(data),
        },
      },
      (res) => {
        const c = [];
        res.on("data", (x) => c.push(x));
        res.on("end", () => {
          let j = null;
          const raw = Buffer.concat(c).toString();
          try { j = JSON.parse(raw); } catch {}
          resolve({ status: res.statusCode, json: j, raw });
        });
      },
    );
    r.on("error", reject);
    r.write(data);
    r.end();
  });
}

function extractImage(j) {
  const parts = j && j.candidates && j.candidates[0] && j.candidates[0].content && j.candidates[0].content.parts;
  if (!parts) return null;
  for (const part of parts) {
    const d = part.inlineData || part.inline_data;
    if (d && d.data) return d.data;
  }
  return null;
}

async function one(name, prompt) {
  for (const model of [PRIMARY_MODEL, FALLBACK_MODEL]) {
    const res = await gen(prompt, model);
    if (res.status === 200) {
      const b64 = extractImage(res.json);
      if (b64) {
        const out = path.join(OUT, `${name}.png`);
        fs.writeFileSync(out, Buffer.from(b64, "base64"));
        console.log(`[${name}] OK via ${model} -> ${out}`);
        return true;
      }
      console.error(`[${name}] ${model}: 200 but no image: ${(res.raw || "").slice(0, 200)}`);
    } else {
      console.error(`[${name}] ${model}: HTTP ${res.status}: ${(res.raw || "").slice(0, 200)}`);
    }
  }
  return false;
}

async function main() {
  if (!TOKEN) { console.error("no GCLOUD_TOKEN"); process.exit(2); }
  fs.mkdirSync(OUT, { recursive: true });
  const arg = (process.argv[2] || "all").toLowerCase();
  const names = arg === "all" ? Object.keys(CONCEPTS) : [arg];
  let ok = 0;
  for (const n of names) {
    if (!CONCEPTS[n]) { console.error("unknown concept", n); continue; }
    if (await one(n, CONCEPTS[n])) ok++;
  }
  console.log(`done: ${ok}/${names.length}`);
  process.exit(ok > 0 ? 0 : 3);
}

main();

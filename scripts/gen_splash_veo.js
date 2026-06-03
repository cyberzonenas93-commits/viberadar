// Generates VibeRadar's animated splash with Veo 3.1 (image-to-video) via
// Vertex AI on the gplus-admin project — animates the app icon (the sound-bars
// equalizer) into a short looping motion asset.
//
//   node scripts/gen_splash_veo.js
//
// Output: assets/splash/splash_motion.mp4
//
// Mirrors the polling/save logic of gplus-app/scripts/gen_market_splash_veo.js,
// but adds an input image (image-to-video) so the actual icon is animated.

const fs = require("fs");
const path = require("path");
const https = require("https");
const { execSync } = require("child_process");

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "gplus-admin";
const LOCATION = process.env.VEO_LOCATION || "us-central1";
const MODEL = process.env.VEO_MODEL || "veo-3.1-generate-001";
const ICON = path.join(__dirname, "..", "assets", "icon", "app_icon.png");
const OUT = path.join(__dirname, "..", "assets", "splash", "splash_motion.mp4");

// White bars on PURE BLACK so the splash can screen-blend the black to fully
// transparent, leaving only the animated bars over the app's brand gradient.
const PROMPT = `Five vertical white rounded-cap bars in a row, centered, the middle bar tallest and the outer bars shorter, on a pure solid black background (#000000 only — no gradient, no other colors anywhere). The bars smoothly and rhythmically rise and fall like a music equalizer reacting to a gentle beat. Flat 2D minimal UI style, crisp clean pure-white bars, pure black everywhere else, seamless loop, smooth fluid motion, no camera movement, no text, no numbers, no logos, no people.`;

function getToken() {
  for (const bin of ["gcloud", "/opt/homebrew/bin/gcloud", "/usr/local/bin/gcloud"]) {
    try {
      return execSync(`${bin} auth print-access-token`, { encoding: "utf8" }).trim();
    } catch (_) {
      // try next path
    }
  }
  throw new Error("could not run gcloud auth print-access-token");
}

function httpJson(method, url, token, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const data = body ? JSON.stringify(body) : null;
    const req = https.request(
      {
        hostname: u.hostname,
        path: u.pathname + u.search,
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          ...(data ? { "Content-Length": Buffer.byteLength(data) } : {}),
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const raw = Buffer.concat(chunks);
          try {
            resolve({ status: res.statusCode, json: JSON.parse(raw.toString()), raw });
          } catch (_) {
            resolve({ status: res.statusCode, json: null, raw });
          }
        });
      },
    );
    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });

  let token = getToken();
  const base = `https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/${LOCATION}/publishers/google/models/${MODEL}`;

  console.log(`[splash-veo] starting text-to-video (${MODEL}, 9:16, 4s, project=${PROJECT})`);
  const start = await httpJson("POST", `${base}:predictLongRunning`, token, {
    instances: [{ prompt: PROMPT }],
    parameters: {
      aspectRatio: "9:16",
      durationSeconds: 4,
      personGeneration: "dont_allow",
      sampleCount: 1,
    },
  });
  if (start.status !== 200 || !start.json?.name) {
    throw new Error(`start failed (${start.status}): ${start.raw.toString().slice(0, 800)}`);
  }

  const operationName = start.json.name;
  const fetchUrl = `${base}:fetchPredictOperation`;
  console.log(`[splash-veo] op: ${operationName}`);

  let response = null;
  for (let attempt = 1; attempt <= 70; attempt += 1) {
    await sleep(12000);
    if (attempt % 4 === 0) token = getToken();
    const poll = await httpJson("POST", fetchUrl, token, { operationName });
    if (poll.status !== 200) {
      console.log(`[splash-veo] poll ${attempt} HTTP ${poll.status}: ${poll.raw.toString().slice(0, 200)}`);
      continue;
    }
    if (poll.json?.done) {
      response = poll.json;
      break;
    }
    console.log(`[splash-veo] poll ${attempt}... ${poll.json?.metadata?.progressPercent ?? "?"}%`);
  }

  if (!response) throw new Error("timed out waiting for Veo");
  if (response.error) throw new Error(JSON.stringify(response.error));

  const videos =
    response.response?.videos ||
    response.response?.generatedSamples ||
    response.response?.generateVideoResponse?.generatedSamples ||
    [];
  const sample = Array.isArray(videos) ? videos[0] : videos;
  const b64 = sample?.bytesBase64Encoded || sample?.video?.bytesBase64Encoded;
  if (!b64) {
    throw new Error(`no video bytes in response: ${JSON.stringify(response).slice(0, 900)}`);
  }

  const buffer = Buffer.from(b64, "base64");
  fs.writeFileSync(OUT, buffer);
  console.log(`\n[splash-veo] ✔ saved ${path.relative(path.join(__dirname, ".."), OUT)} (${(buffer.length / 1024 / 1024).toFixed(1)}MB)`);
}

main().catch((e) => {
  console.error("FAILED:", e.message || e);
  process.exit(1);
});

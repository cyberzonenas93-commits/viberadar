// Generates VibeRadar's animated splash with Veo 3.1 via Vertex AI on the
// gplus-admin project — a short looping pulse asset for the launch splash.
//
//   node scripts/gen_splash_veo.js
//
// Outputs:
//   assets/splash/splash_motion.mp4
//   assets/splash/frames/f01.png ... f48.png
//
// Mirrors the Vertex polling/save logic of:
//   /Users/angelonartey/Desktop/gplus-app/scripts/gen_market_splash_veo.js

const fs = require("fs");
const path = require("path");
const https = require("https");
const { execFileSync, execSync } = require("child_process");

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "gplus-admin";
const LOCATION = process.env.VEO_LOCATION || "us-central1";
const MODEL = process.env.VEO_MODEL || "veo-3.1-generate-001";
const OUT = path.join(__dirname, "..", "assets", "splash", "splash_motion.mp4");
const FRAMES_DIR = path.join(__dirname, "..", "assets", "splash", "frames");
const FRAME_COUNT = 48;
const FRAME_RATE = 12;

const PROMPT = `Vertical 9:16 premium mobile app launch splash for VibeRadar.
Deep near-black ink background (#07090D) with a centered neon radar-wave app mark:
cyan concentric radar arcs on the left, a small center node, and a violet heartbeat
waveform extending to the right. The mark stays centered and clean while it gently
pulses like music through a radar: two calm beat pulses over four seconds, scale
blooming from 96% to 104%, cyan and violet glow brightening on each beat, then
settling. Faint circular radar ripples expand outward from the center node and fade.
Flat premium 2D UI motion, crisp edges, no camera movement, no rotation, no extra
objects, no readable text, no letters, no numbers, no people. Loop-safe final frame
matches the first frame.`;

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

function ffmpegBin() {
  for (const bin of ["ffmpeg", "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]) {
    try {
      execFileSync(bin, ["-version"], { stdio: "ignore" });
      return bin;
    } catch (_) {
      // try next path
    }
  }
  throw new Error("ffmpeg not found");
}

function extractFrames() {
  const ffmpeg = ffmpegBin();
  const tmp = path.join(FRAMES_DIR, `.tmp-${Date.now()}`);
  fs.mkdirSync(tmp, { recursive: true });

  execFileSync(
    ffmpeg,
    [
      "-y",
      "-i",
      OUT,
      "-vf",
      `fps=${FRAME_RATE},scale=360:640:force_original_aspect_ratio=increase,crop=360:640,format=rgba`,
      "-frames:v",
      String(FRAME_COUNT),
      path.join(tmp, "f%02d.png"),
    ],
    { stdio: "pipe" },
  );

  const rendered = fs
    .readdirSync(tmp)
    .filter((name) => /^f\d{2}\.png$/.test(name))
    .sort();
  if (rendered.length !== FRAME_COUNT) {
    throw new Error(`expected ${FRAME_COUNT} frames, got ${rendered.length}`);
  }

  for (const name of fs.readdirSync(FRAMES_DIR)) {
    if (/^f\d{2}\.png$/.test(name)) fs.rmSync(path.join(FRAMES_DIR, name));
  }
  for (const name of rendered) {
    fs.renameSync(path.join(tmp, name), path.join(FRAMES_DIR, name));
  }
  fs.rmSync(tmp, { recursive: true, force: true });
}

async function main() {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.mkdirSync(FRAMES_DIR, { recursive: true });

  let token = getToken();
  const base = `https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/${LOCATION}/publishers/google/models/${MODEL}`;

  console.log(`[splash-veo] starting pulse video (${MODEL}, 9:16, 4s, project=${PROJECT})`);
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
  console.log(`\n[splash-veo] saved ${path.relative(path.join(__dirname, ".."), OUT)} (${(buffer.length / 1024 / 1024).toFixed(1)}MB)`);

  extractFrames();
  console.log(`[splash-veo] ✔ extracted ${FRAME_COUNT} frames to ${path.relative(path.join(__dirname, ".."), FRAMES_DIR)}`);
}

main().catch((e) => {
  console.error("FAILED:", e.message || e);
  process.exit(1);
});

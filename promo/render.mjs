// Renders the promo to out/brimtune-promo.mp4: every frame is drawn by window.renderAt(t) in headless
// Chrome, four sub-frames per frame are averaged for motion blur (180° shutter), then the audio is muxed.
//   node render.mjs                 full render (needs out/audio.wav: node audio.mjs)
//   node render.mjs --stills 1 2.4  PNG stills of those moments into out/stills/
//   node render.mjs --from 5 --to 7 render only part (out/part.mp4), for checking a stretch
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";
import ffmpegPath from "ffmpeg-static";
import { FPS, DURATION } from "./cues.js";

const dir = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(dir, "out");
fs.mkdirSync(out, { recursive: true });
const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); return i < 0 ? def : args[i + 1]; };
const SUB = Number(opt("--sub", 4));
const WORKERS = Number(opt("--workers", 5));
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".wav": "audio/wav", ".png": "image/png" };
const server = http.createServer((req, res) => {
  const file = path.join(dir, decodeURIComponent(new URL(req.url, "http://x").pathname));
  if (!file.startsWith(dir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404).end(); return; }
  res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const url = `http://127.0.0.1:${server.address().port}/index.html`;

const browser = await puppeteer.launch({
  executablePath: CHROME, headless: true,
  args: ["--hide-scrollbars", "--force-color-profile=srgb", "--disable-lcd-text", "--font-render-hinting=none"],
  defaultViewport: { width: 1920, height: 1080, deviceScaleFactor: 1 },
});
async function openPage() {
  const page = await browser.newPage();
  page.on("pageerror", (e) => console.error("page error:", e.message));
  page.on("console", (m) => m.type() === "error" && console.error("console:", m.text()));
  await page.goto(url, { waitUntil: "networkidle0" });
  await page.waitForFunction("window.ready === true", { timeout: 60000 });
  return page;
}
const shot = async (page, t) => {
  await page.evaluate((x) => window.renderAt(x), t);
  return page.screenshot({ type: "png", optimizeForSpeed: true });
};
// Sub-frame k of frame i sits inside the open half of the frame, centred on the frame's time.
const subTime = (i, k) => Math.max(0, i / FPS + ((k + 0.5) / SUB - 0.5) * (0.5 / FPS));

function encoder(file, fps, extra = []) {
  const ff = spawn(ffmpegPath, ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(fps * SUB), "-i", "-",
    ...(SUB > 1 ? ["-vf", `tmix=frames=${SUB},select='eq(mod(n\\,${SUB})\\,${SUB - 1})',setpts=N/${fps}/TB`] : []),
    "-r", String(fps), ...extra, file], { stdio: ["pipe", "inherit", "inherit"] });
  const done = new Promise((r, j) => ff.on("close", (c) => (c ? j(new Error(`ffmpeg ${c}`)) : r())));
  return { write: (buf) => new Promise((r) => (ff.stdin.write(buf) ? r() : ff.stdin.once("drain", r))), end: () => { ff.stdin.end(); return done; } };
}

if (args.includes("--stills")) {
  const times = args.slice(args.indexOf("--stills") + 1).filter((a) => !a.startsWith("--")).map(Number);
  fs.mkdirSync(path.join(out, "stills"), { recursive: true });
  const page = await openPage();
  for (const t of times) {
    const buf = await shot(page, t);
    fs.writeFileSync(path.join(out, "stills", `t${t.toFixed(2)}.png`), buf);
  }
  console.log(`stills → out/stills (${times.length})`);
} else {
  const from = Math.round(Number(opt("--from", 0)) * FPS);
  const to = Math.round(Number(opt("--to", DURATION)) * FPS);
  const frames = to - from;
  const chunk = Math.ceil(frames / WORKERS);
  const started = Date.now();
  let doneFrames = 0;
  const segs = [];
  await Promise.all(Array.from({ length: WORKERS }, async (_, w) => {
    const a = from + w * chunk, b = Math.min(to, a + chunk);
    if (a >= b) return;
    const seg = path.join(out, `seg${w}.mkv`);
    segs[w] = seg;
    const page = await openPage();
    const enc = encoder(seg, FPS, ["-c:v", "ffv1", "-pix_fmt", "bgr0"]);
    for (let i = a; i < b; i++) {
      for (let k = 0; k < SUB; k++) await enc.write(await shot(page, subTime(i, k)));
      if (++doneFrames % 60 === 0) {
        const el = (Date.now() - started) / 1000;
        console.log(`${doneFrames}/${frames} frames, ${el.toFixed(0)} s, ~${((el / doneFrames) * (frames - doneFrames)).toFixed(0)} s left`);
      }
    }
    await enc.end();
    await page.close();
  }));
  const list = path.join(out, "segs.txt");
  fs.writeFileSync(list, segs.filter(Boolean).map((s) => `file '${s}'`).join("\n"));
  const full = from === 0 && to === Math.round(DURATION * FPS);
  const target = path.join(out, full ? "brimtune-promo.mp4" : "part.mp4");
  const audio = path.join(out, "audio.wav");
  const withAudio = fs.existsSync(audio);
  const ff = spawn(ffmpegPath, ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", list,
    ...(withAudio ? ["-ss", String(from / FPS), "-t", String(frames / FPS), "-i", audio] : []),
    "-map", "0:v", ...(withAudio ? ["-map", "1:a", "-c:a", "aac", "-b:a", "256k", "-ar", "48000"] : []),
    "-vf", "scale=out_color_matrix=bt709:out_range=tv",
    "-c:v", "libx264", "-preset", "slow", "-crf", "14", "-profile:v", "high", "-pix_fmt", "yuv420p", "-r", String(FPS),
    "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
    "-movflags", "+faststart", "-t", String(frames / FPS), target], { stdio: "inherit" });
  await new Promise((r, j) => ff.on("close", (c) => (c ? j(new Error(`ffmpeg ${c}`)) : r())));
  segs.filter(Boolean).forEach((s) => fs.rmSync(s));
  console.log(`→ ${path.relative(dir, target)} in ${((Date.now() - started) / 1000).toFixed(0)} s${withAudio ? "" : " (no audio yet)"}`);
}
await browser.close();
server.close();

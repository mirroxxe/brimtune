// Renders banner.html to out/youtube-banner.png and .jpg (2560×1440), plus a preview with the safe-area guides.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import puppeteer from "puppeteer-core";
import ffmpegPath from "ffmpeg-static";

const dir = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(dir, "out");
fs.mkdirSync(out, { recursive: true });
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true, defaultViewport: { width: 2560, height: 1440, deviceScaleFactor: 1 },
});
const page = await browser.newPage();
for (const [query, name] of [["", "youtube-banner.png"], ["?guides", "youtube-banner-guides.png"]]) {
  await page.goto(pathToFileURL(path.join(dir, "banner.html")).href + query, { waitUntil: "networkidle0" });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(out, name), clip: { x: 0, y: 0, width: 2560, height: 1440 } });
}
await browser.close();
// YouTube takes up to 6 MB; a high-quality JPEG stays well under it.
spawnSync(ffmpegPath, ["-y", "-loglevel", "error", "-i", path.join(out, "youtube-banner.png"), "-q:v", "2", path.join(out, "youtube-banner.jpg")], { stdio: "inherit" });
for (const f of ["youtube-banner.png", "youtube-banner.jpg"]) console.log(f, (fs.statSync(path.join(out, f)).size / 1e6).toFixed(2), "MB");

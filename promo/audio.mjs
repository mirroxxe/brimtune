// Scores the promo: music and sound design from the same cues the picture uses → out/audio.wav.
// Everything is synthesised here (additive pad, FM keys and bells, drums from noise and sines,
// a Freeverb-style room), so the track is ours and reproducible.  Run: node audio.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { cue, lyrics, wordStep, DURATION, short } from "./cues.js";

// --short scores the 11-second short: its own music, and the film's sound effects moved through the edit list.
const SHORT = process.argv.includes("--short");
const DUR = SHORT ? short.duration : DURATION;

const SR = 48000, N = Math.round(DUR * SR);
const L = new Float32Array(N), R = new Float32Array(N);       // dry
const RL = new Float32Array(N), RR = new Float32Array(N);     // reverb send
const duckables = { L: new Float32Array(N), R: new Float32Array(N) }; // pad + bass, ducked by the kick

let seed = 7;
const rnd = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296 * 2 - 1; };
const hz = (m) => 440 * Math.pow(2, (m - 69) / 12);
const TAU = Math.PI * 2;

// Write a mono voice into the buses: fn(time since start) → sample.
// While scoring the short, sound effects are written at the film's times and moved through the edit list.
let remap = null;
const throughEdl = (t) => { const seg = short.edl.find(([, src, len]) => t >= src - 1e-9 && t < src + len); return seg ? seg[0] + (t - seg[1]) : null; };
function add(start, len, fn, { gain = 1, pan = 0, send = 0.2, bus = null } = {}) {
  if (remap) { start = remap(start); if (start == null) return; }
  const a = Math.max(0, Math.round(start * SR)), b = Math.min(N, Math.round((start + len) * SR));
  const gl = gain * Math.cos((pan + 1) * Math.PI / 4), gr = gain * Math.sin((pan + 1) * Math.PI / 4);
  const dl = bus ? bus.L : L, dr = bus ? bus.R : R;
  for (let i = a; i < b; i++) {
    const s = fn((i - start * SR) / SR);
    dl[i] += s * gl; dr[i] += s * gr;
    RL[i] += s * gl * send; RR[i] += s * gr * send;
  }
}
const env = (t, a, d) => (t < a ? t / a : Math.exp(-(t - a) / d));

// ---------- instruments ----------
function padChord(start, len, notes, { gain = 0.05, bright = 0.32 } = {}) {
  for (const [j, m] of notes.entries()) for (const det of [-1, 1]) {
    const f = hz(m) * Math.pow(2, (det * 6) / 1200), ph = Math.abs(rnd());
    add(start, len + 0.6, (t) => {
      const e = Math.min(1, t / 0.35) * Math.min(1, Math.max(0, (len + 0.6 - t) / 0.6));
      let s = 0;
      for (let n = 1; n <= 9; n++) s += Math.sin(TAU * f * n * t + ph * n) * Math.exp(-n * (1 - bright)) / n;
      return s * e * (1 + 0.15 * Math.sin(TAU * 0.3 * t + j));
    }, { gain, pan: det * (0.25 + j * 0.08), send: 0.35, bus: duckables });
  }
}
// FM electric-piano pluck.
function keys(start, m, { gain = 0.16, pan = 0, send = 0.3, dec = 0.55, index = 2.2 } = {}) {
  const f = hz(m);
  add(start, dec * 5, (t) => {
    const I = index * Math.exp(-t * 7);
    return Math.sin(TAU * f * t + I * Math.sin(TAU * f * t)) * env(t, 0.003, dec) + 0.3 * Math.sin(TAU * 2 * f * t) * Math.exp(-t * 9);
  }, { gain, pan, send });
}
// Glassy bell (inharmonic FM).
function bell(start, m, { gain = 0.1, pan = 0, send = 0.45, dec = 0.9 } = {}) {
  const f = hz(m);
  add(start, dec * 5, (t) => {
    const I = 3 * Math.exp(-t * 5);
    return Math.sin(TAU * f * t + I * Math.sin(TAU * f * 3.5 * t)) * env(t, 0.002, dec);
  }, { gain, pan, send });
}
function marimba(start, m, { gain = 0.16, pan = 0, send = 0.3 } = {}) {
  const f = hz(m);
  add(start, 1.2, (t) => (Math.sin(TAU * f * t) * Math.exp(-t * 5) + 0.35 * Math.sin(TAU * f * 4 * t) * Math.exp(-t * 22)) * Math.min(1, t / 0.002), { gain, pan, send });
}
function bass(start, len, m, gain = 0.3) {
  const f = hz(m);
  add(start, len, (t) => {
    const e = Math.min(1, t / 0.008) * Math.min(1, (len - t) / 0.05) * (0.45 + 0.55 * Math.exp(-t * 7));
    const s = Math.sin(TAU * f * t) + 0.3 * Math.sin(TAU * 2 * f * t) * Math.exp(-t * 10);
    return Math.tanh(s * 1.2) * e;
  }, { gain, send: 0.02, bus: duckables });
}
const kicks = [];
function kick(start, gain = 0.85) {
  kicks.push(start);
  let ph = 0;
  add(start, 0.5, (t) => {
    const f = 48 + 110 * Math.exp(-t * 28);
    ph += TAU * f / SR;
    return Math.sin(ph) * Math.exp(-t * 6.5) + 0.25 * rnd() * Math.exp(-t * 300);
  }, { gain, send: 0.03 });
}
// Filtered noise with a time-varying band (centre(t) in Hz), for whooshes, claps, hats.
function noise(start, len, { center, q = 1.2, amp, gain = 0.2, pan = 0, send = 0.3 }) {
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  add(start, len, (t) => {
    const fc = Math.min(18000, Math.max(40, center(t)));
    const w = TAU * fc / SR, al = Math.sin(w) / (2 * q), c = Math.cos(w);
    const b0 = al, a0 = 1 + al, a1 = -2 * c, a2 = 1 - al;
    const x = rnd();
    const y = (b0 * x - b0 * x2 - a1 * y1 - a2 * y2) / a0;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    return y * amp(t);
  }, { gain, pan: typeof pan === "function" ? 0 : pan, send });
}
function sweepPan(start, len, from, to, opts) {
  // pan moving across: render two halves with different pans (cheap and smooth enough)
  const steps = 8;
  for (let k = 0; k < steps; k++) {
    const a = (k / steps) * len, b = ((k + 1) / steps) * len;
    noise(start + a, b - a, { ...opts, center: (t) => opts.center(t + a), amp: (t) => opts.amp(t + a) * Math.min(1, t / 0.01, (b - a - t) / 0.01), pan: from + (to - from) * ((k + 0.5) / steps) });
  }
}
const clap = (s, g = 0.32) => noise(s, 0.3, { center: () => 1600, q: 0.9, amp: (t) => (t < 0.03 ? (Math.floor(t / 0.01) % 2 ? 0.6 : 1) : Math.exp(-(t - 0.03) * 14)), gain: g, send: 0.35 });
const hat = (s, g = 0.08, p = 0.2) => noise(s, 0.08, { center: () => 9000, q: 0.7, amp: (t) => Math.exp(-t * 60), gain: g, pan: p, send: 0.1 });
const tick = (s, g = 0.22, f = 2600, p = 0) => {
  add(s, 0.03, (t) => Math.sin(TAU * f * t) * Math.exp(-t * 260), { gain: g, pan: p, send: 0.12 });
  noise(s, 0.02, { center: () => 6000, q: 1, amp: (t) => Math.exp(-t * 400), gain: g * 0.7, pan: p, send: 0.1 });
};
const thump = (s, g = 0.5, f0 = 90) => { let ph = 0; add(s, 0.4, (t) => { ph += TAU * (f0 * (1 + Math.exp(-t * 20))) / SR; return Math.sin(ph) * Math.exp(-t * 9); }, { gain: g, send: 0.05 }); };
const bloop = (s, f0, f1, g = 0.2) => { let ph = 0; add(s, 0.2, (t) => { ph += TAU * (f0 + (f1 - f0) * Math.min(1, t / 0.07)) / SR; return Math.sin(ph) * env(t, 0.004, 0.05); }, { gain: g, send: 0.25 }); };

// ---------- music (short) ----------
function scoreShort() {
  const ch = [[0, 2, [53, 57, 60, 64, 67]], [2, 2, [50, 57, 60, 62, 65]], [4, 1.5, [46, 53, 57, 60, 62]], [5.5, 1.5, [43, 53, 58, 62, 65]],
    [7, 1.5, [48, 55, 58, 62, 65]], [8.5, 1, [46, 53, 57, 62, 64]], [9.5, 1.5, [41, 53, 57, 60, 64, 67, 72]]];
  for (const [st, len, notes] of ch) padChord(st, len, notes, { gain: st >= 9.5 ? 0.045 : 0.034, bright: st >= 9.5 ? 0.5 : 0.38 });
  for (const [st, len, notes] of ch) if (st < 9.5) for (let b = 0; b < len - 0.01; b += 0.5) bass(st + b, 0.46, notes[0] - 12 + (b % 1 === 0.5 ? 12 : 0), 0.2);
  for (let t = 0; t < 9.5 - 0.01; t += 0.25) {
    const c = ch.filter(([st]) => st <= t + 1e-6).pop()[2], step = Math.round(t / 0.25), seq = [0, 2, 1, 3, 2, 4, 3, 1];
    keys(t, c[seq[step % 8] % c.length] + 12, { gain: step % 4 === 0 ? 0.1 : 0.068, pan: step % 2 ? 0.3 : -0.3, dec: 0.4 });
  }
  for (let t = 0; t < 9.5 - 0.01; t += 0.5) {
    const beat = Math.round(t / 0.5);
    if (beat % 2 === 0) kick(t, 0.85); else clap(t, 0.27);
    hat(t + 0.25, 0.07, 0.25); hat(t + 0.125, 0.035, -0.3); hat(t + 0.375, 0.035, -0.3);
  }
  // A lift on every cut, the lyric melody under the full screen, the big chord on the logo.
  short.edl.slice(1, -1).forEach(([t]) => noise(t, 0.9, { center: () => 8000, q: 0.5, amp: (x) => Math.exp(-x * 4), gain: 0.05, send: 0.4 }));
  [74, 77, 81, 79].forEach((m, k) => bell(6.0 + k * wordStep, m, { gain: 0.08, pan: (k - 1.5) * 0.1, dec: 0.5 }));
  kick(9.5, 1);
  { let ph = 0; add(9.5, 1.5, (x) => { ph += TAU * (30 + 30 * Math.exp(-x * 4)) / SR; return Math.sin(ph) * Math.exp(-x * 1.6); }, { gain: 0.4, send: 0.05 }); }
  [65, 69, 72, 76, 79, 84].forEach((m, i) => bell(9.5 + i * 0.012, m, { gain: 0.07, pan: (i - 2.5) * 0.15, dec: 1.4, send: 0.6 }));
  keys(9.5, 53, { gain: 0.14, dec: 1.4 }); keys(9.5, 60, { gain: 0.1, dec: 1.4 });
}

if (SHORT) scoreShort(); else {
// ---------- music ----------
// [start, length, voicing]; F major, two-bar phrases, a breakdown under the lyrics, a hush under "Barely there".
const chords = [
  [0, 2, [53, 57, 60, 64, 67]],          // Fmaj9      hook 1
  [2, 2, [50, 57, 60, 62, 65]],          // Dm9        hook 2
  [4, 2, [46, 53, 57, 60, 62]],          // B♭maj9     Meet Brimtune
  [6, 2, [53, 57, 60, 64, 67]],          // Fmaj9      the Mac
  [8, 2, [57, 60, 64, 67]],              // Am7
  [10, 2, [50, 53, 57, 60, 64]],         // Dm9        YouTube Music
  [12, 2, [46, 53, 57, 62, 60]],         // B♭maj9     search
  [14, 2, [48, 55, 58, 62, 65]],         // C11
  [16, 2, [43, 53, 58, 62, 65]],         // Gm9        full screen (breakdown)
  [18, 2, [48, 55, 58, 64, 67]],         // C9
  [20, 2, [45, 57, 60, 64, 65]],         // F/A        lock screen
  [22, 2, [50, 53, 57, 60, 64]],         // Dm9        alerts
  [24, 2, [46, 53, 57, 62, 64]],         // B♭maj9#11  displays
  [26, 2, [53, 57, 64, 67]],             // Fmaj7 (thin) barely there
  [28, 1, [48, 55, 60, 65]],             // Csus
  [29, 2, [45, 52, 55, 60, 64]],         // Am7        bento
  [31, 0.5, [48, 55, 58, 64]],           // C7
  [31.5, 2, [46, 53, 57, 62, 60]],       // B♭maj9     Free.
  [33.5, 0.5, [48, 55, 58, 62, 65]],     // C11
  [34, 4, [41, 53, 57, 60, 64, 67, 72]], // Fmaj9      the logo
];
for (const [s, len, notes] of chords) {
  const big = s >= 34, hush = s >= 26 && s < 29;
  padChord(s, len, notes, { gain: big ? 0.045 : hush ? 0.026 : 0.034, bright: big ? 0.5 : s < 4 || hush ? 0.22 : 0.36 });
}
// Bass follows the roots where the groove plays.
const groove = (t) => (t >= 6 && t < 16) || (t >= 20 && t < 26) || (t >= 29 && t < 34);
for (const [s, len, notes] of chords) for (let b = 0; b < len - 0.01; b += 0.5) {
  const t = s + b;
  if (groove(t) || (t >= 4 && t < 6)) bass(t, 0.46, notes[0] - 12 + (b % 1 === 0.5 ? 12 : 0), t < 6 ? 0.12 : 0.2);
  else if (t >= 16 && t < 20 && b % 1 === 0) bass(t, 0.9, notes[0] - 12, 0.14);
}
// Hook: one felt-key note per word.
[[cue.hook1, [72, 69, 65, 67, 69]], [cue.hook2, [69, 72, 74, 76, 77, 76]]].forEach(([times, notes]) =>
  times.forEach((t, i) => keys(t, notes[i], { gain: 0.12, dec: 0.7, index: 1.2, pan: (i - 2.5) * 0.08 })));
// Arpeggio on eighths, off during the hook, the lyric breakdown and the hush.
for (let t = 4; t < 34 - 0.01; t += 0.25) {
  if ((t >= 16 && t < 20) || (t >= 26 && t < 29)) continue;
  const ch = chords.filter(([s]) => s <= t + 1e-6).pop()[2];
  const step = Math.round(t / 0.25);
  const seq = [0, 2, 1, 3, 2, 4, 3, 1];
  const m = ch[seq[step % seq.length] % ch.length] + 12;
  keys(t, m, { gain: (step % 4 === 0 ? 0.1 : 0.068) * (t < 6 ? 0.7 : 1), pan: step % 2 ? 0.3 : -0.3, dec: 0.4 });
}
// The lyrics are "sung" by a bell lead, one note per lit word (full screen and lock screen).
const melody = [null, [74, 77, 81, 79, 77, 74], [72, 74, 77, 79, 77, 72], [70, 74, 77, 81, 79, 77], [72, 76, 79, 77, 76, 72]];
melody.forEach((notes, li) => notes && notes.forEach((m, k) => {
  const t = lyrics[li].start + k * wordStep;
  if (t >= cue.full - 0.01 && t < cue.unlock) { bell(t, m, { gain: t < 20 ? 0.085 : 0.05, pan: (k - 2.5) * 0.08, dec: 0.5 }); keys(t, m - 12, { gain: 0.05, dec: 0.3 }); }
}));
// Drums.
for (let t = 4; t < 34 - 0.01; t += 0.5) {
  const beat = Math.round(t / 0.5), on = beat % 2 === 0;
  if (groove(t)) {
    if (on) kick(t, 0.8); else clap(t, 0.27);
    if (beat % 8 === 7) kick(t + 0.25, 0.5);
    hat(t + 0.25, 0.07, 0.25);
    if ((t >= 20 && t < 26) || t >= 29) { hat(t + 0.125, 0.035, -0.3); hat(t + 0.375, 0.035, -0.3); }
  } else if (t >= 16 && t < 20) { if (beat % 4 === 0) kick(t, 0.5); hat(t + 0.25, 0.04, 0.2); }
  else if (t >= 4 && t < 6 && on) kick(t, 0.45);
}
// Under "Barely there": a quiet clock ticking sixteenths.
for (let t = cue.stats + 0.25; t < cue.bento - 0.2; t += 0.125) tick(t, Math.round(t * 8) % 4 === 0 ? 0.05 : 0.025, 4200, 0.2);
// Hits: "Meet", "Free.", the logo.
function hit(t, g = 1) {
  kick(t, g);
  let ph = 0; add(t, 2.4, (x) => { ph += TAU * (30 + 30 * Math.exp(-x * 4)) / SR; return Math.sin(ph) * Math.exp(-x * 1.6); }, { gain: 0.4 * g, send: 0.05 });
  noise(t, 2, { center: (x) => 7000 - 3000 * Math.min(1, x), q: 0.5, amp: (x) => Math.exp(-x * 2.4), gain: 0.05 * g, send: 0.5 });
}
hit(cue.meet, 0.8); [77, 81, 84, 88].forEach((m, i) => bell(cue.meet + i * 0.015, m, { gain: 0.05, pan: (i - 1.5) * 0.2, dec: 1.1, send: 0.6 }));
hit(cue.free, 0.9); clap(cue.free, 0.3); [70, 74, 77, 81].forEach((m, i) => bell(cue.free + i * 0.012, m, { gain: 0.05, pan: (i - 1.5) * 0.2, dec: 0.9 }));
hit(cue.end, 1.0);
[65, 69, 72, 76, 79, 84].forEach((m, i) => bell(cue.end + i * 0.012, m, { gain: 0.07, pan: (i - 2.5) * 0.15, dec: 1.8, send: 0.6 }));
keys(cue.end, 53, { gain: 0.14, dec: 1.6 }); keys(cue.end, 60, { gain: 0.1, dec: 1.6 });
[84, 88, 91, 96].forEach((m, i) => bell(cue.wordmark + i * 0.06, m, { gain: 0.035, pan: -0.4 + i * 0.27, dec: 0.6 }));

}

// ---------- sound design ----------
if (SHORT) remap = throughEdl;
const swell = (s, len, f0, f1, g, send = 0.4) => noise(s, len, { center: (t) => f0 + (f1 - f0) * (t / len) ** 2, q: 0.8, amp: (t) => (t / len) ** 1.6, gain: g, send });
const whoosh = (s, len, from, to, g = 0.14, f = 6000) => sweepPan(s, len, from, to, { center: (t) => 700 + f * Math.sin(Math.PI * Math.min(1, t / len)), q: 1.1, amp: (t) => Math.sin(Math.PI * Math.min(1, t / len)) ** 1.5, gain: g, send: 0.3 });
// Hook: the notch wakes, then drops into the icon.
bloop(cue.wake, 520, 800, 0.14); [84, 88].forEach((m, i) => bell(cue.wake + 0.04 + i * 0.05, m, { gain: 0.035, dec: 0.5 }));
swell(3.45, 0.55, 300, 6000, 0.12);
// Dive into the icon's notch and pull back out of the Mac's.
swell(cue.dive - 0.05, 0.45, 400, 9000, 0.18);
{ let ph = 0; add(cue.dive - 0.05, 0.45, (t) => { ph += TAU * (220 + 900 * (t / 0.45) ** 2) / SR; return Math.sin(ph) * (t / 0.45) ** 2; }, { gain: 0.035, send: 0.4 }); }
thump(cue.mac, 0.4, 70); whoosh(cue.mac, 0.7, 0.3, -0.3, 0.12);
bloop(cue.compact, 520, 800, 0.12);
// Hover → open.
noise(cue.open - 0.18, 0.5, { center: (t) => 1500 + 9000 * Math.min(1, t / 0.2), q: 1.5, amp: (t) => (t < 0.18 ? t / 0.18 : Math.exp(-(t - 0.18) * 9)), gain: 0.11, send: 0.4 });
[84, 88, 91].forEach((m, i) => bell(cue.open + i * 0.03, m, { gain: 0.04, pan: -0.3 + i * 0.3, dec: 0.5 }));
// Volume drag: soft detents rising in pitch.
for (let i = 0; i <= 8; i++) tick(cue.volume[0] + (i / 8) * (cue.volume[1] - cue.volume[0]), 0.05, 1500 + i * 140, 0.2);
// YouTube Music: click, the spark flies to the notch, the island names the song with a shimmer.
tick(cue.play, 0.22, 2600, -0.2);
sweepPan(cue.play + 0.05, 0.3, -0.4, 0.1, { center: (t) => 2000 + 8000 * t / 0.3, q: 3, amp: (t) => Math.sin(Math.PI * t / 0.3), gain: 0.08, send: 0.5 });
bloop(cue.peek, 400, 760, 0.12);
sweepPan(cue.peek, 0.95, -0.7, 0.7, { center: (t) => 2500 + 7000 * t, q: 2.5, amp: (t) => Math.sin(Math.PI * Math.min(1, t / 0.95)), gain: 0.09, send: 0.5 });
[89, 93, 96, 100, 101].forEach((m, i) => bell(cue.peek + 0.08 + i * 0.07, m, { gain: 0.028, pan: -0.6 + i * 0.3, dec: 0.35 }));
// Search, typing, Return, shelf, expand.
tick(cue.search, 0.2, 2600, 0.1);
cue.keys.forEach((k, i) => noise(k, 0.04, { center: () => 3200 + i * 300, q: 1.5, amp: (t) => Math.exp(-t * 120), gain: 0.22, pan: 0.1, send: 0.1 }));
bloop(cue.results, 700, 900, 0.06);
tick(cue.enter, 0.24, 1800, 0.1); bloop(cue.enter + 0.03, 400, 760, 0.11);
sweepPan(cue.enter + 0.03, 0.8, -0.6, 0.6, { center: (t) => 3000 + 6000 * t, q: 2.5, amp: (t) => Math.sin(Math.PI * Math.min(1, t / 0.8)), gain: 0.07, send: 0.5 });
cue.shelf.forEach((s, i) => tick(s - 0.04, 0.07, 1900 + i * 250, -0.2 + i * 0.2));
tick(cue.expand, 0.22, 2400, 0.2); swell(cue.expand, 0.5, 400, 6000, 0.15); thump(cue.full, 0.3, 70);
// Tabs in full screen.
[cue.tabQueue, cue.tabLists].forEach((t, i) => { tick(t, 0.16, 2300 + i * 300, 0.3); whoosh(t + 0.02, 0.3, -0.2, 0.3, 0.04); });
// Lock, whip, alerts.
noise(cue.lock - 0.1, 0.4, { center: (t) => 4000 - 3500 * Math.min(1, t / 0.3), q: 1, amp: (t) => Math.sin(Math.PI * Math.min(1, t / 0.4)), gain: 0.1, send: 0.4 });
marimba(cue.lock + 0.05, 76, { gain: 0.08 }); marimba(cue.lock + 0.14, 69, { gain: 0.08 });
whoosh(cue.unlock - 0.05, 0.4, 0.5, -0.4, 0.2);
marimba(cue.timer, 81, { gain: 0.15 }); marimba(cue.timer + 0.09, 81, { gain: 0.11 });
marimba(cue.meeting, 84, { gain: 0.14, pan: -0.15 }); marimba(cue.meeting + 0.1, 88, { gain: 0.13, pan: 0.15 });
[77, 81, 84].forEach((m, i) => bell(cue.airpods + i * 0.06, m, { gain: 0.07, pan: -0.2 + i * 0.2, dec: 0.5 }));
// Displays: pull back, the display glides in, the pill pops.
whoosh(23.5, 0.8, -0.5, 0.6, 0.14, 4000); thump(cue.displays + 0.6, 0.2, 55); bloop(cue.pill, 450, 820, 0.12);
// Into the pill → stats; counters count; bento tiles land; download.
swell(25.7, 0.32, 500, 9000, 0.16);
for (let i = 0; i < 10; i++) tick(cue.stats + 0.45 + i * 0.09, 0.05, 1200 + i * 160, (i % 2 ? 0.3 : -0.3));
swell(28.4, 0.6, 300, 7000, 0.12);
for (let i = 0; i < 6; i++) tick(cue.bento + 0.15 + i * 0.125 + 0.1, 0.09, 1700 + i * 120, -0.5 + i * 0.2);
whoosh(cue.free - 0.3, 0.35, -0.3, 0.3, 0.14);
bloop(cue.openSource, 500, 700, 0.08);
tick(cue.download, 0.24, 2200, 0.1); marimba(cue.download + 0.06, 84, { gain: 0.1 }); marimba(cue.download + 0.14, 89, { gain: 0.1 });
swell(cue.end - 0.4, 0.42, 400, 9000, 0.15);

remap = null;

// ---------- mix ----------
// Kick ducks the pad and bass.
for (let i = 0; i < N; i++) {
  const t = i / SR;
  let d = 1;
  for (let k = kicks.length - 1; k >= 0; k--) if (kicks[k] <= t) { d = 1 - 0.45 * Math.exp(-(t - kicks[k]) * 9); break; }
  L[i] += duckables.L[i] * d; R[i] += duckables.R[i] * d;
}
// Freeverb-style room on the send.
function reverb(input, offset) {
  const combs = [1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116].map((n) => Math.round((n + offset) * SR / 44100));
  const aps = [556, 441, 341, 225].map((n) => Math.round((n + offset) * SR / 44100));
  const out = new Float32Array(N);
  for (const len of combs) {
    const buf = new Float32Array(len); let idx = 0, store = 0;
    for (let i = 0; i < N; i++) {
      const y = buf[idx]; store = y * 0.8 + store * 0.2;
      buf[idx] = input[i] * 0.015 + store * 0.86; idx = (idx + 1) % len; out[i] += y;
    }
  }
  for (const len of aps) {
    const buf = new Float32Array(len); let idx = 0;
    for (let i = 0; i < N; i++) { const b = buf[idx]; const y = -out[i] + b; buf[idx] = out[i] + b * 0.5; idx = (idx + 1) % len; out[i] = y; }
  }
  return out;
}
const wl = reverb(RL, 0), wr = reverb(RR, 23);
let peak = 0;
const mixL = new Float32Array(N), mixR = new Float32Array(N);
for (let i = 0; i < N; i++) {
  const t = i / SR;
  const fade = t < 0.02 ? t / 0.02 : t > DUR - 1.3 ? Math.pow(Math.max(0, (DUR - t) / 1.3), 1.6) : 1;
  mixL[i] = Math.tanh((L[i] + wl[i] * 0.9) * 1.15) * fade;
  mixR[i] = Math.tanh((R[i] + wr[i] * 0.9) * 1.15) * fade;
  peak = Math.max(peak, Math.abs(mixL[i]), Math.abs(mixR[i]));
}
const norm = 0.89 / peak;
const pcm = Buffer.alloc(44 + N * 4);
pcm.write("RIFF", 0); pcm.writeUInt32LE(36 + N * 4, 4); pcm.write("WAVE", 8); pcm.write("fmt ", 12);
pcm.writeUInt32LE(16, 16); pcm.writeUInt16LE(1, 20); pcm.writeUInt16LE(2, 22); pcm.writeUInt32LE(SR, 24);
pcm.writeUInt32LE(SR * 4, 28); pcm.writeUInt16LE(4, 32); pcm.writeUInt16LE(16, 34); pcm.write("data", 36); pcm.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) {
  pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mixL[i] * norm)) * 32767), 44 + i * 4);
  pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mixR[i] * norm)) * 32767), 46 + i * 4);
}
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), "out");
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, SHORT ? "audio-short.wav" : "audio.wav"), pcm);
console.log(`out/${SHORT ? "audio-short" : "audio"}.wav  ${DUR}s  peak before normalise ${peak.toFixed(2)}`);

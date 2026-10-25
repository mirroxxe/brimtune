// Brimtune — 15-second promo. One function, renderAt(t), sets every frame from the time alone,
// so the renderer can seek anywhere (and back) and get the same picture. See STORYBOARD.md.
import { cue, lyrics, wordStep, DURATION } from "./cues.js";

// ---------- maths ----------
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, k) => a + (b - a) * k;
const prog = (t, start, len) => clamp((t - start) / len);
const ease = {
  inOut: (k) => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2),
  out: (k) => 1 - Math.pow(1 - k, 3),
  out5: (k) => 1 - Math.pow(1 - k, 5),
  in: (k) => k * k * k,
  back: (k) => 1 + 2.2 * Math.pow(k - 1, 3) + 1.2 * Math.pow(k - 1, 2),
};
// A quick press: 0 → 1 → 0 over `len` seconds.
const bump = (t, at, len = 0.14) => { const k = (t - at) / len; return k < 0 || k > 1 ? 0 : Math.sin(Math.PI * k); };

// Monotone cubic through [time, value] keys: smooth, continuous speed, never overshoots a key.
function track(keys, { log = false } = {}) {
  const ts = keys.map((k) => k[0]);
  const vs = keys.map((k) => (log ? Math.log(k[1]) : k[1]));
  const n = ts.length, d = [], m = new Array(n).fill(0);
  for (let i = 0; i < n - 1; i++) d[i] = (vs[i + 1] - vs[i]) / (ts[i + 1] - ts[i]);
  m[0] = d[0];
  for (let i = 1; i < n - 1; i++) {
    if (d[i - 1] * d[i] <= 0) continue;
    const h0 = ts[i] - ts[i - 1], h1 = ts[i + 1] - ts[i];
    const w1 = 2 * h1 + h0, w2 = h1 + 2 * h0;
    m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]);
  }
  return (t) => {
    let v;
    if (t <= ts[0]) v = vs[0] + m[0] * (t - ts[0]);
    else if (t >= ts[n - 1]) v = vs[n - 1];
    else {
      let i = 0;
      while (t > ts[i + 1]) i++;
      const h = ts[i + 1] - ts[i], s = (t - ts[i]) / h, s2 = s * s, s3 = s2 * s;
      v = (2 * s3 - 3 * s2 + 1) * vs[i] + (s3 - 2 * s2 + s) * h * m[i] + (-2 * s3 + 3 * s2) * vs[i + 1] + (s3 - s2) * h * m[i + 1];
    }
    return log ? Math.exp(v) : v;
  };
}

// A damped spring that chases each new target from wherever it was, keeping its speed.
function springStep(x0, v0, dt, w, z) {
  const a = z * w, wd = w * Math.sqrt(1 - z * z);
  const e = Math.exp(-a * dt), c = Math.cos(wd * dt), s = Math.sin(wd * dt), B = (v0 + a * x0) / wd;
  const x = e * (x0 * c + B * s);
  const v = e * (-a * (x0 * c + B * s) + (-x0 * wd * s + B * wd * c));
  return [x, v];
}
function spring(keys, w = 10.5, z = 0.7) {
  return (t) => {
    let x = keys[0][1], v = 0, t0 = keys[0][0], target = keys[0][1];
    for (let i = 1; i < keys.length && keys[i][0] <= t; i++) {
      const [dx, dv] = springStep(x - target, v, keys[i][0] - t0, w, z);
      x = target + dx; v = dv; t0 = keys[i][0]; target = keys[i][1];
    }
    return target + springStep(x - target, v, Math.max(0, t - t0), w, z)[0];
  };
}

const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const mix = (a, b, k) => { const A = hex(a), B = hex(b); return `rgb(${A.map((v, i) => Math.round(lerp(v, B[i], k))).join(",")})`; };

// ---------- content (all made up) ----------
const tracks = [
  { title: "Night Bus Home", artist: "Lumen Field", length: 202, start: 68, colors: ["#F2648E", "#7C6CF2", "#FFAE57"] },
  { title: "Paper Moons", artist: "Orla Vey", length: 228, start: 0, colors: ["#3FB6C9", "#4B5BD6", "#C8F08F"] },
  { title: "Kyiv, 5 a.m.", artist: "Teo Brann", length: 187, start: 61, colors: ["#FF8A4C", "#C2367A", "#FFD36E"] },
];
const switches = [0, cue.next, cue.enter + 0.03];
const trackAt = (t) => (t < switches[1] ? 0 : t < switches[2] ? 1 : 2);
function palette(t) {
  const P = tracks.map((x) => x.colors);
  const blend = (A, B, k) => A.map((c, i) => mix(c, B[i], ease.inOut(k)));
  if (t < cue.next) return blend(P[0], P[0], 0);
  if (t < cue.enter) return blend(P[0], P[1], prog(t, cue.next, 0.8));
  if (t < cue.free) return blend(P[1], P[2], prog(t, cue.enter, 0.7));
  return blend(P[2], P[0], prog(t, cue.free, 0.9));
}
const clock = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

// ---------- DOM ----------
const ICON = {
  prev: '<svg viewBox="0 0 24 24"><path d="M11 7v10l-7-5zm9 0v10l-7-5z"/></svg>',
  pause: '<svg viewBox="0 0 24 24"><path d="M7 5h3.5v14H7zm6.5 0H17v14h-3.5z"/></svg>',
  next: '<svg viewBox="0 0 24 24"><path d="M13 7v10l7-5zm-9 0v10l7-5z"/></svg>',
  expand: '<svg viewBox="0 0 24 24"><path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/></svg>',
  search: '<svg viewBox="0 0 24 24"><path d="M10 3a7 7 0 1 0 4.2 12.6l5.1 5.1 1.4-1.4-5.1-5.1A7 7 0 0 0 10 3zm0 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10z"/></svg>',
  chevR: '<svg class="chev" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>',
  chevD: '<svg class="chev" viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></svg>',
  timer: '<svg viewBox="0 0 24 24"><path d="M9 2h6v2H9zm3 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16zm1 8.6V9h-2v6.4l4.2 2.5 1-1.7z"/></svg>',
  pods: '<svg class="ai pods" viewBox="0 0 24 24"><path d="M6.5 3A3.5 3.5 0 0 0 3 6.5c0 1.6 1 2.9 2.5 3.3V19a1.5 1.5 0 0 0 3 0V6.5A3.5 3.5 0 0 0 6.5 3zm11 0A3.5 3.5 0 0 0 14 6.5V19a1.5 1.5 0 0 0 3 0V9.8c1.5-.4 2.5-1.7 2.5-3.3A3.5 3.5 0 0 0 17.5 3z"/></svg>',
  pointer: '<path d="M1 1 L1 25 L7 19.2 L11.2 28.6 L15.4 26.8 L11.3 17.6 L19.6 17.6 Z" fill="#000" stroke="#fff" stroke-width="1.8" stroke-linejoin="round"/>',
};
const bars = '<span class="bars"><i></i><i></i><i></i><i></i></span>';
const pl = (name, c) => `<span class="pl"><span class="cover" style="--c1:${c[0]};--c2:${c[1]};--c3:${c[2]}"></span><small>${name}</small></span>`;
const row = (title, sub, c, extra = "", cls = "result") =>
  `<div class="${cls}"><span class="cover cover-row" style="--c1:${c[0]};--c2:${c[1]};--c3:${c[2]}"></span><span><strong>${title}</strong><small>${sub}</small></span>${extra}</div>`;

// The Brimtune icon, drawn from Tools/make-icon.swift's geometry (y flipped for SVG).
const iconSVG = `
<svg id="icon" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs><linearGradient id="sq" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#17141C"/><stop offset="1" stop-color="#08080A"/></linearGradient>
  <filter id="ish" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="26" flood-color="#000" flood-opacity=".55"/></filter></defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#sq)" filter="url(#ish)"/>
  <path fill="#ECE7DE" fill-rule="evenodd" d="M262 762 L652 762 A110 110 0 0 0 762 652 L762 542 L608 512 L732 482 L732 352 A90 90 0 0 0 642 262 L584 262 L584 280 A24 24 0 0 1 560 304 L464 304 A24 24 0 0 1 440 280 L440 262 L262 262 Z
    M572 404 a52 52 0 1 0 -104 0 a52 52 0 1 0 104 0 Z M612 636 a92 92 0 1 0 -184 0 a92 92 0 1 0 184 0 Z"/>
  <circle cx="520" cy="404" r="16" fill="#ECE7DE"/><circle cx="520" cy="636" r="30" fill="#F2648E"/>
</svg>`;

const stage = document.getElementById("stage");
const covers = { night: ["#F2648E", "#7C1F4F", "#FFC0D3"], focus: ["#3FB6C9", "#1E3C8C", "#C8F08F"], kyiv: ["#FF8A4C", "#C2367A", "#FFD36E"], liked: ["#7C6CF2", "#241D5C", "#B6F0E4"], late: ["#9B8CF2", "#2E2A6B", "#E9D7FF"] };
const wordsHTML = (text) => text.split(" ").map((w) => `<span class="w">${w}</span>`).join(" ");

stage.innerHTML = `
  <div id="bg"><i class="b1"></i><i class="b2"></i><i class="b3"></i></div>
  <div id="floor"></div>
  <div id="free-word">${"Free.".split("").map((c) => `<span>${c}</span>`).join("")}</div>
  <div id="world"><div id="mac">
    <div id="base"><div class="kb"></div><div class="pad"></div><div id="front"></div></div>
    <div id="lid"><div id="screen">
      <div id="desk">
        <div class="wall"><i class="w1"></i><i class="w2"></i><i class="w3"></i><i class="w4"></i></div>
        <div class="win"><div class="tb"><b></b><b></b><b></b><span class="url">tunes.example/now-playing</span></div>
          <div class="side"><b>Listen now</b><br>Browse<br>Radio<br>Library<br>Playlists<br>Liked music</div>
          <div class="main"><div class="hero"><span class="cover"></span><div><h4 class="wt">Night Bus Home</h4><p class="wa">Lumen Field · Single</p></div></div>
            <div class="rows">${[["Night Bus Home", "3:22"], ["Paper Moons", "3:48"], ["Kyiv, 5 a.m.", "3:07"], ["Glasshouse", "4:01"]].map(([n, d], i) => `<div><span class="cover" style="--c1:${Object.values(covers)[i][0]};--c2:${Object.values(covers)[i][1]};--c3:${Object.values(covers)[i][2]}"></span>${n}<span style="margin-left:auto">${d}</span></div>`).join("")}</div></div>
        </div>
      </div>
      <div id="menubar"><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span>
        <span class="r"><span class="mini"></span><svg viewBox="0 0 24 24"><path d="M12 18.5a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2zM5.6 13.4a9 9 0 0 1 12.8 0l-1.6 1.6a6.8 6.8 0 0 0-9.6 0zM2.4 10.2a13.5 13.5 0 0 1 19.2 0L20 11.8a11.3 11.3 0 0 0-16 0z"/></svg><svg viewBox="0 0 24 24"><path d="M3 8h15a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1zm1 2v4h11v-4zm16 1h1.5v2H20z"/></svg><span>Sat Oct 25&nbsp; 9:41</span></span></div>
      <div id="lock">
        <div class="wall"><i class="w1"></i><i class="w2"></i><i class="w3"></i><i class="w4"></i></div>
        <div class="date">Saturday, October 25</div>
        <div class="clock">9:41</div>
        <div class="card"><span class="cover"></span><div class="tt"><strong class="lt">Kyiv, 5 a.m.</strong><span>Teo Brann</span></div>
          <div class="ctr">${ICON.prev}${ICON.pause}${ICON.next}</div>
          <div class="wave">${"<i></i>".repeat(56)}</div><div class="lprog"><i></i></div></div>
        <div class="who"><b></b>Touch ID or Enter Password</div>
      </div>
      <div id="wake"></div>
      <div id="island"><span class="fl l"></span><span class="fl r"></span><div class="body">
        <div class="view v-compact"><span class="cover cover-sm"></span>${bars}</div>
        <div class="view v-timer"><span class="cover cover-sm"></span><span class="badge">${ICON.timer}<b class="cd">25:00</b></span></div>
        <div class="view v-alert v-meeting"><span class="ai cal">25</span><span class="at"><small>In 5 minutes</small><strong>Design review</strong></span><span class="join">Join</span></div>
        <div class="view v-alert v-airpods">${ICON.pods}<span class="at"><small>Connected</small><strong>AirPods Pro</strong></span><span class="batt"><span class="bb"><span></span></span><b>82%</b></span></div>
        <div class="view v-open"><div class="vi">
          <div class="player">
            <div class="prow"><span class="cover cover-lg"></span><div class="meta"><div class="t ta"><strong></strong><span></span></div><div class="t tb"><strong></strong><span></span></div></div>${bars}</div>
            <div class="progress"><span class="now">1:08</span><span class="bar"><span class="fill"></span></span><span class="left">-2:14</span></div>
            <div class="controls"><span class="ctl c-prev">${ICON.prev}</span><span class="ctl play">${ICON.pause}</span><span class="ctl c-next">${ICON.next}</span><span class="expand">${ICON.expand}</span></div>
            <div class="volume"><svg viewBox="0 0 24 24"><path d="M3 9.5v5h3.6L12 19V5L6.6 9.5z"/><path class="w" d="M15.2 9.6a3.4 3.4 0 0 1 0 4.8M17.6 7.4a6.6 6.6 0 0 1 0 9.2"/></svg><span class="vtrack"><i></i></span><svg viewBox="0 0 24 24" style="opacity:.5"><path d="M3 9.5v5h3.6L12 19V5L6.6 9.5z"/><path class="w" d="M15.2 9.6a3.4 3.4 0 0 1 0 4.8M17.6 7.4a6.6 6.6 0 0 1 0 9.2M19.8 5.2a9.8 9.8 0 0 1 0 13.6"/></svg></div>
          </div>
          <div class="lower">
            <div class="lo-x">
              <div class="search s-idle">${ICON.search}<span class="ph">Search for a song</span></div>
              <div class="xrow"><span class="xtitle">Up Next</span><span class="chip">10</span>${ICON.chevR}</div>
              <div class="xrow"><span class="xtitle">Playlists</span>${ICON.chevD}</div>
              <div class="shelf">${pl("Night drive", covers.night)}${pl("Focus", covers.focus)}${pl("Kyiv mornings", covers.kyiv)}${pl("Liked music", covers.liked)}${pl("Late", covers.late)}</div>
            </div>
            <div class="lo-s">
              <div class="search s-live">${ICON.search}<span class="typed"></span><span class="caret"></span></div>
              <div class="results">${row("Kyiv, 5 a.m.", "Teo Brann · 3:07", covers.kyiv, "<kbd>Return</kbd>", "result first")}${row("Kyiv mornings", "Playlist · 42 songs", covers.night)}${row("Kyiv Lights", "Mira Sol · 2:56", covers.liked)}</div>
            </div>
          </div>
        </div></div>
        <div class="shim"></div>
      </div></div>
      <div id="fs"><div class="fsbase"></div><div class="mesh"><i class="m1"></i><i class="m2"></i><i class="m3"></i></div><div class="shade"></div>
        <span class="cover fcover"></span><div class="ftitle"><strong>Kyiv, 5 a.m.</strong><span>Teo Brann</span></div><div class="fprog"><i></i></div>
        <div class="flabel">Lyrics · word by word</div>
        <div class="lyr"><div class="lines">${lyrics.map((l) => `<div class="line">${wordsHTML(l.text)}</div>`).join("")}</div></div>
      </div>
      <svg id="cursor" viewBox="0 0 26 34">${ICON.pointer}</svg>
      <div id="glare"></div><div id="dim"></div>
    </div></div>
  </div></div>
  <div id="fg">${"<i></i>".repeat(9)}</div>
  <div id="shade"></div>
  <div id="cap"></div>
  <div id="dl"><div class="fillx"></div><div class="lab l1"><svg viewBox="0 0 24 24"><path d="M12 4v11M7 10.5l5 5 5-5M5 20h14"/></svg>Download for Mac</div><div class="lab l2 done"><svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Free, for every Mac</div></div>
  <svg id="pointer" viewBox="0 0 26 34">${ICON.pointer}</svg>
  <div id="fadein"></div>
  <div id="end"><div class="glow"><i class="g1"></i><i class="g2"></i><i class="g3"></i></div>${iconSVG}
    <div id="word">${"Brimtune".split("").map((c) => `<span class="word"><span>${c}</span></span>`).join("")}</div>
    <div id="url"><b>brimtune</b>.pages.dev</div></div>
`;

const $ = (s, el = stage) => el.querySelector(s);
const $$ = (s, el = stage) => [...el.querySelectorAll(s)];
const el = {
  bg: $$("#bg i"), free: $("#free-word"), freeL: $$("#free-word span"), mac: $("#mac"), desk: $("#desk"), win: $(".win"),
  island: $("#island"), compact: $(".v-compact"), timer: $(".v-timer"), meeting: $(".v-meeting"), airpods: $(".v-airpods"), open: $(".v-open"),
  loX: $(".lo-x"), loS: $(".lo-s"), lower: $(".lower"), shim: $(".shim"), metaA: $(".ta"), metaB: $(".tb"), coverLg: $(".cover-lg"),
  now: $(".progress .now"), left: $(".progress .left"), fill: $(".progress .fill"), next: $(".c-next"), expand: $(".expand"),
  sIdle: $(".s-idle"), sLive: $(".s-live"), typed: $(".typed"), caret: $(".caret"), results: $$(".result"), first: $(".result.first"),
  shelf: $$(".shelf .pl"), bars: $$(".bars i"), cd: $(".cd"), bb: $(".bb span"),
  fs: $("#fs"), fsbase: $("#fs .fsbase"), fsshade: $("#fs .shade"), lyr: $("#fs .lyr"), mesh: $$("#fs .mesh i"), fcover: $(".fcover"), lines: $(".lines"), lineEls: $$(".line"), fprog: $(".fprog i"), ftitle: $(".ftitle"), flabel: $(".flabel"),
  lock: $("#lock"), lclock: $("#lock .clock"), ldate: $("#lock .date"), card: $("#lock .card"), wave: $$("#lock .wave i"), lprog: $("#lock .lprog i"), who: $("#lock .who"),
  cursor: $("#cursor"), glare: $("#glare"), dim: $("#dim"), fg: $$("#fg i"), cap: $("#cap"), shade: $("#shade"),
  dl: $("#dl"), dlFill: $("#dl .fillx"), dl1: $("#dl .l1"), dl2: $("#dl .l2"), pointer: $("#pointer"),
  end: $("#end"), icon: $("#icon"), glow: $("#end .glow"), word: $$("#word .word span"), url: $("#url"),
  wt: $(".win .wt"), wake: $("#wake"), fadein: $("#fadein"), wa: $(".win .wa"),
};

// ---------- captions ----------
const captions = [
  { words: ["Your", "notch,", "*awake.*"], at: 0.85, out: 1.9 },
  { words: ["Hover.", "*It plays.*"], at: 2.15, out: 2.92 },
  { words: ["Colour", "from", "*every cover.*"], at: 3.12, out: 3.92 },
  { words: ["Search.", "*Playlists.*"], at: 4.12, out: 5.62 },
  { words: ["Right", "on", "your", "*lock screen.*"], at: 8.3, out: 9.7 },
  { words: ["Timers.", "Meetings.", "*AirPods.*"], at: cue.timer + 0.04, times: [cue.timer + 0.04, cue.meeting + 0.04, cue.airpods + 0.04], out: 11.45 },
].map((c) => {
  const node = document.createElement("div");
  node.className = "capline abs";
  node.style.cssText = "left:0;bottom:0";
  node.innerHTML = c.words.map((w) => {
    const italic = w.startsWith("*");
    const text = w.replace(/\*/g, "");
    return `<span class="word"><span>${italic ? `<em>${text}</em>` : text}</span></span>`;
  }).join("");
  el.cap.append(node);
  return { ...c, node, spans: [...node.querySelectorAll(".word > span")] };
});

function paintCaptions(t) {
  for (const c of captions) {
    const visible = t > c.at - 0.05 && t < c.out + 0.3;
    c.node.style.display = visible ? "block" : "none";
    if (!visible) continue;
    const exit = ease.inOut(prog(t, c.out, 0.26));
    c.node.style.opacity = 1 - exit;
    c.node.style.transform = `translateY(${-26 * exit}px)`;
    c.node.style.filter = exit > 0 ? `blur(${exit * 10}px)` : "none";
    c.spans.forEach((s, i) => {
      const start = c.times ? c.times[i] : c.at + i * 0.075;
      const k = prog(t, start, 0.5);
      const y = (1 - ease.out5(k)) * 105;
      s.style.transform = `translateY(${y}%)`;
      s.style.fontVariationSettings = `"wdth" ${lerp(62, 100, ease.out(k)).toFixed(1)}`;
      s.style.opacity = clamp(k * 3);
    });
  }
}

// ---------- island ----------
const S = [
  [0, "idle"], [cue.compact, "compact"], [cue.open, "open"], [cue.search, "search"], [cue.enter + 0.03, "open"],
  [cue.expand + 0.05, "compact"], [8.15, "compact"], [cue.timer, "timer"], [cue.meeting, "meeting"], [cue.airpods, "airpods"],
  [cue.free, "compact"], [cue.push - 0.08, "notch"],
];
const intervals = (name) => S.map(([s, n], i) => (n === name ? [s, S[i + 1]?.[0] ?? null] : null)).filter(Boolean);
const iv = Object.fromEntries(["compact", "timer", "meeting", "airpods", "open", "search"].map((n) => [n, intervals(n)]));
iv.openAny = [...iv.open, ...iv.search].sort((a, b) => a[0] - b[0]);
function viewAlpha(t, list, delay = 0.1, len = 0.28, out = 0.16) {
  let a = 0;
  for (const [s, e] of list) {
    const i = s <= 0 ? 1 : ease.out(prog(t, s + delay, len));
    const o = e == null ? 1 : 1 - prog(t, e, out);
    a = Math.max(a, Math.min(i, o));
  }
  return a;
}

let geo; // measured once fonts are in
function measure() {
  const isl = el.island;
  isl.style.width = "412px"; isl.style.left = `${756 - 206}px`; isl.style.height = "600px";
  el.loX.style.position = "static";
  const vi = $(".vi", el.open);
  const hOpen = vi.offsetHeight;
  el.loX.style.position = ""; el.loS.style.position = "static";
  const hSearch = vi.offsetHeight;
  el.loS.style.position = "";
  el.lower.style.height = `${Math.max(el.loX.offsetHeight, el.loS.offsetHeight)}px`;
  const screen = $("#screen");
  const at = (node, fx = 0.5, fy = 0.5) => {
    let x = 0, y = 0, n = node;
    while (n && n !== screen) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; }
    return [x + node.offsetWidth * fx, y + node.offsetHeight * fy];
  };
  geo = {
    sizes: { idle: [186, 32, 10], compact: [292, 32, 12], timer: [336, 32, 12], meeting: [392, 84, 28], airpods: [392, 84, 28], open: [412, hOpen, 34], search: [412, hSearch, 34], notch: [144, 42, 22] },
    next: at(el.next), search: at(el.sIdle, 0.3, 0.55), expand: at(el.expand), shelf: el.shelf.map((p) => at($(".cover", p))),
    cover: (() => { const [x, y] = at(el.coverLg, 0, 0); return [x, y, 58, 58]; })(),
  };
  const sz = (n) => geo.sizes[n];
  geo.w = spring(S.map(([s, n]) => [s, sz(n)[0]]));
  geo.h = spring(S.map(([s, n]) => [s, sz(n)[1]]));
  geo.r = spring(S.map(([s, n]) => [s, sz(n)[2]]));
  const [nx, ny] = geo.next, [sx, sy] = geo.search, [ex, ey] = geo.expand, sh = geo.shelf;
  const P = [
    [0, 1330, 1060], [1.2, 1010, 380], [cue.hover, 812, 20], [2.3, 840, 150], [2.86, nx, ny], [3.25, nx + 6, ny + 4],
    [cue.search - 0.12, sx, sy], [4.4, sx + 14, sy + 10], [4.9, sh[0][0] - 20, sh[0][1] - 40], [cue.shelf[0], sh[0][0], sh[0][1]],
    [cue.shelf[1], sh[1][0], sh[1][1]], [cue.shelf[2], sh[2][0], sh[2][1] - 6], [cue.expand - 0.08, ex, ey], [6.2, ex + 4, ey + 3],
  ];
  geo.cx = track(P.map(([t, x]) => [t, x]));
  geo.cy = track(P.map(([t, , y]) => [t, y]));
}

function barsAt(t, i) {
  const beat = t < cue.open ? 0 : Math.exp(-(((t - cue.open) % 0.5)) * 7);
  const k = 0.32 + 0.48 * Math.abs(Math.sin(t * (4.3 + i * 1.9) + i * 1.7)) + 0.3 * beat;
  return clamp(k, 0.2, 1);
}

function paintIsland(t, pal) {
  const w = geo.w(t), h = geo.h(t), r = Math.max(0, geo.r(t));
  const isl = el.island;
  isl.style.width = `${w}px`; isl.style.height = `${h}px`; isl.style.left = `${756 - w / 2}px`;
  isl.style.borderRadius = `0 0 ${r}px ${r}px`;
  isl.style.boxShadow = h > 60 ? `0 ${24 * clamp((h - 40) / 300)}px 60px -18px rgba(0,0,0,.65)` : "none";
  const view = (node, a, blur = true) => {
    node.style.opacity = a.toFixed(3);
    node.style.display = a < 0.002 ? "none" : "";
    node.style.transform = `scale(${lerp(0.94, 1, a)})`;
    node.style.filter = blur && a < 0.999 ? `blur(${(1 - a) * 8}px)` : "none";
  };
  view(el.compact, viewAlpha(t, iv.compact));
  view(el.timer, viewAlpha(t, iv.timer));
  view(el.meeting, viewAlpha(t, iv.meeting));
  view(el.airpods, viewAlpha(t, iv.airpods));
  const aOpen = viewAlpha(t, iv.openAny, 0.06, 0.3, 0.14);
  view(el.open, aOpen, false);
  const aX = viewAlpha(t, iv.open, 0.04, 0.26, 0.12), aS = viewAlpha(t, iv.search, 0.04, 0.26, 0.12);
  el.loX.style.opacity = aX; el.loS.style.opacity = aS;
  el.loX.style.transform = `translateY(${(1 - aX) * 8}px)`; el.loS.style.transform = `translateY(${(1 - aS) * 8}px)`;

  // Song: the old title leaves upwards while the new one arrives.
  const ti = trackAt(t), sw = switches[ti], k = ease.out(prog(t, sw, 0.32));
  const setT = (node, tr) => { node.children[0].textContent = tr.title; node.children[1].textContent = tr.artist; };
  setT(el.metaA, tracks[ti]);
  el.metaA.style.opacity = ti === 0 ? 1 : k; el.metaA.style.transform = `translateY(${ti === 0 ? 0 : (1 - k) * 10}px)`;
  if (ti > 0 && k < 1) { setT(el.metaB, tracks[ti - 1]); el.metaB.style.opacity = 1 - clamp(k * 2); el.metaB.style.transform = `translateY(${-k * 10}px)`; }
  else el.metaB.style.opacity = 0;
  const tr = tracks[ti], pos = tr.start + (t - sw);
  el.now.textContent = clock(pos); el.left.textContent = `-${clock(tr.length - pos)}`;
  el.fill.style.width = `${(pos / tr.length) * 100}%`;
  el.coverLg.style.transform = `scale(${1 + 0.12 * bump(t, cue.enter + 0.03, 0.35) + 0.08 * bump(t, cue.next, 0.3)})`;

  // Shimmer across the island when the song changes.
  const shimT = [cue.next, cue.enter + 0.03].map((s) => prog(t, s, 0.95)).find((p) => p > 0 && p < 1);
  el.shim.style.opacity = shimT == null ? 0 : Math.sin(Math.PI * shimT);
  el.shim.style.transform = `translateX(${shimT == null ? -100 : lerp(-100, 100, ease.inOut(shimT))}%)`;

  // Hover and press states under the pointer.
  const hotNext = t > 2.78 && t < 3.35;
  el.next.style.background = hotNext ? "rgba(255,255,255,.13)" : "transparent";
  el.next.style.transform = `scale(${1 - 0.16 * bump(t, cue.next, 0.16)})`;
  const hotEx = t > 5.58 && t < 5.9;
  el.expand.style.background = hotEx ? "rgba(255,255,255,.14)" : "transparent";
  el.expand.querySelector("svg").style.stroke = hotEx ? "#fff" : "";
  el.expand.style.transform = `scale(${1 - 0.18 * bump(t, cue.expand, 0.16)})`;
  el.shelf.forEach((p, i) => {
    const a = bump(t, cue.shelf[i] - 0.1, 0.34);
    p.querySelector(".cover").style.transform = `scale(${1 + 0.08 * a}) translateY(${-3 * a}px)`;
  });
  // Search: focus ring, typed letters, caret, results, Return.
  const focus = t >= cue.search;
  el.sIdle.style.boxShadow = focus ? "0 0 0 3px rgba(124,108,242,.4)" : "none";
  const n = cue.keys.filter((k2) => t >= k2).length;
  el.typed.textContent = "kyiv".slice(0, n);
  el.caret.style.opacity = (t - cue.search) % 0.6 < 0.36 || (t > cue.keys[0] && t < cue.results + 0.2) ? 1 : 0;
  el.sLive.style.boxShadow = "0 0 0 3px rgba(124,108,242,.4)";
  el.results.forEach((r, i) => {
    const a = ease.out(prog(t, cue.results + i * 0.06, 0.3));
    r.style.opacity = a; r.style.transform = `translateY(${(1 - a) * 12}px)`;
  });
  const pick = t > cue.enter - 0.02;
  el.first.style.background = pick ? "rgba(255,255,255,.18)" : "";
  const kbd = el.first.querySelector("kbd");
  kbd.style.background = pick ? "#F4EFFA" : ""; kbd.style.color = pick ? "#000" : "";
  kbd.style.transform = `scale(${1 + 0.15 * bump(t, cue.enter, 0.2)})`;

  // Timer, AirPods battery.
  el.cd.textContent = t < cue.timer + 0.5 ? "25:00" : "24:59";
  el.bb.style.width = `${82 * ease.out(prog(t, cue.airpods + 0.12, 0.6))}%`;
  [[".v-timer svg", cue.timer], [".cal", cue.meeting], [".v-airpods .pods", cue.airpods]].forEach(([s, at]) => {
    const k2 = prog(t, at + 0.08, 0.5);
    const node = $(s);
    node.style.transform = `scale(${lerp(0.4, 1, ease.back(k2))}) rotate(${(1 - ease.out(k2)) * -14}deg)`;
  });
  el.bars.forEach((b, i) => (b.style.transform = `scaleY(${barsAt(t, i % 4).toFixed(3)})`));
}

// ---------- camera ----------
// Keys: [t, fx, fy, scale, rotateX, rotateY, rotateZ, stageX, stageY]. (fx, fy) is the point on the Mac
// (lid coordinates) that the camera looks at; it lands on (stageX, stageY).
const CAM = [
  [0.0, 776, 30, 3.3, 9, -9, -1.2, 960, 470],
  [0.9, 776, 140, 1.9, 11, -15, -0.6, 990, 470],
  [1.85, 776, 380, 0.94, 12, -21, 0, 1080, 450],
  [2.55, 776, 225, 1.42, 7, -14, 0.3, 1130, 395],
  [3.5, 776, 238, 1.6, 5, -7, 0.4, 1150, 405],
  [4.6, 776, 252, 1.7, 4, 2, 0.2, 1150, 420],
  [5.6, 776, 262, 1.8, 3, 7, 0, 1125, 430],
  [6.05, 776, 511, 1.27, 0, 0, 0, 960, 540],
  [7.8, 776, 511, 1.355, 0, 0, 0.5, 960, 540],
  [8.55, 776, 560, 0.66, 13, 23, 0, 1040, 500],
  [9.75, 776, 560, 0.72, 10, 9, 0, 1060, 500],
  [10.07, 776, 36, 2.7, 7, -3, 0, 960, 300],
  [11.45, 776, 36, 2.86, 6, 3, 0, 960, 300],
  [11.9, 776, 560, 0.56, 15, 0, 0, 960, 645],
  [cue.push, 776, 560, 0.585, 14, 0, 0, 960, 645],
];
const cam = [1, 2, 3, 4, 5, 6, 7, 8].map((c) => track(CAM.map((k) => [k[0], k[c]]), { log: c === 3 }));
// The push into the notch accelerates all the way to the cut.
const PUSH_END = { fx: 776, fy: 20, s: 6, cx: 960, cy: 384 };
function camera(t) {
  if (t <= cue.push) return cam.map((f) => f(t));
  const last = cam.map((f) => f(cue.push));
  const k = ease.in(prog(t, cue.push, cue.logo - cue.push));
  const ks = Math.pow(prog(t, cue.push, cue.logo - cue.push), 2.4);
  return [
    lerp(last[0], PUSH_END.fx, k), lerp(last[1], PUSH_END.fy, ease.inOut(prog(t, cue.push, 0.3))),
    Math.exp(lerp(Math.log(last[2]), Math.log(PUSH_END.s), ks)),
    lerp(last[3], 0, ease.inOut(prog(t, cue.push, 0.3))), 0, 0, PUSH_END.cx, lerp(last[7], PUSH_END.cy, ease.inOut(prog(t, cue.push, 0.3))),
  ];
}

// ---------- frame ----------
function renderAt(t) {
  const pal = palette(t);
  stage.style.setProperty("--a1", pal[0]); stage.style.setProperty("--a2", pal[1]); stage.style.setProperty("--a3", pal[2]);
  const [fx, fy, s, rx, ry, rz, cx, cy] = camera(t);
  el.mac.style.transform = `translate(${cx}px,${cy}px) rotateZ(${rz}deg) rotateX(${rx}deg) rotateY(${ry}deg) scale(${s}) translate(${-fx}px,${-fy}px)`;

  // Far plane drifts against the Mac; near dust drifts the other way, faster.
  const drift = [[0.21, 0.17], [0.16, 0.23], [0.27, 0.13]];
  el.bg.forEach((b, i) => {
    const [a, c] = drift[i];
    b.style.transform = `translate(${-ry * (10 + i * 4) + Math.sin(t * a * 3 + i) * 40}px, ${rx * 9 + Math.cos(t * c * 3 + i) * 30}px) scale(${1 + 0.05 * Math.sin(t * 0.7 + i)})`;
  });
  const fgAmt = t < 5.8 ? 1 : t < 8.3 ? clamp(1 - prog(t, 5.8, 0.2) + prog(t, 8.1, 0.3)) : t < cue.logo ? 1 : 0.45;
  el.fg.forEach((d, i) => {
    const depth = 1.6 + (i % 3) * 0.7, size = 40 + ((i * 53) % 120);
    const x = ((i * 241 + 130) % 1920) + ry * depth * 22 + t * (8 + i * 3);
    const y = ((i * 397 + 90) % 1080) - rx * depth * 9 + Math.sin(t * 0.6 + i) * 20;
    d.style.cssText = `left:${x}px;top:${y}px;width:${size}px;height:${size}px;opacity:${(0.12 + (i % 4) * 0.05) * fgAmt};filter:blur(${4 + depth * 3}px)`;
  });

  // Desktop focus: when the camera is close to the island, the desktop behind it softens.
  const deskBlur = clamp((s - 1.05) / 0.6) * 7;
  el.desk.style.filter = deskBlur > 0.05 ? `blur(${deskBlur.toFixed(2)}px) brightness(${1 - deskBlur * 0.035})` : "none";
  const ti = trackAt(t);
  el.wt.textContent = tracks[ti].title; el.wa.textContent = `${tracks[ti].artist} · Single`;
  el.glare.style.transform = `translateX(${ry * 14 - 200}px)`;
  el.glare.style.opacity = t > 5.9 && t < 7.9 ? 0.3 : 1;

  paintIsland(t, pal);
  // The notch wakes: light leaks from under it before the wings appear.
  const wake = ease.out(prog(t, 0.05, 0.85)) * (1 - ease.inOut(prog(t, cue.compact, 1.1)));
  el.wake.style.opacity = wake.toFixed(3);
  el.wake.style.transform = `scale(${lerp(0.6, 1.15, ease.out(prog(t, 0, 1.4)))},${lerp(0.4, 1, ease.out(prog(t, 0, 1.2)))})`;
  el.fadein.style.opacity = (1 - ease.out(prog(t, 0, 0.45))).toFixed(3);
  el.fadein.style.display = t > 0.45 ? "none" : "";

  // Pointer on the Mac.
  const press = bump(t, cue.next - 0.02) + bump(t, cue.search - 0.02) + bump(t, cue.expand - 0.02);
  const cOp = clamp(prog(t, 0.9, 0.3)) * (1 - prog(t, cue.expand + 0.1, 0.12));
  el.cursor.style.opacity = cOp;
  el.cursor.style.display = cOp < 0.01 ? "none" : "";
  el.cursor.style.transform = `translate(${geo.cx(t)}px,${geo.cy(t)}px) scale(${1.05 - 0.14 * press})`;

  // Full-screen player blooms out of the island's cover, then the Mac locks.
  const bloom = ease.inOut(prog(t, cue.expand + 0.03, 0.32));
  const fsOut = prog(t, cue.lock, 0.18);
  el.fs.style.display = bloom <= 0 || fsOut >= 1 ? "none" : "";
  if (bloom > 0 && fsOut < 1) {
    el.fs.style.opacity = 1 - fsOut;
    const room = ease.out(prog(t, cue.expand + 0.05, 0.3));
    [el.fsbase, el.fsshade].forEach((n) => (n.style.opacity = room));
    el.mesh.forEach((m) => (m.style.opacity = ""));
    el.fs.querySelector(".mesh").style.opacity = room;
    el.fs.querySelector(".mesh").style.transform = `scale(${lerp(1.25, 1, ease.out(prog(t, cue.expand, 0.6)))})`;
    el.mesh.forEach((m, i) => {
      m.style.transform = `translate(${Math.sin(t * 0.8 + i * 2) * 80}px, ${Math.cos(t * 0.7 + i) * 60}px) scale(${1 + 0.1 * Math.sin(t * 1.1 + i * 1.3)})`;
    });
    const enter = ease.out(prog(t, cue.full - 0.1, 0.6));
    const breathe = 1 + 0.015 * Math.sin(((t - cue.full) / 2) * Math.PI * 2);
    // The island's cover grows into the big one (it starts exactly where the small one is).
    const [x0, y0, w0] = geo.cover, fk = ease.inOut(prog(t, cue.expand + 0.03, 0.42));
    el.fcover.style.transformOrigin = "0 0";
    el.fcover.style.transform = `translate(${lerp(x0 - 160, 0, fk)}px,${lerp(y0 - 230, 0, fk)}px) scale(${lerp(w0 / 380, 1, fk) * breathe})`;
    el.ftitle.style.opacity = enter; el.flabel.style.opacity = ease.out(prog(t, cue.full, 0.5));
    el.fprog.style.width = `${((61 + t - switches[2]) / 187) * 100}%`;
    const lineIdx = spring([[0, 0], ...lyrics.slice(1).map((l, i) => [l.start - 0.08, i + 1])], 11, 0.8)(t);
    el.lines.style.transform = `translateY(${(1 - lineIdx) * 104}px)`;
    const current = lyrics.reduce((c, l, i) => (t >= l.start - 0.08 ? i : c), 0);
    el.lineEls.forEach((line, li) => {
      const words = [...line.children];
      words.forEach((w, k) => {
        const p = li < current ? 1 : li > current ? 0 : ease.out(prog(t, lyrics[li].start + k * wordStep - 0.04, 0.2));
        const base = li === current ? 0.3 : li < current ? 0.42 : 0.24;
        w.style.opacity = lerp(base, 1, li === current ? p : 0).toFixed(3);
        w.style.transform = `translateY(${-4 * (li === current ? p : 0)}px)`;
        w.style.textShadow = li === current && p > 0 ? `0 0 ${28 * p}px rgba(255,255,255,${0.35 * p})` : "none";
      });
      line.style.opacity = li === current ? 1 : 0.85;
    });
    el.lines.parentElement.style.transform = `translateY(${(1 - enter) * 30}px)`;
    el.lines.parentElement.style.opacity = enter; el.ftitle.style.transform = `translateY(${(1 - enter) * 16}px)`;
  }
  el.dim.style.opacity = (0.75 * (ease.out(prog(t, cue.lock, 0.1)) - ease.inOut(prog(t, cue.lock + 0.11, 0.18)))).toFixed(3);

  const lockOn = t >= cue.lock && t < cue.unlock + 0.22;
  el.lock.style.display = lockOn ? "" : "none";
  if (lockOn) {
    el.lock.style.opacity = 1 - ease.inOut(prog(t, cue.unlock + 0.06, 0.1));
    const a = ease.out(prog(t, cue.lock + 0.12, 0.45)), b = prog(t, cue.lock + 0.22, 0.55);
    el.lclock.style.transform = `translateY(${(1 - a) * 40}px)`; el.lclock.style.opacity = a;
    el.ldate.style.opacity = a;
    el.card.style.transform = `translateY(${(1 - ease.back(b)) * 60}px) scale(${lerp(0.94, 1, ease.out(b))})`; el.card.style.opacity = clamp(b * 2);
    el.who.style.opacity = ease.out(prog(t, cue.lock + 0.4, 0.5));
    el.wave.forEach((bar, i) => {
      const beat = Math.exp(-((t % 0.5) * 6));
      const hgt = 0.18 + 0.55 * Math.abs(Math.sin(t * 3.1 + i * 0.55) * Math.cos(t * 1.7 + i * 0.23)) + 0.27 * beat * Math.abs(Math.sin(i * 0.9));
      bar.style.height = `${(hgt * 100).toFixed(1)}%`;
    });
    el.lprog.style.width = `${((61 + t - switches[2]) / 187) * 100}%`;
  }

  paintCaptions(t);

  // "Free." behind the Mac, the download button and a pointer in front of it.
  const free = t > cue.free && t < cue.logo + 0.05;
  const zoomK = t > cue.push ? s / cam[2](cue.push) : 1;
  const anchor = [960, 645 - (560 - 20) * cam[2](cue.push)];
  const zoomT = `translate(${anchor[0]}px,${anchor[1]}px) scale(${zoomK}) translate(${-anchor[0]}px,${-anchor[1]}px)`;
  const freeFade = 1 - prog(t, cue.push + 0.12, 0.16);
  el.free.style.display = free ? "" : "none";
  if (free) {
    el.free.style.transform = zoomT; el.free.style.opacity = freeFade;
    el.freeL.forEach((sp, i) => {
      const k = prog(t, cue.free + 0.1 + i * 0.045, 0.55);
      sp.style.transform = `translateY(${(1 - ease.out5(k)) * 140}px)`;
      sp.style.fontVariationSettings = `"wdth" ${lerp(62, 100, ease.out(k)).toFixed(1)}`;
      sp.style.opacity = clamp(k * 2.5);
    });
  }
  const dlOn = t > 11.6 && t < cue.logo + 0.05;
  el.dl.style.display = dlOn ? "" : "none";
  if (dlOn) {
    const a = prog(t, 11.66, 0.5);
    el.dl.style.transform = `${zoomT} translateY(${(1 - ease.back(a)) * 90}px) scale(${1 - 0.06 * bump(t, cue.download - 0.02, 0.16)})`;
    el.dl.style.opacity = clamp(a * 2.5) * freeFade;
    const f = ease.inOut(prog(t, cue.download + 0.02, 0.2));
    el.dlFill.style.transform = `translateX(${(f - 1) * 100}%)`;
    el.dl1.style.opacity = 1 - clamp(f * 2); el.dl2.style.opacity = clamp(f * 2 - 0.6);
    const pk = [[11.7, 1460, 1200], [11.98, 1035, 994], [cue.download + 0.12, 1040, 998], [cue.logo, 1050, 1004]];
    const px = track(pk.map((p) => [p[0], p[1]]))(t), py = track(pk.map((p) => [p[0], p[2]]))(t);
    el.pointer.style.transform = `${zoomT} translate(${px}px,${py}px) scale(${1.55 - 0.22 * bump(t, cue.download - 0.02)})`;
    el.pointer.style.opacity = clamp(prog(t, 11.7, 0.15)) * freeFade;
    el.pointer.style.display = "";
  } else el.pointer.style.display = "none";

  // End card: the notch in the "B" takes over from the island's notch.
  const endA = prog(t, cue.logo - 0.035, 0.07);
  el.end.style.display = endA <= 0 ? "none" : "";
  if (endA > 0) {
    el.end.style.opacity = endA;
    const kStart = (144 * PUSH_END.s) / 144, kEnd = 300 / 824;
    const k = Math.exp(Math.log(kEnd) + springStep(Math.log(kStart) - Math.log(kEnd), 0, Math.max(0, t - cue.logo), 9, 0.78)[0]);
    const settle = ease.out5(prog(t, cue.logo, 0.9));
    const ax = 960, ay = lerp(PUSH_END.cy, 380 - 250 * kEnd, settle) - 7 * ease.inOut(prog(t, 13.3, 1.7));
    const rot = (1 - settle) * -4;
    el.icon.style.transform = `translate(${ax}px,${ay}px) rotate(${rot}deg) scale(${k}) translate(-512px,-262px)`;
    const g = ease.out(prog(t, cue.logo + 0.05, 0.9));
    el.glow.style.opacity = g;
    el.glow.style.transform = `scale(${lerp(0.4, 1, g) * (1 + 0.05 * Math.sin((t - cue.logo) * 2.4))}) rotate(${(t - cue.logo) * 6}deg)`;
    el.word.forEach((sp, i) => {
      const kk = prog(t, cue.wordmark + i * 0.035, 0.6);
      sp.style.transform = `translateY(${(1 - ease.out5(kk)) * 110}%)`;
      sp.style.fontVariationSettings = `"wdth" ${lerp(62, 100, ease.out(kk)).toFixed(1)}`;
      sp.style.opacity = clamp(kk * 3);
    });
    const u = ease.out(prog(t, cue.url, 0.6));
    el.url.style.opacity = u; el.url.style.transform = `translateY(${(1 - u) * 24}px)`;
    el.url.style.letterSpacing = `${lerp(0.12, 0.01, u)}em`;
  }
  el.shade.style.opacity = t > cue.logo ? 0.6 : 1;
}

// ---------- boot ----------
async function boot() {
  await document.fonts.load('800 92px "Archivo"');
  await document.fonts.load('italic 300 92px "Archivo"');
  await document.fonts.load('600 15px "Geist"');
  await document.fonts.ready;
  measure();
  window.renderAt = renderAt;
  const q = new URLSearchParams(location.search);
  const fit = () => {
    const k = Math.min(innerWidth / 1920, innerHeight / 1080);
    stage.style.transform = k === 1 ? "" : `translate(${(innerWidth - 1920 * k) / 2}px,${(innerHeight - 1080 * k) / 2}px) scale(${k})`;
  };
  fit(); addEventListener("resize", fit);
  renderAt(q.has("t") ? parseFloat(q.get("t")) : 0);
  if (q.has("play")) {
    const audio = new Audio("out/audio.wav");
    const start = () => { audio.currentTime = 0; audio.play().catch(() => {}); };
    addEventListener("click", start);
    start();
    const loop = () => { renderAt(Math.min(audio.currentTime, DURATION - 1 / 60)); requestAnimationFrame(loop); };
    loop();
  }
  window.ready = true;
}
boot();

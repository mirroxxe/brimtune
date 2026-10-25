// Brimtune — promo (v2, 38 s). One function, renderAt(t), sets every frame from the time alone,
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
const bump = (t, at, len = 0.14) => { const k = (t - at) / len; return k < 0 || k > 1 ? 0 : Math.sin(Math.PI * k); };
const win = (t, a, b, fin = 0.3, fout = 0.25) => Math.min(ease.out(prog(t, a, fin)), 1 - ease.inOut(prog(t, b, fout)));

// Monotone cubic through [time, value] keys: smooth, continuous speed, never overshoots a key.
function track(keys, { log = false } = {}) {
  const ts = keys.map((k) => k[0]);
  const vs = keys.map((k) => (log ? Math.log(k[1]) : k[1]));
  const n = ts.length, d = [], m = new Array(n).fill(0);
  for (let i = 0; i < n - 1; i++) d[i] = (vs[i + 1] - vs[i]) / (ts[i + 1] - ts[i]);
  for (let i = 1; i < n - 1; i++) {
    if (d[i - 1] * d[i] <= 0) continue;
    const h0 = ts[i] - ts[i - 1], h1 = ts[i + 1] - ts[i];
    const w1 = 2 * h1 + h0, w2 = h1 + 2 * h0;
    m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]);
  }
  return (t) => {
    let v;
    if (t <= ts[0]) v = vs[0];
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
  return [e * (x0 * c + B * s), e * (-a * (x0 * c + B * s) + (-x0 * wd * s + B * wd * c))];
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
const show = (node, on) => { node.style.display = on ? "" : "none"; return on; };

// ---------- content (all made up) ----------
const tracks = [
  { title: "Night Bus Home", artist: "Lumen Field", length: 202, start: 68, colors: ["#F2648E", "#7C6CF2", "#FFAE57"] },
  { title: "Paper Moons", artist: "Orla Vey", length: 228, start: 0, colors: ["#3FB6C9", "#4B5BD6", "#C8F08F"] },
  { title: "Kyiv, 5 a.m.", artist: "Teo Brann", length: 187, start: 52, colors: ["#FF8A4C", "#C2367A", "#FFD36E"] },
];
const switches = [0, cue.peek, cue.enter + 0.03];
const trackAt = (t) => (t < switches[1] ? 0 : t < switches[2] ? 1 : 2);
const posAt = (t) => { const i = trackAt(t); return tracks[i].start + (t - switches[i]); };
function palette(t) {
  const P = tracks.map((x) => x.colors);
  const blend = (A, B, k) => A.map((c, i) => mix(c, B[i], ease.inOut(k)));
  if (t < cue.peek) return blend(P[0], P[0], 0);
  if (t < cue.enter) return blend(P[0], P[1], prog(t, cue.peek, 0.8));
  if (t < cue.stats - 0.3) return blend(P[1], P[2], prog(t, cue.enter, 0.7));
  return blend(P[2], P[0], prog(t, cue.stats - 0.3, 0.6));
}
const clock = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
const covers = { night: ["#F2648E", "#7C1F4F", "#FFC0D3"], focus: ["#3FB6C9", "#1E3C8C", "#C8F08F"], kyiv: ["#FF8A4C", "#C2367A", "#FFD36E"], liked: ["#7C6CF2", "#241D5C", "#B6F0E4"], late: ["#9B8CF2", "#2E2A6B", "#E9D7FF"], sunday: ["#FFD36E", "#E2683C", "#FFF1C9"] };
const cv = (c) => `--c1:${c[0]};--c2:${c[1]};--c3:${c[2]}`;

// ---------- DOM ----------
const I = {
  prev: '<svg viewBox="0 0 24 24"><path d="M11 7v10l-7-5zm9 0v10l-7-5z"/></svg>',
  pause: '<svg viewBox="0 0 24 24"><path d="M7 5h3.5v14H7zm6.5 0H17v14h-3.5z"/></svg>',
  play: '<svg viewBox="0 0 24 24"><path d="M8 5l11 7-11 7z"/></svg>',
  next: '<svg viewBox="0 0 24 24"><path d="M13 7v10l7-5zm-9 0v10l7-5z"/></svg>',
  expand: '<svg viewBox="0 0 24 24"><path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/></svg>',
  search: '<svg viewBox="0 0 24 24"><path d="M10 3a7 7 0 1 0 4.2 12.6l5.1 5.1 1.4-1.4-5.1-5.1A7 7 0 0 0 10 3zm0 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10z"/></svg>',
  chevR: '<svg class="chev" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>',
  chevD: '<svg class="chev" viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></svg>',
  timer: '<svg viewBox="0 0 24 24"><path d="M9 2h6v2H9zm3 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16zm1 8.6V9h-2v6.4l4.2 2.5 1-1.7z"/></svg>',
  pods: '<svg class="ai pods" viewBox="0 0 24 24"><path d="M6.5 3A3.5 3.5 0 0 0 3 6.5c0 1.6 1 2.9 2.5 3.3V19a1.5 1.5 0 0 0 3 0V6.5A3.5 3.5 0 0 0 6.5 3zm11 0A3.5 3.5 0 0 0 14 6.5V19a1.5 1.5 0 0 0 3 0V9.8c1.5-.4 2.5-1.7 2.5-3.3A3.5 3.5 0 0 0 17.5 3z"/></svg>',
  pointer: '<path d="M1 1 L1 25 L7 19.2 L11.2 28.6 L15.4 26.8 L11.3 17.6 L19.6 17.6 Z" fill="#000" stroke="#fff" stroke-width="1.8" stroke-linejoin="round"/>',
  phones: '<svg viewBox="0 0 24 24" class="ln"><path d="M4 15v-3a8 8 0 0 1 16 0v3"/><rect x="3.5" y="14" width="4" height="6" rx="1.5"/><rect x="16.5" y="14" width="4" height="6" rx="1.5"/></svg>',
  shuffle: '<svg viewBox="0 0 24 24" class="ln"><path d="M3 7h3.5c4 0 6 10 10 10H21M3 17h3.5c1.6 0 2.8-1.6 3.9-3.6M13.6 9.6C14.7 8.2 15.6 7 17 7h4M18 4l3 3-3 3M18 14l3 3-3 3"/></svg>',
  xmark: '<svg viewBox="0 0 24 24" class="ln"><path d="M6 6l12 12M18 6L6 18"/></svg>',
  quote: '<svg viewBox="0 0 24 24"><path d="M4 4h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-8l-5 4v-4H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zm4 4.5a1.6 1.6 0 0 0-1.6 1.6c0 .9.7 1.5 1.5 1.5-.1.8-.5 1.3-1.2 1.7l.6.8c1.6-.8 2.4-2 2.4-3.6 0-1.2-.7-2-1.7-2zm6 0a1.6 1.6 0 0 0-1.6 1.6c0 .9.7 1.5 1.5 1.5-.1.8-.5 1.3-1.2 1.7l.6.8c1.6-.8 2.4-2 2.4-3.6 0-1.2-.7-2-1.7-2z"/></svg>',
  history: '<svg viewBox="0 0 24 24" class="ln"><path d="M4 12a8 8 0 1 0 2.4-5.7M4 4v4h4M12 8v4.5l3 2"/></svg>',
  gear: '<svg viewBox="0 0 24 24" class="ln"><circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7"/></svg>',
  note: '<svg viewBox="0 0 24 24"><path d="M9 17.5V6l11-2.5v11.5a2.8 2.8 0 1 1-2-2.7V7.3L11 8.9v8.6a2.8 2.8 0 1 1-2-2.7z"/></svg>',
  down: '<svg viewBox="0 0 24 24" class="ln"><path d="M12 4v11M7 10.5l5 5 5-5M5 20h14"/></svg>',
  check: '<svg viewBox="0 0 24 24" class="ln"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
  cpu: '<svg viewBox="0 0 24 24" class="ln"><rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/></svg>',
  mem: '<svg viewBox="0 0 24 24" class="ln"><rect x="3" y="7" width="18" height="10" rx="2"/><path d="M7 17v3M11 17v3M15 17v3M7 10.5h2M11 10.5h2M15 10.5h2"/></svg>',
};
const barsHTML = (n = 4) => `<span class="bars">${"<i></i>".repeat(n)}</span>`;
const pl = (name, c) => `<span class="pl"><span class="cover" style="${cv(c)}"></span><small>${name}</small></span>`;
const row = (title, sub, c, extra = "", cls = "result") =>
  `<div class="${cls}"><span class="cover cover-row" style="${cv(c)}"></span><span><strong>${title}</strong><small>${sub}</small></span>${extra}</div>`;
const iconSVG = (id) => `
<svg class="bicon" id="${id}" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs><linearGradient id="sq-${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#17141C"/><stop offset="1" stop-color="#08080A"/></linearGradient></defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#sq-${id})" stroke="rgba(255,255,255,.08)" stroke-width="3"/>
  <path fill="#ECE7DE" fill-rule="evenodd" d="M262 762 L652 762 A110 110 0 0 0 762 652 L762 542 L608 512 L732 482 L732 352 A90 90 0 0 0 642 262 L584 262 L584 280 A24 24 0 0 1 560 304 L464 304 A24 24 0 0 1 440 280 L440 262 L262 262 Z
    M572 404 a52 52 0 1 0 -104 0 a52 52 0 1 0 104 0 Z M612 636 a92 92 0 1 0 -184 0 a92 92 0 1 0 184 0 Z"/>
  <circle cx="520" cy="404" r="16" fill="#ECE7DE"/><circle cx="520" cy="636" r="30" fill="#F2648E"/>
</svg>`;
const words = (text) => text.split(" ").map((w) => `<span class="w">${w}</span>`).join(" ");
const maskWords = (list) => list.map((w) => `<span class="word"><span>${w}</span></span>`).join("");

// The app's stage (full screen and lock screen): cover, glass player card, tabs, panels.
const queue = [["Glasshouse", "Mira Sol", covers.liked, "4:01"], ["Late Trams", "Orla Vey", covers.late, "2:54"], ["Orange Hour", "Lumen Field", covers.night, "3:30"], ["Harbour Lights", "Teo Brann", covers.focus, "3:12"], ["Sunday Static", "Mira Sol", covers.sunday, "3:41"]];
const lists = [["Night drive", covers.night], ["Focus", covers.focus], ["Kyiv mornings", covers.kyiv], ["Liked music", covers.liked], ["Late", covers.late], ["Sunday", covers.sunday]];
const stageHTML = (cls) => `
  <div class="sp ${cls}">
    <span class="cover sp-art"></span>
    <div class="pcard glass">
      <div class="pc-top"><div class="pc-t"><strong>Kyiv, 5 a.m.</strong><span>Teo Brann</span></div>${barsHTML(5)}</div>
      <div class="pc-prog"><span class="pc-now">0:52</span><span class="bar"><span class="fill"></span></span><span class="pc-left">-2:15</span></div>
      <div class="pc-ctl"><span class="sm">${I.shuffle}</span><span class="tc">${I.prev}${I.pause}${I.next}</span><span class="sm">${I.phones}</span></div>
    </div>
    <div class="sp-col">
      <div class="tabs glass"><i class="tabsel"></i><span class="tab">Lyrics</span><span class="tab">Up Next</span><span class="tab">Playlists</span></div>
      <div class="pane p-lyr"><div class="lines">${lyrics.map((l) => `<div class="line">${words(l.text)}</div>`).join("")}</div></div>
      <div class="pane p-q"><div class="qh">Up Next</div>${queue.map(([a, b, c, d]) => row(a, b, c, `<em>${d}</em>`, "qrow")).join("")}</div>
      <div class="pane p-pl"><div class="grid">${lists.map(([n, c]) => `<div class="gcard"><span class="cover" style="${cv(c)}"></span><small>${n}</small></div>`).join("")}</div></div>
    </div>
  </div>`;

const stage = document.getElementById("stage");
stage.innerHTML = `
  <div id="bg"><i class="b1"></i><i class="b2"></i><i class="b3"></i></div>
  <div id="floor"></div>
  <div id="world"><div id="rig">
    <div id="mac">
      <div id="base"><div class="kb"></div><div class="pad"></div><div id="front"></div></div>
      <div id="lid"><div id="screen">
        <div id="desk">
          <div class="wall"><i class="w1"></i><i class="w2"></i><i class="w3"></i><i class="w4"></i></div>
          <div class="win yt">
            <div class="tb"><b></b><b></b><b></b><span class="tabx"><span class="fav">${I.note}</span>YouTube Music</span><span class="tabx dim">Docs</span></div>
            <div class="urlbar"><span class="url">music.youtube.com/watch?v=pm-24</span></div>
            <div class="side"><b>Home</b><br>Explore<br>Library<br><span class="mute">Playlists</span><br>Night drive<br>Focus<br>Late</div>
            <div class="main"><h4>Your mix</h4>
              <div class="rows">${[["Night Bus Home", "Lumen Field", covers.night, "3:22"], ["Paper Moons", "Orla Vey", covers.focus, "3:48"], ["Glasshouse", "Mira Sol", covers.liked, "4:01"], ["Late Trams", "Orla Vey", covers.late, "2:54"], ["Kyiv, 5 a.m.", "Teo Brann", covers.kyiv, "3:07"]].map(([n, a, c, d], i) => `<div class="r r${i}"><span class="cover" style="${cv(c)}"></span><span class="pb">${I.play}</span><span class="nm"><b>${n}</b><small>${a}</small></span><span class="du">${d}</span></div>`).join("")}</div></div>
            <div class="pbar"><span class="cover pbc"></span><span class="nm"><b class="pbt">Night Bus Home</b><small class="pba">Lumen Field</small></span><span class="tc">${I.prev}${I.pause}${I.next}</span><span class="bar"><span class="fill"></span></span></div>
          </div>
        </div>
        <div id="menubar"><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span>
          <span class="r"><span class="mini"></span><svg viewBox="0 0 24 24"><path d="M12 18.5a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2zM5.6 13.4a9 9 0 0 1 12.8 0l-1.6 1.6a6.8 6.8 0 0 0-9.6 0zM2.4 10.2a13.5 13.5 0 0 1 19.2 0L20 11.8a11.3 11.3 0 0 0-16 0z"/></svg><span>Sat Oct 25&nbsp; 9:41</span></span></div>
        <div id="lock">
          <div class="wall"><i class="w1"></i><i class="w2"></i><i class="w3"></i><i class="w4"></i></div>
          <div class="date">Saturday, October 25</div><div class="clock">9:41</div>
          ${stageHTML("lk")}
          <div class="who"><b></b>Touch ID or Enter Password</div>
        </div>
        <div id="island"><span class="fl l"></span><span class="fl r"></span><div class="body">
          <div class="view v-compact"><span class="cover cover-sm"></span>${barsHTML()}</div>
          <div class="view v-peek"><div class="pk-row"><span class="cover cover-pk"></span>${barsHTML()}</div><div class="pk-text"><strong>Paper Moons</strong><span>Orla Vey</span></div></div>
          <div class="view v-timer"><span class="cover cover-sm"></span><span class="badge">${I.timer}<b class="cd">25:00</b></span></div>
          <div class="view v-alert v-meeting"><span class="ai cal">25</span><span class="at"><small>In 5 minutes</small><strong>Design review</strong></span><span class="join">Join</span></div>
          <div class="view v-alert v-airpods">${I.pods}<span class="at"><small>Connected</small><strong>AirPods Pro</strong></span><span class="batt"><span class="bb"><span></span></span><b>82%</b></span></div>
          <div class="view v-open"><div class="vi">
            <div class="player">
              <div class="prow"><span class="cover cover-lg"></span><div class="meta"><div class="t ta"><strong></strong><span></span></div><div class="t tb"><strong></strong><span></span></div></div>${barsHTML()}</div>
              <div class="progress"><span class="now">1:08</span><span class="bar"><span class="fill"></span></span><span class="left">-2:14</span></div>
              <div class="controls"><span class="ctl">${I.prev}</span><span class="ctl play">${I.pause}</span><span class="ctl">${I.next}</span><span class="expand">${I.expand}</span></div>
              <div class="volume"><svg viewBox="0 0 24 24" class="spk"><path d="M3 9.5v5h3.6L12 19V5L6.6 9.5z"/><path class="w" d="M15.2 9.6a3.4 3.4 0 0 1 0 4.8"/><path class="w" d="M17.6 7.4a6.6 6.6 0 0 1 0 9.2"/><path class="w" d="M19.8 5.2a9.8 9.8 0 0 1 0 13.6"/></svg><span class="vtrack"><i class="vfill"></i><i class="vthumb"><b class="vbub">62</b></i></span></div>
            </div>
            <div class="lower">
              <div class="lo-x">
                <div class="search s-idle">${I.search}<span class="ph">Search for a song</span></div>
                <div class="xrow"><span class="xtitle">Up Next</span><span class="chip">10</span>${I.chevR}</div>
                <div class="xrow"><span class="xtitle">Playlists</span>${I.chevD}</div>
                <div class="shelf">${pl("Night drive", covers.night)}${pl("Focus", covers.focus)}${pl("Kyiv mornings", covers.kyiv)}${pl("Liked music", covers.liked)}${pl("Late", covers.late)}</div>
              </div>
              <div class="lo-s">
                <div class="search s-live">${I.search}<span class="typed"></span><span class="caret"></span></div>
                <div class="results">${row("Kyiv, 5 a.m.", "Teo Brann · 3:07", covers.kyiv, "<kbd>Return</kbd>", "result first")}${row("Kyiv mornings", "Playlist · 42 songs", covers.night)}${row("Kyiv Lights", "Mira Sol · 2:56", covers.liked)}</div>
              </div>
            </div>
          </div></div>
          <div class="shim"></div>
        </div></div>
        <div id="fs">
          <div class="fsbase"></div><div class="mesh"><i class="m1"></i><i class="m2"></i><i class="m3"></i><i class="m4"></i></div><div class="shade"></div>
          <div class="fclock"><div class="fdate">Sat, Oct 25</div><div class="ftime">9:41</div></div>
          <div class="sidebar glass"><span>${I.xmark}</span><span class="on">${I.quote}</span><span>${I.history}</span><span>${I.gear}</span></div>
          ${stageHTML("fsp")}
        </div>
        <i id="beam"></i>
        <svg id="cursor" viewBox="0 0 26 34">${I.pointer}</svg>
        <div id="glare"></div><div id="dim"></div>
      </div></div>
    </div>
    <div id="mon">
      <div class="neck"></div><div class="foot"></div>
      <div class="panel"><div class="mscreen">
        <div class="wall"><i class="w1"></i><i class="w2"></i><i class="w3"></i><i class="w4"></i></div>
        <div class="mbar"><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span class="r">Sat Oct 25&nbsp; 9:41</span></div>
        <div class="mwin"><div class="tb"><b></b><b></b><b></b></div><div class="doc"><i></i><i></i><i></i><i class="s"></i><i></i><i class="s"></i></div></div>
        <div class="mpill"><span class="cover cover-sm"></span><span class="mt">Kyiv, 5 a.m.</span>${barsHTML()}</div>
      </div></div>
    </div>
  </div></div>
  <div id="fg">${"<i></i>".repeat(9)}</div>
  <div id="shade"></div>
  <div id="chips">${["YouTube Music", "Spotify", "Apple Music", "Safari", "Chrome"].map((c, i) => `<span class="cp${i ? "" : " lead"}">${c}</span>`).join("")}</div>
  <div id="cap"></div>

  <div id="hook" class="card">
    <div class="edge"></div>
    <div class="hisl"><span class="fl l"></span><span class="fl r"></span><span class="cover cover-sm"></span>${barsHTML()}</div>
    <div class="hl h1">${maskWords(["Your", "Mac", "has", "a", "notch."])}</div>
    <div class="hl h2">${maskWords(["What", "if", "it", "played", "<em>your</em>", "<em>music?</em>"])}</div>
    <div class="meet"><span class="mw m-l"><span>Meet</span></span>${iconSVG("micon")}<span class="mw m-r"><span>Brimtune.</span></span></div>
  </div>

  <div id="stats" class="card">
    <div class="sh">${maskWords(["Barely", "<em>there.</em>"])}</div>
    <div class="cols">
      <div class="col"><div class="lab">${I.cpu}CPU</div><div class="num"><b class="n1">0.0</b><small>%</small></div><svg class="spark" viewBox="0 0 600 90"><path class="sp1" d=""/></svg></div>
      <div class="col"><div class="lab">${I.mem}Memory</div><div class="num"><b class="n2">0</b><small>MB</small></div><svg class="spark" viewBox="0 0 600 90"><path class="sp2" d=""/></svg></div>
    </div>
    <div class="fine">About 1.5% CPU and 36 MB, measured with music paused.</div>
  </div>

  <div id="bento" class="card">
    <div class="bh">${maskWords(["Everything,", "<em>in</em>", "<em>your</em>", "<em>notch.</em>"])}</div>
    <div class="grid3d"><div class="tiles">
      <div class="tile t0"><small>Lyrics, word by word</small><div class="tl-l"><span class="w">the</span> <span class="w">city</span> <span class="w">wakes</span> <span class="w">in</span> <span class="w">amber</span> <span class="w">light</span></div></div>
      <div class="tile t1"><small>Player in the notch</small><div class="mini-isl"><span class="cover"></span><div><b>Kyiv, 5 a.m.</b><i>Teo Brann</i></div>${barsHTML()}<span class="mbarx"><span></span></span></div></div>
      <div class="tile t2"><small>Lock screen</small><div class="mini-lock"><b>9:41</b><div class="mlc glass"><span class="cover"></span><span><strong>Kyiv, 5 a.m.</strong><i>Teo Brann</i></span>${barsHTML(5)}</div></div></div>
      <div class="tile t3"><small>Timers & meetings</small><div class="mini-pill amber">${I.timer}<b class="bcd">24:59</b></div><div class="mini-pill"><span class="cal sm">25</span><b>Design review</b><span class="join">Join</span></div></div>
      <div class="tile t4"><small>Every display</small><div class="mini-mon"><i></i></div><div class="mini-mon m2"><i></i></div></div>
      <div class="tile t5"><small>History</small><div class="hist">${[["Kyiv, 5 a.m.", "Teo Brann", covers.kyiv, "now"], ["Paper Moons", "Orla Vey", covers.focus, "2 min"], ["Night Bus Home", "Lumen Field", covers.night, "6 min"]].map(([a, b, c, d]) => `<div><span class="cover" style="${cv(c)}"></span><span><strong>${a}</strong><small>${b}</small></span><em>${d}</em></div>`).join("")}</div></div>
    </div></div>
  </div>

  <div id="offer" class="card">
    <div class="ofree">${"Free.".split("").map((c) => `<span>${c}</span>`).join("")}</div>
    <div class="oopen">${maskWords(["<em>Open</em>", "<em>source.</em>"])}</div>
    <div class="ochip"><span class="gpl">GPL-3.0</span>github.com/mirroxxe/brimtune</div>
    <div id="dl"><div class="fillx"></div><div class="lab l1">${I.down}Download free at <b>brimtune.pages.dev</b></div><div class="lab l2">${I.check}Brimtune.dmg</div></div>
    <svg id="pointer" viewBox="0 0 26 34">${I.pointer}</svg>
  </div>

  <div id="end" class="card"><div class="glow"><i class="g1"></i><i class="g2"></i><i class="g3"></i></div>${iconSVG("icon")}
    <div id="word">${"Brimtune".split("").map((c) => `<span class="word"><span>${c}</span></span>`).join("")}</div>
    <div id="url"><b>brimtune</b>.pages.dev</div>
    <div id="badges"><span>Free</span><span>Open source</span><span>macOS 14+</span></div></div>
  <div id="fadein"></div>
`;

const $ = (s, root = stage) => root.querySelector(s);
const $$ = (s, root = stage) => [...root.querySelectorAll(s)];
const el = {
  bg: $("#bg"), bgI: $$("#bg i"), floor: $("#floor"), fgBox: $("#fg"), world: $("#world"), rig: $("#rig"), mon: $("#mon"), desk: $("#desk"), screen: $("#screen"),
  island: $("#island"), compact: $(".v-compact"), peek: $(".v-peek"), timer: $(".v-timer"), meeting: $(".v-meeting"), airpods: $(".v-airpods"), open: $(".v-open"),
  loX: $(".lo-x"), loS: $(".lo-s"), lower: $(".lower"), shim: $(".shim"), metaA: $(".ta"), metaB: $(".tb"), coverLg: $(".cover-lg"),
  now: $(".progress .now"), left: $(".progress .left"), fill: $(".progress .fill"), expand: $(".expand"),
  vol: $(".volume"), vtrack: $(".vtrack"), vfill: $(".vfill"), vthumb: $(".vthumb"), vbub: $(".vbub"), vw: $$(".spk .w"),
  sIdle: $(".s-idle"), sLive: $(".s-live"), typed: $(".typed"), caret: $(".caret"), results: $$(".result"), first: $(".result.first"),
  shelf: $$(".shelf .pl"), bars: $$(".bars i"), cd: $(".cd"), bb: $(".bb span"), pkText: $(".pk-text"),
  yrows: $$(".win .r"), ypbt: $(".pbt"), ypba: $(".pba"), ypbc: $(".pbc"), ypfill: $(".pbar .fill"),
  fs: $("#fs"), fsbase: $("#fs .fsbase"), fsshade: $("#fs .shade"), fsmesh: $("#fs .mesh"), mesh: $$("#fs .mesh i"), fclock: $(".fclock"), sidebar: $(".sidebar"),
  lock: $("#lock"), lclock: $("#lock .clock"), ldate: $("#lock .date"), who: $("#lock .who"),
  beam: $("#beam"), cursor: $("#cursor"), glare: $("#glare"), dim: $("#dim"), fg: $$("#fg i"), cap: $("#cap"), shade: $("#shade"), chips: $$("#chips .cp"),
  mpill: $(".mpill"),
  hook: $("#hook"), hisl: $(".hisl"), h1: $$(".h1 .word > span"), h2: $$(".h2 .word > span"), h1n: $(".h1"), h2n: $(".h2"), meet: $(".meet"), micon: $("#micon"), mL: $(".m-l > span"), mR: $(".m-r > span"), edge: $(".edge"),
  stats: $("#stats"), sh: $$(".sh .word > span"), n1: $(".n1"), n2: $(".n2"), sp1: $(".sp1"), sp2: $(".sp2"), cols: $$("#stats .col"), fine: $("#stats .fine"),
  bento: $("#bento"), bhN: $(".bh"), bh: $$(".bh .word > span"), grid3d: $(".grid3d"), tiles: $$(".tile"), tlw: $$(".tl-l .w"), bcd: $(".bcd"),
  offer: $("#offer"), ofree: $$(".ofree span"), oopen: $$(".oopen .word > span"), ochip: $(".ochip"),
  dl: $("#dl"), dlFill: $("#dl .fillx"), dl1: $("#dl .l1"), dl2: $("#dl .l2"), pointer: $("#pointer"),
  end: $("#end"), icon: $("#icon"), glow: $("#end .glow"), word: $$("#word .word span"), url: $("#url"), badges: $$("#badges span"),
  fadein: $("#fadein"),
};
const sp = { fs: $(".fsp"), lk: $(".lk") };
const spGeo = {};

// ---------- captions ----------
const captions = [
  { w: ["Hover.", "*It plays.*"], at: 7.6, out: 8.45 },
  { w: ["Volume,", "*right there.*"], at: 8.6, out: 9.85 },
  { w: ["Works", "with", "*YouTube Music.*"], at: 10.65, out: 12.3 },
  { w: ["Search.", "*Playlists.*", "Up Next."], at: 12.6, times: [12.6, 12.68, 14.15], out: 15.3 },
  { w: ["Lyrics,", "*word by word.*"], at: 16.15, out: 17.85 },
  { w: ["Up Next.", "*Playlists.*"], at: cue.tabQueue + 0.05, times: [cue.tabQueue + 0.05, cue.tabLists + 0.05], out: 19.7 },
  { w: ["Even", "on", "your", "*lock screen.*"], at: 20.25, out: 21.7 },
  { w: ["Timers.", "Meetings.", "*AirPods.*"], at: cue.timer + 0.04, times: [cue.timer + 0.04, cue.meeting + 0.04, cue.airpods + 0.04], out: 23.45 },
  { w: ["Every", "display.", "*Notch or not.*"], at: cue.pill + 0.05, out: 25.7 },
].map((c) => {
  const node = document.createElement("div");
  node.className = "capline";
  node.innerHTML = maskWords(c.w.map((w) => (w.startsWith("*") ? `<em>${w.replace(/\*/g, "")}</em>` : w)));
  el.cap.append(node);
  return { ...c, node, spans: [...node.querySelectorAll(".word > span")] };
});
// Words rise through a mask and widen from condensed as they land.
function rise(spans, t, times, { len = 0.5, y = 105 } = {}) {
  spans.forEach((s, i) => {
    const k = prog(t, times[i], len);
    s.style.transform = `translateY(${(1 - ease.out5(k)) * y}%)`;
    s.style.fontVariationSettings = `"wdth" ${lerp(62, 100, ease.out(k)).toFixed(1)}`;
    s.style.opacity = clamp(k * 3);
  });
}
function exitStyle(node, t, out, len = 0.26) {
  const x = ease.inOut(prog(t, out, len));
  node.style.opacity = 1 - x;
  node.style.transform = `translateY(${-26 * x}px)`;
  node.style.filter = x > 0 ? `blur(${x * 10}px)` : "none";
}
function paintCaptions(t) {
  for (const c of captions) {
    if (!show(c.node, t > c.at - 0.05 && t < c.out + 0.3)) continue;
    exitStyle(c.node, t, c.out);
    rise(c.spans, t, c.times ?? c.spans.map((_, i) => c.at + i * 0.075));
  }
}

// ---------- island ----------
const S = [
  [0, "notch"], [cue.compact, "compact"], [cue.open, "open"], [cue.leave, "compact"], [cue.peek, "peek"], [12.15, "compact"],
  [cue.reopen, "open"], [cue.search, "search"], [cue.enter + 0.03, "open"], [cue.expand + 0.05, "compact"],
  [cue.timer, "timer"], [cue.meeting, "meeting"], [cue.airpods, "airpods"], [23.5, "compact"],
];
const intervals = (name) => S.map(([s, n], i) => (n === name ? [s, S[i + 1]?.[0] ?? null] : null)).filter(Boolean);
const iv = Object.fromEntries(["compact", "peek", "timer", "meeting", "airpods", "open", "search"].map((n) => [n, intervals(n)]));
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

let geo;
function localPos(node, root, fx = 0.5, fy = 0.5) {
  let x = 0, y = 0, n = node;
  while (n && n !== root) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; }
  return [x + node.offsetWidth * fx, y + node.offsetHeight * fy];
}
function measure() {
  const isl = el.island;
  isl.style.width = "412px"; isl.style.left = `${756 - 206}px`; isl.style.height = "640px";
  const vi = $(".vi", el.open);
  el.loX.style.position = "static"; const hOpen = vi.offsetHeight;
  el.loX.style.position = ""; el.loS.style.position = "static"; const hSearch = vi.offsetHeight;
  el.loS.style.position = "";
  el.lower.style.height = `${Math.max(el.loX.offsetHeight, el.loS.offsetHeight)}px`;
  const at = (node, fx, fy) => localPos(node, el.screen, fx, fy);
  geo = {
    sizes: { notch: [144, 42, 22], compact: [292, 32, 12], peek: [382, 82, 24], timer: [336, 32, 12], meeting: [392, 84, 28], airpods: [392, 84, 28], open: [412, hOpen, 34], search: [412, hSearch, 34] },
    search: at(el.sIdle, 0.3, 0.55), expand: at(el.expand), shelf: el.shelf.map((p) => at($(".cover", p))),
    cover: (() => { const [x, y] = at(el.coverLg, 0, 0); return [x, y, 58]; })(),
    vt: (() => { const [x, y] = at(el.vtrack, 0, 0.5); return [x, y, el.vtrack.offsetWidth]; })(),
    row: at($(".r1 .pb"), 0.5, 0.5),
  };
  ["w", "h", "r"].forEach((k, j) => (geo[k] = spring(S.map(([s, n]) => [s, geo.sizes[n][j]]))));
  // Stage panels: lyric line tops for scrolling, tab positions for the selector.
  for (const [key, node] of Object.entries(sp)) {
    $$(".pane", node).forEach((p) => (p.style.display = ""));
    spGeo[key] = { tops: $$(".line", node).map((l) => l.offsetTop), tabs: $$(".tab", node).map((tb) => [tb.offsetLeft, tb.offsetWidth]) };
  }
  geo.tabQ = at($$(".fsp .tab")[1], 0.5, 0.55); geo.tabPl = at($$(".fsp .tab")[2], 0.5, 0.55);
  geo.fsArt = at($(".fsp .sp-art"), 0, 0);
  const [vx, vy, vw] = geo.vt, [rx, ry] = geo.row, [sx, sy] = geo.search, [ex, ey] = geo.expand, sh = geo.shelf;
  const v62 = vx + 7 + (vw - 14) * 0.62, v88 = vx + 7 + (vw - 14) * 0.88;
  geo.cursorSegs = [
    { from: 6.3, to: cue.expand + 0.22, keys: [[6.3, 1360, 1010], [7.0, 1010, 300], [cue.hover, 812, 20], [7.95, 840, 170], [8.62, v62, vy + 3], [cue.volume[0], v62, vy], [cue.volume[1], v88, vy], [9.75, v88 + 6, vy + 6],
      [10.25, rx + 20, ry - 10], [cue.play - 0.05, rx, ry], [11.6, rx + 60, ry + 40], [12.3, 800, 22], [cue.search - 0.1, sx, sy], [13.45, sx + 16, sy + 12],
      [14.0, sh[0][0] - 20, sh[0][1] - 40], [cue.shelf[0], sh[0][0], sh[0][1]], [cue.shelf[1], sh[1][0], sh[1][1]], [cue.shelf[2], sh[2][0], sh[2][1] - 6], [cue.expand - 0.08, ex, ey], [16, ex + 4, ey + 3]] },
    { from: 17.35, to: 19.55, keys: [[17.35, 1240, 760], [cue.tabQueue - 0.06, ...geo.tabQ], [18.3, geo.tabQ[0] + 10, geo.tabQ[1] + 14], [cue.tabLists - 0.06, ...geo.tabPl], [19.6, geo.tabPl[0] + 40, geo.tabPl[1] + 90]] },
  ];
  geo.cursorSegs.forEach((s) => { s.x = track(s.keys.map((k) => [k[0], k[1]])); s.y = track(s.keys.map((k) => [k[0], k[2]])); });
}

function barsAt(t, i) {
  const beat = t < cue.mac ? 0 : Math.exp(-((t % 0.5)) * 7);
  return clamp(0.32 + 0.48 * Math.abs(Math.sin(t * (4.3 + i * 1.9) + i * 1.7)) + 0.3 * beat, 0.2, 1);
}

function paintIsland(t) {
  const w = geo.w(t), h = geo.h(t), r = Math.max(0, geo.r(t));
  const isl = el.island;
  isl.style.width = `${w}px`; isl.style.height = `${h}px`; isl.style.left = `${756 - w / 2}px`;
  isl.style.borderRadius = `0 0 ${r}px ${r}px`;
  isl.style.boxShadow = h > 60 ? `0 ${24 * clamp((h - 40) / 300)}px 60px -18px rgba(0,0,0,.65)` : "none";
  const view = (node, a, blur = true) => {
    node.style.opacity = a.toFixed(3);
    if (!show(node, a > 0.002)) return;
    node.style.transform = `scale(${lerp(0.94, 1, a)})`;
    node.style.filter = blur && a < 0.999 ? `blur(${(1 - a) * 8}px)` : "none";
  };
  ["compact", "peek", "timer", "meeting", "airpods"].forEach((n) => view(el[n], viewAlpha(t, iv[n])));
  view(el.open, viewAlpha(t, iv.openAny, 0.06, 0.3, 0.14), false);
  const aX = viewAlpha(t, iv.open, 0.04, 0.26, 0.12), aS = viewAlpha(t, iv.search, 0.04, 0.26, 0.12);
  el.loX.style.opacity = aX; el.loS.style.opacity = aS;
  el.loX.style.transform = `translateY(${(1 - aX) * 8}px)`; el.loS.style.transform = `translateY(${(1 - aS) * 8}px)`;

  const ti = trackAt(t), sw = switches[ti], k = ease.out(prog(t, sw, 0.32));
  const setT = (node, tr) => { node.children[0].textContent = tr.title; node.children[1].textContent = tr.artist; };
  setT(el.metaA, tracks[ti]);
  el.metaA.style.opacity = ti === 0 ? 1 : k; el.metaA.style.transform = `translateY(${ti === 0 ? 0 : (1 - k) * 10}px)`;
  if (ti > 0 && k < 1) { setT(el.metaB, tracks[ti - 1]); el.metaB.style.opacity = 1 - clamp(k * 2); el.metaB.style.transform = `translateY(${-k * 10}px)`; }
  else el.metaB.style.opacity = 0;
  const tr = tracks[ti], pos = posAt(t);
  el.now.textContent = clock(pos); el.left.textContent = `-${clock(tr.length - pos)}`;
  el.fill.style.width = `${(pos / tr.length) * 100}%`;
  el.coverLg.style.transform = `scale(${1 + 0.12 * bump(t, cue.enter + 0.03, 0.35)})`;
  el.pkText.style.transform = `translateY(${(1 - ease.out(prog(t, cue.peek + 0.12, 0.4))) * 8}px)`;

  const shimT = [cue.peek, cue.enter + 0.03].map((s) => prog(t, s, 0.95)).find((p) => p > 0 && p < 1);
  el.shim.style.opacity = shimT == null ? 0 : Math.sin(Math.PI * shimT);
  el.shim.style.transform = `translateX(${shimT == null ? -100 : lerp(-100, 100, ease.inOut(shimT))}%)`;

  // Volume: the track thickens under the pointer, the thumb and level bubble appear while dragging.
  const hotV = win(t, 8.55, 9.8, 0.2, 0.2);
  const level = lerp(0.62, 0.88, ease.inOut(prog(t, cue.volume[0], cue.volume[1] - cue.volume[0])));
  el.vtrack.style.height = `${lerp(4, 8, hotV)}px`;
  el.vol.style.color = `rgba(255,255,255,${lerp(0.5, 0.92, hotV)})`;
  el.vfill.style.width = `calc(${level} * (100% - 14px) + 7px)`;
  el.vthumb.style.left = `calc(${level} * (100% - 14px))`;
  el.vthumb.style.transform = `scale(${hotV * (t > cue.volume[0] && t < cue.volume[1] + 0.1 ? 1.18 : 1)})`;
  el.vbub.textContent = Math.round(level * 100);
  el.vbub.style.opacity = win(t, cue.volume[0], cue.volume[1] + 0.15, 0.12, 0.2);
  el.vw.forEach((wv, i) => (wv.style.opacity = level * 100 > [0, 40, 75][i] ? 1 : 0.18));

  el.expand.style.background = t > 15.33 && t < 15.65 ? "rgba(255,255,255,.14)" : "transparent";
  el.expand.style.transform = `scale(${1 - 0.18 * bump(t, cue.expand, 0.16)})`;
  el.shelf.forEach((p, i) => {
    const a = bump(t, cue.shelf[i] - 0.1, 0.34);
    p.querySelector(".cover").style.transform = `scale(${1 + 0.08 * a}) translateY(${-3 * a}px)`;
  });
  el.sIdle.style.boxShadow = t >= cue.search ? "0 0 0 3px rgba(124,108,242,.4)" : "none";
  el.typed.textContent = "kyiv".slice(0, cue.keys.filter((k2) => t >= k2).length);
  el.caret.style.opacity = (t - cue.search) % 0.6 < 0.36 || (t > cue.keys[0] && t < cue.results + 0.2) ? 1 : 0;
  el.sLive.style.boxShadow = "0 0 0 3px rgba(124,108,242,.4)";
  el.results.forEach((r, i) => { const a = ease.out(prog(t, cue.results + i * 0.06, 0.3)); r.style.opacity = a; r.style.transform = `translateY(${(1 - a) * 12}px)`; });
  const pick = t > cue.enter - 0.02, kbd = el.first.querySelector("kbd");
  el.first.style.background = pick ? "rgba(255,255,255,.18)" : "";
  kbd.style.background = pick ? "#F4EFFA" : ""; kbd.style.color = pick ? "#000" : "";
  kbd.style.transform = `scale(${1 + 0.15 * bump(t, cue.enter, 0.2)})`;

  el.cd.textContent = t < cue.timer + 0.5 ? "25:00" : "24:59";
  el.bb.style.width = `${82 * ease.out(prog(t, cue.airpods + 0.12, 0.6))}%`;
  [[".v-timer svg", cue.timer], [".v-meeting .cal", cue.meeting], [".v-airpods .pods", cue.airpods]].forEach(([s, at]) => {
    const k2 = prog(t, at + 0.08, 0.5);
    $(s).style.transform = `scale(${lerp(0.4, 1, ease.back(k2))}) rotate(${(1 - ease.out(k2)) * -14}deg)`;
  });
}

// The app's stage panel: lyrics on eighths, tab selector, panes, player card.
const lineAt = (t) => lyrics.reduce((c, l, i) => (t >= l.start - 0.08 ? i : c), 0);
const lineSpring = spring([[0, 0], ...lyrics.slice(1).map((l, i) => [l.start - 0.08, i + 1])], 11, 0.8);
function paintStage(key, t, tabKeys) {
  const node = sp[key], g = spGeo[key];
  const li = clamp(lineSpring(t), 0, lyrics.length - 1), i0 = Math.floor(li), f = li - i0;
  const top = lerp(g.tops[i0], g.tops[Math.min(i0 + 1, g.tops.length - 1)], f);
  $(".lines", node).style.transform = `translateY(${g.tops[1] - top}px)`;
  const current = lineAt(t);
  $$(".line", node).forEach((line, l) => {
    [...line.children].forEach((w, k) => {
      const p = l < current ? 1 : l > current ? 0 : ease.out(prog(t, lyrics[l].start + k * wordStep - 0.04, 0.2));
      const lit = l === current ? p : 0;
      w.style.opacity = (l === current ? lerp(0.34, 1, p) : l < current ? 0.4 : 0.26).toFixed(3);
      w.style.textShadow = lit > 0 ? `0 0 ${24 * lit}px rgba(255,255,255,${0.3 * lit})` : "none";
    });
    line.style.filter = Math.abs(l - current) >= 3 ? "blur(2px)" : "none";
  });
  const idx = tabKeys.reduce((c, [tt, i]) => (t >= tt ? i : c), 0);
  const selX = spring(tabKeys.map(([tt, i]) => [tt, g.tabs[i][0]]), 13, 0.85)(t);
  const selW = spring(tabKeys.map(([tt, i]) => [tt, g.tabs[i][1]]), 13, 0.85)(t);
  const sel = $(".tabsel", node);
  sel.style.transform = `translateX(${selX}px)`; sel.style.width = `${selW}px`;
  $$(".tab", node).forEach((tb, i) => (tb.style.opacity = i === idx ? 1 : 0.62));
  [".p-lyr", ".p-q", ".p-pl"].map((s) => $(s, node)).forEach((p, i) => {
    let a = 0;
    tabKeys.forEach(([tt, j], n) => {
      if (j !== i) return;
      const end = tabKeys[n + 1]?.[0] ?? 1e9;
      a = Math.max(a, Math.min(tt <= 0 ? 1 : ease.out(prog(t, tt + 0.05, 0.3)), 1 - prog(t, end, 0.14)));
    });
    p.style.opacity = a.toFixed(3);
    if (show(p, a > 0.002)) p.style.transform = `translateY(${(1 - a) * 12}px)`;
  });
  $$(".p-q .qrow", node).forEach((r, i) => { const a = ease.out(prog(t, cue.tabQueue + 0.08 + i * 0.05, 0.35)); r.style.transform = `translateY(${(1 - a) * 16}px)`; r.style.opacity = a; });
  $$(".p-pl .gcard", node).forEach((r, i) => { const a = ease.out(prog(t, cue.tabLists + 0.08 + i * 0.05, 0.4)); r.style.transform = `translateY(${(1 - a) * 18}px) scale(${lerp(0.92, 1, a)})`; r.style.opacity = a; });
  const pos = posAt(t), len = tracks[2].length;
  $(".pc-now", node).textContent = clock(pos); $(".pc-left", node).textContent = `-${clock(len - pos)}`;
  $(".pcard .fill", node).style.width = `${(pos / len) * 100}%`;
}

// ---------- camera ----------
// Keys: [t, fx, fy, scale, rotateX, rotateY, rotateZ, stageX, stageY]. (fx, fy) is the point on the rig
// (MacBook lid coordinates) that lands on (stageX, stageY).
const PULL = { fx: 776, fy: 20, s: 6, cx: 960, cy: 384 };
const CAM = [
  [cue.mac, PULL.fx, PULL.fy, PULL.s, 0, 0, 0, PULL.cx, PULL.cy],
  [6.95, 776, 430, 0.8, 9, -5, 0, 960, 470],
  [7.45, 776, 300, 1.12, 8, -4, 0, 1010, 430],
  [8.4, 776, 245, 1.52, 5, -3, 0, 1120, 400],
  [9.6, 776, 252, 1.66, 4, 2, 0, 1120, 410],
  [10.3, 700, 420, 1.02, 6, 5, 0, 990, 480],
  [11.6, 710, 410, 0.98, 6, 8, 0, 980, 475],
  [12.35, 776, 240, 1.42, 5, 4, 0, 1130, 400],
  [13.6, 776, 250, 1.6, 4, -2, 0, 1150, 410],
  [15.3, 776, 262, 1.76, 3, -6, 0, 1130, 430],
  [15.95, 776, 511, 1.27, 0, 0, 0, 960, 540],
  [17.8, 800, 520, 1.33, 0, 0, 0.3, 960, 540],
  [19.6, 776, 511, 1.29, 0, 0, 0, 960, 540],
  [20.55, 776, 540, 0.68, 9, -3, 0, 960, 515],
  [21.65, 776, 540, 0.72, 8, 3, 0, 960, 515],
  [22.05, 776, 36, 2.7, 7, -2, 0, 960, 300],
  [23.45, 776, 36, 2.86, 6, 2, 0, 960, 300],
  [24.35, 2050, 560, 0.56, 6, -5, 0, 960, 560],
  [25.9, 2150, 540, 0.6, 5, -8, 0, 960, 560],
];
const cam = [1, 2, 3, 4, 5, 6, 7, 8].map((c) => track(CAM.map((k) => [k[0], k[c]]), { log: c === 3 }));

// ---------- scenes ----------
const ICON_MEET = 200; // the icon's size on the "Meet" line
function paintHook(t) {
  if (!show(el.hook, t < cue.mac + 0.05)) return;
  if (show(el.h1n, t < 2.0)) { rise(el.h1, t, cue.hook1); exitStyle(el.h1n, t, 1.78, 0.22); }
  if (show(el.h2n, t > 1.95 && t < cue.meet + 0.1)) { rise(el.h2, t, cue.hook2); exitStyle(el.h2n, t, 3.8, 0.2); }
  // The notch at the top edge wakes and grows wings, then drops into the icon.
  const wake = ease.out(prog(t, cue.wake, 0.5));
  const w = 2 * spring([[0, 186], [cue.wake, 292]], 10, 0.68)(t), h = 64;
  const drop = ease.inOut(prog(t, 3.7, 0.32));
  const k = lerp(1, (144 * ICON_MEET / 1024) / w * 2.2, drop);
  const y = lerp(0, 540 - ICON_MEET / 2 + 262 * ICON_MEET / 1024 - h * k / 2, drop);
  el.hisl.style.width = `${w}px`; el.hisl.style.height = `${h}px`;
  el.hisl.style.transform = `translate(${960 - w / 2}px, ${y}px) scale(${k})`;
  el.hisl.style.opacity = 1 - prog(t, 3.96, 0.06);
  el.hisl.style.boxShadow = `0 0 ${lerp(0, 120, wake)}px ${lerp(0, 10, wake)}px color-mix(in srgb, var(--a1) ${Math.round(wake * 45)}%, transparent)`;
  $$(".hisl .cover, .hisl .bars", el.hook).forEach((n) => (n.style.opacity = wake * (1 - drop)));
  el.edge.style.opacity = 1 - drop;
  // Meet [icon] Brimtune.
  if (!show(el.meet, t > cue.meet - 0.06)) return;
  const pop = springStep(-1, 0, Math.max(0, t - cue.meet), 13, 0.55)[0] + 1;
  // Diving into the icon's notch: the icon grows around its notch until it matches the Mac's notch.
  const dive = Math.pow(prog(t, cue.dive, cue.mac - cue.dive), 2.6);
  const notchPx = 144 * ICON_MEET / 1024;
  const kd = Math.exp(lerp(0, Math.log((PULL.s * 144) / notchPx), dive));
  const ny = 540 - ICON_MEET / 2 + 283 * ICON_MEET / 1024;
  el.micon.style.transformOrigin = `50% ${(283 / 1024) * 100}%`;
  el.micon.style.transform = `translate(0, ${(PULL.cy + 21 - ny) * dive}px) scale(${lerp(0.4, 1, Math.max(0, pop)) * kd})`;
  const slide = ease.out5(prog(t, cue.meet + 0.08, 0.6));
  el.mL.style.transform = `translateX(${(1 - slide) * 110}%)`; el.mR.style.transform = `translateX(${(slide - 1) * 110}%)`;
  el.mL.style.opacity = el.mR.style.opacity = clamp(slide * 2) * (1 - prog(t, cue.dive, 0.2));
}

function paintWorld(t) {
  const on = t >= cue.mac - 0.001 && t < cue.stats + 0.02;
  [el.world, el.bg, el.floor, el.fgBox].forEach((n) => show(n, on));
  if (!on) return;
  const [fx, fy, s, rx, ry, rz, cx, cy] = cam.map((f) => f(t));
  // Into the external display's pill: the world zooms toward it, then the stats card takes over.
  el.world.style.transform = "";
  el.rig.style.transform = `translate(${cx}px,${cy}px) rotateZ(${rz}deg) rotateX(${rx}deg) rotateY(${ry}deg) scale(${s}) translate(${-fx}px,${-fy}px)`;
  if (t > 25.75) {
    paintMonitor(t);
    const r = el.mpill.getBoundingClientRect(), sr = stage.getBoundingClientRect(), k = sr.width / 1920;
    const px = (r.left + r.width / 2 - sr.left) / k, py = (r.top + r.height / 2 - sr.top) / k;
    const z = Math.exp(Math.log(9) * Math.pow(prog(t, 25.75, 0.25), 2.2));
    el.world.style.transform = `translate(${px}px,${py}px) scale(${z}) translate(${-px}px,${-py}px)`;
  }

  const drift = [[0.21, 0.17], [0.16, 0.23], [0.27, 0.13]];
  el.bgI.forEach((b, i) => {
    const [a, c] = drift[i];
    b.style.transform = `translate(${-ry * (10 + i * 4) + Math.sin(t * a * 3 + i) * 40}px, ${rx * 9 + Math.cos(t * c * 3 + i) * 30}px) scale(${1 + 0.05 * Math.sin(t * 0.7 + i)})`;
  });
  const fsOn = t > 15.7 && t < 20.1;
  el.fg.forEach((d, i) => {
    const depth = 1.6 + (i % 3) * 0.7, size = 40 + ((i * 53) % 120);
    const x = ((i * 241 + 130) % 1920) + ry * depth * 22 + t * (8 + i * 3);
    const y = ((i * 397 + 90) % 1080) - rx * depth * 9 + Math.sin(t * 0.6 + i) * 20;
    d.style.cssText = `left:${x}px;top:${y}px;width:${size}px;height:${size}px;opacity:${fsOn ? 0 : 0.12 + (i % 4) * 0.05};filter:blur(${4 + depth * 3}px)`;
  });
  const deskBlur = clamp((s - 1.12) / 0.5) * 7;
  el.desk.style.filter = deskBlur > 0.05 ? `blur(${deskBlur.toFixed(2)}px) brightness(${1 - deskBlur * 0.035})` : "none";
  el.glare.style.transform = `translateX(${ry * 14 - 200}px)`;
  el.glare.style.opacity = fsOn ? 0.25 : 1;

  paintIsland(t);
  paintWeb(t);

  let px = 0, py = 0, op = 0;
  for (const sg of geo.cursorSegs) {
    if (t < sg.from - 0.3 || t > sg.to + 0.3) continue;
    px = sg.x(t); py = sg.y(t);
    op = Math.max(op, Math.min(prog(t, sg.from, 0.3), 1 - prog(t, sg.to, 0.15)));
  }
  const press = [cue.play, cue.search, cue.expand, cue.tabQueue, cue.tabLists].reduce((a, p) => a + bump(t, p - 0.02), 0)
    + (t > cue.volume[0] - 0.05 && t < cue.volume[1] + 0.05 ? 0.8 : 0);
  el.cursor.style.opacity = op;
  if (show(el.cursor, op > 0.01)) el.cursor.style.transform = `translate(${px}px,${py}px) scale(${1.05 - 0.14 * clamp(press)})`;

  // The spark from the web tab to the notch.
  const bk = prog(t, cue.play + 0.05, cue.peek - cue.play - 0.05);
  if (show(el.beam, bk > 0 && bk < 1)) {
    const e = ease.inOut(bk), [x0, y0] = geo.row, x1 = 756, y1 = 18;
    const bx = (1 - e) ** 2 * x0 + 2 * (1 - e) * e * (x0 + 160) + e * e * x1, by = (1 - e) ** 2 * y0 + 2 * (1 - e) * e * 80 + e * e * y1;
    el.beam.style.transform = `translate(${bx}px,${by}px) scale(${lerp(0.6, 1.4, Math.sin(Math.PI * bk))})`;
    el.beam.style.opacity = Math.sin(Math.PI * Math.min(1, bk * 1.2));
  }
  paintFull(t);
  paintLock(t);
  paintMonitor(t);
}

function paintWeb(t) {
  const played = t >= cue.play;
  el.yrows.forEach((r, i) => {
    const hot = i === 1 && t > 10.15 && t < 11.7;
    r.style.background = played && i === 1 ? "rgba(255,255,255,.1)" : hot ? "rgba(255,255,255,.06)" : "";
    const pb = r.querySelector(".pb");
    pb.style.opacity = hot || (played && i === 1) ? 1 : 0;
    pb.style.transform = `scale(${1 - 0.2 * bump(t, cue.play - 0.02, 0.16)})`;
  });
  const ti = played ? (t < switches[2] ? 1 : 2) : 0;
  el.ypbt.textContent = tracks[ti].title; el.ypba.textContent = tracks[ti].artist;
  el.ypbc.style.cssText = cv(tracks[ti].colors);
  el.ypfill.style.width = `${(posAt(t) / tracks[trackAt(t)].length) * 100}%`;
}

function paintFull(t) {
  const bloom = ease.inOut(prog(t, cue.expand + 0.03, 0.42));
  const fsOut = prog(t, cue.lock, 0.18);
  if (!show(el.fs, bloom > 0 && fsOut < 1)) return;
  el.fs.style.opacity = 1 - fsOut;
  const room = ease.out(prog(t, cue.expand + 0.05, 0.3));
  [el.fsbase, el.fsshade, el.fsmesh].forEach((n) => (n.style.opacity = room));
  el.fsmesh.style.transform = `scale(${lerp(1.25, 1, ease.out(prog(t, cue.expand, 0.6)))})`;
  el.mesh.forEach((m, i) => (m.style.transform = `translate(${Math.sin(t * 0.8 + i * 2) * 80}px, ${Math.cos(t * 0.7 + i) * 60}px) scale(${1 + 0.1 * Math.sin(t * 1.1 + i * 1.3)})`));
  const enter = ease.out(prog(t, cue.full - 0.15, 0.6));
  paintStage("fs", t, [[0, 0], [cue.tabQueue, 1], [cue.tabLists, 2]]);
  // The island's cover grows into the stage's cover (starting exactly on the small one), then breathes.
  const art = $(".fsp .sp-art"), [x0, y0, w0] = geo.cover, [ax, ay] = geo.fsArt, aw = art.offsetWidth;
  const breathe = 1 + 0.012 * Math.sin(((t - cue.full) / 2) * Math.PI * 2);
  art.style.transformOrigin = "0 0";
  art.style.transform = `translate(${lerp(x0 - ax, 0, bloom)}px,${lerp(y0 - ay, 0, bloom)}px) scale(${lerp(w0 / aw, 1, bloom) * breathe})`;
  [".fsp .pcard", ".fsp .sp-col"].forEach((s, i) => { const n = $(s); n.style.opacity = enter; n.style.transform = `translateY(${(1 - enter) * (24 + i * 10)}px)`; });
  el.fclock.style.opacity = enter; el.fclock.style.transform = `translateY(${(1 - enter) * -20}px)`;
  el.sidebar.style.opacity = ease.out(prog(t, cue.full, 0.5));
}

function paintLock(t) {
  el.dim.style.opacity = (0.75 * (ease.out(prog(t, cue.lock, 0.1)) - ease.inOut(prog(t, cue.lock + 0.11, 0.18)))).toFixed(3);
  if (!show(el.lock, t >= cue.lock && t < cue.unlock + 0.22)) return;
  el.lock.style.opacity = 1 - ease.inOut(prog(t, cue.unlock + 0.06, 0.1));
  const a = ease.out(prog(t, cue.lock + 0.12, 0.45)), b = prog(t, cue.lock + 0.22, 0.55);
  el.lclock.style.transform = `translateY(${(1 - a) * 40}px)`; el.lclock.style.opacity = a; el.ldate.style.opacity = a;
  sp.lk.style.transform = `translateY(${(1 - ease.back(b)) * 50}px) scale(${lerp(0.95, 1, ease.out(b))})`; sp.lk.style.opacity = clamp(b * 2);
  el.who.style.opacity = ease.out(prog(t, cue.lock + 0.4, 0.5));
  paintStage("lk", t, [[0, 0]]);
}

function paintMonitor(t) {
  if (!show(el.mon, t > cue.displays - 0.1)) return;
  const k = ease.out5(prog(t, cue.displays, 0.9));
  el.mon.style.transform = `translate3d(${lerp(2300, 1760, k)}px, -40px, -260px) rotateY(-12deg)`;
  el.mon.style.opacity = clamp(k * 3);
  const p = springStep(-1, 0, Math.max(0, t - cue.pill), 12, 0.6)[0] + 1;
  el.mpill.style.opacity = clamp((t - cue.pill) * 6);
  el.mpill.style.transform = `translateX(-50%) scale(${t < cue.pill ? 0.5 : lerp(0.5, 1, p)})`;
}

function paintStats(t) {
  if (!show(el.stats, t > cue.stats - 0.02 && t < cue.bento + 0.3)) return;
  el.stats.style.opacity = 1 - prog(t, cue.bento - 0.05, 0.2);
  rise(el.sh, t, [cue.stats + 0.02, cue.stats + 0.17]);
  const c = ease.out(prog(t, cue.stats + 0.45, 0.9));
  el.n1.textContent = (1.5 * c).toFixed(1); el.n2.textContent = Math.round(36 * c);
  el.cols.forEach((col, i) => { const a = ease.out(prog(t, cue.stats + 0.35 + i * 0.12, 0.5)); col.style.opacity = a; col.style.transform = `translateY(${(1 - a) * 40}px)`; });
  const line = (amp, base, ph) => {
    let d = "";
    for (let x = 0; x <= 600; x += 10) {
      const reveal = clamp((t - cue.stats - 0.5) * 2.2 - (x / 600) * 0.6);
      const y = 70 - base - (Math.sin(x / 37 + ph + t * 2) * amp + Math.sin(x / 13 + ph) * amp * 0.4) * reveal;
      d += `${x ? "L" : "M"}${x} ${y.toFixed(1)}`;
    }
    return d;
  };
  el.sp1.setAttribute("d", line(3, 6, 0)); el.sp2.setAttribute("d", line(2, 14, 2));
  el.fine.style.opacity = ease.out(prog(t, cue.stats + 1.2, 0.5));
}

function paintBento(t) {
  if (!show(el.bento, t > cue.bento - 0.05 && t < cue.free + 0.1)) return;
  rise(el.bh, t, el.bh.map((_, i) => cue.bento + 0.05 + i * 0.07));
  el.bhN.style.opacity = 1 - prog(t, cue.free - 0.25, 0.2);
  const rx = lerp(24, 12, ease.out(prog(t, cue.bento, 1.8))), rz = lerp(-6, -2.5, ease.out(prog(t, cue.bento, 2.2)));
  el.grid3d.style.transform = `translate(-50%,-50%) rotateX(${rx}deg) rotateZ(${rz}deg) translateY(${lerp(40, -10, prog(t, cue.bento, 2.5))}px)`;
  el.tiles.forEach((tile, i) => {
    const a = ease.out5(prog(t, cue.bento + 0.15 + i * 0.125, 0.7));
    const fly = Math.pow(prog(t, cue.free - 0.3 + (i % 3) * 0.03, 0.3), 2);
    tile.style.opacity = clamp(a * 2) * (1 - fly);
    tile.style.transform = `translateZ(${lerp(-700, 0, a) + fly * 1400}px) rotateX(${(1 - a) * 30}deg)`;
    tile.style.filter = fly > 0.05 ? `blur(${fly * 14}px)` : "none";
  });
  const cur = Math.floor((t - cue.bento) / wordStep);
  el.tlw.forEach((w, i) => (w.style.opacity = i <= cur % 8 ? 1 : 0.3));
  el.bcd.textContent = `24:${String(59 - Math.floor(Math.max(0, t - cue.bento))).padStart(2, "0")}`;
}

function paintOffer(t) {
  if (!show(el.offer, t > cue.free - 0.05 && t < cue.end + 0.1)) return;
  el.offer.style.opacity = 1 - prog(t, cue.end - 0.04, 0.08);
  el.ofree.forEach((s, i) => {
    const k = prog(t, cue.free + i * 0.045, 0.55);
    s.style.transform = `translateY(${(1 - ease.out5(k)) * 140}px)`;
    s.style.fontVariationSettings = `"wdth" ${lerp(62, 100, ease.out(k)).toFixed(1)}`;
    s.style.opacity = clamp(k * 2.5);
  });
  rise(el.oopen, t, [cue.openSource, cue.openSource + 0.12]);
  const c = ease.out(prog(t, cue.openSource + 0.35, 0.5));
  el.ochip.style.opacity = c; el.ochip.style.transform = `translateX(-50%) translateY(${(1 - c) * 20}px)`;
  const a = prog(t, 32.9, 0.5);
  el.dl.style.transform = `translateX(-50%) translateY(${(1 - ease.back(a)) * 90}px) scale(${1 - 0.06 * bump(t, cue.download - 0.02, 0.16)})`;
  el.dl.style.opacity = clamp(a * 2.5);
  const f = ease.inOut(prog(t, cue.download + 0.02, 0.3));
  el.dlFill.style.transform = `translateX(${(f - 1) * 100}%)`;
  el.dl1.style.opacity = 1 - clamp(f * 2); el.dl2.style.opacity = clamp(f * 2 - 0.6);
  const pk = [[33.0, 1500, 1200], [33.36, 1100, 930], [cue.download + 0.12, 1104, 934], [cue.end, 1120, 950]];
  const px = track(pk.map((p) => [p[0], p[1]]))(t), py = track(pk.map((p) => [p[0], p[2]]))(t);
  el.pointer.style.transform = `translate(${px}px,${py}px) scale(${1.55 - 0.22 * bump(t, cue.download - 0.02)})`;
  el.pointer.style.opacity = clamp(prog(t, 33.0, 0.15));
}

function paintEnd(t) {
  if (!show(el.end, t > cue.end - 0.05)) return;
  el.end.style.opacity = prog(t, cue.end - 0.04, 0.08);
  const pop = springStep(-1, 0, Math.max(0, t - cue.end), 9, 0.62)[0] + 1;
  const k = (300 / 824) * lerp(0.55, 1, pop);
  const ay = 380 - 7 * ease.inOut(prog(t, 35.5, 2.5));
  el.icon.style.transform = `translate(960px,${ay}px) rotate(${(1 - ease.out5(prog(t, cue.end, 0.9))) * -6}deg) scale(${k}) translate(-512px,-512px)`;
  const g = ease.out(prog(t, cue.end + 0.05, 0.9));
  el.glow.style.opacity = g;
  el.glow.style.transform = `scale(${lerp(0.4, 1, g) * (1 + 0.05 * Math.sin((t - cue.end) * 2.4))}) rotate(${(t - cue.end) * 6}deg)`;
  rise(el.word, t, el.word.map((_, i) => cue.wordmark + i * 0.035), { len: 0.6, y: 110 });
  const u = ease.out(prog(t, cue.url, 0.6));
  el.url.style.opacity = u; el.url.style.transform = `translateY(${(1 - u) * 24}px)`; el.url.style.letterSpacing = `${lerp(0.12, 0.01, u)}em`;
  el.badges.forEach((b, i) => { const a = ease.out(prog(t, cue.badges + i * 0.1, 0.5)); b.style.opacity = a; b.style.transform = `translateY(${(1 - a) * 16}px)`; });
}

function renderAt(t) {
  const pal = palette(t);
  stage.style.setProperty("--a1", pal[0]); stage.style.setProperty("--a2", pal[1]); stage.style.setProperty("--a3", pal[2]);
  paintHook(t);
  paintWorld(t);
  paintCaptions(t);
  el.chips.forEach((c, i) => {
    const a = win(t, 11.15 + i * 0.08, 12.25, 0.4, 0.2);
    c.style.opacity = a; c.style.transform = `translateY(${(1 - a) * 24}px) scale(${lerp(0.9, 1, a)})`;
  });
  show(el.shade, t > cue.mac && t < cue.stats);
  paintStats(t);
  paintBento(t);
  paintOffer(t);
  paintEnd(t);
  el.fadein.style.opacity = (1 - ease.out(prog(t, 0, 0.4))).toFixed(3);
  show(el.fadein, t < 0.4);
  el.bars.forEach((b, i) => (b.style.transform = `scaleY(${barsAt(t, i % 5).toFixed(3)})`));
}

// ---------- boot ----------
async function boot() {
  await Promise.all(['800 92px "Archivo"', 'italic 300 92px "Archivo"', '600 15px "Geist"', '500 15px "Geist"'].map((f) => document.fonts.load(f)));
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

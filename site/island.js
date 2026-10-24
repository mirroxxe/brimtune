// The island at the top of the page: a working miniature of Brimtune.
// Scrolling picks what it shows; hovering opens the player; covers set the page's colours.
(() => {
  const island = document.getElementById("island");
  const root = document.documentElement;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

  // The tour's big island is a copy of this one: same views, driven by the same clock.
  const tourIsland = document.querySelector(".tour-island");
  if (tourIsland) {
    tourIsland.innerHTML = island.innerHTML;
    tourIsland.inert = true;
  }

  // The open island takes exactly the height its content needs, like the app's: measure the
  // current view into --h whenever the state changes (and again once fonts have arrived).
  function fit(el) {
    const inner = el.querySelector(`.view-${el.dataset.state} .vi`);
    if (inner) el.style.setProperty("--h", `${inner.offsetHeight}px`);
    else el.style.removeProperty("--h");
  }
  window.brimtuneFit = fit;
  // After a tour film has picked a song for its island, put the page's song back.
  window.brimtuneRestoreTrack = () => {
    const t = tracks[trackIndex];
    document.querySelectorAll(".tour-island .track-title").forEach((el) => (el.textContent = t.title));
    document.querySelectorAll(".tour-island .track-artist").forEach((el) => (el.textContent = t.artist));
  };
  [island, tourIsland].filter(Boolean).forEach((el) => {
    new MutationObserver(() => fit(el)).observe(el, { attributes: true, attributeFilter: ["data-state"] });
    fit(el);
  });
  document.fonts?.ready.then(() => [island, tourIsland].filter(Boolean).forEach(fit));

  // Made-up songs with made-up covers: three moods, three palettes.
  const tracks = [
    { title: "Night Bus Home", artist: "Lumen Field", length: 202, colors: ["#F2648E", "#7C6CF2", "#FFAE57"] },
    { title: "Paper Moons", artist: "Orla Vey", length: 228, colors: ["#3FB6C9", "#4B5BD6", "#C8F08F"] },
    { title: "Kyiv, 5 a.m.", artist: "Teo Brann", length: 187, colors: ["#FF8A4C", "#C2367A", "#FFD36E"] },
  ];

  let trackIndex = 0;
  let playing = true;
  let position = 68;
  let sectionState = "compact";
  let hovering = false;
  let peekTimer;

  const $ = (sel) => document.querySelectorAll(sel);
  const clock = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

  let peeking = false;
  function render() {
    const base = hovering && ["compact", "idle", "expanded", "timer"].includes(sectionState) ? "expanded" : sectionState;
    // A new song in the compact island opens it for a moment to name itself, like the app's.
    const state = peeking && base === "compact" ? "peek" : base;
    island.dataset.state = state;
    island.dataset.playing = String(playing);
    if (tourIsland) tourIsland.dataset.playing = String(playing);
  }

  function showTrack(i, { shimmer = true } = {}) {
    trackIndex = (i + tracks.length) % tracks.length;
    const t = tracks[trackIndex];
    root.style.setProperty("--a1", t.colors[0]);
    root.style.setProperty("--a2", t.colors[1]);
    root.style.setProperty("--a3", t.colors[2]);
    // The tour's island (data-lock) is showing a song its script picked; leave that one alone.
    document.querySelectorAll(".track-title:not([data-lock] *)").forEach((el) => (el.textContent = t.title));
    document.querySelectorAll(".track-artist:not([data-lock] *)").forEach((el) => (el.textContent = t.artist));
    position = 0;
    updateProgress();
    if (shimmer && !reducedMotion && sectionState === "compact" && !hovering) {
      peeking = true;
      render();
      clearTimeout(peekTimer);
      peekTimer = setTimeout(() => { peeking = false; render(); }, 2800);
    }
    if (shimmer && !reducedMotion) {
      island.classList.remove("shimmer");
      void island.offsetWidth; // restart the animation
      island.classList.add("shimmer");
    }
  }

  function updateProgress() {
    const t = tracks[trackIndex];
    const pct = `${(position / t.length) * 100}%`;
    document.querySelectorAll(".fill").forEach((el) => (el.style.width = pct));
    $(".time-now").forEach((el) => (el.textContent = clock(position)));
    $(".time-left").forEach((el) => (el.textContent = `-${clock(t.length - position)}`));
  }

  // Controls in the expanded island.
  island.addEventListener("click", (e) => {
    const action = e.target.closest("[data-action]")?.dataset.action;
    if (!action) return;
    if (action === "toggle") {
      playing = !playing;
      e.target.closest("button").setAttribute("aria-label", playing ? "Pause" : "Play");
    }
    if (action === "next") showTrack(trackIndex + 1);
    if (action === "prev") showTrack(trackIndex - 1);
    render();
  });

  // Hover or keyboard focus opens the player, like the real thing.
  const hint = document.getElementById("hint");
  let closeTimer;
  function open() {
    clearTimeout(closeTimer);
    hovering = true;
    hint?.classList.add("done");
    render();
  }
  function close() {
    closeTimer = setTimeout(() => { hovering = false; render(); }, 250);
  }
  // Touch screens have no hover: a tap opens and closes it instead.
  if (matchMedia("(hover: none)").matches) {
    if (hint) hint.textContent = "Try it: tap the island at the top of this page.";
    island.addEventListener("click", (e) => {
      if (e.target.closest("[data-action]")) return;
      hovering ? (hovering = false, render()) : open();
    });
  }
  island.addEventListener("mouseenter", open);
  island.addEventListener("mouseleave", close);
  island.addEventListener("focusin", open);
  island.addEventListener("focusout", (e) => { if (!island.contains(e.relatedTarget)) close(); });

  // Whatever crosses the middle of the screen decides what the island shows.
  const watched = document.querySelectorAll("[data-island]");
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      sectionState = entry.target.dataset.island;
      if (sectionState === "timer") timerLeft = 25 * 60;
      render();
    }
  }, { rootMargin: "-48% 0px -48% 0px" });
  watched.forEach((el) => observer.observe(el));

  // Timers count down for real, in the island and in the timer tile.
  let timerLeft = 25 * 60;
  window.brimtuneTimerReset = () => { timerLeft = 25 * 60; };
  const countdowns = document.querySelectorAll(".countdown");

  // Lyrics: every karaoke block lights its words in turn, on one shared clock;
  // the island echoes the current line.
  const islandLines = $(".island-line");
  const blocks = [...document.querySelectorAll("[data-karaoke]")].map((block) => {
    const lines = [...block.querySelectorAll("[data-line]")];
    const words = lines.map((line) => {
      const parts = line.textContent.trim().split(/\s+/);
      line.textContent = "";
      return parts.map((word, i) => {
        const span = document.createElement("span");
        span.className = "w";
        span.textContent = word;
        line.append(span, i < parts.length - 1 ? " " : "");
        return span;
      });
    });
    const entry = { block, lines, words, visible: false };
    new IntersectionObserver(([e]) => { entry.visible = e.isIntersecting; }).observe(block);
    return entry;
  });
  const wordTime = 0.42;
  const lineGap = 0.7;
  let lyricClock = 0;
  // Jump the shared lyric clock to the start of one line: what clicking a line does in the app.
  window.brimtuneSeekLine = (index) => {
    const { words } = blocks[blocks.length - 1];
    lyricClock = words.slice(0, index).reduce((sum, w) => sum + w.length * wordTime + lineGap, 0);
  };

  function paintLyrics() {
    for (const { lines, words, visible } of blocks) {
      if (reducedMotion) { words.flat().forEach((w) => w.style.setProperty("--p", 1)); continue; }
      // Off-screen blocks rest, except the one the island is echoing.
      const echoed = lines === blocks[0].lines && document.querySelector(".tour-stage")?.dataset.scene === "stage";
      if (!visible && !echoed) continue;
      const lineLength = (i) => words[i].length * wordTime + lineGap;
      const cycle = lines.reduce((sum, _, i) => sum + lineLength(i), 0);
      let t = lyricClock % cycle;
      let current = 0;
      while (t > lineLength(current)) { t -= lineLength(current); current += 1; }
      lines.forEach((line, i) => {
        line.classList.toggle("future", i > current);
        line.classList.toggle("past", i < current);
        words[i].forEach((w, k) => {
          const p = i < current ? 1 : i > current ? 0 : Math.min(Math.max((t - k * wordTime) / wordTime, 0), 1);
          w.style.setProperty("--p", p.toFixed(3));
        });
      });
      if (blocks[0].lines === lines && islandLines[0].textContent !== lines[current].textContent) {
        islandLines.forEach((el) => (el.textContent = lines[current].textContent));
      }
    }
  }

  const lyricsVisible = () => blocks.some((b) => b.visible);

  // One clock drives everything that moves.
  let last = performance.now();
  let sinceTrack = 0;
  function tick(now) {
    const dt = Math.min((now - last) / 1000, 0.1);
    last = now;
    if (playing) {
      position = Math.min(position + dt, tracks[trackIndex].length);
      updateProgress();
      if (lyricsVisible()) lyricClock += dt;
    }
    timerLeft = timerLeft > 0 ? timerLeft - dt : 25 * 60;
    countdowns.forEach((el) => (el.textContent = clock(timerLeft)));
    // While the hero and the player chapter are on screen, play through the "album".
    sinceTrack += dt;
    if (!reducedMotion && playing && !hovering && sinceTrack > 9 && ["compact", "expanded"].includes(sectionState)) {
      sinceTrack = 0;
      showTrack(trackIndex + 1);
    }
    paintLyrics();
    requestAnimationFrame(tick);
  }

  showTrack(0, { shimmer: false });
  render();
  paintLyrics();
  requestAnimationFrame(tick);
})();

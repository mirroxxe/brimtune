// The tour's choreography: for each step, a short film of the island being used on a Mac.
// A pointer goes where a person would go, things react (hover, press, type, drag), and the
// scene loops while the step is on screen. motion.js picks the step; this file plays it.
//
//   window.brimtuneTour.enter(stepKey)   start that step's film (after resetting the last one)
//   window.brimtuneTour.pause(bool)      pause or resume (the tour is off screen, or not)
(() => {
  const stage = document.querySelector(".tour-stage");
  const island = stage?.querySelector(".tour-island");
  const { gsap } = window;
  if (!stage || !island || !gsap) return;
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const cursor = stage.querySelector(".cursor");
  const tip = cursor.querySelector(".cursor-tip");
  const menuIcon = stage.querySelector(".mb-icon");
  const windowEl = stage.querySelector(".tour-window");
  const q = (selector) => island.querySelector(selector);
  const qa = (selector) => [...island.querySelectorAll(selector)];

  let tl = null;
  gsap.set(cursor, { x: 0, y: 0, transformOrigin: "3px 2px" });

  // ---------- Small tools ----------

  const state = (name) => {
    island.dataset.state = name;
    window.brimtuneFit?.(island);
    window.brimtuneFitStage?.();
  };
  const scene = (name) => { stage.dataset.scene = name; };

  // Where something is, in the stage's own pixels (the stage may be scaled while it rises in).
  const pt = (el, fx = 0.5, fy = 0.5) => {
    const box = stage.getBoundingClientRect(), r = el.getBoundingClientRect();
    const k = box.width / stage.clientWidth || 1;
    return { x: (r.left + r.width * fx - box.left) / k, y: (r.top + r.height * fy - box.top) / k };
  };
  const put = (el, fx, fy) => { const p = pt(el, fx, fy); gsap.set(cursor, p); };

  const say = (text) => {
    tip.textContent = text;
    // The tip goes to the other side of the pointer when it would run off the stage.
    cursor.classList.remove("flip");
    const x = gsap.getProperty(cursor, "x");
    cursor.classList.toggle("flip", x + 34 + tip.offsetWidth > stage.clientWidth - 12);
    cursor.classList.add("show-tip");
  };
  const hush = () => cursor.classList.remove("show-tip");

  const setText = (selector, text) => qa(selector).forEach((el) => (el.textContent = text));
  const hot = (el, on = true) => el?.classList.toggle("hot", on);
  const cls = (name, on = true) => island.classList.toggle(name, on);

  // The cursor's moves, as timeline steps. Targets are looked up when the move starts, after
  // the island has settled, so they land where the thing really is.
  function glide(at, target, { dur = 1, fx = 0.5, fy = 0.5, ease = "power2.inOut" } = {}) {
    tl.to(cursor, {
      x: () => pt(typeof target === "function" ? target() : target, fx, fy).x,
      y: () => pt(typeof target === "function" ? target() : target, fx, fy).y,
      duration: dur, ease,
    }, at);
  }
  function press(at) {
    tl.call(() => { cursor.classList.remove("click"); void cursor.offsetWidth; cursor.classList.add("click"); }, null, at);
    tl.to(cursor, { scale: 0.8, duration: 0.08, yoyo: true, repeat: 1, ease: "power1.inOut" }, at);
  }
  const show = (at) => tl.to(cursor, { opacity: 1, duration: 0.4 }, at);
  const away = (at) => { tl.call(hush, null, at); tl.to(cursor, { opacity: 0, duration: 0.4 }, at); };

  // Everything a film changes goes back to how it started.
  function reset() {
    ["s-vol-hot", "s-vol-drag", "s-focus", "s-typing", "s-pick", "s-played", "s-page2", "s-paused", "s-joined"].forEach((c) => island.classList.remove(c));
    stage.classList.remove("s-menu", "s-sub");
    stage.querySelectorAll(".hot, .hit").forEach((el) => el.classList.remove("hot", "hit"));
    stage.querySelectorAll(".mm-sub p").forEach((p) => p.classList.remove("on"));
    island.style.removeProperty("--vol");
    island.querySelector(".volume")?.classList.remove("v0", "v1", "v3");
    island.querySelector(".volume")?.classList.add("v2");
    setText(".vol-bubble", "62");
    setText(".typed", "");
    qa(".view-search .typed").forEach((el) => (el.textContent = ""));
    // The song the film picked goes back to what the page is playing.
    island.removeAttribute("data-lock");
    window.brimtuneRestoreTrack?.();
    qa(".cover-lg").forEach((el) => { el.style.removeProperty("--c1"); el.style.removeProperty("--c2"); el.style.removeProperty("--c3"); });
    qa(".songs li").forEach((li, i) => li.classList.toggle("now", i === 0));
    gsap.set(windowEl, { clearProps: "all" });
    stage.querySelector(".v-esc")?.classList.remove("hit");
    scene("browser");
    hush();
  }

  function pick(title, artist, colours) {
    island.dataset.lock = "";
    setText(".track-title", title);
    setText(".track-artist", artist);
    qa(".cover-lg").forEach((el) => { el.style.setProperty("--c1", colours[0]); el.style.setProperty("--c2", colours[1]); el.style.setProperty("--c3", colours[2]); });
    cls("s-played", false); void island.offsetWidth; cls("s-played");
  }

  // The speaker steps through its waves as the level changes.
  function level(v) {
    island.style.setProperty("--vol", v.toFixed(3));
    setText(".vol-bubble", String(Math.round(v * 100)));
    qa(".volume").forEach((el) => {
      el.classList.remove("v0", "v1", "v2", "v3");
      el.classList.add(v < 0.005 ? "v0" : v < 0.34 ? "v1" : v < 0.67 ? "v2" : "v3");
    });
  }

  // ---------- The films ----------

  // What a film starts from: set now, and set again at the top of every loop.
  const begin = (t, fn) => { fn(); t.call(fn, null, 0); };

  const films = {
    // 1. It lives in the notch: it names each new song, then tucks away.
    compact(t) {
      begin(t, () => state("compact"));
      t.call(() => state("peek"), null, 1.1);
      t.call(() => state("compact"), null, 3.9);
      t.to({}, { duration: 6.2 }, 0);
    },

    // 2. Hover, and it opens up: the volume slider, a pause, a play.
    expanded(t) {
      begin(t, () => state("compact"));
      t.set(cursor, { x: stage.clientWidth * 0.8, y: stage.clientHeight * 0.14, opacity: 0 }, 0);
      show(0.2);
      glide(0.3, () => stage.querySelector(".tour-island-wrap"), { dur: 1.1, fy: 0.45 });
      t.call(() => state("expanded"), null, 1.5);
      glide(2.7, () => q(".view-expanded .vol-thumb"), { dur: 1 });
      t.call(() => { cls("s-vol-hot"); say("Drag to set the music's volume"); }, null, 3.4);
      press(3.8);
      t.call(() => cls("s-vol-drag"), null, 3.9);
      const v = { x: 0.62 };
      t.to(v, {
        x: 0.14, duration: 0.9, ease: "power2.inOut",
        onUpdate: () => { level(v.x); put(q(".view-expanded .vol-thumb"), 0.5, 0.5); },
      }, 4.0);
      t.to(v, {
        x: 0.86, duration: 1.5, ease: "power2.inOut",
        onUpdate: () => { level(v.x); put(q(".view-expanded .vol-thumb"), 0.5, 0.5); },
      }, 5.0);
      t.call(() => { cls("s-vol-drag", false); hush(); }, null, 6.6);
      glide(6.8, () => q(".view-expanded .ctl-play"), { dur: 0.9 });
      t.call(() => { hot(q(".view-expanded .ctl-play")); say("Play, pause, skip"); }, null, 7.7);
      press(8.0);
      t.call(() => cls("s-paused"), null, 8.05);
      press(9.3);
      t.call(() => cls("s-paused", false), null, 9.35);
      t.call(() => { hot(q(".view-expanded .ctl-play"), false); hush(); }, null, 9.9);
      t.to({}, { duration: 11.2 }, 0);
    },

    // 3. Find any song: click, type, results rise, Return plays the first.
    search(t) {
      begin(t, () => state("expanded"));
      t.set(cursor, { x: stage.clientWidth * 0.78, y: stage.clientHeight * 0.2, opacity: 0 }, 0);
      show(0.4);
      glide(0.6, () => q(".view-expanded .search-field"), { dur: 1.1, fx: 0.4 });
      t.call(() => say("Click, type, press Return"), null, 1.5);
      press(1.8);
      t.call(() => cls("s-focus"), null, 1.85);
      const text = "paper moons", n = { c: 0 };
      t.to(n, {
        c: text.length, duration: 1.2, ease: "none", delay: 0.3,
        onUpdate: () => {
          const typed = text.slice(0, Math.round(n.c));
          setText(".typed", typed);
          if (typed.length >= 3 && island.dataset.state !== "search") { cls("s-focus", false); state("search"); }
        },
      }, 2.2);
      glide(4.2, () => q(".view-search .result.first"), { dur: 1, fx: 0.3 });
      t.call(() => { cls("s-pick"); say("Return plays it"); }, null, 5.3);
      press(5.9);
      t.call(() => { cls("s-pick", false); pick("Paper Moons", "Orla Vey", ["#3FB6C9", "#4B5BD6", "#C8F08F"]); setText(".typed", ""); state("expanded"); hush(); }, null, 6.0);
      away(7.2);
      t.to({}, { duration: 9 }, 0);
    },

    // 4. Up Next: open it, flip through with the arrows, pick a song.
    upnext(t) {
      begin(t, () => state("expanded"));
      t.set(cursor, { x: stage.clientWidth * 0.8, y: stage.clientHeight * 0.3, opacity: 0 }, 0);
      show(0.4);
      glide(0.6, () => q(".view-expanded .x-upnext-row"), { dur: 1.1, fx: 0.2 });
      t.call(() => { hot(q(".view-expanded .x-upnext-row")); say("Open Up Next"); }, null, 1.6);
      press(2.0);
      t.call(() => { hot(q(".view-expanded .x-upnext-row"), false); state("upnext"); hush(); }, null, 2.05);
      glide(3.1, () => qa(".view-upnext .pager .chev").pop(), { dur: 1 });
      t.call(() => { hot(qa(".view-upnext .pager .chev").pop()); say("Page through the queue"); }, null, 4.0);
      press(4.3);
      t.call(() => cls("s-page2"), null, 4.35);
      press(5.6);
      t.call(() => { cls("s-page2", false); }, null, 5.65);
      t.call(() => hot(qa(".view-upnext .pager .chev").pop(), false), null, 6.0);
      glide(6.0, () => q(".view-upnext .up-list:first-child .up-item:nth-child(2)"), { dur: 0.9, fx: 0.3 });
      t.call(() => { hot(q(".view-upnext .up-list:first-child .up-item:nth-child(2)")); say("Jump straight to a song"); }, null, 6.9);
      press(7.3);
      t.call(() => { pick("Kyiv, 5 a.m.", "Teo Brann", ["#FF8A4C", "#C2367A", "#FFD36E"]); hot(q(".view-upnext .up-list:first-child .up-item:nth-child(2)"), false); hush(); }, null, 7.35);
      away(8.6);
      t.to({}, { duration: 10 }, 0);
    },

    // 5. Playlists: open one (the player slides away), play a song from it.
    playlist(t) {
      begin(t, () => state("expanded"));
      t.set(cursor, { x: stage.clientWidth * 0.8, y: stage.clientHeight * 0.5, opacity: 0 }, 0);
      show(0.4);
      glide(0.6, () => q(".view-expanded .shelf .pl"), { dur: 1.2 });
      t.call(() => { hot(q(".view-expanded .shelf .pl")); say("Open a playlist"); }, null, 1.8);
      press(2.2);
      t.call(() => { hot(q(".view-expanded .shelf .pl"), false); state("playlist"); hush(); }, null, 2.25);
      glide(3.4, () => q(".view-playlist .songs li:nth-child(4)"), { dur: 1, fx: 0.4 });
      t.call(() => { hot(q(".view-playlist .songs li:nth-child(4)")); say("Play any song"); }, null, 4.3);
      press(4.8);
      t.call(() => {
        qa(".view-playlist .songs li").forEach((li) => li.classList.remove("now"));
        const row = q(".view-playlist .songs li:nth-child(4)");
        row.classList.add("now");
        hot(row, false);
        pick("Glasshouse", "Mira Sol", ["#7C6CF2", "#241D5C", "#B6F0E4"]);
        hush();
      }, null, 4.85);
      away(6.2);
      t.to({}, { duration: 8.2 }, 0);
    },

    // 6. Lyrics: the full-screen player; clicking a line syncs to it.
    lyrics(t) {
      begin(t, () => { state("compact"); scene("stage"); });
      t.set(cursor, { x: stage.clientWidth * 0.82, y: stage.clientHeight * 0.85, opacity: 0 }, 0);
      show(0.8);
      glide(1.0, () => stage.querySelector(".stage-lyrics p:nth-child(4)"), { dur: 1.4, fx: 0.25 });
      t.call(() => say("Running early? Click a line to sync"), null, 2.4);
      press(3.2);
      t.call(() => { window.brimtuneSeekLine?.(3); hush(); }, null, 3.25);
      away(4.6);
      t.to({}, { duration: 6.6 }, 0);
    },

    // 7. Timers: from the menu bar icon, pick 25 minutes.
    timer(t) {
      begin(t, () => state("compact"));
      t.set(cursor, { x: stage.clientWidth * 0.6, y: stage.clientHeight * 0.5, opacity: 0 }, 0);
      show(0.4);
      glide(0.6, () => menuIcon, { dur: 1.1 });
      t.call(() => { hot(menuIcon); say("Brimtune's menu bar icon"); }, null, 1.7);
      press(2.1);
      t.call(() => { stage.classList.add("s-menu"); hush(); }, null, 2.15);
      glide(2.9, () => stage.querySelector(".mm-timer"), { dur: 0.8, fx: 0.4 });
      t.call(() => stage.classList.add("s-sub"), null, 3.8);
      glide(4.0, () => stage.querySelector(".mm-sub .m25"), { dur: 0.8, fx: 0.4 });
      t.call(() => stage.querySelector(".mm-sub .m25").classList.add("on"), null, 4.9);
      press(5.2);
      t.call(() => {
        stage.classList.remove("s-menu", "s-sub");
        hot(menuIcon, false);
        window.brimtuneTimerReset?.();
        state("timer");
      }, null, 5.3);
      t.call(() => say("It counts down beside the cover"), null, 6.2);
      away(8.2);
      t.call(() => stage.querySelector(".mm-sub .m25").classList.remove("on"), null, 8.5);
      t.to({}, { duration: 10.4 }, 0);
    },

    // 8. Meetings: it drops down five minutes before; Join.
    meeting(t) {
      begin(t, () => state("compact"));
      t.set(cursor, { x: stage.clientWidth * 0.8, y: stage.clientHeight * 0.4, opacity: 0 }, 0);
      t.call(() => state("meeting"), null, 1.0);
      show(1.6);
      glide(1.8, () => q(".view-meeting .join"), { dur: 1.1 });
      t.call(() => { hot(q(".view-meeting .join")); say("Join the call in one click"); }, null, 2.9);
      press(3.5);
      t.call(() => { cls("s-joined"); hot(q(".view-meeting .join"), false); setText(".view-meeting .join", "Joined"); hush(); }, null, 3.55);
      t.call(() => state("compact"), null, 5.2);
      t.call(() => setText(".view-meeting .join", "Join"), null, 5.9);
      away(5.2);
      t.to({}, { duration: 7.6 }, 0);
    },

    // 9. AirPods: connect, with their battery.
    airpods(t) {
      begin(t, () => state("compact"));
      t.set(cursor, { opacity: 0 }, 0);
      const pct = { n: 0 };
      t.call(() => { state("airpods"); pct.n = 0; }, null, 1.0);
      t.to(pct, { n: 82, duration: 1.5, delay: 0.35, ease: "power2.out", onUpdate: () => setText(".view-airpods .pct", String(Math.round(pct.n))) }, 1.0);
      t.call(() => state("compact"), null, 5.2);
      t.to({}, { duration: 6.8 }, 0);
    },

    // 10. Full screen: the window goes full screen and the island steps aside; Esc brings it back.
    fullscreen(t) {
      begin(t, () => { state("compact"); scene("browser"); });
      t.set(cursor, { x: stage.clientWidth * 0.5, y: stage.clientHeight * 0.9, opacity: 0 }, 0);
      show(0.4);
      const dot = () => stage.querySelector(".tw-bar i:nth-child(3)");
      glide(0.6, dot, { dur: 1.2 });
      t.call(() => { hot(dot()); say("Go full screen"); }, null, 1.8);
      press(2.2);
      t.to(windowEl, { left: "0%", right: "0%", bottom: "0%", height: "104%", borderRadius: 0, duration: 0.8, ease: "power3.inOut" }, 2.3);
      t.call(() => { hot(dot(), false); hush(); state("hidden"); scene("video"); }, null, 2.75);
      away(2.8);
      t.call(() => { stage.querySelector(".v-esc")?.classList.add("hit"); }, null, 5.6);
      t.call(() => { stage.querySelector(".v-esc")?.classList.remove("hit"); scene("browser"); state("compact"); }, null, 6.3);
      t.to(windowEl, { clearProps: "all", duration: 0 }, 6.4);
      t.to({}, { duration: 8.4 }, 0);
    },
  };

  window.brimtuneTour = {
    enter(key) {
      tl?.kill();
      reset();
      gsap.set(cursor, { opacity: 0 });
      const film = films[key];
      if (!film || reduced) return;
      tl = gsap.timeline({ repeat: -1, delay: 0.5 });
      tl.call(reset, null, 0);
      film(tl);
    },
    pause(paused) { tl?.paused(paused); },
  };
})();

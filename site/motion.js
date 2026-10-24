// Scroll-linked motion: smooth scrolling (Lenis) and scenes scrubbed by the scroll (GSAP ScrollTrigger).
// Without GSAP the page keeps its static layout. With reduced motion there's no smooth scrolling,
// and scenes switch between their start and end instead of gliding.
(() => {
  const { gsap, ScrollTrigger, Lenis } = window;
  const html = document.documentElement;
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  // Without the library (or with reduced motion) the hero simply shows, no intro.
  if (!gsap || !ScrollTrigger) return html.classList.add("intro-done");
  if (reduced) html.classList.add("intro-done");
  gsap.registerPlugin(ScrollTrigger);
  html.classList.add("motion");
  const finePointer = matchMedia("(hover: hover) and (pointer: fine)").matches;
  const phone = () => innerWidth <= 760;
  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

  // ---------- Smooth scrolling ----------


  let lenis;
  if (!reduced && Lenis) {
    lenis = new Lenis({ lerp: 0.1 });
    lenis.on("scroll", ScrollTrigger.update);
    window.brimtuneLenis = lenis;
    gsap.ticker.add((time) => lenis.raf(time * 1000));
    gsap.ticker.lagSmoothing(0);
  }
  document.querySelectorAll('a[href^="#"]:not(.skip)').forEach((link) => {
    link.addEventListener("click", (e) => {
      const target = document.querySelector(link.getAttribute("href"));
      if (!target) return;
      e.preventDefault();
      if (!lenis) return target.scrollIntoView();
      // A link in the download dialog: scrolling was paused behind it. Lenis.start() resets
      // any scroll in flight, so resume before starting this one, not after.
      if (lenis.isStopped) lenis.start();
      // Long jumps get more time, so the page glides past the scenes instead of flashing by.
      const distance = Math.abs(target.getBoundingClientRect().top);
      lenis.scrollTo(target, {
        duration: clamp(distance / 5000, 1.1, 3),
        easing: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
      });
    });
  });

  // A timeline tied to a stretch of scroll: scrubbed, or (reduced motion) flipped at a point.
  function scene(trigger, timeline, { start = "top top", end = "bottom bottom", flipAt = 0.4 } = {}) {
    if (reduced) {
      timeline.pause();
      const flip = (self) => timeline.progress(self.progress > flipAt ? 1 : 0);
      return ScrollTrigger.create({ trigger, start, end, onUpdate: flip, onRefresh: flip });
    }
    return ScrollTrigger.create({ trigger, start, end, scrub: 0.6, animation: timeline, invalidateOnRefresh: true });
  }

  // Wraps every word of an element in a span, keeping the spaces and any inline elements (an <em>).
  function splitWords(el, className) {
    const spans = [];
    const walk = (parent) => {
      [...parent.childNodes].forEach((node) => {
        if (node.nodeType === Node.ELEMENT_NODE) return walk(node);
        if (node.nodeType !== Node.TEXT_NODE) return;
        const parts = document.createDocumentFragment();
        node.textContent.split(/(\s+)/).forEach((part) => {
          if (!part) return;
          if (/^\s+$/.test(part)) return parts.append(part);
          const span = document.createElement("span");
          span.className = className;
          span.textContent = part;
          spans.push(span);
          parts.append(span);
        });
        node.replaceWith(parts);
      });
    };
    walk(el);
    return spans;
  }

  // ---------- Hero: the screen steps back into a MacBook on its lock screen ----------

  const hero = document.querySelector(".hero");
  const device = document.getElementById("device");
  const screen = device.querySelector(".screen");
  const lock = device.querySelector(".lock");
  const after = hero.querySelector(".hero-after");

  // Where the MacBook ends up: under the heading, as big as fits, 16:10.
  function finalBox() {
    const vw = innerWidth;
    const vh = innerHeight;
    const top = after.offsetTop + after.offsetHeight + (phone() ? 28 : 40);
    const w = Math.min(vw * (phone() ? 0.9 : 0.84), (vh - top - (phone() ? 48 : 56)) * 1.6, 1180);
    const h = w / 1.6;
    // On a phone there's room to spare below, so the MacBook sits closer to its heading.
    const centre = top + (vh - top - h) * (phone() ? 0.3 : 0.5) + h / 2;
    return { w, h, y: centre - vh / 2 };
  }
  function sizeLock() {
    const { w, h } = finalBox();
    lock.style.setProperty("--lw", `${w}px`);
    lock.style.setProperty("--lh", `${h}px`);
  }
  sizeLock();
  ScrollTrigger.addEventListener("refreshInit", sizeLock);

  gsap.set(device, { xPercent: -50, yPercent: -50, x: 0, y: 0 });
  const chips = hero.querySelector(".hero-stage");
  const afterWords = splitWords(after.querySelector("h2"), "ww");

  // Each widget flies away from the centre, the way it sits around it.
  const away = (axis, k) => (i, el) => {
    const centre = axis === "x" ? el.offsetLeft + el.offsetWidth / 2 - chips.clientWidth / 2 : el.offsetTop + el.offsetHeight / 2 - chips.clientHeight / 2;
    return centre * k;
  };

  const heroTl = gsap.timeline({ defaults: { ease: "none" } })
    // The widgets scatter and the headline lifts away, line by line.
    .to(".hero-chip", { x: away("x", 1.1), y: away("y", 1.1), rotate: (i, el) => (el.offsetLeft > chips.clientWidth / 2 ? 14 : -14), scale: 0.7, opacity: 0, filter: "blur(14px)", duration: 0.34, ease: "power2.in" }, 0)
    .to(".kicker", { y: -50, opacity: 0, duration: 0.2 }, 0)
    .to(".h-line", { yPercent: (i) => (i ? -60 : -110), opacity: 0, filter: "blur(18px)", scale: 0.92, stagger: 0.05, duration: 0.3 }, 0.02)
    .to(".hero-block", { y: -70, opacity: 0, filter: "blur(10px)", duration: 0.24 }, 0.04)
    .to(".scroll-cue, .hero-grid", { opacity: 0, duration: 0.12 }, 0)
    .to(".hero-copy", { opacity: 0, duration: 0.18 }, 0.14)
    // A ring of light goes out from the middle as it happens.
    .fromTo(".hero-pulse", { scale: 0.2, opacity: 0 }, { scale: 1.2, opacity: 0.5, duration: 0.14 }, 0)
    .to(".hero-pulse", { scale: 2.6, opacity: 0, duration: 0.4, ease: "power1.out" }, 0.14)
    // The light itself leans in while the screen steps back into a MacBook.
    .to(".aurora-field", { scale: 1.3, rotate: 10, duration: 0.95 }, 0)
    .to(device, { width: () => finalBox().w, height: () => finalBox().h, y: () => finalBox().y, duration: 0.68, ease: "power2.inOut" }, 0.06)
    .to(screen, { "--r": () => (phone() ? "12px" : "22px"), "--bezel": () => (phone() ? 6 : 12), duration: 0.45 }, 0.3)
    .to(".mb-notch, .mb-base", { opacity: 1, duration: 0.2 }, 0.56)
    .to(lock, { opacity: 1, duration: 0.3 }, 0.32)
    .fromTo(after, { opacity: 0, y: 50 }, { opacity: 1, y: 0, duration: 0.3 }, 0.5)
    .fromTo(afterWords, { opacity: 0, yPercent: 70, filter: "blur(12px)" }, { opacity: 1, yPercent: 0, filter: "blur(0px)", stagger: 0.06, duration: 0.26, ease: "power2.out" }, 0.52)
    .to({}, { duration: 0.18 });
  scene(hero, heroTl, { flipAt: 0.25 });

  // ---------- Hero intro: the light comes up, the headline rises, the widgets pop in ----------

  if (!reduced) {
    const pop = [".aurora", ".hero-grid", ".kicker [data-in]", ".h-word", ".hero-block [data-in]", ".chip-card", ".scroll-cue"].join(",");
    const run = () => {
      const intro = gsap.timeline({
        defaults: { ease: "power3.out" },
        onComplete: () => { html.classList.add("intro-done"); gsap.set(hero.querySelectorAll(pop), { clearProps: "all" }); },
      });
      intro
        .fromTo(".hero .aurora", { opacity: 0 }, { opacity: 1, duration: 2.2, ease: "power2.out" }, 0)
        .fromTo(".hero .hero-grid", { opacity: 0 }, { opacity: 1, duration: 2.4 }, 0.3)
        .fromTo(".kicker [data-in]", { opacity: 0, y: 18, filter: "blur(8px)" }, { opacity: 1, y: 0, filter: "blur(0px)", duration: 0.9 }, 0.2)
        .fromTo(".h-word", { yPercent: 110 }, { yPercent: 0, duration: 1.25, stagger: 0.1, ease: "power4.out" }, 0.3)
        .fromTo(".hero-block [data-in]", { opacity: 0, y: 26, filter: "blur(8px)" }, { opacity: 1, y: 0, filter: "blur(0px)", duration: 1, stagger: 0.12 }, 0.85)
        .fromTo(".chip-card", { opacity: 0, scale: 0.55, y: 40, filter: "blur(16px)" }, { opacity: 1, scale: 1, y: 0, filter: "blur(0px)", duration: 1.3, stagger: { each: 0.13, from: "random" }, ease: "back.out(1.6)" }, 0.7)
        .fromTo(".scroll-cue", { opacity: 0 }, { opacity: 1, duration: 1 }, 1.8);
    };
    // Wait for the fonts, so the headline doesn't jump when they arrive.
    Promise.race([document.fonts?.ready, new Promise((r) => setTimeout(r, 1200))]).then(run);
  }

  // ---------- The pointer: the light and the widgets lean toward it ----------

  if (finePointer && !reduced) {
    const target = { x: 0, y: 0 }, now = { x: 0, y: 0 };
    let heroOn = true;
    hero.addEventListener("pointermove", (e) => {
      const r = screen.getBoundingClientRect();
      target.x = ((e.clientX - r.left) / r.width) * 2 - 1;
      target.y = ((e.clientY - r.top) / r.height) * 2 - 1;
    });
    hero.addEventListener("pointerleave", () => { target.x = 0; target.y = 0; });
    ScrollTrigger.create({ trigger: hero, start: "top top", end: "+=60%", onToggle: (self) => (heroOn = self.isActive) });
    gsap.ticker.add(() => {
      if (!heroOn) return;
      now.x += (target.x - now.x) * 0.06;
      now.y += (target.y - now.y) * 0.06;
      screen.style.setProperty("--mx", now.x.toFixed(4));
      screen.style.setProperty("--my", now.y.toFixed(4));
      screen.style.setProperty("--sx", (0.5 + now.x / 2).toFixed(4));
      screen.style.setProperty("--sy", (0.5 + now.y / 2).toFixed(4));
    });
  }

  // ---------- Headings that arrive word by word, statements that sharpen as you read ----------

  document.querySelectorAll("[data-words]").forEach((el) => {
    const words = splitWords(el, "ww");
    if (reduced) return;
    gsap.from(words, {
      opacity: 0, yPercent: 45, filter: "blur(12px)", duration: 1.1, ease: "power3.out", stagger: 0.07,
      scrollTrigger: { trigger: el, start: "top 86%" },
    });
  });

  document.querySelectorAll("[data-scrub-words]").forEach((el) => {
    const words = splitWords(el, "sw");
    if (reduced) return;
    gsap.fromTo(words, { opacity: 0.12, filter: "blur(5px)" }, {
      opacity: 1, filter: "blur(0px)", ease: "none", stagger: 0.1,
      scrollTrigger: { trigger: el, start: "top 82%", end: "bottom 45%", scrub: 0.6 },
    });
  });

  document.querySelectorAll("[data-count]").forEach((el) => {
    const value = parseFloat(el.dataset.count);
    const decimals = Number(el.dataset.decimals || 0);
    if (reduced || value === 0) return;
    const counter = { v: 0 };
    el.textContent = (0).toFixed(decimals);
    gsap.to(counter, {
      v: value, duration: 1.8, ease: "power3.out",
      onUpdate: () => (el.textContent = counter.v.toFixed(decimals)),
      scrollTrigger: { trigger: el, start: "top 88%" },
    });
  });

  if (!reduced) {
    ScrollTrigger.batch("[data-reveal]", {
      start: "top 88%",
      onEnter: (els) => gsap.fromTo(els, { opacity: 0, y: 48 }, { opacity: 1, y: 0, duration: 1, ease: "power3.out", stagger: 0.1 }),
    });
    gsap.set("[data-reveal]", { opacity: 0 });
  }

  // ---------- The tour: one island, eight things it does ----------

  const tour = document.querySelector(".tour");
  const steps = [...tour.querySelectorAll("[data-step]")];
  const stage = tour.querySelector(".tour-stage");
  const tourIsland = tour.querySelector(".tour-island");
  const wrap = tour.querySelector(".tour-island-wrap");
  const counter = tour.querySelector(".tour-n");
  const progressBar = tour.querySelector(".tour-progress span");
  const indexItems = [...tour.querySelectorAll(".tour-index li")];
  let stepIndex = -1;
  let typing;

  // Scale the island so the current state fills the screen without spilling over.
  function fitIsland() {
    const style = getComputedStyle(tourIsland);
    const w = parseFloat(style.getPropertyValue("--w"));
    const h = parseFloat(style.getPropertyValue("--h"));
    // The layout size, not the drawn one: the stage is still scaling up as it scrolls in.
    const box = { width: stage.clientWidth, height: stage.clientHeight };
    const s = clamp(Math.min((box.width * 0.88) / w, (box.height * 0.8) / h, phone() ? 1.25 : 1.7), 0.6, 1.7);
    wrap.style.setProperty("--s", s.toFixed(3));
  }

  // The search step types its query, like someone's using it.
  function typeQuery() {
    const field = tourIsland.querySelector(".typed");
    const query = "paper moons";
    clearInterval(typing);
    if (reduced) return (field.textContent = query);
    let n = 0;
    field.textContent = "";
    typing = setInterval(() => {
      field.textContent = query.slice(0, ++n);
      if (n >= query.length) clearInterval(typing);
    }, 70);
  }

  function showStep(i) {
    if (i === stepIndex) return;
    stepIndex = i;
    steps.forEach((step, k) => step.classList.toggle("on", k === i));
    indexItems.forEach((item, k) => item.classList.toggle("on", k === i));
    tourIsland.dataset.state = steps[i].dataset.step;
    counter.textContent = String(i + 1).padStart(2, "0");
    fitIsland();
    if (steps[i].dataset.step === "search") typeQuery();
  }
  showStep(0);
  ScrollTrigger.create({
    trigger: tour, start: "top top", end: "bottom bottom",
    onUpdate: (self) => {
      showStep(Math.min(steps.length - 1, Math.floor(self.progress * steps.length)));
      progressBar.style.transform = `scaleX(${self.progress})`;
    },
    onRefresh: fitIsland,
  });

  // ---------- The full-screen player: scrolling sings the lyrics ----------

  const player = document.querySelector(".player");
  const lyricBox = player.querySelector(".scroll-lyrics");
  const lyricTrack = player.querySelector(".sl-track");
  const lyricLines = [...lyricTrack.querySelectorAll("p")];
  const lineWords = lyricLines.map((line) => splitWords(line, "w"));
  const allWords = lineWords.flat();
  let lyricLine = -1;

  function centreLine(i, instant) {
    const line = lyricLines[i];
    const y = lyricBox.clientHeight * 0.42 - (line.offsetTop + line.offsetHeight / 2);
    gsap.to(lyricTrack, { y, duration: instant || reduced ? 0 : 0.8, ease: "power3.out", overwrite: true });
  }

  function sing(progress) {
    // A little lead-in before the first word, and a moment after the last.
    const at = progress * (allWords.length + 3) - 1.5;
    allWords.forEach((w, k) => w.style.setProperty("--p", clamp(at - k, 0, 1).toFixed(3)));
    let reached = 0;
    let line = 0;
    lineWords.forEach((words, i) => {
      if (at >= reached) line = i;
      reached += words.length;
    });
    lyricLines.forEach((p, i) => {
      p.classList.toggle("past", i < line);
      p.classList.toggle("future", i > line);
    });
    if (line !== lyricLine) {
      lyricLine = line;
      centreLine(line);
    }
  }
  sing(0);
  ScrollTrigger.create({
    trigger: player, start: "top top", end: "bottom bottom",
    onUpdate: (self) => sing(self.progress),
    onRefresh: () => lyricLine >= 0 && centreLine(lyricLine, true),
  });
  if (!reduced) {
    gsap.fromTo(".player-cover .cover", { scale: 0.82, rotate: -5 }, {
      scale: 1, rotate: 0, ease: "none",
      scrollTrigger: { trigger: player, start: "top bottom", end: "top top", scrub: 0.6 },
    });
  }

  // The live waveform: made-up audio, drawn only while the player is on screen.
  const wave = player.querySelector(".wave");
  const barCount = phone() ? 36 : 72;
  const bars = Array.from({ length: barCount }, () => wave.appendChild(document.createElement("i")));
  const seeds = bars.map((_, i) => ({ a: 1.3 + ((i * 37) % 11) / 4, b: 2.1 + ((i * 53) % 7) / 3, phase: (i * 1.7) % 6.28 }));
  function drawWave(time) {
    const beat = Math.pow(Math.abs(Math.sin(time * 2.2)), 6) * 0.35;
    bars.forEach((bar, i) => {
      const s = seeds[i];
      const centre = 1 - Math.abs(i / (barCount - 1) - 0.5) * 1.1;
      const v = (0.2 + 0.5 * Math.abs(Math.sin(time * s.a + s.phase)) + 0.3 * Math.abs(Math.sin(time * s.b))) * centre + beat;
      bar.style.transform = `scaleY(${clamp(v, 0.08, 1).toFixed(3)})`;
    });
  }
  if (reduced) {
    drawWave(1.2);
  } else {
    let waveOn = false;
    ScrollTrigger.create({ trigger: player, start: "top bottom", end: "bottom top", onToggle: (self) => (waveOn = self.isActive) });
    gsap.ticker.add((time) => waveOn && drawWave(time));
  }

  // ---------- The little things: a sideways run on wide screens ----------

  const extras = document.querySelector(".extras");
  const extrasTrack = extras.querySelector(".extras-track");
  gsap.matchMedia().add("(min-width: 861px) and (prefers-reduced-motion: no-preference)", () => {
    extras.classList.add("sideways");
    const distance = () => Math.max(0, extrasTrack.scrollWidth - innerWidth);
    const setHeight = () => extras.style.setProperty("--extras-h", `${distance() + innerHeight}px`);
    setHeight();
    gsap.to(extrasTrack, {
      x: () => -distance(), ease: "none",
      scrollTrigger: { trigger: extras, start: "top top", end: () => `+=${distance()}`, scrub: 0.6, invalidateOnRefresh: true, onRefreshInit: setHeight },
    });
    return () => {
      extras.classList.remove("sideways");
      extras.style.removeProperty("--extras-h");
      gsap.set(extrasTrack, { clearProps: "transform" });
    };
  });

  // ---------- The idea's marquee, and the closing wordmark ----------

  if (!reduced) {
    document.querySelectorAll("[data-drift]").forEach((row) => {
      const dir = Number(row.dataset.drift);
      gsap.fromTo(row, { xPercent: dir > 0 ? -10 : 0 }, {
        xPercent: dir > 0 ? 8 : -22, ease: "none",
        scrollTrigger: { trigger: ".idea", start: "top bottom", end: "bottom top", scrub: 0.6 },
      });
    });
    gsap.fromTo(".wordmark", { yPercent: 60 }, {
      yPercent: 12, ease: "none",
      scrollTrigger: { trigger: ".closing", start: "top bottom", end: "bottom bottom", scrub: 0.6 },
    });
  }

  // ---------- Small things that make the whole page feel alive ----------

  // A line along the bottom of the window fills as you read down the page.
  gsap.to(".page-progress i", { scaleX: 1, ease: "none", scrollTrigger: { start: 0, end: "max", scrub: 0.3 } });

  // The menu pill follows where you are.
  const navLinks = [...document.querySelectorAll('.pillnav a[href^="#"]:not(.pill-cta)')];
  navLinks.forEach((link) => {
    const section = document.querySelector(link.getAttribute("href"));
    if (!section) return;
    ScrollTrigger.create({
      trigger: section, start: "top 55%", end: "bottom 55%",
      onToggle: (self) => link.classList.toggle("on", self.isActive),
    });
  });

  if (!reduced) {
    // Labels draw their line in; cards, rows and figures rise one after another.
    document.querySelectorAll(".sect-grid > .label").forEach((label) => {
      gsap.fromTo(label, { clipPath: "inset(0 100% 0 0)" }, { clipPath: "inset(0 0% 0 0)", duration: 1.2, ease: "power3.out", scrollTrigger: { trigger: label, start: "top 90%" } });
    });
    [".figure", ".whats-card", ".faq details"].forEach((selector) => {
      gsap.set(selector, { opacity: 0, y: 44 });
      ScrollTrigger.batch(selector, {
        start: "top 90%",
        onEnter: (els) => gsap.to(els, { opacity: 1, y: 0, duration: 1.1, ease: "power3.out", stagger: 0.12, overwrite: true }),
      });
    });
    gsap.fromTo(".whats-all", { opacity: 0, x: -16 }, { opacity: 1, x: 0, duration: 0.9, ease: "power3.out", scrollTrigger: { trigger: ".whats-all", start: "top 95%" } });

    // The tour's screen and the lock-screen MacBook's heading rise into place as they arrive.
    gsap.fromTo(".tour-stage", { scale: 0.9, y: 90, borderRadius: 48 }, {
      scale: 1, y: 0, borderRadius: phone() ? 20 : 32, ease: "none", immediateRender: false,
      scrollTrigger: { trigger: tour, start: "top 95%", end: "top 15%", scrub: 0.6 },
    });

    // The closing light breathes in as the footer comes near.
    gsap.fromTo(".closing .aurora-field", { scale: 1.35, rotate: -14 }, {
      scale: 1, rotate: 0, ease: "none",
      scrollTrigger: { trigger: ".closing", start: "top bottom", end: "center center", scrub: 0.6 },
    });
  }

  if (finePointer && !reduced) {
    // Buttons lean toward the pointer a little.
    document.querySelectorAll(".magnetic, .pill-cta, .closing .button").forEach((el) => {
      const x = gsap.quickTo(el, "x", { duration: 0.5, ease: "power3.out" });
      const y = gsap.quickTo(el, "y", { duration: 0.5, ease: "power3.out" });
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        x((e.clientX - (r.left + r.width / 2)) * 0.28);
        y((e.clientY - (r.top + r.height / 2)) * 0.4);
      });
      el.addEventListener("pointerleave", () => { x(0); y(0); });
    });

    // Cards tilt toward the pointer, in 3D.
    document.querySelectorAll(".card, .whats-card, .settings").forEach((el) => {
      const rx = gsap.quickTo(el, "rotationX", { duration: 0.6, ease: "power3.out" });
      const ry = gsap.quickTo(el, "rotationY", { duration: 0.6, ease: "power3.out" });
      gsap.set(el, { transformPerspective: 900 });
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        ry(((e.clientX - r.left) / r.width - 0.5) * 7);
        rx(-((e.clientY - r.top) / r.height - 0.5) * 7);
      });
      el.addEventListener("pointerleave", () => { rx(0); ry(0); });
    });
  }

  // Fonts change line lengths, so measure again once they're in.
  document.fonts?.ready.then(() => ScrollTrigger.refresh());
  addEventListener("load", () => ScrollTrigger.refresh());
})();

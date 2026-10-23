// Scroll-linked motion: smooth scrolling (Lenis) and scenes scrubbed by the scroll (GSAP ScrollTrigger).
// Without GSAP the page keeps its static layout. With reduced motion there's no smooth scrolling,
// and scenes switch between their start and end instead of gliding.
(() => {
  const { gsap, ScrollTrigger, Lenis } = window;
  if (!gsap || !ScrollTrigger) return;
  gsap.registerPlugin(ScrollTrigger);
  document.documentElement.classList.add("motion");

  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const phone = () => innerWidth <= 760;
  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

  // ---------- Smooth scrolling ----------


  let lenis;
  if (!reduced && Lenis) {
    lenis = new Lenis({ lerp: 0.1 });
    lenis.on("scroll", ScrollTrigger.update);
    gsap.ticker.add((time) => lenis.raf(time * 1000));
    gsap.ticker.lagSmoothing(0);
  }
  document.querySelectorAll('a[href^="#"]:not(.skip)').forEach((link) => {
    link.addEventListener("click", (e) => {
      const target = document.querySelector(link.getAttribute("href"));
      if (!target) return;
      e.preventDefault();
      lenis ? lenis.scrollTo(target, { duration: 1.6 }) : target.scrollIntoView();
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

  // Wraps every word of an element in a span, keeping the spaces.
  function splitWords(el, className) {
    const words = el.textContent.trim().split(/\s+/);
    el.textContent = "";
    return words.map((word, i) => {
      const span = document.createElement("span");
      span.className = className;
      span.textContent = word;
      el.append(span, i < words.length - 1 ? " " : "");
      return span;
    });
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
  const heroTl = gsap.timeline({ defaults: { ease: "none" } })
    .to(".hero-copy", { opacity: 0, y: -70, filter: "blur(14px)", duration: 0.32 }, 0)
    .to(".hero-art", { yPercent: -60, rotate: -16, scale: 0.8, opacity: 0, duration: 0.42 }, 0)
    .to(device, { width: () => finalBox().w, height: () => finalBox().h, y: () => finalBox().y, duration: 0.68, ease: "power2.inOut" }, 0.06)
    .to(screen, { "--r": () => (phone() ? "12px" : "22px"), "--bezel": () => (phone() ? 6 : 12), duration: 0.45 }, 0.3)
    .to(".mb-notch, .mb-base", { opacity: 1, duration: 0.2 }, 0.56)
    .to(lock, { opacity: 1, duration: 0.3 }, 0.32)
    .fromTo(after, { opacity: 0, y: 50 }, { opacity: 1, y: 0, duration: 0.3 }, 0.52)
    .to({}, { duration: 0.18 });
  scene(hero, heroTl, { flipAt: 0.25 });

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
    const box = stage.getBoundingClientRect();
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

  // Fonts change line lengths, so measure again once they're in.
  document.fonts?.ready.then(() => ScrollTrigger.refresh());
  addEventListener("load", () => ScrollTrigger.refresh());
})();

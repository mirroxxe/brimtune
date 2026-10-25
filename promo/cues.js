// One timeline for picture and sound: scene.js animates these moments, audio.mjs scores them.
// 120 BPM: a beat is 0.5 s, a bar 2 s. Times are seconds from the first frame.
export const FPS = 60;
export const DURATION = 15;
export const BPM = 120;

export const cue = {
  compact: 1.0,      // the notch grows its wings (cover + bars)
  hover: 1.85,       // pointer reaches the island
  open: 2.0,         // island springs open, drums enter
  next: 3.0,         // click ⏭ → Paper Moons, shimmer, room recolours
  search: 4.0,       // click the search field
  keys: [4.12, 4.24, 4.36, 4.48], // "kyiv"
  results: 4.55,
  enter: 4.85,       // Return → Kyiv, 5 a.m.
  shelf: [5.05, 5.2, 5.35], // pointer brushes the playlist covers
  expand: 5.75,      // click ↗ → full-screen player blooms from the cover
  full: 6.0,
  lock: 7.85,        // the Mac locks
  unlock: 9.75,      // whip up to the notch
  timer: 10.0,
  meeting: 10.5,
  airpods: 11.0,
  free: 11.5,
  download: 12.05,
  push: 12.2,
  logo: 12.5,        // match cut: the notch becomes the notch in the "B"
  wordmark: 12.85,
  url: 13.15,
};

// Made-up lyrics; the lit line's words land on eighth notes and the lead melody plays each one.
export const lyrics = [
  { text: "Trams are humming on the hill", start: 4.5 },
  { text: "the city wakes in amber light", start: 6.0 },
  { text: "and I hold the morning still", start: 7.5 },
  { text: "until the river turns to gold", start: 9.0 },
];
export const wordStep = 0.25;

// One timeline for picture and sound: scene.js animates these moments, audio.mjs scores them.
// 120 BPM: a beat is 0.5 s, a bar 2 s. Times are seconds from the first frame.
export const FPS = 60;
export const DURATION = 38;
export const BPM = 120;

export const cue = {
  // Hook (type on night)
  hook1: [0.4, 0.65, 0.9, 1.15, 1.4],          // "Your Mac has a notch."
  hook2: [2.0, 2.25, 2.5, 2.75, 3.0, 3.25],    // "What if it played your music?"
  wake: 3.0,         // the notch on the hook card grows its wings
  meet: 4.0,         // "Meet [icon] Brimtune."
  dive: 5.6,         // push into the icon's notch…
  mac: 6.0,          // …cut to the Mac's notch, pull back
  compact: 6.35,
  // On the Mac
  hover: 7.35,
  open: 7.5,
  volume: [8.75, 9.55], // drag the volume from 62 to 88
  leave: 9.95,
  play: 10.5,        // click ▶ on Paper Moons in the YouTube Music tab
  peek: 10.85,       // the island names the new song
  reopen: 12.45,
  search: 12.75,
  keys: [12.9, 13.02, 13.14, 13.26], // "kyiv"
  results: 13.35,
  enter: 13.65,
  shelf: [14.15, 14.35, 14.55],
  expand: 15.5,
  // Full-screen player
  full: 16.0,
  tabQueue: 18.0,
  tabLists: 18.9,
  lock: 19.85,
  // Lock screen, alerts, displays
  unlock: 21.8,
  timer: 22.0,
  meeting: 22.5,
  airpods: 23.0,
  displays: 23.6,
  pill: 24.3,
  // Cards
  stats: 26.0,
  bento: 29.0,
  free: 31.5,
  openSource: 32.25,
  download: 33.45,
  end: 34.0,
  wordmark: 34.35,
  url: 34.65,
  badges: 34.95,
};

// Made-up lyrics; the lit line's words land on eighth notes and the lead melody plays each one.
export const lyrics = [
  { text: "Trams are humming on the hill", start: 14.5 },
  { text: "the city wakes in amber light", start: 16.0 },
  { text: "and I hold the morning still", start: 17.5 },
  { text: "until the river turns to gold", start: 19.0 },
  { text: "every window keeps a song", start: 20.5 },
  { text: "Kyiv, five a.m., and we're home", start: 22.0 },
];
export const wordStep = 0.25;

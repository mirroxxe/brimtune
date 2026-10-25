# Brimtune promo (38 s)

A 38-second presentation video of Brimtune, made entirely from code: HTML/CSS/JS for the picture,
a small synthesiser for the music and sound design. Storyboard: [STORYBOARD.md](STORYBOARD.md).

```sh
cd promo
npm install            # puppeteer-core (drives your installed Google Chrome) + ffmpeg-static
node audio.mjs         # → out/audio.wav (music + SFX from cues.js)
node render.mjs        # → out/brimtune-promo.mp4 (1920×1080, 60 fps, H.264 yuv420p, AAC)
```

- `cues.js` — the shared timeline (seconds) that both the picture and the sound follow.
- `scene.js` + `promo.css` + `index.html` — the scene; `window.renderAt(t)` draws any moment.
  Preview: serve the folder (e.g. `npx http-server promo`) and open `index.html?play` (with sound,
  after `node audio.mjs`) or `index.html?t=6.2` to hold one moment.
- `render.mjs` — renders every frame in headless Chrome, 4 sub-frames per frame averaged for motion
  blur, in parallel workers; `--stills 1 2.5` for PNG stills, `--from 5 --to 7` for a part.
- `audio.mjs` — additive pad, FM keys/bells, drums and UI sounds, Freeverb-style room, normalised to −1 dBFS.

Songs, artists, covers and lyrics are all made up. `out/` (renders) is not committed.

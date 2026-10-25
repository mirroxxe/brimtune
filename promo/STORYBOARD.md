# Brimtune — 15-second promo: storyboard

**Format:** 1920×1080, 60 fps, H.264 yuv420p, AAC. 900 frames (0…899 / 60).
**Thread:** *the notch wakes up.* A black notch on a MacBook comes alive with music, grows into
everything Brimtune does, and at the end shrinks back into the notch cut into the Brimtune "B" icon.
**Music:** 120 BPM (beat 0.5 s, bar 2 s), F major, Fmaj9 – Am7 – Dm9 – B♭maj9 – F/A – Gm7 – C – Fmaj9.
Soft pad + plucked keys intro, kick/clap enters on the first expand (2.0 s), big chord + sub on
the logo (12.5 s), ringing tail to 15 s. SFX are UI-sized (ticks, glassy swells), not trailer booms.
**Look:** Apple keynote dark stage (#0E0B18 night), soft colour fields from the current cover
(rose/iris/amber → teal → orange), Archivo heavy display with light italic accents, Geist UI.
All songs, covers and lyrics are made up.

Options per scene — the chosen one is **bold**.

| # | Time | Options | Chosen + why |
|---|---|---|---|
| 1 Wake | 0.0–2.0 | a) lid opens on a dark MacBook; b) huge type "Your notch" then reveal; c) **macro on the black notch, a rose/iris glow leaks under it, the compact island grows its wings (cover + bars) on the first pluck, camera pulls back and tilts to a 3/4 MacBook**; d) waveform line draws the notch outline | c — starts the thread on the notch itself, gives depth (macro → product) without a title card |
| 2 Hover → player | 2.0–3.0 | a) **pointer glides in, hover, island springs open into the full player on the downbeat (drums enter)**; b) split-screen compact vs open; c) island opens by itself with a swipe of light | a — shows the real interaction (hover), causal and readable |
| 3 Track change | 3.0–4.0 | a) **click "next" → cover morphs rose → teal, shimmer sweeps the island, the whole room's colour fields recolour**; b) covers fly past as cards; c) album stack flip | a — the colour change is Brimtune's signature; the room recolouring sells it at a glance |
| 4 Search + playlists | 4.0–6.0 | a) **typing "paper" into the island's search (ticks on 16ths) → results; the playlist shelf slides in, "Night drive" opens its song list**; b) cards spread around the island in 3D; c) Up Next pager flicks | a — one continuous UI story inside the same island, keeps identity |
| 5 Lyrics, full screen | 6.0–8.0 | a) camera dives into the MacBook screen; **pointer clicks ↗ expand, the island's cover blooms into the breathing full-screen player, lyrics light word by word on the 8th notes**; b) lyrics in 3D space around the Mac; c) typewriter lyrics on black | a — causal (expand button → full screen), words sung by the actual music |
| 6 Lock screen | 8.0–10.0 | a) **screen dims to the lock screen (clock 9:41) with Brimtune's player; camera arcs the other way around the Mac**; b) close-up of the lock widget only; c) lid half-closes | a — product context + new camera direction for contrast |
| 7 Little moments | 10.0–11.5 | a) three separate cards; b) **camera whips up to the notch; the island morphs Timer 25:00 → Meeting in 5 min → AirPods 82%, one per beat, caption words land with each**; c) phone-style notifications | b — same object morphing on the beat = rhythm + thread |
| 8 Free | 11.5–12.5 | a) price tag; b) **pull back to a frontal Mac, huge "Free." behind it in depth, pointer presses "Download for Mac" → ✓**; c) giant $0 counter | b — Apple-style type behind product, causal button press |
| 9 Logo | 12.5–15.0 | a) icon fades in; b) **camera pushes into the island/notch → match cut to the notch in the "B" icon, pull back reveals the icon, wordmark slides out, brimtune.pages.dev under it; big chord + sub**; c) icon assembles from the speaker circles | b — closes the thread: the notch was the logo all along |

## Shot cards (practical)

1. **0.0–2.0** Camera: macro (scale ≈3.2) on the notch, slow pull to ≈1.15 with rotateX 14°→8°,
   rotateY −16°; background colour fields parallax slower than the Mac; foreground dust faster and
   out of focus. Island idle → compact at 1.0 (pluck + soft "pop"). Caption 0.9–1.9 "Your notch, *awake.*"
   (letters widen from condensed, rise through a mask).
2. **2.0–3.0** Pointer arcs in from lower right, hovers the island at 1.85, island springs open at
   2.0 (glassy swell + kick drop). Caption "Hover. *It plays.*"
3. **3.0–4.0** Pointer moves to ⏭, press 3.0 (click), cover morph + shimmer 3.0–3.9 (shimmer
   swish), colour fields lerp to teal. Caption "Colour from *every cover.*"
4. **4.0–6.0** Click search at 4.0, "paper" typed 4.1–4.6 (key ticks), results 4.65, island slides to
   playlist view 5.0 (soft whoosh). Pointer goes to ↗ at 5.6, press 5.75. Caption "Search. *Playlists.*"
5. **6.0–8.0** Dive: screen fills frame by 6.0, cover blooms into mesh, lyrics lines light word by word
   on 8ths (two lines), slow breathing scale. Shimmer bells follow the words.
6. **8.0–10.0** Cut on the bar to the Mac at 3/4 from the left on the lock screen (9:41, Brimtune
   player), camera arcs right. Caption "On your *lock screen.*"
7. **10.0–11.5** Whip up (motion blur) to the notch. Timer 10.0, Meeting 10.5, AirPods 11.0 (chime
   each, different pitch). Caption builds word by word "Timers. Meetings. *AirPods.*"
8. **11.5–12.5** Pull back to frontal Mac, "Free." huge behind it, button press at 12.05 (click + ✓ chime).
9. **12.5–15.0** Fast push into the notch 12.25–12.5 (riser), cut on 12.5 to the icon's notch,
   spring pull-back to the icon, wordmark + URL slide out at 12.9 / 13.2. Hold with a gentle drift; chord rings out.

## Risks + checks
- CSS 3D rasterisation sharpness when zoomed in → probe frame at the macro and the dive.
- Motion blur: 4 sub-frames per frame (180° shutter) averaged by FFmpeg `tmix`.
- Sync: SFX and music generated from the same `cues.js`; verify in the decoded MP4 at each cue.

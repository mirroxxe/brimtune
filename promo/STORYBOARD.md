# Brimtune — promo v2 (38 s): storyboard

**Format:** 1920×1080, 60 fps, H.264 yuv420p, AAC. 2280 frames.
**Brief (v2):** longer as needed to fit everything; structure like a SaaS launch film (hook question →
"Meet" → product in use → feature beats → bento recap → offer → logo). Must show: YouTube Music,
volume, very low resource use, external displays, the full-screen player exactly as the app draws it
(clock, cover, glass player card, Lyrics / Up Next / Playlists tabs, sidebar), free download on the
site, open source. Fix: the skewed 3/4 MacBook at ~8 s (v1) — keep angles ≤ 12°, real lid rim.
**Thread:** *the notch, woken up.* The hook's notch grows wings, becomes the icon; the icon's notch
match-cuts back into a Mac; every feature happens in or from that notch; it ends on the icon again.
**Music:** 120 BPM, F major. Hook = felt keys, one note per word; hit on "Meet"; groove from the Mac;
breakdown under the lyrics (a bell "sings" each word); groove back; near-silence ticking under
"Barely there"; build through the bento; hits on "Free." and on the logo; ringing tail.

Options per scene — chosen **bold**.

| # | Time | Options | Chosen — why |
|---|---|---|---|
| 1 Hook | 0–4 | a) Mac lid opens; b) **type on night under a notch at the top edge: "Your Mac has a notch." → "What if it played *your music?*", the notch grows wings on the question**; c) silhouette montage of notches | b — the reference's question-hook, on our own object |
| 2 Meet | 4–6 | a) logo fade; b) **the winged notch drops to centre and becomes the icon on the hit; "Meet" and "Brimtune." slide out of it; camera dives into the icon's notch**; c) letters assemble | b — causal, ends in a match-cut |
| 3 Hover | 6–8.5 | a) **cut into the Mac's notch, pull back to a near-frontal MacBook, pointer hovers, island springs open**; b) side angle; c) split screen | a — fixes the skewed mockup, reads instantly |
| 4 Volume | 8.5–10 | a) **drag the island's volume slider (track thickens, level bubble 62→88, speaker waves step up)**; b) HUD; c) keyboard keys | a — the real control |
| 5 YouTube Music | 10–12.4 | a) logos wall; b) **pointer plays a song in a YouTube Music browser tab; a spark flies to the notch, the island peeks the title, the room recolours; chips: Spotify · Apple Music · Safari · Chrome**; c) phone | b — shows *how* (reads the tab) and the cover shimmer |
| 6 Search, playlists | 12.4–15.5 | a) **type "kyiv" in the island's search, Return, brush the playlist shelf, click ↗**; b) cards in 3D; c) Up Next pager | a — one continuous UI story |
| 7 Full screen | 15.5–19.8 | a) generic lyrics card; b) **the cover blooms into the app's real full-screen player (glass clock, cover, player card, tabs, sidebar); lyrics light word by word; tabs flip to Up Next and Playlists**; c) 3D lyrics | b — what the user asked for, exactly the app's layout |
| 8 Lock screen | 19.8–21.8 | a) close-up widget; b) **near-frontal Mac locks; macOS clock + Brimtune's band (cover, card, lyrics continue)**; c) lid half-closed | b — continuity of the same song and lyrics |
| 9 Alerts | 21.8–23.6 | a) cards; b) **whip to the notch: Timer → Meeting → AirPods, one per beat**; c) notifications | b — rhythm on one object |
| 10 Displays | 23.6–26 | a) **pull back; an external display glides in beside the MacBook; a floating pill island appears at its top and plays**; b) multi-monitor grid; c) text only | a — shows "works without a notch" literally |
| 11 Barely there | 26–29 | a) Activity-Monitor screenshot; b) **type card: "Barely there." + counters ≈1.5 % CPU, 36 MB (measured, music paused) with flat sparklines; ticking hush in the music**; c) feather metaphor | b — honest numbers, big type, contrast in sound |
| 12 Bento | 29–31.5 | a) list; b) **2.5D bento grid of six live tiles (lyrics, lock screen, player, timers, displays, history) flying in on eighths, then past the camera**; c) carousel | b — the reference's recap beat, our features |
| 13 Free + open | 31.5–34 | a) price tag; b) **"Free." on the hit, "Open source." under it with GPL-3.0 chip; "Download free at brimtune.pages.dev" pressed**; c) GitHub page | b — offer + where to get it |
| 14 Logo | 34–38 | a) **icon springs in, wordmark rises, URL, "Free · Open source · macOS 14+"; big chord rings out**; b) icon only | a — readable final card |

## Checks
- Mockup angles ≤ 12°, lid rim, lock and displays shots near-frontal.
- Full-screen layout matches `StageView` (clock header, art = min(0.36H, 0.27W), card ≈ 290 pt,
  tabs, lyrics column 0.36W, sidebar at 28/36 pt).
- Numbers only as measured (CLAUDE.md: ~1.5 % CPU, 36 MB, music paused).
- Sync: picture and score from `cues.js`; verify onsets in the decoded MP4.

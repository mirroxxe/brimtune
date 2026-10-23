# Brimtune — project context

Brimtune is a free macOS app (SwiftUI + AppKit, macOS 14+, Apple silicon and Intel) that turns
the MacBook notch into a Dynamic Island–style "island" for music and small live moments, plus a
player on the lock screen and a full-screen player. Previously named **Isle** (bundle id
`app.isle.nowplaying`); now **Brimtune**, bundle id `app.brimtune.mac`. Made in Ukraine by
Volodymyr Chuchman. The user speaks Ukrainian: reply in Ukrainian; code, UI and site are English.

- Repo: `~/Brimtune`, private GitHub `mirroxxe/brimtune` (gh CLI is logged in as `mirroxxe`).
- Support email: brimtune.support@gmail.com. Site (live since 2026-10-23): https://brimtune.pages.dev
- Free distribution, no Apple Developer Program: signed with a self-signed certificate.

## Commands

```sh
./build.sh             # universal build → build.noindex/Brimtune.app (Spotlight-hidden)
./build.sh --install   # …and replace /Applications/Brimtune.app, relaunch
./release.sh 1.0.1     # bump version, build, DMG, Sparkle appcast → dist.noindex/
./deploy.sh --preview  # build site → public.noindex/, serve http://localhost:8899
./deploy.sh            # publish to Cloudflare Pages (wrangler is logged in on this Mac)
```

Always install with `./build.sh --install` (never copy a second Brimtune.app anywhere Spotlight
indexes — the user saw duplicates). Commit + push after each finished change; end commit
messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## App architecture (`Sources/Brimtune`)

- `App/` — `AppDelegate` (menu bar icon = drawn mini island, menus: timers, stopwatch, history,
  full-screen player, preview lock screen, Check for Updates, Setup Guide, About), `Preferences`,
  `SettingsView`, `HistoryView`, `Onboarding` (4-page dark setup guide with live permission
  status), `Updater` (Sparkle 2.10.0, feed `https://brimtune.pages.dev/appcast.xml`).
- `NowPlaying/` — `NowPlayingCenter` merges sources; `BrowserSource` (Safari/Chrome tabs on
  music.youtube.com / open.spotify.com via AppleScript + JS; needs Safari "Allow JavaScript from
  Apple Events"; title-only fallback uses iTunes Search for covers and a local song clock),
  `ScriptableSource` (Music/Spotify apps), `MediaRemoteSource` (reading blocked on macOS 15.4+,
  sending commands still works). YouTube Music playback is switched in-page via the `yt-navigate`
  event — never by setting the tab URL (that triggers Safari's "Leave page?" dialog).
- `Island/` — one `IslandController` per display (notch shape on built-in, floating pill on
  external); modes hidden/idle/compact/peek/alert/expanded; expanded height is measured;
  search field, Up Next (collapsible), playlist shelf + song list.
- `Stage/` — full-screen player and lock-screen panels (`LockScreenSpace` puts windows in a
  SkyLight space at level 400 to show above the lock screen); tabs Lyrics / Up Next / Playlists;
  word-by-word karaoke with ±0.5 s nudges; breathing mesh background.
- `Services/` — AudioMonitor, AudioLevels (Core Audio process tap → live waveform),
  ActivityCenter (timer, stopwatch, EventKit meetings), LyricsService (LRCLIB), MusicSearch
  (scrapes youtube.com results), HistoryStore, LockScreen.

Measured cost: ~1.5% CPU, 36 MB with music paused. Removed on request: blurred cover as
wallpaper, music-video clip player, volume HUD.

## Signing & release

- Code signing: self-signed **"Brimtune Developer"** certificate in the login keychain (10 yrs).
- Updates: Sparkle EdDSA private key in the login keychain; public key in `Resources/Info.plist`.
- Neither key is backed up yet (user postponed). Losing them breaks updates for installed copies.
- DMG background: `Tools/make-dmg-background.swift` (660×440, the visible part of a 660×500
  window); icon: `Tools/make-icon.swift`. The DMG also carries `Read Me.rtf`, made by `release.sh`
  from `Resources/ReadMe.html` (install steps, Open Anyway, every permission, troubleshooting).
- Legal texts: `Legal/` (privacy, terms — Ukrainian law, third-party notices); `[DATE]` is filled
  in when the site is built.

## Website (`site/`)

Static HTML/CSS/JS, no framework. `index.html`, `styles.css`, `island.js` (live demo island fixed
at the top: hover opens the player, scroll switches small states, made-up tracks recolour the
page), `motion.js` (scroll scenes), `build-pages.mjs` + `doc-template.html` render privacy/terms/licenses/changelog.
Fonts: Archivo (display, heavy 800 with light italic accents in <em>) + Geist (text). Colours: night #0E0B18, lilac paper #F1EEF6,
ink #16121F, accents rose #F2648E, iris #7C6CF2, amber #FFAE57. Use made-up songs/covers/lyrics
only (no real copyrighted ones).

### Current design (October 2026)

White, minimal, huge type, long scroll, inspired by augen.pro (recent.design/i/erz4438-augen) but
our own. `motion.js` drives it with Lenis 1.1.13 (smooth scroll) + GSAP/ScrollTrigger 3.12.5 from
CDNs; without GSAP the page falls back to a static layout (`html.motion` gates the pinned CSS);
reduced motion = no smooth scroll, scenes flip instead of scrub. Scenes: hero screen shrinks into a
MacBook on its lock screen → "Quiet by design" (words sharpen, counters) → pinned tour where a big
copy of the island (cloned in `island.js`) morphs through 8 features → full-screen player whose
lyrics are sung by the scroll + live waveform → sideways cards (history, displays, menu bar,
updates, free) → "The idea" + scrubbed marquee → install with a Privacy & Security mock → FAQ →
closing with a giant wordmark. Checked at 1440×900 and 375×812.

## Remaining release plan

1. ~~Redesign the site~~ (done). 2. ~~Publish~~ (done 2026-10-23: the Pages project `brimtune` was
created on classic Pages with `--force`, since new wrangler tries to delegate Pages to Workers;
plain `./deploy.sh` works from now on, no `--force`). 3. Test on a fresh macOS user account.
4. Screen recordings for the site. 5. Launch: Product Hunt, r/macapps, X/Threads, UA Telegram.
6. Back up both signing keys.

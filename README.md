# Brimtune

A Dynamic Island–style now-playing island for the Mac's notch: music from Apple Music,
Spotify and YouTube Music (Safari/Chrome), synced karaoke lyrics, a player on the lock
screen, playlists, timers, calendar countdowns and AirPods alerts.

## Build

```sh
./build.sh            # builds and signs Brimtune.app next to this file
open Brimtune.app
```

Requires macOS 14+ and Xcode's Swift toolchain. `build.sh` signs with the first
Apple Development / Developer ID identity in the keychain (override with
`BRIMTUNE_SIGN_IDENTITY`); a stable signature lets macOS remember permissions.

## Layout

- `Sources/Brimtune/App` — app delegate, preferences, settings, history window
- `Sources/Brimtune/NowPlaying` — sources (MediaRemote, Music/Spotify, browsers) and the merging center
- `Sources/Brimtune/Island` — the notch island
- `Sources/Brimtune/Stage` — full-screen player and lock screen
- `Sources/Brimtune/Services` — audio, lyrics, search, calendar/timers, lock-screen space, history
- `Tools/make-icon.swift` — renders `Resources/AppIcon.icns`

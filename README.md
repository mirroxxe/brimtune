# Brimtune

A Dynamic Island–style now-playing island for the Mac's notch: music from Apple Music,
Spotify and YouTube Music (Safari/Chrome), synced karaoke lyrics, a player on the lock
screen, playlists, timers, calendar countdowns and AirPods alerts.

## Build

```sh
./build.sh             # builds and signs build.noindex/Brimtune.app
./build.sh --install   # …and installs it into /Applications, then relaunches
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

## Release

```sh
./release.sh 1.0.1     # sets the version, builds, makes the DMG and updates the appcast
```

Output goes to `dist.noindex/`: `Brimtune.dmg` (latest, for the Download button),
`updates/Brimtune-X.Y.Z.dmg` and `appcast.xml` (Sparkle feed, served from
`https://brimtune.pages.dev/appcast.xml`). Release notes: `ReleaseNotes/X.Y.Z.html`.

Signing uses two keys that live only in the login keychain; back them up:
- **"Brimtune Developer"** — self-signed code-signing certificate (Keychain Access → My Certificates).
- **Sparkle EdDSA private key** — `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-key.txt`
  exports it. Without it no future update can be published.

Needs `brew install create-dmg`.

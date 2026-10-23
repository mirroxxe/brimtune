# Brimtune

A Dynamic Island–style now-playing island for the Mac's notch: music from Apple Music,
Spotify and YouTube Music (Safari/Chrome), synced karaoke lyrics, a player on the lock
screen, playlists, timers, calendar countdowns and AirPods alerts. On displays without a
notch it floats as a small pill.

Free and open source. Download it at **https://brimtune.pages.dev**.

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

## Website

`site/` is the static site for brimtune.pages.dev (Cloudflare Pages). `deploy.sh` builds it
into `public.noindex/` (legal pages and changelog from `Legal/` and `ReleaseNotes/`, plus
the latest release from `dist.noindex/`) and publishes it with Wrangler.

```sh
./deploy.sh --preview   # http://localhost:8899
npx wrangler login      # once
./deploy.sh             # publish
```

## Contributing

Issues and pull requests are welcome. Brimtune reads browser tabs with AppleScript and a
little JavaScript (`Sources/Brimtune/NowPlaying/BrowserSource.swift`); YouTube Music and
Spotify change their pages from time to time, so fixes there are especially useful.

## Licence

Copyright © 2026 Volodymyr Chuchman. Made in Ukraine.

Brimtune is free software: you can redistribute it and/or modify it under the terms of
the GNU General Public License, version 3, as published by the Free Software Foundation
(see `LICENSE`). It comes with no warranty.

The licence covers the code, not the Brimtune name and icon: if you publish a changed
version, give it a different name and icon (GPL-3.0, section 7(e)). Third-party code and
its licences are listed in `Legal/third-party-notices.md`.

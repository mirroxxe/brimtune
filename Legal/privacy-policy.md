# Brimtune Privacy Policy

_Last updated: [DATE]_

Brimtune is a free macOS app made by Volodymyr Chuchman ("I", "me"). This policy
explains what Brimtune does with information about you. The short version:

- **No account, no analytics, no ads, no tracking.** I don't run servers that receive
  your data, and I never sell or share anything.
- **What you listen to stays on your Mac**, except for the song details Brimtune has to
  send to look up lyrics, covers and search results (see below).
- **Sound, calendar and listening history never leave your Mac.**

## What stays on your Mac

| What | Why | Where it's kept |
|---|---|---|
| Now-playing info (song, artist, album, progress) from Apple Music, Spotify, and YouTube Music or Spotify tabs in Safari or Chrome | To show the island, the full-screen player and the lock-screen player | In memory only |
| Listening history (song, artist, source, time, small cover thumbnail) | The "Listening History" window and "Recently Played" | `~/Library/Application Support/Brimtune` on your Mac. Clear it any time from the History window |
| Your playlists and their songs (YouTube Music) | To show and play them from the island | Read from your open browser tab, kept in memory only |
| Calendar events (title, time, meeting link) | The countdown before a meeting | Read on your Mac; never stored or sent |
| What your Mac is playing (audio) | So the waveform moves with the music | Analysed in memory a fraction of a second at a time; never recorded, stored or sent |
| AirPods / headphone battery level | The "Connected" alert | Read on your Mac; never stored or sent |
| Settings | Your preferences | macOS preferences on your Mac |

To find your music, Brimtune looks at the addresses of the tabs open in Safari or Chrome,
on your Mac, and only works with tabs on `music.youtube.com` and `open.spotify.com`:
it reads what's playing there and runs its scripts only in those tabs. The addresses of
other tabs are checked and immediately discarded. Brimtune never reads the content of
other tabs, your browsing history, passwords or cookies.

## What is sent to other services, and why

Brimtune talks directly from your Mac to these services. Each receives your IP address
(as any internet request does) and is covered by its own privacy policy.

| Service | What Brimtune sends | When |
|---|---|---|
| **LRCLIB** (lrclib.net) | Song title, artist, album and length | To find lyrics for the song playing, if lyrics are on |
| **Apple iTunes Search API** (itunes.apple.com) | Song title (and artist, if known), and your region | To find a cover and length when a browser tab shows only the song title |
| **YouTube** (youtube.com) | The text you type in Brimtune's search field | When you search for a song in the island |
| **YouTube oEmbed** (youtube.com) | The ID of a playlist shown in Brimtune | To load covers for your public or unlisted playlists |
| **Image hosts** (Apple, Google/YouTube, Spotify CDNs) | A request for the cover image | To display covers for songs, the queue, search results and playlists |
| **brimtune.pages.dev** (hosted by Cloudflare) | A request for the update feed, with Brimtune's version in the request | About once a day, and when you choose "Check for Updates…" |

Brimtune doesn't send your name, email, contacts, files, calendar, location or any
identifier of its own. The update check does not include system profiling.

## Permissions Brimtune asks for

macOS asks you before Brimtune can use any of these. You can say no; the related
feature simply won't work. You can change your mind in **System Settings → Privacy &
Security**.

- **Automation (Safari, Chrome, Music, Spotify):** read what's playing and control playback.
- **Audio capture:** the waveform that moves with the music (optional).
- **Calendars:** meeting countdowns (optional).
- **Bluetooth:** headphone battery level (optional).

## The website

brimtune.pages.dev is hosted by Cloudflare, which may keep standard server logs
(IP address, browser, pages requested) for security and reliability. The site uses no
cookies and no advertising or tracking scripts.

## Children

Brimtune isn't directed at children under 13 and doesn't knowingly collect anything
from them.

## Your rights

Because I don't hold data about you, there's nothing for me to access, correct or
delete. Everything Brimtune keeps is on your Mac, and deleting the app and the folder
`~/Library/Application Support/Brimtune` removes it. For data held by the services above,
contact them directly. If you're in the EU/EEA or the UK you also have the right to
complain to your data protection authority.

## Changes

If this policy changes, the new version will be posted here with a new date. Significant
changes will also be mentioned in the release notes.

## Contact

Questions about privacy: [brimtune.support@gmail.com](mailto:brimtune.support@gmail.com)

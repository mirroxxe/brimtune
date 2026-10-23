import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    var previewLockScreen: () -> Void

    var body: some View {
        Form {
            Section("Dynamic Island") {
                Toggle("Show island around the notch", isOn: $preferences.islandEnabled)
                Toggle("Expand on hover", isOn: $preferences.expandOnHover)
                Toggle("Show track changes", isOn: $preferences.showTrackPeek)
                Toggle("Headphone connection alerts", isOn: $preferences.showHUDs)
                Toggle("Waveform follows the music", isOn: $preferences.liveWaveform)
                    .help("Listens to what your Mac plays (macOS asks once). Audio is analysed in memory and never saved.")
                Toggle("Island on external displays", isOn: $preferences.externalDisplays)
                Toggle("Upcoming meetings from Calendar", isOn: $preferences.calendarEnabled)
            }
            Section {
                Toggle("Show on lock screen", isOn: $preferences.lockScreenEnabled)
                Picker("Style", selection: $preferences.lockScreenStyle) {
                    ForEach(LockScreenStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!preferences.lockScreenEnabled)
                Button("Preview Lock Screen", action: previewLockScreen)
            } header: {
                Text("Lock Screen")
            }
            Section {
                Toggle("Synced lyrics", isOn: $preferences.lyricsEnabled)
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Lyrics come from LRCLIB (lrclib.net). The song title and artist are sent to look them up.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open at login", isOn: $preferences.launchAtLogin)
            } footer: {
                Text("Brimtune reads Apple Music and Spotify. macOS will ask once for permission to control each of them.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

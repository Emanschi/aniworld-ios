import SwiftUI
import AniworldKit

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var confirmClearHistory = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                PrioritySection()
                PlaybackSection()
                dataSection
                InfoSection()
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            .confirmationDialog("Gesamten Verlauf löschen?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("Verlauf löschen", role: .destructive) { library.clearHistory() }
                Button("Abbrechen", role: .cancel) {}
            }
            .confirmationDialog(
                "Alles zurücksetzen?",
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button("Alles zurücksetzen", role: .destructive) { library.resetAll() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Favoriten, Verlauf und Fortschritt werden unwiderruflich gelöscht.")
            }
        }
    }

    private var dataSection: some View {
        Section("Daten") {
            Button("Verlauf löschen", role: .destructive) { confirmClearHistory = true }
            Button("Alles zurücksetzen", role: .destructive) { confirmReset = true }
        }
    }
}

// MARK: Priorities

private struct PrioritySection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            ForEach(settings.languagePriority, id: \.self) { language in
                Label(language.displayName, systemImage: "globe")
            }
            .onMove { source, destination in
                settings.languagePriority.move(fromOffsets: source, toOffset: destination)
            }
        } header: {
            Text("Sprachpriorität")
        } footer: {
            Text("Tippe oben auf „Bearbeiten“, um die Reihenfolge zu ändern. Die oberste Sprache wird bevorzugt.")
        }

        Section {
            ForEach(settings.hosterPriority, id: \.self) { hoster in
                Label(hoster, systemImage: "server.rack")
            }
            .onMove { source, destination in
                settings.hosterPriority.move(fromOffsets: source, toOffset: destination)
            }
        } header: {
            Text("Hosterpriorität")
        } footer: {
            Text("Fällt ein Hoster aus, wird automatisch der nächste versucht.")
        }
    }
}

// MARK: Playback

private struct PlaybackSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Nächste Folge automatisch abspielen", isOn: $settings.autoplayNext)
                .tint(Theme.accent)
            Stepper(value: $settings.autoplayCountdown, in: 3...20) {
                HStack {
                    Text("Countdown")
                    Spacer()
                    Text("\(settings.autoplayCountdown) s").foregroundStyle(Theme.textSecondary)
                }
            }
            Stepper(value: $settings.introSkipSeconds, in: 30...150, step: 5) {
                HStack {
                    Text("Intro-Sprung")
                    Spacer()
                    Text("\(settings.introSkipSeconds) s").foregroundStyle(Theme.textSecondary)
                }
            }
            Toggle("Streams prüfen", isOn: $settings.verifyStreams)
                .tint(Theme.accent)
        } header: {
            Text("Wiedergabe")
        } footer: {
            Text("„Streams prüfen“ testet vor dem Start, ob die Videosegmente erreichbar sind. Das ist zuverlässiger, dauert aber etwas länger.")
        }
    }
}

// MARK: Info

private struct InfoSection: View {
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(versionText).foregroundStyle(Theme.textSecondary)
            }
            if let url = URL(string: "https://github.com/dxmoc/aniworld-cli") {
                Link(destination: url) {
                    Label("Originalprojekt auf GitHub", systemImage: "link")
                }
            }
        } header: {
            Text("Info")
        } footer: {
            Text("Diese App ist eine iOS-Portierung von aniworld-cli (dxmoc) und steht wie das Original unter der GPL-3.0. Sie hostet keine Inhalte, sondern verlinkt ausschließlich auf Streams von aniworld.to. Für die Inhalte sind allein die jeweiligen Anbieter verantwortlich.")
        }
    }
}

#Preview("Einstellungen") {
    SettingsView().previewEnvironment()
}

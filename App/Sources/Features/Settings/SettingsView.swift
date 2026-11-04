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
                SyncSection()
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

// MARK: Sync

private struct SyncSection: View {
    @Environment(LibrarySyncService.self) private var sync
    @State private var showPicker = false

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var statusText: String {
        if !sync.isConfigured { return "Nicht eingerichtet" }
        if let error = sync.lastError { return "Fehler: \(error)" }
        if sync.isSyncing { return "Synchronisiere …" }
        if let last = sync.lastSyncAt { return "Zuletzt synchronisiert \(relative(last))" }
        return "Noch nicht synchronisiert"
    }

    var body: some View {
        Section {
            HStack {
                Label("Status", systemImage: "icloud")
                Spacer()
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(sync.lastError == nil ? Theme.textSecondary : Color.red)
                    .multilineTextAlignment(.trailing)
            }
            ForEach(sync.devices) { device in
                HStack {
                    Label(device.name.isEmpty ? "Unbekanntes Gerät" : device.name, systemImage: "iphone")
                    Spacer()
                    Text(relative(device.writtenAt)).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            Button(sync.isConfigured ? "Ordner ändern" : "iCloud-Ordner wählen") { showPicker = true }
                .sheet(isPresented: $showPicker) {
                    FolderPicker(onPick: { url in
                        showPicker = false
                        sync.configure(pickedFolder: url)
                    }, onCancel: {
                        showPicker = false
                    })
                    .ignoresSafeArea()
                }
            if sync.isConfigured {
                Button("Jetzt synchronisieren") { sync.syncNow() }
                    .disabled(sync.isSyncing)
                Button("Synchronisierung deaktivieren", role: .destructive) { sync.disable() }
            }
        } header: {
            Text("Synchronisierung")
        } footer: {
            Text("Die Daten liegen in einem versteckten Ordner „.aniworld-sync“ in deinem iCloud Drive. Jedes Gerät muss einmal iCloud Drive auswählen („Öffnen“ tippen); danach werden Favoriten, Verlauf, Fortschritt und Sprachen automatisch abgeglichen.")
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
            Toggle("Intro-Erkennung (automatisch)", isOn: $settings.enableSkipDetection)
                .tint(Theme.accent)
            if settings.enableSkipDetection {
                Toggle("Intro automatisch überspringen", isOn: $settings.autoSkipIntro)
                    .tint(Theme.accent)
                    .padding(.leading, 12)
                Toggle("Outro automatisch überspringen", isOn: $settings.autoSkipEnding)
                    .tint(Theme.accent)
                    .padding(.leading, 12)
            }
            Stepper(value: $settings.introSkipSeconds, in: 30...150, step: 5) {
                HStack {
                    Text("Manueller Intro-Sprung")
                    Spacer()
                    Text("\(settings.introSkipSeconds) s").foregroundStyle(Theme.textSecondary)
                }
            }
            Toggle("Streams prüfen", isOn: $settings.verifyStreams)
                .tint(Theme.accent)
        } header: {
            Text("Wiedergabe")
        } footer: {
            Text("Erkennt automatisch Intros und Outros und blendet einen passenden Sprung-Button ein. Wenn keine genauen Zeitmarken vorliegen, wird der manuelle Sprung verwendet. „Streams prüfen“ testet vor dem Start, ob die Videosegmente erreichbar sind.")
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
            NavigationLink {
                LicensesView()
            } label: {
                Label("Lizenzen & rechtliche Hinweise", systemImage: "doc.text")
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

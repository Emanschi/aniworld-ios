import SwiftUI
import AniworldKit

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(WatchStatsStore.self) private var stats
    @State private var confirmResetStats = false
    @State private var confirmClearHistory = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                PrioritySection()
                PlaybackSection()
                DownloadsSettingsSection()
                SyncSection()
                NotificationsSection()
                dataSection
                UpdatesSettingsSection()
                InfoSection()
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            .confirmationDialog("Statistik zurücksetzen?", isPresented: $confirmResetStats, titleVisibility: .visible) {
                Button("Statistik zurücksetzen", role: .destructive) { stats.reset() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle gespeicherten Statistiken werden gelöscht, auch auf deinen anderen Geräten (bei aktivem iCloud-Sync).")
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
                Text("Favoriten, Verlauf, Fortschritt und eigene Intro-Zeiten werden unwiderruflich gelöscht.")
            }
        }
    }

    private var dataSection: some View {
        Section("Daten") {
            NavigationLink {
                StatsView()
            } label: {
                Label("Statistiken", systemImage: "chart.bar.xaxis")
            }
            Button("Statistik zurücksetzen", role: .destructive) { confirmResetStats = true }
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
            Text("Die Daten liegen in einem versteckten Unterordner „.aniworld-sync“ des gewählten Ordners. Wähle auf jedem Gerät denselben Ordner in iCloud Drive (z. B. „AniWorld“; der oberste iCloud-Drive-Ordner selbst geht nicht); danach werden Favoriten, Verlauf, Fortschritt, Sprachen und eigene Intro-Zeiten automatisch abgeglichen.")
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
            Toggle("Intro & Outro überspringen", isOn: $settings.enableSkipDetection)
                .tint(Theme.accent)
            if settings.enableSkipDetection {
                Toggle("Intro automatisch überspringen", isOn: $settings.autoSkipIntro)
                    .tint(Theme.accent)
                    .padding(.leading, 12)
                Toggle("Outro automatisch überspringen", isOn: $settings.autoSkipEnding)
                    .tint(Theme.accent)
                    .padding(.leading, 12)
                if settings.autoplayNext {
                    Toggle("Nach dem Outro direkt zur nächsten Folge", isOn: $settings.autoNextOnOutro)
                        .tint(Theme.accent)
                        .padding(.leading, 12)
                }
            }
            Stepper(value: $settings.introSkipSeconds, in: 30...150, step: 5) {
                HStack {
                    Text("Manueller Intro-Sprung")
                    Spacer()
                    Text("\(settings.introSkipSeconds) s").foregroundStyle(Theme.textSecondary)
                }
            }
            NavigationLink {
                CustomSkipListView()
            } label: {
                Label("Eigene Intro-Zeiten", systemImage: "scissors")
            }
            Toggle("Streams prüfen", isOn: $settings.verifyStreams)
                .tint(Theme.accent)
        } header: {
            Text("Wiedergabe")
        } footer: {
            Text("Blendet bei Intro und Outro einen Sprung-Button ein. Die Zeiten legst du selbst fest – im Player für eine Folge oder die ganze Staffel („Eigene Intro-Zeiten“); sie bleiben auf deinem Gerät bzw. in deinem iCloud-Sync. Ohne eigene Zeiten wird der manuelle Sprung verwendet. „Streams prüfen“ testet vor dem Start, ob die Videosegmente erreichbar sind.")
        }
    }
}

// MARK: Notifications

private struct NotificationsSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(EpisodeWatcher.self) private var watcher
    @Environment(\.openURL) private var openURL

    private var lastCheckText: String {
        guard let date = watcher.lastCheckAt else { return "Noch nie" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var isDenied: Bool { watcher.authorizationStatus == .denied }

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Neue Folgen meiner Favoriten", isOn: Binding<Bool>(
                get: { settings.notifyNewEpisodes },
                set: { newValue in
                    if newValue {
                        settings.notifyNewEpisodes = true
                        Task {
                            let granted: Bool = await watcher.requestAuthorization()
                            if granted { await watcher.checkNow() }
                        }
                    } else {
                        settings.notifyNewEpisodes = false
                    }
                }
            ))
            .tint(Theme.accent)
            Toggle("Neue App-Version", isOn: $settings.notifyAppUpdates)
                .tint(Theme.accent)
            if (settings.notifyNewEpisodes || settings.notifyAppUpdates) && isDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mitteilungen sind für AniWorld in den iOS-Einstellungen ausgeschaltet.")
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                    Button("iOS-Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
            if settings.notifyNewEpisodes {
                Button {
                    Task { await watcher.checkNow() }
                } label: {
                    HStack {
                        Text("Jetzt prüfen")
                        if watcher.isChecking { Spacer(); ProgressView() }
                    }
                }
                .disabled(watcher.isChecking)
                HStack {
                    Text("Zuletzt geprüft")
                    Spacer()
                    Text(lastCheckText).foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("Benachrichtigungen")
        } footer: {
            Text("Die App prüft deine Favoriten selbst, ohne Server: beim Öffnen und, soweit iOS es zulässt, gelegentlich im Hintergrund. Bei per Sideload installierten Apps ist die Hintergrundprüfung unzuverlässig; sicher funktioniert die Prüfung beim Öffnen der App. Beim ersten Mal wird nur der aktuelle Stand gemerkt.")
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

// MARK: Downloads

private struct DownloadsSettingsSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(DownloadManager.self) private var downloads
    @State private var confirmDeleteAll = false

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Downloads komprimieren", isOn: $settings.compressDownloads)
                .tint(Theme.accent)

            if settings.compressDownloads {
                Picker("Komprimierung", selection: $settings.downloadQuality) {
                    ForEach(DownloadQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
            }

            Toggle("Gesehene Folgen automatisch löschen", isOn: $settings.autoDeleteWatchedDownloads)
                .tint(Theme.accent)

            Toggle("Nur im WLAN herunterladen", isOn: $settings.downloadOnlyOnWiFi)
                .tint(Theme.accent)

            HStack {
                Text("Belegter Speicher")
                Spacer()
                Text(DownloadFormat.bytes(downloads.totalBytes))
                    .foregroundStyle(Theme.textSecondary)
            }

            if !downloads.records.isEmpty {
                Button("Alle Downloads löschen", role: .destructive) {
                    confirmDeleteAll = true
                }
            }
        } header: {
            Text("Downloads & Speicher")
        } footer: {
            Text("Kodiert heruntergeladene MP4-Dateien nach dem Download auf dem Gerät neu, um Speicher zu sparen. „Hoch“ nutzt HEVC in Originalauflösung, die kleineren Stufen verkleinern auf 720p bzw. 480p. Wie viel das spart, hängt vom Video ab; wird die Datei nicht kleiner, bleibt das Original. HLS-Downloads werden nicht komprimiert.")
        }
        .confirmationDialog("Alle Downloads löschen?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Alle Downloads löschen", role: .destructive) {
                downloads.deleteAll()
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

#Preview("Einstellungen") {
    SettingsView().previewEnvironment()
}

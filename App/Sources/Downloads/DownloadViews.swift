import SwiftUI
import AniworldKit

/// Round per-episode download control: arrow / clock / progress ring / check / warning.
struct DownloadButton: View {
    let state: DownloadState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .none:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 22))
                .foregroundStyle(Theme.textSecondary)
        case .queued:
            Image(systemName: "clock")
                .font(.system(size: 18))
                .foregroundStyle(Theme.textSecondary)
        case .downloading(let progress):
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.03, progress)))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "stop.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.success)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 22))
                .foregroundStyle(Color.red)
        }
    }

    private var accessibilityText: String {
        switch state {
        case .none: return "Herunterladen"
        case .queued: return "In Warteschlange, Download abbrechen"
        case .downloading: return "Lädt herunter, Download abbrechen"
        case .downloaded: return "Heruntergeladen, Download löschen"
        case .failed: return "Download fehlgeschlagen, erneut versuchen"
        }
    }
}

/// List of downloaded episodes grouped by series, with running downloads and the total storage used.
/// Pushed inside an existing `NavigationStack` (Favoriten tab).
struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloads
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(SettingsStore.self) private var settings
    @State private var confirmDeleteAll = false
    @State private var seriesToDelete: SeriesGroup?

    private struct SeriesGroup: Identifiable {
        var series: SeriesSummary
        var records: [DownloadRecord]
        var id: String { series.slug }
    }

    private var groups: [SeriesGroup] {
        var bySlug: [String: [DownloadRecord]] = [:]
        for record in downloads.records {
            bySlug[record.series.slug, default: []].append(record)
        }
        var result: [SeriesGroup] = []
        for (_, items) in bySlug {
            let sorted = items.sorted { lhs, rhs in
                if lhs.episode.season != rhs.episode.season { return lhs.episode.season < rhs.episode.season }
                return lhs.episode.number < rhs.episode.number
            }
            if let first = sorted.first {
                result.append(SeriesGroup(series: first.series, records: sorted))
            }
        }
        return result.sorted {
            $0.series.title.localizedCaseInsensitiveCompare($1.series.title) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if downloads.records.isEmpty && downloads.jobs.isEmpty {
                ContentUnavailableView(
                    "Keine Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Tippe bei einer Folge auf den Download-Pfeil, um sie offline zu speichern.")
                )
            } else {
                list
            }
        }
        .background(AppBackground())
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    Label("Alle löschen", systemImage: "trash")
                }
                .disabled(downloads.records.isEmpty)
            }
        }
        .confirmationDialog("Alle Downloads löschen?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Alle löschen", role: .destructive) {
                downloads.deleteAll()
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(
            "Downloads von „\(seriesToDelete?.series.title ?? "Serie")“ löschen?",
            isPresented: Binding<Bool>(
                get: { seriesToDelete != nil },
                set: { if !$0 { seriesToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: seriesToDelete
        ) { group in
            Button("Alle Downloads dieser Serie löschen", role: .destructive) {
                downloads.deleteAll(seriesSlug: group.series.slug)
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var list: some View {
        @Bindable var settings = settings
        List {
            Section {
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(Theme.accent)
                    Text("Belegter Speicher")
                        .foregroundStyle(.white)
                    Spacer()
                    Text(DownloadFormat.bytes(downloads.totalBytes))
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline)
                .listRowBackground(Theme.surface)

                Toggle(isOn: $settings.autoDeleteWatchedDownloads) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gesehene Folgen automatisch löschen")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Text("Löscht eine Folge, sobald du sie fast ganz gesehen und den Player verlassen hast")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.surface)

                Toggle(isOn: $settings.downloadOnlyOnWiFi) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nur im WLAN herunterladen")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Text("Schont das mobile Datenvolumen unterwegs")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.surface)
            }

            if !downloads.jobs.isEmpty {
                Section("Aktive Downloads") {
                    ForEach(downloads.activeJobs) { job in
                        jobRow(job)
                            .listRowBackground(Theme.surface)
                    }
                }
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.records) { record in
                        Button {
                            play(record, in: group.records)
                        } label: {
                            recordRow(record)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.surface)
                        .contextMenu {
                            Button(role: .destructive) {
                                downloads.delete(record.id)
                            } label: {
                                Label("Download löschen", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { group.records[$0].id }
                        for id in ids { downloads.delete(id) }
                    }
                } header: {
                    HStack {
                        Text(group.series.title)
                        Spacer()
                        Button(role: .destructive) {
                            seriesToDelete = group
                        } label: {
                            Label("Serie entfernen", systemImage: "trash")
                                .font(.caption)
                                .foregroundStyle(Color.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func recordRow(_ record: DownloadRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.episode.code) · \(title(of: record.episode))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(subtitle(of: record))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func jobRow(_ job: DownloadJob) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(job.series.title) · \(job.episode.code)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                switch job.status {
                case .queued:
                    Text(downloads.isWaitingForWiFi ? "Wartet auf WLAN…" : "In Warteschlange")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                case .active:
                    if job.isCompressing == true {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Wird komprimiert…")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        ProgressBar(value: job.progress, height: 4)
                    }
                case .failed:
                    Text(job.errorMessage ?? "Download fehlgeschlagen")
                        .font(.caption)
                        .foregroundStyle(Color.red)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if job.status == .failed {
                Button("Erneut") { downloads.retry(job.id) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            }
            Button {
                downloads.cancel(job.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Download abbrechen")
        }
    }

    private func title(of episode: EpisodeRef) -> String {
        let trimmed = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return episode.season == 0 ? "Film \(episode.number)" : "Folge \(episode.number)"
    }

    private func subtitle(of record: DownloadRecord) -> String {
        var parts: [String] = []
        if let language = record.language { parts.append(language.shortName) }
        if record.sizeBytes > 0 { parts.append(DownloadFormat.bytes(record.sizeBytes)) }
        if let label = record.compressionLabel { parts.append(label) }
        return parts.joined(separator: " · ")
    }

    private func play(_ record: DownloadRecord, in records: [DownloadRecord]) {
        let sameSeason: [EpisodeRef] = records
            .filter { $0.episode.season == record.episode.season }
            .map { $0.episode }
        playback.play(series: record.series, episode: record.episode, seasonEpisodes: sameSeason,
                      language: record.language, fromStart: false)
    }
}

#Preview("Downloads") {
    NavigationStack { DownloadsView() }
        .previewEnvironment()
}

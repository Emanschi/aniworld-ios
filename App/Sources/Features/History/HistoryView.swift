import SwiftUI
import AniworldKit

struct HistoryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if library.history.isEmpty {
                    ContentUnavailableView(
                        "Noch nichts angesehen",
                        systemImage: "play.circle",
                        description: Text("Folgen, die du anschaust, erscheinen hier – so kannst du jederzeit dort weitermachen, wo du aufgehört hast.")
                    )
                } else {
                    historyList
                }
            }
            .background(AppBackground())
            .navigationTitle("Weiterschauen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: StatsView()) {
                        Label("Statistiken", systemImage: "chart.bar.xaxis")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Verlauf löschen", systemImage: "trash")
                    }
                    .disabled(library.history.isEmpty)
                }
            }
            .confirmationDialog("Gesamten Verlauf löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Verlauf löschen", role: .destructive) {
                    library.clearHistory()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Favoriten bleiben erhalten.")
            }
            .navigationDestination(for: SeriesSummary.self) { series in
                SeriesDetailView(series: series)
            }
        }
    }

    private var historyList: some View {
        List {
            ForEach(library.history) { entry in
                Button {
                    playback.resume(entry)
                } label: {
                    HistoryRow(entry: entry)
                }
                .buttonStyle(PressableStyle())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: Theme.screenPadding, bottom: 8, trailing: Theme.screenPadding))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        library.removeFromHistory(entry.series.slug)
                    } label: {
                        Label("Entfernen", systemImage: "trash")
                    }
                }
                .contextMenu {
                    NavigationLink(value: entry.series) {
                        Label("Zur Serie", systemImage: "rectangle.stack")
                    }
                    Button(role: .destructive) {
                        library.removeFromHistory(entry.series.slug)
                    } label: {
                        Label("Entfernen", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

struct HistoryRow: View {
    let entry: WatchEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.series.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(episodeLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(Format.relative(entry.updatedAt))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                if entry.isFinished {
                    Label("Nächste Folge", systemImage: "forward.end.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accentGradient))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        SeriesCover(series: entry.series, aspect: 16.0 / 9.0, cornerRadius: 12)
            .frame(width: 150)
            .overlay(alignment: .bottom) {
                ProgressBar(value: entry.isFinished ? 1 : entry.fraction, height: 3)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
            .overlay(alignment: .center) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .cardShadow()
    }

    private var episodeLine: String {
        let title = entry.episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? entry.episode.code : "\(entry.episode.code) · \(title)"
    }
}

#Preview("Weiterschauen") {
    HistoryView().previewEnvironment()
}

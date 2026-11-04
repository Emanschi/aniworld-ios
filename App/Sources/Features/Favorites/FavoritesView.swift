import SwiftUI
import AniworldKit

enum FavoritesSort: String, CaseIterable, Identifiable {
    case recent
    case alphabetical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Zuletzt hinzugefügt"
        case .alphabetical: "A–Z"
        }
    }
}

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("favoritesSort") private var sortRaw = FavoritesSort.recent.rawValue

    private let columns = [GridItem(.adaptive(minimum: 105, maximum: 170), spacing: 14, alignment: .top)]

    private var sort: FavoritesSort { FavoritesSort(rawValue: sortRaw) ?? .recent }

    private var sortedSeries: [SeriesSummary] {
        switch sort {
        case .recent:
            return library.favorites.sorted { $0.addedAt > $1.addedAt }.map { $0.series }
        case .alphabetical:
            return library.favorites.map { $0.series }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.favorites.isEmpty {
                    ContentUnavailableView(
                        "Keine Favoriten",
                        systemImage: "heart",
                        description: Text("Tippe auf der Seite einer Serie auf das Herz, um sie hier zu speichern.")
                    )
                } else {
                    grid
                }
            }
            .background(AppBackground())
            .navigationTitle("Favoriten")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
            }
            .navigationDestination(for: SeriesSummary.self) { series in
                SeriesDetailView(series: series)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sortierung", selection: $sortRaw) {
                ForEach(FavoritesSort.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
        .disabled(library.favorites.isEmpty)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(sortedSeries) { series in
                    NavigationLink(value: series) {
                        PosterCard(series: series, width: nil)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            library.removeFavorite(series.slug)
                            Haptics.impact()
                        } label: {
                            Label("Aus Favoriten entfernen", systemImage: "heart.slash")
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }
}

#Preview("Favoriten") {
    FavoritesView().previewEnvironment()
}

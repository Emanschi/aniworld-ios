import SwiftUI
import Observation
import AniworldKit

@MainActor
@Observable
final class SearchViewModel {
    var results: [SeriesSummary] = []
    var phase: LoadPhase = .loaded
    private(set) var lastQuery = ""

    func search(_ query: String, service: AniworldService) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lastQuery = trimmed
        if trimmed.isEmpty {
            results = []
            phase = .loaded
            return
        }
        phase = .loading
        do {
            let found = try await service.search(trimmed)
            if Task.isCancelled { return }
            results = found
            phase = .loaded
        } catch {
            if Task.isCancelled { return }
            results = []
            phase = .failed(error)
        }
    }
}

struct SearchView: View {
    @Environment(\.aniworld) private var service
    @State private var vm = SearchViewModel()
    @State private var query = ""
    @AppStorage("recentSearches") private var recentRaw = ""

    private let columns = [GridItem(.adaptive(minimum: 105, maximum: 170), spacing: 14, alignment: .top)]

    private var recents: [String] {
        recentRaw.split(separator: "\n").map(String.init)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .background(AppBackground())
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Serien suchen")
            .onSubmit(of: .search) { rememberSearch(trimmedQuery) }
            .navigationDestination(for: SeriesSummary.self) { series in
                SeriesDetailView(series: series)
            }
            .task(id: query) {
                // Debounce: a new keystroke cancels this task before the search starts.
                if !trimmedQuery.isEmpty {
                    do {
                        try await Task.sleep(for: .milliseconds(350))
                    } catch {
                        return
                    }
                }
                await vm.search(query, service: service)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            recentSearchesView
        } else {
            switch vm.phase {
            case .loading:
                skeletonGrid
            case .failed(let error):
                ErrorStateView(error: error) {
                    Task { await vm.search(query, service: service) }
                }
            case .loaded:
                if vm.results.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                        .padding(.top, 40)
                } else {
                    resultsGrid
                }
            }
        }
    }

    private var resultsGrid: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(vm.results) { series in
                NavigationLink(value: series) {
                    PosterCard(series: series, width: nil)
                }
                .buttonStyle(PressableStyle())
                .simultaneousGesture(TapGesture().onEnded { rememberSearch(trimmedQuery) })
            }
        }
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(0..<9, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBox().aspectRatio(2.0 / 3.0, contentMode: .fit)
                    SkeletonBox(cornerRadius: 4).frame(height: 10)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSearchesView: some View {
        if recents.isEmpty {
            ContentUnavailableView(
                "Serien entdecken",
                systemImage: "magnifyingglass",
                description: Text("Suche nach Titel – zum Beispiel „Naruto“ oder „Attack on Titan“.")
            )
            .padding(.top, 60)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Zuletzt gesucht")
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Löschen") { recentRaw = "" }
                        .font(.subheadline)
                        .tint(Theme.accent)
                }
                FlowLayout(spacing: 8) {
                    ForEach(recents, id: \.self) { term in
                        Button {
                            query = term
                        } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .chipBackground()
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }

    private func rememberSearch(_ term: String) {
        guard term.count >= 2 else { return }
        var list = recents.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        list.insert(term, at: 0)
        recentRaw = list.prefix(10).joined(separator: "\n")
    }
}

#Preview("Suche") {
    SearchView().previewEnvironment()
}

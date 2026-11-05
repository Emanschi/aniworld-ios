import SwiftUI
import Observation
import AniworldKit

@MainActor
@Observable
final class SearchViewModel {
    var results: [SeriesSummary] = []
    var phase: LoadPhase = .loaded
    private(set) var lastQuery = ""

    /// Genres of the site (loaded once per session).
    var genres: [GenreRef] = []
    /// Slugs of the genres currently used as filter, in selection order.
    var selectedGenres: [String] = []

    private var genresLoaded = false
    private var genreCache: [String: [SeriesSummary]] = [:]

    var hasGenreFilter: Bool { !selectedGenres.isEmpty }

    /// Changes whenever the search has to be re-run.
    func key(for query: String) -> String {
        query + "\u{1F}" + selectedGenres.joined(separator: ",")
    }

    func loadGenres(service: AniworldService) async {
        if genresLoaded { return }
        do {
            let result = try await service.genres()
            if Task.isCancelled { return }
            genres = result
            genresLoaded = true
        } catch {
            // Genre chips are optional; text search keeps working without them.
        }
    }

    func toggle(_ genre: GenreRef) {
        if let index = selectedGenres.firstIndex(of: genre.slug) {
            selectedGenres.remove(at: index)
        } else {
            selectedGenres.append(genre.slug)
        }
    }

    func clearGenres() { selectedGenres = [] }

    func search(_ query: String, service: AniworldService) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lastQuery = trimmed
        isLoadingMore = false
        // Invalidates late progress of an older genre search (e.g. after the filter was cleared).
        searchToken += 1
        if selectedGenres.isEmpty {
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
            return
        }
        await searchByGenres(selectedGenres, query: trimmed, service: service)
    }

    /// True while genre pages are still arriving; results shown so far are partial.
    private(set) var isLoadingMore = false
    /// Lists received so far for genres that are still loading.
    private var partial: [String: [SeriesSummary]] = [:]
    /// Bumped per search so late progress of an older search is ignored.
    private var searchToken = 0

    private func searchByGenres(_ slugs: [String], query: String, service: AniworldService) async {
        searchToken += 1
        let token = searchToken
        partial = [:]
        if slugs.allSatisfy({ genreCache[$0] != nil }) {
            showIntersection(slugs, query: query)
            return
        }
        phase = .loading
        isLoadingMore = true
        do {
            try await fetchMissing(slugs, service: service) { [weak self] slug, list in
                await self?.receivePartial(slug, list, slugs: slugs, query: query, token: token)
            }
            guard token == searchToken, !Task.isCancelled else { return }
            isLoadingMore = false
            showIntersection(slugs, query: query)
        } catch {
            guard token == searchToken, !Task.isCancelled else { return }
            isLoadingMore = false
            results = []
            phase = .failed(error)
        }
    }

    /// Shows results as soon as every selected genre has at least its first page.
    private func receivePartial(_ slug: String, _ list: [SeriesSummary], slugs: [String], query: String, token: Int) {
        guard token == searchToken else { return }
        partial[slug] = list
        guard slugs.allSatisfy({ genreCache[$0] != nil || partial[$0] != nil }) else { return }
        showIntersection(slugs, query: query)
    }

    private func showIntersection(_ slugs: [String], query: String) {
        func list(_ slug: String) -> [SeriesSummary] { genreCache[slug] ?? partial[slug] ?? [] }
        var intersection = list(slugs[0])
        for slug in slugs.dropFirst() {
            let other = Set(list(slug).map(\.slug))
            intersection = intersection.filter { other.contains($0.slug) }
        }
        if !query.isEmpty {
            intersection = intersection.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        results = intersection
        phase = .loaded
    }

    /// Loads the series lists of all genres that are not cached yet, concurrently, reporting progress.
    private func fetchMissing(_ slugs: [String], service: AniworldService,
                              onProgress: @escaping @Sendable (String, [SeriesSummary]) async -> Void) async throws {
        let missing = slugs.filter { genreCache[$0] == nil }
        if missing.isEmpty { return }
        let loaded: [(String, [SeriesSummary])] = try await withThrowingTaskGroup(
            of: (String, [SeriesSummary]).self
        ) { group in
            for slug in missing {
                group.addTask {
                    (slug, try await service.series(inGenre: slug, progress: { await onProgress(slug, $0) }))
                }
            }
            var collected: [(String, [SeriesSummary])] = []
            for try await item in group { collected.append(item) }
            return collected
        }
        for (slug, list) in loaded { genreCache[slug] = list }
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
                VStack(alignment: .leading, spacing: 18) {
                    genreFilter
                    content
                }
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
            .task { await vm.loadGenres(service: service) }
            .task(id: vm.key(for: query)) {
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

    // MARK: Genre filter

    @ViewBuilder
    private var genreFilter: some View {
        if !vm.genres.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Genres")
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(.white)
                    Spacer()
                    if vm.hasGenreFilter {
                        Button("Zurücksetzen") { vm.clearGenres() }
                            .font(.subheadline)
                            .tint(Theme.accent)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(vm.genres) { genre in
                            let selected = vm.selectedGenres.contains(genre.slug)
                            Button {
                                vm.toggle(genre)
                            } label: {
                                Text(genre.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .chipBackground(selected: selected)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        Group {
            if trimmedQuery.isEmpty && !vm.hasGenreFilter {
                VStack(alignment: .leading, spacing: 18) {
                    browseAllRow
                    recentSearchesView
                }
            } else {
                switch vm.phase {
                case .loading:
                    skeletonGrid
                case .failed(let error):
                    ErrorStateView(error: error) {
                        Task { await vm.search(query, service: service) }
                    }
                case .loaded:
                    if vm.results.isEmpty && vm.isLoadingMore {
                        // Partial pages have no overlap yet; keep the placeholder until more arrives.
                        skeletonGrid
                    } else if vm.results.isEmpty {
                        if trimmedQuery.isEmpty {
                            ContentUnavailableView(
                                "Keine Treffer",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Zu dieser Genre-Auswahl wurden keine Serien gefunden.")
                            )
                            .padding(.top, 40)
                        } else {
                            ContentUnavailableView.search(text: trimmedQuery)
                                .padding(.top, 40)
                        }
                    } else {
                        resultsGrid
                    }
                }
            }
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    private var browseAllRow: some View {
        NavigationLink(destination: AllSeriesView()) {
            HStack(spacing: 14) {
                Image(systemName: "textformat.abc")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.accentGradient)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.surfaceHigh))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alle Animes A–Z")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Der komplette Katalog nach Anfangsbuchstaben")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var resultsGrid: some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(vm.results) { series in
                    NavigationLink(value: series) {
                        PosterCard(series: series, width: nil)
                    }
                    .buttonStyle(PressableStyle())
                    .simultaneousGesture(TapGesture().onEnded { rememberSearch(trimmedQuery) })
                }
            }
            if vm.isLoadingMore {
                LoadingMoreRow(count: vm.results.count)
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
                description: Text("Suche nach Titel oder wähle oben ein Genre – zum Beispiel „Naruto“ oder „Attack on Titan“.")
            )
            .padding(.top, 30)
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

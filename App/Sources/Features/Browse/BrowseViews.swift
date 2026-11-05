import SwiftUI
import Observation
import AniworldKit

// Browse screens. They link to series with `NavigationLink(destination:)` so they work in every
// NavigationStack without registering extra `navigationDestination` types.

// MARK: - Genre results

@MainActor
@Observable
final class GenreSeriesViewModel {
    var series: [SeriesSummary] = []
    var phase: LoadPhase = .loading
    /// True while more pages are still arriving.
    private(set) var isLoadingMore = false
    private var loadedSlug: String?

    func load(genre: GenreRef, service: AniworldService, force: Bool = false) async {
        if loadedSlug == genre.slug && !force { return }
        phase = .loading
        isLoadingMore = true
        do {
            let result = try await service.series(inGenre: genre.slug, progress: { [weak self] partial in
                await self?.show(partial)
            })
            if Task.isCancelled { return }
            series = result
            loadedSlug = genre.slug
            isLoadingMore = false
            phase = .loaded
        } catch {
            if Task.isCancelled { return }
            isLoadingMore = false
            // Keep what already arrived; only show the error screen when nothing did.
            if series.isEmpty { phase = .failed(error) }
        }
    }

    private func show(_ partial: [SeriesSummary]) {
        guard !partial.isEmpty, partial.count >= series.count else { return }
        series = partial
        phase = .loaded
    }
}

/// Footer below a growing result grid while more pages are loading.
struct LoadingMoreRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.textSecondary)
            Text("\(count) Serien geladen, lädt weitere …")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// All series of one genre as a poster grid.
struct GenreSeriesView: View {
    let genre: GenreRef

    @Environment(\.aniworld) private var service
    @State private var vm = GenreSeriesViewModel()

    private let columns = [GridItem(.adaptive(minimum: 105, maximum: 170), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .background(AppBackground())
        .navigationTitle(genre.name)
        .navigationBarTitleDisplayMode(.large)
        .task(id: genre.slug) { await vm.load(genre: genre, service: service) }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .loading:
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(0..<9, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBox().aspectRatio(2.0 / 3.0, contentMode: .fit)
                        SkeletonBox(cornerRadius: 4).frame(height: 10)
                    }
                }
            }
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await vm.load(genre: genre, service: service, force: true) }
            }
        case .loaded:
            if vm.series.isEmpty {
                ContentUnavailableView(
                    "Keine Serien",
                    systemImage: "tray",
                    description: Text("Für dieses Genre wurden keine Serien gefunden.")
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(vm.series) { series in
                        NavigationLink(destination: SeriesDetailView(series: series)) {
                            PosterCard(series: series, width: nil)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                if vm.isLoadingMore {
                    LoadingMoreRow(count: vm.series.count)
                        .padding(.top, 18)
                }
            }
        }
    }
}

// MARK: - All series A-Z

struct AlphaSection: Identifiable {
    let letter: String
    let items: [SeriesSummary]
    var id: String { letter }
}

@MainActor
@Observable
final class AllSeriesViewModel {
    var phase: LoadPhase = .loading
    var sections: [AlphaSection] = []
    var total = 0
    private var all: [SeriesSummary] = []
    private var hasLoaded = false

    func load(service: AniworldService, filter: String, force: Bool = false) async {
        if hasLoaded && !force { return }
        phase = .loading
        do {
            let result = try await service.allSeries()
            if Task.isCancelled { return }
            all = result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            total = all.count
            hasLoaded = true
            regroup(filter: filter)
            phase = .loaded
        } catch {
            if Task.isCancelled { return }
            phase = .failed(error)
        }
    }

    func regroup(filter: String) {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = needle.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        var buckets: [String: [SeriesSummary]] = [:]
        for series in source {
            buckets[Self.letter(for: series.title), default: []].append(series)
        }
        sections = buckets.keys.sorted { lhs, rhs in
            if lhs == "#" { return true }
            if rhs == "#" { return false }
            return lhs < rhs
        }.map { AlphaSection(letter: $0, items: buckets[$0] ?? []) }
    }

    nonisolated static func letter(for title: String) -> String {
        guard let first = title.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let folded = String(first)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .uppercased()
        if folded.count == 1, let scalar = folded.unicodeScalars.first,
           scalar.value >= 65, scalar.value <= 90 {
            return folded
        }
        return "#"
    }
}

/// Complete catalogue grouped by first letter, with a quick letter index and a local filter.
struct AllSeriesView: View {
    @Environment(\.aniworld) private var service
    @State private var vm = AllSeriesViewModel()
    @State private var filter = ""
    @State private var lastJump = ""

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Alle Animes A–Z")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .always), prompt: "Titel filtern")
            .onChange(of: filter) { _, newValue in vm.regroup(filter: newValue) }
            .task { await vm.load(service: service, filter: filter) }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .loading:
            VStack(spacing: 10) {
                ForEach(0..<10, id: \.self) { _ in
                    SkeletonBox(cornerRadius: 12).frame(height: 46)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 12)
            .frame(maxHeight: .infinity, alignment: .top)
        case .failed(let error):
            ScrollView {
                ErrorStateView(error: error) {
                    Task { await vm.load(service: service, filter: filter, force: true) }
                }
            }
        case .loaded:
            if vm.sections.isEmpty {
                ContentUnavailableView.search(text: filter)
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(vm.sections) { section in
                            Section {
                                VStack(spacing: 8) {
                                    ForEach(section.items) { series in
                                        NavigationLink(destination: SeriesDetailView(series: series)) {
                                            row(series)
                                        }
                                        .buttonStyle(PressableStyle())
                                    }
                                }
                                .padding(.leading, Theme.screenPadding)
                                .padding(.trailing, 36)
                                .padding(.bottom, 12)
                            } header: {
                                sectionHeader(section.letter)
                                    .id(section.letter)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
                letterIndex(proxy: proxy)
            }
        }
    }

    private func sectionHeader(_ letter: String) -> some View {
        Text(letter)
            .font(AppFont.sectionTitle)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background.opacity(0.92))
    }

    private func row(_ series: SeriesSummary) -> some View {
        HStack(spacing: 10) {
            Text(series.title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .contentShape(Rectangle())
    }

    private func letterIndex(proxy: ScrollViewProxy) -> some View {
        let letters = vm.sections.map { $0.letter }
        return GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22, height: geo.size.height)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !letters.isEmpty, geo.size.height > 0 else { return }
                        let ratio = value.location.y / geo.size.height
                        let index = min(max(Int(ratio * CGFloat(letters.count)), 0), letters.count - 1)
                        let letter = letters[index]
                        if letter != lastJump {
                            lastJump = letter
                            proxy.scrollTo(letter, anchor: .top)
                        }
                    }
                    .onEnded { _ in lastJump = "" }
            )
        }
        .frame(width: 22)
        .padding(.vertical, 12)
        .padding(.trailing, 6)
    }
}

// MARK: - Release calendar

@MainActor
@Observable
final class ReleaseCalendarViewModel {
    var days: [CalendarDay] = []
    var phase: LoadPhase = .loading
    private var hasLoaded = false

    func load(service: AniworldService, force: Bool = false) async {
        if hasLoaded && !force { return }
        phase = .loading
        do {
            let result = try await service.releaseCalendar()
            if Task.isCancelled { return }
            days = result
            hasLoaded = true
            phase = .loaded
        } catch {
            if Task.isCancelled { return }
            phase = .failed(error)
        }
    }
}

/// Upcoming releases grouped by day.
struct ReleaseCalendarView: View {
    @Environment(\.aniworld) private var service
    @Environment(LibraryStore.self) private var library
    @State private var vm = ReleaseCalendarViewModel()
    /// Only series that are favorites or in "Weiterschauen".
    @AppStorage("calendarOnlyMine") private var onlyMine = false

    private func isMine(_ slug: String) -> Bool {
        library.isFavorite(slug) || library.lastWatched(seriesSlug: slug) != nil
    }

    var body: some View {
        ScrollView {
            content
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .background(AppBackground())
        .navigationTitle("Kalender")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onlyMine.toggle()
                } label: {
                    Image(systemName: onlyMine ? "star.circle.fill" : "star.circle")
                }
                .accessibilityLabel(onlyMine ? "Alle Serien zeigen" : "Nur meine Serien zeigen")
            }
        }
        .refreshable { await vm.load(service: service, force: true) }
        .task { await vm.load(service: service) }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .loading:
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonBox(cornerRadius: 12).frame(height: 78)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await vm.load(service: service, force: true) }
            }
        case .loaded:
            let days = vm.days
                .map { day -> CalendarDay in
                    var copy = day
                    if onlyMine { copy.entries = day.entries.filter { isMine($0.series.slug) } }
                    return copy
                }
                .filter { !$0.entries.isEmpty }
            if days.isEmpty {
                ContentUnavailableView(
                    onlyMine ? "Nichts von deinen Serien" : "Kein Kalender",
                    systemImage: "calendar",
                    description: Text(onlyMine
                        ? "In den nächsten Tagen erscheint nichts von deinen Favoriten oder Serien in „Weiterschauen“."
                        : "Aktuell sind keine Veröffentlichungen eingetragen.")
                )
                .padding(.top, 40)
            } else {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: day.displayTitle())
                            VStack(spacing: 8) {
                                ForEach(day.entries) { entry in
                                    NavigationLink(destination: SeriesDetailView(series: entry.series)) {
                                        entryRow(entry)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                            .padding(.horizontal, Theme.screenPadding)
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: CalendarEntry) -> some View {
        HStack(spacing: 12) {
            SeriesCover(series: entry.series, cornerRadius: 8)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.series.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !entry.info.isEmpty {
                    Text(entry.info)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .contentShape(Rectangle())
    }
}

#Preview("Alle Animes") {
    NavigationStack { AllSeriesView() }.previewEnvironment()
}

#Preview("Kalender") {
    NavigationStack { ReleaseCalendarView() }.previewEnvironment()
}

#Preview("Genre") {
    NavigationStack { GenreSeriesView(genre: GenreRef(slug: "action", name: "Action")) }.previewEnvironment()
}

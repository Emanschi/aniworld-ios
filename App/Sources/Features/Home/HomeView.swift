import SwiftUI
import Observation
import AniworldKit

@MainActor
@Observable
final class HomeViewModel {
    var sections: [HomeSection] = []
    var phase: LoadPhase = .loading
    private var hasLoaded = false

    func load(service: AniworldService, force: Bool = false) async {
        if hasLoaded && !force { return }
        if !hasLoaded { phase = .loading }
        do {
            let result = try await service.homeSections()
            sections = result
            phase = .loaded
            hasLoaded = true
        } catch {
            if Task.isCancelled { return }
            if sections.isEmpty { phase = .failed(error) }
        }
    }
}

struct HomeView: View {
    @Environment(\.aniworld) private var service
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var vm = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    greeting
                    continueSection
                    favoritesSection
                    remoteSections
                }
                .padding(.bottom, 32)
            }
            .background(AppBackground())
            .refreshable { await vm.load(service: service, force: true) }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SeriesSummary.self) { series in
                SeriesDetailView(series: series)
            }
        }
        .task { await vm.load(service: service) }
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(AppFont.display(32))
                .foregroundStyle(.white)
            Text("Was schauen wir heute?")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 12)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "Guten Morgen"
        case 11..<18: return "Hallo"
        case 18..<23: return "Guten Abend"
        default: return "Gute Nacht"
        }
    }

    // MARK: Library rows

    @ViewBuilder
    private var continueSection: some View {
        if library.history.isEmpty {
            emptyHistoryCard
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Weiterschauen")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(library.history) { entry in
                            Button {
                                playback.resume(entry)
                            } label: {
                                ContinueCard(entry: entry)
                            }
                            .buttonStyle(PressableStyle())
                            .contextMenu { continueMenu(entry) }
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func continueMenu(_ entry: WatchEntry) -> some View {
        NavigationLink(value: entry.series) {
            Label("Zur Serie", systemImage: "rectangle.stack")
        }
        Button(role: .destructive) {
            library.removeFromHistory(entry.series.slug)
        } label: {
            Label("Aus Verlauf entfernen", systemImage: "trash")
        }
    }

    private var emptyHistoryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accentGradient)
            VStack(alignment: .leading, spacing: 3) {
                Text("Noch nichts angeschaut")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                Text("Starte eine Serie – hier findest du sie zum Weiterschauen wieder.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface)
        )
        .padding(.horizontal, Theme.screenPadding)
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if !library.favorites.isEmpty {
            PosterRow(title: "Deine Favoriten", items: library.favorites.map { $0.series })
        }
    }

    // MARK: Remote rows

    @ViewBuilder
    private var remoteSections: some View {
        switch vm.phase {
        case .loading:
            PosterRowSkeleton()
            PosterRowSkeleton()
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await vm.load(service: service, force: true) }
            }
        case .loaded:
            ForEach(vm.sections) { section in
                PosterRow(title: section.title, items: section.items)
            }
        }
    }
}

#Preview("Start") {
    HomeView().previewEnvironment()
}

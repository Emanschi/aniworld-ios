import SwiftUI
import AniworldKit

struct SeriesDetailView: View {
    let series: SeriesSummary

    @Environment(\.aniworld) private var service
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(DownloadManager.self) private var downloads
    @State private var downloadPrompt: EpisodeRef?
    @State private var confirmDeleteSeason = false
    @State private var confirmDeleteSeries = false
    @State private var resetPrompt: ResetScope?

    /// What "Fortschritt zurücksetzen" applies to.
    private enum ResetScope: Equatable {
        case season(Int)
        case series
    }

    private var resetPromptBinding: Binding<Bool> {
        Binding<Bool>(get: { resetPrompt != nil }, set: { if !$0 { resetPrompt = nil } })
    }

    private var resetPromptTitle: String {
        switch resetPrompt {
        case .season(let s): s == 0 ? "Fortschritt aller Filme zurücksetzen?" : "Fortschritt von Staffel \(s) zurücksetzen?"
        case .series, nil: "Gesamten Fortschritt von „\(displaySummary.title)“ zurücksetzen?"
        }
    }
    @State private var vm = SeriesDetailViewModel()
    @State private var descriptionExpanded = false

    private var displaySummary: SeriesSummary { vm.summary(fallback: series) }
    private var lastWatched: WatchEntry? { library.lastWatched(seriesSlug: series.slug) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                actions
                descriptionBlock
                seasonPicker
                episodeSection
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
            .background(alignment: .top) { backdrop }
        }
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { languageMenu }
        .confirmationDialog(
            "Alle Downloads von „\(displaySummary.title)“ löschen?",
            isPresented: $confirmDeleteSeries,
            titleVisibility: .visible
        ) {
            Button("Alle Downloads löschen", role: .destructive) {
                downloads.deleteAll(seriesSlug: displaySummary.slug)
                Haptics.success()
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(
            isFilmsSelected
                ? "Alle heruntergeladenen Filme dieser Serie löschen?"
                : "Alle Downloads dieser Staffel löschen?",
            isPresented: $confirmDeleteSeason,
            titleVisibility: .visible
        ) {
            Button(isFilmsSelected ? "Filme löschen" : "Staffel löschen", role: .destructive) {
                if let season = vm.selectedSeason {
                    downloads.deleteSeason(seriesSlug: displaySummary.slug, season: season)
                    Haptics.success()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(
            resetPromptTitle,
            isPresented: resetPromptBinding,
            titleVisibility: .visible,
            presenting: resetPrompt
        ) { scope in
            Button("Zurücksetzen", role: .destructive) {
                switch scope {
                case .season(let s): library.resetProgress(seriesSlug: displaySummary.slug, season: s)
                case .series: library.resetProgress(seriesSlug: displaySummary.slug)
                }
                Haptics.success()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Gesehen-Markierungen und Fortschritt werden entfernt, damit du von vorne schauen kannst. Downloads bleiben erhalten.")
        }
        .confirmationDialog(
            downloadPromptTitle,
            isPresented: downloadPromptBinding,
            titleVisibility: .visible,
            presenting: downloadPrompt
        ) { episode in
            if downloads.state(for: episode.id) == .downloaded {
                Button("Download löschen", role: .destructive) { downloads.delete(episode.id) }
            } else {
                Button("Download abbrechen", role: .destructive) { downloads.cancel(episode.id) }
            }
            Button("Zurück", role: .cancel) {}
        }
        .task(id: series.slug) {
            await vm.load(series: series, preferredSeason: lastWatched?.episode.season, service: service)
        }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        let url = vm.detail?.backdropURL ?? vm.detail?.coverURL ?? series.coverURL
        return Color.clear
            .frame(height: 440)
            .frame(maxWidth: .infinity)
            .overlay {
                CachedImage(url: url)
                    .blur(radius: 26)
                    .scaleEffect(1.3)
                    .opacity(0.55)
            }
            .overlay {
                LinearGradient(
                    colors: [Theme.background.opacity(0.0), Theme.background],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .clipped()
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            SeriesCover(series: displaySummary, cornerRadius: 16)
                .frame(width: 130)
                .cardShadow()
            VStack(alignment: .leading, spacing: 8) {
                Text(displaySummary.title)
                    .font(AppFont.display(24))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = metaLine {
                    Text(meta)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let age = vm.detail?.ageRating {
                    FSKBadge(age: age)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 24)
    }

    private var metaLine: String? {
        var parts: [String] = []
        if let detail = vm.detail {
            if let start = detail.startYear {
                if let end = detail.endYear, end != start {
                    parts.append("\(start)–\(end)")
                } else if detail.endYear == nil {
                    parts.append("seit \(start)")
                } else {
                    parts.append("\(start)")
                }
            }
            let seasonCount = detail.seasons.filter { !$0.isFilms }.count
            if seasonCount > 0 { parts.append(seasonCount == 1 ? "1 Staffel" : "\(seasonCount) Staffeln") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 14) {
            genreChips
            HStack(spacing: 12) {
                primaryButton
                favoriteButton
            }
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    @ViewBuilder
    private var genreChips: some View {
        if let refs = vm.detail?.genreRefs, !refs.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(refs) { genre in
                    NavigationLink(destination: GenreSeriesView(genre: genre)) {
                        genreChipLabel(genre.name, tappable: true)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        } else if let genres = vm.detail?.genres, !genres.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    genreChipLabel(genre, tappable: false)
                }
            }
        }
    }

    private func genreChipLabel(_ name: String, tappable: Bool) -> some View {
        HStack(spacing: 4) {
            Text(name)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.10)))
    }

    private var primaryButton: some View {
        let target = primaryTarget
        return Button {
            target.action()
        } label: {
            Label(target.title, systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AccentButtonStyle())
        .disabled(!target.enabled)
        .opacity(target.enabled ? 1 : 0.55)
    }

    private struct PrimaryTarget {
        var title: String
        var enabled: Bool
        var action: () -> Void
    }

    private var primaryTarget: PrimaryTarget {
        if let entry = lastWatched {
            let title = entry.isFinished ? "Nächste Folge" : "Fortsetzen · \(entry.episode.code)"
            return PrimaryTarget(title: title, enabled: true) { playback.resume(entry) }
        }
        if let first = vm.firstEpisode {
            return PrimaryTarget(title: "Abspielen · \(first.code)", enabled: true) {
                play(first, episodes: vm.episodesBySeason[first.season] ?? [], fromStart: false)
            }
        }
        return PrimaryTarget(title: "Abspielen", enabled: false) {}
    }

    private var favoriteButton: some View {
        let isFavorite = library.isFavorite(series.slug)
        return Button {
            library.toggleFavorite(displaySummary)
            Haptics.impact()
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isFavorite ? Theme.accentPink : .white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Theme.surfaceHigh))
                .symbolEffect(.bounce, value: isFavorite)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
    }

    // MARK: Description

    @ViewBuilder
    private var descriptionBlock: some View {
        let text = displaySummary.description
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(descriptionExpanded ? nil : 4)
                    .animation(.easeInOut(duration: 0.2), value: descriptionExpanded)
                Button(descriptionExpanded ? "Weniger" : "Mehr") {
                    descriptionExpanded.toggle()
                }
                .font(.subheadline.weight(.semibold))
                .tint(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.screenPadding)
        }
    }

    // MARK: Seasons & episodes

    @ViewBuilder
    private var seasonPicker: some View {
        if vm.seasons.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.seasons) { season in
                        Button {
                            Task { await vm.selectSeason(season.number, slug: series.slug, service: service) }
                        } label: {
                            Text(season.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .chipBackground(selected: vm.selectedSeason == season.number)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
            }
        }
    }

    @ViewBuilder
    private var episodeSection: some View {
        switch vm.detailPhase {
        case .failed(let error):
            ErrorStateView(error: error) {
                Task {
                    await vm.reload(series: series, preferredSeason: lastWatched?.episode.season, service: service)
                }
            }
        case .loading:
            episodeSkeleton
        case .loaded:
            switch vm.episodesPhase {
            case .loading:
                episodeSkeleton
            case .failed(let error):
                ErrorStateView(error: error) {
                    Task {
                        await vm.reload(series: series, preferredSeason: lastWatched?.episode.season, service: service)
                    }
                }
            case .loaded:
                episodeList
            }
        }
    }

    private var episodeSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { _ in
                SkeletonBox(cornerRadius: 12).frame(height: 62)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    @ViewBuilder
    private var episodeList: some View {
        let episodes = vm.currentEpisodes
        if episodes.isEmpty {
            Text("Keine Folgen gefunden.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            VStack(spacing: 10) {
                HStack {
                    if downloads.hasDownloads(in: episodes) {
                        Button(role: .destructive) {
                            confirmDeleteSeason = true
                        } label: {
                            Label(isFilmsSelected ? "Filme löschen" : "Staffel löschen",
                                  systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(Color.red)
                    }
                    Spacer()
                    Button {
                        downloads.download(series: displaySummary, episodes: episodes,
                                           language: languageBinding.wrappedValue)
                        Haptics.impact()
                    } label: {
                        Label(isFilmsSelected ? "Alle Filme laden" : "Ganze Staffel laden",
                              systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.accent)
                }
                LazyVStack(spacing: 10) {
                    ForEach(episodes) { episode in
                        EpisodeRow(
                            episode: episode,
                            progress: library.progress(for: episode),
                            downloadState: downloads.state(for: episode.id),
                            onDownloadTap: { downloadTapped(episode) }
                        ) {
                            play(episode, episodes: episodes, fromStart: false)
                        }
                        .contextMenu { episodeMenu(episode, in: episodes) }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
    }

    /// The films pseudo-season is number 0.
    private var isFilmsSelected: Bool { vm.selectedSeason == 0 }

    private var downloadPromptBinding: Binding<Bool> {
        Binding<Bool>(
            get: { downloadPrompt != nil },
            set: { if !$0 { downloadPrompt = nil } }
        )
    }

    @ViewBuilder
    private func episodeMenu(_ episode: EpisodeRef, in episodes: [EpisodeRef]) -> some View {
        let progress = library.progress(for: episode)
        let watched = progress?.watched ?? false
        Button {
            library.setWatched(!watched, episode: episode, series: displaySummary)
        } label: {
            Label(watched ? "Als ungesehen markieren" : "Als gesehen markieren",
                  systemImage: watched ? "eye.slash" : "eye")
        }
        if !watched, (progress?.position ?? 0) > 0 {
            Button {
                library.resetProgress(seriesSlug: displaySummary.slug, episodeID: episode.id)
            } label: {
                Label("Fortschritt zurücksetzen", systemImage: "arrow.counterclockwise")
            }
        }
        Button {
            library.markWatchedUpTo(episode, in: episodes, series: displaySummary)
        } label: {
            Label("Bis hier als gesehen markieren", systemImage: "checkmark.circle")
        }
        Button {
            play(episode, episodes: episodes, fromStart: true)
        } label: {
            Label("Von vorne abspielen", systemImage: "gobackward")
        }
    }

    private var downloadPromptTitle: String {
        guard let episode = downloadPrompt else { return "Download" }
        return downloads.state(for: episode.id) == .downloaded
            ? "Heruntergeladene Folge \(episode.code) löschen?"
            : "Download von \(episode.code) abbrechen?"
    }

    private func downloadTapped(_ episode: EpisodeRef) {
        switch downloads.state(for: episode.id) {
        case .none:
            downloads.download(series: displaySummary, episodes: [episode], language: languageBinding.wrappedValue)
            Haptics.impact()
        case .failed:
            downloads.retry(episode.id)
        case .queued, .downloading, .downloaded:
            downloadPrompt = episode
        }
    }

    private func play(_ episode: EpisodeRef, episodes: [EpisodeRef], fromStart: Bool) {
        playback.play(series: displaySummary, episode: episode, seasonEpisodes: episodes, fromStart: fromStart)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var languageMenu: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            let slug = displaySummary.slug
            let hasDownloads = downloads.hasDownloads(seriesSlug: slug)
            let hasProgress = library.hasProgress(seriesSlug: slug)
            if hasDownloads || hasProgress || !vm.seasons.isEmpty {
                Menu {
                    if let season = vm.selectedSeason, !library.allWatched(vm.currentEpisodes) {
                        Button {
                            library.markWatched(vm.currentEpisodes, series: displaySummary)
                            Haptics.success()
                        } label: {
                            Label(season == 0 ? "Alle Filme als gesehen markieren"
                                              : "Staffel \(season) als gesehen markieren",
                                  systemImage: "checkmark.circle")
                        }
                    }
                    if vm.seasons.contains(where: { !$0.isFilms }) {
                        Button {
                            Task {
                                guard let all = try? await vm.allRegularEpisodes(slug: slug, service: service) else { return }
                                library.markWatched(all, series: displaySummary)
                                Haptics.success()
                            }
                        } label: {
                            Label("Ganze Serie als gesehen markieren", systemImage: "checkmark.circle.fill")
                        }
                    }
                    if let season = vm.selectedSeason, library.hasProgress(seriesSlug: slug, season: season) {
                        Button {
                            resetPrompt = .season(season)
                        } label: {
                            Label(season == 0 ? "Fortschritt der Filme zurücksetzen"
                                              : "Fortschritt von Staffel \(season) zurücksetzen",
                                  systemImage: "arrow.counterclockwise")
                        }
                    }
                    if hasProgress {
                        Button {
                            resetPrompt = .series
                        } label: {
                            Label("Gesamten Fortschritt zurücksetzen", systemImage: "arrow.counterclockwise.circle")
                        }
                    }
                    if settings.onlineSkipTimes {
                        let disabled = library.isOnlineSkipDisabled(seriesSlug: slug)
                        Button {
                            library.setOnlineSkipDisabled(!disabled, seriesSlug: slug)
                        } label: {
                            Label(disabled ? "AniSkip-Zeitmarken für diese Serie einschalten"
                                           : "AniSkip-Zeitmarken für diese Serie ausschalten",
                                  systemImage: disabled ? "forward.end" : "forward.end.alt")
                        }
                    }
                    if hasDownloads {
                        Button(role: .destructive) {
                            confirmDeleteSeries = true
                        } label: {
                            Label("Alle Downloads dieser Serie löschen", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            Menu {
                Picker("Sprache", selection: languageBinding) {
                    ForEach(StreamLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            } label: {
                Image(systemName: "globe")
            }
        }
    }

    private var languageBinding: Binding<StreamLanguage> {
        Binding<StreamLanguage>(
            get: {
                library.preferredLanguage(seriesSlug: series.slug)
                    ?? settings.languagePriority.first
                    ?? .germanDub
            },
            set: { newValue in
                library.setPreferredLanguage(newValue, seriesSlug: series.slug)
            }
        )
    }
}

// MARK: Episode row

struct EpisodeRow: View {
    let episode: EpisodeRef
    let progress: EpisodeProgress?
    var downloadState: DownloadState = .none
    var onDownloadTap: () -> Void = {}
    let onPlay: () -> Void

    private var watched: Bool { progress?.watched ?? false }
    private var fraction: Double { watched ? 0 : (progress?.fraction ?? 0) }

    private var displayTitle: String {
        let trimmed = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return episode.season == 0 ? "Film \(episode.number)" : "Folge \(episode.number)"
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onPlay) {
                HStack(spacing: 14) {
                    numberBadge
                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayTitle)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(watched ? Theme.textSecondary : .white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if fraction > 0.01 {
                            ProgressBar(value: fraction, height: 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    trailingIcon
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            DownloadButton(state: downloadState, action: onDownloadTap)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
        )
    }

    private var numberBadge: some View {
        Text("\(episode.number)")
            .font(.system(.callout, design: .rounded).weight(.bold))
            .foregroundStyle(watched ? Theme.textSecondary : .white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(Theme.surfaceHigh))
    }

    @ViewBuilder
    private var trailingIcon: some View {
        if watched {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
        } else {
            Image(systemName: "play.circle")
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview("Serien-Detail") {
    NavigationStack {
        SeriesDetailView(series: MockAniworldService.sampleSeries[0])
    }
    .previewEnvironment()
}

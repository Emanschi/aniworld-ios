import SwiftUI
import AniworldKit

struct SeriesDetailView: View {
    let series: SeriesSummary

    @Environment(\.aniworld) private var service
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackCoordinator.self) private var playback
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
            if let genres = vm.detail?.genres, !genres.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        Text(genre)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                }
            }
            HStack(spacing: 12) {
                primaryButton
                favoriteButton
            }
        }
        .padding(.horizontal, Theme.screenPadding)
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
            LazyVStack(spacing: 10) {
                ForEach(episodes) { episode in
                    EpisodeRow(
                        episode: episode,
                        progress: library.progress(for: episode)
                    ) {
                        play(episode, episodes: episodes, fromStart: false)
                    }
                    .contextMenu { episodeMenu(episode, in: episodes) }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
    }

    @ViewBuilder
    private func episodeMenu(_ episode: EpisodeRef, in episodes: [EpisodeRef]) -> some View {
        let watched = library.progress(for: episode)?.watched ?? false
        Button {
            library.setWatched(!watched, episode: episode, series: displaySummary)
        } label: {
            Label(watched ? "Als ungesehen markieren" : "Als gesehen markieren",
                  systemImage: watched ? "eye.slash" : "eye")
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

    private func play(_ episode: EpisodeRef, episodes: [EpisodeRef], fromStart: Bool) {
        playback.play(series: displaySummary, episode: episode, seasonEpisodes: episodes, fromStart: fromStart)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var languageMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
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
    let onPlay: () -> Void

    private var watched: Bool { progress?.watched ?? false }
    private var fraction: Double { watched ? 0 : (progress?.fraction ?? 0) }

    private var displayTitle: String {
        let trimmed = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return episode.season == 0 ? "Film \(episode.number)" : "Folge \(episode.number)"
    }

    var body: some View {
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
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
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

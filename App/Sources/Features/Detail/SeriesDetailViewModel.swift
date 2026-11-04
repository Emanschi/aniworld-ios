import Foundation
import Observation
import AniworldKit

@MainActor
@Observable
final class SeriesDetailViewModel {
    var detail: SeriesDetail?
    var detailPhase: LoadPhase = .loading
    var selectedSeason: Int?
    var episodesBySeason: [Int: [EpisodeRef]] = [:]
    var episodesPhase: LoadPhase = .loading

    private var hasLoadedDetail = false

    var seasons: [SeasonRef] { detail?.seasons ?? [] }

    var currentEpisodes: [EpisodeRef] {
        guard let selectedSeason else { return [] }
        return episodesBySeason[selectedSeason] ?? []
    }

    /// First regular episode (S01E01 or the first available), for the "Abspielen" button.
    var firstEpisode: EpisodeRef? {
        let regular = episodesBySeason.keys.filter { $0 > 0 }.sorted()
        if let season = regular.first, let episode = episodesBySeason[season]?.first {
            return episode
        }
        if let films = episodesBySeason[0]?.first, seasons.allSatisfy({ $0.isFilms }) {
            return films
        }
        return nil
    }

    /// Summary enriched with whatever the detail page provided.
    func summary(fallback: SeriesSummary) -> SeriesSummary {
        guard let detail else { return fallback }
        var summary = detail.summary
        if summary.coverURL == nil { summary.coverURL = detail.coverURL ?? fallback.coverURL }
        if summary.description.isEmpty { summary.description = detail.description }
        return summary
    }

    func load(series: SeriesSummary, preferredSeason: Int?, service: AniworldService) async {
        if hasLoadedDetail { return }
        detailPhase = .loading
        episodesPhase = .loading
        do {
            let loaded = try await service.seriesDetail(slug: series.slug)
            if Task.isCancelled { return }
            detail = loaded
            detailPhase = .loaded
            hasLoadedDetail = true
            let numbers = loaded.seasons.map { $0.number }
            var target: Int?
            if let preferredSeason, numbers.contains(preferredSeason) {
                target = preferredSeason
            } else {
                target = numbers.first(where: { $0 > 0 }) ?? numbers.first
            }
            if let target {
                await selectSeason(target, slug: series.slug, service: service)
            } else {
                episodesPhase = .loaded
            }
        } catch {
            if Task.isCancelled { return }
            detailPhase = .failed(error)
        }
    }

    func selectSeason(_ number: Int, slug: String, service: AniworldService) async {
        selectedSeason = number
        if episodesBySeason[number] != nil {
            episodesPhase = .loaded
            return
        }
        episodesPhase = .loading
        do {
            let episodes = try await service.episodes(slug: slug, season: number)
            episodesBySeason[number] = episodes
            if selectedSeason == number { episodesPhase = .loaded }
        } catch {
            if Task.isCancelled { return }
            if selectedSeason == number { episodesPhase = .failed(error) }
        }
    }

    func reload(series: SeriesSummary, preferredSeason: Int?, service: AniworldService) async {
        if hasLoadedDetail, let selectedSeason {
            await selectSeason(selectedSeason, slug: series.slug, service: service)
        } else {
            await load(series: series, preferredSeason: preferredSeason, service: service)
        }
    }
}

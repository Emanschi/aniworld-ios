import Foundation

// Shared contract between AniworldKit and the app. Add fields only with defaults;
// do not rename or remove existing ones.

/// Audio/subtitle variant offered by aniworld.to.
public enum StreamLanguage: String, Codable, Hashable, Sendable, CaseIterable {
    case germanDub = "ger-dub"
    case germanSub = "ger-sub"
    case englishSub = "eng-sub"

    public var displayName: String {
        switch self {
        case .germanDub: "Deutsch"
        case .germanSub: "Deutsch (Untertitel)"
        case .englishSub: "Englisch (Untertitel)"
        }
    }

    public var shortName: String {
        switch self {
        case .germanDub: "GerDub"
        case .germanSub: "GerSub"
        case .englishSub: "EngSub"
        }
    }
}

/// A series as it appears in search results, lists and the library.
public struct SeriesSummary: Identifiable, Hashable, Codable, Sendable {
    public var slug: String
    public var title: String
    public var url: URL
    public var description: String
    public var coverURL: URL?

    public var id: String { slug }

    public init(slug: String, title: String, url: URL, description: String = "", coverURL: URL? = nil) {
        self.slug = slug
        self.title = title
        self.url = url
        self.description = description
        self.coverURL = coverURL
    }
}

/// A season entry. `number == 0` is the films section.
public struct SeasonRef: Identifiable, Hashable, Codable, Sendable {
    public var number: Int
    public var id: Int { number }
    public var isFilms: Bool { number == 0 }
    public var title: String { isFilms ? "Filme" : "Staffel \(number)" }

    public init(number: Int) { self.number = number }
}

/// Full series page data.
public struct SeriesDetail: Hashable, Codable, Sendable {
    public var summary: SeriesSummary
    public var description: String
    public var coverURL: URL?
    public var backdropURL: URL?
    public var genres: [String]
    public var startYear: Int?
    public var endYear: Int?
    public var seasons: [SeasonRef]

    public init(summary: SeriesSummary, description: String, coverURL: URL?, backdropURL: URL? = nil,
                genres: [String] = [], startYear: Int? = nil, endYear: Int? = nil, seasons: [SeasonRef]) {
        self.summary = summary
        self.description = description
        self.coverURL = coverURL
        self.backdropURL = backdropURL
        self.genres = genres
        self.startYear = startYear
        self.endYear = endYear
        self.seasons = seasons
    }
}

/// A single playable episode or film.
public struct EpisodeRef: Identifiable, Hashable, Codable, Sendable {
    public var seriesSlug: String
    public var season: Int
    public var number: Int
    public var title: String
    public var url: URL

    public var id: String { "\(seriesSlug)-s\(season)e\(number)" }

    /// "S01E03" or "Film 2".
    public var code: String {
        season == 0 ? "Film \(number)" : String(format: "S%02dE%02d", season, number)
    }

    public init(seriesSlug: String, season: Int, number: Int, title: String = "", url: URL) {
        self.seriesSlug = seriesSlug
        self.season = season
        self.number = number
        self.title = title
        self.url = url
    }
}

/// One hoster entry on an episode page.
public struct HosterLink: Hashable, Codable, Sendable {
    public var name: String
    /// nil when the page's language key could not be classified.
    public var language: StreamLanguage?
    public var languageKey: Int
    public var redirectURL: URL

    public init(name: String, language: StreamLanguage?, languageKey: Int, redirectURL: URL) {
        self.name = name
        self.language = language
        self.languageKey = languageKey
        self.redirectURL = redirectURL
    }
}

/// The final stream handed to AVPlayer. `headers` must be sent with every request
/// (master playlist, variants and segments) — the CDNs check Referer/User-Agent.
public struct ResolvedStream: Hashable, Sendable {
    public var url: URL
    public var headers: [String: String]
    public var hoster: String
    public var language: StreamLanguage?

    public init(url: URL, headers: [String: String], hoster: String, language: StreamLanguage?) {
        self.url = url
        self.headers = headers
        self.hoster = hoster
        self.language = language
    }
}

/// User preferences that influence stream resolution.
public struct StreamPreferences: Hashable, Codable, Sendable {
    public var languagePriority: [StreamLanguage]
    public var hosterPriority: [String]

    public static let `default` = StreamPreferences(
        languagePriority: [.germanDub, .germanSub, .englishSub],
        hosterPriority: ["VOE", "Vidmoly"]
    )

    public init(languagePriority: [StreamLanguage], hosterPriority: [String]) {
        self.languagePriority = languagePriority
        self.hosterPriority = hosterPriority
    }
}

/// A titled row of series for the home screen (e.g. "Neue Episoden", "Beliebt").
public struct HomeSection: Identifiable, Hashable, Sendable {
    public var title: String
    public var items: [SeriesSummary]
    public var id: String { title }

    public init(title: String, items: [SeriesSummary]) {
        self.title = title
        self.items = items
    }
}

public enum AniworldError: Error, Equatable, Sendable {
    case cloudflareChallenge(URL)
    case http(status: Int, url: URL)
    case parsing(String)
    case noPlayableStream
    case cancelled
}

/// Type of segment returned by skip time services.
public enum SkipType: String, Codable, Hashable, Sendable, CaseIterable {
    case op = "op"
    case ed = "ed"
    case mixedOp = "mixed-op"
    case mixedEd = "mixed-ed"
    case recap = "recap"

    public var displayName: String {
        switch self {
        case .op, .mixedOp: "Intro"
        case .ed, .mixedEd: "Outro"
        case .recap: "Rückblick"
        }
    }

    public var buttonTitle: String {
        switch self {
        case .op, .mixedOp: "Intro überspringen"
        case .ed, .mixedEd: "Outro überspringen"
        case .recap: "Rückblick überspringen"
        }
    }

    public var isOpening: Bool {
        self == .op || self == .mixedOp
    }

    public var isEnding: Bool {
        self == .ed || self == .mixedEd
    }

    public var isRecap: Bool {
        self == .recap
    }
}

/// A time interval in seconds for an intro, outro or recap.
public struct SkipInterval: Hashable, Codable, Sendable {
    public var startTime: Double
    public var endTime: Double

    public var duration: Double { max(0, endTime - startTime) }

    public init(startTime: Double, endTime: Double) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// A skip segment for an episode.
public struct SkipTime: Identifiable, Hashable, Codable, Sendable {
    public var skipId: String
    public var skipType: SkipType
    public var interval: SkipInterval
    public var episodeLength: Double

    public var id: String { skipId }

    public init(skipId: String, skipType: SkipType, interval: SkipInterval, episodeLength: Double = 0) {
        self.skipId = skipId
        self.skipType = skipType
        self.interval = interval
        self.episodeLength = episodeLength
    }
}

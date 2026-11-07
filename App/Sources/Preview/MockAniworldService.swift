import SwiftUI
import AniworldKit

/// Realistic offline data for SwiftUI previews.
struct MockAniworldService: AniworldService {
    var latency: Duration = .milliseconds(350)

    // MARK: Sample data

    private static func make(_ slug: String, _ title: String, _ description: String) -> SeriesSummary {
        SeriesSummary(
            slug: slug, title: title,
            url: URL(string: "https://aniworld.to/anime/stream/\(slug)")!,
            description: description
        )
    }

    static let sampleSeries: [SeriesSummary] = [
        make("naruto", "Naruto",
             "Der junge Ninja Naruto Uzumaki träumt davon, Hokage seines Dorfes zu werden und von allen anerkannt zu werden. Doch zuerst muss er das Geheimnis hinter dem Dämonenfuchs in seinem Inneren lüften und sich gefährlichen Gegnern stellen."),
        make("attack-on-titan", "Attack on Titan",
             "Seit über hundert Jahren leben die Menschen hinter gewaltigen Mauern, um sich vor menschenfressenden Titanen zu schützen. Als eine Mauer durchbrochen wird, schwört Eren Jäger Rache."),
        make("one-piece", "One Piece",
             "Monkey D. Ruffy will der König der Piraten werden. Gemeinsam mit seiner Crew segelt er über die Grand Line auf der Suche nach dem legendären Schatz One Piece."),
        make("death-note", "Death Note",
             "Der Schüler Light Yagami findet ein Notizbuch, mit dem er Menschen allein durch das Aufschreiben ihres Namens töten kann. Der geniale Detektiv L nimmt die Jagd auf."),
        make("demon-slayer-kimetsu-no-yaiba", "Demon Slayer: Kimetsu no Yaiba",
             "Tanjiro Kamado wird Dämonenjäger, nachdem seine Familie ermordet und seine Schwester in einen Dämon verwandelt wurde."),
        make("jujutsu-kaisen", "Jujutsu Kaisen",
             "Yuji Itadori verschluckt einen verfluchten Finger und wird zum Gefäß des mächtigen Fluchgeistes Sukuna."),
        make("fullmetal-alchemist-brotherhood", "Fullmetal Alchemist: Brotherhood",
             "Die Brüder Edward und Alphonse Elric suchen nach dem Stein der Weisen, um ihre Körper wiederherzustellen."),
        make("my-hero-academia", "My Hero Academia",
             "In einer Welt, in der fast jeder eine Superkraft besitzt, träumt der kraftlose Izuku Midoriya davon, ein Held zu werden."),
        make("one-punch-man", "One Punch Man",
             "Saitama besiegt jeden Gegner mit nur einem Schlag und leidet unter der Langeweile eines Helden ohne Herausforderung."),
        make("steins-gate", "Steins;Gate",
             "Der exzentrische Wissenschaftler Okabe entdeckt, dass sich mit einer Mikrowelle Nachrichten in die Vergangenheit schicken lassen."),
        make("cowboy-bebop", "Cowboy Bebop",
             "Eine Crew von Kopfgeldjägern streift 2071 durch das Sonnensystem und kämpft mit ihrer Vergangenheit."),
        make("spy-x-family", "Spy x Family",
             "Der Spion Twilight muss für seine Mission eine Familie gründen und adoptiert ein Mädchen, das Gedanken lesen kann.")
    ]

    private static let episodeTitles = [
        "Der Beginn", "Ein neuer Weg", "Schatten der Vergangenheit", "Das Versprechen",
        "Aufeinandertreffen", "Die Prüfung", "Wendepunkt", "Verborgene Wahrheit",
        "Der Sturm zieht auf", "Kampf um jeden Preis", "Abschied", "Ein neuer Morgen"
    ]

    private static func detail(for series: SeriesSummary) -> SeriesDetail {
        SeriesDetail(
            summary: series,
            description: series.description,
            coverURL: nil,
            genres: ["Action", "Abenteuer", "Shounen", "Fantasy"],
            startYear: 2002,
            endYear: series.slug == "naruto" ? 2007 : nil,
            seasons: [SeasonRef(number: 0), SeasonRef(number: 1), SeasonRef(number: 2), SeasonRef(number: 3)],
            ageRating: 12,
            genreRefs: sampleGenres.prefix(4).map { $0 }
        )
    }

    static let sampleGenres: [GenreRef] = [
        GenreRef(slug: "action", name: "Action"),
        GenreRef(slug: "abenteuer", name: "Abenteuer"),
        GenreRef(slug: "shounen", name: "Shounen"),
        GenreRef(slug: "fantasy", name: "Fantasy"),
        GenreRef(slug: "comedy", name: "Comedy"),
        GenreRef(slug: "thriller", name: "Thriller"),
        GenreRef(slug: "sci-fi", name: "Sci-Fi")
    ]

    /// Deterministic fake genre membership for previews.
    private static func members(of slug: String) -> [SeriesSummary] {
        guard let index = sampleGenres.firstIndex(where: { $0.slug == slug }) else { return [] }
        return sampleSeries.enumerated()
            .filter { ($0.offset + index) % 2 == 0 || index < 2 }
            .map { $0.element }
    }

    // MARK: AniworldService

    func search(_ query: String) async throws -> [SeriesSummary] {
        try await Task.sleep(for: latency)
        let needle = query.lowercased()
        return Self.sampleSeries.filter { $0.title.lowercased().contains(needle) }
    }

    func seriesDetail(slug: String) async throws -> SeriesDetail {
        try await Task.sleep(for: latency)
        guard let series = Self.sampleSeries.first(where: { $0.slug == slug }) else {
            throw AniworldError.parsing("Unbekannte Serie")
        }
        return Self.detail(for: series)
    }

    func episodes(slug: String, season: Int) async throws -> [EpisodeRef] {
        try await Task.sleep(for: latency)
        let count = season == 0 ? 3 : 12
        return (1...count).map { (number: Int) -> EpisodeRef in
            let path = season == 0 ? "filme/film-\(number)" : "staffel-\(season)/episode-\(number)"
            return EpisodeRef(
                seriesSlug: slug, season: season, number: number,
                title: season == 0 ? "Der Film \(number)" : Self.episodeTitles[(number - 1) % Self.episodeTitles.count],
                url: URL(string: "https://aniworld.to/anime/stream/\(slug)/\(path)")!
            )
        }
    }

    func hosters(for episode: EpisodeRef) async throws -> [HosterLink] {
        try await Task.sleep(for: latency)
        return [
            HosterLink(name: "VOE", language: .germanDub, languageKey: 1,
                       redirectURL: URL(string: "https://aniworld.to/redirect/1")!),
            HosterLink(name: "Vidmoly", language: .germanSub, languageKey: 3,
                       redirectURL: URL(string: "https://aniworld.to/redirect/2")!)
        ]
    }

    func availableLanguages(_ hosters: [HosterLink], preferences: StreamPreferences) -> [StreamLanguage] {
        preferences.languagePriority.filter { language in hosters.contains { $0.language == language } }
    }

    func resolveStream(hosters: [HosterLink], language: StreamLanguage?, preferences: StreamPreferences,
                       verify: Bool, excluding: Set<String>) async throws -> ResolvedStream {
        throw AniworldError.noPlayableStream
    }

    func homeSections() async throws -> [HomeSection] {
        try await Task.sleep(for: latency)
        let all = Self.sampleSeries
        return [
            HomeSection(title: "Neue Episoden", items: Array(all.prefix(6))),
            HomeSection(title: "Beliebte Animes", items: Array(all.dropFirst(3).prefix(8))),
            HomeSection(title: "Neu auf AniWorld", items: Array(all.suffix(5)))
        ]
    }

    func genres() async throws -> [GenreRef] {
        try await Task.sleep(for: latency)
        return Self.sampleGenres
    }

    func series(inGenre slug: String) async throws -> [SeriesSummary] {
        try await Task.sleep(for: latency)
        return Self.members(of: slug)
    }

    func allSeries() async throws -> [SeriesSummary] {
        try await Task.sleep(for: latency)
        return Self.sampleSeries.sorted { $0.title < $1.title }
    }

    func releaseCalendar() async throws -> [CalendarDay] {
        try await Task.sleep(for: latency)
        let all = Self.sampleSeries
        return [
            CalendarDay(title: "Heute", entries: all.prefix(3).enumerated().map { offset, series -> CalendarEntry in
                if offset == 0 {
                    // Dub lags behind the subs.
                    return CalendarEntry(id: "today-\(series.slug)", series: series, info: "S01E05", releases: [
                        CalendarRelease(code: "S01E02", language: .germanDub, time: "17:10"),
                        CalendarRelease(code: "S01E05", language: .germanSub, time: "17:10"),
                        CalendarRelease(code: "S01E05", language: .englishSub, time: "17:10")
                    ])
                }
                return CalendarEntry(id: "today-\(series.slug)", series: series, info: "Staffel 2 · Folge \(offset + 5)")
            }),
            CalendarDay(title: "Morgen", entries: all.dropFirst(3).prefix(2).map { series in
                CalendarEntry(id: "tomorrow-\(series.slug)", series: series, info: "Neue Folge")
            }),
            CalendarDay(title: "Übermorgen", entries: all.dropFirst(5).prefix(2).map { series in
                CalendarEntry(id: "later-\(series.slug)", series: series, info: "Staffel 1 · Folge 1")
            })
        ]
    }
}

/// A mock that always fails, to preview error states.
struct FailingAniworldService: AniworldService {
    let error: AniworldError

    func search(_ query: String) async throws -> [SeriesSummary] { throw error }
    func seriesDetail(slug: String) async throws -> SeriesDetail { throw error }
    func episodes(slug: String, season: Int) async throws -> [EpisodeRef] { throw error }
    func hosters(for episode: EpisodeRef) async throws -> [HosterLink] { throw error }
    func availableLanguages(_ hosters: [HosterLink], preferences: StreamPreferences) -> [StreamLanguage] { [] }
    func resolveStream(hosters: [HosterLink], language: StreamLanguage?, preferences: StreamPreferences,
                       verify: Bool, excluding: Set<String>) async throws -> ResolvedStream { throw error }
    func homeSections() async throws -> [HomeSection] { throw error }
}

extension View {
    /// Injects the same environment objects as `AniworldApp`, backed by the mock service.
    @MainActor
    func previewEnvironment(service: AniworldService = MockAniworldService()) -> some View {
        let env = AppEnvironment.make(service: service, stats: WatchStatsStore.preview())
        return self
            .environment(env.library)
            .environment(env.settings)
            .environment(env.playback)
            .environment(env.sync)
            .environment(env.downloads)
            .environment(env.watcher)
            .environment(env.stats)
            .environment(env.streakReminders)
            .environment(\.aniworld, env.service)
            .preferredColorScheme(.dark)
    }
}

#Preview("Home – Cloudflare-Fehler") {
    HomeView()
        .previewEnvironment(service: FailingAniworldService(
            error: .cloudflareChallenge(URL(string: "https://aniworld.to")!)
        ))
}

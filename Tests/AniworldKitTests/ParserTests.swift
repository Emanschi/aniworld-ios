import XCTest
@testable import AniworldKit

final class SearchParserTests: XCTestCase {
    func testKeepsOnlySeriesRoots() throws {
        let series = SearchParser.parse(try Fixture.data("search_naruto.json"))
        XCTAssertFalse(series.isEmpty)
        for s in series {
            XCTAssertTrue(s.url.absoluteString.hasPrefix("https://aniworld.to/anime/stream/"))
            XCTAssertFalse(s.url.absoluteString.contains("/staffel-"))
            XCTAssertFalse(s.url.absoluteString.contains("/episode-"))
        }
    }

    func testStripsMarkupAndDedupes() throws {
        let series = SearchParser.parse(try Fixture.data("search_naruto.json"))
        XCTAssertEqual(Set(series.map(\.slug)).count, series.count)
        let naruto = try XCTUnwrap(series.first { $0.slug == "naruto" })
        XCTAssertEqual(naruto.title, "Naruto")
        XCTAssertFalse(naruto.description.contains("<em>"))
        XCTAssertFalse(naruto.description.contains("&#"))
    }

    func testDecodesEntitiesInTitle() throws {
        let series = SearchParser.parse(try Fixture.data("search_naruto.json"))
        let spinoff = try XCTUnwrap(series.first { $0.slug == "naruto-spin-off-rock-lee-his-ninja-pals" })
        XCTAssertEqual(spinoff.title, "Naruto Spin-Off: Rock Lee & His Ninja Pals")
    }

    func testHandlesGarbage() {
        XCTAssertEqual(SearchParser.parse(Data("[]".utf8)), [])
        XCTAssertEqual(SearchParser.parse(Data("not json".utf8)), [])
        XCTAssertEqual(SearchParser.parse([["link": "/support/frage/x", "title": "x"]]), [])
        XCTAssertEqual(SearchParser.parse([["foo": "bar"]]), [])
    }

    func testTitleMatchesFirstKeepingSiteOrder() {
        let payload: [[String: Any]] = [
            ["link": "/anime/stream/toradora", "title": "Toradora!"],
            ["link": "/anime/stream/frieren", "title": "<em>Frieren</em>: Beyond"],
            ["link": "/anime/stream/berghof", "title": "Die Kinder vom Berghof"],
            ["link": "/anime/stream/frieren-2", "title": "Frieren 2"],
        ]
        XCTAssertEqual(SearchParser.parse(payload, query: "frieren").map(\.slug),
                       ["frieren", "frieren-2", "toradora", "berghof"])
        XCTAssertEqual(SearchParser.parse(payload).first?.slug, "toradora")
    }
}

final class SeriesParserTests: XCTestCase {
    func testSeasonsIncludeFilmsLast() throws {
        let seasons = SeriesParser.parseSeasons(try Fixture.text("series_naruto.html"), slug: "naruto")
        XCTAssertEqual(seasons.map(\.number), [1, 2, 3, 4, 0])
        XCTAssertTrue(seasons.last?.isFilms ?? false)
    }

    func testEpisodesSeasonOne() throws {
        let eps = SeriesParser.parseEpisodes(try Fixture.text("series_naruto.html"), slug: "naruto", season: 1)
        XCTAssertEqual(eps.first?.number, 1)
        XCTAssertEqual(eps.first?.season, 1)
        XCTAssertEqual(eps.first?.url.absoluteString, "https://aniworld.to/anime/stream/naruto/staffel-1/episode-1")
        XCTAssertEqual(eps.first?.code, "S01E01")
        XCTAssertEqual(eps.first?.title, "Wer ist Naruto?")
        let nums = eps.map(\.number)
        XCTAssertEqual(nums, Array(Set(nums)).sorted())
    }

    func testEpisodesFilms() throws {
        let eps = SeriesParser.parseEpisodes(try Fixture.text("films_naruto.html"), slug: "naruto", season: 0)
        XCTAssertFalse(eps.isEmpty)
        XCTAssertTrue(eps.allSatisfy { $0.season == 0 })
        XCTAssertEqual(eps.first?.url.absoluteString, "https://aniworld.to/anime/stream/naruto/filme/film-1")
        XCTAssertEqual(eps.first?.code, "Film 1")
        XCTAssertEqual(eps.first?.title, "Hidden Leaf Village Grand Sports Festival! [OVA]")
    }

    func testDetail() throws {
        let d = try SeriesParser.parseDetail(try Fixture.text("series_naruto.html"), slug: "naruto")
        XCTAssertEqual(d.summary.title, "Naruto")
        XCTAssertEqual(d.startYear, 2002)
        XCTAssertEqual(d.endYear, 2007)
        XCTAssertTrue(d.description.hasPrefix("Ein riesiges neunschwänziges Fuchsmonster"))
        XCTAssertGreaterThan(d.description.count, 300)
        XCTAssertEqual(d.coverURL?.absoluteString.hasPrefix("https://aniworld.to/public/img/cover/naruto-stream-cover"), true)
        XCTAssertEqual(d.backdropURL?.host, "aniworld.to")
        XCTAssertTrue(d.genres.contains("Action"))
        XCTAssertFalse(d.genres.contains("GerSub"))
        XCTAssertEqual(d.seasons.map(\.number), [1, 2, 3, 4, 0])
        XCTAssertEqual(d.ageRating, 12)
        XCTAssertTrue(d.genreRefs.contains(GenreRef(slug: "action", name: "Action")))
        XCTAssertEqual(d.genreRefs.map(\.name), d.genres)
    }

    func testAgeRatingFallbackAndOldJSONDecoding() throws {
        let html = "<div class=\"series-title\"><h1><span>X</span></h1></div><div class=\"fsk fsk16\">Ab: <span>16</span></div>"
        XCTAssertEqual(try SeriesParser.parseDetail(html, slug: "x").ageRating, 16)
        XCTAssertNil(try SeriesParser.parseDetail("<div class=\"series-title\"><h1><span>X</span></h1></div>", slug: "x").ageRating)

        // JSON stored by an older version has no ageRating/genreRefs keys.
        let old = """
        {"summary":{"slug":"x","title":"X","url":"https://aniworld.to/anime/stream/x","description":""},
         "description":"d","genres":["Action"],"seasons":[{"number":1}]}
        """
        let decoded = try JSONDecoder().decode(SeriesDetail.self, from: Data(old.utf8))
        XCTAssertNil(decoded.ageRating)
        XCTAssertEqual(decoded.genreRefs, [])
        XCTAssertEqual(decoded.genres, ["Action"])
    }

    func testDetailWithoutTitleThrows() {
        XCTAssertThrowsError(try SeriesParser.parseDetail("<html></html>", slug: "x"))
    }
}

final class EpisodeParserTests: XCTestCase {
    func testLanguageMapCoversAllThree() throws {
        let map = EpisodeParser.parseLanguageMap(try Fixture.text("episode_naruto_s1e1.html"))
        XCTAssertEqual(Set(map.values.compactMap { $0 }), [.germanDub, .germanSub, .englishSub])
        XCTAssertEqual(map[1] ?? nil, .germanDub)
        XCTAssertEqual(map[3] ?? nil, .germanSub)
        XCTAssertEqual(map[2] ?? nil, .englishSub)
    }

    func testClassificationOrder() {
        XCTAssertEqual(EpisodeParser.classifyLanguage("/img/japanese-german.svg", "Deutsch"), .germanSub)
        XCTAssertEqual(EpisodeParser.classifyLanguage("", "", "mit Untertitel Deutsch"), .germanSub)
        XCTAssertEqual(EpisodeParser.classifyLanguage("/img/japanese-english.svg"), .englishSub)
        XCTAssertEqual(EpisodeParser.classifyLanguage("Englische Sprache"), .englishSub)
        XCTAssertEqual(EpisodeParser.classifyLanguage("/img/german.svg", "Deutsch"), .germanDub)
        XCTAssertNil(EpisodeParser.classifyLanguage("/img/french.svg", "Français"))
    }

    func testHosters() throws {
        let hosters = EpisodeParser.parseHosters(try Fixture.text("episode_naruto_s1e1.html"))
        XCTAssertTrue(Set(hosters.map(\.name)).contains("VOE"))
        for h in hosters {
            XCTAssertTrue(h.redirectURL.absoluteString.hasPrefix("https://aniworld.to/redirect/"))
            XCTAssertNotNil(h.language)
        }
        let voeDub = try XCTUnwrap(hosters.first { $0.name == "VOE" && $0.language == .germanDub })
        XCTAssertEqual(voeDub.languageKey, 1)
    }

    func testUnknownLanguageKeyYieldsNilLanguage() {
        let html = """
        <div class="changeLanguageBox"><img src="/german.svg" data-lang-key="1" alt="Deutsch"></div>
        <ul><li data-lang-key="9" data-link-target="/redirect/5"><h4>VOE</h4></li></ul>
        """
        let hosters = EpisodeParser.parseHosters(html)
        XCTAssertEqual(hosters.count, 1)
        XCTAssertNil(hosters[0].language)
        XCTAssertEqual(hosters[0].languageKey, 9)
    }
}

final class HomeParserTests: XCTestCase {
    func testParsesRows() {
        let html = """
        <div class="pageTitle15 controls"><h2>Beliebt</h2></div>
        <div class="previews"><div class="preview rows">
          <div class="coverListItem"><a href="/anime/stream/foo"><div><img data-src="/public/img/cover/foo.png" src="data:image/png;base64,AAAA"></div><h3> Foo </h3><small>Action</small></a></div>
          <div class="coverListItem"><a href="/anime/stream/foo"><h3>Foo again</h3></a></div>
          <div class="coverListItem"><a href="/anime/stream/bar"><h3>Bar</h3></a></div>
        </div></div>
        <div class="pageTitle15"><h2>Leer</h2></div><div class="previews"></div>
        <div class="pageTitle15"><h2>Genres</h2></div><div>no previews</div>
        """
        let sections = HomeParser.parse(html)
        XCTAssertEqual(sections.map(\.title), ["Beliebt"])
        XCTAssertEqual(sections[0].items.map(\.slug), ["foo", "bar"])
        XCTAssertEqual(sections[0].items[0].title, "Foo")
        XCTAssertEqual(sections[0].items[0].description, "Action")
        XCTAssertEqual(sections[0].items[0].coverURL?.absoluteString, "https://aniworld.to/public/img/cover/foo.png")
        XCTAssertNil(sections[0].items[1].coverURL)
    }

    func testGarbageYieldsEmpty() {
        XCTAssertEqual(HomeParser.parse("<html><body>hi</body></html>"), [])
        XCTAssertEqual(HomeParser.parse(""), [])
    }
}

final class GenreParserTests: XCTestCase {
    func testGenresFromHomePage() throws {
        let genres = GenreParser.parseGenres(try Fixture.text("home_genres.html"))
        XCTAssertGreaterThan(genres.count, 20)
        XCTAssertTrue(genres.contains(GenreRef(slug: "action", name: "Action")))
        XCTAssertTrue(genres.contains(GenreRef(slug: "actionkomoedie", name: "Actionkomödie")))
        XCTAssertFalse(genres.contains { ["ger", "gersub", "engsub", "eng", "gerdub"].contains($0.slug) })
        XCTAssertEqual(Set(genres.map(\.slug)).count, genres.count)
    }

    func testGenreRefRejectsPaginationAndLanguages() {
        XCTAssertNil(GenreParser.genreRef(href: "https://aniworld.to/genre/action/2", name: "2"))
        XCTAssertNil(GenreParser.genreRef(href: "/genre/gersub", name: "GerSub"))
        XCTAssertNil(GenreParser.genreRef(href: "/anime/stream/x", name: "x"))
        XCTAssertEqual(GenreParser.genreRef(href: "/genre/boys-love", name: " Boys Love ")?.name, "Boys Love")
    }

    func testGenrePage() throws {
        let html = try Fixture.text("genre_action.html")
        let items = GenreParser.parseGenrePage(html)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].slug, "compass-20-animation-project")
        XCTAssertEqual(items[0].title, "#Compass 2.0 Animation Project")
        XCTAssertEqual(items[0].url.absoluteString, "https://aniworld.to/anime/stream/compass-20-animation-project")
        XCTAssertEqual(items[0].coverURL?.absoluteString.hasPrefix("https://aniworld.to/public/img/cover/compass-20"), true)
        XCTAssertEqual(GenreParser.lastPage(html, slug: "action"), 37)
        XCTAssertEqual(GenreParser.lastPage("<html></html>", slug: "action"), 1)
    }

    func testSeriesLists() throws {
        for name in ["animes.html", "animes_alphabet.html"] {
            let items = GenreParser.parseSeriesList(try Fixture.text(name))
            XCTAssertFalse(items.isEmpty, name)
            XCTAssertEqual(Set(items.map(\.slug)).count, items.count)
            XCTAssertTrue(items.allSatisfy { $0.url.absoluteString.hasPrefix("https://aniworld.to/anime/stream/") })
            XCTAssertTrue(items.allSatisfy { !$0.title.isEmpty })
        }
        let first = try XCTUnwrap(GenreParser.parseSeriesList(try Fixture.text("animes.html")).first)
        XCTAssertEqual(first.slug, "demons-ascension")
        XCTAssertEqual(first.title, "Demon's Ascension")
    }

    func testGarbageYieldsEmpty() {
        XCTAssertEqual(GenreParser.parseGenres(""), [])
        XCTAssertEqual(GenreParser.parseGenrePage("<html></html>"), [])
        XCTAssertEqual(GenreParser.parseSeriesList("<html></html>"), [])
    }
}

final class CalendarParserTests: XCTestCase {
    func testParsesDays() throws {
        let days = CalendarParser.parse(try Fixture.text("animekalender.html"))
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].title, "Donnerstag, 05.11.2026 (heute)")
        let first = try XCTUnwrap(days[0].entries.first)
        XCTAssertEqual(first.series.slug, "fx-fighter-kurumichan")
        XCTAssertEqual(first.series.title, "FX Fighter KURUMICHAN")
        XCTAssertEqual(first.series.url.absoluteString, "https://aniworld.to/anime/stream/fx-fighter-kurumichan")
        XCTAssertEqual(first.info, "S01E06 · 13:40")
        XCTAssertNotNil(first.series.coverURL)
        XCTAssertEqual(Set(days.flatMap(\.entries).map(\.id)).count, days.flatMap(\.entries).count)
    }

    func testDayTitles() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let date = try XCTUnwrap(CalendarParser.date(in: "Donnerstag, 05.11.2026 (heute)", calendar: cal))
        let day = CalendarDay(title: "x", entries: [], date: date)
        let noon = { (d: Int) in cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 12))! }
        XCTAssertEqual(day.displayTitle(now: noon(5), calendar: cal), "Heute")
        XCTAssertEqual(day.displayTitle(now: noon(4), calendar: cal), "Morgen")
        XCTAssertEqual(day.displayTitle(now: noon(6), calendar: cal), "Gestern")
        XCTAssertEqual(day.displayTitle(now: noon(1), calendar: cal), "Donnerstag, 05.11.")
        XCTAssertEqual(CalendarDay(title: "roh", entries: []).displayTitle(), "roh")
        XCTAssertNil(CalendarParser.date(in: "ohne Datum"))
    }

    func testGarbageYieldsEmpty() {
        XCTAssertEqual(CalendarParser.parse(""), [])
        XCTAssertEqual(CalendarParser.parse("<section class=\"calendarList\"><h3>Montag</h3></section>"), [])
    }
}
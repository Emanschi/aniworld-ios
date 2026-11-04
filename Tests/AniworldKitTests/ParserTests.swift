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

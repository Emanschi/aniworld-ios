import Foundation
import AniworldKit

extension WatchStatsStore {
    /// Store with generated sample sessions for SwiftUI previews (nothing is written to disk).
    static func preview() -> WatchStatsStore {
        let now = Date()
        let meta: [String: SeriesMeta] = [
            "naruto": SeriesMeta(genres: ["Action", "Abenteuer"], ageRating: 12, updatedAt: now),
            "one-piece": SeriesMeta(genres: ["Abenteuer", "Comedy"], ageRating: 12, updatedAt: now),
            "attack-on-titan": SeriesMeta(genres: ["Action", "Drama"], ageRating: 16, updatedAt: now),
            "death-note": SeriesMeta(genres: ["Thriller", "Mystery"], ageRating: 16, updatedAt: now),
            "bleach": SeriesMeta(genres: ["Action", "Fantasy"], ageRating: 12, updatedAt: now),
            "demon-slayer": SeriesMeta(genres: ["Action", "Fantasy"], ageRating: 16, updatedAt: now),
        ]
        return WatchStatsStore(fileURL: nil, initialSessions: sampleSessions(now: now), initialMeta: meta)
    }

    static func sampleSessions(now: Date = Date()) -> [WatchSession] {
        let calendar = Calendar.current
        let titles: [(slug: String, title: String)] = [
            ("naruto", "Naruto"), ("one-piece", "One Piece"), ("attack-on-titan", "Attack on Titan"),
            ("death-note", "Death Note"), ("bleach", "Bleach"), ("demon-slayer", "Demon Slayer"),
        ]
        let languages: [StreamLanguage] = [.germanDub, .germanDub, .germanSub, .englishSub]
        var result: [WatchSession] = []
        var seed = 7
        func next(_ n: Int) -> Int {
            seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
            return seed % max(n, 1)
        }
        for dayOffset in 0..<75 {
            guard next(10) < 6, let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let hour = [8, 13, 19, 21, 22, 23][next(6)]
            var start = calendar.date(bySettingHour: hour, minute: next(40), second: 0, of: day) ?? day
            let entry = titles[next(titles.count)]
            let count = 1 + next(4)
            for e in 0..<count {
                let minutes = Double(18 + next(8))
                let end = start.addingTimeInterval(minutes * 60)
                if end > now { break }
                result.append(WatchSession(
                    seriesSlug: entry.slug, seriesTitle: entry.title,
                    season: 1 + next(2), episode: 1 + e + dayOffset % 20,
                    language: languages[next(languages.count)], hoster: "VOE",
                    startedAt: start, endedAt: end, watchedSeconds: minutes * 60,
                    episodeDuration: minutes * 60 + 90, completed: next(10) < 8,
                    skippedSeconds: Double(next(3)) * 85, wasOffline: next(10) == 0, deviceID: "preview"))
                start = end.addingTimeInterval(Double(60 + next(300)))
            }
        }
        return result.sorted { $0.startedAt < $1.startedAt }
    }
}

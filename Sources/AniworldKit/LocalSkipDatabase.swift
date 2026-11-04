import Foundation

/// Fast, offline-first local database for anime skip times.
/// Supports series slugs/names, seasons, and episode ranges (e.g. "1-13", "14", "default").
public final class LocalSkipDatabase: @unchecked Sendable {
    public static let shared = LocalSkipDatabase()

    public struct Interval: Sendable {
        public var start: Double
        public var end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }
    }

    public struct Rule: Sendable {
        public var op: Interval?
        public var ed: Interval?
        public var recap: Interval?
        /// True when "op": null was explicitly specified, meaning this episode has no intro.
        public var noOpening: Bool

        public init(op: Interval? = nil, ed: Interval? = nil, recap: Interval? = nil, noOpening: Bool = false) {
            self.op = op
            self.ed = ed
            self.recap = recap
            self.noOpening = noOpening
        }
    }

    private struct EpisodeMatcher: Sendable {
        enum Pattern: Sendable {
            case single(Int)
            case range(Int, Int)
            case wildcard
        }

        var pattern: Pattern
        var rule: Rule

        func matches(episode: Int) -> Bool {
            switch pattern {
            case .single(let num):
                return num == episode
            case .range(let start, let end):
                return episode >= start && episode <= end
            case .wildcard:
                return true
            }
        }

        var priority: Int {
            switch pattern {
            case .single: return 3
            case .range: return 2
            case .wildcard: return 1
            }
        }
    }

    private let lock = NSLock()
    private var seriesMap: [String: [String: [EpisodeMatcher]]] = [:]

    public init(jsonData: Data? = nil) {
        if let jsonData {
            load(data: jsonData)
        } else if let bundleData = Self.loadBundleData() {
            load(data: bundleData)
        }
    }

    private static func loadBundleData() -> Data? {
        if let url = Bundle.main.url(forResource: "skip_database", withExtension: "json") {
            return try? Data(contentsOf: url)
        }
        return nil
    }

    public func load(data: Data) {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var parsedMap: [String: [String: [EpisodeMatcher]]] = [:]

        for (seriesKey, seasonObj) in raw {
            guard let seasons = seasonObj as? [String: Any] else { continue }
            let normalizedSeries = normalize(seriesKey)
            var seasonMap: [String: [EpisodeMatcher]] = [:]

            for (seasonKey, episodeObj) in seasons {
                guard let episodes = episodeObj as? [String: Any] else { continue }
                let normalizedSeason = normalizeSeasonKey(seasonKey)
                var matchers: [EpisodeMatcher] = []

                for (epKey, ruleObj) in episodes {
                    guard let ruleDict = ruleObj as? [String: Any] else { continue }
                    guard let pattern = parseEpisodePattern(epKey) else { continue }
                    let rule = parseRule(ruleDict)
                    matchers.append(EpisodeMatcher(pattern: pattern, rule: rule))
                }

                // Sort so single episode takes precedence over range, which takes precedence over wildcard
                matchers.sort { $0.priority > $1.priority }
                seasonMap[normalizedSeason] = matchers
            }

            parsedMap[normalizedSeries] = seasonMap
        }

        lock.lock()
        self.seriesMap = parsedMap
        lock.unlock()
    }

    /// Looks up skip times for an episode.
    /// Returns `nil` if series or episode is not found in the local table.
    /// If found, returns the list of `SkipTime` intervals (can be empty if episode has no intro/outro).
    public func findSkipTimes(seriesSlug: String, seriesTitle: String, season: Int, episode: Int) -> [SkipTime]? {
        lock.lock()
        defer { lock.unlock() }

        let keysToTry = [normalize(seriesSlug), normalize(seriesTitle)]
        for seriesKey in keysToTry {
            guard let seasonMap = seriesMap[seriesKey] else { continue }

            let seasonKeysToTry = ["\(season)", "default", "*"]
            for sKey in seasonKeysToTry {
                guard let matchers = seasonMap[sKey] else { continue }
                if let matched = matchers.first(where: { $0.matches(episode: episode) }) {
                    let times = buildSkipTimes(from: matched.rule, season: season, episode: episode)
                    if !times.isEmpty || matched.rule.noOpening {
                        return times
                    }
                }
            }
        }

        return nil
    }

    private func buildSkipTimes(from rule: Rule, season: Int, episode: Int) -> [SkipTime] {
        var list: [SkipTime] = []

        if let recap = rule.recap, recap.end > recap.start {
            list.append(SkipTime(
                skipId: "local-recap-s\(season)e\(episode)",
                skipType: .recap,
                interval: SkipInterval(startTime: recap.start, endTime: recap.end)
            ))
        }

        if let op = rule.op, op.end > op.start, !rule.noOpening {
            list.append(SkipTime(
                skipId: "local-op-s\(season)e\(episode)",
                skipType: .op,
                interval: SkipInterval(startTime: op.start, endTime: op.end)
            ))
        }

        if let ed = rule.ed, ed.end > ed.start {
            list.append(SkipTime(
                skipId: "local-ed-s\(season)e\(episode)",
                skipType: .ed,
                interval: SkipInterval(startTime: ed.start, endTime: ed.end)
            ))
        }

        return list.sorted { $0.interval.startTime < $1.interval.startTime }
    }

    private func normalize(_ string: String) -> String {
        string.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func normalizeSeasonKey(_ key: String) -> String {
        let cleaned = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == "default" || cleaned == "*" || cleaned == "all" { return "default" }
        // Extract digits if written like "staffel_1" or "s1"
        let digits = cleaned.filter { $0.isNumber }
        return digits.isEmpty ? cleaned : digits
    }

    private func parseEpisodePattern(_ key: String) -> EpisodeMatcher.Pattern? {
        let cleaned = key.lowercased()
            .replacingOccurrences(of: "folge", with: "")
            .replacingOccurrences(of: "ep", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned == "default" || cleaned == "*" || cleaned == "all" {
            return .wildcard
        }

        if cleaned.contains("-") {
            let parts = cleaned.components(separatedBy: "-")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap { Int($0) }
            if parts.count == 2, parts[0] <= parts[1] {
                return .range(parts[0], parts[1])
            }
        }

        if let single = Int(cleaned) {
            return .single(single)
        }

        return nil
    }

    private func parseRule(_ dict: [String: Any]) -> Rule {
        let noOp = dict["op"] is NSNull
        let opInterval = parseInterval(dict["op"])
        let edInterval = parseInterval(dict["ed"])
        let recapInterval = parseInterval(dict["recap"])

        return Rule(
            op: opInterval,
            ed: edInterval,
            recap: recapInterval,
            noOpening: noOp
        )
    }

    private func parseInterval(_ value: Any?) -> Interval? {
        guard let dict = value as? [String: Any] else { return nil }
        guard let start = (dict["start"] as? NSNumber)?.doubleValue,
              let end = (dict["end"] as? NSNumber)?.doubleValue,
              end > start, start >= 0 else {
            return nil
        }
        return Interval(start: start, end: end)
    }
}

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

        /// Strict ordering used to pick the winner when several matchers match an episode.
        func isMoreSpecific(than other: EpisodeMatcher) -> Bool {
            if priority != other.priority { return priority > other.priority }
            if case .range(let s1, let e1) = pattern, case .range(let s2, let e2) = other.pattern {
                let w1 = e1 - s1
                let w2 = e2 - s2
                if w1 != w2 { return w1 < w2 }
                return s1 < s2
            }
            if case .single(let a) = pattern, case .single(let b) = other.pattern {
                return a < b
            }
            return false
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
            guard !normalizedSeries.isEmpty else { continue }
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

                // Deterministic precedence: single > range (narrowest first, then lower start) > wildcard.
                matchers.sort { $0.isMoreSpecific(than: $1) }
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

        // Japanese-only or otherwise unnormalizable names normalize to "" and must never match.
        var bases: [String] = []
        for key in [normalize(seriesSlug), normalize(seriesTitle)] where !key.isEmpty && !bases.contains(key) {
            bases.append(key)
        }
        guard !bases.isEmpty else { return nil }

        // 1. Exact season of the base series.
        for base in bases {
            if let times = resolve(seriesMap[base]?["\(season)"], season: season, episode: episode) {
                return times
            }
        }

        // 2. Season-specific alias entries (e.g. "jujutsu-kaisen-2nd-season"): their season N, then "1"
        //    (standalone season entries often index episodes under season 1), then their default rule.
        if season > 1 {
            for base in bases {
                for alias in generateSeasonSeriesVariants(base: base, season: season) {
                    guard let seasonMap = seriesMap[alias] else { continue }
                    for sKey in ["\(season)", "1", "default"] {
                        if let times = resolve(seasonMap[sKey], season: season, episode: episode) {
                            return times
                        }
                    }
                }
            }
        }

        // 3. Default/wildcard rule of the base series.
        for base in bases {
            if let times = resolve(seriesMap[base]?["default"], season: season, episode: episode) {
                return times
            }
        }

        return nil
    }

    /// Best matching rule among `matchers` as skip times; nil when nothing matches or the rule is empty
    /// (so the lookup can continue with less specific entries).
    private func resolve(_ matchers: [EpisodeMatcher]?, season: Int, episode: Int) -> [SkipTime]? {
        guard let matchers, let matched = matchers.first(where: { $0.matches(episode: episode) }) else { return nil }
        let times = buildSkipTimes(from: matched.rule, season: season, episode: episode)
        return (!times.isEmpty || matched.rule.noOpening) ? times : nil
    }

    private func generateSeasonSeriesVariants(base: String, season: Int) -> [String] {
        guard !base.isEmpty else { return [] }
        var variants: [String] = []
        variants.append("\(base)season\(season)")
        variants.append("\(base)s\(season)")
        variants.append("\(base)staffel\(season)")
        variants.append("\(base)\(season)")

        switch season {
        case 2:
            variants.append("\(base)2ndseason")
            variants.append("\(base)secondseason")
            variants.append("\(base)ii")
        case 3:
            variants.append("\(base)3rdseason")
            variants.append("\(base)thirdseason")
            variants.append("\(base)iii")
        case 4:
            variants.append("\(base)4thseason")
            variants.append("\(base)fourthseason")
            variants.append("\(base)iv")
            variants.append("\(base)finalseason")
            variants.append("\(base)thefinalseason")
        case 5:
            variants.append("\(base)5thseason")
            variants.append("\(base)fifthseason")
            variants.append("\(base)v")
        case 6:
            variants.append("\(base)6thseason")
            variants.append("\(base)vi")
        case 7:
            variants.append("\(base)7thseason")
            variants.append("\(base)vii")
        default:
            variants.append("\(base)\(season)thseason")
        }
        return variants
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
            .folding(options: .diacriticInsensitive, locale: nil)
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
        var cleaned = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned == "default" || cleaned == "*" || cleaned == "all" {
            return .wildcard
        }

        // Only a leading prefix ("folge 3", "episode3", "ep 3", "e3") is stripped, never text elsewhere.
        for prefix in ["folge", "episode", "ep", "e"] where cleaned.hasPrefix(prefix) {
            cleaned = String(cleaned.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".:_")))
            break
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

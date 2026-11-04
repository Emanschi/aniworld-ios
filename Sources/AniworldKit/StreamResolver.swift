import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Picks and resolves a playable stream from hosters.
///
/// Order: language priority first, then hoster priority, so the best language's hosters are
/// exhausted before falling through. Extraction failures fall through to the next candidate.
/// Resolved streams are liveness-checked: VOE in particular serves a master playlist whose
/// segments answer 403 from a dead CDN node, so we confirm one real segment loads.
struct StreamResolver: Sendable {
    let http: HTTPFetching
    let extractors: ExtractorRegistry

    /// Status codes meaning "the CDN served us bytes" (206 = partial/Range reply).
    static let okStatus: Set<Int> = [200, 206]

    // MARK: Ordering

    /// Languages offered by `hosters`, by `preferences.languagePriority`; unlisted ones last.
    static func availableLanguages(_ hosters: [HosterLink], preferences: StreamPreferences) -> [StreamLanguage] {
        var unique: [StreamLanguage] = []
        for case let language? in hosters.map(\.language) where !unique.contains(language) { unique.append(language) }
        let pri = preferences.languagePriority
        return unique.enumerated().sorted { a, b in
            let ra = pri.firstIndex(of: a.element) ?? pri.count, rb = pri.firstIndex(of: b.element) ?? pri.count
            return (ra, a.offset) < (rb, b.offset)
        }.map(\.element)
    }

    /// With `language`, restricts to it and orders by hoster priority. Without, orders by
    /// (language priority, hoster priority) and drops unclassified/unlisted languages.
    static func orderHosters(_ hosters: [HosterLink], language: StreamLanguage?,
                             preferences: StreamPreferences) -> [HosterLink] {
        let hostPri = preferences.hosterPriority.map { $0.lowercased() }
        func hostRank(_ h: HosterLink) -> Int { hostPri.firstIndex(of: h.name.lowercased()) ?? hostPri.count }
        let candidates: [HosterLink]
        func langRank(_ h: HosterLink) -> Int { h.language.flatMap { preferences.languagePriority.firstIndex(of: $0) } ?? 0 }
        if let language {
            candidates = hosters.filter { $0.language == language }
        } else {
            candidates = hosters.filter { $0.language.map(preferences.languagePriority.contains) ?? false }
        }
        return candidates.enumerated().sorted { a, b in
            (langRank(a.element), hostRank(a.element), a.offset) < (langRank(b.element), hostRank(b.element), b.offset)
        }.map(\.element)
    }

    // MARK: Resolution

    func resolve(hosters: [HosterLink], language: StreamLanguage?, preferences: StreamPreferences,
                 verify: Bool, excluding: Set<String>) async throws -> ResolvedStream {
        let skipped = Set(excluding.map { $0.lowercased() })
        for hoster in Self.orderHosters(hosters, language: language, preferences: preferences) {
            try Task.checkCancellation()
            guard !skipped.contains(hoster.name.lowercased()),
                  let extractor = extractors.extractor(for: hoster.name),
                  let stream = await extractor.extract(redirectURL: hoster.redirectURL, http: http) else { continue }
            if verify, !(await isLive(stream)) { continue }
            return ResolvedStream(url: stream.url, headers: stream.headers, hoster: hoster.name, language: hoster.language)
        }
        throw AniworldError.noPlayableStream
    }

    // MARK: Liveness

    /// First non-comment line of an m3u8, resolved against `base`.
    static func firstEntry(of playlist: String, base: URL) -> URL? {
        for line in playlist.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("#") { return URL(string: trimmed, relativeTo: base)?.absoluteURL }
        }
        return nil
    }

    /// Best-effort check that the stream delivers bytes, not just a 200. HLS drills
    /// master -> variant -> first segment (where VOE's 403 shows up); progressive URLs are probed
    /// directly. Segments are probed without downloading the body. Errors count as "not live".
    func isLive(_ stream: ExtractedStream) async -> Bool {
        do {
            func request(_ url: URL) -> URLRequest {
                var r = URLRequest(url: url)
                for (key, value) in stream.headers { r.setValue(value, forHTTPHeaderField: key) }
                return r
            }
            var target = stream.url
            if target.absoluteString.lowercased().contains(".m3u8") {
                let master = try await http.send(request(target))
                guard Self.okStatus.contains(master.status) else { return false }
                guard let entry = Self.firstEntry(of: master.text, base: target) else { return true }
                target = entry
                if target.absoluteString.lowercased().contains(".m3u8") {
                    let variant = try await http.send(request(target))
                    guard Self.okStatus.contains(variant.status) else { return false }
                    guard let segment = Self.firstEntry(of: variant.text, base: target) else { return true }
                    target = segment
                }
            }
            return Self.okStatus.contains(try await http.probeStatus(request(target)))
        } catch {
            return false
        }
    }
}

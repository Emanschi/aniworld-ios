import Foundation
import Observation
import UserNotifications

struct AppUpdate: Equatable, Identifiable {
    let version: String
    let name: String
    let notes: String
    let url: URL
    let publishedAt: Date?

    var id: String { version }

    /// Plain-text excerpt of the (markdown) release notes for the banner.
    var excerpt: String {
        var lines: [String] = []
        for raw in notes.split(whereSeparator: { $0.isNewline }) {
            var line: String = String(raw).trimmingCharacters(in: .whitespaces)
            while line.hasPrefix("#") { line.removeFirst() }
            line = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") || line.hasPrefix("* ") { line = "• " + String(line.dropFirst(2)) }
            if !line.isEmpty { lines.append(line) }
        }
        let joined: String = lines.joined(separator: "\n")
        if joined.count <= 280 { return joined }
        return String(joined.prefix(280)) + "…"
    }
}

/// Cached copy of the latest GitHub release.
private struct CachedRelease: Codable {
    let version: String
    let name: String
    let body: String
    let url: String
    let publishedAt: Date?
}

private struct GitHubRelease: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let published_at: String?
    let draft: Bool?
    let prerelease: Bool?
}

@MainActor
@Observable
final class AppUpdateChecker {
    static let shared = AppUpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        /// Repo private / offline / rate limited: nothing to show.
        case unavailable
    }

    private(set) var availableUpdate: AppUpdate?
    private(set) var state: State = .idle
    /// Version the user dismissed the banner for.
    private(set) var dismissedVersion: String?

    static let releasesPage = URL(string: "https://github.com/Emanschi/aniworld-ios/releases")!
    private static let apiURL = URL(string: "https://api.github.com/repos/Emanschi/aniworld-ios/releases/latest")!
    private static let throttle: TimeInterval = 6 * 60 * 60

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let lastCheckKey = "updates.lastCheck"
    @ObservationIgnored private let cacheKey = "updates.cachedRelease"
    @ObservationIgnored private let notifiedKey = "updates.notifiedVersion"
    @ObservationIgnored private let dismissedKey = "updates.dismissedVersion"

    private init() {
        dismissedVersion = defaults.string(forKey: dismissedKey)
        if let cached = loadCache() { apply(cached) }
    }

    /// True when the banner should be shown.
    var shouldShowBanner: Bool {
        guard let update = availableUpdate else { return false }
        return update.version != dismissedVersion
    }

    func dismissBanner() {
        guard let update = availableUpdate else { return }
        dismissedVersion = update.version
        defaults.set(update.version, forKey: dismissedKey)
    }

    /// Checks GitHub (throttled to every 6 h unless `force`).
    func check(force: Bool = false) async {
        if state == .checking { return }
        let last: Date? = defaults.object(forKey: lastCheckKey) as? Date
        if !force, let last = last, Date().timeIntervalSince(last) < Self.throttle {
            if let cached = loadCache() {
                apply(cached)
            } else if state == .idle {
                state = .unavailable
            }
            return
        }
        state = .checking
        var request = URLRequest(url: Self.apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AniWorld-iOS/\(AppVersion.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = fallbackState()
                return
            }
            defaults.set(Date(), forKey: lastCheckKey)
            guard http.statusCode == 200 else {
                // 404 while the repo is private, 403 on rate limit: stay silent.
                state = fallbackState()
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            if release.draft == true || release.prerelease == true {
                state = fallbackState()
                return
            }
            var version: String = release.tag_name.trimmingCharacters(in: .whitespaces)
            if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
            let cached = CachedRelease(
                version: version,
                name: release.name ?? "AniWorld \(version)",
                body: release.body ?? "",
                url: release.html_url,
                publishedAt: Self.parseDate(release.published_at)
            )
            saveCache(cached)
            apply(cached)
        } catch {
            state = fallbackState()
        }
    }

    /// Runs `check()` and posts a local notification once per new version.
    /// Called from the background refresh task.
    func checkAndNotify() async {
        await check()
        guard let update = availableUpdate else { return }
        if defaults.string(forKey: notifiedKey) == update.version { return }

        let center = UNUserNotificationCenter.current()
        let settings: UNNotificationSettings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Update verfügbar: AniWorld \(update.version)"
        content.body = "Tippe, um die neue Version herunterzuladen."
        content.sound = .default
        content.userInfo = ["url": update.url.absoluteString]
        let request = UNNotificationRequest(identifier: "app-update-\(update.version)", content: content, trigger: nil)
        do {
            try await center.add(request)
            defaults.set(update.version, forKey: notifiedKey)
        } catch {
            // Try again on the next background run.
        }
    }

    // MARK: Helpers

    private func fallbackState() -> State {
        availableUpdate != nil ? .updateAvailable : .unavailable
    }

    private func apply(_ release: CachedRelease) {
        guard SemanticVersion.isNewer(release.version, than: AppVersion.version),
              let url = URL(string: release.url) else {
            availableUpdate = nil
            state = .upToDate
            return
        }
        availableUpdate = AppUpdate(
            version: release.version, name: release.name, notes: release.body,
            url: url, publishedAt: release.publishedAt
        )
        state = .updateAvailable
    }

    private func loadCache() -> CachedRelease? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(CachedRelease.self, from: data)
    }

    private func saveCache(_ release: CachedRelease) {
        if let data = try? JSONEncoder().encode(release) { defaults.set(data, forKey: cacheKey) }
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
}

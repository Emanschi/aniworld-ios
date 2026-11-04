import Foundation

/// Lokaler Stand je Serie: bekannte Staffeln und Anzahl der Folgen.
/// Liegt als JSON in Application Support und wird bewusst NICHT per iCloud synchronisiert.
struct EpisodeSnapshotEntry: Codable, Equatable, Sendable {
    /// Staffelnummer (als String, 0 = Filme) -> Anzahl Folgen. `-1` = Staffel bekannt, Anzahl nicht erfasst.
    var counts: [String: Int]
    var checkedAt: Date
}

final class EpisodeSnapshotStore {
    private(set) var entries: [String: EpisodeSnapshotEntry] = [:]
    private let fileURL: URL?

    init(fileURL: URL? = EpisodeSnapshotStore.defaultFileURL()) {
        self.fileURL = fileURL
        load()
    }

    static func defaultFileURL() -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        return base.appendingPathComponent("episode-watch.json")
    }

    func entry(for slug: String) -> EpisodeSnapshotEntry? { entries[slug] }

    func set(_ entry: EpisodeSnapshotEntry, for slug: String) { entries[slug] = entry }

    /// Entfernt Serien, die keine Favoriten mehr sind.
    func prune(keeping slugs: Set<String>) {
        entries = entries.filter { slugs.contains($0.key) }
    }

    func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: EpisodeSnapshotEntry].self, from: data) else { return }
        entries = decoded
    }
}

import Foundation
import AniworldKit

/// A copy of the library (and statistics) taken right before sync data was replaced or removed.
struct LibraryBackup: Codable, Equatable, Sendable {
    var createdAt: Date
    /// Why the backup was made (e.g. "Zusammenführen").
    var reason: String
    var library: LibraryState
    var stats: StatsState
}

/// Writes `library-backup-<date>.json` files to a directory (Application Support by default) and
/// keeps the newest few.
struct LibraryBackupStore: Sendable {
    static let keepCount = 5

    var directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// Application Support (same place as `library.json`).
    static func standard() -> LibraryBackupStore? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        return LibraryBackupStore(directory: base)
    }

    private static let prefix = "library-backup-"

    private func fileName(for date: Date, suffix: String = "") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return Self.prefix + f.string(from: date) + suffix + ".json"
    }

    /// Writes a backup and prunes old ones. Returns the file URL.
    @discardableResult
    func write(_ backup: LibraryBackup) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent(fileName(for: backup.createdAt))
        // Two backups within the same second must not overwrite each other ("_1" sorts after ".json").
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent(fileName(for: backup.createdAt, suffix: "_\(n)"))
            n += 1
        }
        let data = try JSONEncoder().encode(backup)
        try data.write(to: url, options: [.atomic])
        prune()
        return url
    }

    /// Backup files, newest first (the date is part of the file name).
    func files() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix(Self.prefix) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// The newest readable backup.
    func latest() -> LibraryBackup? {
        let decoder = JSONDecoder()
        for url in files() {
            if let data = try? Data(contentsOf: url), let backup = try? decoder.decode(LibraryBackup.self, from: data) {
                return backup
            }
        }
        return nil
    }

    func prune() {
        for url in files().dropFirst(Self.keepCount) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

import Foundation

/// A device that wrote a snapshot into the sync folder.
struct SyncDevice: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var writtenAt: Date
}

enum SyncError: LocalizedError {
    case folderUnavailable
    case folderDownloading

    var errorDescription: String? {
        switch self {
        case .folderUnavailable: "Der gewählte Ordner ist nicht mehr erreichbar. Bitte wähle ihn erneut."
        case .folderDownloading: "Der Sync-Ordner wird noch aus iCloud geladen."
        }
    }
}

/// All blocking file IO of the sync. Call these from a background task, never from the main actor.
enum SyncFolderIO {
    static let folderName = ".aniworld-sync"

    struct ReadResult: Sendable {
        var snapshots: [SyncSnapshot] = []
        /// Files that are still iCloud placeholders (download was requested).
        var pendingDownloads = 0
    }

    /// `<picked>/.aniworld-sync/devices`, created if needed. Caller must hold security-scoped access.
    static func devicesDirectory(for picked: URL) throws -> URL {
        let fm = FileManager.default
        let root: URL
        if picked.lastPathComponent == folderName {
            root = picked
        } else {
            root = picked.appendingPathComponent(folderName, isDirectory: true)
            // A not-yet-downloaded folder shows up as ".aniworld-sync.icloud": don't shadow it.
            let placeholder = picked.appendingPathComponent("." + folderName + ".icloud")
            if !fm.fileExists(atPath: root.path), fm.fileExists(atPath: placeholder.path) {
                try? fm.startDownloadingUbiquitousItem(at: root)
                throw SyncError.folderDownloading
            }
        }
        let devices = root.appendingPathComponent("devices", isDirectory: true)
        try fm.createDirectory(at: devices, withIntermediateDirectories: true)
        return devices
    }

    /// Reads the snapshots of all other devices.
    static func readRemote(picked: URL, ownDeviceID: String) throws -> ReadResult {
        let accessing = picked.startAccessingSecurityScopedResource()
        defer { if accessing { picked.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let dir = try devicesDirectory(for: picked)
        let urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])
        var result = ReadResult()
        let decoder = JSONDecoder()
        let ownFile = ownDeviceID + ".json"

        for url in urls {
            let name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                // Placeholder: ".<real name>.icloud"
                let realName = String(name.dropFirst().dropLast(".icloud".count))
                guard realName.hasSuffix(".json"), realName != ownFile else { continue }
                let realURL = dir.appendingPathComponent(realName)
                try? fm.startDownloadingUbiquitousItem(at: realURL)
                result.pendingDownloads += 1
                continue
            }
            guard !name.hasPrefix("."), name.hasSuffix(".json"), name != ownFile else { continue }

            var coordinationError: NSError?
            var data: Data?
            NSFileCoordinator(filePresenter: nil).coordinate(
                readingItemAt: url, options: [], error: &coordinationError
            ) { readURL in
                data = try? Data(contentsOf: readURL)
            }
            guard let data, let snapshot = try? decoder.decode(SyncSnapshot.self, from: data) else { continue }
            // Files written by a newer schema are ignored rather than half-understood.
            guard snapshot.schemaVersion <= SyncSnapshot.currentSchemaVersion,
                  snapshot.deviceID != ownDeviceID else { continue }
            result.snapshots.append(snapshot)
        }
        return result
    }

    /// Writes this device's snapshot (atomic, coordinated).
    static func write(_ snapshot: SyncSnapshot, picked: URL) throws {
        let accessing = picked.startAccessingSecurityScopedResource()
        defer { if accessing { picked.stopAccessingSecurityScopedResource() } }

        let dir = try devicesDirectory(for: picked)
        let target = dir.appendingPathComponent(snapshot.deviceID + ".json")
        let data = try JSONEncoder().encode(snapshot)

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: target, options: .forReplacing, error: &coordinationError
        ) { writeURL in
            do {
                try data.write(to: writeURL, options: [.atomic])
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}

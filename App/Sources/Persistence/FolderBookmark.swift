import Foundation

/// Persists a bookmark of the folder the user picked in the document picker.
enum FolderBookmark {
    private static let key = "sync.folderBookmark"

    static var isStored: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    /// Stores a bookmark for `url` (a URL returned by the document picker).
    static func save(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Resolves the stored bookmark; refreshes it when stale. Returns nil if none/unresolvable.
    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { try? save(url) }
        return url
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

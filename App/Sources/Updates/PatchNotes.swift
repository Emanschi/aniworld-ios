import SwiftUI

/// One released version with its user-facing notes (App/Resources/PatchNotes.json).
struct PatchNoteEntry: Codable, Identifiable, Hashable {
    let version: String
    let date: String
    let notes: [String]

    var id: String { version }

    /// "2026-11-04" -> "4. November 2026"
    var formattedDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let parsed: Date = parser.date(from: date) else { return date }
        let out = DateFormatter()
        out.locale = Locale(identifier: "de_DE")
        out.dateStyle = .long
        out.timeStyle = .none
        return out.string(from: parsed)
    }
}

/// Wrapper so a list of entries can drive `.sheet(item:)`.
struct PatchNotesPayload: Identifiable {
    let id = UUID()
    let entries: [PatchNoteEntry]
}

enum SemanticVersion {
    /// Numeric component-wise comparison ("0.10.0" > "0.9.1"). Missing parts count as 0.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a: [Int] = components(lhs)
        let b: [Int] = components(rhs)
        let count: Int = max(a.count, b.count)
        for index in 0..<count {
            let x: Int = index < a.count ? a[index] : 0
            let y: Int = index < b.count ? b[index] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func components(_ version: String) -> [Int] {
        var text: String = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // Drop pre-release / build suffixes ("1.2.3-beta+4").
        if let cut = text.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            text = String(text[text.startIndex..<cut])
        }
        return text.split(separator: ".").map { (part: Substring) -> Int in
            Int(part.filter { $0.isNumber }) ?? 0
        }
    }
}

enum AppVersion {
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }
}

/// Loads the bundled notes and decides whether to show them after an update.
enum PatchNotesStore {
    private static let lastBuildKey = "patchnotes.lastSeenBuild"
    private static let lastVersionKey = "patchnotes.lastSeenVersion"

    static func loadAll() -> [PatchNoteEntry] {
        guard let url = Bundle.main.url(forResource: "PatchNotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([PatchNoteEntry].self, from: data)
        else { return [] }
        return entries
    }

    private static let seenNotesKey = "patchnotes.seenNotes"

    /// Returns the notes not seen yet (only the new lines, grouped by version) and marks all as seen.
    /// Works per note instead of per build, so CI builds without new notes show nothing.
    /// Fresh install (nothing stored) -> marks everything as seen and returns nil.
    @MainActor
    static func consumePendingNotes() -> [PatchNoteEntry]? {
        let defaults = UserDefaults.standard
        let all: [PatchNoteEntry] = loadAll()
        let keys: [String] = all.flatMap { (entry: PatchNoteEntry) -> [String] in
            entry.notes.map { (note: String) -> String in entry.version + "|" + note }
        }
        // Installs that already used the build-based variant count as "not fresh".
        let wasInstalled: Bool = defaults.stringArray(forKey: seenNotesKey) != nil
            || defaults.string(forKey: lastBuildKey) != nil
            || hasExistingLibrary()
        let seen: Set<String> = Set(defaults.stringArray(forKey: seenNotesKey) ?? [])
        defaults.set(Array(seen.union(keys)), forKey: seenNotesKey)
        defaults.set(AppVersion.build, forKey: lastBuildKey)
        defaults.set(AppVersion.version, forKey: lastVersionKey)
        guard wasInstalled else { return nil }

        var result: [PatchNoteEntry] = []
        for entry in all {
            let fresh: [String] = entry.notes.filter { (note: String) -> Bool in
                !seen.contains(entry.version + "|" + note)
            }
            if !fresh.isEmpty {
                result.append(PatchNoteEntry(version: entry.version, date: entry.date, notes: fresh))
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Updates from versions before the patch notes existed still have a library file.
    @MainActor
    private static func hasExistingLibrary() -> Bool {
        guard let url = LibraryStore.defaultFileURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

// MARK: Views

private struct PatchNoteCard: View {
    let entry: PatchNoteEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Version \(entry.version)")
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(.white)
                Spacer()
                Text(entry.formattedDate)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(entry.notes, id: \.self) { (note: String) in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 7, height: 7)
                        .padding(.top, 7)
                    Text(note)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
    }
}

/// Popup shown once after an update.
struct PatchNotesSheet: View {
    let entries: [PatchNoteEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.accentGradient)
                    Text("Was ist neu")
                        .font(AppFont.display(30))
                        .foregroundStyle(.white)
                    if let first = entries.first {
                        Text("AniWorld \(first.version)")
                            .font(AppFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, 32)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(entries) { (entry: PatchNoteEntry) in
                            PatchNoteCard(entry: entry)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Weiter").frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
        }
        .presentationDetents([.large])
    }
}

/// Full list, reachable from the settings.
struct PatchNotesListView: View {
    private let entries: [PatchNoteEntry] = PatchNotesStore.loadAll()

    var body: some View {
        ZStack {
            AppBackground()
            if entries.isEmpty {
                Text("Keine Patchnotes vorhanden.")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(entries) { (entry: PatchNoteEntry) in
                            PatchNoteCard(entry: entry)
                        }
                    }
                    .padding(Theme.screenPadding)
                }
            }
        }
        .navigationTitle("Patchnotes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

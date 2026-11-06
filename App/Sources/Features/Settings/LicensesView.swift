import SwiftUI

/// One component whose license obliges us to show a notice in the app.
/// Keep this list in sync with THIRD_PARTY_NOTICES.md (see AGENTS.md).
struct LicenseItem: Identifiable, Hashable {
    var name: String
    var role: String
    var copyright: String
    var license: String
    var url: URL
    /// Bundled license text in App/Resources/Licenses (without ".txt").
    var textResource: String

    var id: String { name }
}

enum LicenseCatalog {
    static let sourceURL = URL(string: "https://github.com/Emanschi/aniworld-ios")!

    static let items: [LicenseItem] = [
        LicenseItem(
            name: "AniWorld für iOS",
            role: "Diese App",
            copyright: "Copyright © 2026 Emanschi und Mitwirkende",
            license: "GNU General Public License v3.0 oder später",
            url: sourceURL,
            textResource: "GPL-3.0"
        ),
        LicenseItem(
            name: "aniworld-cli",
            role: "Grundlage für Suche, Seiten-Parser, Hoster-Extraktoren und Testdaten",
            copyright: "Copyright © dxmoc",
            license: "GNU General Public License v3.0 oder später",
            url: URL(string: "https://github.com/dxmoc/aniworld-cli")!,
            textResource: "GPL-3.0"
        ),
        LicenseItem(
            name: "SwiftSoup",
            role: "HTML-Parser",
            copyright: "Copyright © 2009–2025 Jonathan Hedley (jsoup)\nCopyright © 2016–2025 Nabil Chatbi (Swift-Port)",
            license: "MIT License",
            url: URL(string: "https://github.com/scinfu/SwiftSoup")!,
            textResource: "SwiftSoup-MIT"
        ),
    ]

    static func text(for item: LicenseItem) -> String? {
        let url = Bundle.main.url(forResource: item.textResource, withExtension: "txt")
            ?? Bundle.main.url(forResource: item.textResource, withExtension: "txt", subdirectory: "Licenses")
        guard let url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// "Lizenzen & rechtliche Hinweise": the notices GPL-3.0 §5(d) and the MIT license require.
struct LicensesView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AniWorld für iOS")
                        .font(.headline)
                    Text("Copyright © 2026 Emanschi und Mitwirkende")
                    Text("Dieses Programm ist freie Software: Du kannst es unter den Bedingungen der GNU General Public License, Version 3 oder (nach deiner Wahl) jeder späteren Version, weitergeben und/oder verändern.")
                    Text("Es wird OHNE JEDE GEWÄHRLEISTUNG bereitgestellt, sogar ohne die implizite Gewährleistung der MARKTREIFE oder der EIGNUNG FÜR EINEN BESTIMMTEN ZWECK. Details stehen in der GNU General Public License.")
                }
                .font(.footnote)
                .padding(.vertical, 4)
                Link(destination: LicenseCatalog.sourceURL) {
                    Label("Quellcode dieser App", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } header: {
                Text("Lizenz")
            }

            Section {
                ForEach(LicenseCatalog.items) { item in
                    NavigationLink {
                        LicenseDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.body.weight(.semibold))
                            Text(item.license).font(.caption).foregroundStyle(Theme.accent)
                            Text(item.role).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Verwendete Software")
            }

            Section {
                Text("Diese App hostet, speichert und verbreitet keine Inhalte. Sie ruft ausschließlich öffentlich erreichbare Seiten von aniworld.to und der dort verlinkten Hoster auf. Für die Inhalte sind allein die jeweiligen Anbieter verantwortlich. Die Nutzung erfolgt auf eigene Verantwortung und unter Beachtung des geltenden Rechts.")
                    .font(.footnote)
                Text("Diese App steht in keiner Verbindung zu aniworld.to, den Hostern oder Apple. Alle genannten Marken gehören ihren jeweiligen Inhabern.")
                    .font(.footnote)
            } header: {
                Text("Haftungsausschluss")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Lizenzen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseDetailView: View {
    let item: LicenseItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.name).font(.title3.weight(.bold))
                Text(item.copyright).font(.footnote)
                Link(destination: item.url) {
                    Label(item.url.absoluteString, systemImage: "link")
                        .font(.footnote)
                }
                Divider()
                if let text = LicenseCatalog.text(for: item) {
                    Text(text)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text("Der Lizenztext (\(item.license)) ist unter dem Link oben abrufbar.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppBackground())
        .navigationTitle(item.license)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Lizenzen") {
    NavigationStack { LicensesView() }
        .preferredColorScheme(.dark)
}

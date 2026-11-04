import SwiftUI

/// Lists the user's own intro/outro times; swipe to delete.
struct CustomSkipListView: View {
    @Environment(LibraryStore.self) private var library

    private func seriesName(_ skip: CustomSkip) -> String {
        library.knownTitle(forSlug: skip.seriesSlug) ?? skip.seriesSlug
    }

    private func scopeText(_ skip: CustomSkip) -> String {
        let season = skip.season == 0 ? "Filme" : "Staffel \(skip.season)"
        if let episode = skip.episode { return "\(season) · Folge \(episode)" }
        return "\(season) · ganze Staffel"
    }

    private func timesText(_ skip: CustomSkip) -> String {
        var parts: [String] = []
        if skip.hasIntro, let s = skip.introStart, let e = skip.introEnd {
            parts.append("Intro \(PlayerFormat.time(s)) – \(PlayerFormat.time(e))")
        }
        if skip.hasOutro, let s = skip.outroStart, let e = skip.outroEnd {
            parts.append("Outro \(PlayerFormat.time(s)) – \(PlayerFormat.time(e))")
        }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        let list = library.customSkipList
        List {
            if list.isEmpty {
                Section {
                    Text("Noch keine eigenen Intro-Zeiten. Du kannst sie im Player über „Intro festlegen“ oder „Intro bearbeiten“ anlegen.")
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Section {
                    ForEach(list) { skip in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(seriesName(skip))
                                .font(.system(.body, design: .rounded).weight(.semibold))
                            Text(scopeText(skip))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                            Text(timesText(skip))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        let keys = offsets.map { list[$0].key }
                        for key in keys { library.removeCustomSkip(key: key) }
                    }
                } footer: {
                    Text("Eigene Zeiten haben Vorrang vor der mitgelieferten Datenbank. Wischen zum Löschen.")
                }
            }

            Section {
                Button("„Nicht mehr fragen“ zurücksetzen") {
                    library.resetMutedSkipPrompts()
                }
                .disabled(library.mutedSkipPromptSlugs.isEmpty)
            } footer: {
                Text("Für \(library.mutedSkipPromptSlugs.count) Serien wird der Hinweis „Kein Intro hinterlegt“ nicht mehr angezeigt.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Eigene Intro-Zeiten")
        .navigationBarTitleDisplayMode(.inline)
    }
}

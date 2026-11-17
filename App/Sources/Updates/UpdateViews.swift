import SwiftUI

/// Insert into the settings `Form`.
struct UpdatesSettingsSection: View {
    @State private var checker = AppUpdateChecker.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("App & Updates") {
            LabeledContent("Installierte Version", value: "\(AppVersion.version) (\(AppVersion.build))")

            Button {
                Task { await checker.check(force: true) }
            } label: {
                HStack {
                    Text("Nach Updates suchen")
                    Spacer()
                    if checker.state == .checking { ProgressView() }
                }
            }
            .disabled(checker.state == .checking)

            statusRow

            Link("Alle Versionen auf GitHub", destination: AppUpdateChecker.releasesPage)

            NavigationLink("Patchnotes anzeigen") {
                PatchNotesListView()
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch checker.state {
        case .upToDate:
            Label("Du hast die neueste Version.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
        case .updateAvailable:
            if let update = checker.availableUpdate {
                Button {
                    openURL(update.url)
                } label: {
                    Label("Version \(update.version) verfügbar – zum Download", systemImage: "arrow.down.circle.fill")
                }
            }
        case .unavailable:
            Text("Update-Informationen sind gerade nicht verfügbar.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        case .idle, .checking:
            EmptyView()
        }
    }
}

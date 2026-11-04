import SwiftUI

/// Dismissible card shown when a newer version exists.
struct UpdateBannerView: View {
    let update: AppUpdate
    let onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Theme.accentGradient)
                    .font(.title3)
                Text("Neue Version \(update.version) verfügbar")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            if !update.excerpt.isEmpty {
                Text(update.excerpt)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(5)
            }
            HStack(spacing: 10) {
                Button {
                    openURL(update.url)
                } label: {
                    Text("Zum Download")
                }
                .buttonStyle(AccentButtonStyle())
                Button("Später", action: onDismiss)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Theme.surfaceHigh)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        .padding(.horizontal, Theme.screenPadding)
    }
}

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

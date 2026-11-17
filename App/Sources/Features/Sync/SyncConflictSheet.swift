import SwiftUI
import AniworldKit

/// Shown at app start (and after a sync) when merging with iCloud would remove or replace local data.
/// Nothing is applied until one of the three buttons is tapped.
struct SyncConflictSheet: View {
    @Environment(LibrarySyncService.self) private var sync
    let info: SyncConflictInfo

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "exclamationmark.icloud.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.accentGradient)
                        .padding(.top, 24)
                    Text("Gespeicherte Stände unterscheiden sich")
                        .font(AppFont.display(24))
                        .multilineTextAlignment(.center)
                    Text("Dieses Gerät und iCloud haben unterschiedliche Daten. Beim Zusammenführen würde Folgendes von diesem Gerät entfernt oder zurückgesetzt:")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    lossesCard

                    summaryCard(title: "Dieses Gerät", systemImage: "iphone", summary: info.local)
                    summaryCard(title: "iCloud", systemImage: "icloud", summary: info.remote)

                    Text("Vor jeder Auswahl wird eine Sicherung dieses Geräts angelegt. Du kannst sie später in den Einstellungen unter „Synchronisierung“ wiederherstellen.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 10) {
                        Button {
                            sync.resolveConflict(.merge)
                        } label: {
                            Text("Zusammenführen (empfohlen)").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccentButtonStyle())

                        choiceButton("Dieses Gerät behalten") { sync.resolveConflict(.keepLocal) }
                        choiceButton("iCloud übernehmen") { sync.resolveConflict(.adoptRemote) }
                    }
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, Theme.screenPadding)
            }
        }
        .interactiveDismissDisabled(true)
    }

    private func choiceButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
        }
        .buttonStyle(.plain)
    }

    // MARK: Parts

    private var lossesCard: some View {
        let l = info.losses
        var lines: [String] = []
        if l.favorites > 0 { lines.append(count(l.favorites, "Favorit", "Favoriten") + " entfernt") }
        if l.history > 0 { lines.append(count(l.history, "Verlaufseintrag", "Verlaufseinträge") + " entfernt") }
        if l.progressRemoved > 0 { lines.append("Fortschritt von " + count(l.progressRemoved, "Folge", "Folgen") + " entfernt") }
        if l.progressBackwards > 0 { lines.append("Fortschritt von " + count(l.progressBackwards, "Folge", "Folgen") + " zurückgesetzt") }
        if l.customSkips > 0 { lines.append(count(l.customSkips, "eigene Intro-Zeit", "eigene Intro-Zeiten") + " entfernt") }
        if l.statsSessions > 0 { lines.append(count(l.statsSessions, "Statistik-Sitzung", "Statistik-Sitzungen") + " entfernt") }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Color.red)
                    Text(line).font(.subheadline)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
    }

    private func summaryCard(title: String, systemImage: String, summary: SyncStateSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(.headline, design: .rounded))
            row("Favoriten", summary.favorites)
            row("Verlauf", summary.history)
            row("Folgen mit Fortschritt", summary.episodesWithProgress)
            row("Eigene Intro-Zeiten", summary.customSkips)
            row("Statistik-Sitzungen", summary.statsSessions)
            HStack(alignment: .top) {
                Text("Zuletzt geändert").foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(summary.lastChanged.map { Self.dateFormatter.string(from: $0) } ?? "–")
                    if let name = summary.deviceName, !name.isEmpty {
                        Text(name).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
    }

    private func row(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("\(value)")
        }
        .font(.subheadline)
    }

    private func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

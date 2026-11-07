import SwiftUI

/// Close button, titles and the right-hand tools (AirPlay, PiP, options).
struct PlayerTopBar: View {
    let vm: PlayerViewModel
    /// False while loading: only the close button and titles are shown.
    var showsTools: Bool = true
    let onOptions: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PlayerIconButton(systemName: "chevron.down", label: "Schließen") {
                vm.close()
            }
            titles
            Spacer(minLength: 8)
            if showsTools {
                tools
            }
        }
        .foregroundStyle(.white)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(vm.series.title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .lineLimit(1)
            Text(episodeLine)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(0.6), radius: 3)
    }

    private var episodeLine: String {
        vm.episode.title.isEmpty ? vm.episode.code : "\(vm.episode.code) · \(vm.episode.title)"
    }

    private var tools: some View {
        HStack(spacing: 10) {
            CastButton(vm: vm)
            AirPlayButton()
                .frame(width: 28, height: 28)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
            if vm.pip.isPossible {
                PlayerIconButton(
                    systemName: vm.pip.isActive ? "pip.exit" : "pip.enter",
                    label: "Bild-in-Bild"
                ) {
                    vm.pip.toggle()
                }
            }
            // Always available: besides language/hoster it holds the intro/outro editor.
            PlayerIconButton(systemName: "ellipsis", label: "Optionen", action: onOptions)
        }
    }
}

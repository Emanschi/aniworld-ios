import SwiftUI
import AniworldKit

/// Side panels that slide in from the right (speed, episodes, language & hoster).
enum PlayerPanel: Hashable {
    case speed
    case episodes
    case options
}

/// Dimmed backdrop plus the panel for the selected kind.
struct PlayerPanelHost: View {
    let panel: PlayerPanel
    let vm: PlayerViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
                .transition(.opacity)
            panelBody
                .frame(width: 360)
                .frame(maxHeight: .infinity)
                .background(Theme.surface.opacity(0.97).ignoresSafeArea())
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                        .ignoresSafeArea()
                }
                .transition(.move(edge: .trailing))
        }
    }

    @ViewBuilder
    private var panelBody: some View {
        switch panel {
        case .speed:
            PlayerSpeedPanel(vm: vm, onClose: onClose)
        case .episodes:
            PlayerEpisodePanel(vm: vm, onClose: onClose)
        case .options:
            PlayerOptionsPanel(vm: vm, onClose: onClose)
        }
    }
}

/// Title row with a close button, shared by all panels.
struct PlayerPanelHeader: View {
    let title: String
    var subtitle: String?
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.sectionTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surfaceHigh))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Schließen")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

/// One selectable row with an optional checkmark.
struct PlayerChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(selected ? .bold : .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.18) : Theme.surfaceHigh.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.7) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

import SwiftUI

/// Small dismissible card shown when no intro time is known for the episode.
/// Sits bottom-left (above the scrubber while the controls are shown) and hides itself after ~10 s.
struct PlayerIntroPrompt: View {
    let vm: PlayerViewModel
    let controlsShown: Bool
    let onDefine: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 0) {
                card
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .padding(.bottom, controlsShown ? 112 : 28)
            .animation(.easeInOut(duration: 0.25), value: controlsShown)
        }
        .transition(.opacity)
        .task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if Task.isCancelled { return }
            vm.dismissIntroPrompt()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "scissors")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Kein Intro hinterlegt")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Button {
                    vm.dismissIntroPrompt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Schließen")
            }
            HStack(spacing: 12) {
                Button {
                    onDefine()
                } label: {
                    Text("Intro festlegen")
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                Button {
                    vm.muteIntroPromptForSeries()
                } label: {
                    Text("Für diese Serie nicht mehr fragen")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: 330, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

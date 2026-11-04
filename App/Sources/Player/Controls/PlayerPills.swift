import SwiftUI

/// "Intro überspringen" / "Nächste Folge" pills, visible even while the controls are hidden.
struct PlayerPills: View {
    let vm: PlayerViewModel
    /// Lifts the pills above the scrubber while the controls are shown.
    let controlsShown: Bool

    private var showSkipIntro: Bool {
        if vm.activeSkipSegment != nil {
            return true
        }
        // Fixed-jump fallback only when no intro time is known for this episode.
        return !vm.hasKnownIntro && vm.position < 240 && vm.duration > Double(vm.introSkipSeconds) + 120
    }

    private var skipButtonTitle: String {
        vm.activeSkipSegment?.skipType.buttonTitle ?? "Intro überspringen"
    }

    private var showNext: Bool {
        vm.hasNext && vm.countdown == nil && vm.duration > 0 && vm.duration - vm.position < 120
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if showSkipIntro {
                    pill(skipButtonTitle, systemImage: "forward.fill") { vm.skipActiveOrIntro() }
                }
                if showNext {
                    pill("Nächste Folge", systemImage: "forward.end.fill") { vm.playNext() }
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, controlsShown ? 112 : 28)
            .animation(.easeInOut(duration: 0.25), value: controlsShown)
        }
    }

    private func pill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.9), lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

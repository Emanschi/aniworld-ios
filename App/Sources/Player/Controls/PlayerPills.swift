import SwiftUI

/// "Intro überspringen" / "Nächste Folge" pills, visible even while the controls are hidden.
struct PlayerPills: View {
    /// Skip button to show (nil = none). Passed in as plain values so the parent drives the updates,
    /// independent of the controls being visible.
    let skip: SkipPill?
    let showNext: Bool
    let onSkip: () -> Void
    let onNext: () -> Void
    /// Lifts the pills above the scrubber while the controls are shown.
    let controlsShown: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let skip {
                pill(skip.title, systemImage: "forward.fill", action: onSkip)
                    .transition(.opacity)
            }
            if showNext {
                pill("Nächste Folge", systemImage: "forward.end.fill", action: onNext)
                    .transition(.opacity)
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, controlsShown ? 112 : 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.easeInOut(duration: 0.25), value: controlsShown)
        .animation(.easeInOut(duration: 0.2), value: skip)
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

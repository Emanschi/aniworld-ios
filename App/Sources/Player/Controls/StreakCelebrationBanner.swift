import SwiftUI

/// Duolingo-style banner at the top of the player when the episode just extended the daily streak.
/// Hides itself (the view model clears `streakCelebration` after a few seconds) or on tap.
struct StreakCelebrationBanner: View {
    let days: Int
    let onDismiss: () -> Void

    @State private var flameScale: CGFloat = 0.3
    @State private var flameGlow = false

    private var title: String {
        days == 1 ? "Streak gestartet!" : "Streak verlängert!"
    }

    private var subtitle: String {
        days == 1 ? "Tag 1 – schau morgen wieder eine Folge." : "\(days) Tage am Stück. Weiter so!"
    }

    var body: some View {
        VStack {
            Button(action: onDismiss) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(flameGlow ? 0.35 : 0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red],
                                                            startPoint: .top, endPoint: .bottom))
                            .scaleEffect(flameScale)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text("\(days)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1)
                        )
                )
                .shadow(color: .orange.opacity(0.35), radius: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 16)
            .padding(.top, 20)
            Spacer(minLength: 0)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(subtitle)")
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { flameScale = 1 }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { flameGlow = true }
        }
    }
}

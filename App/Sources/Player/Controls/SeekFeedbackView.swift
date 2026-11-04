import SwiftUI

/// Accumulated double-tap seek ("-10 s", "-20 s", ...) shown on the tapped half.
struct SeekBubble: Equatable {
    var side: PlayerSide
    /// Signed total in seconds.
    var total: Int
    /// Increments on every tap so the animation replays.
    var tick: Int
}

struct SeekFeedbackView: View {
    let bubble: SeekBubble?

    var body: some View {
        HStack(spacing: 0) {
            half(for: .backward)
            half(for: .forward)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func half(for side: PlayerSide) -> some View {
        ZStack {
            if let bubble, bubble.side == side {
                SeekBubbleContent(side: side, total: bubble.total)
                    .id(bubble.tick)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: bubble)
    }
}

private struct SeekBubbleContent: View {
    let side: PlayerSide
    let total: Int

    @State private var rippling = false

    private var text: String {
        let sign = total < 0 ? "\u{2212}" : "+"
        return "\(sign)\(abs(total)) s"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 150, height: 150)
            Circle()
                .strokeBorder(Theme.accent.opacity(0.8), lineWidth: 2)
                .frame(width: 150, height: 150)
                .scaleEffect(rippling ? 1.5 : 0.7)
                .opacity(rippling ? 0 : 0.8)
            VStack(spacing: 6) {
                Image(systemName: side == .forward ? "chevron.right.2" : "chevron.left.2")
                    .font(.system(size: 26, weight: .bold))
                Text(text)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { rippling = true }
        }
    }
}

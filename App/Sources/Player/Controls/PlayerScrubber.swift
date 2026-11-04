import SwiftUI

/// Custom seek bar: buffered range, played range (accent gradient), growing thumb and a
/// time bubble while dragging. Elapsed time on the left, remaining time on the right.
struct PlayerScrubber: View {
    let vm: PlayerViewModel
    let onActivity: () -> Void

    @State private var dragFraction: Double?

    private let hitHeight: CGFloat = 44

    private var isDragging: Bool { dragFraction != nil }

    private var playedFraction: Double {
        guard vm.duration > 0 else { return 0 }
        return min(max(vm.position / vm.duration, 0), 1)
    }

    private var shownFraction: Double { dragFraction ?? playedFraction }
    private var shownTime: Double { shownFraction * max(vm.duration, 0) }

    private var bufferedFraction: Double {
        guard vm.duration > 0 else { return 0 }
        return min(max(vm.bufferedPosition / vm.duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(PlayerFormat.time(shownTime))
                .frame(minWidth: 44, alignment: .trailing)
            track
            Text(PlayerFormat.remaining(position: shownTime, duration: vm.duration))
                .frame(minWidth: 52, alignment: .leading)
        }
        .font(.system(.footnote, design: .rounded).weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
    }

    private var track: some View {
        GeometryReader { geo in
            trackContent(width: geo.size.width)
        }
        .frame(height: hitHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wiedergabeposition")
        .accessibilityValue("\(PlayerFormat.time(shownTime)) von \(PlayerFormat.time(vm.duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: vm.seek(by: 10)
            case .decrement: vm.seek(by: -10)
            @unknown default: break
            }
            onActivity()
        }
    }

    private func trackContent(width: CGFloat) -> some View {
        let barHeight: CGFloat = isDragging ? 8 : 4
        let thumbSize: CGFloat = isDragging ? 22 : 12
        let playedWidth = width * CGFloat(shownFraction)
        let bubbleCenter = min(max(playedWidth, 30), max(width - 30, 30))

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(height: barHeight)
            Capsule()
                .fill(Color.white.opacity(0.38))
                .frame(width: width * CGFloat(bufferedFraction), height: barHeight)
            Capsule()
                .fill(LinearGradient(colors: [Theme.accent, Theme.accentPink],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: playedWidth, height: barHeight)
            Circle()
                .fill(Color.white)
                .frame(width: thumbSize, height: thumbSize)
                .shadow(color: Theme.accent.opacity(isDragging ? 0.7 : 0.0), radius: 8)
                .offset(x: playedWidth - thumbSize / 2)
            if isDragging {
                timeBubble
                    .offset(x: bubbleCenter - 30, y: -38)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: hitHeight)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .gesture(dragGesture(width: width))
    }

    private var timeBubble: some View {
        Text(PlayerFormat.time(shownTime))
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 60, height: 28)
            .background(Capsule().fill(Theme.surfaceHigh))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1))
    }

    private func fraction(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard vm.duration > 0 else { return }
                let f = fraction(for: value.location.x, width: width)
                if dragFraction == nil {
                    vm.beginScrubbing()
                    onActivity()
                }
                dragFraction = f
                vm.scrub(to: f * vm.duration)
            }
            .onEnded { value in
                guard vm.duration > 0 else {
                    dragFraction = nil
                    return
                }
                let f = fraction(for: value.location.x, width: width)
                vm.endScrubbing(at: f * vm.duration)
                dragFraction = nil
                onActivity()
            }
    }
}

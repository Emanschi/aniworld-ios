import SwiftUI

/// Full-screen touch layer below the controls:
/// - Single tap toggles the controls
/// - Double tap on the left/right third seeks 10s, middle toggles play/pause
/// - Vertical swipe on left half adjusts brightness, on right half adjusts volume (Netflix style)
struct PlayerGestureLayer: View {
    let onTap: () -> Void
    let onDoubleTap: (PlayerSide) -> Void
    var onVerticalSwipe: ((_ isLeft: Bool, _ deltaFraction: Double) -> Void)? = nil
    var onSwipeEnd: (() -> Void)? = nil

    @State private var dragStarted = false
    @State private var ignoreNextTapUntil: Date = .distantPast

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                zone(.backward)
                zone(.center)
                zone(.forward)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        dragStarted = true
                        ignoreNextTapUntil = Date().addingTimeInterval(0.3)
                        let isLeft = value.startLocation.x < geo.size.width / 2
                        let deltaY = -(value.translation.height)
                        let fractionDelta = Double(deltaY / max(geo.size.height * 0.65, 100))
                        onVerticalSwipe?(isLeft, fractionDelta)
                    }
                    .onEnded { _ in
                        dragStarted = false
                        ignoreNextTapUntil = Date().addingTimeInterval(0.3)
                        onSwipeEnd?()
                    }
            )
        }
        .ignoresSafeArea()
    }

    private func zone(_ side: PlayerSide) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2)
                    .onEnded {
                        guard Date() > ignoreNextTapUntil else { return }
                        onDoubleTap(side)
                    }
                    .exclusively(before: TapGesture(count: 1).onEnded {
                        guard Date() > ignoreNextTapUntil else { return }
                        onTap()
                    })
            )
    }
}

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

    /// nil = not decided yet for the current drag; true = vertical swipe, false = ignore (horizontal).
    @State private var dragIsVertical: Bool?
    @State private var dragOrigin: CGPoint?
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
                        ignoreNextTapUntil = Date().addingTimeInterval(0.3)
                        // A new drag (SwiftUI does not call onEnded for cancelled gestures).
                        if dragOrigin != value.startLocation {
                            if dragIsVertical == true { onSwipeEnd?() }
                            dragOrigin = value.startLocation
                            dragIsVertical = nil
                        }
                        // Decide the direction once, at the start of the drag.
                        if dragIsVertical == nil {
                            dragIsVertical = abs(value.translation.height) > abs(value.translation.width)
                        }
                        guard dragIsVertical == true else { return }
                        let isLeft = value.startLocation.x < geo.size.width / 2
                        let deltaY = -(value.translation.height)
                        let fractionDelta = Double(deltaY / max(geo.size.height * 0.65, 100))
                        onVerticalSwipe?(isLeft, fractionDelta)
                    }
                    .onEnded { _ in
                        let wasVertical = dragIsVertical == true
                        dragIsVertical = nil
                        dragOrigin = nil
                        ignoreNextTapUntil = Date().addingTimeInterval(0.3)
                        if wasVertical { onSwipeEnd?() }
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

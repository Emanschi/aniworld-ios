import SwiftUI

/// Full-screen touch layer below the controls: single tap toggles the controls,
/// double tap on the left/right third seeks, double tap in the middle toggles play/pause.
struct PlayerGestureLayer: View {
    let onTap: () -> Void
    let onDoubleTap: (PlayerSide) -> Void

    var body: some View {
        HStack(spacing: 0) {
            zone(.backward)
            zone(.center)
            zone(.forward)
        }
        .ignoresSafeArea()
    }

    private func zone(_ side: PlayerSide) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2)
                    .onEnded { onDoubleTap(side) }
                    .exclusively(before: TapGesture(count: 1).onEnded { onTap() })
            )
    }
}

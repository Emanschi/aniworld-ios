import SwiftUI

/// The full controls layer: scrims, top bar, center controls, scrubber and action row.
/// The empty areas are not hit-testable, so taps reach the gesture layer below.
struct PlayerControlsOverlay: View {
    let vm: PlayerViewModel
    let onPanel: (PlayerPanel) -> Void
    let onLock: () -> Void
    let onActivity: () -> Void

    var body: some View {
        ZStack {
            scrims
            PlayerCenterControls(vm: vm, onActivity: onActivity)
            VStack(spacing: 0) {
                PlayerTopBar(vm: vm, showsTools: true) {
                    onPanel(.options)
                }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    PlayerScrubber(vm: vm, onActivity: onActivity)
                    PlayerBottomActions(vm: vm, onPanel: onPanel, onLock: onLock, onActivity: onActivity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }

    private var scrims: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color.black.opacity(0.8), Color.black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
            Spacer(minLength: 0)
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

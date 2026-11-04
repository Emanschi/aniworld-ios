import SwiftUI

/// Large play/pause button with ±10 s buttons; a spinner replaces play/pause while buffering.
struct PlayerCenterControls: View {
    let vm: PlayerViewModel
    let onActivity: () -> Void

    var body: some View {
        HStack(spacing: 56) {
            skipButton(systemName: "gobackward.10", label: "10 Sekunden zurück", delta: -10)
            centerButton
            skipButton(systemName: "goforward.10", label: "10 Sekunden vor", delta: 10)
        }
        .foregroundStyle(.white)
    }

    private func skipButton(systemName: String, label: String, delta: Double) -> some View {
        Button {
            vm.seek(by: delta)
            onActivity()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 34, weight: .regular))
                .frame(width: 64, height: 64)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var centerButton: some View {
        if vm.isBuffering {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.8)
                .frame(width: 84, height: 84)
        } else {
            Button {
                vm.togglePlayPause()
                onActivity()
            } label: {
                Image(systemName: vm.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 38, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.default, value: vm.isPaused)
                    .frame(width: 84, height: 84)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(vm.isPaused ? "Abspielen" : "Pause")
        }
    }
}

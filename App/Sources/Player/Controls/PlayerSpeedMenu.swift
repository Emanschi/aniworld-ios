import SwiftUI

/// Playback speed selection (checkmark on the current rate).
struct PlayerSpeedPanel: View {
    let vm: PlayerViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PlayerPanelHeader(title: "Geschwindigkeit", subtitle: nil, onClose: onClose)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(PlayerViewModel.playbackRates, id: \.self) { rate in
                        PlayerChoiceRow(
                            title: rate == 1 ? "Normal (1x)" : PlayerFormat.rate(rate),
                            selected: rate == vm.playbackRate
                        ) {
                            vm.setPlaybackRate(rate)
                            onClose()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
    }
}

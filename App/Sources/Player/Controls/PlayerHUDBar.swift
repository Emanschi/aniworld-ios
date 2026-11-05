import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit
import AniworldKit

enum PlayerHUDKind: Equatable {
    case brightness
    case volume
}

struct PlayerHUDState: Equatable {
    var kind: PlayerHUDKind
    var value: Double
}

/// Netflix-style vertical indicator pill for brightness and volume.
struct PlayerHUDBar: View {
    let state: PlayerHUDState

    private var iconName: String {
        switch state.kind {
        case .brightness:
            return state.value >= 0.5 ? "sun.max.fill" : "sun.min.fill"
        case .volume:
            if state.value <= 0.001 {
                return "speaker.slash.fill"
            } else if state.value < 0.33 {
                return "speaker.wave.1.fill"
            } else if state.value < 0.66 {
                return "speaker.wave.2.fill"
            } else {
                return "speaker.wave.3.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: 22)

            // Vertical capsule bar (Netflix style)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.black.opacity(0.65))
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accentPink],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: max(geo.size.height * CGFloat(min(max(state.value, 0), 1)), 0))
                }
            }
            .frame(width: 36, height: 150)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)

            Text("\(Int(round(min(max(state.value, 0), 1) * 100)))%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
    }
}

// MARK: - System volume bridge

@MainActor
final class HiddenMPVolumeView: MPVolumeView {
    override func layoutSubviews() {
        super.layoutSubviews()
        VolumeController.shared.scanSlider(in: self)
    }
}

@MainActor
struct SystemVolumeView: UIViewRepresentable {
    typealias UIViewType = HiddenMPVolumeView

    func makeUIView(context: Context) -> HiddenMPVolumeView {
        let view = HiddenMPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        // Kept in the hierarchy (but invisible) so programmatic changes do not pop up the system volume HUD
        // on top of our own indicator. Only the slider is needed, not the route button.
        view.alpha = 0.0001
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.showsRouteButton = false
        VolumeController.shared.scanSlider(in: view)
        return view
    }

    func updateUIView(_ uiView: HiddenMPVolumeView, context: Context) {
        VolumeController.shared.scanSlider(in: uiView)
    }
}

@MainActor
final class VolumeController {
    static let shared = VolumeController()
    private weak var volumeSlider: UISlider?

    func scanSlider(in view: UIView) {
        if let slider = view.subviews.first(where: { $0 is UISlider }) as? UISlider {
            self.volumeSlider = slider
            return
        }
        for subview in view.subviews {
            if let slider = subview as? UISlider {
                self.volumeSlider = slider
                return
            }
        }
    }

    var currentVolume: Float {
        if let slider = volumeSlider {
            return slider.value
        }
        return AVAudioSession.sharedInstance().outputVolume
    }

    func setVolume(_ volume: Float) {
        let clamped = max(0.0, min(1.0, volume))
        if let slider = volumeSlider {
            slider.setValue(clamped, animated: false)
            slider.sendActions(for: .valueChanged)
        }
    }
}

import SwiftUI
import AVFoundation

/// Netflix-style action row below the scrubber.
struct PlayerBottomActions: View {
    let vm: PlayerViewModel
    let onPanel: (PlayerPanel) -> Void
    let onLock: () -> Void
    let onActivity: () -> Void

    private var isFilled: Bool { vm.videoGravity == .resizeAspectFill }

    var body: some View {
        HStack(spacing: 22) {
            action("speedometer", "Geschwindigkeit (\(PlayerFormat.rate(vm.playbackRate)))") {
                onPanel(.speed)
            }
            action("rectangle.stack", "Folgen") {
                onPanel(.episodes)
            }
            action("captions.bubble", "Sprache & Hoster") {
                onPanel(.options)
            }
            if vm.hasNext {
                action("forward.end.fill", "Nächste Folge") {
                    vm.playNext()
                }
            }
            Spacer(minLength: 8)
            iconAction(
                isFilled ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                isFilled ? "Bild einpassen" : "Bild füllen"
            ) {
                vm.toggleVideoGravity()
                onActivity()
            }
            iconAction("lock.fill", "Steuerung sperren") {
                onLock()
            }
        }
        .foregroundStyle(.white)
    }

    private func action(_ systemName: String, _ title: String, _ handler: @escaping () -> Void) -> some View {
        Button {
            handler()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func iconAction(_ systemName: String, _ label: String, _ handler: @escaping () -> Void) -> some View {
        Button {
            handler()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

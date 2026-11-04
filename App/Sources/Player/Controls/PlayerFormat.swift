import SwiftUI

/// Formatting helpers and small shared building blocks of the player controls.
enum PlayerFormat {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func remaining(position: Double, duration: Double) -> String {
        "-" + time(max(duration - position, 0))
    }

    /// "1x", "1,5x", "0,75x"
    static func rate(_ rate: Float) -> String {
        let value = Double(rate)
        if value == value.rounded() { return "\(Int(value))x" }
        let text = String(format: "%g", value).replacingOccurrences(of: ".", with: ",")
        return text + "x"
    }
}

/// Side of the screen a gesture happened on.
enum PlayerSide: Equatable {
    case backward
    case center
    case forward
}

/// Circular material button used in the top bar and the lock overlay.
struct PlayerIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 40
    var iconSize: CGFloat = 17
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

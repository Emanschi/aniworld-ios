import SwiftUI

/// "FSK 12"-style age rating badge, colored like the German FSK labels.
struct FSKBadge: View {
    let age: Int

    private var fill: Color {
        switch age {
        case ..<6: return Color(white: 0.92)
        case 6..<12: return Color(red: 0.98, green: 0.80, blue: 0.10)
        case 12..<16: return Color(red: 0.25, green: 0.70, blue: 0.30)
        case 16..<18: return Color(red: 0.20, green: 0.45, blue: 0.85)
        default: return Color(red: 0.85, green: 0.15, blue: 0.15)
        }
    }

    private var textColor: Color {
        switch age {
        case ..<12: return Color.black.opacity(0.85)
        default: return .white
        }
    }

    var body: some View {
        Text("FSK \(age)")
            .font(.system(.caption, design: .rounded).weight(.heavy))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
            .accessibilityLabel("Freigegeben ab \(age) Jahren")
    }
}

#Preview("FSK") {
    HStack {
        ForEach([0, 6, 12, 16, 18], id: \.self) { FSKBadge(age: $0) }
    }
    .padding()
    .background(Theme.background)
}

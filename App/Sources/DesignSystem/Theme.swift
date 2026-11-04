import SwiftUI
import UIKit

/// Colors, metrics and small helpers shared by all screens.
enum Theme {
    static let accent = Color(red: 0.62, green: 0.36, blue: 1.0)
    static let accentPink = Color(red: 0.96, green: 0.32, blue: 0.62)
    static let background = Color(red: 0.045, green: 0.04, blue: 0.075)
    static let surface = Color(red: 0.10, green: 0.09, blue: 0.15)
    static let surfaceHigh = Color(red: 0.16, green: 0.14, blue: 0.23)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.40)
    static let success = Color(red: 0.35, green: 0.85, blue: 0.60)

    static let screenPadding: CGFloat = 20
    static let cardRadius: CGFloat = 14

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentPink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Deterministic gradient per title, used while (or instead of) a cover image.
    static func placeholderGradient(for title: String) -> LinearGradient {
        let seed: Int = title.unicodeScalars.reduce(0) { (acc: Int, scalar: Unicode.Scalar) -> Int in
            (acc &* 31 &+ Int(scalar.value)) % 360
        }
        let hue = Double(seed) / 360.0
        let hue2 = (hue + 0.12).truncatingRemainder(dividingBy: 1.0)
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.55, brightness: 0.55),
                Color(hue: hue2, saturation: 0.70, brightness: 0.28)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static func initials(for title: String) -> String {
        let words = title.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0) }.joined()
        return letters.uppercased()
    }
}

/// Typography helpers.
enum AppFont {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let sectionTitle = Font.system(.title3, design: .rounded).weight(.bold)
    static let caption = Font.system(.caption, design: .rounded).weight(.semibold)
}

/// Full-screen dark background with a soft accent glow at the top.
struct AppBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            RadialGradient(
                colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.0)],
                center: .top, startRadius: 0, endRadius: 420
            )
            .frame(height: 460)
        }
        .ignoresSafeArea()
    }
}

enum Haptics {
    @MainActor static func impact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum Format {
    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "gerade eben" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func remaining(_ seconds: Double) -> String {
        if seconds <= 0 { return "" }
        let minutes = Int((seconds / 60).rounded(.up))
        return "noch \(max(minutes, 1)) Min."
    }
}

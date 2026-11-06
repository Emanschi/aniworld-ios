import SwiftUI
import UIKit
import WidgetKit

/// Farben und Hilfen der Widgets (Kopie der relevanten Werte aus dem App-Theme,
/// weil die Extension keinen App-Code importieren kann).
enum WidgetTheme {
    static let accent = Color(red: 0.62, green: 0.36, blue: 1.0)
    static let accentPink = Color(red: 0.96, green: 0.32, blue: 0.62)
    static let background = Color(red: 0.045, green: 0.04, blue: 0.075)
    static let surface = Color(red: 0.10, green: 0.09, blue: 0.15)
    static let surfaceHigh = Color(red: 0.16, green: 0.14, blue: 0.23)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.40)
    static let success = Color(red: 0.35, green: 0.85, blue: 0.60)
    static let flame = Color(red: 1.0, green: 0.55, blue: 0.20)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentPink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var flameGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.25), flame, accentPink],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Dunkler Widget-Hintergrund mit leichtem Farbschimmer.
    static var backgroundView: some View {
        ZStack {
            background
            RadialGradient(colors: [accent.opacity(0.28), Color.clear],
                           center: .topTrailing, startRadius: 0, endRadius: 220)
        }
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Hinweis, wenn noch keine Daten von der App geschrieben wurden.
struct WidgetHintView: View {
    var text: String = "Öffne AniWorld, um das Widget zu füllen"
    var systemImage: String = "sparkles.tv"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(WidgetTheme.accentGradient)
            Text(text)
                .font(WidgetTheme.font(13))
                .foregroundStyle(WidgetTheme.textSecondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum WidgetFormat {
    /// "3 Std. 20 Min.", "45 Min.", "0 Min."
    static func duration(_ seconds: Double) -> String {
        let totalMinutes = Int((max(0, seconds) / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours) Std. \(minutes) Min." }
        return "\(minutes) Min."
    }

    /// "noch 12 Min."; leer, wenn nichts mehr übrig ist.
    static func remaining(_ seconds: Double) -> String {
        if seconds <= 0 { return "" }
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if minutes >= 60 { return "noch \(minutes / 60) Std. \(minutes % 60) Min." }
        return "noch \(minutes) Min."
    }

    static func daysText(_ n: Int) -> String { n == 1 ? "1 Tag" : "\(n) Tage" }

    static func initials(_ title: String) -> String {
        let words = title.split(separator: " ")
        var result = ""
        for word in words.prefix(2) {
            if let first = word.first { result += String(first).uppercased() }
        }
        return result.isEmpty ? "?" : result
    }

    static let weekdayInitials = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    /// Mo = 0 ... So = 6
    static func weekdayIndex(of date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}

/// Cover aus dem App-Group-Ordner oder Farbverlauf mit Initialen als Ersatz.
struct WidgetCoverView: View {
    let title: String
    let fileName: String?

    private var image: UIImage? {
        guard let fileName, let dir = WidgetShared.coversDirectory else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(fileName).path)
    }

    private var hue: Double {
        var sum = 0
        for scalar in title.unicodeScalars {
            sum = (sum &* 31 &+ Int(scalar.value)) % 997
        }
        return Double(sum % 100) / 100.0
    }

    var body: some View {
        if let image {
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(hue: hue, saturation: 0.55, brightness: 0.55),
                             Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.70, brightness: 0.28)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(WidgetFormat.initials(title))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .minimumScaleFactor(0.5)
            }
        }
    }
}

/// "Nächste Folge" mit kleinem Symbol (statt Fortschritt / Restzeit).
struct WidgetNextEpisodeLabel: View {
    var size: CGFloat = 11
    var color: Color = WidgetTheme.textSecondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "forward.end.fill")
                .font(.system(size: size - 2, weight: .bold))
            Text("Nächste Folge")
                .font(WidgetTheme.font(size))
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct WidgetProgressBar: View {
    let progress: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(WidgetTheme.accentGradient)
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

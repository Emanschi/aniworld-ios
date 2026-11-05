import Foundation
import AniworldKit

/// German formatting helpers for the statistics screens.
enum StatsFormat {
    /// "3 Std 20 Min", "45 Min", "< 1 Min".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return seconds > 0 ? "< 1 Min" : "0 Min" }
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m) Min" }
        if m == 0 { return "\(h) Std" }
        return "\(h) Std \(m) Min"
    }

    static func hoursMinutes(_ seconds: Double) -> (hours: Int, minutes: Int) {
        let minutes = Int((seconds / 60).rounded())
        return (minutes / 60, minutes % 60)
    }

    /// "42 %" for a 0...1 fraction.
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }

    /// "+12 %" / "−8 %".
    static func signedPercent(_ fraction: Double) -> String {
        let value = Int((fraction * 100).rounded())
        if value > 0 { return "+\(value) %" }
        if value < 0 { return "−\(abs(value)) %" }
        return "±0 %"
    }

    /// One decimal, German comma ("2,5").
    static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func count(_ n: Int, singular: String, plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }

    /// "Dein Oktober-Rückblick" for months, "Dein 2026" otherwise.
    static func recapTitle(_ period: StatsPeriod) -> String {
        if let name = period.monthName { return "Dein \(name)-Rückblick" }
        return "Dein Rückblick \(period.title)"
    }
}

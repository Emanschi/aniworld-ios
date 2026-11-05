import SwiftUI
import AniworldKit

/// Duolingo-style daily streak: a day counts once an episode was watched completely.
struct StreakCard: View {
    let streak: WatchStreak

    @State private var bounce = 0

    private static let flameGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.78, blue: 0.20), Color(red: 1.0, green: 0.42, blue: 0.10),
                 Color(red: 0.92, green: 0.20, blue: 0.18)],
        startPoint: .top, endPoint: .bottom)

    private var isLit: Bool { streak.current > 0 }

    private var headline: String {
        switch streak.current {
        case 0: return "Kein Streak"
        case 1: return "1 Tag"
        default: return "\(streak.current) Tage"
        }
    }

    private var message: String {
        if streak.todayDone {
            return "Heute geschafft! Schau morgen wieder eine ganze Folge, um deinen Streak zu halten."
        }
        if streak.atRisk {
            return "Dein Streak ist in Gefahr: Schau heute noch eine ganze Folge."
        }
        return "Schau eine ganze Folge, um einen neuen Streak zu starten."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(isLit ? AnyShapeStyle(Self.flameGradient) : AnyShapeStyle(Theme.textTertiary))
                    .symbolEffect(.bounce, value: bounce)
                    .shadow(color: isLit ? Color.orange.opacity(0.55) : .clear, radius: 14)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(AppFont.display(28))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(streak.atRisk ? Color.orange : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 0) {
                ForEach(streak.lastSevenDays, id: \.date) { (day: WatchStreak.StreakDay) in
                    dayView(day)
                        .frame(maxWidth: .infinity)
                }
            }
            if streak.longest > 0 {
                Label("Längster Streak: \(streak.longest) \(streak.longest == 1 ? "Tag" : "Tage")",
                      systemImage: "trophy.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(isLit ? Color.orange.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streak: \(headline). \(message)")
        .onAppear { if isLit { bounce += 1 } }
    }

    private func dayView(_ day: WatchStreak.StreakDay) -> some View {
        let isToday: Bool = Calendar.current.isDateInToday(day.date)
        return VStack(spacing: 6) {
            Text(Self.weekdayLetter(day.date))
                .font(.caption2.weight(.bold))
                .foregroundStyle(isToday ? Color.white : Theme.textTertiary)
            ZStack {
                Circle()
                    .fill(day.done ? Color.orange.opacity(0.18) : Theme.surfaceHigh)
                    .frame(width: 34, height: 34)
                if day.done {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Self.flameGradient)
                } else if isToday {
                    Circle()
                        .strokeBorder(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 34, height: 34)
                }
            }
        }
    }

    private static func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEEEE"
        return formatter.string(from: date)
    }
}

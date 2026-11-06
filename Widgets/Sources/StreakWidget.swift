import SwiftUI
import WidgetKit

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.Kind.streak, provider: SnapshotProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Deine Tage am Stück")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StreakWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var streak: WidgetSnapshot.Streak? { entry.snapshot?.streak }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                    Color.clear
                default:
                    WidgetTheme.backgroundView
                }
            }
            .widgetURL(WidgetShared.homeURL)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            if let streak { medium(streak) } else { WidgetHintView(text: "Öffne AniWorld, um das Widget zu füllen", systemImage: "flame.fill") }
        default:
            if let streak { small(streak) } else { WidgetHintView(text: "Öffne AniWorld, um das Widget zu füllen", systemImage: "flame.fill") }
        }
    }

    // MARK: Home screen

    private func statusText(_ s: WidgetSnapshot.Streak) -> (String, Color, String?) {
        if s.todayDone { return ("Heute geschafft", WidgetTheme.success, "checkmark.circle.fill") }
        if s.atRisk { return ("Heute noch eine Folge schauen!", WidgetTheme.accentPink, "exclamationmark.triangle.fill") }
        return ("Starte deine Serie", WidgetTheme.textSecondary, nil)
    }

    private func small(_ s: WidgetSnapshot.Streak) -> some View {
        let status = statusText(s)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(s.current > 0 ? WidgetTheme.flameGradient : LinearGradient(colors: [WidgetTheme.textTertiary], startPoint: .top, endPoint: .bottom))
                Spacer(minLength: 0)
                if s.todayDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WidgetTheme.success)
                }
            }
            Spacer(minLength: 0)
            Text("\(s.current)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(s.current == 1 ? "Tag in Folge" : "Tage in Folge")
                .font(WidgetTheme.font(12))
                .foregroundStyle(WidgetTheme.textSecondary)
            Text(status.0)
                .font(WidgetTheme.font(10))
                .foregroundStyle(status.1)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ s: WidgetSnapshot.Streak) -> some View {
        let status = statusText(s)
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(s.current > 0 ? WidgetTheme.flameGradient : LinearGradient(colors: [WidgetTheme.textTertiary], startPoint: .top, endPoint: .bottom))
                Text("\(s.current)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(s.current == 1 ? "Tag in Folge" : "Tage in Folge")
                    .font(WidgetTheme.font(12))
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
            .frame(minWidth: 90, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    if let icon = status.2 {
                        Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                    }
                    Text(status.0)
                        .font(WidgetTheme.font(12))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(status.1)

                weekDots(s)

                Text("Rekord: \(WidgetFormat.daysText(s.longest))")
                    .font(WidgetTheme.font(11))
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func weekDots(_ s: WidgetSnapshot.Streak) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(s.lastSevenDays.enumerated()), id: \.offset) { index, day in
                let isToday = index == s.lastSevenDays.count - 1
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(day.done ? AnyShapeStyle(WidgetTheme.flameGradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                            .frame(width: 20, height: 20)
                        if day.done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .overlay(
                        Circle().stroke(isToday ? WidgetTheme.accent : Color.clear, lineWidth: 1.5).padding(-2)
                    )
                    Text(WidgetFormat.weekdayInitials[WidgetFormat.weekdayIndex(of: day.date)])
                        .font(WidgetTheme.font(9))
                        .foregroundStyle(isToday ? Color.white : WidgetTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Lock screen

    private var inline: some View {
        let s = streak
        let count = s?.current ?? 0
        return Label(s == nil ? "AniWorld öffnen" : "\(WidgetFormat.daysText(count)) in Folge", systemImage: "flame.fill")
    }

    private var circular: some View {
        let s = streak
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: (s?.todayDone ?? false) ? "checkmark" : "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .widgetAccentable()
                Text("\(s?.current ?? 0)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }

    private var rectangular: some View {
        let s = streak
        return HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 26, weight: .bold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                if let s {
                    Text("\(s.current) \(s.current == 1 ? "Tag" : "Tage") in Folge")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(s.todayDone ? "Heute geschafft" : (s.atRisk ? "Heute noch eine Folge schauen!" : "Starte deine Serie"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("Öffne AniWorld")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

import SwiftUI
import WidgetKit

struct StatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.Kind.stats, provider: SnapshotProvider()) { entry in
            StatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Statistik")
        .description("Deine Woche in Zahlen")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StatsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) { WidgetTheme.backgroundView }
            .widgetURL(WidgetShared.statsURL)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemMedium: medium(snapshot)
            case .systemLarge: large(snapshot)
            default: small(snapshot)
            }
        } else {
            WidgetHintView(text: "Öffne AniWorld, um das Widget zu füllen", systemImage: "chart.bar.fill")
        }
    }

    // MARK: Pieces

    private func header(_ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WidgetTheme.accentGradient)
            Text(title)
                .font(WidgetTheme.font(12))
                .foregroundStyle(WidgetTheme.textSecondary)
        }
    }

    private func metric(_ value: String, _ label: String, size: CGFloat = 20) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(WidgetTheme.font(11))
                .foregroundStyle(WidgetTheme.textSecondary)
                .lineLimit(1)
        }
    }

    /// Balkendiagramm Mo-So aus einfachen Capsules.
    private func barChart(_ values: [Double], height: CGFloat, highlightToday: Bool) -> some View {
        let padded = values + Array(repeating: 0, count: max(0, 7 - values.count))
        let maxValue = max(padded.prefix(7).max() ?? 0, 1)
        let todayIndex = WidgetFormat.weekdayIndex(of: entry.date)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let isToday = highlightToday && i == todayIndex
                let ratio = CGFloat(padded[i] / maxValue)
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(padded[i] > 0
                              ? AnyShapeStyle(WidgetTheme.accentGradient)
                              : AnyShapeStyle(Color.white.opacity(0.12)))
                        .frame(height: max(5, ratio * (height - 16)))
                        .opacity(padded[i] > 0 && highlightToday && !isToday ? 0.75 : 1)
                    Text(WidgetFormat.weekdayInitials[i])
                        .font(WidgetTheme.font(9))
                        .foregroundStyle(isToday ? Color.white : WidgetTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
            }
        }
        .frame(height: height)
    }

    // MARK: Small

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Diese Woche")
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(WidgetFormat.duration(s.week.totalSeconds))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Sehzeit")
                    .font(WidgetTheme.font(11))
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
            metric("\(s.week.completedEpisodes)", s.week.completedEpisodes == 1 ? "Folge geschaut" : "Folgen geschaut")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private func medium(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                header("Diese Woche")
                Spacer()
                Text(WidgetFormat.duration(s.week.totalSeconds))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
            }
            barChart(s.week.weekdaySeconds, height: 62, highlightToday: true)
            HStack(alignment: .top, spacing: 14) {
                metric("\(s.week.completedEpisodes)", "Folgen", size: 16)
                metric("\(s.week.seriesCount)", "Serien", size: 16)
                if let top = s.week.topSeriesTitle {
                    metric(top, "Top-Serie", size: 16)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Large

    private func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    header("Diese Woche")
                    Spacer()
                    Text(WidgetFormat.duration(s.week.totalSeconds))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                barChart(s.week.weekdaySeconds, height: 78, highlightToday: true)
                HStack(alignment: .top, spacing: 14) {
                    metric("\(s.week.completedEpisodes)", "Folgen", size: 16)
                    metric("\(s.week.seriesCount)", "Serien", size: 16)
                    if let top = s.week.topSeriesTitle {
                        metric(top, "Top-Serie", size: 16)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WidgetTheme.surface))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WidgetTheme.accentGradient)
                        Text("Dieser Monat")
                            .font(WidgetTheme.font(12))
                            .foregroundStyle(WidgetTheme.textSecondary)
                    }
                    Spacer()
                    Text(WidgetFormat.duration(s.month.totalSeconds))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                barChart(s.month.weekdaySeconds, height: 66, highlightToday: false)
                HStack(alignment: .top, spacing: 14) {
                    metric("\(s.month.completedEpisodes)", "Folgen", size: 16)
                    metric("\(s.month.seriesCount)", "Serien", size: 16)
                    if let top = s.month.topSeriesTitle {
                        metric(top, "Top-Serie", size: 16)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WidgetTheme.surface))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

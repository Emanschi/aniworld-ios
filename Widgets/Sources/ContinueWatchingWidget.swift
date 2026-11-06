import SwiftUI
import WidgetKit

struct ContinueWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.Kind.continueWatching, provider: SnapshotProvider()) { entry in
            ContinueWatchingWidgetView(entry: entry)
        }
        .configurationDisplayName("Weiterschauen")
        .description("Mach da weiter, wo du aufgehört hast")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct ContinueWatchingWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var items: [WidgetSnapshot.ContinueItem] { entry.snapshot?.continueWatching ?? [] }

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var background: some View {
        if family == .systemSmall, let top = items.first {
            ZStack {
                WidgetCoverView(title: top.title, fileName: top.coverFileName)
                LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.85)],
                               startPoint: .center, endPoint: .bottom)
            }
        } else {
            WidgetTheme.backgroundView
        }
    }

    @ViewBuilder
    private var content: some View {
        if entry.snapshot == nil {
            WidgetHintView(text: "Öffne AniWorld, um das Widget zu füllen", systemImage: "play.rectangle.fill")
                .padding(16)
        } else if items.isEmpty {
            WidgetHintView(text: "Noch nichts angefangen", systemImage: "play.rectangle.fill")
                .padding(16)
        } else {
            switch family {
            case .systemMedium: medium
            case .systemLarge: large
            default: small
            }
        }
    }

    // MARK: Small

    private var small: some View {
        let item = items[0]
        return VStack(alignment: .leading, spacing: 3) {
            Spacer(minLength: 0)
            Text(item.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(2)
            Text(item.episodeLabel)
                .font(WidgetTheme.font(12))
                .foregroundStyle(Color.white.opacity(0.8))
            WidgetProgressBar(progress: item.progress, height: 4)
                .padding(.vertical, 2)
            Text(WidgetFormat.remaining(item.remainingSeconds))
                .font(WidgetTheme.font(10))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(WidgetShared.seriesURL(slug: item.slug))
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(items.prefix(3))) { item in
                Link(destination: WidgetShared.seriesURL(slug: item.slug)) {
                    VStack(alignment: .leading, spacing: 5) {
                        ZStack(alignment: .bottom) {
                            WidgetCoverView(title: item.title, fileName: item.coverFileName)
                            WidgetProgressBar(progress: item.progress, height: 3)
                                .padding(.horizontal, 6)
                                .padding(.bottom, 6)
                        }
                        .frame(height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(item.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Text("\(item.episodeLabel) · \(WidgetFormat.remaining(item.remainingSeconds))")
                            .font(WidgetTheme.font(10))
                            .foregroundStyle(WidgetTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Large

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weiterschauen")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
            ForEach(Array(items.prefix(4))) { item in
                Link(destination: WidgetShared.seriesURL(slug: item.slug)) {
                    HStack(spacing: 12) {
                        WidgetCoverView(title: item.title, fileName: item.coverFileName)
                            .frame(width: 52, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                            Text(item.episodeLabel)
                                .font(WidgetTheme.font(12))
                                .foregroundStyle(WidgetTheme.textSecondary)
                            WidgetProgressBar(progress: item.progress, height: 4)
                            Text(WidgetFormat.remaining(item.remainingSeconds))
                                .font(WidgetTheme.font(11))
                                .foregroundStyle(WidgetTheme.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

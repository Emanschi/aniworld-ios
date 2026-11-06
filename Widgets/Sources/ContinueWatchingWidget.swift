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

    /// "S1 · F5" bzw. "nach S1 · F5", wenn die nächste Folge ansteht.
    private func episodeText(_ item: WidgetSnapshot.ContinueItem) -> String {
        item.isNextEpisode ? "nach \(item.episodeLabel)" : item.episodeLabel
    }

    @ViewBuilder
    private func remainingText(_ item: WidgetSnapshot.ContinueItem, size: CGFloat, color: Color) -> some View {
        let text = WidgetFormat.remaining(item.remainingSeconds)
        if !text.isEmpty {
            Text(text)
                .font(WidgetTheme.font(size))
                .foregroundStyle(color)
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
            Text(episodeText(item))
                .font(WidgetTheme.font(12))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
            if item.isNextEpisode {
                WidgetNextEpisodeLabel(size: 11, color: Color.white.opacity(0.85))
                    .padding(.vertical, 2)
            } else {
                WidgetProgressBar(progress: item.progress, height: 4)
                    .padding(.vertical, 2)
                remainingText(item, size: 10, color: Color.white.opacity(0.7))
            }
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
                            if !item.isNextEpisode {
                                WidgetProgressBar(progress: item.progress, height: 3)
                                    .padding(.horizontal, 6)
                                    .padding(.bottom, 6)
                            }
                        }
                        .frame(height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(item.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        if item.isNextEpisode {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(episodeText(item))
                                    .font(WidgetTheme.font(10))
                                    .foregroundStyle(WidgetTheme.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                WidgetNextEpisodeLabel(size: 10, color: WidgetTheme.accent)
                            }
                        } else {
                            let remaining = WidgetFormat.remaining(item.remainingSeconds)
                            Text(remaining.isEmpty ? item.episodeLabel : "\(item.episodeLabel) · \(remaining)")
                                .font(WidgetTheme.font(10))
                                .foregroundStyle(WidgetTheme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Weiterschauen")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
            ForEach(Array(items.prefix(4))) { item in
                Link(destination: WidgetShared.seriesURL(slug: item.slug)) {
                    HStack(spacing: 10) {
                        WidgetCoverView(title: item.title, fileName: item.coverFileName)
                            .frame(width: 44, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                            Text(episodeText(item))
                                .font(WidgetTheme.font(12))
                                .foregroundStyle(WidgetTheme.textSecondary)
                                .lineLimit(1)
                            if item.isNextEpisode {
                                WidgetNextEpisodeLabel(size: 11, color: WidgetTheme.accent)
                            } else {
                                WidgetProgressBar(progress: item.progress, height: 4)
                                remainingText(item, size: 11, color: WidgetTheme.textTertiary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

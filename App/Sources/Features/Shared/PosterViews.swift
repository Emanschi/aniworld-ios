import SwiftUI
import AniworldKit

/// Portrait cover with title underneath. Pass `width: nil` inside grids.
struct PosterCard: View {
    let series: SeriesSummary
    var width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SeriesCover(series: series)
                .cardShadow()
            Text(series.title)
                .font(AppFont.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }
}

/// Titled horizontal row of poster cards that push `SeriesSummary` destinations.
struct PosterRow: View {
    let title: String
    var subtitle: String?
    let items: [SeriesSummary]
    var cardWidth: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { series in
                        NavigationLink(value: series) {
                            PosterCard(series: series, width: cardWidth)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 4)
            }
        }
    }
}

/// Wide "Weiterschauen" card with progress.
struct ContinueCard: View {
    let entry: WatchEntry
    var width: CGFloat = 260

    var body: some View {
        SeriesCover(series: entry.series, aspect: 16.0 / 9.0)
            .overlay { shade }
            .overlay(alignment: .topTrailing) { playBadge }
            .overlay(alignment: .bottomLeading) { caption }
            .overlay(alignment: .bottom) {
                ProgressBar(value: entry.isFinished ? 1 : entry.fraction, height: 4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .frame(width: width)
            .cardShadow()
    }

    private var shade: some View {
        LinearGradient(
            colors: [.black.opacity(0.0), .black.opacity(0.85)],
            startPoint: .center, endPoint: .bottom
        )
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(.ultraThinMaterial))
            .padding(10)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.series.title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 20)
    }

    private var subtitle: String {
        if entry.isFinished { return "Nächste Folge nach \(entry.episode.code)" }
        let remaining = Format.remaining(entry.remaining)
        return remaining.isEmpty ? entry.episode.code : "\(entry.episode.code) · \(remaining)"
    }
}

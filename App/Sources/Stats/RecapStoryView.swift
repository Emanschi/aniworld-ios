import SwiftUI
import AniworldKit

/// Decides whether the Start tab offers last month's recap (first days of a new month, once per month).
enum RecapPrompt {
    private static func key(_ period: StatsPeriod) -> String { "stats.recapSeen.\(period.id)" }

    @MainActor
    static func candidate(store: WatchStatsStore, now: Date = Date(), calendar: Calendar = .current) -> StatsPeriod? {
        guard calendar.component(.day, from: now) <= 7 else { return nil }
        let previous = StatsPeriod.previousMonth(of: now, calendar: calendar)
        guard !UserDefaults.standard.bool(forKey: key(previous)) else { return nil }
        let stats = store.stats(for: previous, calendar: calendar)
        guard stats.hasData, stats.totalSeconds >= 600 else { return nil }
        return previous
    }

    static func markSeen(_ period: StatsPeriod) {
        UserDefaults.standard.set(true, forKey: key(period))
    }
}

/// Banner on the Start tab: "Dein Oktober-Rückblick ist da".
struct RecapBanner: View {
    let period: StatsPeriod
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dein \(period.monthName ?? period.title)-Rückblick ist da")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Text("Tippe, um zu sehen, was du geschaut hast.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.22)))
            }
            .accessibilityLabel("Schließen")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.accentGradient))
        .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 6)
        .padding(.horizontal, Theme.screenPadding)
    }
}

/// Spotify-Wrapped-like full-screen story for one period. Tap right/left or swipe to move on.
struct RecapStoryView: View {
    let period: StatsPeriod
    let stats: WatchStats
    let onClose: () -> Void

    private enum Page: Hashable {
        case intro, total, topSeries, topFive, genres, rhythm, binge, extras, outro
    }

    @State private var index = 0

    private var pages: [Page] {
        var result: [Page] = [.intro, .total]
        if !stats.topSeries.isEmpty { result.append(.topSeries) }
        if stats.topSeries.count > 1 { result.append(.topFive) }
        if !stats.topGenres.isEmpty { result.append(.genres) }
        if stats.mostActiveWeekday != nil { result.append(.rhythm) }
        if let b = stats.longestBinge, b.episodes >= 2 { result.append(.binge) }
        result.append(.extras)
        result.append(.outro)
        return result
    }

    var body: some View {
        let pages: [Page] = self.pages
        let current: Int = min(index, pages.count - 1)
        GeometryReader { geo in
            ZStack {
                background(for: pages[current]).ignoresSafeArea()
                pageView(pages[current])
                    .id(current)
                    .transition(.opacity)
                    .padding(.horizontal, 28)
                    .padding(.top, 90)
                    .padding(.bottom, 50)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                VStack(spacing: 14) {
                    HStack(spacing: 4) {
                        ForEach(0..<pages.count, id: \.self) { (i: Int) in
                            Capsule()
                                .fill(Color.white.opacity(i <= current ? 0.95 : 0.3))
                                .frame(height: 3)
                        }
                    }
                    HStack {
                        Text(period.title)
                            .font(AppFont.caption)
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.white.opacity(0.2)))
                        }
                        .accessibilityLabel("Schließen")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { (value: SpatialTapGesture.Value) in
                    if value.location.x < geo.size.width / 3 { move(-1, count: pages.count) }
                    else { move(1, count: pages.count) }
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { (value: DragGesture.Value) in
                    if value.translation.width < -40 { move(1, count: pages.count) }
                    else if value.translation.width > 40 { move(-1, count: pages.count) }
                }
            )
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    private func move(_ delta: Int, count: Int) {
        let target = index + delta
        if target >= count {
            onClose()
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) { index = max(target, 0) }
    }

    // MARK: Pages

    private func background(for page: Page) -> some View {
        let colors: [Color]
        switch page {
        case .intro: colors = [Theme.accent, Theme.accentPink]
        case .total: colors = [Color(red: 0.98, green: 0.45, blue: 0.35), Theme.accentPink]
        case .topSeries: colors = [Color(red: 0.20, green: 0.45, blue: 0.95), Theme.accent]
        case .topFive: colors = [Theme.accent, Color(red: 0.10, green: 0.07, blue: 0.30)]
        case .genres: colors = [Color(red: 0.10, green: 0.65, blue: 0.60), Color(red: 0.20, green: 0.35, blue: 0.85)]
        case .rhythm: colors = [Color(red: 0.95, green: 0.60, blue: 0.20), Theme.accentPink]
        case .binge: colors = [Theme.accentPink, Color(red: 0.35, green: 0.10, blue: 0.45)]
        case .extras: colors = [Color(red: 0.30, green: 0.30, blue: 0.90), Theme.accentPink]
        case .outro: colors = [Theme.accentPink, Theme.accent]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        switch page {
        case .intro: introPage
        case .total: totalPage
        case .topSeries: topSeriesPage
        case .topFive: topFivePage
        case .genres: genresPage
        case .rhythm: rhythmPage
        case .binge: bingePage
        case .extras: extrasPage
        case .outro: outroPage
        }
    }

    private func headline(_ text: String) -> some View {
        Text(text)
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(.white.opacity(0.9))
    }

    private func big(_ text: String, size: CGFloat = 52) -> some View {
        Text(text)
            .font(AppFont.display(size))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.5)
            .lineLimit(3)
    }

    private func sub(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
    }

    private var introPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
            big(StatsFormat.recapTitle(period), size: 44)
            sub("Zeit für einen Blick zurück: Das hast du geschaut. Tippe, um weiterzugehen.")
            Spacer()
        }
    }

    private var totalPage: some View {
        let hm = StatsFormat.hoursMinutes(stats.totalSeconds)
        return VStack(alignment: .leading, spacing: 16) {
            Spacer()
            headline("Du hast insgesamt")
            big(hm.hours > 0 ? "\(hm.hours) Std \(hm.minutes) Min" : "\(hm.minutes) Min")
            sub("Anime geschaut – \(StatsFormat.count(stats.episodeCount, singular: "Folge", plural: "Folgen")) aus \(StatsFormat.count(stats.seriesCount, singular: "Serie", plural: "Serien")).")
            if let fun = stats.funComparison { sub(fun) }
            if let change = stats.changeToPrevious {
                sub("Das sind \(StatsFormat.signedPercent(change)) im Vergleich zum Vormonat.")
            }
            Spacer()
        }
    }

    private var topSeriesPage: some View {
        let top: SeriesStat? = stats.topSeries.first
        return VStack(alignment: .leading, spacing: 16) {
            Spacer()
            headline("Deine Nummer 1")
            if let top {
                CoverImage(url: top.coverURL, title: top.title, cornerRadius: 16)
                    .frame(width: 170)
                    .cardShadow()
                big(top.title, size: 34)
                sub("\(StatsFormat.duration(top.seconds)) – \(StatsFormat.percent(top.share)) deiner Sehzeit.")
            }
            Spacer()
        }
    }

    private var topFivePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            headline("Deine Top 5")
            ForEach(Array(stats.topSeries.enumerated()), id: \.offset) { pair in
                HStack(spacing: 12) {
                    Text("\(pair.offset + 1)")
                        .font(AppFont.display(28))
                        .foregroundStyle(.white)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pair.element.title)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(StatsFormat.duration(pair.element.seconds))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            Spacer()
        }
    }

    private var genresPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            headline("Dein Lieblingsgenre")
            if let first = stats.topGenres.first {
                big(first.name)
                sub("\(StatsFormat.percent(first.share)) deiner Sehzeit.")
            }
            ForEach(Array(stats.topGenres.dropFirst().prefix(3).enumerated()), id: \.offset) { pair in
                Text("\(pair.element.name) · \(StatsFormat.percent(pair.element.share))")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
        }
    }

    private var rhythmPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            headline("Dein Rhythmus")
            if let day = stats.mostActiveWeekdayName {
                big(day)
                sub("war dein aktivster Wochentag.")
            }
            if let tod = stats.mostActiveTimeOfDay {
                sub("Meistens schaust du \(tod.title.lowercased()).")
            }
            if stats.longestStreakDays >= 2 {
                sub("Dein längster Streak: \(stats.longestStreakDays) Tage in Folge.")
            }
            Spacer()
        }
    }

    private var bingePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            headline("Dein längster Binge")
            if let binge = stats.longestBinge {
                big("\(binge.episodes) Folgen")
                sub("am Stück – \(StatsFormat.duration(binge.seconds)) ohne lange Pause.")
            }
            Spacer()
        }
    }

    private var extrasPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            headline("Noch mehr Zahlen")
            sub("Durchschnittlich bleibst du \(StatsFormat.duration(stats.averageSessionSeconds)) dran.")
            sub("Du hast \(StatsFormat.percent(stats.completionRate)) deiner Folgen bis zum Ende geschaut.")
            if stats.skippedSeconds >= 60 {
                sub("Intros und Outros überspringen hat dir \(StatsFormat.duration(stats.skippedSeconds)) gespart.")
            }
            if stats.newSeriesCount > 0 {
                sub("\(StatsFormat.count(stats.newSeriesCount, singular: "neue Serie", plural: "neue Serien")) angefangen.")
            }
            Spacer()
        }
    }

    private var outroPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            big("Bis zum nächsten Rückblick!", size: 40)
            sub("Alle Zahlen findest du jederzeit unter „Statistiken“.")
            Button(action: onClose) {
                Text("Fertig")
            }
            .buttonStyle(AccentButtonStyle())
            .padding(.top, 8)
            Spacer()
        }
    }
}

#Preview("Rückblick") {
    let store = WatchStatsStore.preview()
    return RecapStoryView(period: StatsPeriod.month(containing: Date(), calendar: .current),
                          stats: store.stats(for: .all)) {}
}
